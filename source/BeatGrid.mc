import Toybox.Lang;

//! The absolute beat timeline.
//!
//! Deliberately works in whole milliseconds, because that is the resolution
//! the firmware's tone profile works in. Modelling the grid more finely than
//! the hardware can express it would only let our idea of where a beat is
//! drift away from where it actually sounds.
//!
//! The cost is a tempo quantised to integer milliseconds: 170spm wants
//! 352.94ms and gets 353ms, so the real tempo is 169.97spm. That is a 0.017%
//! error -- about one beat per hour, and utterly inaudible. What a runner
//! actually feels is the SPACING between consecutive beats, and that is exact.
class BeatGrid {

    private var _intervalMs as Number = 353;
    private var _anchorMs as Number = 0;
    private var _started as Boolean = false;

    public function initialize(spm as Number, stepsPerBeat as Number) {
        setTempo(spm, stepsPerBeat);
    }

    //! @return true if the tempo actually changed
    public function setTempo(spm as Number, stepsPerBeat as Number) as Boolean {
        var safeSpm = spm;
        if (safeSpm < MIN_SPM) { safeSpm = MIN_SPM; }
        if (safeSpm > MAX_SPM) { safeSpm = MAX_SPM; }

        var divisor = stepsPerBeat;
        if (divisor < 1) { divisor = 1; }

        var bpm = safeSpm / divisor;
        if (bpm < 1) { bpm = 1; }

        // Round to nearest millisecond rather than truncating: at 170spm that
        // is 353 rather than 352, halving the tempo error.
        var interval = (60000 + bpm / 2) / bpm;
        if (interval < 1) { interval = 1; }

        var changed = (interval != _intervalMs);
        _intervalMs = interval;
        return changed;
    }

    public function intervalMs() as Number {
        return _intervalMs;
    }

    //! Put a beat exactly on `nowMs`.
    public function restart(nowMs as Number) as Void {
        _anchorMs = nowMs;
        _started = true;
    }

    public function isStarted() as Boolean {
        return _started;
    }

    //! Milliseconds from `nowMs` until the next beat is due, in
    //! [0, intervalMs). Zero means a beat is due right now.
    public function nextBeatDelayMs(nowMs as Number) as Number {
        if (!_started) {
            restart(nowMs);
            return 0;
        }

        var since = nowMs - _anchorMs;

        // The clock wrapped (System.getTimer() wraps about every 25 days) or
        // we have been away so long the anchor is meaningless. Re-base.
        if (since < 0 || since > RESYNC_MS) {
            restart(nowMs);
            return 0;
        }

        var phase = since % _intervalMs;
        if (phase == 0) {
            return 0;
        }
        return _intervalMs - phase;
    }

    //! Milliseconds since the previous beat began, in [0, intervalMs).
    public function sinceLastBeatMs(nowMs as Number) as Number {
        var delay = nextBeatDelayMs(nowMs);
        if (delay == 0) {
            return 0;
        }
        return _intervalMs - delay;
    }

    const RESYNC_MS = 5000;
    const MIN_SPM = 100;
    const MAX_SPM = 220;
}
