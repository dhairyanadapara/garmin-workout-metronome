import Toybox.Lang;

// Where the runner's cadence sits relative to the target band.
enum CadenceZone {
    ZONE_UNKNOWN = 0,   // no cadence reading yet (not running, or paused)
    ZONE_IN_RANGE = 1,
    ZONE_TOO_SLOW = 2,
    ZONE_TOO_FAST = 3
}

//! Watches live cadence against the target band and decides when to fire the
//! out of range alert.
//!
//! Two things make this non trivial and both are about not nagging the runner:
//!
//! 1. SMOOTHING. Raw currentCadence jitters by several spm stride to stride,
//!    and a single odd stride (a curb, a dodge, a glance at the watch) must not
//!    trip a +/-5% band. We average over a short rolling window.
//!
//! 2. HYSTERESIS. Even smoothed, cadence hovering right on the boundary would
//!    alert every few seconds. So an alert needs N consecutive out of range
//!    ticks to fire, then goes quiet for a cooldown, and only fully re arms
//!    once the runner is genuinely back inside the band.
class CadenceMonitor {

    // Rolling average length in seconds (== compute() ticks). Five seconds is
    // roughly 15 strides -- long enough to be stable, short enough that a real
    // drift is caught within a few strides of happening.
    const WINDOW_TICKS = 5;

    // Cadence is meaningless for the first few seconds of a run while the
    // runner is still accelerating off the line, so stay silent through it.
    const WARMUP_TICKS = 15;

    private var _samples as Array<Number>;
    private var _count as Number = 0;      // valid samples in the ring
    private var _head as Number = 0;       // next write position
    private var _sum as Number = 0;

    private var _zone as Number = ZONE_UNKNOWN;
    private var _outOfRangeTicks as Number = 0;
    private var _cooldownTicks as Number = 0;
    private var _activeTicks as Number = 0;

    public function initialize() {
        _samples = new Array<Number>[WINDOW_TICKS];
        clear();
    }

    //! Forget all history. Call on activity start and on unpause -- cadence
    //! from before a pause says nothing about cadence after it.
    public function clear() as Void {
        for (var i = 0; i < WINDOW_TICKS; i++) {
            _samples[i] = 0;
        }
        _count = 0;
        _head = 0;
        _sum = 0;
        _zone = ZONE_UNKNOWN;
        _outOfRangeTicks = 0;
        _cooldownTicks = 0;
        _activeTicks = 0;
    }

    //! Feed one tick of data.
    //! @param cadence raw Activity.Info.currentCadence -- may be null
    //! @param config  target band settings
    //! @return true when the caller should play the deviation alert THIS tick
    public function update(cadence as Number?, config as Config) as Boolean {
        if (_cooldownTicks > 0) {
            _cooldownTicks--;
        }

        // A null or zero cadence means "not currently striding" -- standing at
        // a crossing, or the wrist sensor has lost the rhythm. Not an error to
        // alert about, so hold the previous state and wait.
        if (cadence == null || cadence <= 0) {
            _zone = ZONE_UNKNOWN;
            _outOfRangeTicks = 0;
            return false;
        }

        _activeTicks++;
        push(cadence);

        // Do not judge cadence until the rolling window is actually full.
        if (_count < WINDOW_TICKS || _activeTicks < WARMUP_TICKS) {
            _zone = ZONE_UNKNOWN;
            return false;
        }

        var avg = average();
        var tolerance = (config.targetSpm * config.deviationPercent) / 100;
        if (tolerance < 1) { tolerance = 1; }

        var low = config.targetSpm - tolerance;
        var high = config.targetSpm + tolerance;

        if (avg < low) {
            _zone = ZONE_TOO_SLOW;
        } else if (avg > high) {
            _zone = ZONE_TOO_FAST;
        } else {
            // Back in the band: re arm immediately so the next genuine drift
            // is reported without waiting out the cooldown.
            _zone = ZONE_IN_RANGE;
            _outOfRangeTicks = 0;
            _cooldownTicks = 0;
            return false;
        }

        if (!config.deviationEnabled) {
            return false;
        }

        _outOfRangeTicks++;
        if (_outOfRangeTicks < config.deviationConfirmTicks) {
            return false;
        }
        if (_cooldownTicks > 0) {
            return false;
        }

        _cooldownTicks = config.deviationCooldownSec;
        return true;
    }

    public function zone() as Number {
        return _zone;
    }

    //! Smoothed cadence, or null before the window fills.
    public function smoothedCadence() as Number? {
        if (_count < WINDOW_TICKS) { return null; }
        return average();
    }

    //! Signed deviation from target as a percentage, or null if unknown.
    public function deviationPercent(config as Config) as Number? {
        var avg = smoothedCadence();
        if (avg == null || config.targetSpm <= 0) { return null; }
        return ((avg - config.targetSpm) * 100) / config.targetSpm;
    }

    private function push(cadence as Number) as Void {
        if (_count == WINDOW_TICKS) {
            _sum -= _samples[_head];
        } else {
            _count++;
        }
        _samples[_head] = cadence;
        _sum += cadence;
        _head = (_head + 1) % WINDOW_TICKS;
    }

    private function average() as Number {
        if (_count == 0) { return 0; }
        return _sum / _count;
    }
}
