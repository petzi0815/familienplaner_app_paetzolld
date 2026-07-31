# Wein-API (Weinkeller, Bewertungen, Preise) — Knowledge für Ole

Der Lebensbereich **Wein** ist API-first. Ole (oder jedes externe Tool) kann Weine anlegen,
suchen, bewerten, den Bestand pflegen und Preisrecherchen anstoßen. Alles erscheint sofort im
nativen Wein-Bereich der iOS-App.

- **Basis-URL:** `https://familienplaner.yagemi.app/api/v1`
- **Auth:** `Authorization: Bearer <API_KEY>`. Lesen = Rolle `readonly`, Schreiben = Rolle `agent`.
- **Ressourcen (generisches CRUD):** `weine`, `wein-bewertungen`, `wein-preise`
- **Eigene Routen:** `wein-scan`, `wein-lookup`, `wein-preischeck`, `wein-bewertung`, `wein-einstellungen`
- **Tabellen:** `weine`, `wein_bewertungen`, `wein_preise` (Migration `0021_wein.sql`)

Grundgedanke der Aufteilung: `weine` ist der Wein als Sache, `wein_bewertungen` hält **genau eine**
Bewertung je (Wein, Person) — den aktuellen Stand, kein Log —, `wein_preise` ist die Preis-Historie
(jede Recherche hängt Zeilen an).

---

## 1. Datenmodell

### 1.1 `weine` (Ressource `weine`)

| Spalte | Typ | Werte / Format | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | Autoincrement | Primärschlüssel |
| `name` | TEXT | Pflicht | Weinname **ohne** Weingut, z. B. „Barolo Riserva" |
| `weingut` | TEXT | Default `""` | Erzeuger |
| `jahrgang` | INTEGER | Jahr oder NULL | NULL = jahrgangslos (viele Sekte/Champagner) — nie 0 raten |
| `typ` | TEXT | `rot` \| `weiss` \| `rose` \| `sekt` \| `champagner` \| `schaumwein` \| `dessert` \| `port` \| `sonstiges` (Default `rot`) | Weinart |
| `rebsorten` | TEXT | JSON-Array von Strings, Default `[]` | z. B. `["Nebbiolo"]` |
| `land` / `region` / `lage` | TEXT | frei | Herkunft, `lage` = Einzellage/Weinberg |
| `alkohol` | REAL | 0–25 | Volumenprozent |
| `geschmacksrichtung` | TEXT | `trocken` \| `halbtrocken` \| `feinherb` \| `lieblich` \| `suess` \| `brut nature` \| `extra brut` \| `brut` \| `extra dry` \| `sec` \| `demi-sec` \| `unbekannt` (Default `unbekannt`) | Restsüße-Angabe des Etiketts |
| `suesse`, `saeure`, `tannin`, `koerper` | INTEGER | 1–5 oder NULL | Geschmacksprofil (1 = sehr wenig, 5 = sehr viel). NULL = unbekannt |
| `aromen` | TEXT | JSON-Array, Default `[]` | z. B. `["Kirsche","Vanille","Leder"]` |
| `serviertemperatur` | TEXT | frei | z. B. `"16-18 °C"` |
| `trinkfenster_von` / `trinkfenster_bis` | INTEGER | Jahreszahlen | Reifefenster |
| `bio`, `vegan` | INTEGER | `0` \| `1` (Default `0`) | Zertifizierung |
| `flaschengroesse_ml` | INTEGER | 50–27000 (Default `750`) | Füllmenge |
| `ean` | TEXT | nur Ziffern | Barcode — Schlüssel für den Einkaufs-Scan |
| `beschreibung` | TEXT | frei | Hintergrund/Story (Weingut, Lage, Ausbau) |
| `auszeichnungen` | TEXT | JSON-Array, Default `[]` | z. B. `["Falstaff 93","Parker 91"]` |
| `speiseempfehlung` | TEXT | frei | Passende Speisen |
| `referenzpreis` | REAL | Euro | **Basis der Rabattrechnung** = typischer Ladenpreis, nicht der günstigste |
| `bester_preis` | REAL | Euro | Zuletzt gefundener Bestpreis |
| `bester_preis_haendler` | TEXT | frei | Händler zum Bestpreis |
| `bester_preis_url` | TEXT | `http(s)://…` | Link zum Angebot |
| `preis_geprueft_at` | TEXT | Zeitstempel | Letzte Recherche — steuert die Fälligkeit im Job |
| `gekauft_preis` | REAL | Euro | Was **wir** bezahlt haben |
| `gekauft_bei` | TEXT | frei | … und wo |
| `preis_beobachten` | INTEGER | `0` \| `1` (Default `1`) | 1 = Job `wein-preischeck` beobachtet diesen Wein |
| `bestand` | INTEGER | Default `0` | Flaschen im Keller |
| `lagerort` | TEXT | frei | Gruppierung in der Kellersicht |
| `foto_key` | TEXT | Storage-Key, Media-Bereich `wein` | Etikettenfoto |
| `quelle` | TEXT | `manuell` \| `foto` \| `ean` \| `ki` (Default `manuell`) | Wie der Datensatz entstanden ist |
| `ki_confidence` | TEXT | `hoch` \| `mittel` \| `niedrig` | Selbsteinschätzung der Erfassung (**kein** CHECK — steht nicht in `/schema` unter `allowed`) |
| `notizen` | TEXT | frei | Freitext |
| `created_at`, `updated_at` | TEXT | `YYYY-MM-DD HH:MM:SS` | Automatisch |

