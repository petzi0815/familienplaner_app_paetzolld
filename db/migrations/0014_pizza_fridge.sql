-- 0014_pizza_fridge.sql — Kuehlschranktemperatur pro Rezeptur speicherbar
-- Damit eine gespeicherte Rezeptur die (Advanced-)Kuehlschranktemperatur verlustfrei mitfuehrt.
-- SQLite kann kein "ADD COLUMN IF NOT EXISTS", aber der Migrations-Tracker (schema_migrations)
-- fuehrt jede Datei genau einmal aus → ein simples ALTER TABLE ADD COLUMN ist idempotent.
-- NOT NULL ist zulaessig, weil ein DEFAULT angegeben ist; bestehende Zeilen erhalten so den Default 5.
-- Technik bleibt fest "Kugeln kalt" → keine weitere Spalte noetig.
ALTER TABLE "pizza_rezepte" ADD COLUMN fridge_temp REAL NOT NULL DEFAULT 5;
