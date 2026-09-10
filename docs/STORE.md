# Phase 6 — Connect IQ Store submission

## Pre-flight

- [ ] Phase 1 spike passed on real hardware, outcome recorded in [SPIKE.md](SPIKE.md)
- [ ] Full on-device matrix in [TESTING.md](TESTING.md) passed, especially test 6 (off-screen)
- [ ] `manifest.xml` version is `1.0.0`
- [ ] Permissions are **only** `Attention` — do not add `Positioning`, `FitContributor`, or anything else this app doesn't use; extra permissions slow review and cost installs
- [ ] Products list is `fr165` + `fr165m` only
- [ ] Build with `-w` and fix every warning
- [ ] Developer key backed up somewhere off this machine

## Build the release package

```bash
cd /d/Projects/garmin-workout-metronome
monkeyc -e -f monkey.jungle -o bin/WorkoutMetronome.iq -y /d/Projects/.keys/workout_metronome.der -w -r
```

`-e` exports the `.iq` bundle (all devices at once — this is the file you upload, not a `.prg`), `-r` builds in release mode. In VS Code: **Monkey C: Export Project**.

## Assets to prepare

| Asset | Spec | Notes |
|---|---|---|
| App icon | 1024×1024 PNG | The 40×40 `launcher_icon.png` in the repo is the on-watch icon, *not* the store icon — make a proper one |
| Screenshots | ≥1, ideally 3–5, at FR165 resolution (390×390) | Take from the simulator: **Simulation → Capture Screen** |
| Name | "Workout Metronome" | Store rules forbid "Garmin" in an app name |
| Category | **Data Fields** | |

Good screenshot set: in-range (green) · too slow (red, with the % footer) · a 4-field page showing the compact layout · the settings screen in Connect Mobile.

## Listing copy

**Short description**

> A running metronome that keeps beating inside your native run and structured workouts — not just as a standalone app.

**Long description** — lead with the thing that differentiates it and the thing that causes support tickets:

> Most Garmin metronomes are watch apps, so they stop the moment you start a run. This is a **data field**: add it to a run data screen and it beats for the whole activity, including structured workouts, even while you're looking at another data page.
>
> - Set your target cadence (100–220 steps per minute)
> - Beat on every step, every other step, or every 4th
> - Choose tone, vibration, or both
> - Get a distinct alert when your cadence drifts more than 5% off target — rising tone to speed up, falling tone to slow down
>
> **Setup:** add "Workout Metronome" to a data screen in your Run activity settings. **Settings are changed in Garmin Connect Mobile** (your device → Activities & App Management → Data Fields → Workout Metronome → Settings) — Garmin does not allow data fields to be configured on the watch itself.
>
> **Tone requires watch sounds to be switched on** (Settings → System → Sound and Vibe).
>
> Currently supports Forerunner 165 and 165 Music. More devices are being added as each is tested — this app cues audio and vibration at precise sub-second intervals, and that behaviour varies by hardware, so devices are only added once verified rather than listed optimistically.

That last paragraph pre-empts the "why isn't my watch supported" reviews, and the two bold lines pre-empt the two guaranteed one-star reviews (settings not on watch; no sound because tones are muted).

## Submit

1. Free developer account at <https://apps.garmin.com> → **Upload an App**
2. Upload the `.iq`, fill in the listing, attach screenshots
3. Submit for review — typically a few business days

Expect one rejection round. The usual causes: permissions in the manifest the app doesn't actually use, a crash on a device in the product list you never tested, missing settings documentation, or an icon at the wrong size.

## After approval

- Watch the reviews for the first fortnight — data field reviews skew hostile because of the settings-location confusion
- Then widen the device list per [DEVICE-EXPANSION.md](DEVICE-EXPANSION.md)
- Keep the developer key. Without it there is no path to publishing 1.0.1.
