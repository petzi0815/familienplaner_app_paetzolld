# CLAUDE.md — Familienplaner (Paetzold-Stilke)

> Anker-Dokument für Session-Kontinuität. Hier steht **wo wir stehen**, die Spezifikation und
> die Arbeitskonventionen. Bei neuer Session: dieses File zuerst lesen, dann das Session-Memory
> (`~/.claude/projects/C--bin-familienplaner-app/memory/`, Index `MEMORY.md`).

## ▶️ WIEDERAUFNAHME (nächste Session) — START HIER

**Stand (2026-07-12, HEAD `312a8a8`): Backend + iOS LIVE — NEU: Abfuhrkalender (Müll-Termine) komplett + Legacy-Backup Supabase/Lovable gesichert.** `https://familienplaner.yagemi.app`.

**NEU 2026-07-12 — Abfuhrkalender + Legacy-Backup (Details: [[session-2026-07-12_abfuhr-und-backup]]):**
- **Abfuhrkalender** neuer Lebensbereich: Backend (`server/abfuhr/*`, Routen `/abfuhr/{import-ics,next,sync-aha,calendar}`,
  Migration 0008/0009, Jobs `abfuhr-reminder` 19-Uhr-Vorabend + `abfuhr-aha-sync` monatlich) + **aha-region.de Auto-Sync**
  (3-Schritt-Formular, kein jährliches ICS-Upload; live 37 Termine) + iOS Heute-Karte + **native Kategorie-Ansicht**
  `Views/AbfuhrCalendarView.swift` (Bereich `abfuhrkalender`→native). Lokale Vorabend-Erinnerung 19 Uhr (offline).
- **Legacy-Backup** (Lars will Lovable+Supabase löschen): `_reference/elisbooks-original-backup-20260712/` — pristine
  Supabase (Daten 346/7/5/5 + 8 Migrationen + 5 Edge Functions inkl. **canopy-proxy** = nie migriert) + kompletter
  Lovable-Quellcode (264 Dateien). **Migration 1:1 verifiziert** (IDs identisch, 0 Verlust). ⚠️ `_reference/` git-ignored →
  Backup NUR lokal. **OFFEN: Lars fragen ob off-site ins Git committen** (`git add -f …`), DANN darf er löschen.
- **OFFEN (nur Todo, NICHT umsetzen bis Lars startet):** Per-User-Login-Keys für Lars & Elita statt Oles Shared-Key
  → Geräte-Zuordnung + gezielte Push (nur an Foto-Uploader). Spec: [[todo-per-user-login-keys]].

**Stand (2026-07-12, HEAD `1c0f82c`): Backend LIVE + nativer ElisBooks-Bücherbereich in iOS (Build 7, inkl. KI-Metadaten/Dubletten/Export/Einstellungen).** OpenAI live verifiziert (recommendations/cleaner ok); Menü-Config-Gating gebaut.

**NEU 2026-07-12 — Nativer ElisBooks-Bereich in iOS (Details: [[reference-elisbooks-original-app]]):**
- Elitas Lovable/Supabase-Bücher-App **nativ nachgebaut** (ersetzt den generischen Browser für `elisbooks`), Backend =
  Familienplaner-v1-API. Modul `ios-app/App/Sources/Books/`: Regale-CRUD, Bibliothek (Raster/Liste, Suche, Filter,
  Sortierung, Bulk), Detail/Bearbeiten, Scanner (einzeln/bulk), manuelle Suche, Wunschliste, Vorschläge (lokal+OpenAI), KI-Regalscan.
- Backend v1: `POST /elisbooks/books-bulk` + `/elisbooks/ai/{shelf-ocr,recommendations}` (OpenAI, **token-gated** → 501
  ohne `OPENAI_API_KEY`). **Lars muss `OPENAI_API_KEY` in Coolify setzen** für Regalscan + KI-Empfehlungen.
