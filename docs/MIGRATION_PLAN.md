# Technischer Migrationsplan — Familienplaner (Paetzold-Stilke)

> Migration des lokal auf der Synology laufenden Familienplaners in ein
> API-first Monorepo mit Autodeploy via GitHub → **Coolify**.
> Zielrepo: `https://github.com/petzi0815/familienplaner_app_paetzolld`
> Referenz-Tech-Stack (nur Muster, kein Design): `C:\bin\placetel-elevenlabs-asterix-bridge`
> Stand: 2026-07-11 · Autor: Claude Code

---

## 0. Bestätigte Grundsatz-Entscheidungen

| Thema | Entscheidung |
|---|---|
| **Architektur** | Bestehende **Next.js-16-Fullstack-App** bleibt Basis, ausgebaut zu sauberem Monorepo. UI + `/api/v1` + Worker in einem Deployable. Die UI ist Konsument der eigenen API (API-first). |
| **Datenhaltung** | **Eine konsolidierte SQLite-DB** (`familienplaner.db`) auf dem Coolify-Volume `/data`. Migrations, FTS5, Cross-Domain-Suche. `better-sqlite3` bleibt. |
| **Auth** | **API-Key (rollenbasiert)** für Agent „Ole" + **Login (Session-Cookie)** für die Web-UI. `/healthz` & `/version` offen. |
| **Umfang** | **Vollständige Migration in Phasen** — erst Gerüst + Deployment live, dann alle ~13 Bereiche komplett (Daten + v1-API + UI + Jobs). |
| **Observability** | **Sentry** (wie Referenz) + strukturiertes Logging + In-Memory-Log-Ringpuffer + admin-gated `GET /api/v1/debug/logs`. |
| **Änderbarkeit via API** | Admin-gated Config-/Content-Routen (`PUT /api/v1/config`, `Lebensbereiche`-CRUD, Feature-Flags) — Ole **und** Claude Code können die App über die API steuern. |
| **Wissensbasis** | **graphify** (`graphify-out/` + post-commit-Hook), **CLAUDE.md**-Session-Anker, **Memory + Session-Logs**, Phasenabschluss via `/beenden`. |
| **iOS** | Jetzt nur **vorbereitet**: versionierte API, Token-Auth, OpenAPI (Swift-Codegen später), stabile Media-URLs, `ios-app/`-Slot + deaktivierter TestFlight-Workflow (Referenzmuster). |
| **Offenes Datenmodell** | Typisierte Tabellen je Bestandsbereich (verlustfreie Migration) **plus** `lebensbereiche`-Registry + generischer `entries`-Escape-Hatch + Scaffold für neue Bereiche. |

---

## 1. Ausgangslage (Ist-Zustand aus den ZIPs)

- **Stack:** Next.js 16.1.6 / React 19.2.3 / TypeScript 5.9.3 / Tailwind v4 / `better-sqlite3` — heute `next start` auf Port 3001, PWA (Service-Worker, Apple-Touch-Icon), iOS-Designsprache (SF-Font, Apple-Systemfarben, Gradient-Kacheln, mobile-first).
- **~13 Lebensbereiche:** Samu-Inventar, Termine, Reisen, Wunschliste, Geschenkplaner, Garten, Vorratskammer, Gypsi (Katzenfutter), Reiniger, Bücher (E-Book-Downloader), Elisbooks (physische Bücher), Smart-Home/HA-Voice, Verträge (heute JSON).
- **~95 API-Routen**, **~19 Seiten** (`src/app/**`).
- **12 SQLite-Dateien** mit teils FTS5. **Kernproblem:** DB-Pfade chaotisch — teils hartkodierte Absolutpfade (`/home/node/.openclaw/workspace/skills/...`), teils relative `process.cwd()`-Pfade. Muss auf `DATA_DIR`/Volume vereinheitlicht werden.
- **~407 Media-Dateien** unter `media/skills/<bereich>/images`; DB-Records referenzieren Bildpfade.
- **Cron/Jobs** (Termin-Reminder, Wochenend-Tipps, Rezept-Recherche, Deal-Scout, Backlog-Retries, HA-Sync …) mit Telegram-Topic-Routing (heute via OpenClaw).
- **Agent „Ole":** greift heute teils direkt auf Dateien/SQL zu. Ziel lt. Master-Prompt: für **jede** Fähigkeit ein dokumentierter API-Weg, mit Dry-Run vor riskanten Aktionen.

