# Phase 5 — Test matrix

## Unit tests

```bash
tools/build.sh test
```

Eight tests in [`source/Tests.mc`](../source/Tests.mc), all on `BeatScheduler`. **Status: all 8 pass** against SDK 9.2.0. The one that matters most is `testPhaseCarriesAcrossWindows` — it fails if anyone ever "simplifies" the scheduler by restarting the phase each tick, which is the change that would silently reintroduce a once-per-second stutter.

`testNoDriftOverAnHour` is the regression guard on timing accuracy.

## Simulator

`Ctrl+F5` in VS Code, then use the simulator menus:

| Check | How | Pass |
|---|---|---|
| All field sizes | Simulation → Data Fields → 1, 2, 3, 4-field layouts | Readable in every slot; tiny slot shows just the number |
| Cadence colouring | Simulation → Activity Data → set cadence 170 | Number goes green |
| Too slow alert | Set cadence 150, wait ~20 s | Fires **once**, red, then silent for the cooldown |
| Too fast alert | Set cadence 195 | Fires once, distinct from the slow alert |
| Re-arm | Return to 170, then drop to 150 again | Alerts again promptly (in-range resets the cooldown) |
| No nagging | Hold 150 for 3 minutes | Alerts spaced by the cooldown, not every second |
| Warm-up silence | Start activity, cadence 150 immediately | Silent for the first 15 s |
| Pause | Pause the timer | Header reads PAUSED, no cues |
| Resume | Resume | Beat restarts on the beat, cadence history cleared |
| Muted tones | Simulation → Device Settings → tones off, cue mode = tone | Header reads MUTED |
| Structured workout | Simulation → Activity → load a workout | Beat is continuous across step transitions |
| Memory | Run with the memory viewer open | Well under the data-field cap; flat over time (no leak) |

Cue playback in the simulator is not trustworthy for *timing* — that's what the on-device spike is for. Use the simulator for logic and layout.

## On device (FR165)

| # | Scenario | Pass criteria |
|---|---|---|
| 1 | Plain 20 min run, tone+vibe, 170 spm | Even beat throughout; no stutter at the second boundary |
| 2 | Structured workout from Garmin Connect | Beat continuous across every step transition |
| 3 | Treadmill (indoor run, wrist cadence) | Cadence reads sensibly; alerts behave |
| 4 | Pause 2 min mid-run, resume | Silent while paused; clean restart |
| 5 | Tones muted in system settings | Vibration still beats; header reads MUTED if vibe is also off |
| 6 | Field on a **non-visible** data page for 10 min | Beat never stops — the core guarantee |
| 7 | Alongside another CIQ data field | Both work; no memory error |
| 8 | 45 min continuous | Battery drain noted for the store listing |
| 9 | Change target spm in Connect Mobile **mid-run** | Tempo changes without ending the activity |
| 10 | Every-other-step mode at 180 spm | Beat at 90/min, feels like a downbeat |
| 11 | Full run start→save→sync | FIT file uploads normally, no corruption |

Test 6 is the whole product. If it fails, nothing else matters.

## Known-acceptable behaviour

- The number of beats **per second window** varies between 3 and 4 at some tempos. That's microsecond truncation, and the *spacing* stays correct to within 1 ms — do not "fix" it.
- A beat's tone can overrun the 1000 ms window by up to 40 ms. Deliberate: clamping it would truncate that beat to an inaudible click. See the comment in `Cue.queueToneWindow`.
- Vibration above ~180 spm may feel like a smear rather than distinct taps. That's the motor's ramp time, not a bug.
