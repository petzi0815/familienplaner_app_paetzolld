import { getDb } from "@/server/db/connection";
import { columnNames, textColumns, getColumns } from "@/server/db/introspect";
import { enumConstraints, checkEnums } from "@/server/db/constraints";
import { type Resource, pkOf } from "./registry";
import { expandImages } from "@/server/media/media";
import { reindexRow, removeFromIndex } from "@/server/db/fts";
import { listResponse, ok, created, fail, notFound } from "@/server/http/respond";
import { log } from "@/server/observability/logger";
import type { Auth } from "@/server/auth/auth";

// Mappt SQLite-Fehler auf saubere JSON-Antworten (nie leerer 500).
function dbError(e: unknown, res: Resource): Response {
  const msg = String((e as Error)?.message ?? e);
  if (/CHECK constraint/i.test(msg)) return fail("check_violation", "Ungültiger Wert für ein Feld mit fester Werteliste. Erlaubte Werte via GET /api/v1/" + res.key + "/schema.", 422, { sqlite: msg });
  if (/NOT NULL constraint/i.test(msg)) return fail("not_null", "Ein Pflichtfeld fehlt: " + msg, 422, { sqlite: msg });
  if (/FOREIGN KEY constraint/i.test(msg)) return fail("foreign_key", "Verknüpfter Datensatz existiert nicht (z.B. kind_id/ereignis_id).", 409, { sqlite: msg });
  if (/UNIQUE constraint/i.test(msg)) return fail("unique", "Datensatz existiert bereits (Eindeutigkeit verletzt).", 409, { sqlite: msg });
  log.error("DB-Schreibfehler", { resource: res.key, error: msg });
  return fail("db_error", "Datenbankfehler beim Schreiben.", 500, { sqlite: msg });
}

function enumViolation(res: Resource, valid: Record<string, unknown>): Response | null {
  const v = checkEnums(getDb(), res.table, valid);
  if (!v) return null;
  return fail("invalid_value", `Feld '${v.column}' erlaubt nur: ${v.allowed.join(", ")} (bekam '${String(v.value)}').`, 422, { column: v.column, allowed: v.allowed });
}

const RESERVED = new Set(["limit", "offset", "sort", "order", "search", "q", "dry_run", "view"]);
const CREATED_COLS = ["created_at", "erstellt_am", "erfasst_am", "added_at"];
const UPDATED_COLS = ["updated_at", "aktualisiert_am"];
const nowIso = () => new Date().toISOString();

function logEvent(action: string, res: Resource, entityId: string | number | null, auth: Auth | null, detail?: unknown): void {
  try {
    getDb().prepare("INSERT INTO event_log (actor, action, domain, entity_id, detail) VALUES (?,?,?,?,?)")
      .run(auth?.actor ?? "anon", action, res.key, entityId == null ? null : String(entityId), detail ? JSON.stringify(detail) : null);
  } catch { /* Audit darf nie die Aktion kippen */ }
}

/** GET /api/v1/<domain> — Liste mit Filter/Suche/Sort/Pagination. */
export function listRows(res: Resource, url: URL): Response {
  const db = getDb();
  const colSet = new Set(columnNames(db, res.table));
  const pk = pkOf(res);
  const where: string[] = [];
  const params: unknown[] = [];

  for (const [k, v] of url.searchParams.entries()) {
    if (RESERVED.has(k)) continue;
    if (colSet.has(k)) { where.push(`"${k}" = ?`); params.push(v); }
  }
  const q = url.searchParams.get("search") ?? url.searchParams.get("q");
  if (q) {
    const cols = res.searchable ?? textColumns(db, res.table);
    if (cols.length) {
      where.push("(" + cols.map((c) => `"${c}" LIKE ?`).join(" OR ") + ")");
      for (let i = 0; i < cols.length; i++) params.push(`%${q}%`);
    }
  }
  const whereSql = where.length ? " WHERE " + where.join(" AND ") : "";
  const total = (db.prepare(`SELECT COUNT(*) AS c FROM "${res.table}"${whereSql}`).get(...params) as { c: number }).c;

  let orderSql = res.sort ? ` ORDER BY ${res.sort}` : ` ORDER BY "${pk}" DESC`;
  const sortParam = url.searchParams.get("sort");
  if (sortParam) {
    const [c, dir] = sortParam.split(":");
    if (colSet.has(c)) orderSql = ` ORDER BY "${c}" ${/desc/i.test(dir ?? "") ? "DESC" : "ASC"}`;
  }
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 100) || 100, 1), 1000);
  const offset = Math.max(Number(url.searchParams.get("offset") ?? 0) || 0, 0);

  const rows = db.prepare(`SELECT * FROM "${res.table}"${whereSql}${orderSql} LIMIT ? OFFSET ?`).all(...params, limit, offset) as Record<string, unknown>[];
  for (const r of rows) expandImages(r, res.image);
  return listResponse(rows, total, { limit, offset });
}

export function getRow(res: Resource, id: string): Response {
  const db = getDb();
  const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pkOf(res)}" = ?`).get(id) as Record<string, unknown> | undefined;
  if (!row) return notFound(res.label);
  expandImages(row, res.image);
  return ok(row);
}

