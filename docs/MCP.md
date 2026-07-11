# MCP-Server (Model Context Protocol)

Der Familienplaner stellt neben der REST-API einen **MCP-Server** bereit — im **selben Backend/Prozess**,
kein separater Dienst, kein Extra-Deploy. MCP-fähige Agenten (Claude Desktop, Claude Code, OpenClaw/„Ole",
sofern MCP-fähig) bekommen die Fähigkeiten als typisierte Tools mit Schemas — ohne die Endpunkt-Doku in den
Prompt schreiben zu müssen.

## Endpoint & Auth

- **URL:** `https://familienplaner.yagemi.app/api/mcp`
- **Transport:** Streamable HTTP (JSON-RPC 2.0 über `POST`)
- **Auth:** `Authorization: Bearer <API-Key>` — **derselbe Key wie die REST-API** (Rolle ≥ `agent`).
  Kein separater Mechanismus. Ohne gültigen Key → HTTP 401.

Da es dieselbe Registry/dieselben Funktionen wie `/api/v1` nutzt, sind API und MCP **immer synchron**:
neue Ressource in der Registry ⇒ automatisch in `list_resources` und im `resource`-Enum der Tools.

## Tools

| Tool | Zweck |
|------|-------|
| `list_resources` | Alle Ressourcen (Lebensbereiche) + Spalten + Schreibschutz. Zuerst aufrufen. |
| `resource_schema` | Spalten, Typen, Pflichtfelder, **erlaubte Werte (Enums)** einer Ressource. Vor `create_record`. |
| `list_records` | Lesen mit Filtern, `search`, `sort`, `limit`/`offset`. |
| `get_record` | Einzelner Datensatz per `id`. |
| `create_record` | Anlegen (`dry_run` möglich). Nur beschreibbare Ressourcen. |
| `update_record` | Teil-Update (`dry_run` möglich). |
| `delete_record` | Löschen (`dry_run` möglich). |
| `search` | Ressourcenübergreifende Volltextsuche. |
| `dashboard_today` | Tageszustand: Termine, Erinnerungen, nächste Reise, Garten, MHD, Foto-Inbox. |
| `reminders_due` | Heute fällige Termin-Erinnerungen. |
| `foto_inbox_new` | Neue, unzugeordnete Fotos (Workflow siehe unten). |
| `list_jobs` / `run_job` | Hintergrund-Jobs auflisten / manuell auslösen (`dry_run`). |
| `send_push` | Alert-Push an alle iOS-Geräte (nur wenn APNs konfiguriert). |

**Schreibschutz & Validierung** laufen exakt wie in der REST-API: `readonly`-Ressourcen lehnen Schreib-Tools
mit 403 ab, CHECK-/Enum-Verstöße kommen als klare `isError`-Ergebnisse (nie leerer 500). `dry_run: true`
validiert, ohne zu schreiben.

### Foto-Workflow (für „Ole")

1. `foto_inbox_new` → neue Fotos (`status='neu'`).
2. Bild laden/analysieren (Media-URL aus dem Datensatz).
3. `update_record` `foto-inbox` `{ status:'zugeordnet', analyse, zugeordnet_resource, zugeordnet_id }`
   → löst **automatisch einen Push** an die iOS-App aus.

## Client-Konfiguration

**Claude Desktop / Claude Code** (`mcp` Server-Eintrag, HTTP-Transport):

```json
{
  "mcpServers": {
    "familienplaner": {
      "type": "http",
      "url": "https://familienplaner.yagemi.app/api/mcp",
      "headers": { "Authorization": "Bearer <DEIN_AGENT_API_KEY>" }
    }
  }
}
```

**Claude Code CLI:**

```bash
claude mcp add --transport http familienplaner https://familienplaner.yagemi.app/api/mcp \
  --header "Authorization: Bearer <DEIN_AGENT_API_KEY>"
```

## Schnelltest (curl)

```bash
BASE=https://familienplaner.yagemi.app/api/mcp
KEY=<DEIN_AGENT_API_KEY>

# 1) Handshake
curl -s $BASE -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'

# 2) Tools auflisten
curl -s $BASE -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# 3) Tool aufrufen
curl -s $BASE -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"dashboard_today","arguments":{}}}'
```
