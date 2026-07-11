import Database from "better-sqlite3";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";
import { ensureSeeded } from "./seed";
import { runMigrations } from "./migrate";

let _db: Database.Database | null = null;

/**
 * Zentrale DB-Verbindung (Singleton). Beim ersten Zugriff: Seed ins DATA_DIR
 * kopieren (falls leer), DB öffnen (WAL), ausstehende Migrationen anwenden.
 */
export function getDb(): Database.Database {
  if (_db) return _db;
  ensureSeeded();
  const db = new Database(config.dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  runMigrations(db);
  _db = db;
  log.info("DB verbunden", { path: config.dbPath });
  return _db;
}

/** Für Tests/Reset. */
export function closeDb(): void {
  if (_db) { _db.close(); _db = null; }
}