- **Standing Order:** Fokus iOS, **PWA pausiert** ([[feedback-fokus-ios-pwa-pausiert]]). Noch offen (nächste iOS-Builds):
  Tabellenansicht/Pagination, Multi-Source-Metadaten, KI-Cleaner/Enhancer, Dubletten-Finder, Export/PDF, Einstellungen.

**NEU 2026-07-12 — iOS-Bücher-Handoff + Migrations-Parität (Details: Memory [[reference-elisbooks-original-app]]):**
- **iOS „Buch scannen"** legt jetzt den VOLLEN Datensatz an wie die Original-Bücher-App: Google-Books-Anreicherung
  (Verlag/Datum/Beschreibung/Seiten/Kategorien/Sprache/Cover, Open Library Fallback) + **Regal-Auswahl** +
  Lesestatus; authors/categories als JSON, publisher-Fallback „Unbekannter Verlag". Redundante „Foto aufnehmen"-Kachel raus.
- **Elitas Original-App validiert** via Supabase-Connector (Projekt `ldbzlizkgsdoxxjceuao`): Schema + Row-Counts
  (346 books/7 shelves/5 wishlist) 1:1 zu Oles Port; 4/5 Edge Functions migriert — **`canopy-proxy` (Amazon-Empfehlungen)
  fehlt**; das reiche Lovable-**Frontend** ist im neuen App noch NICHT nachgebaut (nur generischer Browser).

**NEU 2026-07-12 — Fotobox (Details: Memory [[session-2026-07-12_fotobox]]):**
- **Strukturierte Foto-Queue** als 2. Eingangskanal neben Telegram. Ole: `GET /api/v1/fotobox-items?status=pending`
  → `POST /{id}/claim` → Medien via `item.media[].url` → `GET /<target_resource>/schema` → Write → `POST /{id}/result`.
- **Erweiterbare Wertebereiche** (domain/intent/status/review_reason/target_resource) in `fotobox_labels` (kein CHECK) —
  neue Werte via `POST /api/v1/fotobox-labels`. Item-Validierung läuft dynamisch dagegen. Migration `0007_fotobox`.
- **iOS-Fotobox**: nach dem Foto Domäne (On-Device-KI-Vorschlag/Auswahl) + **kontextabhängige Dropdowns mit gültigen
  Werten** je Domäne (aus `GET /fotobox-items/form-config`: enum strikt, sonst reale DISTINCT-Werte). Save → fotobox-item.
- **OpenAPI**: `https://familienplaner.yagemi.app/api/v1/docs` (Swagger) / `/api/v1/openapi.json` — für Ole zum Testen.
- Verifiziert: Runtime-Smoke (create/claim-409/result/label-extend→neue Domain nutzbar/media/idempotenz/schema/form-config) + iOS-Build-Check grün.

**NEU 2026-07-12 — Bespoke-Ports (Details: Memory [[session-2026-07-12_bespoke-ports]]):**
- **Alle fehlenden Original-Bereichsseiten 1:1 nachgezogen** (vorher nur generischer Browser): Samu, Garten, Geschenkplaner,
  Termine, Vorratskammer, Wunschliste, Gypsi, Reiniger, Buecher, Smart Home, Vertraege (Reisen war schon davor).
- **Muster: Kompat-API-Layer** (`server/legacy/*-db.ts` + `app/api/<bereich>/*`) spiegelt die Original-Endpunkte
  (`?stats/?matrix/?mode=month/…`) gegen die konsolidierte **Singleton-DB** (`getDb()`, **nie `close()`**), Tabellen praefixiert;
  Auth via `guard()` (lesen=readonly, schreiben=agent) wie v1. Seiten **verbatim** kopiert, nur Bild-URLs → `/api/v1/media/<key>`.
  Externe KI/Netz/HA-Endpunkte → **501 `notMigrated`** (buecher search/download/retry/enrich, wunschliste enrich/scrape/pricecheck,
  smarthome exec/ask/prompt). Portal verlinkt alle via `BESPOKE_HREF`.
