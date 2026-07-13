import Database from "better-sqlite3";
import { config } from "@/server/config";
import { log } from "@/server/observability/logger";
import { sha256 } from "@/server/util/hash";
import { ensureSeeded } from "./seed";
import { runMigrations } from "./migrate";
import { ensureFtsPopulated } from "./fts";

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
  bootstrapApiKeys(db);
  ensureFtsPopulated(db);
  _db = db;
  log.info("DB verbunden", { path: config.dbPath });
  return _db;
}

/**
 * Legt beim Boot die konfigurierten API-Keys an (gehasht), falls gesetzt & noch nicht vorhanden:
 * - den Shared-Agent-Key „Ole" (owner NULL),
 * - je einen Per-User-Key für Lars & Elita (owner gesetzt) — für Geräte-Zuordnung + gezielte Push.
 */
function bootstrapApiKeys(db: Database.Database): void {
  ensureKey(db, "bootstrap-agent", config.bootstrapAgentApiKey, "agent", null);
  for (const k of config.bootstrapUserKeys) {
    ensureKey(db, k.label, k.key, k.role, k.owner);
  }
}

/** Fügt einen API-Key idempotent ein (nur wenn gesetzt und noch nicht vorhanden). */
function ensureKey(db: Database.Database, label: string, key: string, role: string, owner: string | null): void {
  if (!key) return;
  const hash = sha256(key);
  if (db.prepare("SELECT 1 FROM api_keys WHERE key_hash=?").get(hash)) return;
  db.prepare("INSERT INTO api_keys (label, key_hash, role, owner) VALUES (?,?,?,?)").run(label, hash, role, owner);
  log.info("API-Key angelegt", { label, role, owner: owner ?? "-" });
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
