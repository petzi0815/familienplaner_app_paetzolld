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

## Lokal auf dem Mac
```bash
cd ios-app && brew install xcodegen && xcodegen generate && open Familienplaner.xcodeproj
```
Zum Testen am Gerät ein eigenes Debug-Signing-Team in Xcode wählen (die manuelle Distribution-Konfig gilt nur für den CI-Release).
