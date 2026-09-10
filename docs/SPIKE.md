# Phase 1 — Hardware capability spike

**Run this before trusting anything else in the repo.**

## The assumption under test

The product rests on one thing that no documentation confirms and no simulator can prove: that a Forerunner 165, from inside a data field, will accept a **multi-element tone profile** and play it back **evenly, sub-second, once per second, forever**.

The docs say `playTone` accepts `:toneProfile` and that data fields may call it. They do not say what happens when you call it again a second later while the previous profile may still be playing, and they do not say whether FR165 firmware honours the durations faithfully. Those are the questions.

## RESOLVED: the dropped beat (2026-09-10)

Two screen recordings of the simulator at 170spm, analysed by onset detection,
settled question 1 before the watch was ever involved.

**60-second recording:** 161 beats at 2000Hz, median gap 353.0ms (= exactly
170spm), and **10 dropped beats** at t = 6.1, 12.1, 18.1, 24.1, 30.1, 36.1,
42.1, 48.1, 54.1, 60.1s -- one every 6.01 seconds, with gaps of 685-705ms
against the 353ms interval. Shortest burst measured 9.7ms against a 40ms beat.

**Cause.** A `playTone` call CANCELS a profile that is still playing. At 170spm
the phase carry cycles such that every 6th window places a beat at ~999ms; the
next second's call arrives ~1ms later and cuts it to silence. The truncated
9.7ms bursts are the same effect caught mid-beat.

**Fix.** `BeatScheduler.nextWindow` now takes a `minBeatMs` guard and will not
schedule a beat without room to sound; such a beat carries into the next
window at offset 0, late by under 15ms instead of missing. `Cue` shortens a
beat that fits but cannot run full length, which costs nothing perceptually
because rhythm is carried by the ONSET, not the duration.

Modelled across 100-220spm: **zero drops, mean timing error under 1.1ms**,
worst case bounded by the 15ms guard, beat counts exact over 30 minutes.
Locked in by `testNoBeatIsTruncated` and `testNoDroppedBeatsOverTime`.

**Still open, and watch-only:** whether FR165 firmware honours profile
durations as faithfully as the simulator does, and whether `compute()` keeps
running while the field is off-screen.

## Already answered by the fr165 simulator

A capability probe run against the real `fr165` target settled the "does the
API even exist here" half of the question, so the spike now only has to answer
the hardware-behaviour half:

| Probe | Result |
|---|---|
| `Attention has :playTone` | true |
| `Attention has :ToneProfile` | **true** |
| `Attention has :vibrate` / `:VibeProfile` | true |
| 3-element tone profile | accepted, no throw |
| 8-element tone profile (worst case, 220 spm) | accepted, no throw |
| Screen / memory | 390x390, field uses 13.5kB of 252.5kB |

So the degraded "no ToneProfile" fallback path in `Cue` will not be taken on
this device, and profiles are not rejected for size.

What the simulator still cannot tell us, and the watch must:

1. Whether a second `playTone` **cancels** a profile that is still playing.
2. Whether the firmware honours the **durations** evenly, or drifts/stutters.
3. Whether `compute()` really keeps running when the field is **off-screen**.

Questions 1 and 3 are the ones that can kill the design.

## Running it in the simulator

```
toolsuild.cmd spike
```

**The simulator reports `timerState 0` (TIMER_STATE_OFF) until you press START
on the simulated watch.** The spike therefore cues REGARDLESS of timer state,
so it makes noise the moment it loads -- otherwise you would sit in silence
wondering whether the build was broken.

The main app does respect timer state, so to hear *that* in the simulator you
must press START (or use Simulation > Activity Data) first. It shows PAUSED in
the header until you do.

The spike's fourth line reports the raw value, so there is never any guessing:

```
tick 24  cued 24     <- compute() calls, and how many actually cued
timerState 0         <- 0=OFF 1=STOPPED 2=PAUSED 3=ON, or "null"/"absent"
tone ok              <- last cue result
```

## Build and load

```bash
tools/build.sh spike
```

Copy `spike\bin\spike.prg` to `GARMIN\APPS\` on the watch, then add **Metronome Spike** to a run data screen.

Before starting, on the watch: **Settings → System → Sound and Vibe** — turn tones **on** and set vibration **on**. The spike shows both flags on screen (`snd`/`vib`) so you can confirm.

## What the field shows

```
t1 p1 v1        <- has playTone / has ToneProfile / has vibrate
snd1 vib1       <- system tones on / vibration on
tick 43         <- compute() calls since the field was created
ok              <- last cue result
```

The spike **alternates**: odd seconds fire the tone profile, even seconds fire the vibe profile, so you can judge each without the other masking it. Each is three pulses at 0 ms, 300 ms, 600 ms.

## The protocol

Start a **Run** activity and let it record for ~5 minutes.

| # | Do this | Watch for |
|---|---|---|
| 1 | Stand still, listen through the first 30 s | **3 evenly spaced beeps** every other second |
| 2 | Feel the wrist on the alternating seconds | **3 distinct buzzes**, not one long one |
| 3 | Press DOWN to a different data page, wait 60 s | Beeps/buzzes **must continue** |
| 4 | Return to the spike page | `tick` must have kept counting (≈1/s, no gaps) |
| 5 | Pause the activity | Cues stop |
| 6 | Resume | Cues restart cleanly |
| 7 | Run 3–4 minutes at real pace | Rhythm stays even while arms swing |
| 8 | Note battery % before and after | For the drain estimate |

Record a phone video with audio for step 1 — it lets you count the beeps frame by frame afterwards rather than trusting your ear mid-run.

## Reading the result

| What you hear | Verdict | What to do |
|---|---|---|
| 3 even beeps per tone-second | ✅ **Green light** | Proceed. The whole design works as intended. |
| 1 beep per tone-second | ❌ Each `playTone` cancels the previous queue | Tone mode is dead. Make vibration the primary cue, mark tone as "single beep" in settings, and reconsider whether the product is worth shipping tone-first. |
| 3 beeps but uneven / late / stuttering | ⚠️ Partial | Try `BEAT_MS` 60 and a 2-element profile, and consider dropping max spm. Firmware is honouring durations loosely. |
| Beeps stop when you change data page (step 3) | ❌ **Fatal** | `compute()` is not running off-screen. The entire approach is void; nothing rescues it. Stop and report. |
| `profile threw` in the status line | ❌ Profile rejected | Halve the element count and retry; if a 2-element profile also throws, tone mode is out. |
| Nothing at all, `snd0` | — | Not a result. Turn tones on and rerun. |

## Vibration specifics

Forerunners flatten pattern *intensity* — the duty cycle mostly just decides "buzzing or not" — so the **durations** are what carry the rhythm. What matters at step 2 is whether you feel three separate taps or one smear. If it smears, raise the beat length and lower max spm; a vibration metronome above ~180 spm may simply not be resolvable on the wrist.

## Record the outcome here

```
Date:
Firmware version (Settings > System > About):
t / p / v flags:
Step 1 (tone evenness):
Step 2 (vibe distinctness):
Step 3 (off-screen continuation):
Battery over 30 min:
Verdict:
```

Then update the Phase 1 row in the [README](../README.md) status table before moving on.