- **Verifiziert:** `next build` grün + **Runtime-Smoke 43/43 Endpunkte 200** (echter `next start` gegen Seed-DB) + Prod-Sanity
  (401-gated, 501-Stubs, `/samu`→307). iOS: neues `FieldFormat .keyValue` rendert JSON-Objekt-Spalten (z.B. `ha-entities.attributes`)
  als Key/Value statt Rohtext; Build-Check + TestFlight **beide success**.
- **Lernpunkt:** Next 16 lintet NICHT mehr im `next build` (kein `eslint`-Feld im `NextConfig`-Typ) → 1:1-Legacy-Ports mit
  `any`/`<img>` bauen sauber durch; tsc bleibt das Gate.

**NEU 2026-07-11 (Details: Memory [[session-2026-07-11_part2]] + [[familienplaner-ios-app]]):**
- **MCP-Server** `POST /api/mcp` (Streamable HTTP, gleicher Agent-Key wie REST, 14 generische Tools; `docs/MCP.md`).
- **iOS-App komplett auf iOS 26** (Liquid Glass, Barcode-Scanner ISBN/EAN, On-Device-KI Foto-Vorschlag [Vision+FoundationModels],
  EventKit-Kalender, lokale Erinnerungen, MapKit-Reisen, Siri-Kurzbefehle, WidgetKit-Widgets) + **Bereiche-Browser**
  (alle Lebensbereiche durchnavigieren, datengetrieben aus `/agent/capabilities`; Liste/Bildraster/Detail + Schnellaktionen).
- **CI-Pipeline live:** `.github/workflows/ios-build.yml` (Compile-Check ohne Signing) + `ios.yml` (signierter TestFlight-Upload,
  Build-Nr = run_number). Apple-Provisioning **komplett autonom via ASC-API** (Node ES256-JWT, kein fastlane): Bundle-IDs,
  frisches Cert `A7DKJCU523`, 2 Profile, alle GH-Secrets/Vars. App-Record `6789983007`, App Group `group.app.yagemi.familienplaner` live.

**Migration P0–P5 (Basis):** konsolidierte SQLite (Seed-on-Boot), generische v1-API (~48 Ressourcen), rollenbasierte Auth,
Agent-Endpunkte, Suche/Dashboard/Reminders, Jobs, **FTS5**, Bild-Upload, Reise-Docs, Sentry-Wiring, OpenAPI, graphify. Details: [[session-2026-07-11]].

**Offen (Lars, extern — kann ich nicht):** Coolify **`APNS_*`** (5 Vars, Block geliefert) + Redeploy → dann `GET /api/v1/push/status`;
optional **`SENTRY_DSN`** (Projekt `yagemi/familienplaner`); TestFlight interne **Tester** eintragen. Sonst sauberer Stand.

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

### Update 12 (2026-07-12) — iOS-Bücher-Handoff 1:1 + Fotobox-Kachel-Aufräumen + Original-App-Parität
- **`897595b` (iOS Build 5):** „Buch scannen" legt den VOLLEN elisbooks-books-Datensatz an wie die Original-App:
  `ProductLookup.book` → Google Books zuerst (Verlag/Datum/Beschreibung/Seiten/Kategorien/Sprache/Cover), Open Library
  Fallback; `BookScanSheet` mit Verlag-Feld, **Regal-Picker** (`elisbooks-bookshelves`), Gelesen-Toggle; authors/categories
  als JSON, publisher-Fallback „Unbekannter Verlag", is_read/is_on_picklist, bookshelf_id. `APIClient.bookshelves()` +
  `Models.Bookshelf`. Runtime-Smoke (create voller Feldsatz + FK-Regal + readback + delete) grün. Redundante
  „Foto aufnehmen"-Kachel im Erfassen-Hub entfernt (Fotobox übernimmt).
