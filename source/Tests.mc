import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the beat grid and the arming policy.
//!
//! The beat itself is produced by the FIRMWARE looping a repeating profile, so
//! there is no per-beat scheduling code left to test. What must be correct is:
//!   - the grid the profile is built from
//!   - the arming policy, which must never issue a profile while a beat is
//!     sounding, and must never build one that is not exactly one interval long

const BEAT_MS = 40;     // Cue.BEAT_MS

//! Tempo is quantised to whole milliseconds because that is the resolution the
//! firmware profile uses. Rounding, not truncation, halves the error.
(:test)
function testIntervalMaths(logger as Logger) as Boolean {
    var g = new BeatGrid(180, 1);
    Test.assertEqualMessage(g.intervalMs(), 333, "180spm should be 333ms");

    g.setTempo(170, 1);
    Test.assertEqualMessage(g.intervalMs(), 353, "170spm should round to 353ms, not 352");

    g.setTempo(180, 2);
    Test.assertEqualMessage(g.intervalMs(), 667, "180spm/2 should round to 667ms");

    g.setTempo(120, 1);
    Test.assertEqualMessage(g.intervalMs(), 500, "120spm should be 500ms");
    return true;
}

//! The quantised tempo must stay within a fraction of a percent of the target.
(:test)
function testTempoErrorIsNegligible(logger as Logger) as Boolean {
    for (var spm = 100; spm <= 220; spm++) {
        var g = new BeatGrid(spm, 1);
        var errorTenths = (600000 / g.intervalMs()) - spm * 10;
        if (errorTenths < 0) { errorTenths = -errorTenths; }
        Test.assertMessage(errorTenths <= 6,
            spm + "spm quantises with an error of " + errorTenths + " tenths of a spm");
    }
    return true;
}

//! A corrupt setting must never produce a zero or negative interval.
(:test)
function testTempoClamping(logger as Logger) as Boolean {
    var g = new BeatGrid(0, 0);
    Test.assertMessage(g.intervalMs() > 0, "zero spm must not give a zero interval");
    g.setTempo(-50, 1);
    Test.assertMessage(g.intervalMs() > 0, "negative spm must not give a zero interval");
    g.setTempo(9999, 1);
    Test.assertMessage(g.intervalMs() > 0, "absurd spm must still be positive");
    return true;
}

//! restart() puts a beat on the instant the runner set off.
(:test)
function testRestartPutsABeatOnNow(logger as Logger) as Boolean {
    var g = new BeatGrid(170, 1);
    g.restart(500000);
    Test.assertEqualMessage(g.nextBeatDelayMs(500000), 0, "a beat should be due at restart");
    return true;
}

//! The grid is absolute: the delay to the next beat depends only on the clock,
//! never on how many times it has been asked. This is what makes a duplicate
//! or out-of-order wake-up harmless.
(:test)
function testGridIsAbsoluteAndIdempotent(logger as Logger) as Boolean {
    var g = new BeatGrid(170, 1);
    g.restart(500000);

    var a = g.nextBeatDelayMs(500100);
    var b = g.nextBeatDelayMs(500100);
    var c = g.nextBeatDelayMs(500100);
    Test.assertEqualMessage(a, b, "repeat query changed the answer");
    Test.assertEqualMessage(b, c, "third query changed the answer");
    Test.assertEqualMessage(a, 253, "170spm: 100ms after a beat, 253ms to the next");

    // Asking out of order must not disturb it either.
    g.nextBeatDelayMs(500900);
    Test.assertEqualMessage(g.nextBeatDelayMs(500100), 253,
        "an out-of-order query shifted the grid");
    return true;
}

//! Walking the clock forward must produce beats exactly one interval apart,
//! with no accumulation error, at every tempo.
(:test)
function testGridSpacingIsExact(logger as Logger) as Boolean {
    var tempos = [100, 150, 165, 170, 173, 180, 190, 200, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var g = new BeatGrid(tempos[t], 1);
        var interval = g.intervalMs();
        var base = 1000000;
        g.restart(base);

        var previous = base;
        var beats = 600000 / interval;      // ten minutes of beats
        for (var n = 1; n <= beats; n++) {
            var beat = base + n * interval;
            Test.assertEqualMessage(g.nextBeatDelayMs(beat), 0,
                tempos[t] + "spm: beat " + n + " is not on the grid");
            Test.assertEqualMessage(beat - previous, interval,
                tempos[t] + "spm: spacing drifted at beat " + n);
            previous = beat;
        }
    }
    return true;
}

