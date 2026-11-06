#!/bin/sh
# See deploy-to-kobo.sh --wifi.
set -e
cd "$(dirname "$0")/.."

SSH_KEY="$HOME/.ssh/id_kobo"
LAST_FILE=.kobo-address
NAMES_FILE=.kobo-addresses # "name address" for each device
REMOTE_DIR=/mnt/onboard/.adds/koreader

ALL=
HOST=
for arg; do
    case "$arg" in
        --all) ALL=1 ;;
        elipsa|libra)
            HOST="$(awk -v name="$arg" '$1 == name { print $2 }' "$NAMES_FILE" 2>/dev/null || true)"
            [ -n "$HOST" ] || { echo "No address for the $arg yet. Give it once: ./deploy-to-kobo.sh --wifi 192.168.1.50" >&2; exit 1; }
            ;;
        *) HOST="$arg" ;;
    esac
done
[ -n "$HOST" ] || HOST="$(cat "$LAST_FILE" 2>/dev/null || true)"
[ -n "$HOST" ] || { echo "Give the address shown in the Kobo's cogwheel: ./deploy-to-kobo.sh --wifi 192.168.1.50" >&2; exit 1; }
[ -f "$SSH_KEY" ] || { echo "No $SSH_KEY yet. Install once over USB first, which sets it up." >&2; exit 1; }

kobo() {
    ssh -i "$SSH_KEY" -p 2222 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.ssh/known_hosts_kobo" \
        "root@$HOST" "$@"
}

if ! kobo true 2>/dev/null; then
    echo "Can't reach the Kobo at $HOST. Wake it and turn on Updates over Wi-Fi in the cogwheel." >&2
    exit 1
fi
echo "$HOST" > "$LAST_FILE"
case "$(kobo /bin/kobo_config.sh 2>/dev/null || true)" in
    condor) NAME=elipsa ;;
    io) NAME=libra ;;
    *) NAME=kobo ;;
esac
{ grep -v "^$NAME " "$NAMES_FILE" 2>/dev/null || true; echo "$NAME $HOST"; } > "$NAMES_FILE.new"
mv "$NAMES_FILE.new" "$NAMES_FILE"
echo "Updating the $NAME at $HOST"
KOREADER_REV="$(sed -n 's/^KOREADER_REV=//p' tools/koreader-base.sh)"
HAVE_REV="$(kobo "cat $REMOTE_DIR/git-rev" 2>/dev/null || true)"
[ "$HAVE_REV" = "$KOREADER_REV" ] || echo "Note: KOReader is $HAVE_REV, Quiet UI is built for $KOREADER_REV." >&2

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/plugins" "$STAGE/patches" "$STAGE/data"
cp -R mods/plugins/quietui.koplugin "$STAGE/plugins/"
cp -R mods/patches/. "$STAGE/patches/"
cp mods/usbms/KoboUSBMS.tar.gz "$STAGE/data/"

# Everything arrives and unpacks in memory first, so a dropped connection changes nothing.
COPYFILE_DISABLE=1 tar --format ustar --exclude '._*' --exclude '.DS_Store' -czf - -C "$STAGE" plugins patches data |
    kobo 'rm -rf /tmp/quietui-update && mkdir -p /tmp/quietui-update && tar xzf - -C /tmp/quietui-update'

if [ -n "$ALL" ]; then
    echo "Sending fonts and the dictionary…"
    COPYFILE_DISABLE=1 tar --format ustar --exclude '._*' --exclude '.DS_Store' -cf - -C fonts . |
        kobo 'mkdir -p /mnt/onboard/fonts && tar xf - -C /mnt/onboard/fonts'
    COPYFILE_DISABLE=1 tar --format ustar --exclude '._*' --exclude '.DS_Store' -cf - -C dict . |
        kobo "mkdir -p $REMOTE_DIR/data/dict && tar xf - -C $REMOTE_DIR/data/dict"
fi

# The old plugin folder is replaced in one step, under a name KOReader doesn't load.
LOG_START="$(kobo "cd $REMOTE_DIR &&
    rm -rf plugins/.quietui.new &&
    cp -r /tmp/quietui-update/plugins/quietui.koplugin plugins/.quietui.new &&
    cp /tmp/quietui-update/patches/* patches/ &&
    cp /tmp/quietui-update/data/KoboUSBMS.tar.gz data/ &&
    rm -rf plugins/quietui.koplugin &&
    mv plugins/.quietui.new plugins/quietui.koplugin &&
    rm -rf /tmp/quietui-update &&
    sync &&
    wc -c < crash.log")"
echo "Installed. Restarting KOReader…"

running() { kobo 'pgrep -f reader.lua | head -1' 2>/dev/null || true; }
BEFORE="$(running)"
kobo 'touch /tmp/quietui-restart'
i=0
while [ $i -lt 30 ]; do
    sleep 2
    i=$((i + 2))
    NOW="$(running)"
    [ -n "$NOW" ] && [ "$NOW" != "$BEFORE" ] && break
done
if [ -z "$NOW" ] || [ "$NOW" = "$BEFORE" ]; then
    echo "KOReader didn't restart by itself. The new version loads at its next start." >&2
    exit 1
fi

# Give it time to reach the library, then look for errors from this start only.
sleep 8
ERRORS="$(kobo "cd $REMOTE_DIR && tail -c +$((LOG_START + 1)) crash.log | grep -E 'ERROR|stack traceback|attempt to|Crash' || true")"
if [ -n "$ERRORS" ]; then
    echo "KOReader restarted with errors:" >&2
    echo "$ERRORS" >&2
    exit 1
fi
echo "Updated. KOReader restarted without errors."
