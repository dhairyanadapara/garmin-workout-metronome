import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the pure logic. Run with `tools/build.sh test`, or in
//! VS Code: "Monkey C: Run Tests".
//!
//! These functions are annotated (:test) and are excluded from release builds,
//! so they cost nothing on device.

const WIN = 1000;      // the scheduling window Cue uses
const MINB = 15;       // Cue.MIN_BEAT_MS

//! A beat interval is 60s / beats-per-minute.
(:test)
function testIntervalMaths(logger as Logger) as Boolean {
    var s = new BeatScheduler(180, 1);
    Test.assertEqualMessage(s.intervalMs(), 333, "180spm should be ~333ms");

    s.setTempo(180, 2);   // beat every other step -> 90 beats/min
    Test.assertEqualMessage(s.intervalMs(), 667, "180spm/2 should be ~667ms");

    s.setTempo(120, 1);
    Test.assertEqualMessage(s.intervalMs(), 500, "120spm should be 500ms");
    return true;
}

//! Tempo is clamped, not trusted: a corrupt property must not divide by zero.
(:test)
function testTempoClamping(logger as Logger) as Boolean {
    var s = new BeatScheduler(0, 0);
    Test.assertMessage(s.intervalMs() > 0, "zero spm must not produce a zero interval");

    s.setTempo(-50, 1);
    Test.assertMessage(s.intervalMs() > 0, "negative spm must not produce a zero interval");

    s.setTempo(9999, 1);
    Test.assertMessage(s.intervalMs() > 0, "absurd spm must still be positive");
    return true;
}

//! The first window at 180spm starts on a beat, spaced ~333ms.
(:test)
function testFirstWindow(logger as Logger) as Boolean {
    var s = new BeatScheduler(180, 1);
    var w = s.nextWindow(WIN, MINB);
    Test.assertMessage(w.size() >= 3, "180spm should give at least 3 beats in a second");
    Test.assertEqualMessage(w[0], 0, "first beat at offset 0");
    Test.assertEqualMessage(w[1], 333, "second beat at 333ms");
    Test.assertEqualMessage(w[2], 666, "third beat at 666ms");
    return true;
}

//! 170spm does not divide evenly into a second, so a naive implementation
//! that restarts the phase each tick would emit a beat at offset 0 of every
//! window and stutter once a second. Phase must carry over.
(:test)
function testPhaseCarriesAcrossWindows(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    var first = s.nextWindow(WIN, MINB);
    var second = s.nextWindow(WIN, MINB);

    Test.assertEqualMessage(first[0], 0, "first window starts on a beat");
    Test.assertMessage(second[0] != 0,
        "second window must NOT start on a beat -- phase did not carry over");

    var lastOfFirst = first[first.size() - 1];
    var gap = (WIN - lastOfFirst) + second[0];
    var interval = s.intervalMs();
    var error = gap - interval;
    if (error < 0) { error = -error; }
    Test.assertMessage(error <= 2,
        "cross-window gap " + gap + "ms should equal the interval " + interval + "ms");
    return true;
}

//! REGRESSION TEST FOR THE DROPPED BEAT.
//!
//! A recording of the metronome at 170spm showed a beat vanishing roughly
//! every 6 seconds: gaps of ~706ms where 353ms was expected. The firmware
//! cancels a tone profile that is still playing when the next playTone call
//! arrives, so any beat scheduled in the last few ms of a window was cut to
//! silence.
//!
//! This test replays that firmware behaviour against the scheduler and
//! asserts that no beat is ever scheduled where it would be truncated.
(:test)
function testNoBeatIsTruncated(logger as Logger) as Boolean {
    var tempos = [100, 150, 165, 170, 173, 180, 190, 200, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var s = new BeatScheduler(spm, 1);

        for (var tick = 0; tick < 600; tick++) {
            var w = s.nextWindow(WIN, MINB);
            for (var i = 0; i < w.size(); i++) {
                // A beat must have at least MINB of room before the window
                // ends, or the firmware will swallow it.
                Test.assertMessage(w[i] + MINB <= WIN,
                    "at " + spm + "spm a beat at " + w[i] +
                    "ms leaves under " + MINB + "ms of window -- it would be truncated");
            }
        }
    }
    return true;
}

