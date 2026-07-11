import type BetterSqlite3 from "better-sqlite3";
import { RESOURCES, pkOf, type Resource } from "@/server/domains/registry";
import { textColumns } from "./introspect";
import { log } from "@/server/observability/logger";

const TITLE = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "problem", "item"];
function titleOf(row: Record<string, unknown>): string { for (const k of TITLE) if (row[k]) return String(row[k]); return ""; }
function contentOf(db: BetterSqlite3.Database, res: Resource, row: Record<string, unknown>): string {
  const cols = res.searchable ?? textColumns(db, res.table);
  return cols.map((c) => row[c]).filter(Boolean).map(String).join(" ").slice(0, 4000);
}

export function ftsAvailable(db: BetterSqlite3.Database): boolean {
  try { db.prepare("SELECT 1 FROM fts_index LIMIT 1").get(); return true; } catch { return false; }
}

/** Aktualisiert den Index für genau eine Zeile (nach create/update). */
export function reindexRow(db: BetterSqlite3.Database, res: Resource, id: string | number): void {
  if (!ftsAvailable(db)) return;
  try {
    db.prepare("DELETE FROM fts_index WHERE resource=? AND entity_id=?").run(res.key, String(id));
    const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pkOf(res)}"=?`).get(id) as Record<string, unknown> | undefined;
    if (!row) return;
    db.prepare("INSERT INTO fts_index (resource, entity_id, title, content) VALUES (?,?,?,?)")
      .run(res.key, String(id), titleOf(row), contentOf(db, res, row));
  } catch { /* FTS optional */ }
}

export function removeFromIndex(db: BetterSqlite3.Database, resourceKey: string, id: string | number): void {
  if (!ftsAvailable(db)) return;
  try { db.prepare("DELETE FROM fts_index WHERE resource=? AND entity_id=?").run(resourceKey, String(id)); } catch { /* ignore */ }
}

/** Baut den kompletten Index neu auf (einmalig beim ersten Boot nach der Migration). */
export function rebuildAll(db: BetterSqlite3.Database): number {
  const ins = db.prepare("INSERT INTO fts_index (resource, entity_id, title, content) VALUES (?,?,?,?)");
  let n = 0;
  const tx = db.transaction(() => {
    db.exec("DELETE FROM fts_index");
    for (const res of RESOURCES) {
      const cols = res.searchable ?? textColumns(db, res.table);
      const rows = db.prepare(`SELECT * FROM "${res.table}"`).all() as Record<string, unknown>[];
      for (const row of rows) { ins.run(res.key, String(row[pkOf(res)]), titleOf(row), cols.map((c) => row[c]).filter(Boolean).map(String).join(" ").slice(0, 4000)); n++; }
    }
  });
  tx();
  return n;
}

/** Beim Boot: wenn der Index leer ist (frisch migriert), einmal befüllen. */
export function ensureFtsPopulated(db: BetterSqlite3.Database): void {
  if (!ftsAvailable(db)) return;
  try {
    const c = (db.prepare("SELECT COUNT(*) AS c FROM fts_index").get() as { c: number }).c;
    if (c === 0) { const n = rebuildAll(db); log.info("FTS-Index aufgebaut", { rows: n }); }
  } catch (e) { log.warn("FTS-Aufbau übersprungen", { error: String(e) }); }
}

/** FTS5-Suche. Prefix-Match je Term; gibt Treffer mit Anzeigename zurück. */
export function ftsSearch(db: BetterSqlite3.Database, q: string, limit = 200): { resource: string; entity_id: string; title: string }[] {
  const terms = q.trim().split(/\s+/).filter(Boolean).map((t) => `"${t.replace(/"/g, "")}"*`).join(" ");
  if (!terms) return [];
  return db.prepare("SELECT resource, entity_id, title FROM fts_index WHERE content MATCH ? LIMIT ?").all(terms, limit) as { resource: string; entity_id: string; title: string }[];
}