- **Migrations-Parität** via Supabase-Connector geprüft (Elitas Original, Projekt `ldbzlizkgsdoxxjceuao`): Schema +
  Row-Counts 1:1; **`canopy-proxy` (Amazon-Empfehlungen) nicht migriert**; Lovable-Frontend im neuen App noch nicht nachgebaut.
  **Lesson:** unsere `elisbooks_*`-IDs sind ID-erhaltend = identisch mit Supabase (Regal-FKs matchen direkt). Details [[reference-elisbooks-original-app]].

### Update 11 (2026-07-12) — Fotobox: strukturierte Foto-Queue + erweiterbare Enums + iOS-Picker
- **API (`5696b71`, live):** `fotobox-items`-Queue + Lifecycle (`/claim` [409-Lock], `/result`, `/fail`, `/approve`,
  `/reject`, `/media`(+`/{mediaId}`)), idempotente Erstellung (inline media base64), nested API-Shape (`uploaded_by`/
  `routing`/`review`/`processing`/`result`). **Wertebereiche dynamisch** aus `fotobox_labels` → per API erweiterbar
  (`POST /fotobox-labels`), Validierung dagegen (server/fotobox/{labels,store,lifecycle,formconfig}.ts). Migration `0007`.
  `GET /fotobox-items/schema` = label-aware allowed + domain→target-Mapping; `GET /fotobox-items/form-config` =
  kontextabhängige Vorschlagsfelder je Domäne (enum aus CHECK, sonst reale DISTINCT-Werte der Zielressource).
  capabilities + OpenAPI dokumentiert.
- **iOS (`f1700bf`, Build-Check grün):** `FotoboxView` — Foto → Domäne (On-Device Vision+FoundationModels-Vorschlag,
  auf gültige Domänen beschränkt, oder manuell) → **kontextabhängige Dropdowns** (datengetrieben aus form-config,
  passen sich an die Domäne an; enum strikt, suggest frei ergänzbar) → `analysis_hint` + Foto → `POST /fotobox-items`.
  Eintrag im Erfassen-Hub. Models/APIClient erweitert.
- **Lessons:** (1) Erweiterbare Enums NICHT als CHECK (nicht runtime-änderbar) → Label-Tabelle + dyn. Validierung.
  (2) Explizite statische Routen (`app/api/v1/fotobox-items/*`) überschreiben das generische `[domain]` — Registry-Eintrag
  nur für capabilities/OpenAPI; generische Writes scheitern fail-safe (TEXT-PK ohne Default). (3) form-config aus echten
  DISTINCT-Werten hält die iOS-Dropdowns automatisch valide + aktuell.

### Update 10 (2026-07-12) — Alle 12 bespoke Bereichsseiten 1:1 portiert (Kompat-API-Layer) + iOS JSON-Felder
- **11 Lebensbereiche 1:1 aus dem Original nachgezogen** (`92a49fd`, live `611c193`): Samu, Garten, Geschenkplaner, Termine,
  Vorratskammer, Wunschliste, Gypsi, Reiniger, Buecher, Smart Home, Vertraege. Vorher hatten diese nur den generischen
  `ResourceBrowser`; jetzt die originalgetreuen, funktionsreichen Seiten (Matrix/Stats/Kalender/GTS/Vergleiche …).
- **Architektur „Kompat-API-Layer"** statt Seiten auf v1 umzuverdrahten: pro Bereich `server/legacy/<bereich>-db.ts`
  (Original-Lib, aber Verbindung = geteiltes `getDb()`-Singleton, **alle `db.close()` entfernt**, Tabellen praefixiert) +
  Kompat-Routen unter `app/api/<bereich>/*` (spiegeln die Original-Endpunkte + Spezialmodi 1:1, `guard()`-Auth). Seiten
  **verbatim** kopiert; einzige Änderung: Bild-URLs `/api/images|/api/<bereich>/images` → `/api/v1/media/<key>`.
  Externe KI/Netz/HA-Endpunkte → **501** (`notMigrated`, `server/legacy/compat.ts`). Vertraege = statische Seite + `data/vertraege.json`.
