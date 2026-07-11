import { getDb } from "@/server/db/connection";
import { RESOURCES, pkOf, resourceByKey } from "@/server/domains/registry";
import { textColumns } from "@/server/db/introspect";
import { ftsAvailable, ftsSearch } from "@/server/db/fts";
import { getAuth, hasRole } from "@/server/auth/auth";
import { unauthorized, ok, fail } from "@/server/http/respond";

// Cross-Domain-Volltextsuche — FTS5 (mit LIKE-Fallback).
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DISPLAY = ["title", "titel", "name", "friendly_name", "bezeichnung", "anbieter", "beschreibung", "problem"];
const display = (row: Record<string, unknown>) => { for (const c of DISPLAY) if (row[c]) return String(row[c]); return ""; };

export function GET(req: Request): Response {
  if (!hasRole(getAuth(req), "readonly")) return unauthorized();
  const url = new URL(req.url);
  const q = (url.searchParams.get("q") ?? "").trim();
  if (!q) return fail("missing_q", "Query-Parameter 'q' erforderlich.", 400);
  const domainFilter = url.searchParams.get("domains");
  const domains = domainFilter ? new Set(domainFilter.split(",").map((s) => s.trim())) : null;
  const db = getDb();

  // Bevorzugt FTS5.
  if (ftsAvailable(db)) {
    try {
      const hits = ftsSearch(db, q, 300);
      const results = hits
        .map((h) => ({ res: resourceByKey(h.resource), h }))
        .filter(({ res }) => res && (!domains || domains.has(res.domain)))
        .slice(0, 200)
        .map(({ res, h }) => ({ resource: h.resource, domain: res!.domain, label: res!.label, id: h.entity_id, display: h.title }));
      return ok({ query: q, engine: "fts5", count: results.length, results });
    } catch { /* Fallback auf LIKE */ }
  }

  // LIKE-Fallback.
  const results: { resource: string; domain: string; label: string; id: unknown; display: string }[] = [];
  for (const r of RESOURCES) {
    if (domains && !domains.has(r.domain)) continue;
    const cols = r.searchable ?? textColumns(db, r.table);
    if (!cols.length) continue;
    const whereSql = "(" + cols.map((c) => `"${c}" LIKE ?`).join(" OR ") + ")";
    const params = cols.map(() => `%${q}%`);
    try {
      const rows = db.prepare(`SELECT * FROM "${r.table}" WHERE ${whereSql} LIMIT 8`).all(...params) as Record<string, unknown>[];
      for (const row of rows) results.push({ resource: r.key, domain: r.domain, label: r.label, id: row[pkOf(r)], display: display(row) });
    } catch { /* skip */ }
    if (results.length >= 200) break;
  }
  return ok({ query: q, engine: "like", count: results.length, results });
}
