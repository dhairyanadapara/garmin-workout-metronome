# How the beat is scheduled

This is the one genuinely hard part of the app, and it went through a wrong design first. This document records the pattern used, why it is the standard one, and what measurements forced the change — so nobody "simplifies" it back.

## The constraint

A Connect IQ data field is the only app type that runs inside a native activity, and it gets:

- **`compute()` roughly once per second.** Nominally 1 Hz. Measured in the simulator: usually exactly 1000 ms, but it fires **twice 47–125 ms apart at activity start**, and a busy watch can deliver it late.
- **No `Toybox.Timer`.** The app can never be awake for an individual beat.
- **`Attention.playTone` takes a *relative* profile** — an array of (frequency, duration) pairs — and **a new call cancels whatever is still playing**. There is no "play at absolute time T".

So the app must express up to a second and a half of rhythm as one relative array, re-issued on an unreliable clock.

## The pattern: look-ahead scheduling on an absolute timeline

This is the standard software-metronome architecture — the one behind DAWs, drum machines and Web Audio's "two clocks" approach. Three rules:

1. **Beats live on an absolute timeline.** `beat(n) = t0 + n × interval`. Nothing is derived by accumulating deltas between wake-ups, so drift is impossible *by construction* rather than by testing.

2. **A coarse, unreliable wake-up clock drives a precise output clock.** `compute()` only tops up the queue; the firmware's own playback is what keeps time. The wake-up is never itself the rhythm.

3. **The look-ahead horizon exceeds the wake-up interval.** Each call schedules every beat due in `[now, now + horizon)`. That overlap is what makes a late wake-up harmless.

The Connect IQ adaptation is that the overlap is **re-queued rather than merged**: because a new `playTone` cancels the old, each call recomputes the beats still ahead and emits them as offsets from *now*.

That makes `schedule()` **idempotent** — and idempotence is what does the real work here:

| Wake-up clock misbehaves | What happens |
|---|---|
| Fires twice, 47 ms apart (measured at activity start) | Second call re-queues the same absolute beats, minus any that already sounded. No phase change. |
| Arrives 450 ms late | The horizon already covered the gap. |
| Jitters ±80 ms | Beats stay on the absolute grid; only the queue top-up moves. |
| Doesn't come for 10 minutes (paused, off-screen) | `RESYNC_MS` re-bases instead of stepping forward beat by beat. |
| Clock runs backwards (`System.getTimer()` wraps ~25 days) | Detected and re-based. |

A beat cancelled mid-flight is recovered by `TOL_MS`: it is still in the future by less than 20 ms when the cancelling call arrives, so the next call re-queues it. `TOL_MS` is kept **below** the 40 ms beat length, so a beat that already sounded in full is never played twice.

## Measured platform limits

Probed on the `fr165` target rather than assumed:

| | |
|---|---|
| `Attention has :ToneProfile` | true |
| `playTone` profile elements | **32+ accepted** |
| `vibrate` profile elements | **8 maximum** |
| `vibrate` with 10 elements | **uncatchable `Too Many Arguments Error` — kills the data field.** `try`/`catch` does *not* save you |

Hence `TONE_HORIZON_MS = 1500` (220 spm needs 12 elements — plenty of room, and it tolerates a wake-up 500 ms late), while the vibration cue is **hard-truncated to 8 elements** and therefore covers less of the horizon at high cadence. That is an accepted trade: the tone carries the rhythm and the next wake-up tops the vibration up.

## What was wrong before, and how it was caught

The first implementation cut time into **disjoint 1000 ms windows** and carried a phase remainder between them. It drifted nothing — but it made `compute()` itself the rhythm, so every quirk of the wake-up clock became audible:

- **A beat vanished every 6.01 seconds at 170 spm.** Screen recordings analysed by onset detection: 10 dropped beats in 60 s, gaps of 685–705 ms against a 353 ms interval, and bursts as short as 9.7 ms against a 40 ms beat. Cause: at 170 spm the phase carry cycles so every 6th window places a beat within a millisecond of the window edge, and the next call cancelled it before it could sound.
- Patching that with a minimum-beat guard plus deferral cut it to **2 drops in 68 s** — better, but the fix was defending a boundary that only existed because of the window partitioning.
- The duplicate start tick needed a **500 ms threshold guard**, a magic number with no principle behind it.

Both patches are gone. Absolute time removes the boundary rather than defending it, and idempotence removes the duplicate-tick guard rather than tuning it.

## Verification

`tools/build.sh test` — 12 tests asserting the *properties*, not particular offsets:

- `testScheduleIsIdempotent` — the same clock reading gives the same answer and leaves the timeline untouched
- `testDuplicateWakeupAtStart` — the measured 47 ms double-tick, at five tempos
- `testNoDroppedBeatsUnderCleanClock` — zero drops at 100–220 spm
- `testJitteryWakeupClock` — ±80 ms wake-up jitter
- `testHorizonCoversALateWakeup` — a 450 ms late wake-up leaves no hole
- `testNoDriftOverHalfAnHour` — exact beat counts at four tempos
- `testVibeElementBudget` — never exceeds the fatal 8-element vibrate limit
- `testResyncAfterLongAbsence` — long gaps and a backwards clock

Measured end to end on the `fr165` simulator, 52 wake-ups including one duplicate at +125 ms:

```
sounded beats: 146 over 51.2s
gap: min=352 max=353 median=353  DROPS=0
worst deviation from median: 1ms
implied tempo: 170.0 spm
```

Against the old scheduler, the same measurement gave a dropped beat every 6.01 seconds.

## If you change this

Re-run the recording analysis, don't trust your ear. Capture the simulator's audio, extract with `ffmpeg -vn -ac 1 -ar 48000`, detect onsets on a rectified 1 ms envelope, and check the inter-onset gaps against `60000 / spm`. A dropped beat shows up as a gap of almost exactly twice the interval — which is how the 6-second bug was found in the first place.
