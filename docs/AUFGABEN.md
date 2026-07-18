# Aufgaben-API (Familien-Tasks) — Knowledge für Ole

Familien-Aufgaben sind API-first. Ole (oder jedes externe Tool) kann sie über die v1-REST-API
anlegen, auflisten, ändern, abhaken und löschen. Sie erscheinen automatisch in der iOS-App im
Dashboard-Abschnitt **„Aufgaben"**.

- **Basis-URL:** `https://familienplaner.yagemi.app/api/v1`
- **Auth:** `Authorization: Bearer <AGENT_API_KEY>` (Oles Schlüssel, Rolle `agent`).
- **Ressource:** `aufgaben`

## Felder

| Feld          | Pflicht | Werte / Format | Bedeutung |
|---------------|---------|----------------|-----------|
| `title`       | ja      | Text | Kurzer Titel der Aufgabe |
| `description` | ja*     | Text | Beschreibung/Details (fachlich Pflicht; DB-Default `""`) |
| `owner`       | –       | `lars` \| `elita` \| `familie` (Default `familie`) | Zuständig |
| `due_date`    | –       | `YYYY-MM-DD` | Fälligkeit (ohne = unterminiert). Vergangen = überfällig |
| `priority`    | –       | `niedrig` \| `normal` \| `hoch` (Default `normal`) | Priorität |
| `recurring`   | –       | `einmalig` \| `taeglich` \| `woechentlich` \| `monatlich` \| `jaehrlich` (Default `einmalig`) | Wiederholung |
| `termin_id`   | –       | Integer | Verknüpfung zu einem Termin (`/api/v1/termine`) |
| `project`     | –       | Text | Projekt-/Sammel-Label (z. B. „Hausbau", „Umzug") |
| `notes`       | –       | Text | Freie Notizen |
| `source`      | –       | Text (Default `manuell`) | Herkunft — Ole bitte `ole` setzen |

\* Wird `description` weggelassen, greift der DB-Default `""` — für gute Aufgaben aber immer mitgeben.

Falsche Enum-Werte → HTTP 422 mit `error.details.allowed` (Liste der erlaubten Werte).
Aktuelles Schema jederzeit: `GET /api/v1/aufgaben/schema`.

## Endpunkte

- `POST   /api/v1/aufgaben` — neue Aufgabe anlegen (Body = Felder oben). `?dry_run=1` prüft nur.
- `GET    /api/v1/aufgaben` — auflisten. Filter: `?owner=`, `?status=offen|erledigt`, `?priority=`,
  `?search=`, `?sort=due_date:asc`, `?limit=`, `?offset=`.
- `GET    /api/v1/aufgaben/{id}` — eine Aufgabe.
- `PATCH  /api/v1/aufgaben/{id}` — Felder ändern (z. B. `{"due_date":"2026-08-01","priority":"hoch"}`).
- `POST   /api/v1/aufgaben/{id}/complete` — **abhaken** (empfohlen statt PATCH status).
  Einmalige → `status=erledigt`. Wiederholende → rücken automatisch auf die nächste Fälligkeit vor
  (ab dem späteren von `due_date`/heute) und bleiben `offen`.
- `DELETE /api/v1/aufgaben/{id}` — löschen.

## Beispiele (curl)

```bash
# Anlegen
curl -X POST https://familienplaner.yagemi.app/api/v1/aufgaben \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{
        "title": "Kellerregal montieren",
        "description": "Regal an der Nordwand, Dübel liegen im Werkzeugkoffer",
        "owner": "lars",
        "due_date": "2026-07-25",
        "priority": "hoch",
        "recurring": "einmalig",
        "project": "Keller",
        "source": "ole"
      }'

# Wiederkehrende Aufgabe
curl -X POST https://familienplaner.yagemi.app/api/v1/aufgaben \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"title":"Rauchmelder testen","description":"alle Etagen","owner":"familie","recurring":"monatlich","source":"ole"}'

# Offene Aufgaben von Elita
curl -H "Authorization: Bearer $OLE_KEY" \
  "https://familienplaner.yagemi.app/api/v1/aufgaben?owner=elita&status=offen&sort=due_date:asc"

# Abhaken (id 42)
curl -X POST -H "Authorization: Bearer $OLE_KEY" \
  https://familienplaner.yagemi.app/api/v1/aufgaben/42/complete
```

## Prompt-Baustein für Ole (zum Teilen)

> Du kannst Familien-Aufgaben über die Familienplaner-API verwalten. Basis:
> `https://familienplaner.yagemi.app/api/v1`, Header `Authorization: Bearer <DEIN_AGENT_KEY>`.
> Eine Aufgabe anlegen: `POST /aufgaben` mit JSON `{title, description, owner, due_date?, priority?,
> recurring?, project?, termin_id?, notes?, source:"ole"}`. `owner` ∈ {lars, elita, familie};
> `priority` ∈ {niedrig, normal, hoch}; `recurring` ∈ {einmalig, taeglich, woechentlich, monatlich,
> jaehrlich}; `due_date` = `YYYY-MM-DD`. Gib **immer** eine aussagekräftige `description` und eine/n
> `owner` an. Aufgaben auflisten: `GET /aufgaben?owner=&status=offen`. Abhaken: `POST /aufgaben/{id}/complete`
> (wiederkehrende rücken automatisch weiter). Bei ungültigen Enum-Werten kommt HTTP 422 mit der Liste der
> erlaubten Werte; das aktuelle Schema liefert `GET /aufgaben/schema`. Aufgaben erscheinen sofort im
> Dashboard der Familie unter „Aufgaben".

Garten-Aufgaben (aus dem Gartenplaner) erscheinen im selben Dashboard-Abschnitt, werden aber über
`garten-aufgaben` gepflegt, nicht über `aufgaben`.