Antworten des generischen CRUD enthalten zusätzlich `foto_key_url` (aufgelöste Bild-URL,
`/api/v1/media/<key>`), sobald `foto_key` gesetzt ist. Der Rohwert bleibt daneben stehen.

Volltextsuche (`?search=`) greift auf `name`, `weingut`, `land`, `region`, `lage`, `rebsorten`,
`aromen`, `beschreibung`, `speiseempfehlung`, `notizen`.

### 1.2 `wein_bewertungen` (Ressource `wein-bewertungen`)

| Spalte | Typ | Werte | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | Autoincrement | Primärschlüssel |
| `wein_id` | INTEGER | FK → `weine.id`, `ON DELETE CASCADE` | Wein |
| `owner` | TEXT | `lars` \| `elita` | Person — **keine** Familien-Bewertung |
| `sterne` | INTEGER | `1`–`5` | Bewertung |
| `kommentar` | TEXT | Default `""` | Freitext |
| `created_at`, `updated_at` | TEXT | Zeitstempel | Automatisch |

`UNIQUE (wein_id, owner)`: pro Wein und Person existiert genau eine Zeile. Zum Schreiben immer
`POST /wein-bewertung` benutzen (UPSERT) — ein zweiter `POST /wein-bewertungen` über das generische
CRUD läuft in einen Unique-Konflikt.

### 1.3 `wein_preise` (Ressource `wein-preise`, **schreibgeschützt**)

| Spalte | Typ | Werte | Bedeutung |
|---|---|---|---|
| `id` | INTEGER | Autoincrement | Primärschlüssel |
| `wein_id` | INTEGER | FK → `weine.id`, `ON DELETE CASCADE` | Wein |
| `preis` | REAL | Euro, Pflicht | Preis für **eine** Flasche, ohne Versand |
| `haendler` | TEXT | Default `""` | Shop-Name |
| `url` | TEXT | `http(s)://…` | Link zum Angebot |
| `quelle` | TEXT | `perplexity` \| `manuell` \| `ki` (Default `perplexity`) | Herkunft der Zeile |
| `gefunden_at` | TEXT | Zeitstempel | Wann recherchiert |

Die Ressource ist `readonly`: `POST`/`PATCH`/`DELETE` antworten mit **403 `readonly`**. Zeilen
entstehen ausschließlich über `POST /wein-preischeck` bzw. den gleichnamigen Job.

---

## 2. Generische CRUD-Endpunkte

Für alle drei Ressourcen gilt das übliche v1-Muster (`<res>` = `weine` \| `wein-bewertungen` \| `wein-preise`):

- `GET    /api/v1/<res>` — Liste. Antwort ist ein **Envelope** `{ "data": [...], "total": n, "limit": …, "offset": … }`.
  Filter: jede Spalte als Query (`?typ=rot`, `?wein_id=12`), dazu `?search=`, `?sort=spalte:asc|desc`,
  `?limit=` (max. 1000), `?offset=`.
- `GET    /api/v1/<res>/{id}` — eine Zeile als **bares Objekt** (kein Envelope).
- `POST   /api/v1/<res>` — anlegen (`?dry_run=1` prüft nur). Antwort = die angelegte Zeile.
- `PATCH  /api/v1/<res>/{id}` — Felder ändern.
- `DELETE /api/v1/<res>/{id}` — löschen (bei `weine` fallen Bewertungen und Preise per CASCADE mit).
- `GET    /api/v1/<res>/schema` — aktuelle Spalten inklusive `allowed`-Listen der CHECK-Spalten.

