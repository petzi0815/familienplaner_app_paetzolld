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
  recordBoot(db);
  _db = db;
  log.info("DB verbunden", { path: config.dbPath });
  return _db;
}

/**
 * Boot-Bookkeeping für die Persistenz-Prüfung:
 * - `seeded_at`: einmalig gesetzt, wenn die DB neu entsteht (bleibt bei persistentem Volume konstant).
 * - `boot_count`: zählt bei JEDEM Start hoch (wächst über Redeploys hinweg, wenn persistent).
 * - `last_boot_at`: Zeitpunkt des letzten Starts.
 */
function recordBoot(db: Database.Database): void {
  const now = new Date().toISOString();
  db.prepare("INSERT INTO app_settings(key,value) VALUES('seeded_at',?) ON CONFLICT(key) DO NOTHING").run(now);
  db.prepare(
    "INSERT INTO app_settings(key,value) VALUES('boot_count','1') ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER)+1, updated_at=datetime('now')",
  ).run();
  db.prepare(
    "INSERT INTO app_settings(key,value) VALUES('last_boot_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=datetime('now')",
  ).run(now);
}

/** Für Tests/Reset. */
export function closeDb(): void {
  if (_db) { _db.close(); _db = null; }
}
