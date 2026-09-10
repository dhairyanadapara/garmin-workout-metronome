import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the pure logic. Run with:
//!   monkeyc -f monkey.jungle -o bin/test.prg -y <key>.der -d fr165 --unit-test
//!   monkeydo bin/test.prg fr165 -t
//! or in VS Code: "Monkey C: Run Tests".
//!
//! These functions are annotated (:test) and are excluded from release builds,
//! so they cost nothing on device.

//! A beat interval is 60s / beats-per-minute.
(:test)
function testIntervalMaths(logger as Logger) as Boolean {
    var s = new BeatScheduler(180, 1);
    // 180 beats/min -> 333ms
    Test.assertEqualMessage(s.intervalMs(), 333, "180spm should be ~333ms");

    s.setTempo(180, 2);   // beat every other step -> 90 beats/min -> 666ms
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

//! The first window at 180spm starts on a beat and spaces them ~333ms apart.
//! Note the count per window is NOT fixed even at a tempo that divides evenly
//! into a second: microsecond truncation can pull a fourth beat in at ~999ms,
//! and the following window then holds three. That is correct -- what matters
//! is the SPACING, never the per-window count.
(:test)
function testFirstWindow(logger as Logger) as Boolean {
    var s = new BeatScheduler(180, 1);
    var w = s.nextWindow(1000);
    Test.assertMessage(w.size() == 3 || w.size() == 4,
        "180spm should give 3 or 4 beats in the first second, got " + w.size());
    Test.assertEqualMessage(w[0], 0, "first beat at offset 0");
    Test.assertEqualMessage(w[1], 333, "second beat at 333ms");
    Test.assertEqualMessage(w[2], 666, "third beat at 666ms");
    return true;
}

//! THE IMPORTANT ONE. 170spm does not divide evenly into one second, so a
//! naive implementation that restarts the phase each tick would emit a beat at
//! offset 0 of every window and stutter once a second. Phase must carry over.
(:test)
function testPhaseCarriesAcrossWindows(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);   // 352.9ms
    var first = s.nextWindow(1000);
    var second = s.nextWindow(1000);

    Test.assertEqualMessage(first[0], 0, "first window starts on a beat");
    Test.assertMessage(second[0] != 0,
        "second window must NOT start on a beat -- phase did not carry over");

    // Gap across the window boundary must equal one beat interval.
    var lastOfFirst = first[first.size() - 1];
    var gap = (1000 - lastOfFirst) + second[0];
    var interval = s.intervalMs();
    var error = gap - interval;
    if (error < 0) { error = -error; }
    Test.assertMessage(error <= 2,
        "cross-window gap " + gap + "ms should equal the interval " + interval + "ms");
    return true;
}

//! Over an hour of ticks the total beat count must match the expected count.
//! This is the drift test: 1ms of leak per beat would show up as dozens of
//! missing or extra beats here.
(:test)
function testNoDriftOverAnHour(logger as Logger) as Boolean {
    var spm = 173;                       // deliberately awkward, 346.8ms
    var s = new BeatScheduler(spm, 1);

    var total = 0;
    for (var tick = 0; tick < 3600; tick++) {
        total += s.nextWindow(1000).size();
    }

    var expected = spm * 60;             // beats in 60 minutes
    var error = total - expected;
    if (error < 0) { error = -error; }
    logger.debug("beats=" + total + " expected=" + expected + " error=" + error);

    // Allow a couple of beats for the integer-microsecond truncation only.
    Test.assertMessage(error <= 2,
        "drifted by " + error + " beats over an hour (expected <= 2)");
    return true;
}

//! Offsets must always sit inside the window they were requested for --
//! Cue turns them into rest durations, and an out-of-range offset would
//! produce a negative rest.
(:test)
function testOffsetsWithinWindow(logger as Logger) as Boolean {
    var s = new BeatScheduler(100, 4);  // slowest legal tempo: 25 beats/min
    for (var tick = 0; tick < 100; tick++) {
        var w = s.nextWindow(1000);
        // At 25 beats/min a beat lands only every 2.4s, so most windows here
        // are legitimately EMPTY. That is fine; what must hold is that any
        // offset we do emit is inside the window.
        for (var i = 0; i < w.size(); i++) {
            Test.assertMessage(w[i] >= 0 && w[i] < 1000,
                "offset " + w[i] + " outside the window");
        }
    }
    return true;
}

//! Offsets must be strictly ascending -- a tone profile is played in order, so
//! an out-of-order offset would produce a negative rest duration.
(:test)
function testOffsetsAscending(logger as Logger) as Boolean {
    var s = new BeatScheduler(200, 1);
    for (var tick = 0; tick < 50; tick++) {
        var w = s.nextWindow(1000);
        for (var i = 1; i < w.size(); i++) {
            Test.assertMessage(w[i] > w[i - 1], "offsets must ascend within a window");
        }
    }
    return true;
}

//! reset() must put the next beat back at offset 0 -- this is what makes the
//! first beat after an unpause land immediately.
(:test)
function testResetAlignsPhase(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    s.nextWindow(1000);
    s.nextWindow(1000);
    s.reset();
    var w = s.nextWindow(1000);
    Test.assertEqualMessage(w[0], 0, "reset should align the next beat to offset 0");
    return true;
}