- **Umsetzung:** Samu als Referenz-Port selbst gebaut + verifiziert (Blueprint), dann 9 Bereiche **parallel via Subagenten**
  (jeder: Lib+Routen+Seite, SQL gegen Seed-DB geprüft, kein Build). 1 finaler `next build` + **Runtime-Smoke 43/43 200**
  (echter Server gegen Seed-DB) + Prod-Sanity. **Lessons:** (1) Next 16 lintet nicht im Build → Legacy-`any`/`<img>` ok, tsc bleibt Gate.
  (2) `getDb()` ist Singleton → Ports **dürfen nie `close()`**. (3) Original-Libs hatten teils `CREATE TABLE`-Bootstrap → entfernt
  (konsolidierte DB ist migriert). (4) Original-Bild-Keys sind bereits `<bereich>/<datei>` → passen direkt auf `/api/v1/media`.
- **iOS** (`611c193`): neues `FieldFormat .keyValue` + `parseJSONObject` — JSON-Objekt-Spalten (`ha-entities.attributes` u.a.)
  werden als saubere Key/Value-Zeilen statt roher `{…}`-String gezeigt; `guessFormat` erkennt `{…}` automatisch. Build-Check + TestFlight success.

### Update 9 (2026-07-11) — MCP-Server + iOS-26-Ausbau + TestFlight LIVE + Bereiche-Browser
- **MCP-Server** `POST /api/mcp` (`d5deae5`): dünner Adapter über crud/queries, 14 generische Tools, Auth = Agent-Key.
  Geteilte Query-Logik nach `server/domains/queries.ts` (REST+MCP). Doku `docs/MCP.md`.
- **iOS-App auf iOS 26** (Target 17→26, mehrere Commits bis `e5f6ddc`): Liquid Glass Tab-Bar, Barcode-Scanner (ISBN→Open
  Library, EAN→Open Food Facts), **On-Device-KI** (Vision + FoundationModels) Foto-Bereichsvorschlag, EventKit-Kalender,
  lokale Erinnerungen, MapKit-Reisen, ausgebaute Siri-Intents, **WidgetKit-Widgets** (App Group), **Bereiche-Browser**
  (`Bereiche.swift`/`ResourceBrowser.swift`, datengetrieben aus `/agent/capabilities`).
- **CI**: `ios-build.yml` (signaturfreier Compile-Check — fing einen dt.-Anführungszeichen-Bug, den 2 Review-Subagenten
  übersahen → [[feedback-swift-string-literals-ci]]) + `ios.yml` aktiviert (TestFlight, Build 1+2 live).
- **Apple-Provisioning autonom via ASC-REST-API** (Node ES256-JWT, kein fastlane/kein Mac): Bundle-IDs+Caps, frisches
  Cert `A7DKJCU523` gemintet (alter `.p12` nicht auslesbar), 2 Profile, alle GH-Secrets/Vars. **Lesson:** App-Record
  (`POST /v1/apps`=FORBIDDEN) + App-Group brauchen zwingend Apple-2FA — kein Key umgeht das.
- Coolify-APNs-ENV-Block an Lars geliefert (Werte team-weit aus Referenz-`.env`, nur `APNS_BUNDLE_ID` abweichend).

### Update 8 (2026-07-11) — iOS UI/UX-Ausbau (frohe Farben + native Funktionen)
- **Design-System (`Theme.swift`):** `Color(hex:)`, `Palette` mit frohen Verläufen je Lebensbereich
  (1:1 zur Web-App), `BereichChip` (ausgewählt = Verlauf), `GradientButtonStyle`, farbiges `BrandMark`.
