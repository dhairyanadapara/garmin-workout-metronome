# Phase 0 — Toolchain setup

Nothing here can be scripted: the SDK Manager needs a Garmin account login and a GUI installer. Budget about an hour, most of it downloads.

## Current state of this machine

| | |
|---|---|
| Java 17 | OK - `C:\Program Files\Microsoft\jdk-17.0.8.7-hotspot` (`JAVA_HOME` points here) |
| Connect IQ SDK | OK - **9.2.0** (2026-06-09), marked active |
| OpenSSL / Git | OK |
| Developer key | OK - `D:\Projects\.keys\workout_metronome.der` |
| **FR165 device profile** | **MISSING - this is the remaining blocker** |

## 1. Java 17 - the PATH trap

Java 17 is installed, but **Java 1.8 is still first on `PATH`**, so a bare `java -version` reports 1.8 and `monkeyc` can fail with obscure class-version errors.

`tools/build.sh` pins `JAVA_HOME` for you, so prefer it over calling `monkeyc` directly. If you want the shell fixed globally, move the JDK 17 `bin` ahead of the Java 8 entry in the system PATH (leave Java 8 installed - something else is pulling it in).

## 2. Install the FR165 device profiles

Device profiles are separate downloads from the SDK, and no Forerunner is installed yet. Without them, `-d fr165` cannot build or simulate.

1. Open the **Connect IQ SDK Manager**
2. **Devices** tab, tick **Forerunner 165** and **Forerunner 165 Music**
3. Let them download

Verify:

```bash
ls ~/AppData/Roaming/Garmin/ConnectIQ/Devices | grep fr165
```

## 3. VS Code

Install the **Monkey C** extension (publisher: Garmin). It should auto-detect the SDK; if not, `Monkey C: Verify Installation` will say what's missing.

## 4. Developer key

Every build is signed. **Lose this key and you can never publish an update to your own store listing** — back it up somewhere durable.

```bash
mkdir -p /d/Projects/.keys
openssl genrsa -out /d/Projects/.keys/workout_metronome.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in /d/Projects/.keys/workout_metronome.pem \
  -out /d/Projects/.keys/workout_metronome.der -nocrypt
```

It lives outside the repo on purpose, and `.gitignore` blocks `*.der` / `*.pem` as a second line of defence.

This key is **already generated** - the block above is only for recreating it. Point VS Code at it: **Settings > Monkey C > Developer Key Path** > `D:\Projects\.keys\workout_metronome.der`

## 5. Build

```bash
tools/build.sh sim         # build AND run in the simulator
tools/build.sh test        # build + run the unit tests in the simulator
tools/build.sh device      # app -> bin/WorkoutMetronome.prg, for sideloading
tools/build.sh spike       # build AND run the Phase 1 capability probe
tools/build.sh release     # signed .iq bundle for the store
```

`sim` starts the simulator if it is not already running, loads the freshly
built field into it, and brings the window to the front.

All default to `fr165`; pass a device as the second argument to override. The script pins `JAVA_HOME`, reads whichever SDK is currently marked active, and refuses to build with a clear message if the device profile is not installed.

In VS Code, **Monkey C: Build for Device** / `Ctrl+F5` work too.

### Already verified against SDK 9.2.0

Built for an installed device profile (`fenix6`, standing in until FR165 lands):

- App, unit-test and spike targets all **BUILD SUCCESSFUL** with `-w`
- All **8 scheduler unit tests PASS** in the Monkey C VM
- `testNoDriftOverAnHour` reported `beats=10381 expected=10380 error=1`, matching the independent Python model exactly

So the code compiles and the timing maths is correct. What remains unproven is purely hardware behaviour, which is Phase 1.

## 6. Sideload to the watch

1. Connect the FR165 by USB; it mounts as a drive.
2. Copy `bin\WorkoutMetronome.prg` into `GARMIN\APPS\` on the watch.
3. Eject properly, then disconnect.
4. On the watch: **Run → hold UP → Activity Settings → Data Screens →** pick a screen → add **Workout Metronome** as a field.

Settings live in **Garmin Connect Mobile → your device → Activities & App Management → Data Fields → Workout Metronome → Settings**. Data field settings cannot be edited on the watch — this catches people out constantly, which is why the store description says so up front.

## Exit criteria

- [x] Java 17 available; SDK 9.2.0 active
- [x] Developer key generated and backed up
- [x] App, tests and spike all build clean with `-w`
- [x] All 8 unit tests pass
- [ ] **FR165 + FR165 Music device profiles installed** <- blocker
- [ ] `tools/build.sh device` succeeds for `fr165`
- [ ] The field renders correctly in the FR165 simulator at every field size
- [ ] The field appears in the data-screen picker on the real watch

Then go to [SPIKE.md](SPIKE.md) — **do not skip it.**
