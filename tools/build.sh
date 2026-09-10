#!/usr/bin/env bash
# Build / test / package the data field.
#
#   tools/build.sh device        build the app for the watch      (default)
#   tools/build.sh test          build AND run the unit tests
#   tools/build.sh spike         build the Phase 1 capability spike
#   tools/build.sh release       build the signed .iq for the store
#
# Second argument overrides the target device, e.g. tools/build.sh device fr165m
#
# Why this script exists rather than "just run monkeyc": this machine has
# Java 8 first on PATH, and the SDK 9.x compiler silently needs 17+. Pinning
# JAVA_HOME here avoids an afternoon of confusing class-version errors.

set -euo pipefail

CMD="${1:-device}"
DEVICE="${2:-fr165}"

JAVA_HOME="${JAVA_HOME:-/c/Program Files/Microsoft/jdk-17.0.8.7-hotspot}"
CIQ_HOME="$HOME/AppData/Roaming/Garmin/ConnectIQ"
KEY="${CIQ_KEY:-/d/Projects/.keys/workout_metronome.der}"

# Use whichever SDK the SDK Manager currently has marked active.
SDK="$(tr -d '\r\n' < "$CIQ_HOME/current-sdk.cfg")"
SDK_BIN="$(cygpath -u "$SDK" 2>/dev/null || echo "$SDK")bin"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$SDK_BIN:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -f "$KEY" ]; then
    echo "No developer key at $KEY -- see docs/SETUP.md step 4." >&2
    exit 1
fi

if [ ! -d "$CIQ_HOME/Devices/$DEVICE" ] && [ "$CMD" != "release" ]; then
    echo "Device profile '$DEVICE' is not installed." >&2
    echo "Open the Connect IQ SDK Manager, Devices tab, and install it." >&2
    echo "Installed: $(ls "$CIQ_HOME/Devices" | tr '\n' ' ')" >&2
    exit 1
fi

mkdir -p bin

case "$CMD" in
  device)
    monkeyc -f monkey.jungle -o bin/WorkoutMetronome.prg -y "$KEY" -d "$DEVICE" -w
    echo "Built bin/WorkoutMetronome.prg for $DEVICE"
    echo "Sideload: copy it to GARMIN\\APPS\\ on the watch over USB."
    ;;
  test)
    monkeyc -f monkey.jungle -o bin/test.prg -y "$KEY" -d "$DEVICE" -w --unit-test
    # monkeydo needs the simulator listening.
    if ! tasklist 2>/dev/null | grep -qi simulator; then
        ( connectiq >/dev/null 2>&1 & )
        for _ in $(seq 1 20); do
            tasklist 2>/dev/null | grep -qi simulator && break
        done
    fi
    monkeydo bin/test.prg "$DEVICE" -t
    ;;
  spike)
    mkdir -p spike/bin
    ( cd spike && monkeyc -f monkey.jungle -o bin/spike.prg -y "$KEY" -d "$DEVICE" -w )
    echo "Built spike/bin/spike.prg for $DEVICE -- see docs/SPIKE.md"
    ;;
  release)
    # -e exports the multi-device .iq bundle for the store; -r is release mode.
    monkeyc -e -f monkey.jungle -o bin/WorkoutMetronome.iq -y "$KEY" -w -r
    echo "Built bin/WorkoutMetronome.iq -- upload this to apps.garmin.com"
    ;;
  *)
    echo "Unknown command '$CMD'. Use: device | test | spike | release" >&2
    exit 1
    ;;
esac
