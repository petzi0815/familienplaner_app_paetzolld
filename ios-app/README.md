# ios-app/ — Familienplaner (native SwiftUI)

Schlanke iPhone-App zum **Aufnehmen einzelner Fotos** und groben Zuordnen zu einem Lebensbereich.
Die Fotos landen im **Foto-Eingang** (`POST /api/v1/foto/upload`, Status `neu`); der Agent „Ole"
analysiert und kategorisiert sie später in die Datenbank.

## Aufbau
- **Ein Target** (SwiftUI, iOS 17+), Bundle-ID `app.yagemi.familienplaner`.
- `App/Sources/` — App-Entry, `Settings` (Base-URL + API-Key im Keychain), `APIClient`
  (Bearer gegen `/api/v1`, multipart Foto-Upload), `ImagePicker` (Kamera/Mediathek),
  Views (Login, Foto, Inbox, Einstellungen).
- Muster (Keychain, API-Client, Multipart-Upload, xcodegen/fastlane) übernommen aus dem
  Referenzprojekt `placetel-elevenlabs-asterix-bridge/ios-app`.

## Build
Die `.xcodeproj` wird **nicht** committet, sondern auf dem CI-Runner erzeugt:
```bash
brew install xcodegen
cd ios-app && xcodegen generate      # erzeugt Familienplaner.xcodeproj
open Familienplaner.xcodeproj        # lokal (Mac) — oder via GitHub Actions bauen
```
TestFlight-Build läuft über GitHub Actions (`.github/workflows-disabled/ios.yml` → nach
`workflows/` verschieben). Signing/Secrets: **`docs/IOS.md`**.

## Anmeldung in der App
Server-URL (`https://familienplaner.yagemi.app`) + **API-Key** (Rolle `agent`) eingeben —
derselbe Key wie für Ole. Wird sicher im Schlüsselbund gespeichert.
