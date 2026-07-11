# CLAUDE.md — Familienplaner (Paetzold-Stilke)

> Anker-Dokument für Session-Kontinuität. Hier steht **wo wir stehen**, die Spezifikation und
> die Arbeitskonventionen. Bei neuer Session: dieses File zuerst lesen, dann das Session-Memory
> (`~/.claude/projects/C--bin-familienplaner-app/memory/`, Index `MEMORY.md`).

## ▶️ WIEDERAUFNAHME (nächste Session) — START HIER

**Stand (2026-07-11): ALLE PHASEN P0–P5 FERTIG & LIVE.** `https://familienplaner.yagemi.app`.
Migration komplett: konsolidierte SQLite (Seed-on-Boot, Volume persistent verifiziert), generische v1-API
für ~48 Ressourcen, rollenbasierte Auth (API-Keys + Familien-Login), Agent-Endpunkte (capabilities/query/
action + Dry-Run), Suche/Dashboard/Reminders, Domänen-UIs (Ressourcen-Browser + Bereichs-Navigation),
Jobs/Scheduler (Run-Logs, env-gated Notify), Backup-Endpunkt + VPS-Skripte, Sentry + Log-Ringpuffer,
OpenAPI, API.md. **Offen/optional:** bereichsspezifische Sonderlogik (Reise-Doc-Upload, Geschenk-„vergeben",
Bild-Upload in der UI), FTS5-Volltext (aktuell LIKE), iOS-App bauen (API ist vorbereitet), graphify-Graph.

