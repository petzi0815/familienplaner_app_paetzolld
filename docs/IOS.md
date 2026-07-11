# iOS-App — Setup, Signing & TestFlight

Native SwiftUI-App unter `ios-app/`. Build via **XcodeGen + Fastlane → TestFlight** (GitHub Actions,
macOS-Runner). Muster 1:1 aus dem Referenzprojekt (manuelles Signing, ASC-API-Key, base64-Secrets).

## Was die App macht
Login (Server-URL + API-Key) → 3 Tabs: **Foto** (Kamera/Mediathek → Bereich wählen → hochladen),
**Inbox** (hochgeladene Fotos + Status), **Einstellungen**. Uploads gehen an `POST /api/v1/foto/upload`
(Foto-Eingang, Status `neu`); Ole holt sie via `GET /api/v1/foto-inbox?status=neu` und ordnet zu.

## Einmalige Voraussetzungen (Lars, Apple-seitig)
1. **App-Record in App Store Connect anlegen** — Apple erlaubt das nicht per API-Key.
   Bundle-ID: `app.yagemi.familienplaner`, Name „Familienplaner".
2. **App Store Connect API-Key** (`.p8`) erstellen (Users and Access → Integrations → App Store Connect API).
3. **Distribution-Zertifikat** (`Apple Distribution`, `.p12`) + **Provisioning-Profil** (App Store, für die Bundle-ID).

## GitHub Repo-Konfiguration
**Variables** (Settings → Secrets and variables → Actions → Variables):
- `APPLE_TEAM_ID` — Developer-Portal-Team-ID
- `APP_PROFILE_NAME` — exakter Name des Provisioning-Profils

**Secrets** (Settings → Secrets):
- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (`base64 -i AuthKey_XXX.p8`)
- `DIST_CERT_P12_BASE64` (`base64 -i dist.p12`), `DIST_CERT_PASSWORD`
- `APP_PROFILE_BASE64` (`base64 -i app.mobileprovision`)

(Kein Widget → keine `WIDGET_*`-Secrets nötig.)

## Workflow aktivieren
Der Workflow liegt deaktiviert unter `.github/workflows-disabled/ios.yml`:
```bash
git mv .github/workflows-disabled/ios.yml .github/workflows/ios.yml
gh auth refresh -s workflow      # Push von workflows/ braucht workflow-Scope
git commit -am "ci: iOS-TestFlight-Workflow aktivieren" && git push
```
Danach: Push auf `main` mit Änderungen unter `ios-app/**` → signierter Build → internes TestFlight.
Manuell: Actions → „iOS TestFlight" → Run workflow.

## Versionen (aus dem Referenzmuster)
Runner `macos-15` · Xcode `latest-stable` · Ruby `3.3` · fastlane `~> 2.226` · XcodeGen `≥ 2.38` ·
Deployment-Target iOS `17.0` · Signing: Manual / `Apple Distribution`.

## Push (APNs) — „Foto zugeordnet"-Benachrichtigung
Die App registriert beim Start ihr Device-Token (`POST /api/v1/push/register`). Wenn Ole ein Foto
zuordnet (`PATCH /api/v1/foto-inbox/{id} {status:"zugeordnet"}`), sendet das Backend automatisch einen
Push. Ole kann zusätzlich jederzeit `POST /api/v1/push/send { title, body }` aufrufen.

**Backend (Coolify-Env) — der APNs-Auth-Key ist team-weit und aus dem Referenzprojekt wiederverwendbar
(`C:\bin\placetel-elevenlabs-asterix-bridge\.env`), nur die Bundle-ID unterscheidet sich:**
```
APNS_KEY_P8=<wie im Referenz-.env — base64 der AuthKey_XXXX.p8>
APNS_KEY_ID=<wie im Referenz-.env>
APPLE_TEAM_ID=<wie im Referenz-.env>
APNS_BUNDLE_ID=app.yagemi.familienplaner
```
Ohne diese Env sind Pushes stille No-Ops. Status prüfen: `GET /api/v1/push/status` (admin) → `{enabled, devices}`.

**Apple-seitig:** Für die App-ID `app.yagemi.familienplaner` die Capability **Push Notifications**
aktivieren (Developer-Portal) und das Provisioning-Profil neu erzeugen. Das Entitlement
`aps-environment: production` steckt bereits in `project.yml` (xcodegen erzeugt die `.entitlements`).

## Signing-Secrets vorbereiten (Helfer)
`ios-app/tools/prepare-signing.sh <p8> <p12> <mobileprovision>` base64-kodiert die Dateien und gibt die
`gh secret set` / `gh variable set`-Befehle aus. **ASC-API-Key + Distribution-Zertifikat sind team-weit**
(aus dem Referenzprojekt wiederverwendbar); **neu** ist nur das Provisioning-Profil für die neue Bundle-ID.

## Lokal auf dem Mac
```bash
cd ios-app && brew install xcodegen && xcodegen generate && open Familienplaner.xcodeproj
```
Zum Testen am Gerät ein eigenes Debug-Signing-Team in Xcode wählen (die manuelle Distribution-Konfig gilt nur für den CI-Release).
