# ios-app/ — Platzhalter für die native iOS-App (später)

Noch nicht implementiert. Die REST-API (`/api/v1`) wird von Anfang an iOS-tauglich gebaut:
versioniert, Token-Auth (API-Key), OpenAPI (Swift-Codegen später), stabile Media-URLs.

Geplant analog zum Referenzprojekt (`placetel-elevenlabs-asterix-bridge/ios-app/`):
native SwiftUI, `project.yml` (XcodeGen), `fastlane` → TestFlight, GitHub-Actions-Workflow
`.github/workflows-disabled/ios.yml` (aktivieren, sobald die App existiert).
