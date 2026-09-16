import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! The data field itself.
//!
//! compute() is called about once a second by the native activity, INCLUDING
//! while the field's data page is not on screen -- that is what lets the
//! metronome keep going while the runner looks at their pace page. onUpdate()
//! only runs when the page is visible and does nothing but draw.
//!
//! Note what compute() does NOT do: it does not produce the beat. The beat is
//! a repeating profile the firmware loops on its own clock (see Metronome and
//! docs/SCHEDULING.md). compute() only arms it, tops up the vibration, and
//! watches cadence. Making the wake-up responsible for the rhythm is exactly
//! what produced audibly missing beats in two earlier designs.
//!
//! Deliberately no layout XML: a data field can be given anything from a full
//! screen down to a quarter of a small round watch face, so the layout is
//! computed from the actual dc dimensions instead.
//! Bumped on every sideload, so the field can prove which build is running.
const BUILD = 10;

class MetronomeView extends WatchUi.DataField {

    private var _config as Config;
    private var _grid as BeatGrid;
    private var _cue as Cue;
    private var _metronome as Metronome;
    private var _cadence as CadenceMonitor;

    // Whether the idle silence has been issued since the timer last stopped.
    // Re-issuing it every tick would spam playTone for no reason; issuing it
    // only once per idle period is enough to kill a stale loop.
    private var _clearedWhileIdle as Boolean = false;

    // What the watch last reported, purely so the field can show it. The
    // start/stop decision does NOT come from this -- see the timer callbacks.
    private var _timerState as Number = -1;

    // Silenced by the runner mid-activity. Distinct from _beating: the timer
    // is still running, cadence is still watched and displayed, we are simply
    // not making any noise. Survives a pause and resume -- someone who muted
    // the beat did not mean "until the next traffic light".
    private var _muted as Boolean = false;

    // True while the activity timer is running and the beat should sound.
    // Compared against the timer state every tick rather than tracked through
    // transitions -- see syncToTimerState().
    private var _beating as Boolean = false;

    // Display state, written by compute() and read by onUpdate().
    private var _liveCadence as Number? = null;
    private var _deviation as Number? = null;
    private var _zone as Number = ZONE_UNKNOWN;

    public function initialize() {
        DataField.initialize();

        _config = new Config();
        _grid = new BeatGrid(_config.targetSpm, _config.stepsPerBeat);
        _cue = new Cue();
        _metronome = new Metronome(_grid, _cue);
        _cadence = new CadenceMonitor();
    }

    //! Called from AppBase.onSettingsChanged() when the phone pushes new
    //! settings mid activity. Re-reading here means the runner can change
    //! target cadence from their phone without restarting the run.
    public function reloadSettings() as Void {
        // Note this also discards any lap-button adjustment, which is right:
        // an explicit edit from the phone should win over an in-run nudge.
        _config.load();
        _grid.setTempo(_config.targetSpm, _config.stepsPerBeat);
        _cadence.clear();
        // Metronome notices the interval changed on its next tick and re-arms.
    }

    //! Once per second, for the whole activity.
    public function compute(info as Activity.Info) as Void {
        var now = System.getTimer();
        var timerState = timerStateOf(info);

        _timerState = timerState;
        stopIfTimerNotRunning(timerState);

        _liveCadence = (info has :currentCadence) ? info.currentCadence : null;

        if (!_beating) {
            _zone = ZONE_UNKNOWN;
            _deviation = null;
            return;
        }

        var shouldAlert = _cadence.update(_liveCadence, _config);
        _zone = _cadence.zone();
        _deviation = _cadence.deviationPercent(_config);

        if (_muted) {
            // Keep watching and displaying cadence, but make no noise at all --
            // including the off-target alert, which is the last thing someone
            // who just silenced the metronome wants to hear.
            if (_metronome.isArmed()) {
                _metronome.stop(_config);
            }
            return;
        }

        if (shouldAlert) {
            // There is only one buzzer, so the alert has to interrupt the
            // looping beat. Metronome re-arms on a later tick, at a moment
            // that will not clip a beat.
            _metronome.interruptForAlert(_zone == ZONE_TOO_FAST, _config);
        } else {
            _metronome.tick(now, _config);
        }

        // Vibration cannot be armed the way the tone can -- Attention.vibrate
        // has no repeat -- so it is topped up here every wake-up.
        if (_config.wantsVibe()) {
            _cue.pulseVibe(vibeOffsets(now), _config);
        }
    }