function pickValidColumns(res: Resource, body: Record<string, unknown>): { valid: Record<string, unknown>; unknown: string[] } {
  const db = getDb();
  const cols = new Set(columnNames(db, res.table));
  const valid: Record<string, unknown> = {};
  const unknownKeys: string[] = [];
  for (const [k, v] of Object.entries(body)) {
    if (k === "dry_run") continue;
    if (cols.has(k)) valid[k] = v;
    else unknownKeys.push(k);
  }
  return { valid, unknown: unknownKeys };
}

export function createRow(res: Resource, body: Record<string, unknown>, auth: Auth | null, dryRun: boolean): Response {
  if (res.readonly) return fail("readonly", `${res.label} ist schreibgeschützt.`, 403);
  const db = getDb();
  const pk = pkOf(res);
  const cols = new Set(columnNames(db, res.table));
  const { valid, unknown } = pickValidColumns(res, body);
  if (unknown.length) return fail("unknown_columns", `Unbekannte Felder: ${unknown.join(", ")}`, 400, { allowed: [...cols] });
  // Auto-Zeitstempel
  const now = nowIso();
  for (const c of CREATED_COLS) if (cols.has(c) && valid[c] == null) valid[c] = now;
  for (const c of UPDATED_COLS) if (cols.has(c) && valid[c] == null) valid[c] = now;
  const keys = Object.keys(valid);
  if (!keys.length) return fail("empty", "Keine gültigen Felder angegeben.", 400);

  const enumErr = enumViolation(res, valid);
  if (enumErr) return enumErr;

  if (dryRun) return ok({ dry_run: true, would: { action: "create", resource: res.key, data: valid } });

  try {
    const stmt = db.prepare(`INSERT INTO "${res.table}" (${keys.map((k) => `"${k}"`).join(",")}) VALUES (${keys.map(() => "?").join(",")})`);
    const info = stmt.run(...keys.map((k) => valid[k]));
    const newId = valid[pk] ?? info.lastInsertRowid;
    logEvent("create", res, newId as number, auth, valid);
    reindexRow(db, res, newId as number);
    const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pk}" = ?`).get(newId) as Record<string, unknown>;
    if (row) expandImages(row, res.image);
    return created(row ?? { [pk]: newId });
  } catch (e) {
    return dbError(e, res);
  }
}

export function updateRow(res: Resource, id: string, body: Record<string, unknown>, auth: Auth | null, dryRun: boolean): Response {
  if (res.readonly) return fail("readonly", `${res.label} ist schreibgeschützt.`, 403);
  const db = getDb();
  const pk = pkOf(res);
  const existing = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pk}" = ?`).get(id);
  if (!existing) return notFound(res.label);
  const cols = new Set(columnNames(db, res.table));
  const { valid, unknown } = pickValidColumns(res, body);
  if (unknown.length) return fail("unknown_columns", `Unbekannte Felder: ${unknown.join(", ")}`, 400, { allowed: [...cols] });
  delete valid[pk];
  const now = nowIso();
  for (const c of UPDATED_COLS) if (cols.has(c)) valid[c] = now;
  const keys = Object.keys(valid);
  if (!keys.length) return fail("empty", "Keine gültigen Felder zum Aktualisieren.", 400);

  const enumErr = enumViolation(res, valid);
  if (enumErr) return enumErr;

  if (dryRun) return ok({ dry_run: true, would: { action: "update", resource: res.key, id, data: valid } });

  try {
    db.prepare(`UPDATE "${res.table}" SET ${keys.map((k) => `"${k}" = ?`).join(", ")} WHERE "${pk}" = ?`).run(...keys.map((k) => valid[k]), id);
    logEvent("update", res, id, auth, valid);
    reindexRow(db, res, id);
    const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pk}" = ?`).get(id) as Record<string, unknown>;
    expandImages(row, res.image);
    return ok(row);
  } catch (e) {
    return dbError(e, res);
  }
}

export function deleteRow(res: Resource, id: string, auth: Auth | null, dryRun: boolean): Response {
  if (res.readonly) return fail("readonly", `${res.label} ist schreibgeschützt.`, 403);
  const db = getDb();
  const pk = pkOf(res);
  const existing = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pk}" = ?`).get(id);
  if (!existing) return notFound(res.label);
  if (dryRun) return ok({ dry_run: true, would: { action: "delete", resource: res.key, id } });
  try {
    db.prepare(`DELETE FROM "${res.table}" WHERE "${pk}" = ?`).run(id);
    logEvent("delete", res, id, auth, null);
    removeFromIndex(db, res.key, id);
    return ok({ deleted: true, id });
  } catch (e) {
    return dbError(e, res);
  }
}

/** JSON-Schema-artige Beschreibung der Ressource (Spalten + Typen). */
export function schemaOf(res: Resource): Response {
  const db = getDb();
  const enums = enumConstraints(db, res.table);
  const cols = getColumns(db, res.table).map((c) => ({
    name: c.name,
    type: c.type || "TEXT",
    required: !!c.notnull && !c.pk && c.dflt == null,
    primary_key: !!c.pk,
    ...(enums[c.name] ? { allowed: enums[c.name] } : {}),
  }));
  return ok({ resource: res.key, table: res.table, domain: res.domain, label: res.label, primary_key: pkOf(res), image: res.image ?? null, readonly: !!res.readonly, columns: cols });
}