### Datenbank-Inventar (Konsolidierungs-Quellen)

| Legacy-DB | Kern-Tabellen (Rows) | Ziel-Namespace |
|---|---|---|
| `samu-inventar.db` | items (222), marken (48), bedarfsliste (8), items_fts | `samu_*` |
| `termine.db` | termine (36) | `termine` |
| `reisen.db` | trips (21) + 15 trip_* + weekend_tips (88) | `reisen_*` |
| `wunschliste.db` | events (3), items (26) | `wunschliste_*` |
| `geschenkplaner.db` | geschenke (433), ereignisse (62), kinder (11), anlass_config (33), vergangene_geschenke | `geschenk_*` |
| `garten.db` | aufgaben (241), samen (57), duenger (15), pflanzen (6), *_fts, pflanze_duenger | `garten_*` |
| `vorratskammer.db` | lebensmittel (0), rezepte (0) | `vorrat_*` |
| `gypsi.db` | futter (5) | `gypsi_futter` |
| `reiniger.db` | reiniger (4), anwendungen (17) | `reiniger_*` |
| `elisbooks.db` | books (346), bookshelves (7), wishlist (5), user_settings (5) | `elisbooks_*` |
| `ebook-downloader/wishlist.db` | wishlist (88) | `ebook_wishlist` |
| `ha-voice.db` | entities (3906), entities_fts, relationships (394), aliases (2), command_log (19) | `ha_*` |
| `vertraege.json` | (JSON) | `vertraege` (neu tabellarisiert) |

> Hinweis: `databases/samu-inventar/db/` enthält die **kanonischen** `termine.db`, `reisen.db`, `wunschliste.db`, `samu-inventar.db` (die `garten.db`/`geschenkplaner.db` dort sind leere Dubletten → ignorieren; kanonisch sind `databases/garten/…` und `databases/geschenkplaner/…`). WAL/SHM vor Import per `PRAGMA wal_checkpoint(TRUNCATE)` konsolidieren.

---

## 2. Zielarchitektur

```
                       petzi0815/familienplaner_app_paetzolld  (main → Coolify Autodeploy)
┌───────────────────────────────────────────────────────────────────────────────┐
│  Coolify-App (1 Container, Port 3000)                                           │
│  ┌─────────────────────────────┐        ┌────────────────────────────────────┐ │
│  │  Next.js (apps/web)          │        │  Worker/Scheduler (node-cron)      │ │
│  │  • UI (iOS-Design, PWA)      │        │  • idempotente Jobs + Run-Logs     │ │
│  │  • /api/v1/** (REST+OpenAPI) │◄──────►│  • ruft interne v1-Job-Endpunkte   │ │
│  │  • Auth (API-Key / Session)  │        │  • Telegram/Notify (env-gated OFF) │ │
│  │  • Sentry + Log-Ringpuffer   │        └────────────────────────────────────┘ │
│  └──────────────┬──────────────┘                                                │
│                 │ better-sqlite3 (WAL)                                          │
│        ┌────────▼─────────┐   Persistentes Coolify-Volume  →  /data            │
│        │ familienplaner.db│   /data/media/<bereich>/...                        │
│        └──────────────────┘                                                    │
└───────────────────────────────────────────────────────────────────────────────┘
        ▲ Konsumenten der API:  Web-UI · Agent „Ole" (API-Key) · später iOS-App · Claude Code
```

### Monorepo-Layout

