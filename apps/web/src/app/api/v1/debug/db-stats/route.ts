import { getDb } from "@/server/db/connection";
import { config } from "@/server/config";
import { isAdminRequest, unauthorized } from "@/server/auth/admin";

// DB-Statistik (admin) — Row-Counts aller Tabellen + Migrationsstand. Debug-Hilfe.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export function GET(req: Request): Response {
  if (!isAdminRequest(req)) return unauthorized();
  const db = getDb();
  const tables = (
    db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all() as { name: string }[]
  ).map((r) => r.name);
  const counts: Record<string, number> = {};
  let total = 0;
  for (const t of tables) {
    const c = (db.prepare(`SELECT COUNT(*) AS c FROM "${t}"`).get() as { c: number }).c;
    counts[t] = c;
    total += c;
  }
  const migrations = db.prepare("SELECT version, applied_at FROM schema_migrations ORDER BY version").all();
  return Response.json(
    { dbPath: config.dbPath, migrations, tableCount: tables.length, totalRows: total, counts },
    { headers: { "cache-control": "no-store" } },
  );
}