- **CameraView neu:** buntes Hero (Symbol-`.pulse`), Kamera + **PhotosPicker**, horizontale bunte
  **Bereichs-Chips**, Verlaufs-Upload-Button, **Haptik** (`.sensoryFeedback`) + Symbol-Effekte
  (`.bounce` bei Erfolg), Verlaufs-Hintergrund je Bereich.
- **InboxView neu:** **Foto-Grid** (LazyVGrid) mit Status-Punkten + Bereichs-Chips (ultraThinMaterial),
  Detail-Sheet mit großem Bild; farbige Leerzustände.
- **iOS-native Extras:** **Siri/Kurzbefehl** („Foto zum Familienplaner hinzufügen", `AppIntents.swift`
  + `AppShortcutsProvider`), **Home-Screen-Quick-Action** („Foto aufnehmen", Info.plist + AppDelegate),
  PhotosPicker, Haptik, SF-Symbol-Effekte.
- **Review (Subagent): 0 Blocker/baubar** (iOS-17-APIs: AnyShapeStyle, sensoryFeedback, symbolEffect,
  PhotosPicker, .onChange 2-Param, AppShortcuts alle korrekt). Kompilierung im CI.

### Update 7 (2026-07-11) — APNs-Push (Backend + iOS) + App-Icon + TestFlight-Prep
- **APNs-Push-Backend:** `server/push/apns.ts` — token-basiert (ES256-JWT via `crypto.sign` dsaEncoding
  ieee-p1363 = 64-Byte-Sig, verifiziert; Provider-Token ~40 min gecacht) + **HTTP/2** (`node:http2`) an
  api.push.apple.com; tote Tokens (410) werden entfernt. Migration 0005 `device_tokens`. Endpunkte
  `POST/DELETE /api/v1/push/register`, `POST /api/v1/push/send` (agent), `GET /api/v1/push/status` (admin).
  **Auto-Push** wenn `foto-inbox`→`zugeordnet` (Hook in der `[id]`-PATCH-Route). Token-gated (kein Key → No-Op).
  Config: `APNS_KEY_P8/KEY_ID`, `APPLE_TEAM_ID`, `APNS_BUNDLE_ID`. **Key ist team-weit → aus Referenz-.env
  wiederverwendbar, nur Bundle-ID (=apns-topic) unterscheidet sich.** Lokal verifiziert (register/status/send/hook/delete).
- **iOS-Push:** `AppDelegate` (Token-Registrierung → `POST /push/register`, `#if DEBUG`→sandbox/production),
  `@UIApplicationDelegateAdaptor`, `requestPushAuthorization` in MainTabView, `aps-environment: production`
  im project.yml-Entitlement (gitignored, xcodegen-generiert).
- **App-Icon** neu gestaltet (Haus + Kamera-Linse auf Blau→Indigo-Verlauf, 1024px, via System.Drawing).
- **TestFlight-Prep:** `ios-app/tools/prepare-signing.sh` (base64 + gh-Befehle); Doku `docs/IOS.md`
  (Push-Env, reusable team-weite Keys, Apple-Push-Capability).
- **Lesson:** APNs braucht HTTP/2 → `node:http2` (globales fetch/undici macht kein HTTP/2 zu Apple).

### Update 6 (2026-07-11) — iOS-App + Foto-Inbox-Feature
- **Foto-Inbox (Backend, `4fe7024`, live):** Migration 0004 `foto_inbox` (storage_key, bereich, status
  neu/in_bearbeitung/zugeordnet/verworfen, notiz, analyse, zugeordnet_resource/id) + Dashboard-Kachel.
  `POST /api/v1/foto/upload` (multipart **oder** JSON-Base64) → Datei nach media/foto-inbox/ + Eintrag `neu`.
  Ressource `foto-inbox` im generischen CRUD. Agent-Workflow: `GET ?status=neu` → analysieren →
  `PATCH {status:zugeordnet,…}` (+ Bild via /media/upload {resource,id} anhängen). Lokal verifiziert.
- **iOS-App (`ios-app/`, native SwiftUI, iOS 17+):** Login (Base-URL+API-Key, Keychain) → TabView Foto/Inbox/
  Einstellungen. Kernfeature: `UIImagePickerController` (Kamera/Mediathek) → `jpegForUpload` → multipart an
  `/api/v1/foto/upload` mit Bereich-Picker (aus `/lebensbereiche`). Inbox mit auth-bewussten Thumbnails.
  Muster (Keychain, API-Client, Multipart, xcodegen/fastlane) via Workflow aus dem Referenzprojekt extrahiert.
  Build: xcodegen + fastlane → TestFlight (`.github/workflows-disabled/ios.yml`, `docs/IOS.md`).
  **Review (Subagent): 0 Blocker, baubar.** Kann hier nicht kompiliert werden (kein Mac) → Validierung im CI.
  **Lesson:** „APN Punkte" (Lars) = API-Punkte/Endpunkte, kein Push nötig.

### Update 5 (2026-07-11) — Ole-Testfeedback-Fix + Sentry-Projekt
- **Create-500-Bug gefixt (`f99ab4d`, live):** Ole-Abnahmetest — create bei `garten-duenger`,
  `vorrat-lebensmittel`, `geschenk-anlaesse`, `geschenk-geschenke` endete mit **leerem HTTP 500**.
  Ursache: **CHECK-Constraints** (enum-Spalten typ/kategorie/anlass/status); dry_run ging durch, echter
  INSERT knallte unbehandelt. Fix: `server/db/constraints.ts` liest `CHECK(col IN (...))`; `crud.ts`
  validiert Enums VOR dem Insert (auch im dry_run → konsistent) → 422 `{code:invalid_value, details:{column,allowed}}`;
  alle DB-Writes in try/catch → saubere JSON-Fehler (check/not_null/foreign_key/unique/db_error), **nie leerer 500**;
  `/schema` liefert jetzt `allowed`. Prod verifiziert (invalid→422, valid→201, Cleanup).
  **Lesson:** generisches CRUD über echte Tabellen braucht Constraint-bewusstes Error-Mapping — sonst
  werden legitime DB-Constraints zu undurchsichtigen 500ern.
- **Sentry-Projekt angelegt:** Org `yagemi` (EU) → Projekt `familienplaner` (slug), Plattform `javascript-nextjs`,
  via Sentry-API mit dem PAT aus dem Referenzprojekt. DSN per Test-Event verifiziert. App-Wiring
  (instrumentation.ts + onRequestError) existiert schon → nur `SENTRY_DSN` in Coolify setzen. Details [[session-2026-07-11]].

### Update 4 (2026-07-11) — Nacharbeiten: FTS5, Uploads, graphify (LIVE)
- **FTS5 (Migration 0003):** einheitlicher `fts_index`, ins generische CRUD integriert (Reindex bei
  create/update/delete), Boot-Aufbau; `/search` nutzt FTS (LIKE-Fallback). Prod: `engine:fts5`, korfu 41 Treffer.
- **Uploads/Sonderlogik:** `POST /api/v1/media/upload` (Bild → storage_key) + Upload-Button im ResourceBrowser;
  `GET/POST /api/v1/files/reisen-docs[/{id}]` (BLOB-Download/Upload); Schnellaktionen (Status-PATCH) im Detail.
  Prod verifiziert (PDF-Download id 13 → 200/130 KB).
- **graphify:** `graphify-out/` generiert (AST-only, 0 Tokens; 221 Nodes/805 Edges/15 Communities). God-Nodes
  `getDb/getAuth/hasRole/ok/fail`. **Lesson (Windows):** graphify-Reports mit `PYTHONUTF8=1` schreiben (cp1252
  scheitert an `→`); auf `apps/web/src` zielen (nicht Repo-Root — sonst 808 Media-Bilder als Vision-Chunks).

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
