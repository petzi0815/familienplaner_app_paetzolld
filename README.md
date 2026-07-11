# Familienplaner — Paetzold-Stilke

API-first Familienplaner (Web + zukünftige iOS-App) für die Organisation der Familie in
Lebensbereichen: Termine, Reisen, Samu-Inventar, Wunschliste, Geschenkplaner, Garten,
Vorratskammer, Gypsi, Reiniger, Bücher, Smart Home, Verträge — offen für neue Bereiche.

Die Web-UI ist **Konsument der eigenen REST-API** (`/api/v1`). Dieselbe API bedient den
lokalen KI-Agenten „Ole" (API-Key) und später eine iPhone-App. Deployment: **Autodeploy
via GitHub-Push → Coolify**.

> **Status:** 🏗️ Phase 0 — Fundament. Projektstand & Spezifikation: [`CLAUDE.md`](CLAUDE.md) ·
> vollständiger Plan: [`docs/MIGRATION_PLAN.md`](docs/MIGRATION_PLAN.md).

## Stack

- **Next.js 16** / React 19 / TypeScript / Tailwind v4 (iOS-Designsprache, PWA)
- **SQLite** (better-sqlite3), eine konsolidierte DB unter `$DATA_DIR/familienplaner.db`
- **OpenAPI**-dokumentierte `/api/v1`-REST-API, rollenbasierter API-Key + Session-Login
- **Sentry** + strukturiertes Logging + In-Memory-Log-Ringpuffer (`/api/v1/debug/logs`)
- Docker (multi-stage, standalone) · Coolify · GitHub

## Repository-Layout

```
apps/web/            Next.js-App (UI + /api/v1 + Worker)
ios-app/             Platzhalter für die native iOS-App (später)
db/migrations/       nummerierte SQL-Migrationen (konsolidiertes Schema)
scripts/             Import (Legacy-SQLite/Media), Verify, Backup/Restore
docs/                Plan, API, DB, Deployment, Runbook
Dockerfile           App-Image (Coolify Build Pack Dockerfile)
docker-compose.yml   lokale Produktions-Parität
.github/workflows-disabled/  CI + iOS-Build (aktivieren = nach workflows/ verschieben)
```

## Lokale Entwicklung

```bash
cp .env.example .env      # Werte eintragen (ADMIN_PASSWORD, SESSION_SECRET …)
npm install
npm run dev               # http://localhost:3000
```

Produktions-Parität lokal:

```bash
docker compose up --build
curl localhost:3000/healthz     # -> ok
curl localhost:3000/version     # -> { "commit": "local", ... }
```

## Deployment

Push auf `main` → Coolify rebuildet + deployt automatisch (Build Pack Dockerfile, Port 3000,
Volume `/data`). Details: [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
Deploy-Check: `curl https://<host>/version` (commit == gepushter Kurz-SHA) + `/healthz`.
