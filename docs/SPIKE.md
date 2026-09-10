# Phase 1 — Hardware capability spike

**Run this before trusting anything else in the repo.**

## The assumption under test

The product rests on one thing that no documentation confirms and no simulator can prove: that a Forerunner 165, from inside a data field, will accept a **multi-element tone profile** and play it back **evenly, sub-second, once per second, forever**.

The docs say `playTone` accepts `:toneProfile` and that data fields may call it. They do not say what happens when you call it again a second later while the previous profile may still be playing, and they do not say whether FR165 firmware honours the durations faithfully. Those are the questions.

## Build and load

```bash
cd /d/Projects/garmin-workout-metronome/spike
monkeyc -f monkey.jungle -o bin/spike.prg -y /d/Projects/.keys/workout_metronome.der -d fr165 -w
```

Copy `bin\spike.prg` to `GARMIN\APPS\` on the watch, then add **Metronome Spike** to a run data screen.

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
