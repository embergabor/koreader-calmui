#!/bin/sh
# Copy Quiet UI (plugin, patches, fonts, dictionary) onto the Kobo's KOReader install, then eject.
#   ./deploy-to-kobo.sh [--no-eject]
set -e
cd "$(dirname "$0")"
KOBO=/Volumes/KOBOeReader
KOREADER="$KOBO/.adds/koreader"

[ -d "$KOREADER/plugins" ] || { echo "Kobo not mounted (or KOReader not installed) at $KOBO" >&2; exit 1; }

# Plugins replaced by Quiet UI
rm -rf "$KOREADER/plugins/readerbar.koplugin" "$KOREADER/plugins/typolibrary.koplugin"

COPYFILE_DISABLE=1 rsync -r --delete --exclude '._*' --exclude '.DS_Store' \
    mods/plugins/quietui.koplugin "$KOREADER/plugins/"
mkdir -p "$KOREADER/patches"
COPYFILE_DISABLE=1 rsync -r --exclude '._*' --exclude '.DS_Store' mods/patches/ "$KOREADER/patches/"
mkdir -p "$KOBO/fonts"
COPYFILE_DISABLE=1 rsync -r --exclude '._*' --exclude '.DS_Store' --include '*.ttf' --include '*.otf' --exclude '*' \
    fonts/ "$KOBO/fonts/"

mkdir -p "$KOREADER/data/dict"
COPYFILE_DISABLE=1 rsync -r --exclude '._*' --exclude '.DS_Store' dict/ "$KOREADER/data/dict/"

find "$KOREADER/plugins/quietui.koplugin" "$KOREADER/patches" "$KOBO/fonts" "$KOREADER/data/dict" -name '._*' -delete
sync
echo "Deployed Quiet UI to $KOBO"

[ "$1" = "--no-eject" ] || diskutil eject "$KOBO"
