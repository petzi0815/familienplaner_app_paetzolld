# Technischer Prompt für Migration in eine eigenständige Familienplaner-Webapp/API

Du migrierst den bestehenden Familienplaner von OpenClaw-Skills + Next.js-App + SQLite-Dateien in eine robuste Webapp mit klaren APIs. Ziel: Ole soll später alle Funktionen über strukturierte APIs ansprechen können, mindestens so gut wie heute über direkte SQLite-/Dateizugriffe.

## Ausgangslage

Der Export enthält die aktuelle App unter `app/familienplaner-webapp`. Sie ist eine Next.js-App mit API-Routen unter `src/app/api/*` und Seiten für u.a. Termine, Reisen, Wunschliste, Samu-Inventar, Garten, Vorratskammer, Gypsi, Geschenkplaner, Reiniger, Bücher/Elisbooks und Smart Home. Daten liegen derzeit in mehreren SQLite-Dateien unter `databases/`. Skill-Anweisungen und Cron-Scheduler liegen unter `skills/` und `cron/`.

## Harte Anforderungen

1. Baue eine zentrale Familienplaner-App mit versionierter REST-API oder tRPC/OpenAPI. Externe Agenten müssen dokumentiert und stabil zugreifen können.
2. Trenne Datenhaltung, API, UI und Worker/Scheduler. Keine Cronjobs mit direktem SQL im Prompt.
3. Migriere Daten so, dass bestehende IDs, Bildpfade und Beziehungen erhalten bleiben.
4. Erzeuge OpenAPI/Swagger-Doku und einen maschinenlesbaren API-Index für Ole.
5. Authentifiziere API-Zugriffe mit Service Token/API Key und rollenbasierten Rechten.
6. Secrets gehören in Env Vars/Secret Store, nicht in Code oder Datenexporte.
7. Bilder/Dateien müssen über stabile Media-URLs verfügbar sein; DB-Records sollen nicht auf zufällige lokale Pfade zeigen, sondern auf verwaltete Asset-IDs oder relative Storage-Keys.
8. Jeder Bereich braucht CRUD plus agentenfreundliche Query-Endpunkte.
9. Jobs müssen idempotent sein und Run-Logs speichern.
10. Telegram-Topic-Routing muss als Konfiguration abgebildet werden.

## Zieldomänen

- Termine: `termine.db`; wichtigste API: fällige Erinnerungen, neue Termine, Status, Kategorien, Reminder-Tage.
- Reisen/Aktivitäten: `reisen.db`; Trips, Notes, Links, Dokumente/BLOBs, Wochenendtipps.
- Wunschliste/Geschenke: `wunschliste.db`, `geschenkplaner.db`; Events, Items, Preischecks, Bilder, Empfehlungen.
- Samu-Inventar: `samu-inventar.db`; Kleidung/Spielzeug, Status, Größen, Bilder, Verkaufs-/Schranklogik.
- Garten: `garten.db`; Pflanzen, Samen, Aufgaben, Dünger, GTS/Wetterbezug, Bilder.
- Vorratskammer: `vorratskammer.db`; Lebensmittel, MHD, Status, Rezepte, Einkaufs-/Resteverwertung.
- Gypsi: `gypsi.db`; Futtervorlieben, Status, Marke/Sorte/Geschmack, Bilder.
- Reiniger: `reiniger.db`; Produkte, Oberflächen, Fleckenhilfe, Anwendungshinweise, Bilder.
- Bücher/Elisbooks: `elisbooks.db` und Ebook-Wishlist; Buchwünsche, Backlog, Downloadstatus, Empfehlungen.
- Smart Home/HA Voice: `ha-voice.db`; Entities, Aliases, Beziehungen, Logs, HA Zugriff.
- Verträge: aktuell JSON/Memory plus GraphRAG; mittelfristig eigene Tabellen/Importpipeline.

## API-Mindestumfang pro Domäne

- `GET /api/v1/<domain>` mit Filter/Pagination/Search.
- `POST /api/v1/<domain>` zum Anlegen.
- `GET /api/v1/<domain>/{id}`.
- `PATCH /api/v1/<domain>/{id}`.
- `DELETE /api/v1/<domain>/{id}` mit Soft-Delete, wo sinnvoll.
- `POST /api/v1/<domain>/import` für Migration/Backfills.
- `GET /api/v1/<domain>/schema` oder OpenAPI-Schema.
- `POST /api/v1/jobs/<jobName>/run` für Scheduler/Agent-Auslösung.

## Agentenfreundliche Spezialendpunkte

- `GET /api/v1/agent/capabilities`: Liste aller Domänen, Endpunkte, erlaubter Aktionen, Beispielpayloads.
- `POST /api/v1/agent/query`: strukturierte Suche über Domänen, nie freies SQL.
- `POST /api/v1/agent/action`: validierte Aktionen mit Dry-Run-Modus.
- `GET /api/v1/reminders/due` und `POST /api/v1/reminders/{id}/sent`.
- `GET /api/v1/dashboard/today`: kompakter Tageszustand für Ole.
- `GET /api/v1/search?q=...&domains=...`: Volltextsuche.

## Scheduler-Migration

Lies `docs/CRON_MIGRATION.md` und `cron/*.json`. Lege alle wiederkehrenden Aufgaben als Worker-Jobs an. Jeder Job soll speichern: Name, Schedule, letzte Ausführung, Status, Fehler, erzeugte Nachrichten, betroffene Datensätze. Jobs dürfen Telegram erst senden, wenn die Zielkonfiguration vorhanden ist.

## Datenmigration

Nutze `docs/database-schemas.json` und die DB-Dateien. Erstelle Migrationen statt Ad-hoc-Schemaänderungen. Prüfe WAL/SHM-Dateien und konsolidiere SQLite vor Import. Bildpfade aus den DBs müssen gegen `media/` auflösbar sein.

## Qualität

- Schreibe Importtests mit Row-Counts gegen `docs/DATABASES.md`.
- Schreibe API-Contract-Tests für die wichtigsten Agentenendpunkte.
- Liefere eine lokale Dev-Anleitung: `npm ci`, DB-Seed/Import, Start, Beispiel-curl.
- Liefere eine Produktionsanleitung mit Backup/Restore für DB und Media.

## Wichtig für Ole

Ole darf nach der Migration nicht mehr raten oder direkt in Dateipfade greifen müssen. Für jede bisherige Fähigkeit muss es einen dokumentierten API-Weg geben. Besonders wichtig: Termine, Reisen, Samu-Inventar, Garten, Vorratskammer, Gypsi, Geschenkplaner, Bücher, Reiniger und Smart Home. APIs sollen klare Fehler liefern und Dry-Run unterstützen, damit Ole vor riskanten Aktionen erst eine Vorschau geben kann.
