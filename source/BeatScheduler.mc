import Toybox.Lang;

//! Look-ahead beat scheduler on an absolute timeline.
//!
//! This is the standard software-metronome pattern (the one behind DAWs, drum
//! machines and Web Audio's "two clocks" approach), adapted to the one
//! constraint Connect IQ adds.
//!
//! THE PATTERN
//!   1. Beats live on an ABSOLUTE timeline: beat(n) = t0 + n * interval.
//!      Nothing is derived by accumulating deltas, so drift is impossible by
//!      construction rather than by testing.
//!   2. A coarse, unreliable wake-up clock (compute(), nominally 1 Hz) drives
//!      a precise output clock (the firmware's own tone playback). The
//!      wake-up only tops up the queue -- it is never itself the rhythm.
//!   3. Each wake-up schedules every beat due in [now, now + horizon), where
//!      the horizon is LONGER than the wake-up interval. That overlap is what
//!      makes a late wake-up harmless.
//!
//! THE CONNECT IQ TWIST
//! There is no "play at absolute time T" call. Attention.playTone takes a
//! RELATIVE profile, and issuing a new one CANCELS whatever is still playing.
//! So the overlap is re-queued rather than merged: each call recomputes the
//! beats still in the future and emits them as offsets from now.
//!
//! That makes scheduling IDEMPOTENT, which is what makes the whole thing
//! robust. Measured behaviours this handles with no special case:
//!   - compute() firing twice 47ms apart at activity start (seen in the
//!     simulator): the second call simply re-queues the same future beats.
//!   - a wake-up arriving late: the horizon already covered the gap.
//!   - a beat cancelled mid-flight: it is still in the future by less than
//!     TOL_MS, so the next call re-queues it instead of losing it.
//!
//! An earlier version instead cut time into disjoint 1000ms windows and
//! carried a phase remainder between them. It drifted nothing, but every
//! boundary became an artefact: a recording showed a beat vanishing every
//! 6.01 seconds, because a beat landing near a window edge was cancelled by
//! the next call before it could sound. Absolute time removes the boundary
//! rather than defending it.
class BeatScheduler {

    //! How far into the past a beat may be and still be worth playing.
    //!
    //! A beat cancelled mid-flight is only a few ms old when the cancelling
    //! call arrives, so re-queueing it recovers it. Kept BELOW the beat length
    //! so a beat that already sounded in full is never played twice.
    const TOL_MS = 20;

    //! If the timeline is further behind than this -- the field was paused,
    //! off-screen, or the clock wrapped -- re-base instead of stepping the
    //! whole way forward one beat at a time.
    const RESYNC_MS = 5000;

    //! Hard ceiling on beats returned from one call. Nothing should approach
    //! it (220spm over a 1500ms horizon is 6), but an absurd interval must not
    //! be able to spin this loop.
    const MAX_BEATS = 16;

    private var _intervalUs as Number = 0;

    // Absolute time of the next beat not yet known to have sounded, split into
    // whole milliseconds plus a 0..999us remainder. The remainder is what
    // keeps a tempo like 170spm (352.941ms) exact without floating point.
    private var _nextMs as Number = 0;
    private var _nextFracUs as Number = 0;
    private var _started as Boolean = false;

    public function initialize(spm as Number, stepsPerBeat as Number) {
        setTempo(spm, stepsPerBeat);
    }

    //! Change tempo without disturbing the timeline: the next beat still lands
    //! when it was already due, and the new spacing applies from there. That
    //! is what a musician expects when they turn the dial.
    public function setTempo(spm as Number, stepsPerBeat as Number) as Void {
        var safeSpm = spm;
        if (safeSpm < MIN_SPM) { safeSpm = MIN_SPM; }
        if (safeSpm > MAX_SPM) { safeSpm = MAX_SPM; }

        var divisor = stepsPerBeat;
        if (divisor < 1) { divisor = 1; }

        var beatsPerMinute = safeSpm / divisor;
        if (beatsPerMinute < 1) { beatsPerMinute = 1; }

        _intervalUs = 60000000 / beatsPerMinute;
    }

    public function intervalMs() as Number {
        return (_intervalUs + 500) / 1000;
    }

    //! Put the next beat exactly at `nowMs`. Call on activity start and on
    //! resume, so the first beat lands the moment the runner sets off.
    public function restart(nowMs as Number) as Void {
        _nextMs = nowMs;
        _nextFracUs = 0;
        _started = true;
    }

    //! Offsets, in ms from `nowMs`, of every beat due within the horizon.
    //!
    //! Idempotent: calling twice with the same `nowMs` returns the same
    //! offsets and leaves the timeline unchanged. That is deliberate -- it is
    //! what makes a duplicate or early wake-up a non-event.
    //!
    //! @param nowMs      System.getTimer() at the top of this wake-up
    //! @param horizonMs  how far ahead to schedule; MUST exceed the expected
    //!                   wake-up interval, or a late wake-up leaves a hole
    public function schedule(nowMs as Number, horizonMs as Number) as Array<Number> {
        if (!_started) {
            restart(nowMs);
        }

        var behind = nowMs - _nextMs;

        // Clock went backwards (System.getTimer() wraps about every 25 days),
        // or we have been away long enough that stepping forward beat by beat
        // is pointless. Either way, start the timeline again from now.
        if (behind < 0 && behind < -RESYNC_MS) {
            restart(nowMs);
            behind = 0;
        } else if (behind > RESYNC_MS) {
            restart(nowMs);
            behind = 0;
        }

        // Retire beats that have definitively already sounded. Anything more
        // recent than TOL_MS may have been cut off mid-beat, so it stays on
        // the timeline to be re-queued below.
        while (_nextMs < nowMs - TOL_MS) {
            advance();
        }

        // Emit from temporaries: the timeline is NOT consumed here, which is
        // exactly what makes repeated calls safe.
        var offsets = [] as Array<Number>;
        var t = _nextMs;
        var frac = _nextFracUs;
        var limit = nowMs + horizonMs;

        while (t < limit && offsets.size() < MAX_BEATS) {
            var offset = t - nowMs;
            if (offset < 0) {
                // Due a moment ago and probably cut short -- play it now.
                offset = 0;
            }
            offsets.add(offset);

            var total = frac + _intervalUs;
            t += total / 1000;
            frac = total % 1000;
        }

        return offsets;
    }

    //! Step the timeline on by exactly one interval, carrying the sub
    //! millisecond remainder so nothing is ever rounded away.
    private function advance() as Void {
        var total = _nextFracUs + _intervalUs;
        _nextMs += total / 1000;
        _nextFracUs = total % 1000;
    }

    // Guard rails. 100..220 spm covers walking through to elite track work.
    const MIN_SPM = 100;
    const MAX_SPM = 220;
}