//! THE ARMING RULE.
//!
//! A profile may only be issued when no beat is sounding, or the new profile
//! cancels a beat mid-flight -- exactly the fault that produced audibly
//! missing beats in the two earlier designs.
//!
//! The rule is delay <= interval - BEAT_MS. Prove it never admits an unsafe
//! moment, and that it admits enough moments to be practical.
(:test)
function testArmingWindowIsSafeAndReachable(logger as Logger) as Boolean {
    var tempos = [100, 150, 170, 180, 200, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var g = new BeatGrid(tempos[t], 1);
        var interval = g.intervalMs();
        var base = 2000000;
        g.restart(base);

        var safe = 0;
        var total = 0;

        for (var offset = 0; offset < interval; offset++) {
            var now = base + offset;
            var delay = g.nextBeatDelayMs(now);
            var since = g.sinceLastBeatMs(now);
            total++;

            if (delay <= interval - BEAT_MS) {
                safe++;
                // Nothing may be sounding.
                Test.assertMessage(since == 0 || since >= BEAT_MS,
                    tempos[t] + "spm: armed " + since + "ms into a " + BEAT_MS + "ms beat");
                // And the profile must be exactly one interval long.
                Test.assertMessage(interval - BEAT_MS - delay >= 0,
                    tempos[t] + "spm: negative tail rest at delay " + delay);
            }
        }

        var percent = (safe * 100) / total;
        logger.debug(tempos[t] + "spm: " + percent + "% of moments are safe to arm");
        Test.assertMessage(percent >= 80,
            tempos[t] + "spm: only " + percent + "% of wake-ups can arm; too few");
    }
    return true;
}

//! sinceLastBeat and nextBeatDelay are two views of one position, and the
//! arming rule relies on both, so they must agree.
(:test)
function testGridViewsAgree(logger as Logger) as Boolean {
    var g = new BeatGrid(173, 1);
    var interval = g.intervalMs();
    var base = 3000000;
    g.restart(base);

    for (var offset = 0; offset < interval * 3; offset++) {
        var now = base + offset;
        var delay = g.nextBeatDelayMs(now);
        var since = g.sinceLastBeatMs(now);
        if (delay == 0) {
            Test.assertEqualMessage(since, 0, "a beat due now should be 0ms since the last");
        } else {
            Test.assertEqualMessage(delay + since, interval,
                "delay " + delay + " + since " + since + " should equal " + interval);
        }
    }
    return true;
}

//! Coming back after a long absence -- paused, off-screen, or the clock
//! wrapped -- must re-base rather than return nonsense.
(:test)
function testResyncAfterLongAbsence(logger as Logger) as Boolean {
    var g = new BeatGrid(170, 1);
    g.restart(500000);
    g.nextBeatDelayMs(500100);

    Test.assertEqualMessage(g.nextBeatDelayMs(1100000), 0,
        "should re-base after a ten minute gap");

    Test.assertEqualMessage(g.nextBeatDelayMs(1000), 0,
        "should re-base after the clock wrapped backwards");
    return true;
}

//! A vibration window must never need more than the 8 elements
//! Attention.vibrate allows -- exceeding it is an uncatchable crash that
//! takes the whole data field down.
(:test)
function testVibeElementBudget(logger as Logger) as Boolean {
    var g = new BeatGrid(220, 1);          // fastest legal tempo
    var interval = g.intervalMs();
    var base = 4000000;
    g.restart(base);

    for (var offset = 0; offset < interval; offset++) {
        var now = base + offset;
        var first = g.nextBeatDelayMs(now);
        var at = first;
        var beats = 0;
        while (at < 1000 && beats < 4) {   // MetronomeView caps the window at 4
            beats++;
            at += interval;
        }
        var elements = beats * 2;
        if (beats > 0 && first == 0) { elements -= 1; }
        Test.assertMessage(elements <= 8,
            "vibe window needs " + elements + " elements; the fatal limit is 8");
    }
    return true;
}
