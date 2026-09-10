# Widening beyond the Forerunner 165

v1.0 ships `fr165` + `fr165m` only. That is deliberate, not timidity: this app depends on precise sub-second audio and haptic scheduling, and that behaviour is firmware- and hardware-specific. A device added without testing becomes a one-star review, and a data field's rating is very hard to recover.

## The gating requirements

A candidate device must have:

1. **API level ≥ 3.2.0** (the manifest's `minApiLevel`)
2. **Data field support** (every modern watch has it; some Edge units differ)
3. **`Attention has :ToneProfile`** — this is the one that actually varies, and it's what the spike checks
4. A vibration motor, if vibration mode is to be usable

## Order to expand in

Nearest hardware first, because the closer the platform the likelier the tone behaviour matches what was validated:

1. **FR255 / FR265 series** — closest siblings. Note both have a *native* metronome already, so the selling point there is the ±5% off-target alert and the workout-long behaviour, not the metronome itself.
2. **FR55, FR570, FR970** — same family, different generations.
3. **Fenix 7/8, epix, Venu** — different screen shapes; re-check the compact layouts.
4. **Edge units** — only if there's demand. Cycling cadence is a different use case and the copy would need rewriting.

## Procedure per device family

1. Add the product ids to `manifest.xml`.
2. Install that device in the SDK Manager and run the full simulator matrix from [TESTING.md](TESTING.md) — layouts break first on round vs. semi-round screens and on small displays.
3. **Run the [spike](SPIKE.md) on real hardware of that family.** Borrow one if you have to; the simulator cannot answer the tone-queuing question. If nobody can test it, either leave the device off the list or ship it and say plainly in the listing that it's untested.
4. Bump the version, resubmit, and mention the new devices in the release notes.

## Layout risks when the screen changes

`MetronomeView.onUpdate` computes everything from the actual `dc` dimensions and has no layout XML, so it adapts — but two things still need eyes on them per family:

- **Semi-round / edge-cut screens:** `getObscurityFlags()` is currently unused. On devices where a data field is clipped at the screen edge, the centred text may need nudging.
- **Very small fields** (a 4-field page on a 240×240 watch): the `h < 45` branch drops to number-only. Check that the number still fits.

## What not to do

Don't list every CIQ 3.2+ device at launch to maximise reach. The store lets you do it and it reliably backfires: the app installs on hardware where `ToneProfile` is absent, users get one beep a second instead of a metronome, and the reviews say "doesn't work" — which is both true and permanent.