Ungültige Enum-Werte → **422** mit `error.details.allowed`. Unbekannte Felder werden ignoriert und
in der Antwort unter `ignored` gemeldet.

```bash
# Weißweine ab Bestand 1, neueste zuerst
curl -H "Authorization: Bearer $OLE_KEY" \
  "https://familienplaner.yagemi.app/api/v1/weine?typ=weiss&sort=created_at:desc&limit=20"

# Wein anlegen (Minimalsatz)
curl -X POST https://familienplaner.yagemi.app/api/v1/weine \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"name":"Barolo Riserva","weingut":"Cantina Rossi","jahrgang":2019,"typ":"rot",
       "rebsorten":"[\"Nebbiolo\"]","land":"Italien","region":"Piemont",
       "referenzpreis":39.90,"bestand":2,"lagerort":"Keller Regal 3","quelle":"manuell"}'

# Bestand nach einer geöffneten Flasche korrigieren
curl -X PATCH https://familienplaner.yagemi.app/api/v1/weine/12 \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"bestand":1}'

# Preis-Historie eines Weins
curl -H "Authorization: Bearer $OLE_KEY" \
  "https://familienplaner.yagemi.app/api/v1/wein-preise?wein_id=12&sort=gefunden_at:desc"
```

**JSON-Spalten** (`rebsorten`, `aromen`, `auszeichnungen`) sind TEXT mit JSON-Inhalt — der Wert muss
als **String** geschickt werden (`"[\"Nebbiolo\"]"`), nicht als JSON-Array.

---

## 3. Die fünf eigenen Routen

Alle Antworten sind envelope-frei (das Objekt steht direkt im Body). Fehler kommen einheitlich als
`{"error":{"code":…,"message":…,"details":…}}`.

### 3.1 `POST /api/v1/wein-scan` — Erfassung Schritt 1 (Rolle `agent`)

Etikettenfoto, EAN oder Freitext → angereicherter Vorschlag. **Speichert nichts.** Ohne
`OPENAI_API_KEY` antwortet die Route mit **501 `not_configured`**.

Body (mindestens eines der drei Felder):

| Feld | Format | Bedeutung |
|---|---|---|
| `image` | data-URL (`data:image/jpeg;base64,…`) | Etikettenfoto |
| `ean` | String | Barcode |
| `text` | String | Freitext, z. B. abgetippte Etikettzeile |

```bash
curl -X POST https://familienplaner.yagemi.app/api/v1/wein-scan \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"ean":"4006542001234","text":"Barolo Riserva 2019"}'
```

Antwort:

```json
{
  "vorschlag": {
    "name": "Barolo Riserva", "weingut": "Cantina Rossi", "jahrgang": 2019,
    "typ": "rot", "rebsorten": "[\"Nebbiolo\"]", "land": "Italien", "region": "Piemont",
    "alkohol": 14.5, "geschmacksrichtung": "trocken",
    "suesse": 1, "saeure": 4, "tannin": 4, "koerper": 4,
    "aromen": "[\"Kirsche\",\"Vanille\",\"Leder\"]",
    "trinkfenster_von": 2024, "trinkfenster_bis": 2035,
    "referenzpreis": 39.9, "bester_preis": 33.9, "bester_preis_haendler": "Weinfreunde",
    "bester_preis_url": "https://…", "ean": "4006542001234",
    "quelle": "ean", "ki_confidence": "mittel"
  },
  "preise": [{ "preis": 33.9, "haendler": "Weinfreunde", "url": "https://…" }],
  "quellen": ["https://…", "https://…"],
  "confidence": "mittel",
  "hinweise": ["Zur EAN ist in der Produktdatenbank (Open Food Facts) nichts hinterlegt — …"],
  "dublette": { "id": 12, "titel": "Cantina Rossi Barolo Riserva 2019", "bewertungen": [ … ] }
}
```

- `vorschlag` enthält **ausschließlich gültige `weine`-Spalten** in DB-Schreibweise und ist bereits
  auf die CHECK-Listen und plausible Zahlenbereiche geprüft — er kann unverändert an
  `POST /api/v1/weine` weitergereicht werden.