    //! Beat offsets, relative to now, for the next vibration window. Derived
    //! from the same grid the tone is armed against, so the two stay together.
    private function vibeOffsets(nowMs as Number) as Array<Number> {
        var offsets = [] as Array<Number>;
        var interval = _grid.intervalMs();
        var at = _grid.nextBeatDelayMs(nowMs);
        var horizon = _cue.vibeHorizonMs();

        while (at < horizon && offsets.size() < 4) {
            offsets.add(at);
            at += interval;
        }
        return offsets;
    }

    // ------------------------------------------------------------------
    // Timer events. These are the AUTHORITATIVE start and stop signals.
    //
    // Polling Activity.Info.timerState is not: on a real FR165 the field began
    // beating the moment the Run screen was opened, before START was ever
    // pressed. Whatever the watch reports there, these callbacks fire only on
    // the real transitions, so the beat can only ever begin when the runner
    // actually sets off.
    // ------------------------------------------------------------------

    public function onTimerStart() as Void { beginBeating(); }
    public function onTimerResume() as Void { beginBeating(); }

    public function onTimerStop() as Void { endBeating(); }
    public function onTimerPause() as Void { endBeating(); }
    public function onTimerReset() as Void { endBeating(); }

    //! The lap button is the ONLY input a Connect IQ data field can receive --
    //! there is no way to give one a menu or a key handler. So it is what
    //! adjusts the target cadence mid-run, stepping up and wrapping back to the
    //! bottom of the range at the top, because one button means one direction.
    //!
    //! Off by default would make it undiscoverable; on by default risks
    //! surprising someone who presses lap for laps. It is a setting, defaulting
    //! to on, and the new target is shown on the field immediately.
    public function onTimerLap() as Void {
        var action = _config.lapAction;

        if (action == LAP_NOTHING) {
            return;
        }

        if (action == LAP_MUTE) {
            setMuted(!_muted);
            return;
        }

        // Coming out of a silent position resumes at the current target rather
        // than stepping past it, so the press that unmutes does exactly one
        // thing.
        if (_muted) {
            setMuted(false);
            return;
        }

        var wrapped = _config.stepTarget();

        if (wrapped && action == LAP_CADENCE_MUTE) {
            // The silent position sits at the top of the cycle, so the sequence
            // reads 160 -> 165 -> ... -> 180 -> off -> 160, and muting is
            // always reachable without leaving the field.
            setMuted(true);
            return;
        }

        _grid.setTempo(_config.targetSpm, _config.stepsPerBeat);
        _cadence.clear();
        // Metronome sees the interval change on its next tick and re-arms at a
        // moment that will not clip a beat.
    }

    private function setMuted(muted as Boolean) as Void {
        _muted = muted;
        if (_muted) {
            // Silence immediately rather than waiting for the arming to lapse:
            // the runner pressed the button because they want quiet NOW.
            _metronome.stop(_config);
        } else if (_beating) {
            _grid.setTempo(_config.targetSpm, _config.stepsPerBeat);
            _metronome.start(System.getTimer(), _config);
        }
    }

    private function beginBeating() as Void {
        if (_beating) { return; }
        _cadence.clear();
        _beating = true;
        if (!_muted) {
            _metronome.start(System.getTimer(), _config);
        }
    }

    private function endBeating() as Void {
        _beating = false;
        _metronome.stop(_config);
    }

    //! A SAFETY NET, not the start signal.
    //!
    //! This may only ever STOP the beat, never start it. The timer callbacks
    //! above are what start it. That asymmetry is deliberate: the observed
    //! fault was the field beating before the activity had begun, so anything
    //! that could start the beat from polled state is a liability, while
    //! anything that can silence a beat that should not be sounding is pure
    //! benefit.
    //!
    //! It matters because an arming outlives this app -- the firmware keeps
    //! looping whether or not we are still here -- so a stale arming has to be
    //! actively silenced rather than left to expire.
    private function stopIfTimerNotRunning(timerState as Number) as Void {
        if (timerState == Activity.TIMER_STATE_ON) {
            _clearedWhileIdle = false;
            return;
        }

        if (_beating) {
            endBeating();
        }

        // Once per idle period, silence the firmware unconditionally. Not
        // guarded by _metronome.isArmed(), because the loop that needs killing
        // may have been armed by a PREVIOUS instance of this field, which this
        // one has no record of.
        if (!_clearedWhileIdle) {
            _clearedWhileIdle = true;
            _metronome.forceSilence(_config);
        }
    }

