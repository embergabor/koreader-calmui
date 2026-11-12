#!/bin/sh
# Builds Calm UI as one package for KOReader's own updater. Copied to .adds/koreader/ota/update.tar.xz on
# the Kobo, it's unpacked on the Kobo at KOReader's next start, so the computer writes only that file.
#   tools/make-package.sh OUT [public_key]
# The key is only for your own devices: it lets deploy-to-kobo.sh --wifi log in. Release packages have none.
set -e
case "$1" in
    "") echo "usage: tools/make-package.sh OUT [public_key]" >&2; exit 1 ;;
    /*) OUT="$1" ;;
    *) OUT="$PWD/$1" ;;
esac
KEY="$2"
[ -z "$KEY" ] || [ -f "$KEY" ] || { echo "No key at $KEY" >&2; exit 1; }
case "$KEY" in /*|"") ;; *) KEY="$PWD/$KEY" ;; esac
cd "$(dirname "$0")/.."

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/koreader/plugins" "$STAGE/koreader/patches" "$STAGE/koreader/data"
cp -R mods/plugins/quietui.koplugin "$STAGE/koreader/plugins/"
cp -R mods/patches/. "$STAGE/koreader/patches/"
# USB storage screen: same program, smaller text, no giant logo
cp mods/usbms/KoboUSBMS.tar.gz "$STAGE/koreader/data/"
if [ -n "$KEY" ]; then
    mkdir -p "$STAGE/koreader/settings/SSH"
    cp "$KEY" "$STAGE/koreader/settings/SSH/authorized_keys"
fi
# Never an ota/package.index in here: the updater would take it as KOReader's file list and
# delete whatever isn't on it.
mkdir -p "$(dirname "$OUT")"
COPYFILE_DISABLE=1 tar --format ustar --no-xattrs --uid 0 --gid 0 --exclude '._*' --exclude '.DS_Store' \
    -cJf "$OUT" -C "$STAGE" koreader
