import Toybox.Lang;

//! Drives the beat by ARMING the firmware rather than by feeding it.
//!
//! WHY THIS EXISTS
//! A data field is woken about once a second and cannot use a Timer, so the
//! obvious design is to hand the firmware the next second of rhythm on every
//! wake-up. That was the first two designs, and both produced audibly missing
//! beats. The reason is structural: a new playTone CANCELS whatever is still
//! playing, and a 40ms beat occupies 40ms of every 353ms at 170spm -- so
//! roughly 11% of wake-ups land on top of a beat and cut it short. Recordings
//! confirmed it: bursts as short as 9.7ms against a 40ms beat.
//!
//! THE FIX IS TO STOP FEEDING IT
//! Attention.playTone accepts :repeatCount (measured on fr165: at least
//! 10000). So the beat pattern is issued ONCE as a single repeating profile
//! and the firmware plays the metronome on its own hardware clock. Perfectly
//! even by construction, because nothing interrupts it.
//!
//! Exposure to the cancellation artefact drops from every wake-up to once
//! per re-arm -- and even that is made harmless by the two rules in tryArm().
class Metronome {

    //! How long one arming lasts.
    //!
    //! This is a SAFETY limit, not a performance one. Once armed, the firmware
    //! loops on its own and keeps beeping even if this app stops running --
    //! so the arming length is the worst case for how long a watch can be left
    //! beeping after an activity ends abruptly, the field is torn down, or the
    //! app is killed. An earlier 10 minute arming made exactly that happen on
    //! a real watch: the beat carried on across screens with no way to stop it.
    //!
    //! 20 seconds bounds the damage while still leaving ~15 wake-ups to find a
    //! safe re-arming moment, so continuity does not suffer.
    const ARM_MS = 20000;

    //! Re-arm once the current arming has less than this left. At 1 Hz that is
    //! ~8 chances to catch a moment when no beat is sounding, and only ~11% of
    //! moments are unsafe.
    const REARM_LEAD_MS = 8000;

    private var _grid as BeatGrid;
    private var _cue as Cue;

    private var _armed as Boolean = false;
    private var _armedUntilMs as Number = 0;
    private var _armedIntervalMs as Number = 0;

    public function initialize(grid as BeatGrid, cue as Cue) {
        _grid = grid;
        _cue = cue;
    }

    //! Stop the beat and forget the arming. The firmware would otherwise keep
    //! playing for the rest of the arming window, straight through a pause.
    public function stop(config as Config) as Void {
        if (_armed) {
            _cue.silenceTone(config);
        }
        _armed = false;
        _armedUntilMs = 0;
    }

    //! Silence the firmware whether or not THIS instance armed it.
    //!
    //! An arming outlives the app that made it, so a loop started by a previous
    //! run of the data field is still playing while a fresh instance sits there
    //! with _armed == false, believing there is nothing to stop. That is
    //! exactly what happened on a real watch: an old build armed for ten
    //! minutes and the beat carried on into the next activity, seemingly
    //! starting "as soon as Run was selected". Guarding the silence behind our
    //! own bookkeeping is the bug; this does not.
    public function forceSilence(config as Config) as Void {
        _cue.silenceTone(config);
        _armed = false;
        _armedUntilMs = 0;
    }

    //! Called when the runner sets off, or resumes.
    public function start(nowMs as Number, config as Config) as Void {
        _grid.restart(nowMs);
        _armed = false;
        armNow(nowMs, 0, config);
    }

    //! One wake-up's worth of work while the metronome should be sounding.
    public function tick(nowMs as Number, config as Config) as Void {
        // A tempo change invalidates the pattern the firmware is looping.
        if (_armedIntervalMs != _grid.intervalMs()) {
            _armed = false;
        }

        if (!_armed) {
            tryArm(nowMs, config);
            return;
        }

        if (_armedUntilMs - nowMs < REARM_LEAD_MS) {
            tryArm(nowMs, config);
        }
    }

    //! The deviation alert has to interrupt the loop -- there is only one
    //! buzzer. Re-arming afterwards is what the next tick() does.
    public function interruptForAlert(tooFast as Boolean, config as Config) as Void {
        _cue.playDeviation(tooFast, config);
        _armed = false;
    }

    public function isArmed() as Boolean {
        return _armed;
    }

    //! Arm only at a moment that cannot damage the rhythm.
    //!
    //! Two conditions, which turn out to be the same condition:
    //!   - the lead-in rest must fit inside one interval alongside the beat,
    //!     i.e. delay <= interval - beat
    //!   - no beat may be sounding right now, or issuing the new profile would
    //!     cut it short -- which is true exactly when delay <= interval - beat
    //!
    //! At 170spm that admits 313ms of every 353ms, so 89% of wake-ups qualify
    //! and there are ~60 chances before the current arming expires. If this
    //! wake-up does not qualify, doing nothing is correct: the firmware is
    //! still playing.
    private function tryArm(nowMs as Number, config as Config) as Void {
        var interval = _grid.intervalMs();
        var delay = _grid.nextBeatDelayMs(nowMs);
        var beatMs = _cue.beatMs();

        if (delay > interval - beatMs) {
            return;     // a beat is sounding; wait for the next wake-up
        }

        armNow(nowMs, delay, config);
    }

    //! Issue the repeating profile.
    //!
    //! The lead-in rest goes INSIDE the repeating profile and the trailing
    //! rest is shortened to match, so the profile is exactly one interval long
    //! and the beat sits at `delay` within every repetition. That is what
    //! keeps re-arming phase-accurate instead of restarting the grid.
    private function armNow(nowMs as Number, delay as Number, config as Config) as Void {
        var interval = _grid.intervalMs();
        var repeats = ARM_MS / interval;
        if (repeats < 1) { repeats = 1; }

        var armed = _cue.armBeat(interval, delay, repeats, config);
        if (!armed) {
            return;
        }

        _armed = true;
        _armedIntervalMs = interval;
        _armedUntilMs = nowMs + delay + repeats * interval;
    }
}
