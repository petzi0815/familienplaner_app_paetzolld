// Portiert aus dem Original (`lib/smarthome-db.ts`, Smart Home / Home Assistant). Änderungen ggü. Original:
//  - Verbindung: shared `getDb()` (konsolidierte DB, Singleton) statt eigener better-sqlite3-Datei.
//  - KEIN eigener DB_PATH / `new Database(...)` mehr; `readonly`-Parameter bleibt aus Signaturgründen,
//    wird aber ignoriert (der Singleton ist read-write). Aufrufer schließen die Verbindung NICHT (`db.close()`).
//  - Tabellen präfixiert: entities→ha_entities, relationships→ha_relationships, aliases→ha_aliases,
//    command_log→ha_command_log (Umschreibung in den Routen).
// Logik/Signaturen bleiben 1:1.
import { getDb } from "@/server/db/connection";

export function getSmarthomeDb(_readonly = true) {
  return getDb();
}
