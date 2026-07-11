# Familienplaner API (v1)

API-first: die Web-UI, der Agent „Ole" und später die iOS-App nutzen dieselbe REST-API.
Basis: `https://familienplaner.yagemi.app/api/v1` · OpenAPI/Swagger: `/api/v1/docs` · Spec: `/api/v1/openapi.json`

## Authentifizierung

- **Agent/Programme:** `Authorization: Bearer <API-Key>` (Rolle `agent` oder `admin`).
  Der Bootstrap-Key wird aus `BOOTSTRAP_AGENT_API_KEY` beim Start angelegt.
- **Web-UI:** Familien-Passwort-Login (`POST /api/v1/auth/login`) → Session-Cookie.
- Rollen: `readonly` < `agent` < `admin`. Lesen braucht `readonly`+, Schreiben `agent`+, Config/Debug `admin`.
- Offen (ohne Auth): `/healthz`, `/version`, `/api/v1`, `/api/v1/openapi.json`, `/api/v1/docs`, `/api/v1/auth/login`.

## Generisches CRUD (jede Ressource)

`<key>` ist eine der ~48 Ressourcen (siehe `GET /api/v1/agent/capabilities`), z.B.
`termine`, `reisen`, `samu-items`, `garten-pflanzen`, `vertraege`, `geschenk-geschenke`, …

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/api/v1/<key>` | Liste — `?spalte=wert`, `?search=`, `?sort=spalte:asc\|desc`, `?limit=`, `?offset=` |
| POST | `/api/v1/<key>` | Anlegen (JSON-Body) — `?dry_run=1` für Vorschau |
| GET | `/api/v1/<key>/{id}` | Detail |
| PATCH | `/api/v1/<key>/{id}` | Ändern — `?dry_run=1` |
| DELETE | `/api/v1/<key>/{id}` | Löschen — `?dry_run=1` |
| GET | `/api/v1/<key>/schema` | Spalten/Typen |
| POST | `/api/v1/<key>/import` | Bulk-Import (Array oder `{items:[...]}`) |

Bild-Ressourcen liefern zusätzlich aufgelöste URLs (`<spalte>_url` / `<spalte>_urls`), auslieferbar über `/api/v1/media/<key>`.

## Agentenfreundliche Endpunkte

| Pfad | Zweck |
|---|---|
| `GET /api/v1/agent/capabilities` | Maschinenlesbarer Index (Domänen, Ressourcen, Spalten, Konventionen) |
| `POST /api/v1/agent/query` | Strukturierte Suche: `{ resource, filters, search, sort, limit, offset }` |
| `POST /api/v1/agent/action` | Validierte Aktion: `{ action:create\|update\|delete, resource, id?, data?, dry_run? }` |
| `GET /api/v1/search?q=&domains=` | Cross-Domain-Volltextsuche |
| `GET /api/v1/dashboard/today` | Kompakter Tageszustand |
| `GET /api/v1/reminders/due` · `POST /api/v1/reminders/{id}/sent` | Fällige Termin-Erinnerungen |
| `GET/PUT /api/v1/config` | Runtime-Settings (admin) |
| `GET /api/v1/jobs` · `POST /api/v1/jobs/{name}/run?dry_run=1` | Jobs auflisten/auslösen |

## Beispiele

```bash
KEY="<agent-key>"; B="https://familienplaner.yagemi.app/api/v1"
curl -H "Authorization: Bearer $KEY" "$B/agent/capabilities"
curl -H "Authorization: Bearer $KEY" "$B/termine?sort=date:asc&limit=5"
# Anlegen mit Vorschau, dann echt:
curl -H "Authorization: Bearer $KEY" -H "content-type: application/json" \
  -d '{"title":"U8","date":"2026-10-05","category":"u_untersuchung","dry_run":true}' "$B/termine"
# Job auslösen (Vorschau):
curl -H "Authorization: Bearer $KEY" -X POST "$B/jobs/termine-reminders/run?dry_run=1"
```

## Debug / Betrieb (admin)

- `GET /api/v1/debug/logs?lines=&grep=` — In-Memory-Log-Ringpuffer.
- `GET /api/v1/debug/db-stats` — Row-Counts + Migrationsstand.
- `GET/POST /api/v1/debug/backup` — DB-Backup nach `$DATA_DIR/backups/`.
- Voll-Backup (DB+Media) auf VPS: `scripts/backup.sh` · Restore: `scripts/restore.sh`.
