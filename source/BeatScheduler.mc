import Toybox.Lang;

//! Pure beat-timing maths. No I/O, no Toybox.Attention, no Activity -- so it
//! can be unit tested in the simulator without a running activity.
//!
//! WHY THIS CLASS EXISTS
//! A Connect IQ data field cannot use Toybox.Timer and compute() is called
//! only once per second. So we never "tick" a beat; instead, once per second
//! we ask this class for every beat offset that falls inside the NEXT one
//! second window, and hand that whole window to the firmware as a single
//! queued tone/vibe profile.
//!
//! TWO TRAPS THIS CLASS EXISTS TO AVOID
//!
//! 1. PHASE DRIFT. If you restart the beat phase at each compute() tick, the
//!    beat drifts against the wall clock and the rhythm stutters once per
//!    second. Instead we carry the fractional remainder of the last window
//!    forward, in microseconds, using exact integer maths.
//!
//! 2. THE TRUNCATED TAIL. A recording of the running metronome showed a beat
//!    vanishing every ~6 seconds at 170spm -- gaps of 706ms against a 353ms
//!    interval. The cause: when the next second's playTone call arrives, the
//!    firmware CANCELS whatever of the previous profile is still playing. Any
//!    beat scheduled in the last few milliseconds of a window was therefore
//!    silently cut to nothing.
//!
//!    So a beat is only scheduled if at least `minBeatMs` of it can sound
//!    before the window ends. One that cannot is carried into the next window
//!    and lands at offset 0 there -- late by less than minBeatMs, rather than
//!    missing altogether. Beats that fit but cannot run full length are
//!    shortened in place by Cue, which costs nothing perceptually: rhythm is
//!    carried by a beat's ONSET, not its duration.
class BeatScheduler {

    // Microseconds until the next beat, measured from the START of the next
    // window we are asked to fill.
    //
    // Usually in [0, _intervalUs). It can be slightly NEGATIVE -- down to
    // -minBeatUs -- when a beat was carried over from the previous window
    // because it could not finish there. A negative carry means "this beat was
    // due just before now", and it is emitted at offset 0.
    private var _carryUs as Number = 0;

    // Microseconds between beats.
    private var _intervalUs as Number = 0;

    //! @param spm target steps per minute (the runner's cadence target)
    //! @param stepsPerBeat 1 = beat on every step, 2 = every other step, 4 = every 4th
    public function initialize(spm as Number, stepsPerBeat as Number) {
        setTempo(spm, stepsPerBeat);
    }

    //! Change tempo. Resets phase, because a tempo change is a deliberate
    //! discontinuity -- carrying the old phase over would produce one
    //! wrong-length gap at the changeover.
    public function setTempo(spm as Number, stepsPerBeat as Number) as Void {
        var safeSpm = spm;
        if (safeSpm < MIN_SPM) { safeSpm = MIN_SPM; }
        if (safeSpm > MAX_SPM) { safeSpm = MAX_SPM; }

        var divisor = stepsPerBeat;
        if (divisor < 1) { divisor = 1; }

        var beatsPerMinute = safeSpm / divisor;
        if (beatsPerMinute < 1) { beatsPerMinute = 1; }

        // 60 s in microseconds / beats per minute. Integer division loses at
        // most 1us per beat -- ~11ms over an hour at 180spm. Irrelevant next
        // to the firmware's own scheduling granularity (milliseconds).
        _intervalUs = 60000000 / beatsPerMinute;
        _carryUs = 0;
    }

    //! Beat interval in whole milliseconds (for display / tests).
    public function intervalMs() as Number {
        return (_intervalUs + 500) / 1000;
    }

    //! Drop the accumulated phase so the next window starts with a beat at
    //! offset 0. Call on activity start, unpause, or manual restart.
    public function reset() as Void {
        _carryUs = 0;
    }

    //! Every beat offset (in ms, relative to the window start) that can
    //! actually SOUND inside the next `windowMs` window, and advance the phase.
    //!
    //! Call this EXACTLY ONCE per window you actually play. Calling it twice
    //! without playing the first window advances the phase and loses beats.
    //!
    //! @param windowMs    length of the window being filled
    //! @param minBeatMs   shortest beat worth scheduling; a beat with less
    //!                    room than this defers to the next window
    public function nextWindow(windowMs as Number, minBeatMs as Number) as Array<Number> {
        var windowUs = windowMs * 1000;
        var minBeatUs = minBeatMs * 1000;
        var offsets = [] as Array<Number>;

        var atUs = _carryUs;

        // Only schedule a beat that has room to be heard. This is the guard
        // against the truncated tail described above.
        while (atUs + minBeatUs <= windowUs) {
            var offsetUs = atUs;
            if (offsetUs < 0) {
                // Carried over from the previous window: play it immediately.
                offsetUs = 0;
            }
            offsets.add(offsetUs / 1000);

            // Advance by the TRUE interval, not from the clamped offset, so
            // carrying a beat over never shifts the underlying grid.
            atUs += _intervalUs;
        }

        // Carry the overshoot -- or the shortfall, if we stopped early to
        // avoid a truncated beat -- into the next window. This is the whole
        // point: the phase is continuous across the 1 Hz compute() boundary.
        _carryUs = atUs - windowUs;

        return offsets;
    }

    // Guard rails. 100..220 spm covers walking through to elite track work;
    // outside that the tone profile either has too few or too many elements.
    const MIN_SPM = 100;
    const MAX_SPM = 220;
}
