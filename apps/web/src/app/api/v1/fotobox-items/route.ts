import { getDb } from "@/server/db/connection";
import { getAuth, hasRole } from "@/server/auth/auth";
import { ok, created, fail, listResponse, unauthorized, forbidden } from "@/server/http/respond";
import { validateItemValues, targetResourceForDomain } from "@/server/fotobox/labels";
import { genId, serializeItem, getItemRow, saveMedia, logProc } from "@/server/fotobox/store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// GET /api/v1/fotobox-items — Queue lesen (Filter: status, domain, intent, target_resource,
// uploaded_person, from/to über created_at; search; sort; limit/offset). Liefert das nested Shape.
export async function GET(req: Request): Promise<Response> {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const db = getDb();
  const url = new URL(req.url);
  const where: string[] = [];
  const params: unknown[] = [];
  for (const col of ["status", "domain", "intent", "target_resource", "uploaded_person", "source", "review_required"]) {
    const v = url.searchParams.get(col);
    if (v != null && v !== "") { where.push(`"${col}" = ?`); params.push(v); }
  }
  const from = url.searchParams.get("from"); if (from) { where.push("created_at >= ?"); params.push(from); }
  const to = url.searchParams.get("to"); if (to) { where.push("created_at <= ?"); params.push(to); }
  const q = url.searchParams.get("search") ?? url.searchParams.get("q");
  if (q) {
    where.push("(status LIKE ? OR domain LIKE ? OR intent LIKE ? OR target_resource LIKE ? OR result_summary LIKE ? OR uploaded_person LIKE ?)");
    for (let i = 0; i < 6; i++) params.push(`%${q}%`);
  }
  const whereSql = where.length ? " WHERE " + where.join(" AND ") : "";
  const total = (db.prepare(`SELECT COUNT(*) AS c FROM fotobox_items${whereSql}`).get(...params) as { c: number }).c;

  let orderSql = " ORDER BY created_at DESC";
  const sortParam = url.searchParams.get("sort");
  if (sortParam) {
    const [c, dir] = sortParam.split(":");
    if (/^[a-z0-9_]+$/i.test(c)) orderSql = ` ORDER BY "${c}" ${/desc/i.test(dir ?? "") ? "DESC" : "ASC"}`;
  }
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? 50) || 50, 1), 500);
  const offset = Math.max(Number(url.searchParams.get("offset") ?? 0) || 0, 0);
  const rows = db.prepare(`SELECT * FROM fotobox_items${whereSql}${orderSql} LIMIT ? OFFSET ?`).all(...params, limit, offset) as Record<string, unknown>[];
  return listResponse(rows.map((r) => serializeItem(db, r)), total, { limit, offset });
}

type Obj = Record<string, unknown>;
const s = (v: unknown): string | null => (v == null || v === "" ? null : String(v));
const asObj = (v: unknown): Obj => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : {});

