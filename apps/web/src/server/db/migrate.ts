import fs from "node:fs";
import path from "node:path";
import type BetterSqlite3 from "better-sqlite3";
import { log } from "@/server/observability/logger";
import { resolveMigrationsDir } from "./paths";

/**
 * Wendet ausstehende SQL-Migrationen (db/migrations/*.sql, nummeriert) idempotent an.
 * Auf einer geseedeten DB sind 0001/0002 bereits vermerkt → werden übersprungen.
 */
export function runMigrations(db: BetterSqlite3.Database): void {
  const dir = resolveMigrationsDir();
  if (!dir || !fs.existsSync(dir)) {
    log.warn("Kein Migrations-Verzeichnis gefunden", { dir });
    return;
  }
  db.exec(
    "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL DEFAULT (datetime('now')))",
  );
  const applied = new Set(
    (db.prepare("SELECT version FROM schema_migrations").all() as { version: string }[]).map((r) => r.version),
  );
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".sql")).sort();
  for (const f of files) {
    const version = f.replace(/\.sql$/, "");
    if (applied.has(version)) continue;
    const sql = fs.readFileSync(path.join(dir, f), "utf8");
    const tx = db.transaction(() => {
      db.exec(sql);
      db.prepare("INSERT INTO schema_migrations (version) VALUES (?)").run(version);
    });
    tx();
    log.info("Migration angewandt", { version });
  }
}
