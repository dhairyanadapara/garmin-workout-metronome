# Workout Metronome — Garmin Connect IQ data field

A running metronome that **keeps beating inside the native Run activity and structured workouts**, so you can hold a target steps-per-minute for a whole session.

The Forerunner 165 has no built-in metronome (the 255/265/955 do). Every metronome on the store for it is a *watch app*, and starting a run kills the watch app. This is a **data field** instead — the only Connect IQ app type that runs inside a native activity.

## How it beats, given a data field can't use a timer

A data field gets exactly one `compute()` call per second and `Toybox.Timer` is unavailable, so the app can never be awake for the individual beats. Instead:

> Once per second, `compute()` hands the firmware **the next full second of rhythm in a single call** — `Attention.playTone({:toneProfile => [...]})` takes an *array* of (frequency, duration) pairs and plays them back-to-back on its own clock. `Attention.vibrate()` takes a `VibeProfile` array the same way.

`Attention.vibrate` is capped at **8 elements**, and 220 spm needs exactly 8 (beat + rest, four times). That cap is why the scheduling window is 1000 ms and not longer.

The other half is phase continuity. 170 spm is 352.9 ms per beat, which does not divide into a second — so [`BeatScheduler`](source/BeatScheduler.mc) carries the leftover microseconds into the next window instead of restarting at zero each tick. Restarting is the classic bug and produces a stutter once per second, every second. Verified: **≤1 ms per-beat deviation, ≤1 beat drift per hour.**

## Features

- Target cadence 100–220 spm; beat on every step, every other step, or every 4th
- Tone, vibration, or both — each behind device capability checks
- **Off-target alert:** a distinct two-tone cue when your smoothed cadence drifts outside ±5% of target, rising for *speed up*, falling for *slow down*
- Smoothing + hysteresis so it doesn't nag: 5 s rolling average, N consecutive out-of-range seconds to fire, then a cooldown
- Silent while paused, and through the first 15 s of a run

## Layout

```
source/
  WorkoutMetronomeApp.mc   AppBase; forwards phone settings pushes to the view
  MetronomeView.mc         the data field: compute() cues, onUpdate() only draws
  BeatScheduler.mc         pure beat-timing maths (drift-free, unit tested)
  Cue.mc                   everything touching Toybox.Attention, behind capability checks
  CadenceMonitor.mc        rolling average + hysteresis for the off-target alert
  Config.mc                crash-proof typed reads of app settings
  Tests.mc                 (:test) unit tests for the scheduler
resources/
  settings/                the Garmin Connect Mobile settings screen + defaults
spike/                     throwaway Phase 1 hardware capability probe
docs/
  SETUP.md                 toolchain install, developer key, build & sideload
  SPIKE.md                 the Phase 1 protocol and how to read the result
  TESTING.md               simulator + on-device test matrix
  STORE.md                 submission checklist and listing copy
  DEVICE-EXPANSION.md      how to widen beyond FR165 safely
```

## Status

| Phase | State |
|---|---|
| 0 · Toolchain | ⏳ **needs you** — Connect IQ SDK is not installed on this machine, see [docs/SETUP.md](docs/SETUP.md) |
| 1 · Hardware capability spike | ⏳ blocked on Phase 0 — see [docs/SPIKE.md](docs/SPIKE.md) |
| 2 · Core metronome | ✅ written, unverified on device |
| 3 · Off-target alert | ✅ written, unverified on device |
| 4 · Settings & polish | ✅ written, unverified on device |
| 5 · Testing | ⏳ blocked on Phase 0 |
| 6 · Store submission | ⏳ see [docs/STORE.md](docs/STORE.md) |

**Phase 1 is a genuine gate.** If the FR165 turns out to cancel a queued tone profile on each new `playTone` call, tone mode degrades to one beep per second and vibration becomes the primary cue. That assumption cannot be tested without the watch.

## Quick start

```bash
cd D:/Projects/garmin-workout-metronome
```

Then follow [docs/SETUP.md](docs/SETUP.md) — the SDK install needs a Garmin account and a GUI installer, so it can't be scripted.