- `dublette` ist gesetzt, wenn dieselbe EAN existiert oder Name/Weingut bei gleichem Jahrgang passen
  (`null`, wenn nichts gefunden wurde). In dem Fall steht der Hinweis zusätzlich in `hinweise`.
- `hinweise` erklärt jede Degradation im Klartext (fehlender Schlüssel, Anbieter nicht erreichbar,
  Wein nicht identifizierbar). Diesen Text immer anzeigen, statt ihn zu verschlucken.
- Die Route ist ein Langläufer (`maxDuration = 120`): die KI-Kette braucht regelmäßig deutlich mehr
  als 25 Sekunden. Clients müssen ihr HTTP-Timeout entsprechend groß wählen.

### 3.2 `GET /api/v1/wein-lookup` — Einkaufs-Scan (Rolle `readonly`)

„Kennen wir den Wein — und wie fanden wir ihn?"

| Query | Format | Bedeutung |
|---|---|---|
| `ean` | String | Barcode (bevorzugt) |
| `name` | String | Name; erst exakt, dann unscharf über „Weingut Name" |
| `enrich` | `0` \| `1` (Default `1`) | `0` = schnelle Antwort ohne KI-Vorschlag |

`ean` **oder** `name` ist Pflicht, sonst 400 `no_input`.

```bash
curl -H "Authorization: Bearer $OLE_KEY" \
  "https://familienplaner.yagemi.app/api/v1/wein-lookup?ean=4006542001234"
```

Bekannter Wein:

```json
{
  "known": true,
  "wein": { "id": 12, "name": "Barolo Riserva", "…": "… alle Spalten …" },
  "bewertungen": [
    { "owner": "elita", "sterne": 5, "kommentar": "Lieblingswein" },
    { "owner": "lars", "sterne": 4, "kommentar": "" }
  ],
  "schnitt": 4.5,
  "vorschlag": null
}
```

Unbekannter Wein (mit `ean` und `enrich=1` läuft die KI-Kette und liefert einen Anlege-Vorschlag —
dieselbe Form wie bei `/wein-scan`, nur ohne `dublette`):

```json
{
  "known": false, "wein": null, "bewertungen": [], "schnitt": null,
  "vorschlag": { "name": "…", "weingut": "…", "…": "…" },
  "preise": [{ "preis": 33.9, "haendler": "Weinfreunde", "url": "https://…" }],
  "quellen": ["https://…"], "confidence": "mittel", "hinweise": []
}
```

`vorschlag` bleibt `null`, wenn kein `ean` mitgegeben wurde, `enrich=0` gesetzt ist,
`OPENAI_API_KEY` fehlt oder die Kette scheitert — die Kennen-wir-den-schon-Antwort kommt trotzdem.

### 3.3 `POST /api/v1/wein-preischeck` — Preisrecherche anstoßen (Rolle `agent`)

| Feld | Format | Bedeutung |
|---|---|---|
| `wein_id` | Integer | Genau diesen Wein prüfen (ignoriert `preis_beobachten` — bewusste Nutzeraktion) |
| `alle` | Boolean | Alle beobachteten Weine prüfen (ignoriert das Intervall, max. 100 je Lauf) |
| `dry_run` | Boolean | Recherchiert und rechnet, schreibt aber nicht in die DB (**kostet trotzdem** API-Aufrufe) |

`wein_id` oder `alle: true` ist Pflicht, sonst 400 `no_target`.

```bash
curl -X POST https://familienplaner.yagemi.app/api/v1/wein-preischeck \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"wein_id":12}'
```

Antwort:

```json
{
  "geprueft": 1,
  "treffer": [
    {
      "weinId": 12,
      "titel": "Cantina Rossi Barolo Riserva 2019",
      "treffer": [
        { "preis": 33.9, "haendler": "Weinfreunde", "url": "https://…" },
        { "preis": 36.5, "haendler": "Vinos", "url": "https://…" }
      ],
      "bester": { "preis": 33.9, "haendler": "Weinfreunde", "url": "https://…" },
      "referenzpreis": 39.9,
      "rabattProzent": 15
    }
  ],
  "rabatte": [],
  "dry_run": false
}
```

**Zwei Stolperfallen:**

1. `treffer` auf oberster Ebene ist ein Ergebnis **je geprüftem Wein** — die einzelnen Angebote
   (`preis`/`haendler`/`url`) liegen eine Ebene tiefer in `treffer[].treffer[]` bzw. in
   `treffer[].bester`. `rabatte` ist die Teilmenge, die die eingestellte Rabattschwelle erreicht.
