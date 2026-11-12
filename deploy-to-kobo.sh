#!/bin/sh
# Install Calm UI (plugin, patches, fonts, dictionary) on the Kobo's KOReader.
#   ./deploy-to-kobo.sh [--no-eject]     over USB, then eject. KOReader unpacks it at its next start.
#                                        Checks KOReader first, and installs it and NickelMenu if missing.
#   ./deploy-to-kobo.sh --check          after that, with the Kobo connected again: did it all arrive?
#   ./deploy-to-kobo.sh --wifi [address | elipsa | libra] [--all]
#       Over Wi-Fi, then restart KOReader. Needs one USB install first, and Updates over Wi-Fi
#       turned on in the cogwheel, which shows the address. Each device's address is remembered
#       under its name; with neither, the last one used. Fonts and the dictionary only come
#       along with --all.
set -e
cd "$(dirname "$0")"
KOBO="${KOBO:-/Volumes/KOBOeReader}" # Depot passes the volume it found, in case there are two Kobos
KOREADER="$KOBO/.adds/koreader"
SSH_KEY="$HOME/.ssh/id_kobo"

if [ "$1" = "--wifi" ]; then
    shift
    exec tools/deploy-wifi.sh "$@"
fi

[ -d "$KOBO/.kobo" ] || { echo "Kobo not mounted at $KOBO" >&2; exit 1; }
. tools/koreader-base.sh

# The Mac's FAT driver can write directory entries the Kobo's disk check rejects when it's
# unplugged: it renames the file to FSCK0000.000, so the plugin no longer loads. Only a few
# rarely changing files are written from here, and KOReader's own updater unpacks the rest
# on the Kobo.
if [ "$1" = "--check" ]; then
    problems=0
    report() { echo "PROBLEM: $*"; problems=$((problems + 1)); }
    [ ! -f "$KOBO/.kobo/KoboRoot.tgz" ] || report "NickelMenu not applied yet: eject the Kobo and let it restart"
    [ -f "$KOBO/.adds/nm/koreader" ] || report "the NickelMenu entry for KOReader is missing"
    fetch_package "$KOREADER_PKG" "$KOREADER_URL" "$KOREADER_SHA"
    koreader_problems > /tmp/kobo-check.$$
    while IFS= read -r line; do report "$line"; done < /tmp/kobo-check.$$
    rm -f /tmp/kobo-check.$$
    [ -f "$KOREADER/git-rev" ] || { echo "$problems problem(s). Nothing was changed."; exit 1; }
    [ ! -f "$KOREADER/ota/update.tar.xz" ] || report "not unpacked yet: open KOReader on the Kobo first"
    for found in $(find "$KOREADER/plugins" "$KOREADER/patches" "$KOREADER/settings/SSH" "$KOBO/fonts" "$KOREADER/data/dict" -name 'FSCK*' 2>/dev/null); do
        report "renamed by the disk check: $found"
    done
    diff -rq -x '._*' -x '.DS_Store' mods/plugins/quietui.koplugin "$KOREADER/plugins/quietui.koplugin" |
        grep -v "^Only in $KOREADER" > /tmp/kobo-check.$$ || true
    while IFS= read -r line; do report "$line"; done < /tmp/kobo-check.$$
    rm -f /tmp/kobo-check.$$
    for patch in mods/patches/*; do
        cmp -s "$patch" "$KOREADER/patches/$(basename "$patch")" || report "patch differs or is missing: $(basename "$patch")"
    done
    # Errors from KOReader's last start only
    last_start="$(grep -n 'Applying patch: ./patches/1-quietui-fonts' "$KOREADER/crash.log" | tail -1 | cut -d: -f1)"
    if [ -n "$last_start" ]; then
        tail -n +"$last_start" "$KOREADER/crash.log" | grep -E 'Failed to initialize|stack traceback|attempt to ' | cut -c1-200 > /tmp/kobo-check.$$ || true
        while IFS= read -r line; do report "log: $line"; done < /tmp/kobo-check.$$
        rm -f /tmp/kobo-check.$$
    fi
    if [ "$problems" -ne 0 ]; then
        echo "$problems problem(s). Nothing was changed."
        exit 1
    fi
    # All there: clear out files the new version no longer has.
    (cd "$KOREADER/plugins/quietui.koplugin" && for f in *; do
        [ -e "$OLDPWD/mods/plugins/quietui.koplugin/$f" ] || { rm -rf "./$f"; echo "Removed old file: $f"; }
    done)
    sync
    echo "All good: every file arrived and KOReader started without errors."
    exit 0
fi

ensure_koreader

# The key updates over Wi-Fi log in with
[ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "kobostuff deploy" -f "$SSH_KEY"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
tools/make-package.sh "$STAGE/update.tar.xz" "$SSH_KEY.pub"
mkdir -p "$KOREADER/ota"
COPYFILE_DISABLE=1 cp "$STAGE/update.tar.xz" "$KOREADER/ota/update.tar.xz"

# Plugins replaced by Calm UI
rm -rf "$KOREADER/plugins/readerbar.koplugin" "$KOREADER/plugins/typolibrary.koplugin"

# Only rewritten when changed. --inplace: rsync's temporary files clash with FAT's short names.
# Both are optional, and not in git: fonts/ goes to the Kobo's fonts folder, dict/ to KOReader's.
if [ -d fonts ]; then
    mkdir -p "$KOBO/fonts"
    COPYFILE_DISABLE=1 rsync -r --inplace --size-only --exclude '._*' --exclude '.DS_Store' --include '*.ttf' --include '*.otf' --exclude '*' \
        fonts/ "$KOBO/fonts/"
fi
if [ -d dict ]; then
    mkdir -p "$KOREADER/data/dict"
    COPYFILE_DISABLE=1 rsync -r --inplace --size-only --exclude '._*' --exclude '.DS_Store' dict/ "$KOREADER/data/dict/"
fi
# macOS adds these for new folders too, so the whole .adds tree is cleaned here, last.
find "$KOBO/.adds" "$KOBO/fonts" -name '._*' -type f -delete
rm -f "$KOBO/.kobo/._KoboRoot.tgz"
sync
echo "Copied to $KOBO. Open KOReader from the Kobo's home screen; it unpacks at that start."
[ ! -f "$KOBO/.kobo/KoboRoot.tgz" ] || echo "First, after the eject, the Kobo restarts to apply NickelMenu. KOReader is then in its main menu."
echo "Then connect the Kobo again and run: ./deploy-to-kobo.sh --check"

[ "$1" = "--no-eject" ] || diskutil eject "$KOBO"
