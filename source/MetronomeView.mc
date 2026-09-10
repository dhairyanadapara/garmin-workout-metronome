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
class MetronomeView extends WatchUi.DataField {

    private var _config as Config;
    private var _grid as BeatGrid;
    private var _cue as Cue;
    private var _metronome as Metronome;
    private var _cadence as CadenceMonitor;

    // Last known timer state, so we can detect the start/pause/resume edges.
    private var _lastTimerState as Number = Activity.TIMER_STATE_OFF;
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
        _config.load();
        _grid.setTempo(_config.targetSpm, _config.stepsPerBeat);
        _cadence.clear();
        // Metronome notices the interval changed on its next tick and re-arms.
    }

    //! Once per second, for the whole activity.
    public function compute(info as Activity.Info) as Void {
        var now = System.getTimer();
        var timerState = timerStateOf(info);

        handleTimerEdges(timerState, now);

        _liveCadence = (info has :currentCadence) ? info.currentCadence : null;

        if (!_beating) {
            _zone = ZONE_UNKNOWN;
            _deviation = null;
            return;
        }

        var shouldAlert = _cadence.update(_liveCadence, _config);
        _zone = _cadence.zone();
        _deviation = _cadence.deviationPercent(_config);

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

    //! Start beating when the timer runs, stop on pause or stop.
    private function handleTimerEdges(timerState as Number, nowMs as Number) as Void {
        if (timerState == _lastTimerState) { return; }

        var nowRunning = (timerState == Activity.TIMER_STATE_ON);

        if (nowRunning) {
            _cadence.clear();
            _beating = true;
            // Put a beat exactly on the moment the runner set off.
            _metronome.start(nowMs, _config);
        } else {
            _beating = false;
            // Essential: the firmware would otherwise keep looping the beat
            // straight through the pause, for the rest of the arming window.
            _metronome.stop(_config);
        }

        _lastTimerState = timerState;
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
        if (_config.wantsTone() && !_cue.tonesAudible() && !_config.wantsVibe()) {
            return WatchUi.loadResource(Rez.Strings.LabelMuted) as String;
        }
        if (_config.wantsTone() && !_cue.hasToneProfile()) {
            return WatchUi.loadResource(Rez.Strings.LabelDegraded) as String;
        }
        return WatchUi.loadResource(Rez.Strings.LabelName) as String;
    }

    private function footer() as String {
        var target = _config.targetSpm.format("%d");
        if (_deviation == null) {
            return target;
        }
        var sign = (_deviation > 0) ? "+" : "";
        return target + "  " + sign + _deviation.format("%d") + "%";
    }
}