2. Diese Route serialisiert ihre TypeScript-Struktur direkt, die Schlüssel sind hier **camelCase**
   (`weinId`, `rabattProzent`) — anders als die snake_case-Felder der Tabellenrouten.

Konnte für einen Wein nichts ermittelt werden, trägt sein Ergebnis ein Feld `fehler` mit dem
Klartextgrund (z. B. „Preisrecherche benötigt PERPLEXITY_API_KEY im Backend (Coolify).",
„Preissuche nicht erreichbar — beim nächsten Lauf erneut.", „Keine passenden Angebote gefunden.").
Diesen Text ausgeben, statt pauschal „nichts gefunden" zu melden. Ein Sammellauf ohne ein einziges
Ergebnis liefert zusätzlich `hinweise` mit dem Klartextgrund: es war nichts fällig, es läuft bereits
eine Sammelprüfung (zwei Sammelläufe können sich nicht überlappen) oder einer der beiden
API-Schlüssel fehlt.

Erfolgreiche Läufe schreiben je Angebot eine Zeile nach `wein_preise` und aktualisieren am Wein
`bester_preis`, `bester_preis_haendler`, `bester_preis_url` und `preis_geprueft_at`. Wurde nichts
gefunden, wird nur `preis_geprueft_at` gesetzt (der alte Bestpreis bleibt stehen). **Push verschickt
diese Route nie** — das macht ausschließlich der Job.

### 3.4 `POST /api/v1/wein-bewertung` — bewerten (Rolle `agent`)

| Feld | Pflicht | Format | Bedeutung |
|---|---|---|---|
| `wein_id` | ja | Integer | Wein |
| `sterne` | ja | `1`–`5` | Bewertung |
| `kommentar` | – | Text | Freitext |
| `owner` | – | `lars` \| `elita` | Nur **Fallback**: primär nimmt der Server die Person aus dem API-Key |

```bash
curl -X POST https://familienplaner.yagemi.app/api/v1/wein-bewertung \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"wein_id":12,"sterne":5,"kommentar":"Passt zu Wild","owner":"elita"}'
```

```json
{
  "bewertung": { "id": 7, "wein_id": 12, "owner": "elita", "sterne": 5, "kommentar": "Passt zu Wild" },
  "schnitt": 4.5,
  "bewertungen": [ { "owner": "elita", "…": "…" }, { "owner": "lars", "…": "…" } ]
}
```

UPSERT auf `(wein_id, owner)`: erneutes Bewerten überschreibt die eigene Bewertung.
**Wichtig für Ole:** Mit einem geteilten Schlüssel ohne Person (`auth.owner = null`) ist `owner` im
Body Pflicht — sonst kommt **400 `no_owner`** und es wird nichts gespeichert. Erfolg also nie am
abgeschickten Request festmachen, sondern an der 2xx-Antwort.

### 3.5 `GET` / `PUT /api/v1/wein-einstellungen` — Preiswächter konfigurieren (Rolle `agent`)

Bewusst Rolle `agent` (nicht `admin` wie `/api/v1/config`): Lars und Elita sollen die Überwachung
aus der App heraus einstellen können.

| Feld | Format | Grenzen | Default | Bedeutung |
|---|---|---|---|---|
| `intervall_tage` | Integer | 1–90 | `7` | Abstand, in dem ein beobachteter Wein neu recherchiert wird |
| `rabatt_prozent` | Integer | 5–80 | `20` | Ab dieser Ersparnis gegenüber `referenzpreis` gilt ein Angebot als Schnäppchen |
| `push_aktiv` | Boolean | – | `true` | Bei Schnäppchen die Familie per Push informieren |

```bash
curl -H "Authorization: Bearer $OLE_KEY" \
  https://familienplaner.yagemi.app/api/v1/wein-einstellungen
# {"intervall_tage":7,"rabatt_prozent":20,"push_aktiv":true}

curl -X PUT https://familienplaner.yagemi.app/api/v1/wein-einstellungen \
  -H "Authorization: Bearer $OLE_KEY" -H "Content-Type: application/json" \
  -d '{"intervall_tage":14,"rabatt_prozent":25}'
```