```
familienplaner_app_paetzolld/
├── apps/
│   └── web/                     # Next.js 16 (migrierte familienplaner-webapp)
│       ├── src/
│       │   ├── app/
│       │   │   ├── (ui-seiten)  # bestehende Seiten, an /api/v1 angebunden
│       │   │   └── api/v1/**    # versionierte REST-API + OpenAPI + agent + debug
│       │   ├── server/
│       │   │   ├── db/          # Connection, Migrations-Runner, Repos je Domäne
│       │   │   ├── domains/     # Domänen-Services (Business-Logik, entkoppelt)
│       │   │   ├── auth/        # API-Keys, Rollen, Session-Login
│       │   │   ├── openapi/     # zod-Schemas → openapi.json
│       │   │   ├── jobs/        # Job-Registry + Handler + Run-Logs
│       │   │   ├── media/       # Storage-Keys, Auflösung, Serving
│       │   │   └── observability/  # logger (pino), ring-buffer, sentry
│       │   └── lib/             # UI-Helfer, api-client (fetch-Wrapper)
│       └── public/
├── ios-app/                     # Platzhalter (SwiftUI später) + README
├── packages/
│   └── api-types/               # generierte TS-Typen aus OpenAPI (UI + später Swift)
├── db/
│   ├── migrations/              # 0001_init.sql, 0002_…  (nummeriert, idempotent)
│   └── schema.md                # dokumentiertes Zielschema
├── scripts/
│   ├── import-legacy.ts         # 12 SQLite + JSON → familienplaner.db (ID-erhaltend)
│   ├── import-media.ts          # media/** → /data/media + Pfad-Rewrite
│   ├── verify-import.ts         # Row-Counts gegen docs/DATABASES.md
│   └── backup.sh / restore.sh   # DB + Media Backup/Restore
├── docs/                        # dieser Plan, API, DB, Deployment, Runbook, Secrets
├── graphify-out/                # Wissensgraph (GRAPH_REPORT.md, graph.html) — generiert
├── .github/workflows/           # ci.yml (lint/build/test) + ios.yml (disabled placeholder)
├── Dockerfile                   # multi-stage: build Next standalone → schlanke Runtime
├── docker-compose.yml           # lokale Produktions-Parität (Volume /data)
├── .env.example                 # jede Variable kommentiert (Referenzmuster)
├── .dockerignore / .gitignore
├── CLAUDE.md                    # Session-Kontinuitäts-Anker (WIEDERAUFNAHME + Dev-Log)
├── README.md
└── package.json                 # npm workspaces (apps/*, packages/*)
```

---

## 3. Datenmodell — verlustfrei + offen erweiterbar

**Prinzip:** Bestandsbereiche behalten ihre **typisierten Tabellen** (verlustfreie Migration, bestehende UIs/Queries bleiben nutzbar). Für Offenheit kommen drei Bausteine dazu:

1. **`lebensbereiche` (Registry)** — steuert das Dashboard **datengetrieben**:
   `id, key, titel, beschreibung, emoji, gradient, sort, enabled, api_base, schema_ref, erstellt_am`. Die heutigen Kacheln (`page.tsx`) werden daraus gerendert. Neuer Bereich = neuer Datensatz + Route, kein UI-Rebuild nötig.
2. **`entries` + JSON-`custom_fields` (Escape-Hatch)** — generische Tabelle für Bereiche ohne eigenes Schema (`bereich_key, typ, titel, daten JSON, bild_key, status, timestamps`). Ermöglicht spontane neue Bereiche ohne Migration.
3. **Scaffold** (`scripts/new-lebensbereich.ts`) — generiert Migration + Service + `/api/v1/<key>`-Route + OpenAPI-Eintrag + Dashboard-Registry-Zeile aus einer kleinen Spezifikation.

Zusätzlich global:
- **`app_settings`** (key/value, JSON) — Runtime-Config über `PUT /api/v1/config`.
- **`api_keys`** (hash, rolle, label, last_used, revoked) und **`users`/`sessions`** für die UI-Anmeldung.
- **`job_runs`** (name, schedule, started_at, finished_at, status, error, messages, affected_rows) für idempotente Jobs mit Run-Logs.
- **`media_assets`** (id, bereich, storage_key, original_name, mime, bytes, sha256, created_at) — stabile Asset-IDs statt Zufallspfade.
- **`event_log`** (append-only Audit: wer/was/wann über die API geändert hat).

Migrations als nummerierte SQL-Dateien, beim Boot idempotent angewandt (`schema_migrations`-Tabelle). SQLite-Dialekt beibehalten (FTS5, `datetime('now')`).

---

## 4. API-v1-Design (Master-Prompt-konform)

**Pro Domäne** (`<domain>` = termine, reisen, samu, wunschliste, geschenke, garten, vorrat, gypsi, reiniger, elisbooks, ebooks, smarthome, vertraege):
- `GET /api/v1/<domain>` — Filter, Pagination, Search
- `POST /api/v1/<domain>` — Anlegen
- `GET|PATCH|DELETE /api/v1/<domain>/{id}` — Detail/Update/Soft-Delete
- `POST /api/v1/<domain>/import` — Migration/Backfill
- `GET /api/v1/<domain>/schema` — JSON-Schema/OpenAPI-Fragment

