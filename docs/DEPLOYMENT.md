# Deployment — Coolify + GitHub

Push auf `main` → Coolify rebuildet + deployt automatisch (Coolify GitHub App).

## Coolify-App einrichten (einmalig)

1. Coolify → Projekt anlegen (z.B. „Familienplaner") → **+ New → Private Repository (GitHub App)**
   - Repository: `petzi0815/familienplaner_app_paetzolld`, Branch **`main`**
   - Build Pack: **Dockerfile** (Root-[`Dockerfile`](../Dockerfile)), Port **3000**
2. **Domain:** die gewünschte URL setzen (Traefik/SSL macht Coolify; DNS-A-Record auf die
   Server-IP). Denselben Wert als Env `PUBLIC_BASE_URL` eintragen.
3. **Persistentes Volume:** *Storages* → + Add → Destination **`/data`**
   (enthält `familienplaner.db` + `media/` — überlebt Redeploys).
4. **Environment Variables:** siehe [`.env.example`](../.env.example). Minimal für den Start:
   `PUBLIC_BASE_URL`, `ADMIN_PASSWORD`, `SESSION_SECRET`. Optional: `SENTRY_DSN`,
   `BOOTSTRAP_AGENT_API_KEY`, `OPENAI_API_KEY`, `TELEGRAM_*`, `HOME_ASSISTANT_*`.
5. Optional **Watch Paths** (ein Pattern pro Zeile!): `apps/web/**`, `Dockerfile`, `db/**`,
   `package.json`, `package-lock.json` — dann triggern reine Doku-/CLAUDE.md-Commits KEIN Deploy.

Coolify liefert `SOURCE_COMMIT` als Build-Arg; das Dockerfile mappt es auf `APP_GIT_SHA`.

## Deploy-Verifikation

```bash
curl https://<host>/healthz     # -> ok
curl https://<host>/version     # -> { "commit": "<kurz-SHA>", ... }
curl https://<host>/api/v1      # -> API-Index
# Log-Ringpuffer (admin):
curl -H "Authorization: Bearer $ADMIN_PASSWORD" "https://<host>/api/v1/debug/logs?lines=100"
```

`commit` muss dem gepushten Kurz-SHA entsprechen.

## Lokale Produktions-Parität

```bash
docker compose up --build
curl localhost:3000/healthz
```

## Backup / Restore

Ab Phase 1: `scripts/backup.sh` sichert `familienplaner.db` (`VACUUM INTO`) + `media/` als Tar;
`scripts/restore.sh` spielt zurück. Im Coolify-Terminal gegen das `/data`-Volume ausführbar.