    //! Called when the data field is torn down. Without this the firmware
    //! carries on looping the beat for the rest of the arming window, with
    //! nothing left running that could stop it.
    public function onHide() as Void {
        _beating = false;
        _metronome.stop(_config);
    }

    //! Same, for app shutdown.
    public function shutdown() as Void {
        _beating = false;
        _metronome.stop(_config);
    }

    private function timerStateOf(info as Activity.Info) as Number {
        if (info has :timerState && info.timerState != null) {
            return info.timerState;
        }
        // Unknown timer state means we are NOT inside a running activity, so
        // stay silent. The API types this "Null or Activity.TimerState", and
        // defaulting to ON would make the field beep on the pre-start screen.
        return Activity.TIMER_STATE_OFF;
    }

    //! Drawing only. Never cue from here: onUpdate does not run when the page
    //! is off screen.
    public function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;

        dc.setColor(bg, bg);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // The field can be tiny (a quarter of a 4-field page) or nearly full
        // screen, so pick fonts by available height rather than fixed sizes.
        var big = (h >= 90) ? Graphics.FONT_NUMBER_MEDIUM
                : (h >= 60) ? Graphics.FONT_NUMBER_MILD
                : Graphics.FONT_SYSTEM_MEDIUM;
        var small = Graphics.FONT_SYSTEM_XTINY;

        var value = (_liveCadence != null && _liveCadence > 0)
                    ? _liveCadence.format("%d")
                    : "--";

        var zoneColor = fg;
        if (_zone == ZONE_TOO_SLOW || _zone == ZONE_TOO_FAST) {
            zoneColor = Graphics.COLOR_RED;
        } else if (_zone == ZONE_IN_RANGE) {
            zoneColor = Graphics.COLOR_GREEN;
        }

        // Tiny slot: just the number, coloured by zone. Anything more is
        // unreadable at a glance while running.
        if (h < 45) {
            dc.setColor(zoneColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_SYSTEM_MEDIUM, value,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 2, small, label(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(zoneColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2, big, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - dc.getFontHeight(small) - 2, small, footer(),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function label() as String {
        if (!_beating) {
            return WatchUi.loadResource(Rez.Strings.LabelPaused) as String;
        }
        if (_muted) {
            return WatchUi.loadResource(Rez.Strings.LabelSilenced) as String;
        }
        if (_config.wantsTone() && !_cue.tonesAudible() && !_config.wantsVibe()) {
            return WatchUi.loadResource(Rez.Strings.LabelMuted) as String;
        }
        if (_config.wantsTone() && !_cue.hasToneProfile()) {
            return WatchUi.loadResource(Rez.Strings.LabelDegraded) as String;
        }
        return WatchUi.loadResource(Rez.Strings.LabelName) as String;
    }

    //! Bottom line: the TARGET, plus how far off it you currently are.
    //!
    //! Labelled, because the big number above is live cadence and two bare
    //! numbers on one small screen are easy to confuse at a glance mid-run.
    //! The target can change during a run via the lap button, so it has to be
    //! visible rather than something you set once and forget.
    private function footer() as String {
        // Before the activity starts, show what the watch is actually
        // reporting. The field beating early has been chased twice on guesses
        // about this value; now it is simply visible. BUILD is bumped whenever
        // a new .prg is sideloaded, so there is never any doubt about which
        // build is running.
        if (!_beating) {
            // Before the activity starts: which build, what the watch reports
            // for the timer, whether the device has tone profiles at all, and
            // whether its tones are switched on.
            return "b" + BUILD.format("%d")
                 + " ts" + _timerState.format("%d")
                 + " p" + (_cue.hasToneProfile() ? "1" : "0")
                 + " s" + (_cue.tonesAudible() ? "1" : "0");
        }

        var target = WatchUi.loadResource(Rez.Strings.LabelTarget) as String;
        if (_muted) {
            target += " " + (WatchUi.loadResource(Rez.Strings.LabelOff) as String);
        } else {
            target += " " + _config.targetSpm.format("%d");
        }

        // While beating, the metronome's own status rides along: ARM when the
        // firmware is looping, otherwise the reason it is not.
        target += " " + _metronome.status();

        if (_deviation == null) {
            return target;
        }
        var sign = (_deviation > 0) ? "+" : "";
        return target + " " + sign + _deviation.format("%d") + "%";
    }
}
