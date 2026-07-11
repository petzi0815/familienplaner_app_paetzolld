#!/usr/bin/env bash
# Restore von DB (+ optional Media) aus einem Backup. Danach App neu starten/deployen.
# Nutzung: restore.sh <familienplaner-YYYYMMDD-HHMMSS.db> [media-YYYYMMDD-HHMMSS.tar.gz]
set -euo pipefail
DATA_DIR="${DATA_DIR:-/data}"
DB_BACKUP="${1:?DB-Backup-Datei angeben}"
MEDIA_BACKUP="${2:-}"

# WAL/SHM entfernen, damit die restaurierte DB sauber übernommen wird.
rm -f "$DATA_DIR/familienplaner.db-wal" "$DATA_DIR/familienplaner.db-shm"
cp "$DB_BACKUP" "$DATA_DIR/familienplaner.db"
echo "DB wiederhergestellt aus $DB_BACKUP"

if [ -n "$MEDIA_BACKUP" ] && [ -f "$MEDIA_BACKUP" ]; then
  rm -rf "$DATA_DIR/media"
  tar -xzf "$MEDIA_BACKUP" -C "$DATA_DIR"
  echo "Media wiederhergestellt aus $MEDIA_BACKUP"
fi
echo "Fertig — App neu starten (Coolify: Redeploy/Restart)."
