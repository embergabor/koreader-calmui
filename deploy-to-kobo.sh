#!/bin/sh
# Copy the plugins in mods/plugins onto the Kobo's KOReader install, then eject.
#   ./deploy-to-kobo.sh [--no-eject]
set -e
cd "$(dirname "$0")"
KOBO=/Volumes/KOBOeReader
DEST="$KOBO/.adds/koreader/plugins"

[ -d "$DEST" ] || { echo "Kobo not mounted (or KOReader not installed) at $KOBO" >&2; exit 1; }

for plugin in mods/plugins/*.koplugin; do
    COPYFILE_DISABLE=1 rsync -r --delete --exclude '._*' --exclude '.DS_Store' "$plugin" "$DEST/"
    echo "copied $(basename "$plugin")"
done
find "$DEST" -name '._*' -delete
sync

[ "$1" = "--no-eject" ] || diskutil eject "$KOBO"
