# E-Book-Downloads (Shelfmark) — wann ein Buch „geladen" ist

Kurzreferenz für den E-Book-Bereich (`ebook_wishlist`, Kompat-API `/api/buecher`, iOS-Bereich
„E-Books"). Relevant, sobald jemand am Wunschlisten-Retry, an den Jobs oder an der Statusanzeige
arbeitet.

## Das Missverständnis, das der Auslöser war

Shelfmark (die familieneigene Downloader-Instanz auf der Synology) beantwortet

```
POST https://<shelfmark>/api/releases/download
```

mit **`200 {"priority":0,"status":"queued"}`**. Das ist die Annahme in die **Warteschlange** —
**kein abgeschlossener Download**. Danach läuft asynchron:

```
queued → locating → resolving → downloading → complete | error | cancelled
```

Bis Juli 2026 hat der Familienplaner das HTTP 200 direkt als `status='heruntergeladen'` verbucht.
Ergebnis: Bücher verschwanden aus dem Backlog, obwohl bei Shelfmark **jeder** Download scheiterte
(`Destination not writable: /cwa-book-ingest ([Errno 13] Permission denied)`). Die Original-App
hatte denselben Fehler — dort fiel er weniger auf, weil ein Mensch jeden Download einzeln auslöste.

## Zwei-Stufen-Modell (seit Migration 0019)

| Spalte | Bedeutung |
|---|---|
| `download_state` | `NULL` (nie angefasst) · `queued` (bei Shelfmark eingereiht) · `complete` (bestätigt) · `failed` (nachweislich gescheitert) |
| `queued_at` | ISO-Zeitpunkt der Einreihung |
| `queued_source_id` | Shelfmark-Download-ID (md5) des eingereihten Release |
| `last_error` | letzte Klartext-Meldung von Shelfmark |

1. **Einreihen** — `checkAndDownload()` sucht, wählt den Treffer (Titel-/Autor-Abgleich!) und POSTet
   ihn. Bei 2xx: `download_state='queued'`, **`status` bleibt `gesucht`** → das Buch bleibt sichtbar
   im Backlog.
2. **Bestätigen** — Job **`buecher-wishlist-verify`** (alle 10 min) gleicht `queued`-Zeilen gegen
   Shelfmark ab:
   * `complete` → `status='heruntergeladen'`, `download_state='complete'`
   * `error`/`cancelled` → zurück ins Backlog, Grund in `last_error`
   * noch unterwegs → unverändert
   * Shelfmark kennt den Download nicht mehr (Neustart): Gegenprobe in Calibre-Web; sonst nach
     **6 Stunden** (`STALE_HOURS`) als gescheitert werten.

## Zwei Wahrheitsquellen bei Shelfmark

| Endpunkt | Inhalt | Haltbarkeit |
|---|---|---|
| `GET /api/status` | Live-Warteschlange nach Buckets | **nur im Speicher** — Neustart löscht sie |
| `GET /api/activity/history?limit=&offset=` | Historie | persistiert, aber **nur die in Shelfmark weggeklickten** („dismissed") Einträge |

Ein Download kann also aus beiden verschwinden, ohne je fertig geworden zu sein → „unbekannt" ist
ein eigener Zustand und zählt **nie** als Erfolg. `downloadStates()` mischt beide, Live gewinnt.

## Endkontrolle: die Bibliothek

Ein erfolgreicher Download landet über den Ingest-Ordner in **Calibre-Web**. Die Bibliothek ist damit
die eigentliche Wahrheit für „wirklich heruntergeladen" — dauerhaft und unabhängig von Shelfmark-Neustarts.

Job **`buecher-wishlist-repair`** (manuell + einmalig 150 s nach dem Boot) prüft alle als
`heruntergeladen` markierten Bücher gegen Bibliothek **und** Shelfmark-Historie und legt
unbestätigte zurück ins Backlog. **Sicherung:** ohne erreichbare Bibliothek ändert der Job
**nichts** — lieber nichts tun als korrekte Einträge zurücksetzen. Bestätigte Zeilen bekommen
`download_state='complete'` und werden künftig übersprungen (idempotent).

Trockenlauf zuerst:

```bash
curl -s -X POST -H "Authorization: Bearer $KEY" "https://familienplaner.yagemi.app/api/v1/jobs/buecher-wishlist-repair/run?dry_run=1"
```

## Treffer-Auswahl

`pickBest()` verwirft alles, was nicht zum Titel passt (wortgrenzen-treuer Abgleich, kein
Teilstring), und gewichtet danach **Autor (+8) > Sprache de (+4) > epub (+2) > bekannter Verlag (+1)**.
Ohne Titel-Gate hätte „Der Schwarm" den Perry-Rhodan-Heftroman geladen. Kein passender Treffer →
das Buch bleibt im Backlog, statt das Falsche zu laden.

## „Fertige löschen"

`cleanupDownloaded()` löscht **nur** Zeilen mit `status='heruntergeladen' AND download_state='complete'`
— also ausschließlich bestätigte Downloads. Vor der Reparatur trägt kein Altbestand diese Markierung;
der Knopf löscht dann bewusst nichts.

## Wenn nichts mehr ankommt

Zuerst Shelfmark selbst fragen — der Fehler steht dort im Klartext:

```bash
curl -sk "https://bookdl.yagemi.synology.me:1443/api/status"
curl -sk "https://bookdl.yagemi.synology.me:1443/api/activity/history?limit=50&offset=0"
```

Häufigste Ursache bisher: **`/cwa-book-ingest` ist für den Shelfmark-Container nicht schreibbar**
(Rechte/UID auf der Synology). Das ist ein Infrastrukturproblem — die App kann es nur melden,
nicht beheben.