`PUT` ist ein Patch: nur mitgeschickte Felder ändern sich, die Antwort ist immer der vollständige
Stand **nach** dem Schreiben. Werte außerhalb der Grenzen → **422 `invalid_value`** mit `min`/`max`.
Ein Body ohne bekanntes Feld → 400 `empty`.

---

## 4. Die dreistufige KI-Kette (`server/wein/enrich.ts`)

Genutzt von `POST /wein-scan` und — bei unbekannter EAN — von `GET /wein-lookup`.
Die Kette **scheitert nie hart**: fällt eine Stufe aus, landet der Grund als Klartext in `hinweise`
und das Teilergebnis bleibt nutzbar.

| Stufe | Anbieter | Aufgabe |
|---|---|---|
| 1a — Identifikation über EAN | **Open Food Facts** (frei, kein Schlüssel, 10 s Budget) | Produktname, Marke → `weingut`, Land, Füllmenge, Bio-/Vegan-Label, Weinart aus den Kategorien. Unbekannte EAN = kein Fehler, nur kein Treffer |
| 1b — Identifikation über Foto | **OpenAI `gpt-4o` Vision** | Liest das Etikett wörtlich (Weingut, Name, Jahrgang, Rebsorten, Alkohol, Herkunft, Etikett-Rohtext). Das Etikett gewinnt gegen die Produktdatenbank |
| 2 — Recherche | **Perplexity `sonar-pro`** (Live-Websuche, 45 s Budget) | Aktuelle Händlerpreise deutscher Online-Shops + Hintergrund (Lage, Ausbau, Geschmacksprofil, Auszeichnungen, Trinkfenster). Ergebnis ist Prosa **plus Quellenliste** |
| 3 — Normalisierung | **OpenAI `gpt-4o`** (JSON-Modus) | Formt Identifikation + Recherche in genau die `weine`-Spalten, dazu `preise[]` und `confidence` |

Nachbereitung nach Stufe 3 (deterministisch, nicht durch die KI):

- `bester_preis`/`-_haendler`/`-_url` kommen **immer** aus der geprüften Angebotsliste, nie aus dem
  Fließtext der KI.
- Fehlt `referenzpreis`, wird der **Median** der gefundenen Angebote eingesetzt.
- `confidence` wird ehrlich gedeckelt: ohne Recherche höchstens `mittel`, ohne Name **und** Weingut
  immer `niedrig`.
- `quelle` wird auf `foto` / `ean` / `ki` gesetzt, `ki_confidence` auf den ermittelten Wert.
- Alles, was keine echte `weine`-Spalte ist oder außerhalb der CHECK-Listen bzw. plausibler
  Zahlenbereiche liegt, wird verworfen — der Vorschlag ist damit ohne Nachprüfung schreibbar.

**Ohne Schlüssel (Token-Gating):**

| Fehlender Schlüssel | Wirkung |
|---|---|
| `OPENAI_API_KEY` | `POST /wein-scan` antwortet **501 `not_configured`**. `GET /wein-lookup` antwortet weiterhin, aber ohne `vorschlag`. Innerhalb der Kette: keine Etikett-Erkennung, keine Normalisierung — nur direkt gelesene Werte plus Klartext-Hinweis |
| `PERPLEXITY_API_KEY` | Kette läuft weiter, aber ohne Live-Preise und ohne Web-Hintergrund; `hinweise` erklärt das. `POST /wein-preischeck` liefert je Wein ein `fehler`-Ergebnis, der Job überspringt sich vollständig |

Beide Schlüssel werden in Coolify gesetzt (`.env.example`: `OPENAI_API_KEY`, `PERPLEXITY_API_KEY`).
Ob sie gesetzt sind, zeigt `GET /api/v1/debug/selftest`.