<!-- Historie P0 -->
**Stand (2026-07-11): Phase 0 — Fundament FERTIG & gepusht (commit `19247ad`).**
Migration des lokal (Synology) laufenden Familienplaners in ein API-first Monorepo mit
Autodeploy via GitHub → Coolify. Bestätigte Entscheidungen (siehe Tabelle unten):
Next.js-Fullstack behalten & zu Monorepo ausbauen · EINE konsolidierte SQLite auf `/data` ·
API-Key (Agent „Ole") + Familien-Passwort-Login (UI) · vollständige Migration in Phasen.
Zielrepo: `https://github.com/petzi0815/familienplaner_app_paetzolld` (main gepusht).
Monorepo-Skelett steht: `apps/web` (Next 16), Dockerfile (standalone via `NEXT_OUTPUT_STANDALONE=1`),
compose, Observability (Logger + Ring-Buffer + Sentry env-gated), `/healthz` `/version` `/api/v1`
`/api/v1/debug/logs` `/api/v1/docs`. Lokal verifiziert: build+typecheck+lint grün, Endpunkte live.

**Offen (Lars, manuell):** Coolify-App anlegen (Build Pack Dockerfile, Port 3000, Volume `/data`,
Env `PUBLIC_BASE_URL`+`ADMIN_PASSWORD`+`SESSION_SECRET`) → live Shell; dann `/version`+`/healthz`
prüfen. Anleitung: `docs/DEPLOYMENT.md`.
**Nächste Schritte (Claude):** P1 — DB-Konsolidierungsschema + Migrations-Runner + Import der 12
Legacy-SQLite + `vertraege.json` (ID-erhaltend) + Media-Move/Rewrite + `verify-import.ts`
(Row-Counts vs. `docs/DATABASES.md`) + Backup/Restore. Offene Punkte: Coolify-Domain, Verträge-Zielschema.

## Grundsatz-Entscheidungen

| Thema | Entscheidung |
|---|---|
| Architektur | Next.js-16-Fullstack behalten, zu Monorepo ausbauen. UI + `/api/v1` + Worker in einem Deployable. UI = Konsument der eigenen API. |
| Datenhaltung | Eine konsolidierte SQLite `familienplaner.db` auf Coolify-Volume `/data` (better-sqlite3, Migrations, FTS5, Cross-Domain-Suche). |
| Auth | API-Key (Rollen admin/agent/readonly) für „Ole" + Familien-Passwort-Session-Login für die UI. `/healthz`+`/version` offen. |
| Umfang | Vollständige Migration in Phasen P0–P5. |
| Observability | Sentry (env-gated) + strukturiertes Logging + In-Memory-Log-Ringpuffer + admin `GET /api/v1/debug/logs`. |
| Änderbarkeit | Admin-Routen `PUT /api/v1/config`, `Lebensbereiche`-CRUD, `POST /api/v1/jobs/<name>/run` — Ole & Claude Code steuern die App über die API. |
| Offenes Datenmodell | Typisierte Tabellen je Bestandsbereich + `lebensbereiche`-Registry + generischer `entries`-Escape-Hatch + Scaffold. |
| iOS | Vorbereitet (versionierte API, Token-Auth, OpenAPI, stabile Media-URLs, `ios-app/`-Slot, disabled Workflow). App selbst später. |

## Projektziel

Zentrale Familien-App, in der die Familie Paetzold-Stilke (Lars, Elita, Kind „Samu", Katzen
Gypsi/Barcoo) ihr Leben in **Lebensbereichen** organisiert. **API-first:** jede Fähigkeit ist
über eine dokumentierte, versionierte REST-API erreichbar — für die Web-UI, den lokalen
KI-Agenten „Ole" (OpenClaw/Hermes, per API-Key) und später eine iPhone-App. Master-Prompt der
Migration: `docs/TECHNICAL_MIGRATION_PROMPT.md` (aus dem Export, ins Repo übernommen unter docs/).

## Architektur

Ein Coolify-Container (Port 3000): Next.js liefert UI **und** `/api/v1`; ein node-cron-Worker
fährt idempotente Jobs mit Run-Logs. Datenhaltung: eine SQLite unter `$DATA_DIR/familienplaner.db`
(WAL), Media unter `$DATA_DIR/media/<bereich>/…`. Push auf `main` → Coolify Auto-Deploy.

Details & Phasenplan: **`docs/MIGRATION_PLAN.md`**.

## Lebensbereiche (Bestand)

Termine · Reisen · Samu-Inventar (Kleidung/Spielzeug/Marken/Bedarf) · Wunschliste ·
Geschenkplaner · Garten · Vorratskammer · Gypsi (Katzenfutter) · Reiniger · Elisbooks
(physische Bücher) · E-Book-Downloader · Smart Home/HA-Voice · Verträge. Neue Bereiche jederzeit
über die `lebensbereiche`-Registry ergänzbar.

## API-v1-Konventionen

- Pro Domäne: `GET/POST /api/v1/<domain>`, `GET/PATCH/DELETE /api/v1/<domain>/{id}`,
  `POST /<domain>/import`, `GET /<domain>/schema`.
- Agent: `GET /api/v1/agent/capabilities`, `POST /api/v1/agent/query`,
  `POST /api/v1/agent/action` (mit `dry_run`), `GET /api/v1/dashboard/today`,
  `GET /api/v1/search`, `GET /api/v1/reminders/due`.
- Steuerung: `GET/PUT /api/v1/config`, `Lebensbereiche`-CRUD, `POST /api/v1/jobs/<name>/run`,
  `GET /api/v1/debug/logs?lines=&grep=`.
- Validierung via zod → einheitliche Fehler `{error:{code,message,details}}`. OpenAPI unter
  `/api/v1/openapi.json`, Swagger-UI `/api/v1/docs`.

## Deployment (Coolify + GitHub)

- GitHub `petzi0815/familienplaner_app_paetzolld`, Branch `main`. Push → Coolify rebuildet+deployt.
- Coolify: Build Pack **Dockerfile** (Root-`Dockerfile`), Port **3000**, persistentes Volume `/data`,
  Env aus `.env.example`. Domain via `PUBLIC_BASE_URL`. Watch Paths: `apps/web/**`, `Dockerfile`,
  `db/**` (Doku/CLAUDE.md triggern KEIN Deploy).
- Deploy-Check: `curl https://<host>/version` (commit == Kurz-SHA) + `/healthz`.
- Lokal: `docker compose up --build`. Details: `docs/DEPLOYMENT.md`.

## Observability & Debugging

- **Sentry** (`SENTRY_DSN` leer = aus), Release = `APP_GIT_SHA`, PII aus, kein Perf-Tracing.
- **Log-Ringpuffer** (In-Memory, ~1500 Zeilen) → `GET /api/v1/debug/logs?lines=&grep=` (admin) —
  primäre Debug-Quelle ohne Coolify-Terminal. Überlebt keinen Neustart.
- `GET /healthz` (Liveness), `GET /version` (SHA für Deploy-Verifikation).

## Session-Memory & Arbeitskonventionen (Claude)

- **Persistentes Memory:** `~/.claude/projects/C--bin-familienplaner-app/memory/` — Index in
  `MEMORY.md`. **Pro Session** ein `session-YYYY-MM-DD*.md` (was getan/entschieden/gelernt,
  Live-Quirks, nächste Schritte).
- **Session-Ende / Phasenabschluss:** via `/beenden` — Session-Log schreiben, diesen
  WIEDERAUFNAHME-Block aktualisieren, alles committen + pushen (Push deployt via Coolify).
- **graphify:** für dieses Repo konfiguriert (Abschnitt unten). Bei Codebasis-Fragen zuerst den
  Graph nutzen (`graphify query "..."`), nach Doku-Änderungen `/graphify --update`.
- Code Englisch; Doku/Kommentare/Commits Deutsch wo sinnvoll, prägnant. Jede Phase lauffähig
  committen; nach Push per `/version` verifizieren. Secrets nur via `.env`/Coolify.

## Dev-Log (jüngste zuerst)

### Update 3 (2026-07-11) — Phasen 3–5: UIs, Jobs, Härtung (LIVE)
- **P3 UIs:** generischer `ResourceBrowser` (Liste/Bildraster, Suche, Detail, CRUD via v1-API, Bilder,
  Formular aus `/schema`) + `/bereich/[key]` (Einzel→Browser, Multi→Unterkacheln) + `/liste/[resource]`;
  Portal-Kacheln verlinkt. **Lessons:** setState synchron im Effect → Lint-Error (Initial-Load async);
  `<img>` = nur Warnung (ok). `lib/api.ts` schickt Session-Cookie mit.
- **P4 Jobs:** `server/jobs/{registry,runner,scheduler,notify}.ts` — 3 idempotente Jobs (termine-reminders,
  vorrat-mhd-check, garten-aufgaben-check), Run-Logs in `job_runs`, node-cron In-Process-Scheduler
  (`JOBS_ENABLED`), Notify env-gated (kein Telegram-Token → nur Log). Endpunkte `GET /api/v1/jobs`,
  `GET /jobs/{name}`, `POST /jobs/{name}/run?dry_run=1`. Verifiziert (garten dry-run: 35 Aufgaben).
- **P5 Härtung:** `POST/GET /api/v1/debug/backup` (better-sqlite3 `.backup()` nach `$DATA_DIR/backups/`),
  `scripts/{backup,restore}.sh` (VPS), `scripts/smoke.mjs` (API-Smoke), `docs/API.md`, README aktualisiert.

### Update 2 (2026-07-11) — Phase 2: API-Framework + Auth + Agent (lokal verifiziert)
- **Auth:** `server/auth/{auth,session,server}.ts` — Bearer (Admin-Passwort ODER `api_keys`-Hash mit
  Rolle) + signierte Session-Cookies (HMAC/`SESSION_SECRET`). Rollen readonly<agent<admin. Bootstrap-
  Agent-Key beim Boot aus `BOOTSTRAP_AGENT_API_KEY`. Middleware (`middleware.ts`, edge-safe, nur Cookie-
  Präsenz) gated die UI → `/login`.
- **Generisches CRUD:** `server/domains/{registry,crud}.ts` + `db/introspect.ts` — 48 Ressourcen aus
  einer Registry, Spalten zur Laufzeit aus DB. Routen `/api/v1/[domain]` + `/[id]` (+`/schema`,`/import`).
  Filter `?col=val`, `?search=`, `?sort=col:asc`, `?limit/offset`, Bild-URL-Expansion, Auto-Zeitstempel,
  `event_log`-Audit, `?dry_run=1`.
- **Agent:** `agent/capabilities` (maschinenlesbarer Index), `agent/query` (strukturierte Suche),
  `agent/action` (create/update/delete + Dry-Run). Plus `search`, `dashboard/today`, `reminders/due`,
  `config`, `media/[...key]`, `auth/{login,logout,me}`.
- **UI:** Login-Seite + datengetriebenes Portal (Kacheln aus `lebensbereiche`, Tagesübersicht aus DB).
- **Lessons:** (1) Tailwind-JIT generiert KEINE Klassen aus DB-Werten → Gradient-Map im Quelltext.
  (2) React-19-Lint „impure function during render" → Zeit via SQLite `date('now')`/`julianday` statt JS-Date.
  (3) Middleware läuft edge → keine node-Imports (Cookie-Name als Literal); `/healthz`,`/version` aus Matcher
  ausschließen, sonst Redirect-Loop auf den Healthcheck.
- **Verifiziert lokal:** Middleware-Redirect, 401 ohne Auth, CRUD (list/get/create id 37/delete),
  Media 401→200 (181 KB JPEG), Agent-Capabilities (14 Domänen/48 Ressourcen), Query, Dry-Run, Suche
  (korfu→21 Treffer), Dashboard, event_log. build+typecheck+lint grün.

### Update 1 (2026-07-11) — Phase 1: DB-Konsolidierung & Datenmigration (LIVE)
- Alle 12 Legacy-SQLite exakt introspiziert (`scripts/introspect-legacy.mjs` → `_legacy/schemas.json`).
- Konsolidiertes Schema: `db/migrations/0001_infra.sql` (Registry, Auth, Jobs, Media, Audit,
  Verträge, Escape-Hatch) + `0002_domains.sql` (46 Domänen-Tabellen, generiert von
  `gen-domain-migration.mjs` — präfixiert wg. Kollisionen items/wishlist/events/user_settings,
  FK-REFERENCES umgeschrieben).
- **Lesson (Regex-FK-Rewrite):** `REFERENCES books` matchte auch `bookshelves` (→ Syntaxfehler
  „near helves"). Fix: Wortgrenze `\b` nach dem Tabellennamen.
- Seed-Builder (`scripts/build-seed.mjs`): ID-erhaltender Import via ATTACH+INSERT (inkl. BLOBs:
  16 Reise-Docs/5 MB), Media-Umzug `_legacy/media` → `seed/media/<bereich>/`, Bildpfad-Rewrite auf
  Storage-Keys (`<bereich>/<datei>`; externe URLs bleiben), Verträge aus JSON, Registry-Seed.
  Verifikation dst==src grün (6355 Domänen-Zeilen), 406 Assets, 307 Pfade, 2 fehlende Dateien.
- Laufzeit: `server/db/{connection,migrate,seed,paths}.ts` — Seed-on-Boot ins DATA_DIR +
  idempotenter Migrations-Runner, gestartet via `instrumentation.register()` (nodejs).
- **Lesson:** `instrumentation.register()` darf NICHT früh returnen, wenn `SENTRY_DSN` leer ist —
  sonst läuft die DB-Init nie (DSN ist default leer). DB-Init vor der Sentry-Guard.
- Dockerfile kopiert `db/` + `seed/` ins Image (`DB_MIGRATIONS_DIR`/`DB_SEED_DIR`).
- Seed (DB 8 MB + Media 63 MB) committet → Coolify seedet Prod-Volume beim Boot selbst.
- **Verifiziert:** frischer DATA_DIR seedet sich (56 Tabellen/6801 Zeilen); Prod-Deploy `a419872` live.

### Update 0 (2026-07-11) — Projekt-Setup & Plan
- Migrationsquellen analysiert (3 ZIPs: core + media-rest + media-samu): Next.js-16-App,
  12 SQLite (teils kaputte Pfade `/home/node/.openclaw/...`), ~407 Media, Cron/Telegram, Agent „Ole".
- Referenzprojekt `placetel-elevenlabs-asterix-bridge` als Muster analysiert (Coolify/Docker,
  Sentry, Log-Ringpuffer, CLAUDE.md-Anker, Memory/Session-Logs, graphify).
- Grundsatz-Entscheidungen via AskUserQuestion bestätigt (Tabelle oben).
- Vollständiger Plan geschrieben: `docs/MIGRATION_PLAN.md`. Memory angelegt
  ([[projekt-familienplaner]], [[familienplaner-referenzmuster]]).
- **P0 FERTIG (commit `19247ad`, gepusht):** Monorepo-Skelett (npm workspaces, apps/web),
  Dockerfile (multi-stage standalone, /data-Volume), docker-compose, .env.example, CI (disabled),
  Observability (Logger + Ring-Buffer + Sentry-Hook), `/healthz`+`/version`+`/api/v1`+`/api/v1/debug/logs`+`/api/v1/docs`.
  - **Lesson (Windows):** Next 16/Turbopack + `output:'standalone'` scheitert lokal auf Windows am
    `:` in Chunknamen (`node:inspector`) beim Standalone-Copy → `EINVAL copyfile`. Gelöst: Standalone
    nur im Docker-Build (`NEXT_OUTPUT_STANDALONE=1` im Dockerfile), lokal/CI ohne. Der Compile/Typecheck
    lief davor bereits grün — reines OS-Copy-Problem, auf Linux (Coolify) irrelevant.
  - **Lesson:** eigener Mini-Logger statt pino (vermeidet Worker/Transport-Probleme im standalone-Bundle).

## graphify

This project has (will have) a knowledge graph at graphify-out/ with god nodes, community
structure, and cross-file relationships.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading source files / grep / codebase questions.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files.
- Cross-module „how does X relate to Y" → prefer `graphify query`, `graphify path`, `graphify explain`.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
