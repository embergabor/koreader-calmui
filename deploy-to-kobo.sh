#!/bin/sh
# Copy Quiet UI (plugin, patches, fonts, dictionary) onto the Kobo's KOReader install.
#   ./deploy-to-kobo.sh [--no-eject]     over USB, then eject
#   ./deploy-to-kobo.sh --wifi [address] [--all]
#       Over Wi-Fi, then restart KOReader. Needs one USB install first, and Updates over Wi-Fi
#       turned on in the cogwheel, which shows the address. The last address is remembered.
#       Fonts and the dictionary only come along with --all.
set -e
cd "$(dirname "$0")"
KOBO=/Volumes/KOBOeReader
SSH_KEY="$HOME/.ssh/id_kobo"

if [ "$1" = "--wifi" ]; then
    shift
    exec tools/deploy-wifi.sh "$@"
fi

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

# The key updates over Wi-Fi log in with
[ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "kobostuff deploy" -f "$SSH_KEY"
mkdir -p "$KOREADER/settings/SSH"
touch "$KOREADER/settings/SSH/authorized_keys"
grep -qF "$(cat "$SSH_KEY.pub")" "$KOREADER/settings/SSH/authorized_keys" ||
    cat "$SSH_KEY.pub" >> "$KOREADER/settings/SSH/authorized_keys"

# USB storage screen: same program, smaller text, no giant logo
cp mods/usbms/KoboUSBMS.tar.gz "$KOREADER/data/KoboUSBMS.tar.gz"

mkdir -p "$KOREADER/data/dict"
COPYFILE_DISABLE=1 rsync -r --inplace --exclude '._*' --exclude '.DS_Store' dict/ "$KOREADER/data/dict/"

find "$KOREADER/plugins/quietui.koplugin" "$KOREADER/patches" "$KOREADER/settings/SSH" "$KOBO/fonts" "$KOREADER/data/dict" -name '._*' -delete
sync
echo "Deployed Quiet UI to $KOBO"

[ "$1" = "--no-eject" ] || diskutil eject "$KOBO"