//! The same scenario end to end: reconstruct the absolute beat times the way
//! the recording measured them, and assert no gap is ever ~2x the interval.
(:test)
function testNoDroppedBeatsOverTime(logger as Logger) as Boolean {
    var spm = 170;                       // the tempo in the recording
    var s = new BeatScheduler(spm, 1);
    var interval = s.intervalMs();

    var previous = -1;
    var worstGap = 0;
    var drops = 0;
    var count = 0;

    for (var tick = 0; tick < 900; tick++) {   // 15 minutes
        var w = s.nextWindow(WIN, MINB);
        for (var i = 0; i < w.size(); i++) {
            var absolute = tick * WIN + w[i];
            if (previous >= 0) {
                var gap = absolute - previous;
                if (gap > worstGap) { worstGap = gap; }
                // A dropped beat shows up as a gap of about two intervals.
                if (gap > (interval * 3) / 2) { drops++; }
            }
            previous = absolute;
            count++;
        }
    }

    logger.debug("beats=" + count + " worstGap=" + worstGap + "ms interval=" + interval + "ms");
    Test.assertEqualMessage(drops, 0,
        "found " + drops + " dropped beats (worst gap " + worstGap + "ms)");

    // And the total must still be right -- the guard must not lose beats.
    var expected = spm * 15;
    var diff = count - expected;
    if (diff < 0) { diff = -diff; }
    Test.assertMessage(diff <= 2,
        "beat count " + count + " should be ~" + expected);
    return true;
}

//! Deferring a beat to the next window makes it slightly late. Bound that.
(:test)
function testTimingErrorIsBounded(logger as Logger) as Boolean {
    var tempos = [150, 165, 170, 173, 180, 190, 200, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var s = new BeatScheduler(spm, 1);
        var interval = s.intervalMs();
        var previous = -1;
        var worst = 0;

        for (var tick = 0; tick < 600; tick++) {
            var w = s.nextWindow(WIN, MINB);
            for (var i = 0; i < w.size(); i++) {
                var absolute = tick * WIN + w[i];
                if (previous >= 0) {
                    var error = (absolute - previous) - interval;
                    if (error < 0) { error = -error; }
                    if (error > worst) { worst = error; }
                }
                previous = absolute;
            }
        }

        logger.debug(spm + "spm worst timing error = " + worst + "ms");
        Test.assertMessage(worst <= MINB + 2,
            spm + "spm: worst error " + worst + "ms exceeds the " + MINB + "ms bound");
    }
    return true;
}

//! Over an hour the total beat count must match. This is the drift guard.
(:test)
function testNoDriftOverAnHour(logger as Logger) as Boolean {
    var spm = 173;                       // deliberately awkward
    var s = new BeatScheduler(spm, 1);

    var total = 0;
    for (var tick = 0; tick < 3600; tick++) {
        total += s.nextWindow(WIN, MINB).size();
    }

    var expected = spm * 60;
    var error = total - expected;
    if (error < 0) { error = -error; }
    logger.debug("beats=" + total + " expected=" + expected + " error=" + error);

    Test.assertMessage(error <= 2,
        "drifted by " + error + " beats over an hour (expected <= 2)");
    return true;
}

//! Offsets must sit inside the window -- Cue turns them into rest durations,
//! and an out-of-range offset would produce a negative rest.
(:test)
function testOffsetsWithinWindow(logger as Logger) as Boolean {
    var s = new BeatScheduler(100, 4);  // slowest legal tempo: 25 beats/min
    for (var tick = 0; tick < 100; tick++) {
        var w = s.nextWindow(WIN, MINB);
        // At 25 beats/min most windows are legitimately EMPTY. What must hold
        // is that any offset we do emit is inside the window.
        for (var i = 0; i < w.size(); i++) {
            Test.assertMessage(w[i] >= 0 && w[i] < WIN,
                "offset " + w[i] + " outside the window");
        }
    }
    return true;
}

//! Offsets must be strictly ascending -- a tone profile plays in order, so an
//! out-of-order offset would produce a negative rest duration.
(:test)
function testOffsetsAscending(logger as Logger) as Boolean {
    var s = new BeatScheduler(200, 1);
    for (var tick = 0; tick < 50; tick++) {
        var w = s.nextWindow(WIN, MINB);
        for (var i = 1; i < w.size(); i++) {
            Test.assertMessage(w[i] > w[i - 1], "offsets must ascend within a window");
        }
    }
    return true;
}

//! A window must never need more elements than Attention.vibrate allows (8).
//! Each beat costs a rest plus the beat itself.
(:test)
function testVibeElementCapNotExceeded(logger as Logger) as Boolean {
    var s = new BeatScheduler(220, 1);   // fastest legal tempo
    for (var tick = 0; tick < 300; tick++) {
        var w = s.nextWindow(WIN, MINB);
        var elements = w.size() * 2;
        if (w.size() > 0 && w[0] == 0) { elements -= 1; }   // no leading rest
        Test.assertMessage(elements <= 8,
            "window needs " + elements + " vibe elements, cap is 8");
    }
    return true;
}

//! reset() must put the next beat back at offset 0 -- this is what makes the
//! first beat after an unpause land immediately.
(:test)
function testResetAlignsPhase(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    s.nextWindow(WIN, MINB);
    s.nextWindow(WIN, MINB);
    s.reset();
    var w = s.nextWindow(WIN, MINB);
    Test.assertEqualMessage(w[0], 0, "reset should align the next beat to offset 0");
    return true;
}
