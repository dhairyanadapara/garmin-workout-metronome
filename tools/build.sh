#!/usr/bin/env bash
# Build / test / package the data field.
#
#   tools/build.sh sim           build AND run the app in the simulator
#   tools/build.sh device        build the app for the watch      (default)
#   tools/build.sh test          build AND run the unit tests
#   tools/build.sh spike         build AND run the Phase 1 spike in the simulator
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

# Start the simulator if it is not already up, then load a .prg into it and
# bring its window to the front so it is ready to look at (or record).
run_in_simulator() {
    local prg="$1"
    if ! tasklist 2>/dev/null | grep -qi simulator; then
        ( connectiq >/dev/null 2>&1 & )
        for _ in $(seq 1 30); do
            tasklist 2>/dev/null | grep -qi simulator && break
            powershell -NoProfile -Command "Start-Sleep -Milliseconds 400" >/dev/null 2>&1
        done
        powershell -NoProfile -Command "Start-Sleep -Seconds 3" >/dev/null 2>&1
    fi

    ( monkeydo "$prg" "$DEVICE" >/dev/null 2>&1 & )
    powershell -NoProfile -Command "Start-Sleep -Seconds 5" >/dev/null 2>&1

    powershell -NoProfile -Command '
Add-Type @"
using System; using System.Runtime.InteropServices;
public class S {
  [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
$p = Get-Process simulator -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowTitle -like "*CIQ Simulator*" } | Select-Object -First 1
if ($p) {
  [void][S]::ShowWindow($p.MainWindowHandle, 9)
  [void][S]::SetForegroundWindow($p.MainWindowHandle)
  Write-Output ("Simulator ready: " + $p.MainWindowTitle)
} else { Write-Output "Simulator window not found" }' 2>/dev/null | tail -1
}

case "$CMD" in
  sim)
    monkeyc -f monkey.jungle -o bin/WorkoutMetronome.prg -y "$KEY" -d "$DEVICE" -w
    run_in_simulator bin/WorkoutMetronome.prg
    echo "The field is beating at the configured target cadence."
    echo "Record with OBS, or watch the display."
    ;;
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
    run_in_simulator spike/bin/spike.prg
    ;;
  release)
    # -e exports the multi-device .iq bundle for the store; -r is release mode.
    monkeyc -e -f monkey.jungle -o bin/WorkoutMetronome.iq -y "$KEY" -w -r
    echo "Built bin/WorkoutMetronome.iq -- upload this to apps.garmin.com"
    ;;
  *)
    echo "Unknown command '$CMD'. Use: sim | device | test | spike | release" >&2
    exit 1
    ;;
esac
