# Installing on the Forerunner 165

Two ways in. Sideloading is right while the app is still being developed; the store comes later.

## Sideload over USB (what you want now)

### 1. Build

```
tools\build.cmd device
```

Produces `bin\WorkoutMetronome.prg`. Use `tools\build.cmd device fr165m` if yours is the Music edition — the `.prg` is built per device and the wrong one simply will not appear on the watch.

### 2. Copy it to the watch

1. Plug the FR165 in by USB. It mounts as a drive called **GARMIN**.
2. Open `GARMIN\APPS\` on that drive.
3. Copy `bin\WorkoutMetronome.prg` into it.
4. **Eject the drive properly** (Safely Remove Hardware), then unplug. Pulling the cable without ejecting is the usual reason an app does not show up.

The watch does not need a restart.

### 3. Add it to a run data screen

On the watch:

1. Press **START** → choose **Run**
2. Hold **UP** (the middle-left button) to open the activity menu
3. **Run Settings** → **Data Screens**
4. Pick a screen to edit, or **Add New**
5. Choose a field position → scroll to **Connect IQ Fields** → pick **Workout Metronome**
6. Press **BACK** out of the menus

The field now sits on that screen. It reads `PAUSED` until you press START to begin the activity; then the header changes to `CADENCE` and the beat starts.

### 4. Turn tones on

**Settings → System → Sound and Vibe** → make sure **Tones** are on (and **Vibration** if you want the vibration cue). If tones are muted, the field's header shows `MUTED` rather than pretending to work.

## Changing the settings

Data field settings **cannot be edited on the watch** — Garmin does not allow it. They live in the phone app:

**Garmin Connect Mobile** → your device → **Activities & App Management** → **Data Fields** → **Workout Metronome** → **Settings**

| Setting | Default | |
|---|---|---|
| Target cadence | 170 | steps per minute, 100–220 |
| Beat on | Every step | or every other / every 4th step |
| Beat using | Tone and vibration | or either alone |
| Off-target alert | On | fires when smoothed cadence drifts outside the band |
| Alert band | 5% | |
| Alert delay | 3 s | seconds off target before it fires |
| Alert cooldown | 10 s | minimum gap between alerts |

For a sideloaded app the settings only appear in Connect Mobile once the watch has synced, which can take a few minutes after install.

## Uninstalling

Delete the `.prg` from `GARMIN\APPS\`, or on the watch: **Settings → Connect IQ Apps → Data Fields → Workout Metronome → Remove**.

## The timing ruler (measurement probe)

Alongside the app there is a throwaway probe used to calibrate the beat timing against the real firmware. Everything measured so far comes from the **simulator**, whose audio path need not behave like the watch — so the numbers need confirming on hardware before the tempo can be trusted.

```
tools\build.cmd probe
```

Copy `probe\bin\probe.prg` to `GARMIN\APPS\` the same way, then add **Timing Ruler** to a data screen. It starts beeping as soon as the field is shown — no need to start an activity.

Record about 30 seconds of it with a phone held near the watch, in a quiet room. The beeps come in a repeating group of four with deliberately different spacings (roughly 245 / 350 / 455 / 560 ms), and measuring those four intervals reveals how the firmware rounds the durations it is given. See [SCHEDULING.md](SCHEDULING.md).

Remove the probe once the calibration is done — it is not part of the product.

## Later: installing from the Connect IQ store

Once submitted and approved, installation is the normal route: find it in the Connect IQ store app, tap install, and it syncs to the watch. Steps 3 and 4 above are still needed — a data field always has to be added to a data screen by hand. See [STORE.md](STORE.md).
