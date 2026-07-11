#!/usr/bin/env bash
# Kodiert die Signing-Dateien base64 und gibt die gh-Befehle aus, um sie als
# GitHub-Repo-Secrets/Variables zu setzen. Nichts wird automatisch gepusht.
# Nutzung: ./prepare-signing.sh AuthKey_XXX.p8 dist.p12 app.mobileprovision
set -euo pipefail
P8="${1:?ASC-API-Key .p8 angeben}"
P12="${2:?Distribution .p12 angeben}"
PROFILE="${3:?Provisioning-Profil .mobileprovision angeben}"
b64() { base64 -w0 "$1" 2>/dev/null || base64 "$1"; }

echo "# 1) Secrets setzen (Werte werden nicht angezeigt):"
echo "gh secret set ASC_KEY_P8_BASE64      --body \"\$(base64 -w0 '$P8')\""
echo "gh secret set DIST_CERT_P12_BASE64   --body \"\$(base64 -w0 '$P12')\""
echo "gh secret set APP_PROFILE_BASE64     --body \"\$(base64 -w0 '$PROFILE')\""
echo "gh secret set ASC_KEY_ID             # 10-stellige Key-ID"
echo "gh secret set ASC_ISSUER_ID          # Issuer-ID (ASC → Integrations)"
echo "gh secret set DIST_CERT_PASSWORD     # Passwort der .p12 (leer erlaubt)"
echo ""
echo "# 2) Variables setzen:"
echo "gh variable set APPLE_TEAM_ID        # Developer-Team-ID"
echo "gh variable set APP_PROFILE_NAME     # exakter Name des Provisioning-Profils"
echo ""
echo "# Hinweis: ASC-API-Key + Distribution-.p12 sind team-weit (aus dem Referenzprojekt"
echo "# wiederverwendbar). NEU ist nur das Provisioning-Profil für app.yagemi.familienplaner."
