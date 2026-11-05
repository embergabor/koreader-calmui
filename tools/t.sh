#!/bin/sh
# ./tools/t.sh 'T.tap(100,200)' [seconds to wait]; prints what the command logged.
H="$(dirname "$0")/../emulator/home"
: > "$H/test-out.txt"
printf '%s\n' "$1" > "$H/test-cmd.tmp" && mv "$H/test-cmd.tmp" "$H/test-cmd.lua"
sleep "${2:-1}"
cat "$H/test-out.txt"
