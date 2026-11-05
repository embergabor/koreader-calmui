#!/bin/sh
# Launch the KOReader emulator as a Kobo Elipsa 2E (1404x1872 @ 227 DPI), or a Libra 2 (1264x1680 @ 300).
# The window is sized in points; on a Retina display that renders at 2x,
# so a 702x936 window is the device's real 1404x1872 framebuffer.
#   ./run-emulator.sh [--libra] [--landscape] [file.epub]
# Log: emulator/home/crash.log

W=702 H=936 DPI=227
case "$1" in --libra) W=632 H=840 DPI=300; export EMULATE_MODEL=Kobo_io; shift ;; esac
case "$1" in --landscape) T=$W; W=$H; H=$T; shift ;; esac

# The app chdirs into its bundle, so make file arguments absolute.
for arg; do
    shift
    [ -e "$arg" ] && arg="$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg")"
    set -- "$@" "$arg"
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
export QUIETUI_SETTINGS="$ROOT/mods/plugins/quietui.koplugin/settings.lua"
export KO_HOME="$ROOT/emulator/home"
export EMULATE_READER_W=$W EMULATE_READER_H=$H EMULATE_READER_DPI=$DPI

exec "$ROOT/emulator/KOReader.app/Contents/MacOS/koreader" -d "$@" \
    >"$KO_HOME/crash.log" 2>&1
