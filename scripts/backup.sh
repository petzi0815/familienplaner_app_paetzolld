#!/usr/bin/env bash
# Voll-Backup (DB + Media) auf Dateiebene — auf dem VPS gegen das Coolify-Volume ausführen.
# Für DB-only-Backups im laufenden Container reicht: POST /api/v1/debug/backup (admin).
set -euo pipefail
DATA_DIR="${DATA_DIR:-/data}"
OUT="${1:-$DATA_DIR/backups}"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# DB konsistent kopieren: WAL zuerst in die Haupt-DB schreiben (falls sqlite3 vorhanden),
# sonst .db + .db-wal zusammen sichern.
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$DATA_DIR/familienplaner.db" "VACUUM INTO '$OUT/familienplaner-$TS.db'"
else
  cp "$DATA_DIR/familienplaner.db" "$OUT/familienplaner-$TS.db"
  [ -f "$DATA_DIR/familienplaner.db-wal" ] && cp "$DATA_DIR/familienplaner.db-wal" "$OUT/familienplaner-$TS.db-wal" || true
fi

# Media
if [ -d "$DATA_DIR/media" ]; then
  tar -czf "$OUT/media-$TS.tar.gz" -C "$DATA_DIR" media
fi

echo "Backup abgelegt in $OUT:"
ls -lh "$OUT" | tail -n +2
