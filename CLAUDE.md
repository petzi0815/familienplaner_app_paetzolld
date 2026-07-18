# CLAUDE.md — Familienplaner (Paetzold-Stilke)

> Anker-Dokument für Session-Kontinuität. Hier steht **wo wir stehen**, die Spezifikation und
> die Arbeitskonventionen. Bei neuer Session: dieses File zuerst lesen, dann das Session-Memory
> (`~/.claude/projects/C--bin-familienplaner-app/memory/`, Index `MEMORY.md`).

## ▶️ WIEDERAUFNAHME (nächste Session) — START HIER

**NEU 2026-07-18 (5. Session) — Dashboard Zeit/Ort, NEUER Bereich AUFGABEN (inkl. Push), Vorrat-Erfassung überarbeitet + KI-Rezept, Prod-Debug-Zugang. Backend live `82c2fa1`, iOS Builds 46–50 (alle grün). Details: [[session-2026-07-18_dashboard-vorrat-aufgaben-push]].**
- **Dashboard-Termine:** Uhrzeit (fett+`fixedSize` vorne, war hinter langem Datum abgeschnitten) + antippbarer **Ort → Google Maps** (`Support/MapsLink.swift`, `comgooglemaps` in project.yml). Backend-Agenda liefert `location`.
- **NEUER Lebensbereich „Aufgaben"** (Migration `0016`): generisches CRUD + `POST /aufgaben/{id}/complete` (recurring, tag-geclampt). Dashboard-Section (Offen/Erledigt-Umschalter, Wieder-Öffnen), `aufgabenFeed()` mergt Familie + Garten-Aufgaben (akt. Monat). **Push** (Migration `0017`, backend-only): Anlege-Push an konkrete Person (lars/elita, nicht self/familie) via `createRow`-Hook (`notifyOwnerOnCreate`); Job `aufgaben-reminders` 1 Tag vor `due_date`. Ole-Doku `docs/AUFGABEN.md`. **Live verifiziert** (Push kam an).
- **Vorrat-Erfassung** (Erfassen-Scan + manuelles Formular): Lagerort Pflicht (Regal/Kühlschrank/Tiefkühl = Kategorie umbenannt), MHD Pflicht, **Foto** (`VorratPhotoField` → `media/upload`). EAN-Scan füllt via **Open Food Facts** Name/Marke/**Menge**/**Lagerort** (Heuristik aus `categories_tags`) + lädt **Produktbild** als Vorschlag. Dashboard-Section **„Bald ablaufend"** (Vorrat raus aus Agenda).
- **KI-Rezept** `POST /api/v1/vorrat/rezept-vorschlag` (OpenAI gpt-4o, JSON-Modus, token-gated): One-Click aus ablaufenden Zutaten → vollständiges Rezept. iOS `RezeptVorschlagSheet` (Button in „Bald ablaufend" + Rezepte-Tab).
- **Prod-Debug für Claude:** `GET /api/v1/debug/selftest?openai=1` (Integrations-Booleans + DB-Stände + OpenAI-Live-Ping) + dedizierter Agent-Key via Coolify-ENV `FAMILIENPLANER_AGENT_KEY` → ich kann jetzt LIVE gegen Prod testen. Siehe [[reference-prod-api-debug]].
- **Non-obvious:** [[feedback-xcuitest-identifier-vs-label]] (Text mit ID → Label-Subscript matcht nicht); dt.-Quote-Compile-Bug kam wieder (Scan fing ihn); literaler `app/api/v1/<x>/`-Ordner mit nur tiefer Sub-Route shadowt `[domain]` NICHT; `date(x,'+1 month')` überspringt Monatsenden → eigene `nextDue`. [[feedback-immer-auto-compile-ci]] gilt.
- **OFFEN (optional, NICHT umgesetzt):** Aufgaben-Push auch „2 Tage vorher" + Push am Fälligkeitstag für überfällige. `FAMILIENPLANER_AGENT_KEY` steht im Chat (bewusst) → optional rotierbar. Prod hat aktuell 0 Lebensmittel/Aufgaben.

**NEU 2026-07-17 (4. Session) — NEUER LEBENSBEREICH „PIZZA MACHEN" 🍕 (nur iOS), in 4 Ausbaustufen gebaut + jede gegen Prod/CI verifiziert. Alle live, HEAD `6bf1095`. Details: [[session-2026-07-17_pizza-planer]].**
- **Teig-Rechner / Rezept-Kalkulator** (neapolitanisch, Rückwärtsplanung ab Essenszeit). Backend rein datenhaltend: Migrationen `0013_pizza` (pizza_rezepte + pizza_notizen, CASCADE), `0014` (fridge_temp), `0015` (mehltyp-CHECK auf 5 Sorten, datenerhaltend per Table-Rebuild+Notizen-Stash). 2 Registry-Einträge → generisches CRUD, KEINE eigene Route. iOS: `App/Sources/Pizza/*` (Models/Calculator/API/Store/RootView/PlanerView/RezepteView/Share/Reminders/Erklaerung/StartRegler).
- **Hefe-Modell physikalisch:** warm-äquivalente Stunden `pct = K/(Σ tᵢ·2^((Tᵢ−20)/7) · mehlFaktor)`, K=4,5 (Advanced-Regler „K-Wert"). Kühlschrank 5 °C ≈ 0,23 warme h/h. Cold-Ferment-Hefe trifft Praxis (24h→0,43%, 72h→0,21%). Same-Day-Anker unverändert (6×275 tipo00 22°C → 994g/621ml/28g/7,2g). Ofen fix Gozney Dome (30 min).
- **Stufe 1 (`eed2cbe`):** Grundplaner. **Stufe 2 (`8460369`):** fixe Essenszeit, nie „geht nicht" — Kühlschrankgare über Nacht (Kugeln kalt, längste Gare bis 72h), warm/kalt. **Stufe 3 (`c59fb57`):** 3 Mehlsorten (Caputo Pizzeria / La Farina 14 / Edeka Herzstücke — alle Weizen-Tipo-00, mehlFaktor 1,0 ⇒ gleiche Hefe, nur Hydration+Gär-Toleranz-Hinweis unterscheiden) + In-App-Erklärungen (Info-Button je Option, inkl. K-Wert). **Stufe 4 (`6bf1095`):** **Start-Korridor-Regler** ersetzt Warm/Kalt-Umschalter — Nutzer wählt die Startzeit per Regler, Nachtruhe-Sperrzonen als „nicht möglich" markiert (Daumen snappt via `korridor.segmente`, kein Neuaufbau je Frame), Default = frühester Start (meiste Aroma), warm/kalt = abgeleitetes Badge.
- **Verifikations-Muster (bewährt):** eigenes JS-Referenzmodell im Scratchpad (`ref-cold.mjs`/`ref-corridor.mjs`) als ausführbare Spezifikation → Workflow portiert 1:1 nach Swift → Verify-Agent portiert das RESULTIERENDE Swift zurück nach JS und difft gegen die Referenz (Korridor: 0 Abweichungen über >1000 Punkte). Plus adversariale Multi-Linsen-Reviews (jeder Fund einzeln widerlegt). Migration je gegen Seed-DB-Kopie mit Testdaten. Backend-Endpunkte + fridge_temp + mehltyp gegen ECHTE Prod mit `BOOTSTRAP_AGENT_API_KEY` getestet.
- **XCUITest-Suite WIEDER GRÜN** (war seit `c19a968` rot): 2 vorbestehende Fehler gefixt (`064ab57`) — Alarmo-Kachel: Container-`.accessibilityIdentifier` überschrieb Kind-IDs (Aktivieren-Button hieß `alarmo-tile` statt `alarmo-arm`, echter A11y-Bug); Smarthome-Szenen: `LazyVGrid` off-screen → Test scrollt jetzt ein. Ursachen aus dem `.xcresult`-Artefakt des CI-Fehllaufs (zstd-Blobs, Element-Baum) rausgezogen, nicht geraten. **Standing Order weiter gültig: [[feedback-swift-string-literals-ci]] Quick-Scan nach jedem iOS-Change.**
- **OFFEN/Hinweis:** (1) Der Agent-API-Key stand im Klartext im Chat — Lars sollte `BOOTSTRAP_AGENT_API_KEY` in Coolify rotieren. (2) Dinkel bekommt laut Spec §3.7 (10% schneller) WENIGER Hefe als tipo00 — falls Lars das anders will, ist es ein K/Faktor-Tweak. (3) Der neue TestFlight-Build enthält den kompletten Pizza-Bereich (kommt per Update-Banner).

**NEU 2026-07-14 (3. Session) — HOME-ASSISTANT-ANBINDUNG: Alarmo-Alarmanlage + neuer Smarthome-Tab (Raffstore Höhe/Neigung + Szenen) + Suche oben-rechts. Kameras nur RECHERCHIERT (nächster Schritt). Details: [[session-2026-07-14_alarmo-smarthome-raffstore]] + [[reference-unifi-protect-cameras]].**
- **HA-Client neu** (`server/homeassistant/{client,alarmo,house}.ts`) + `config.homeAssistant` (Token/URL aus Coolify, in `.env.example`). Zert. gültig → globales `fetch`.
- **Alarmo** (`alarm_control_panel.alarmo`): `GET/POST /api/v1/alarmo` (GET readonly, POST agent+, **PIN 4578 SERVERSEITIG** via `config.alarmoCode`/`ALARMO_PIN` — kein Code-Tippen in der App). iOS `AlarmoTile` auf **Heute UND Smarthome-Tab** (Status + Aktivieren-Menü Abwesend/Zuhause/Nacht / Deaktivieren).
- **NEUER Smarthome-Tab** (`Views/SmarthomeTabView.swift`, **ersetzt den Suchen-Tab** in der Bottom-Bar; Icon `blinds.horizontal.closed`): **Raffstore-Steuerung** (5 Cover `_invert`, alle Position+Tilt) — `BlindCard` mit Blind-Glyph + Höhe-Slider + Lamellen-Slider + Auf/Stop/Zu (**pending-Guard pro Achse** → Slider springt nicht auf Zwischenstände) + **Szenen** (`script.raffstore_{putzen,verdunkeln,sichtschutz}`). Backend `server/homeassistant/house.ts` mit **Allow-List**; Routen `GET /api/v1/smarthome/house`, `POST /smarthome/cover|script`. Cover-Felder: `position`/`tilt_position`.
- **Suche**: aus Bottom-Bar → **Toolbar-Button oben rechts auf „Heute"** (öffnet SearchView als Sheet). `MainTab.search`→`.smarthome`.
- **Verifiziert**: `tsc` grün + **alle HA-Endpunkte gegen echtes HA** (Alarmo disarm safe; 5 Raffstores gelesen; cover stop; Allow-List 422). 2 Multi-Linsen-Reviews (Swift-Compile-Gate) — **swift-compile 0 Findings**, 7 minor confirmed+gefixt, Slider-Jump war False-Positive. iOS via Mac-mini-CI.
- **Kameras GEBAUT (über Home Assistant, kein UniFi-Key/Tailscale):** `server/homeassistant/cameras.ts` (Allow-List 9 Kameras) + Routen `GET /api/v1/smarthome/cameras`, `/cameras/[entity]/snapshot` (Backend proxyt JPEG mit HA-Token). iOS: Kamera-Sektion im Smarthome-Tab — `CameraThumb` (Snapshot-Raster, alle 6 s, scenePhase-gekoppelt) + `CameraLiveView` (AVKit `VideoPlayer`, Vollbild, zeigt bei Fehler die ECHTE AVPlayer-Ursache). Alle Endpunkte gegen echtes HA verifiziert. Recherche/Warum-HA in [[reference-unifi-protect-cameras]].
  - **Live-HLS-FIX (Nutzer: „durchgestrichenes Play, Stream startet nicht"):** Ursache = die direkte HA-URL (`petzi0815.duckdns.org:8123`) ist vom Handy oft NICHT erreichbar (NAT-Hairpin; **ATS ausgeschlossen** — HA hat TLS1.3/Let's-Encrypt). Fix: **HLS wird jetzt übers Backend geproxyt** (`server/homeassistant/hls-proxy.ts` + öffentliche Route `GET /api/v1/smarthome/hls/[token]`) — `/cameras/[entity]/stream` mintet via WS die HA-HLS-URL und gibt eine **signierte Backend-Proxy-URL** zurück; der Proxy schreibt alle Playlist-Referenzen (bare + `URI="…"`) auf weitere signierte Proxy-URLs um und streamt Segmente. AVPlayer sendet keinen Auth-Header → Schutz = **HMAC-Token (HA-Pfad+Ablauf, `SESSION_SECRET`)**, nur `/api/hls/…`-Pfade, 2 h TTL, kein Redirect-Follow. Ende-zu-Ende verifiziert. Handy spricht nur noch `familienplaner.yagemi.app`.
  - **Live-HLS-FIX 2 (Stream startete weiter nicht) → dann Low-Latency:** HA liefert **LL-HLS** (blockierende Reloads via `_HLS_msn/_HLS_part`). Zwischenschritt war LL-HLS-Tags strippen (Standard-HLS, ~15–20s Latenz, stabil). **Finale Version (Nutzer wollte niedrige Latenz):** LL-HLS bleibt, die Route reicht die `_HLS_*`-Query an HA durch → **~2s Latenz**. Verifiziert: HA-direkt und Proxy geben identische 400 bei Out-of-Range-Part (⇒ Query wird durchgereicht); exakter Next-Part → Proxy blockt 767ms und liefert 200 mit LL-HLS-Playlist. Backend-only, greift ohne App-Build.
  - **Player-Verbesserungen (nur iOS, braucht Build):** `CameraLiveView` nutzt jetzt eine eigene `AVPlayerLayer`-View (`CameraPlayerView`, keine AVKit-Controls) mit **Pinch-Zoom + Verschieben** (MagnifyGesture/DragGesture, Doppeltipp = Reset) und **Drehung ins Querformat** — per `AppDelegate.orientationLock` (App bleibt Hochformat, nur die Live-Kamera erlaubt Querformat; `project.yml` UISupportedInterfaceOrientations um Landscape erweitert). **WICHTIG: direkte UniFi-Cloud-API geht NICHT für Live** (RTSPS-URLs lokal, kein AVPlayer-Format, Cloud relayt kein Video) → HA ist der richtige Weg.
- **Alarmo-Bugfix (Nutzer-Report „hängt bei Wird aktiviert"):** Ursache = offene Tür (Alarmo bricht Scharfschalten ab → zurück zu disarmed) + App pollte nur ~3 s. Fix: `alarmoAction` **beobachtet bis Endzustand** (bis ~90 s) + meldet Fehlschlag mit **offenen Sensoren als Klarnamen** (`resolveOpenSensors` → Friendly-Name, z. B. „Hebeschiebetür Küche"); Kachel zeigt offene Türen proaktiv (nur wenn unscharf). `AlarmoStatus.open_sensors` jetzt `string[]`.
- **Calibre-Buch-Download GEBAUT:** auf der Buch-Detailseite (`CalibreBookDetail.swift`) Format-Buttons (epub/…) → lädt die Datei über `GET /api/buecher/calibre/download/[id]?format=` (Backend `downloadBook` via `authed()`, wie der Cover-Proxy) → schreibt sie in `temporaryDirectory` (`<Titel>.<fmt>`) → **Teilen-Dialog** (`ShareSheet`/`UIActivityViewController`) → „In Bücher kopieren". `bookDetail`/Route liefern jetzt `formats` (aus den `/download/<id>/<fmt>/`-Links); iOS-Fallback „epub". LERNPUNKT: Datei-Content-Disposition ASCII-sicher halten (`<id>.<fmt>`) — CWA-Namen mit Typografie-/Nicht-Latin1-Zeichen werfen sonst beim HTTP-Header. NICHT lokal gegen echtes CWA verifiziert (CWA_*-Creds nur in Coolify) — Muster = der funktionierende Cover-Proxy + epub-Fallback.
- **OFFEN (Lars, Coolify):** `HOME_ASSISTANT_URL` + `HOME_ASSISTANT_TOKEN` gesetzt ✓. Optional `ALARMO_PIN` in Coolify, wenn der PIN NICHT im Repo stehen soll (sonst Default 4578). Coolify muss HA (`petzi0815.duckdns.org:8123`) per https+wss erreichen (für Alarmo/Raffstore/Kamera-Snapshot/HLS-Mint). Calibre-Download braucht die schon gesetzten `CWA_*`.
- **⚠️ LERNPUNKT (c19a968): 2 dt.-Anführungszeichen-Compile-Bugs** (schließendes ASCII-`"` statt `"`) in `CalibreBookDetail.swift:50` (App-Target) + `FamilienplanerUITests.swift:150` (Test-Target) — von tsc UND Agent-„Compile-Gate"-Reviews DURCHGEWUNKEN, erst vom echten Mac-mini-Xcode-Build gefangen. Fix → Build Check GRÜN. **Nach jedem iOS-Change den Quick-Scan aus [[feedback-swift-string-literals-ci]] laufen; Agent-Reviews sind KEIN Compile-Ersatz.**
- **OFFEN (nächste Session): XCUITest-Suite ist ROT** — seit c19a968 kompiliert das Test-Target wieder, aber ≥1 Test schlägt zur **Laufzeit** fehl (Assertion, KEIN Compile-Fehler; erster Lauf seit die neuen Kamera/Alarmo/Smarthome-Tests liefen). Nächste Session: `.xcresult` von Run **29370389397** (Artefakt `uitest-results.zip`) laden ODER lokal auf dem Mac mini laufen → welcher Test fehlschlägt → fixen. Blockt NICHT den TestFlight-Build (Build Check ✓).

**Stand (2026-07-14 Abend, /beenden, HEAD `c19a968`, gepusht): Backend LIVE (`familienplaner.yagemi.app`, alle HA/Kamera/Alarmo/Raffstore/Calibre-Endpunkte). iOS Build Check GRÜN, TestFlight-Upload lief noch durch (⇒ neuer Build mit Pinch-Zoom/Drehung kommt per Update-Banner). Kamera-Live-Stream funktioniert (Low-Latency ~2s). EINZIGER offener Punkt: die rote XCUITest-Suite (Laufzeit-Assertion).**

**NEU 2026-07-14 (2. Session) — AreaScaffold-Vereinheitlichung + Geschenke-KPI + kompakte Kacheln + NEUER Bereich Trauerkarten + 4 UI-Ideen + native Swipe (8 Listen) + Haptik. HEAD `003486a`, alles gepusht (Coolify + Mac-mini-CI bauen). Details: [[session-2026-07-14_areascaffold-kpi-trauerkarten]].**
- **iOS-Reuse vollendet**: neues `AreaScaffold<Trailing,Controls,Content>` (`Support/AreaUI.swift`) + `NotifiableStore`/`.areaToast` auf ALLE 11 übrigen Bereiche migriert (Termine=Referenz, Books behält Amber-Chrome). −79 Zeilen, 4-Linsen-Review 0 Blocker.
- **Geschenke-KPI** → „Geschenk-Anlässe" (`geschenk_ereignisse.datum` in [heute,+3M]). **Bereiche-Hub** kompakter (~3 Spalten, keine „X Listen"-Zeile) + **Favoriten** (Long-Press-Pin, `@AppStorage`).
- **NEUER Lebensbereich „Trauerkarten"** (🕊️) aus Lovable/Supabase `memories-app` migriert: **Migration 0012** (`trauerkarten`/`_personen`/`_kosten` — 3 Personen/29 Karten Σ Trauergeld 1295€/22 Kosten) + 39 Bilder (Boot-Media-Sync in `seed.ts`, pro Unterordner) + 3 v1-Registry-Ressourcen + **KI-Scan** `/api/v1/trauerkarten-scan` (gpt-4o Vision, token-gated) + nativer iOS-Bereich (Karten-Raster + Detail + Kostenübersicht mit Kostenverteilung/Ausgleichszahlungen). **LERNPUNKT:** memory-photos-Bucket = verwaiste Metadaten (Voll-Fotos physisch gelöscht → public aber 404) → nur Thumbnails + 1 Karte (base64) migrierbar. **Nutzer kann Supabase/Lovable jetzt löschen.**
- **Heute-Screen**: persönliche Begrüßung (`AppState.me` aus `/auth/me`) + „Als Nächstes"-Karte + globaler Such-Einstieg (→ Suchen-Tab). **Haptik** zentral in `NotifiableStore.notify` (greift für ALLE Bereiche). **KPI-Int-Tausenderpunkt-Fix**. `AreaEmptyState` mit optionalem Aktions-Button.
- **Native Swipe-Aktionen** auf 8 Listen (Termine, Vorrat, Gypsi, Wunschliste, Samu-Bedarf, Ebooks-Wunschliste, Reiniger, Verträge) via List-Umbau (clear rows + `.scrollContentBackground(.hidden)`, Karten-Look erhalten). **LERNPUNKT:** `.textCase(nil)` auf `Section` unterdrückt Auto-Uppercase der List-Header; `List` in `VStack` kollabiert NICHT (anders als ScrollView). Umsetzung via Workflow (6 Konvertierungen parallel + Review je Datei — Review muss die TATSÄCHLICH editierte Datei prüfen, nicht die vorab geratene).
- **OFFEN (nur vom Nutzer zurückgestellt):** Trauerkarten-PDF/Share-Export (Signature-Feature der Original-App) — bei Bedarf nachziehen. Sonst keine Blocker.

**Stand (2026-07-14, 2. Session, HEAD `003486a`, gepusht): ALLE iOS-Bereiche auf AreaScaffold/NotifiableStore/areaToast + NEUER Bereich Trauerkarten (Backend+Daten+iOS, Migration 0012) + Home-Personalisierung + globale Suche + Bereiche-Favoriten + native Swipe (8 Listen) + zentrale Haptik. `tsc`+`next build` grün, Migration gegen Seed-DB verifiziert; iOS via Mac-mini-CI (nicht lokal kompilierbar) — Reviews als Compile-Ersatz.**

**NEU 2026-07-14 (Abend) — Kalender-Abo, generisches Anstehendes, Per-User-Termine, KPI-Rework, iOS-Reuse, Shelfmark, Update-Banner (Details: [[session-2026-07-14_kalender-feed-dashboard-per-user]]). Migration 0011. Backend 46 Smoke-Checks grün + adversarialer Review (0 Blocker).**
- **Abonnierbarer ICS-Feed** (Termine+Abfuhr+Reisen): `server/ics/generate.ts` + `server/feed/tokens.ts` + öffentliche Route `app/api/feed/[token]/familienplaner.ics` (Token im Pfad, KEIN getAuth) + `/api/v1/feed/subscribe|rotate`. iOS: HeuteView „Kalender abonnieren" (webcal) + SettingsSheet.
- **Generisches „Anstehendes"**: `queries.ts::agenda(days,owner)` mergt Termine/Abfuhr/Reisen/Vorrat/reminders; `reminders`-Tabelle (URL-Key **`erinnerungen`**, nicht `reminders`!) per API befüllbar; Route `/api/v1/agenda`. iOS Home = EINE datengetriebene Agenda-Liste.
- **Per-User-Termine**: `termin_user_state` (read/notify + 2d/1d-Marker), `POST /api/termine/[id]/mystate`, Job `termine-user-reminders` (owner-Push 2 & 1 Tag vorher). iOS TerminCard: „gelesen"-Auge + Benachrichtigungs-Menu. LocalReminders: Termine raus (Server-Push).
- **KPI-Kacheln „Aktions-Fokus 6"** (datengetrieben, antippbar → Deep-Link). **Geschenke 458→zukünftig** (`e.datum>=now`, auch Widget).
- **iOS-Reuse**: `BEREICH_REGISTRY` (1 Eintrag/Bereich), `NotifiableStore`, `.areaToast`. **Shelfmark E-Book-Suche/Download echt** (node:https-Proxy, war 501). **Update-Banner** (`/api/v1/app/version` + Fastfile/CI).
- **E-Books-Cover + Calibre-Web** (Nachtrag Abend): (a) Wunschlisten-Cover-Backfill aus Google Books
  (`server/ebooks/covers.ts` + Job `buecher-cover-enrich` + Boot-One-Shot) → Cover erscheinen ohne App-Update.
  (b) **Calibre-Web-Integration**: `server/ebooks/calibre.ts` (Session/CSRF/self-signed node:https, nur lesen +
  auf Regal legen), Routen `/api/buecher/calibre/{shelves,books,cover/[id],shelf}`, config.calibre (`CWA_*`).
  iOS: neuer **„Bibliothek"-Tab** (`Ebooks/CalibreView.swift`) — 5354 Bücher durchsuchbar, nach Regal filterbar,
  Cover, auf-Regal-legen. Live gegen die CWA-Instanz verifiziert (8/8, add/remove-Round-Trip sauber).
  **+ Detailseite** (`Ebooks/CalibreBookDetail.swift`, Route `/api/buecher/calibre/book/[id]`): Metadaten + Beschreibung
  + Regale zuordnen/entfernen (data-shelf-action="remove" = Mitgliedschaft). **+ Sortierung**: Neueste zuerst (Default) /
  Autor A–Z / Z–A. LERNPUNKT: CWA `/ajax/listbooks` ignoriert sort für id/timestamp/title (Titel-Sort nur mit Suche),
  nur `author_sort` greift zuverlässig → „alphabetisch" = Autor. LERNPUNKT 2: antippbare Grid-Zelle MUSS ein `Button`
  sein (VStack+onTapGesture ist in XCUITest nicht `app.buttons` → Test rot; App lief trotzdem).
- **E-Book-Wunschlisten-Retry** (`server/ebooks/wishlist.ts`, live): pro-Buch „Jetzt suchen & laden" + Bulk „Alle prüfen"
  (fire-and-forget) + „Fertige löschen" + Wochen-Job `buecher-wishlist-retry`. Shelfmark searchReleases→pickBest
  (de+epub)→startDownload, attempts/last_attempt vermerkt, bei Erfolg status=heruntergeladen. Routen
  `/api/buecher/wishlist-check|-check-all|-cleanup`. iOS-Buttons in EbooksWishlistView/EbookCard. Netzfehler → generisch
  (kein Host-Leak). Live-Smoke 8/8.
- **OFFEN (Lars, extern):** (1) fürs Update-Banner GH-Variable `FAMILIENPLANER_BASE_URL=https://familienplaner.yagemi.app` + Secret `FAMILIENPLANER_DEPLOY_KEY` (Agent-Key) setzen. (2) `APNS_*` in Coolify (bekannt offen) → sonst kein Per-User-Push. (3) Coolify muss `bookdl.yagemi.synology.me:1443` erreichen (sonst Shelfmark-Suche 502). `SHELFMARK_BASE_URL` optional. (4) **Calibre**: `CWA_URL`/`CWA_USERNAME`/`CWA_PASSWORD` in Coolify setzen (sonst Bibliothek-Tab 501; empfohlen: eigener CWA-Nutzer statt admin), Coolify muss `books.yagemi.synology.me:1443` erreichen.

**Stand (2026-07-14 Abend, HEAD `1e718fe`, CI 3/3 grün): Backend + iOS LIVE — ALLE Lebensbereiche nativ + Kalender-Abo + generisches Anstehendes + Per-User-Termine + E-Books komplett (Shelfmark-Suche/Download, Wunschlisten-Cover + Retry, Calibre-Web-Bibliothek mit Detail/Sort/Regale) + Update-Banner. Deployment vollständig konfiguriert (Coolify + GitHub).** `https://familienplaner.yagemi.app`.

**NEU 2026-07-14 (Nachtrag) — 2 Geschenkplaner-Bugs gefixt (`9733200`, Details: [[feedback-swiftui-runtime-bugs]]):**
Nav: Event→Detail ging nicht (value-basierte NavigationLink in gepushter View flaky → closure-basiert wie Reisen).
Optik: Jahr „2.026" statt „2026" (`Int` in `Text("…\(int)")` → `\(String(int))`). Beide Klassen alle Bereiche
geprüft → nur Geschenkplaner. UI-Test-Best-Practice: `UITestFixtures.swift` (im `-uitest`-Modus vom CompatClient
geliefert) → **datengetriebener** Test `testGeschenkplanerEventNavigation` fängt beide.

**NEU 2026-07-14 — Restliche Bereiche nativ + XCUITest (Details: [[session-2026-07-14_restliche-bereiche-und-xcuitest]]):**
- **Letzte 8 Bereiche nativ** (`App/Sources/{Termine,Vorrat,Wunschliste,Gypsi,Reiniger,Ebooks,SmartHome,Vertraege}/`) →
  **kein generischer Browser mehr**. Volle PWA-Parität, native UX. Ebooks=E-Book-Wunschliste (domain `ebooks`, API `/api/buecher`);
  Vertraege nutzt v1 `/api/v1/vertraege` (Envelope). 501-Aktionen angezeigt aber deaktiviert.
- **XCUITest-GUI-Suite** (`ios-app/UITests/`, Target nur `test`-Action) + `.github/workflows/ios-uitest.yml`: Login-Bypass
  (`UITestMode`) + statische Bereiche (`DomainCatalog.buildStatic`) → offline testbar. Prüft Tabs, jede Kachel navigiert +
  Zurück, Segment-Tabs. Standing Order [[feedback-ios-xcuitest-gui]].
- **CI auf self-hosted Mac mini** (Runner `[self-hosted, ios, mac-mini-buero, familienplaner]`, von Jenna `598d4c2`
  vorbereitet) statt GitHub-hosted — build/uitest/testflight. **Vor Push `git fetch`+rebase (shared Runner/Repo)!**
- Ergebnis: Build Check ✓ + TestFlight ✓ (App mit allen Bereichen hochgeladen), XCUITest 4/4.

**Stand (2026-07-13, HEAD `7ae6414`): Backend + iOS LIVE — Samu/Garten/Geschenkplaner als native iOS-Bereiche + Per-User-Login-Keys.**

**NEU 2026-07-13 — Native Bereiche + Per-User-Keys (Details: [[session-2026-07-13_native-bereiche-und-per-user-keys]]):**
- **3 native iOS-Bereiche** ersetzen den generischen Browser: `App/Sources/Samu|Garten|Geschenke/` (Routing in
  `Views/Bereiche.swift`). Volle Feature/Filter/Sicht-Parität zur PWA, aber **native iOS-Bedienung** (Segment-Tabs,
  Filter-Pills/Menüs, Live-Suche, Pull-to-Refresh, Pivot-Matrizen, Garten-GTS via Swift Charts + interaktive Timelines,
  Geschenke-Tinder-Bewerten). Geteilte Basis `App/Sources/Support/` (CompatClient=bare-array `/api`-Client, Coerce, AreaUI-Atome).
- **Per-User-Login-Keys LIVE:** Migration `0010` (owner auf api_keys/device_tokens/foto_inbox), Bootstrap
  `BOOTSTRAP_LARS_API_KEY`/`BOOTSTRAP_ELITA_API_KEY`, owner-gezielte Push mit Broadcast-Fallback, `/auth/me`+iOS-Settings
  zeigen Person. **OFFEN (Lars, Coolify):** die 2 ENV-Keys setzen + Redeploy → dann Lars & Elita je eigenen Key in iOS-Login.
- **Standing Order** (neu): native iOS-UX statt PWA-Klon MIT voller Parität; iOS-Builds sparsam bündeln (1 großer, autonom).
  [[feedback-ios-native-not-pwa-clone]]. Lessons: Shared-UI-Atom-Namen gegen GANZE Codebasis prüfen (StatTile-Kollision);
  `async let`-Init ohne `await`/`try?`.

**Stand (2026-07-12, HEAD `312a8a8`): Backend + iOS LIVE — Abfuhrkalender (Müll-Termine) komplett + Legacy-Backup Supabase/Lovable gesichert.**

**NEU 2026-07-12 — Abfuhrkalender + Legacy-Backup (Details: [[session-2026-07-12_abfuhr-und-backup]]):**
- **Abfuhrkalender** neuer Lebensbereich: Backend (`server/abfuhr/*`, Routen `/abfuhr/{import-ics,next,sync-aha,calendar}`,
  Migration 0008/0009, Jobs `abfuhr-reminder` 19-Uhr-Vorabend + `abfuhr-aha-sync` monatlich) + **aha-region.de Auto-Sync**
  (3-Schritt-Formular, kein jährliches ICS-Upload; live 37 Termine) + iOS Heute-Karte + **native Kategorie-Ansicht**
  `Views/AbfuhrCalendarView.swift` (Bereich `abfuhrkalender`→native). Lokale Vorabend-Erinnerung 19 Uhr (offline).
- **Legacy-Backup** (Lars will Lovable+Supabase löschen): `_reference/elisbooks-original-backup-20260712/` — pristine
  Supabase (Daten 346/7/5/5 + 8 Migrationen + 5 Edge Functions inkl. **canopy-proxy** = nie migriert) + kompletter
  Lovable-Quellcode (264 Dateien). **Migration 1:1 verifiziert** (IDs identisch, 0 Verlust). ⚠️ `_reference/` git-ignored →
  Backup NUR lokal. **OFFEN: Lars fragen ob off-site ins Git committen** (`git add -f …`), DANN darf er löschen.
- Per-User-Login-Keys: ✅ umgesetzt am 2026-07-13 (siehe NEU-Block oben).

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