**Agentenfreundliche Spezial-Endpunkte (für Ole):**
- `GET  /api/v1/agent/capabilities` — maschinenlesbarer Index: Domänen, Endpunkte, erlaubte Aktionen, Beispiel-Payloads.
- `POST /api/v1/agent/query` — strukturierte Suche über Domänen (nie freies SQL).
- `POST /api/v1/agent/action` — validierte Aktionen mit **`dry_run`**-Modus (Vorschau vor Ausführung).
- `GET  /api/v1/reminders/due` · `POST /api/v1/reminders/{id}/sent`
- `GET  /api/v1/dashboard/today` — kompakter Tageszustand.
- `GET  /api/v1/search?q=&domains=` — FTS5-Volltextsuche cross-domain.

**Änderungs-/Steuer-Routen (Ole + Claude Code):**
- `GET|PUT /api/v1/config` — App-Settings zur Laufzeit.
- `GET|POST|PATCH|DELETE /api/v1/lebensbereiche` — Bereiche anlegen/umbenennen/aktivieren.
- `POST /api/v1/jobs/<name>/run` — Job/Scheduler-Auslösung.
- `GET /api/v1/debug/logs?lines=&grep=` — Log-Ringpuffer (admin).

**Querschnitt:**
- **Auth-Middleware:** Bearer-API-Key (Rollen `admin` / `agent` / `readonly`) **oder** Session-Cookie (UI). `/healthz`, `/version`, `/api/v1/openapi.json`, `/api/v1/docs` offen.
- **Validierung:** zod-Schemas → einheitliche Fehlerobjekte (`{error:{code,message,details}}`), klare 4xx, Dry-Run-Vorschau.
- **OpenAPI:** aus zod generiert → `GET /api/v1/openapi.json` + Swagger-UI unter `/api/v1/docs`. TS-Typen nach `packages/api-types` (UI + später Swift-Codegen).
- **Pagination:** `?limit=&offset=` + `X-Total-Count`.

---

## 5. Media

- Alle `media/skills/<area>/images/*` → `/data/media/<area>/…` (Volume).
- DB-Bildpfade werden beim Import auf **relative Storage-Keys** umgeschrieben (`media_assets.storage_key`), keine Absolutpfade mehr.
- Stabile Auslieferung über `GET /api/v1/media/<area>/<key>` (bzw. `/media/...` Rewrite) mit Caching-Headern — iOS-tauglich.

---

## 6. Observability & Debuggability (Referenzmuster)

- **Sentry** (`@sentry/nextjs`): `SENTRY_DSN` (leer = aus), `release = APP_GIT_SHA`, `tracesSampleRate=0`, `sendDefaultPii=false`. Fängt Server- & Client-Fehler.
- **Strukturiertes Logging** (pino) + **In-Memory-Ring-Buffer** (letzte ~1500 Zeilen) → `GET /api/v1/debug/logs?lines=&grep=` (admin). Primäre Debug-Quelle ohne Coolify-Terminal — wie im Referenzprojekt.
- **`GET /healthz`** (Liveness) + **`GET /version`** (`commit == SOURCE_COMMIT`) für Deploy-Verifikation.
- **`event_log`** als fachlicher Audit-Trail (welche API-Aktion hat was geändert).
- **Debug-Routen** admin-gated (z.B. `GET /api/v1/debug/db-stats`, `GET /api/v1/debug/config`) — damit Claude Code Fehler „hier" gezielt untersuchen kann.

---

## 7. Jobs / Scheduler

- **Job-Registry** mit idempotenten Handlern; jeder Lauf schreibt `job_runs` (Name, Schedule, letzte Ausführung, Status, Fehler, erzeugte Nachrichten, betroffene Datensätze).
- Auslösung doppelt: **`POST /api/v1/jobs/<name>/run`** (Ole/Claude/extern) **und** interner **node-cron**-Scheduler im Worker.
- **Keine freien SQL-Snippets** mehr im Cron — Jobs rufen stabile interne Services/Endpunkte.
- **Telegram/Notifications**: Adapter mit `TELEGRAM_*`-Env + Topic-Routing-Konfiguration (`app_settings`), standardmäßig **AUS**, bis Zielkonfiguration gesetzt ist.
- Migrationsziele u.a.: Termin-Erinnerungen (aus `termine`), Wochenend-Tipps, Rezept-Recherche, Geschenk-Recherche, Buch-/E-Book-Backlog-Retry, Deal-Scout, Zooplus-Reminder, HA-Sync/Diff, PV-/WP-Checks.

