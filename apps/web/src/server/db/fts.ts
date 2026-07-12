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
function trgmAvailable(db: BetterSqlite3.Database): boolean {
  try { db.prepare("SELECT 1 FROM fts_trgm LIMIT 1").get(); return true; } catch { return false; }
}

/** Aktualisiert beide Indizes für genau eine Zeile (nach create/update). */
export function reindexRow(db: BetterSqlite3.Database, res: Resource, id: string | number): void {
  if (!ftsAvailable(db)) return;
  try {
    const row = db.prepare(`SELECT * FROM "${res.table}" WHERE "${pkOf(res)}"=?`).get(id) as Record<string, unknown> | undefined;
    const title = row ? titleOf(row) : "";
    const content = row ? contentOf(db, res, row) : "";
    db.prepare("DELETE FROM fts_index WHERE resource=? AND entity_id=?").run(res.key, String(id));
    if (row) db.prepare("INSERT INTO fts_index (resource, entity_id, title, content) VALUES (?,?,?,?)").run(res.key, String(id), title, content);
    if (trgmAvailable(db)) {
      db.prepare("DELETE FROM fts_trgm WHERE resource=? AND entity_id=?").run(res.key, String(id));
      if (row) db.prepare("INSERT INTO fts_trgm (resource, entity_id, title, content) VALUES (?,?,?,?)").run(res.key, String(id), title, content);
    }
  } catch { /* FTS optional */ }
}

export function removeFromIndex(db: BetterSqlite3.Database, resourceKey: string, id: string | number): void {
  if (!ftsAvailable(db)) return;
  try { db.prepare("DELETE FROM fts_index WHERE resource=? AND entity_id=?").run(resourceKey, String(id)); } catch { /* ignore */ }
  try { db.prepare("DELETE FROM fts_trgm WHERE resource=? AND entity_id=?").run(resourceKey, String(id)); } catch { /* ignore */ }
}

/** Baut beide Indizes komplett neu auf. */
export function rebuildAll(db: BetterSqlite3.Database): number {
  const hasTrgm = trgmAvailable(db);
  const ins = db.prepare("INSERT INTO fts_index (resource, entity_id, title, content) VALUES (?,?,?,?)");
  const insT = hasTrgm ? db.prepare("INSERT INTO fts_trgm (resource, entity_id, title, content) VALUES (?,?,?,?)") : null;
  let n = 0;
  const tx = db.transaction(() => {
    db.exec("DELETE FROM fts_index");
    if (hasTrgm) db.exec("DELETE FROM fts_trgm");
    for (const res of RESOURCES) {
      const rows = db.prepare(`SELECT * FROM "${res.table}"`).all() as Record<string, unknown>[];
      for (const row of rows) {
        const id = String(row[pkOf(res)]);
        const title = titleOf(row);
        const content = contentOf(db, res, row);
        ins.run(res.key, id, title, content);
        insT?.run(res.key, id, title, content);
        n++;
      }
    }
  });
  tx();
  return n;
}

/** Beim Boot: wenn einer der Indizes leer ist (frisch migriert / gerade Trigramm ergänzt), befüllen. */
export function ensureFtsPopulated(db: BetterSqlite3.Database): void {
  if (!ftsAvailable(db)) return;
  try {
    const c = (db.prepare("SELECT COUNT(*) AS c FROM fts_index").get() as { c: number }).c;
    const t = trgmAvailable(db) ? (db.prepare("SELECT COUNT(*) AS c FROM fts_trgm").get() as { c: number }).c : 1;
    if (c === 0 || t === 0) { const n = rebuildAll(db); log.info("FTS-Index aufgebaut", { rows: n, trigram: trgmAvailable(db) }); }
  } catch (e) { log.warn("FTS-Aufbau übersprungen", { error: String(e) }); }
}

type Hit = { resource: string; entity_id: string; title: string };

/** FTS5-Prefix-Suche (exakt/Wortanfang). */
export function ftsSearch(db: BetterSqlite3.Database, q: string, limit = 200): Hit[] {
  const terms = q.trim().split(/\s+/).filter(Boolean).map((t) => `"${t.replace(/"/g, "")}"*`).join(" ");
  if (!terms) return [];
  return db.prepare("SELECT resource, entity_id, title FROM fts_index WHERE content MATCH ? LIMIT ?").all(terms, limit) as Hit[];
}

function trigrams(q: string): string[] {
  const norm = q.toLowerCase().replace(/[^a-z0-9äöüß\s]/gi, " ");
  const out = new Set<string>();
  for (const word of norm.split(/\s+/)) {
    if (word.length < 3) continue;
    for (let i = 0; i <= word.length - 3; i++) out.add(word.slice(i, i + 3));
  }
  return [...out];
}

/** Tippfehlertolerante Trigramm-Suche: ODER über die Query-Trigramme, nach bm25 sortiert
 *  (mehr geteilte Trigramme = besser). Findet Substrings und leichte Verschreiber. */
export function ftsFuzzy(db: BetterSqlite3.Database, q: string, limit = 200): Hit[] {
  if (!trgmAvailable(db)) return [];
  const tg = trigrams(q);
  if (!tg.length) return [];
  const match = tg.map((t) => `"${t}"`).join(" OR ");
  try {
    return db.prepare("SELECT resource, entity_id, title FROM fts_trgm WHERE content MATCH ? ORDER BY bm25(fts_trgm) LIMIT ?").all(match, limit) as Hit[];
  } catch { return []; }
}
