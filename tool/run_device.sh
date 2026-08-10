#!/usr/bin/env bash
# Runs the app on the USB-connected Android device with the local
# backend reachable through an adb reverse tunnel.
#
# The backend only listens on 127.0.0.1, so the phone reaches it via
# `adb reverse`: the phone's own localhost:8000 is forwarded over USB
# to the Mac's localhost:8000. The tunnel dies whenever the cable is
# unplugged or adb restarts — this script re-creates it every launch.
#
# Usage:  tool/run_device.sh [extra flutter run args]
set -euo pipefail

cd "$(dirname "$0")/.."

adb reverse tcp:8000 tcp:8000
echo "adb reverse tunnel active: phone localhost:8000 -> mac localhost:8000"

exec flutter run \
  --dart-define=CHORD_API_BASE_URL=http://127.0.0.1:8000 \
  "$@"
