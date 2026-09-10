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
//! The trap this class exists to avoid: if you restart the beat phase at each
//! compute() tick, the beat silently drifts against the wall clock and the
//! rhythm stutters once per second. Instead we carry the fractional remainder
//! of the last window forward, in microseconds, using exact integer maths.
class BeatScheduler {

    // Microseconds until the next beat, measured from the START of the next
    // window we are asked to fill. Always in [0, _intervalUs).
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

    //! Every beat offset (in ms, relative to the window start) that falls
    //! inside the next `windowMs` window, and advance the phase.
    //!
    //! Call this EXACTLY ONCE per window you actually play. Calling it twice
    //! without playing the first window advances the phase and loses beats.
    public function nextWindow(windowMs as Number) as Array<Number> {
        var windowUs = windowMs * 1000;
        var offsets = [] as Array<Number>;

        var atUs = _carryUs;
        while (atUs < windowUs) {
            offsets.add(atUs / 1000);
            atUs += _intervalUs;
        }

        // Carry the overshoot into the next window. This is the whole point:
        // the phase is continuous across the 1 Hz compute() boundary.
        _carryUs = atUs - windowUs;

        return offsets;
    }

    // Guard rails. 100..220 spm covers walking through to elite track work;
    // outside that the tone profile either has too few or too many elements.
    const MIN_SPM = 100;
    const MAX_SPM = 220;
}
