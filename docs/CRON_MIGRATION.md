# Cron Jobs / Scheduled Work

Dateien:

- `cron/jobs-current.summary.json`: aktuelle Jobliste aus dem OpenClaw-Cron-Tool am Exportzeitpunkt.
- `cron/jobs-openclaw-snapshot.migrated.json`: vorhandener Cron-Dateisnapshot mit vollständigen Payloads aus der OpenClaw-Migration.
- `cron/jobs-state-openclaw-snapshot.migrated.json`: vorhandener State-Snapshot.

Wichtige Jobs, die in der neuen Webapp/API als Scheduler oder Worker nachgebaut werden sollten:

- `📅 Termin-Erinnerungen (DB-basiert)`: liest `termine.db`, sendet fällige Erinnerungen und markiert sie als gesendet.
- `🏖️ Wochenend-Aktivitäten (Region Hannover)`: nutzt Reisen-/Termine-Kontext und postet ins Reisen-Topic.
- `🍳 Vorratskammer Rezept-Recherche`: nutzt Vorratskammerdaten für Rezept-/Resteverwertung.
- `🎁 Geschenkplaner`: Geschenkideen/Preischecks aus `geschenkplaner.db`.
- `📚 Bücher Backlog Retry` und `📚 E-Book Backlog Retry`: Buchwunsch-/Download-Backlog.
- `📖 Buchempfehlungen für Elita`: Empfehlungslauf auf Basis Bücherprofil/Wishlist.
- `Deal-Scout & Sale-Check`: Kinderkleidung, Schuhe, Zooplus, Haushaltsbedarf; nutzt Deal-Kontextdateien.
- `Zooplus Nachbestell-Erinnerung`: Haustierbedarf.
- `HA Entity-Sync`, `HA Entity Diff`, `WP Health-Check`, `PV Tages-Report`: Smart-Home-/HA-nahe Jobs.
- Geburtstags-/Termin-/Kita-Einmalerinnerungen sollten künftig aus `termine.db` kommen, nicht als lose Cron-Einzeljobs.

Zielarchitektur: Cronjobs sollten keine freien Shell-SQL-Snippets mehr enthalten, sondern stabile interne API-Endpunkte aufrufen, z.B. `POST /api/jobs/termine/reminders/run`.
