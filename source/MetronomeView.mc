import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The data field itself.
//!
//! compute() is the heartbeat of the whole app: it is called once per second
//! by the native activity, INCLUDING while the field's data page is not on
//! screen, which is what lets the metronome keep going while the runner looks
//! at their pace page. onUpdate() only runs when the page is visible and does
//! nothing but draw.
//!
//! Deliberately no layout XML: a data field can be given anything from a
//! full screen down to a quarter of a small round watch face, so the layout is
//! computed from the actual dc dimensions instead.
class MetronomeView extends WatchUi.DataField {

    private var _config as Config;
    private var _scheduler as BeatScheduler;
    private var _cue as Cue;
    private var _cadence as CadenceMonitor;

    // Last known timer state, so we can detect the start/pause/resume edges
    // that need to reset the beat phase.
    private var _lastTimerState as Number = Activity.TIMER_STATE_OFF;
    private var _beating as Boolean = false;

    // Display state, written by compute() and read by onUpdate().
    private var _liveCadence as Number? = null;
    private var _deviation as Number? = null;
    private var _zone as Number = ZONE_UNKNOWN;

    public function initialize() {
        DataField.initialize();

        _config = new Config();
        _scheduler = new BeatScheduler(_config.targetSpm, _config.stepsPerBeat);
        _cue = new Cue();
        _cadence = new CadenceMonitor();
    }

    //! Called from AppBase.onSettingsChanged() when the phone pushes new
    //! settings mid activity. Re-reading here means the runner can change
    //! target cadence from their phone without restarting the run.
    public function reloadSettings() as Void {
        _config.load();
        _scheduler.setTempo(_config.targetSpm, _config.stepsPerBeat);
        _cadence.clear();
    }

    //! Once per second, for the whole activity.
    public function compute(info as Activity.Info) as Void {
        var timerState = timerStateOf(info);

        handleTimerEdges(timerState);

        _liveCadence = (info has :currentCadence) ? info.currentCadence : null;

        if (!_beating) {
            _zone = ZONE_UNKNOWN;
            _deviation = null;
            return;
        }

        var shouldAlert = _cadence.update(_liveCadence, _config);
        _zone = _cadence.zone();
        _deviation = _cadence.deviationPercent(_config);

        // Always advance the scheduler's phase, even on an alert tick, so the
        // beat grid stays aligned to the wall clock rather than shifting by a
        // second every time the runner drifts out of range.
        var offsets = _scheduler.nextWindow(_cue.windowMs(), _cue.minBeatMs());

        if (shouldAlert) {
            // The alert replaces this window's beats. Overlapping them would
            // put two things through one buzzer and muddle both.
            var tooFast = (_zone == ZONE_TOO_FAST);
            _cue.playDeviation(tooFast, _config);
            return;
        }

        _cue.playBeats(offsets, _config);
    }

    //! Start beating on the timer running, stop on pause/stop, and reset the
    //! beat phase across every edge so the first beat after a resume lands
    //! immediately rather than at some leftover fraction of a second.
    private function handleTimerEdges(timerState as Number) as Void {
        if (timerState == _lastTimerState) { return; }

        var nowRunning = (timerState == Activity.TIMER_STATE_ON);

        if (nowRunning) {
            _scheduler.reset();
            _cadence.clear();
            // Always start beating with the timer. There is deliberately no
            // "start manually" option: a data field cannot receive any user
            // input, so an off-by-default metronome could never be switched
            // on. If you want it silent, remove the field from the page.
            _beating = true;
        } else {
            _beating = false;
        }

        _lastTimerState = timerState;
    }

    private function timerStateOf(info as Activity.Info) as Number {
        if (info has :timerState && info.timerState != null) {
            return info.timerState;
        }
        // Very old API levels omit timerState. Treat elapsed time moving as
        // "running" -- but minApiLevel is 3.2 so this is belt and braces.
        return Activity.TIMER_STATE_ON;
    }

    //! Drawing only. Never cue from here: onUpdate does not run when the page
    //! is off screen, and cueing here would make the beat stop the moment the
    //! runner scrolled to another data page.
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

        // Label
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 2, small, label(), Graphics.TEXT_JUSTIFY_CENTER);

        // Live cadence, big
        dc.setColor(zoneColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2, big, value,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Target + deviation footer
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - dc.getFontHeight(small) - 2, small, footer(),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function label() as String {
        if (!_beating) {
            return WatchUi.loadResource(Rez.Strings.LabelPaused) as String;
        }
        if (_config.wantsTone() && !_cue.tonesAudible() && !_config.wantsVibe()) {
            // The runner has asked for tones but muted the watch -- say so,
            // otherwise the field looks broken.
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
