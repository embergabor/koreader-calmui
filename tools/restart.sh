#!/bin/sh
# Restarts the emulator and waits until the test driver answers.
cd "$(dirname "$0")/.."
pkill -f 'MacOS/koreader'; sleep 1
(nohup ./run-emulator.sh "$@" >/dev/null 2>&1 &)
sleep "${WAIT:-8}"