// POST /api/v1/fotobox-items (?dry_run=1) — neues Item anlegen (idempotent via idempotency_key).
// Akzeptiert das nested Shape (uploaded_by/routing/review/…) ODER flache Spalten. Optional inline media[].
export async function POST(req: Request): Promise<Response> {
  const auth = getAuth(req);
  if (!hasRole(auth, "agent")) return auth ? forbidden() : unauthorized();
  let body: Obj;
  try { body = (await req.json()) as Obj; } catch { return fail("bad_json", "Ungültiger JSON-Body.", 400); }

  const db = getDb();
  const idem = s(body.idempotency_key);
  if (idem) {
    const existing = db.prepare("SELECT * FROM fotobox_items WHERE idempotency_key=?").get(idem) as Obj | undefined;
    if (existing) return ok({ ...serializeItem(db, existing), idempotent_reuse: true });
  }

  const up = asObj(body.uploaded_by);
  const rt = asObj(body.routing);
  const rv = asObj(body.review);
  const domain = s(rt.domain ?? body.domain);
  let targetResource = s(rt.target_resource ?? body.target_resource);
  if (!targetResource && domain) targetResource = targetResourceForDomain(db, domain);

  const cols: Obj = {
    id: genId("fbx"),
    idempotency_key: idem,
    source: s(body.source) ?? "app_fotobox",
    status: s(body.status) ?? "pending",
    uploaded_person: s(up.person ?? body.uploaded_person),
    uploaded_display_name: s(up.display_name ?? body.uploaded_display_name),
    uploaded_device_id: s(up.device_id ?? body.uploaded_device_id),
    uploaded_telegram_id: s(up.telegram_id ?? body.uploaded_telegram_id),
    domain,
    intent: s(rt.intent ?? body.intent),
    target_resource: targetResource,
    target_id: s(rt.target_id ?? body.target_id),
    confidence: rt.confidence ?? body.confidence ?? null,
    preclassified_by: s(rt.preclassified_by ?? body.preclassified_by),
    analysis_hint: body.analysis_hint != null ? JSON.stringify(body.analysis_hint) : null,
    labels: body.labels != null ? JSON.stringify(body.labels) : null,
    telegram_equivalent: body.telegram_equivalent != null ? JSON.stringify(body.telegram_equivalent) : null,
    review_required: (rv.required ?? body.review_required) ? 1 : 0,
    review_reason: s(rv.reason ?? body.review_reason),
    review_question: s(rv.question ?? body.review_question),
  };

  const violation = validateItemValues(db, cols);
  if (violation) return fail("invalid_value", `Feld '${violation.field}' erlaubt nur (aktive Labels): ${violation.allowed.join(", ")}. Neue Werte via POST /api/v1/fotobox-labels.`, 422, violation);

  const dryRun = new URL(req.url).searchParams.get("dry_run") === "1" || body.dry_run === true;
  if (dryRun) return ok({ dry_run: true, would: { action: "create", resource: "fotobox-items", data: cols } });

  const keys = Object.keys(cols);
  try {
    db.prepare(`INSERT INTO fotobox_items (${keys.map((k) => `"${k}"`).join(",")}) VALUES (${keys.map(() => "?").join(",")})`)
      .run(...keys.map((k) => cols[k] as never));
  } catch (e) {
    const msg = String((e as Error)?.message ?? e);
    if (/UNIQUE/i.test(msg)) return fail("unique", "idempotency_key existiert bereits.", 409, { sqlite: msg });
    return fail("db_error", "Fehler beim Anlegen.", 500, { sqlite: msg });
  }
  const itemId = String(cols.id);
  logProc(db, itemId, auth?.actor ?? null, "created", { source: cols.source, domain, status: cols.status });

  // Inline-Medien (optional): media:[{data_base64|data_url, mime?, filename?, order?, width?, height?, created_at_original?}]
  const inlineMedia = Array.isArray(body.media) ? (body.media as Obj[]) : [];
  const savedMedia: Obj[] = [];
  for (const m of inlineMedia) {
    let data = String(m.data_base64 ?? m.data_url ?? m.data ?? "");
    if (!data) continue;
    let mime = s(m.mime) ?? undefined;
    const dm = /^data:([^;]+);base64,([\s\S]*)$/.exec(data);
    if (dm) { mime = mime ?? dm[1]; data = dm[2]; }
    let buf: Buffer;
    try { buf = Buffer.from(data, "base64"); } catch { continue; }
    if (!buf.length) continue;
    savedMedia.push(saveMedia(db, itemId, {
      buf, mime, filename: s(m.filename) ?? undefined,
      order: m.order != null ? Number(m.order) : undefined,
      width: m.width != null ? Number(m.width) : null,
      height: m.height != null ? Number(m.height) : null,
      createdAtOriginal: s(m.created_at_original),
    }));
  }
  if (savedMedia.length) logProc(db, itemId, auth?.actor ?? null, "media_added", { count: savedMedia.length });

  const row = getItemRow(db, itemId)!;
  return created(serializeItem(db, row));
}