Die Preisrecherche (`server/wein/pricecheck.ts`) benutzt dieselben zwei Anbieter, aber nur zweistufig:
Perplexity sucht live nach Angeboten, OpenAI (`gpt-4o`, JSON-Modus) übersetzt die Prosa in saubere
Zahlen. Reine Regex-Extraktion wäre zu fehleranfällig („ab 12,90 € (6er-Karton 71,40 €)"), und ein
falscher Preis löst einen falschen Schnäppchen-Push aus. Fehlt einer der beiden Schlüssel, wird gar
nicht erst gesucht — dann käme eine bezahlte Antwort heraus, die niemand auswerten kann.

---

## 5. Job `wein-preischeck`

| Eigenschaft | Wert |
|---|---|
| Name | `wein-preischeck` |
| Zeitplan | `0 6 * * *` (täglich 06:00, Zeitzone `Europe/Berlin`) |
| Topic | `wein` |
| Manuell | `POST /api/v1/jobs/wein-preischeck/run` (`?dry_run=1` für den Trockenlauf) |
| Status/Historie | `GET /api/v1/jobs/wein-preischeck`, Läufe in `job_runs` |

Ablauf:

1. Fehlt `PERPLEXITY_API_KEY` oder `OPENAI_API_KEY`, endet der Lauf sofort als sauberer No-Op mit
   entsprechender Meldung — es wird nichts „geprüft", was nie geprüft wurde.
2. **Fällig** ist ein Wein, wenn `preis_beobachten = 1`, `referenzpreis > 0` und die letzte Prüfung
   (`preis_geprueft_at`) länger als `intervall_tage` her ist (NULL = fällig). Sortierung: ältester
   zuerst, damit über mehrere Läufe jeder drankommt.
3. Kostendeckel: **maximal 25 Weine pro Lauf**, 400 ms Pause zwischen zwei Weinen. Bei 25 Weinen pro
   Nacht und 7 Tagen Intervall bleiben 175 beobachtete Weine dauerhaft aktuell. Der ausdrückliche
   „alle prüfen"-Lauf (`{"alle":true}` über die Route) hebt das Intervall auf, aber nicht die Kosten:
   dort liegt die Grenze bei 100.
4. Je Wein: Perplexity-Recherche → OpenAI-Auswertung → Historie in `wein_preise`, Bestpreis und
   `preis_geprueft_at` am Wein. `preis_geprueft_at` wird auch gesetzt, wenn nichts gefunden wurde
   (sonst wäre derselbe Wein sofort wieder fällig) — **nicht** aber, wenn ein Schlüssel fehlt.
5. Push: Ergebnisse ab `rabatt_prozent` Ersparnis gegenüber `referenzpreis` gehen als Meldung raus,
   sofern `push_aktiv` gesetzt ist — bis zu 3 Angebote je einzeln („🍷 Wein im Angebot"), ab 4 eine
   Sammelmeldung. Bewusst **ohne** `owner`, also an alle Geräte der Familie: der Weinkeller ist
   gemeinsam.
6. Der Trockenlauf (`dry_run`) listet nur die fälligen Weine und kostet **nichts** — er feuert
   absichtlich keine API-Aufrufe ab.

Zwei Sammelläufe (Job und manueller „alle prüfen") können sich nicht überlappen; der zweite kommt
mit `geprueft: 0` zurück.

### Einstellungen in `app_settings`

Die drei Werte liegen in derselben Tabelle wie `PUT /api/v1/config` und sind damit auch über die
Admin-Config sicht- und änderbar. Bequemer ist `PUT /api/v1/wein-einstellungen` (Abschnitt 3.5),
weil dort die Grenzen geprüft werden.

| Schlüssel | Wert | Default |
|---|---|---|
| `wein.preischeck.intervall_tage` | `"1"`–`"90"` | `7` |
| `wein.preischeck.rabatt_prozent` | `"5"`–`"80"` | `20` |
| `wein.preischeck.push_aktiv` | `"true"` \| `"false"` | `true` |

`app_settings.value` ist TEXT. Gelesen wird tolerant: unlesbare Werte ergeben den Standard,
Werte außerhalb der Grenzen werden auf den nächstgelegenen erlaubten Wert geklemmt — nie NaN.

---

## 6. Bedienung in der iOS-App

Der Bereich („Bereiche" → 🍷 Wein) hat die Segmente **Alle / Keller / Top / Offen**, Volltextsuche
und Filter nach Farbe, Rebsorte, Land und Mindestbewertung. Über das Menü oben rechts laufen
„Wein erfassen", „Im Laden scannen" und „Einstellungen".

**Zweischrittige Erfassung.** Schritt 1 (`wein-scan`) hat drei gleichwertige Einstiege — Etikett
fotografieren, Barcode scannen oder Weingut/Name/Jahrgang tippen — und einen Knopf, der die Kette im
Backend anstößt. Gespeichert wird dabei **nichts**. Schritt 2 zeigt jedes ermittelte Feld editierbar,
gegliedert in Wein / Herkunft / Geschmack / Hintergrund / Preis / Keller, darüber Vertrauensgrad,
Klartext-Hinweise und die Quellen-Links. Meldet das Backend eine Dublette, steht oben eine Karte mit
den vorhandenen Bewertungen und zwei Wegen: vorhandenen Wein öffnen oder trotzdem als eigenen
Eintrag anlegen (anderer Jahrgang). Erst der Speichern-Knopf legt den Datensatz an; das Etikettenfoto
wird vorher hochgeladen (Media-Bereich `wein`), damit der Wein gleich mit `foto_key` entsteht.
Direkt danach lässt sich die eigene Sterne-Bewertung setzen.

**Einkaufs-Scan im Laden** („Im Laden scannen", `wein-lookup`). Flasche aus dem Regal, Barcode
anvisieren, Ampel lesen: *Zugreifen* (Schnitt ≥ 4), *Geht so* (≥ 3), *Lieber stehen lassen*,
*Noch nicht bewertet* — dazu beide Bewertungen mit Kommentar und der Familienschnitt. Ist der Wein
unbekannt, zeigt die Karte den KI-Vorschlag und führt in die Erfassung.

**Bewertung je Person.** Auf der Detailseite ist die eigene Bewertung (1–5 Sterne + Kommentar)
bearbeitbar, die der anderen Person steht daneben. Die Person kommt aus dem persönlichen API-Key
(`/auth/me`); mit einem geteilten Schlüssel ohne Person lehnt der Server das Bewerten ab.
Ebenfalls auf der Detailseite: „Preis jetzt prüfen" (Einzel-Preischeck), der Schalter
`preis_beobachten` und die Preis-Historie.

**Keller.** Das Segment „Keller" ist eine Bestandssicht, keine zweite Katalogliste: nach `lagerort`
gruppiert, Flaschen direkt in der Zeile hoch- und runterzählbar (`bestand`), dazu die Summenzeile
und zwei Hinweisblöcke — „Jetzt trinkreif" (`trinkfenster_bis` läuft in den nächsten zwei Jahren ab
oder ist vorbei) und „Letzte Flasche" (`bestand == 1`, beim nächsten Einkauf mitdenken).

---

## 7. Prompt-Baustein für Ole (zum Teilen)

> Du kannst den Weinkeller der Familie über die Familienplaner-API verwalten. Basis:
> `https://familienplaner.yagemi.app/api/v1`, Header `Authorization: Bearer <DEIN_AGENT_KEY>`.
> Weine liegen in der Ressource `weine` (`GET/POST /weine`, `GET/PATCH/DELETE /weine/{id}`,
> Listen kommen als `{data,total}`). Pflichtfeld ist `name`; `typ` ∈ {rot, weiss, rose, sekt,
> champagner, schaumwein, dessert, port, sonstiges}; `geschmacksrichtung` ∈ {trocken, halbtrocken,
> feinherb, lieblich, suess, brut nature, extra brut, brut, extra dry, sec, demi-sec, unbekannt};
> `rebsorten`/`aromen`/`auszeichnungen` sind JSON-Arrays **als String**; `suesse`/`saeure`/`tannin`/
> `koerper` sind 1–5 oder weglassen; `jahrgang` darf fehlen (jahrgangslose Sekte). Zum Anlegen aus
> einem Foto oder einer EAN: `POST /wein-scan` mit `{image|ean|text}` → liefert `vorschlag` (bereits
> gültige Spalten), `preise`, `confidence`, `hinweise` und ggf. `dublette`; den `vorschlag` danach
> unverändert an `POST /weine` schicken. „Kennen wir den Wein?": `GET /wein-lookup?ean=…` →
> `known`, `bewertungen`, `schnitt`. Bewerten: `POST /wein-bewertung` mit
> `{wein_id, sterne (1–5), kommentar, owner:"lars"|"elita"}` — `owner` ist bei einem geteilten
> Schlüssel Pflicht, sonst kommt 400. Preise prüfen: `POST /wein-preischeck` mit `{wein_id}`
> (dauert Minuten; in der Antwort ist `treffer` ein Ergebnis **je Wein**, die Angebote liegen in
> `treffer[].treffer` bzw. `treffer[].bester`, Schlüssel camelCase). Preisüberwachung einstellen:
> `GET/PUT /wein-einstellungen` mit `{intervall_tage 1–90, rabatt_prozent 5–80, push_aktiv}`.
> Melde immer den Klartext aus `hinweise` bzw. `fehler` zurück, statt „nichts gefunden" zu sagen.
