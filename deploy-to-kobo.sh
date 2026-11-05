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

# --inplace: rsync's temporary files clash with FAT's short names, which fsck then renames to FSCK*.
COPYFILE_DISABLE=1 rsync -r --inplace --delete --exclude '._*' --exclude '.DS_Store' \
    mods/plugins/quietui.koplugin "$KOREADER/plugins/"
mkdir -p "$KOREADER/patches"
COPYFILE_DISABLE=1 rsync -r --inplace --exclude '._*' --exclude '.DS_Store' mods/patches/ "$KOREADER/patches/"
mkdir -p "$KOBO/fonts"
COPYFILE_DISABLE=1 rsync -r --inplace --exclude '._*' --exclude '.DS_Store' --include '*.ttf' --include '*.otf' --exclude '*' \
    fonts/ "$KOBO/fonts/"

# USB storage screen: same program, smaller text, no giant logo
cp mods/usbms/KoboUSBMS.tar.gz "$KOREADER/data/KoboUSBMS.tar.gz"

mkdir -p "$KOREADER/data/dict"
COPYFILE_DISABLE=1 rsync -r --inplace --exclude '._*' --exclude '.DS_Store' dict/ "$KOREADER/data/dict/"

find "$KOREADER/plugins/quietui.koplugin" "$KOREADER/patches" "$KOBO/fonts" "$KOREADER/data/dict" -name '._*' -delete
sync
echo "Deployed Quiet UI to $KOBO"

[ "$1" = "--no-eject" ] || diskutil eject "$KOBO"
