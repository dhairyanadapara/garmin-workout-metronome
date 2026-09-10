# Phase 0 — Toolchain setup

Nothing here can be scripted: the SDK Manager needs a Garmin account login and a GUI installer. Budget about an hour, most of it downloads.

## What this machine already has

| | |
|---|---|
| Java | **1.8.0_401** — ⚠️ too old, see below |
| OpenSSL | 1.1.1t ✅ |
| Git | 2.40.1 ✅ |
| Connect IQ SDK | ❌ not installed |

## 1. Java 17+

The Connect IQ SDK 7.x compiler needs a modern JDK; Java 8 will fail with obscure class-version errors. Install **Temurin 17 (or 21) JDK** from <https://adoptium.net>, then confirm the *first* Java on PATH is the new one:

```bash
java -version
```

If it still reports 1.8, put the new JDK's `bin` ahead of the old entry in the system PATH (the old Java 8 is probably pulled in by another app — leave it installed, just reorder).

## 2. Connect IQ SDK Manager

1. Sign in / create a free account at <https://developer.garmin.com/connect-iq/sdk/>
2. Download the **SDK Manager for Windows** and run it.
3. In the SDK tab: install the **latest 7.x SDK** and mark it *active*.
4. In the Devices tab: install **Forerunner 165** and **Forerunner 165 Music**.

Devices are separate downloads from the SDK. Without them, `-d fr165` fails.

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

Point VS Code at it: **Settings → Monkey C → Developer Key Path** → `D:\Projects\.keys\workout_metronome.der`

## 5. First build

Open `D:\Projects\garmin-workout-metronome` in VS Code and run **Monkey C: Build for Device** (or `Ctrl+F5` to run in the simulator). Pick `fr165`.

Command line equivalent:

```bash
monkeyc -f monkey.jungle -o bin/WorkoutMetronome.prg -y /d/Projects/.keys/workout_metronome.der -d fr165 -w
```

`-w` turns on warnings — leave it on, Monkey C's type checker catches a lot at this level.

Run the unit tests:

```bash
monkeyc -f monkey.jungle -o bin/test.prg -y /d/Projects/.keys/workout_metronome.der -d fr165 -w --unit-test
monkeydo bin/test.prg fr165 -t
```

All eight scheduler tests should pass. The maths behind them was already verified independently in Python (≤1 ms per-beat deviation, ≤1 beat drift/hour), so a failure here means a Monkey C porting problem, not a logic problem.

## 6. Sideload to the watch

1. Connect the FR165 by USB; it mounts as a drive.
2. Copy `bin\WorkoutMetronome.prg` into `GARMIN\APPS\` on the watch.
3. Eject properly, then disconnect.
4. On the watch: **Run → hold UP → Activity Settings → Data Screens →** pick a screen → add **Workout Metronome** as a field.

Settings live in **Garmin Connect Mobile → your device → Activities & App Management → Data Fields → Workout Metronome → Settings**. Data field settings cannot be edited on the watch — this catches people out constantly, which is why the store description says so up front.

## Exit criteria

- [ ] `java -version` reports 17+
- [ ] `monkeyc` builds `bin/WorkoutMetronome.prg` with no warnings
- [ ] `monkeydo` runs the unit tests green
- [ ] The field renders in the FR165 simulator
- [ ] The field appears in the data-screen picker on the real watch

Then go to [SPIKE.md](SPIKE.md) — **do not skip it.**
