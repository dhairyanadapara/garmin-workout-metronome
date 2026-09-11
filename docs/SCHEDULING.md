# How the beat is scheduled

This is the one genuinely hard part of the app, and it went through a wrong design first. This document records the pattern used, why it is the standard one, and what measurements forced the change — so nobody "simplifies" it back.

## The constraint

A Connect IQ data field is the only app type that runs inside a native activity, and it gets:

- **`compute()` roughly once per second.** Measured in the simulator: usually exactly 1000 ms, but it fires **twice 47-125 ms apart at activity start**, and a busy watch can deliver it late.
- **No `Toybox.Timer`.** The app can never be awake for an individual beat.
- **`Attention.playTone` takes a *relative* profile**, and **a new call CANCELS whatever is still playing.**

That last point is the crux, and it is what two earlier designs got wrong.

## Why "feed it every second" cannot work

Both earlier designs handed the firmware the next second or so of rhythm on every wake-up. At 170 spm a 40 ms beat occupies 40 ms of every 353 ms, so **roughly 11% of wake-ups land on top of a sounding beat and cut it short.**

Recordings of the simulator, analysed by onset detection, showed exactly that:

| Design | Result over ~60 s at 170 spm |
|---|---|
| Disjoint 1000 ms windows with a carried phase | **10 dropped beats**, one every 6.01 s, gaps of 685-705 ms against 353 ms |
| Same, plus a minimum-beat guard and deferral | **2 dropped beats**, bursts as short as 9.7 ms |
| Look-ahead horizon on an absolute timeline | **2 dropped beats**, bursts as short as 9.7 ms |

The look-ahead version was the right *pattern* - absolute timeline, idempotent scheduling, horizon overlap - and it fixed the 6-second periodicity. But it still re-issued a profile every second, so it still cancelled a beat mid-flight about one wake-up in nine. Feeding the firmware is the problem; no scheduling cleverness removes it.

## The design: arm the firmware, do not feed it

`Attention.playTone` accepts **`:repeatCount`** (measured on fr165: accepted up to at least 10000). So the beat pattern is issued **once**, as a single profile exactly one beat period long, and the firmware loops it on its own hardware clock:

```
[rest leadInMs] [beat 40ms] [rest interval - 40 - leadInMs]     x repeatCount
```

The rhythm is now produced by hardware timing, not by our wake-up clock. It is even by construction, because nothing interrupts it. Measured on target: one arming of 1699 repeats covers **10 minutes**, and across 40 subsequent wake-ups there were **zero** further tone calls.

This is the same principle as the look-ahead pattern - let the precise clock keep time, not the coarse one - taken to its conclusion. The coarse clock now does nothing but *arm*.

### Re-arming without a phase jump

An arming eventually expires, and a tempo change or a deviation alert invalidates it. Re-arming means another `playTone`, so it must not damage the rhythm. Two rules, which turn out to be one rule:

- The lead-in rest goes **inside** the repeating profile and the trailing rest is shortened to match, so the profile stays exactly one interval long and the beat keeps its phase. Re-arming is phase-accurate to 1 ms.
- Arm **only when no beat is sounding**, which is true exactly when `delay <= interval - beatMs`.

At 170 spm that admits 313 ms of every 353 ms, so **89% of wake-ups qualify** and there are ~60 chances in the minute before an arming expires. A wake-up that does not qualify simply does nothing, which is correct - the firmware is still playing.

### What still gets fed

`Attention.vibrate` has **no repeat parameter**, so the vibration cue must still be re-issued every wake-up, within a hard 8-element budget. The tone carries the rhythm; the vibration is the coarser cue, and a clipped buzz is far less perceptible than a missing beat.

### Stopping

A long arming outlives a pause, so `Metronome.stop()` must replace the loop with a 1 ms silent profile. Without that the watch keeps beating through a paused activity.

## Measured platform limits

Probed on the `fr165` target rather than assumed:

| | |
|---|---|
| `Attention has :ToneProfile` | true |
| `playTone` profile elements | **32+ accepted** |
| `playTone :repeatCount` | **accepted up to at least 10000** |
| `vibrate` profile elements | **8 maximum** |
| `vibrate` with 10 elements | **uncatchable `Too Many Arguments Error` - kills the data field.** `try`/`catch` does *not* save you |

## Tempo quantisation

The firmware profile works in whole milliseconds, so the grid does too - modelling the beat more finely than the hardware can express it would only let our idea of where a beat is drift from where it actually sounds.

170 spm wants 352.94 ms and gets 353 ms, so the real tempo is 169.97 spm: a 0.017% error, about one beat per hour. What a runner feels is the *spacing* between consecutive beats, and that is exact.


## OPEN: a 2% tempo offset, not yet calibrated on hardware

Recordings of the **simulator** consistently measure the armed metronome's
period as **360 ms** where the profile is `40 + 313 = 353 ms`. That is
166.67 spm against a requested 170 - a systematic 2% offset. The spacing is
steady and no beats are dropped; the tempo is simply slow.

The likeliest cause is the firmware rounding each element duration **up** to a
quantum: `313 -> 320` would give exactly the 360 ms observed.

A first ruler probe used rests of 300/305/310/315 and was too fine to tell -
all four rounded to the same value and produced four identical 360 ms gaps,
which is equally consistent with a large quantum or with no pattern at all.
The probe now uses **205 / 310 / 415 / 520**, chosen so that every candidate
quantum predicts a distinct signature:

| rest | none | Q=5 | Q=8 | Q=10 | Q=16 | Q=20 | Q=40 |
|---|---|---|---|---|---|---|---|
| 205 | 245 | 245 | 248 | 250 | 248 | 260 | 280 |
| 310 | 350 | 350 | 352 | 350 | 360 | 360 | 360 |
| 415 | 455 | 455 | 456 | 460 | 456 | 460 | 480 |
| 520 | 560 | 560 | 560 | 560 | 568 | 560 | 560 |

**This must be measured on the watch, not the simulator.** Every timing figure
in this document so far comes from the simulator's audio path, which need not
match the firmware's. Once the quantum is known, the fix is to choose beat and
rest durations that are already multiples of it, so the firmware has nothing to
round - not to subtract a fudge factor.

Until then the app's tempo is accurate to about 2% in the simulator, and
unmeasured on hardware.

## Verification

`tools/build.sh test` - 10 tests covering the grid and the arming policy:

- `testGridIsAbsoluteAndIdempotent` - the answer depends only on the clock, so a duplicate or out-of-order wake-up is harmless
- `testGridSpacingIsExact` - ten minutes of beats at nine tempos, every gap exactly one interval
- `testArmingWindowIsSafeAndReachable` - checks every millisecond of an interval: the rule never admits a moment when a beat is sounding, never produces a negative tail rest, and still admits at least 80% of moments
- `testVibeElementBudget` - never exceeds the fatal 8-element vibrate limit
- `testResyncAfterLongAbsence` - long gaps and a backwards clock
- plus tempo maths, rounding, clamping, and the two grid views agreeing

## If you change this

Re-run the recording analysis, do not trust your ear. Capture the simulator audio, extract with `ffmpeg -vn -ac 1 -ar 48000`, detect onsets on a rectified 1 ms envelope, and check inter-onset gaps against `60000 / spm`. A dropped beat is a gap of almost exactly twice the interval; a *clipped* beat shows up as an unusually short burst length. Both are how the earlier faults were found.

**Do not go back to issuing a profile every wake-up.** It has been tried twice and measured twice.