---

## 8. Deployment (Coolify + GitHub, Referenzmuster)

- **Dockerfile** (multi-stage): Stage 1 baut `apps/web` als Next **standalone** Output; Stage 2 schlanke Node-Runtime (`node:24-slim`), `better-sqlite3` nativ für die Runtime gebaut, Non-Root-User (uid/gid 1001), `mkdir /data`, `HEALTHCHECK` auf `/healthz`, `EXPOSE 3000`, `ARG SOURCE_COMMIT → ENV APP_GIT_SHA`. `ENV DATA_DIR=/data`.
- **docker-compose.yml**: lokale Produktions-Parität (`volumes: familienplaner-data:/data`, Port 3000, env_file `.env`, healthcheck).
- **Coolify**: 1 Projekt, 1 App aus dem Repo, **Build Pack Dockerfile**, Port 3000, Domain (z.B. `familie.paetzold.…` — final festzulegen), **persistentes Volume `/data`**, Env-Vars aus `.env.example`. **Push auf `main` → Auto-Rebuild+Deploy.** Watch Paths optional (`apps/web/**`, `Dockerfile`, `db/**`).
- **GitHub Actions**: `ci.yml` (lint + typecheck + build + Import-/Contract-Tests) auf PR/Push. `ios.yml` als **deaktivierter Platzhalter** (TestFlight, fastlane, xcodegen) analog Referenz — aktiviert erst mit iOS-App.
- **Deploy-Check:** `curl https://<host>/version` (SHA-Match) + `curl https://<host>/healthz`.
- **Backup/Restore:** `scripts/backup.sh` (DB `VACUUM INTO` + Media-Tar) / `restore.sh`; im Runbook dokumentiert.
- **Secrets** nur via Coolify-Env / `.env` (nie committen): `OPENAI_API_KEY`, `TELEGRAM_*`, `HOME_ASSISTANT_*`, `SENTRY_DSN`, `SESSION_SECRET`, `ADMIN_PASSWORD`/Bootstrap-API-Key, optional `UNIFI_*`, `CALIBRE_URL`.

---

## 9. Self-Learning / Session-Kontinuität (Referenzmuster)

- **`CLAUDE.md`** als Projekt-Anker: `▶️ WIEDERAUFNAHME`-Block (wo stehen wir), Spezifikation, Arbeitskonventionen, datierte `Update N`-Dev-Log-Einträge mit **Lessons**, `Nächste Schritte`, `[[memory]]`-Verlinkung, **graphify**-Abschnitt.
- **Persistentes Memory:** `~/.claude/projects/C--bin-familienplaner-app/memory/` mit `MEMORY.md`-Index; **pro Session** ein `session-YYYY-MM-DD*.md` (getan/entschieden/gelernt, Live-Quirks, nächste Schritte).
- **Phasenabschluss:** via **`/beenden`** — Session-Log schreiben, `WIEDERAUFNAHME` aktualisieren, committen + pushen (Push deployt via Coolify).
- **graphify:** `graphify-out/` + post-commit-Hook; bei Codebasis-Fragen zuerst den Graph nutzen; nach Doku-Änderungen `/graphify --update`.
- **Konvention:** Code Englisch; Doku/Kommentare/Commits Deutsch wo sinnvoll; jede Phase lauffähig committen und nach Push per `/version` verifizieren.

---

## 10. Phasenplan (jede Phase lauffähig + deploybar)

