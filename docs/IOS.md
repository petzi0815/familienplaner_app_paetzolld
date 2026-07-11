# iOS-App — Setup, Signing & TestFlight

Native SwiftUI-App unter `ios-app/` für **iOS 26** (Liquid Glass, nur neueste iPhones).
Build via **XcodeGen + Fastlane → TestFlight** (GitHub Actions, macOS-Runner).
Zwei Targets: **App** + **Widget-Extension**.

## Was die App macht
Login (Server-URL + API-Key) → Tabs im iOS-26-Liquid-Glass-Look:
- **Heute** — Dashboard (`GET /api/v1/dashboard/today`): anstehende Termine, Erinnerungen, nächste Reise,
  MHD-Warnungen, Foto-Inbox-Zähler. Kalender-Button pro Termin (EventKit).
- **Foto** — Kamera/Mediathek → Bereich wählen → hochladen (`POST /api/v1/foto/upload`).
  **On-Device-KI** (Vision + Foundation Models) schlägt den Lebensbereich vor (ab iPhone 15 Pro).
- **Inbox** — hochgeladene Fotos + Status (Grid).
- **Scannen** — Buch (ISBN, Open-Library-Lookup → `elisbooks-books`) & Lebensmittel
  (EAN, Open-Food-Facts → `vorrat-lebensmittel`) per VisionKit-Barcode-Scanner.
- **Mehr** — Reisen-Karte (MapKit), Konto/Server.
- **Suchen** — ressourcenübergreifende Volltextsuche (Such-Rolle der Tab-Bar).

Weiteres: **Siri/Spotlight-Kurzbefehle** („Was steht heute an", „Zum Vorrat hinzufügen", „Buch scannen"),
**lokale Erinnerungen** (Termine/MHD, offline), **Widgets** (Home-/Sperrbildschirm/StandBy),
**APNs-Push** („Foto zugeordnet").

## Verwendete iOS-26-Frameworks & Capabilities
| Feature | Framework | Voraussetzung |
|---|---|---|
| Liquid Glass UI | SwiftUI (iOS 26) | Deployment-Target 26.0, Xcode 26 |
| Barcode-Scanner | VisionKit `DataScannerViewController` | Kamera-Berechtigung (in Info.plist) |
| On-Device-KI | Vision + **FoundationModels** (Beta) | iPhone 15 Pro+ / Apple Intelligence an — sonst automatischer Fallback |
| Kalender | EventKit (write-only) | `NSCalendarsWriteOnlyAccessUsageDescription` (in Info.plist) |
| Erinnerungen | UserNotifications | Push-Berechtigung (schon für APNs erteilt) |
| Reise-Karte | MapKit + CoreLocation | — |
| Widgets | WidgetKit | **App Group** + eigenes App-ID/Profil (s. u.) |
| Push | APNs | Push-Capability + Backend-Env (s. u.) |

## Einmalige Voraussetzungen (Lars, Apple-seitig)
1. **App-Record in App Store Connect** — Bundle-ID `app.yagemi.familienplaner`, Name „Familienplaner".
2. **App Store Connect API-Key** (`.p8`) — Users and Access → Integrations.
3. **Distribution-Zertifikat** (`Apple Distribution`, `.p12`) — team-weit, aus dem Referenzprojekt wiederverwendbar.
4. **Capabilities für die App-ID** `app.yagemi.familienplaner` (Developer-Portal):
   - **Push Notifications**
   - **App Groups** → Gruppe `group.app.yagemi.familienplaner` anlegen/zuweisen
5. **Zweite App-ID für das Widget**: `app.yagemi.familienplaner.widgets` mit derselben **App-Groups**-Capability
   (Gruppe `group.app.yagemi.familienplaner`).
6. **Zwei App-Store-Provisioning-Profile** erzeugen: eins je App-ID (App + Widget).

> Ohne das Widget-Profil schlägt der Archive-Build fehl (die App bettet die Extension ein). Falls du das
> Widget vorerst NICHT ausliefern willst: in `ios-app/project.yml` das Target `FamilienplanerWidgets` und die
> `dependencies:`-Zeile im App-Target entfernen — dann entfallen alle `WIDGET_*`-Secrets und die App-Group-Capability.

## GitHub Repo-Konfiguration
**Variables** (Settings → Secrets and variables → Actions → Variables):
- `APPLE_TEAM_ID` — Team-ID
- `APP_PROFILE_NAME` — exakter Name des App-Profils
- `WIDGET_PROFILE_NAME` — exakter Name des Widget-Profils

**Secrets** (Settings → Secrets):
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`
- `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`
- `APP_PROFILE_BASE64` (`base64 -i app.mobileprovision`)
- `WIDGET_PROFILE_BASE64` (`base64 -i widget.mobileprovision`)

## Workflow aktivieren
Der Workflow liegt deaktiviert unter `.github/workflows-disabled/ios.yml`:
```bash
git mv .github/workflows-disabled/ios.yml .github/workflows/ios.yml
gh auth refresh -s workflow      # Push von workflows/ braucht workflow-Scope
git commit -am "ci: iOS-TestFlight-Workflow aktivieren" && git push
```
Danach: Push auf `main` mit Änderungen unter `ios-app/**` → signierter Build (App + Widget) → internes TestFlight.
Manuell: Actions → „iOS TestFlight" → Run workflow.

## Versionen
Runner `macos-15` (bei fehlendem Xcode 26 auf `macos-26` heben) · Xcode **26.0** · Ruby `3.3` ·
fastlane `~> 2.226` · XcodeGen `≥ 2.38` · Deployment-Target iOS **26.0** · Signing: Manual / `Apple Distribution`.

## Push (APNs) — „Foto zugeordnet"-Benachrichtigung
Die App registriert beim Start ihr Device-Token (`POST /api/v1/push/register`). Wenn Ole ein Foto
zuordnet (`PATCH /api/v1/foto-inbox/{id} {status:"zugeordnet"}`), sendet das Backend automatisch einen
Push. Ole kann zusätzlich `POST /api/v1/push/send { title, body }` aufrufen.

**Backend (Coolify-Env) — der APNs-Auth-Key ist team-weit und aus dem Referenzprojekt wiederverwendbar,
nur die Bundle-ID unterscheidet sich:**
```
APNS_KEY_P8=<base64 der AuthKey_XXXX.p8>
APNS_KEY_ID=<...>
APPLE_TEAM_ID=<...>
APNS_BUNDLE_ID=app.yagemi.familienplaner
```
Ohne diese Env sind Pushes stille No-Ops. Status: `GET /api/v1/push/status` (admin) → `{enabled, devices}`.

## Signing-Secrets vorbereiten (Helfer)
`ios-app/tools/prepare-signing.sh <p8> <p12> <mobileprovision>` base64-kodiert die Dateien und gibt die
`gh secret set` / `gh variable set`-Befehle aus. **ASC-API-Key + Distribution-Zertifikat sind team-weit**;
**neu** sind die beiden Provisioning-Profile (App + Widget) für die neuen Bundle-IDs.

## Lokal auf dem Mac
```bash
cd ios-app && brew install xcodegen && xcodegen generate && open Familienplaner.xcodeproj
```
Zum Testen am Gerät ein eigenes Debug-Signing-Team in Xcode wählen. Foundation Models & Liquid Glass
brauchen einen iOS-26-Simulator/Device; die On-Device-KI läuft nur auf iPhone 15 Pro+ mit aktivierter
Apple Intelligence (sonst greift der Fallback).
