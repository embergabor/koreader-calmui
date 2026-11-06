# KOReader and NickelMenu on the Kobo: which versions Quiet UI is built against, how to check them,
# and how to install them over USB. Sourced by deploy-to-kobo.sh.

KOREADER_REV=v2026.07.2-293-gc8eb592_2026-10-27_kobo
KOREADER_PKG=downloads/koreader-kobo/koreader-kobo.targz
KOREADER_URL=https://github.com/koreader/koreader/releases/download/ota/koreader-kobo-v2026.07.2-293-gc8eb592_2026-10-27.targz
KOREADER_SHA=8c3cee24019abd309da1f779c71e75d18e71d8a895edb1d08011c80c9bfac4b1
NICKELMENU_PKG=downloads/nickelmenu/KoboRoot.tgz
NICKELMENU_URL=https://github.com/pgaskin/NickelMenu/releases/download/v0.6.0/KoboRoot.tgz
NICKELMENU_SHA=322ff9aa863860e8f5f7e0b55cae561c54bf95983b9bce1d19819d1225d064af
NICKELMENU_ENTRY='menu_item :main :KOReader :cmd_spawn :quiet :exec /mnt/onboard/.adds/koreader/koreader.sh'

# fetch_package file url sha256: downloads it if it isn't here yet, and refuses a file that differs.
fetch_package() {
    if [ ! -f "$1" ]; then
        echo "Downloading $(basename "$1")…"
        mkdir -p "$(dirname "$1")"
        curl -sSLf -o "$1.part" "$2" || { rm -f "$1.part"; echo "Couldn't download $2" >&2; return 1; }
        mv "$1.part" "$1"
    fi
    [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$3" ] || { echo "$1 isn't the expected file. Nothing was changed." >&2; return 1; }
}

# koreader_problems: prints what's wrong with KOReader on the Kobo, and nothing if it's fine.
# Left out: the ota folder, which KOReader's updater changes, and the marker its first start removes.
koreader_problems() {
    [ -f "$KOREADER/git-rev" ] || { echo "KOReader isn't installed"; return 0; }
    have="$(cat "$KOREADER/git-rev")"
    [ "$have" = "$KOREADER_REV" ] || echo "KOReader is $have, Quiet UI is built for $KOREADER_REV"
    tar tzf "$KOREADER_PKG" | grep -Ev '^koreader/(ota/|update_once\.marker$)' | while IFS= read -r file; do
        [ -f "$KOBO/.adds/$file" ] || echo "KOReader file missing: $file"
    done
    find "$KOREADER" -name 'FSCK*' 2>/dev/null | while IFS= read -r file; do
        echo "renamed by the disk check: $file"
    done
}

# ensure_koreader: installs KOReader and NickelMenu if they aren't there. A different KOReader version is
# only reported, since replacing it isn't something to do by surprise.
ensure_koreader() {
    fetch_package "$KOREADER_PKG" "$KOREADER_URL" "$KOREADER_SHA"
    fetch_package "$NICKELMENU_PKG" "$NICKELMENU_URL" "$NICKELMENU_SHA"
    if [ ! -f "$KOREADER/git-rev" ]; then
        echo "Installing KOReader ${KOREADER_REV}…"
        mkdir -p "$KOBO/.adds"
        COPYFILE_DISABLE=1 tar --no-xattrs -xzf "$KOREADER_PKG" -C "$KOBO/.adds/"
        find "$KOREADER" -name '._*' -type f -delete
        sync
    fi
    # .adds/nm/doc comes from NickelMenu's own package, which the Kobo unpacks at its next restart.
    if [ ! -f "$KOBO/.adds/nm/doc" ]; then
        echo "Installing NickelMenu. The Kobo applies it and restarts after it's ejected."
        COPYFILE_DISABLE=1 cp "$NICKELMENU_PKG" "$KOBO/.kobo/KoboRoot.tgz"
    fi
    if [ ! -f "$KOBO/.adds/nm/koreader" ]; then
        mkdir -p "$KOBO/.adds/nm"
        printf '%s\n' "$NICKELMENU_ENTRY" > "$KOBO/.adds/nm/koreader"
    fi
    problems="$(koreader_problems)"
    if [ -n "$problems" ]; then
        echo "$problems" >&2
        case "$problems" in
            *missing*|*renamed*|*"isn't installed"*) return 1 ;;
        esac
    fi
    echo "KOReader checked: $(cat "$KOREADER/git-rev")"
}