| Phase | Inhalt | Ergebnis / Verifikation |
|---|---|---|
| **P0 — Fundament** | Monorepo-Skelett, `git init` + Remote `petzi0815/…`, `CLAUDE.md`, `.env.example`, `.gitignore`/`.dockerignore`, **Dockerfile + compose**, `/healthz` + `/version`, Sentry + Logger + Ring-Buffer + `/api/v1/debug/logs`, `ci.yml`, Coolify-Doku, README. | Leere-aber-**live** Shell auf Coolify; `/version` == SHA; `/healthz` ok. |
| **P1 — DB & Migration** | Konsolidiertes Schema + Migrations-Runner; `import-legacy.ts` (12 SQLite + `vertraege.json` → 1 DB, **IDs erhalten**); `import-media.ts` + Pfad-Rewrite; `verify-import.ts` (Row-Counts vs. `DATABASES.md`); Backup/Restore. | Ein `familienplaner.db` mit korrekten Row-Counts; Media unter `/data/media`; FTS neu aufgebaut. |
| **P2 — API-Framework** | Base-Utils (Validierung, Pagination, Fehler, Dry-Run), Auth (API-Keys + Rollen + UI-Login), OpenAPI-Generator + Swagger-UI, Agent-Endpunkte (`capabilities`/`query`/`action`), `search`, `dashboard/today`, `reminders/due`, `config` + `lebensbereiche` + `debug`. | `/api/v1/docs` erreichbar; `agent/capabilities` liefert Index; Auth greift. |
| **P3 — Domänen** | Je Domäne: Repo/Service auf konsolidierte DB, `/api/v1/<domain>`-CRUD, bestehende **UI-Seiten** an v1 anbinden, Media. In Wellen (parallelisierbar per Workflow). | Alle ~13 Bereiche in UI + API funktionsfähig; Contract-Tests grün. |
| **P4 — Jobs** | Job-Registry + `job_runs` + `POST /jobs/<name>/run` + node-cron; Cron-Migration; Notify-Adapter (env-gated OFF). | Jobs idempotent, mit Run-Logs; Termin-Reminder DB-basiert. |
| **P5 — Härtung & Abschluss** | Contract-/Import-Tests vollständig, OpenAPI-Vollständigkeit, Security-Review, Dev- + Prod-Runbook, Backup/Restore-Doku, **graphify-Graph**, Session-Log/Self-Learning, `ios-app/`-Scaffold + disabled `ios.yml`. | Grüner CI, dokumentiert, iOS-ready, `/beenden`-Abschluss. |

**Reihenfolge Domänen-Wellen (P3):**
1. Termine, Reisen (höchste Ole-Priorität, Reminder-relevant)
2. Samu-Inventar (items/marken/bedarf), Wunschliste, Geschenkplaner
3. Garten, Vorratskammer, Gypsi, Reiniger
4. Elisbooks, E-Book-Downloader, Smart-Home, Verträge

---

## 11. Design

Beibehaltung der bestehenden **iOS-Designsprache** (SF-Font, Apple-Systemfarben `#007AFF/#34C759/#FF9F0A/#AF52DE…`, Gradient-Kacheln, Rundungen, `active:scale`-Interaktionen, Safe-Area, PWA). Dashboard-Kacheln künftig **datengetrieben** aus `lebensbereiche`. Alle Masken responsive/mobil-first (ist bereits so angelegt). Keine Orientierung am Referenzprojekt-Design.

---

## 12. Risiken & Gegenmaßnahmen

| Risiko | Gegenmaßnahme |
|---|---|
| `better-sqlite3` (nativ) im Next-standalone-Docker | Runtime-Rebuild im Dockerfile, `output: 'standalone'` + `serverExternalPackages`, Smoke-Test im CI. |
| ID-/Beziehungsverlust bei Konsolidierung | Namespacing + ID-erhaltender Import + `verify-import.ts` (Row-Counts) + Backups vor jedem Schritt. |
| Kaputte Bildpfade | Zentrales `media_assets`-Mapping + Rewrite + Fallback-Route mit Logging. |
| Öffentliche Erreichbarkeit | Auth-Middleware ab P2, `/healthz`/`/version` als einzige offene Endpunkte, Secrets nur via Env. |
| Ungewollte Deploys durch Doku-Commits | Coolify Watch Paths (Code-Pfade) — Doku/CLAUDE.md triggert kein Deploy. |
| Telegram-Fehlsendungen | Notify standardmäßig AUS, erst mit gesetzter Topic-Config aktiv; Dry-Run. |

---

## 13. Offene Punkte (vor/za Beginn zu klären, blockieren P0 nicht)

- **Domain** für Coolify (z.B. `familie.paetzold.name`/`.app`?) → für OpenAPI-Server-URL, CORS, iOS.
- **GitHub-Push-Auth** (gh-Token/Coolify-GitHub-App vorhanden?).
- **UI-Login-Modell:** ein Familien-Passwort oder Nutzer (Lars/Elita) getrennt?
- **Verträge**: gewünschtes Zielschema (aus `vertraege.json` + AGENTS.md-Felder ableitbar) bestätigen.
