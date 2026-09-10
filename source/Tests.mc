import Toybox.Lang;
import Toybox.Test;

//! Unit tests for the look-ahead scheduler. Run with `tools/build.sh test`.
//!
//! These test the PROPERTIES the pattern relies on -- idempotence, absolute
//! timing, horizon overlap -- rather than particular offsets, because it is
//! those properties that make the scheduler robust to a wake-up clock that
//! fires twice, late, or not at all.

const HORIZON = 1500;   // Cue.TONE_HORIZON_MS
const VIBE_CAP = 8;     // Cue.VIBE_MAX_ELEMENTS -- exceeding it is fatal

//! Play a whole run of wake-ups and return the absolute times of the beats
//! that actually SOUND, applying the firmware rule that a new playTone
//! cancels an unfinished profile.
function soundedBeats(spm as Number, wakeups as Array<Number>) as Array<Number> {
    var s = new BeatScheduler(spm, 1);
    s.restart(wakeups[0]);

    var heard = [] as Array<Number>;

    for (var i = 0; i < wakeups.size(); i++) {
        var now = wakeups[i];
        var offsets = s.schedule(now, HORIZON);
        var cancelAt = (i + 1 < wakeups.size()) ? wakeups[i + 1] : 0x7FFFFFFF;

        for (var k = 0; k < offsets.size(); k++) {
            var start = now + offsets[k];
            if (start >= cancelAt) {
                break;              // cancelled before it began
            }
            // A beat re-queued after being cut short counts once.
            if (heard.size() > 0 && start - heard[heard.size() - 1] < 25) {
                continue;
            }
            heard.add(start);
        }
    }
    return heard;
}

function worstGapError(times as Array<Number>, intervalMs as Number) as Number {
    var worst = 0;
    for (var i = 1; i < times.size(); i++) {
        var error = (times[i] - times[i - 1]) - intervalMs;
        if (error < 0) { error = -error; }
        if (error > worst) { worst = error; }
    }
    return worst;
}

function countDrops(times as Array<Number>, intervalMs as Number) as Number {
    var drops = 0;
    for (var i = 1; i < times.size(); i++) {
        if ((times[i] - times[i - 1]) > (intervalMs * 3) / 2) {
            drops++;
        }
    }
    return drops;
}

function evenWakeups(count as Number, periodMs as Number) as Array<Number> {
    var w = [] as Array<Number>;
    for (var i = 0; i < count; i++) {
        w.add(100000 + i * periodMs);
    }
    return w;
}

//! Tempo maths.
(:test)
function testIntervalMaths(logger as Logger) as Boolean {
    var s = new BeatScheduler(180, 1);
    Test.assertEqualMessage(s.intervalMs(), 333, "180spm should be ~333ms");
    s.setTempo(180, 2);
    Test.assertEqualMessage(s.intervalMs(), 667, "180spm/2 should be ~667ms");
    s.setTempo(120, 1);
    Test.assertEqualMessage(s.intervalMs(), 500, "120spm should be 500ms");
    return true;
}

//! A corrupt setting must not produce a zero or negative interval.
(:test)
function testTempoClamping(logger as Logger) as Boolean {
    var s = new BeatScheduler(0, 0);
    Test.assertMessage(s.intervalMs() > 0, "zero spm must not give a zero interval");
    s.setTempo(-50, 1);
    Test.assertMessage(s.intervalMs() > 0, "negative spm must not give a zero interval");
    s.setTempo(9999, 1);
    Test.assertMessage(s.intervalMs() > 0, "absurd spm must still be positive");
    return true;
}

//! THE PROPERTY THE WHOLE DESIGN RESTS ON.
//!
//! Scheduling must be idempotent: the same clock reading must produce the same
//! answer and leave the timeline untouched. This is what makes a duplicate
//! wake-up a non-event, and it is what the old window-based scheduler could
//! not do -- there, every call consumed a window whether or not time had moved.
(:test)
function testScheduleIsIdempotent(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    s.restart(500000);

    var a = s.schedule(500000, HORIZON);
    var b = s.schedule(500000, HORIZON);
    var c = s.schedule(500000, HORIZON);

    Test.assertEqualMessage(a.size(), b.size(), "repeat call changed the beat count");
    Test.assertEqualMessage(b.size(), c.size(), "third call changed the beat count");
    for (var i = 0; i < a.size(); i++) {
        Test.assertEqualMessage(a[i], b[i], "repeat call changed offset " + i);
        Test.assertEqualMessage(b[i], c[i], "third call changed offset " + i);
    }
    return true;
}

//! REGRESSION: compute() fires twice 47ms apart at activity start (measured in
//! the simulator). The rhythm must be unaffected.
(:test)
function testDuplicateWakeupAtStart(logger as Logger) as Boolean {
    var tempos = [150, 170, 173, 200, 220];
    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var interval = new BeatScheduler(spm, 1).intervalMs();

        var w = [100000, 100047] as Array<Number>;
        for (var i = 1; i < 90; i++) { w.add(100000 + i * 1000); }

        var heard = soundedBeats(spm, w);
        var drops = countDrops(heard, interval);
        var worst = worstGapError(heard, interval);
        logger.debug(spm + "spm dup-start: beats=" + heard.size()
                     + " drops=" + drops + " worstErr=" + worst + "ms");

        Test.assertEqualMessage(drops, 0, spm + "spm: duplicate start tick dropped a beat");
        Test.assertMessage(worst <= 45, spm + "spm: worst error " + worst + "ms after duplicate tick");
    }
    return true;
}

//! REGRESSION FOR THE 6-SECOND DROPOUT.
//!
//! A recording at 170spm showed a beat vanishing every 6.01 seconds: 10 in 60
//! seconds, gaps of ~700ms against a 353ms interval. The cause was a beat
//! landing at a scheduling-window boundary and being cancelled before it could
//! sound. With an absolute timeline and an overlapping horizon there are no
//! boundaries, so this must be exactly zero.
(:test)
function testNoDroppedBeatsUnderCleanClock(logger as Logger) as Boolean {
    var tempos = [100, 150, 165, 170, 173, 180, 190, 200, 220];
    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var interval = new BeatScheduler(spm, 1).intervalMs();
        var heard = soundedBeats(spm, evenWakeups(120, 1000));
        var drops = countDrops(heard, interval);
        var worst = worstGapError(heard, interval);
        logger.debug(spm + "spm clean: beats=" + heard.size()
                     + " drops=" + drops + " worstErr=" + worst + "ms");
        Test.assertEqualMessage(drops, 0, spm + "spm dropped " + drops + " beats on a clean clock");
        Test.assertMessage(worst <= 25, spm + "spm worst error " + worst + "ms");
    }
    return true;
}

//! A jittery wake-up clock -- a watch busy with GPS, HR and screen redraws --
//! must not disturb the rhythm, because the rhythm comes from the absolute
//! timeline and not from when we happened to be called.
(:test)
function testJitteryWakeupClock(logger as Logger) as Boolean {
    var jitter = [0, 63, -47, 28, -71, 15, 80, -22, 51, -66, 9, 74, -35, 42, -58];
    var tempos = [170, 173, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var interval = new BeatScheduler(spm, 1).intervalMs();

        var w = [] as Array<Number>;
        for (var i = 0; i < 120; i++) {
            w.add(100000 + i * 1000 + jitter[i % jitter.size()]);
        }

        var heard = soundedBeats(spm, w);
        var drops = countDrops(heard, interval);
        var worst = worstGapError(heard, interval);
        logger.debug(spm + "spm jitter: beats=" + heard.size()
                     + " drops=" + drops + " worstErr=" + worst + "ms");
        Test.assertEqualMessage(drops, 0, spm + "spm dropped a beat under wake-up jitter");
        Test.assertMessage(worst <= 45, spm + "spm worst error " + worst + "ms under jitter");
    }
    return true;
}

//! The horizon exists to cover a LATE wake-up. A 1500ms horizon must survive a
//! wake-up arriving 500ms late; that is the whole reason it is not 1000ms.
(:test)
function testHorizonCoversALateWakeup(logger as Logger) as Boolean {
    var spm = 170;
    var interval = new BeatScheduler(spm, 1).intervalMs();

    var w = [] as Array<Number>;
    var t = 100000;
    for (var i = 0; i < 90; i++) {
        w.add(t);
        t += (i % 7 == 3) ? 1450 : 1000;   // every 7th wake-up is 450ms late
    }

    var heard = soundedBeats(spm, w);
    var drops = countDrops(heard, interval);
    logger.debug("late-wakeup: beats=" + heard.size() + " drops=" + drops);
    Test.assertEqualMessage(drops, 0, "a late wake-up left a hole: " + drops + " drops");
    return true;
}

//! Absolute timing means no drift, ever. Over half an hour the number of
//! beats actually SOUNDED must match exactly, not approximately.
//!
//! Note this must be counted through the firmware model, not by tallying
//! offsets: the scheduler deliberately re-emits a beat that was due within
//! TOL_MS, because that is how a beat cancelled mid-flight is recovered. A
//! naive tally counts those twice.
(:test)
function testNoDriftOverHalfAnHour(logger as Logger) as Boolean {
    var tempos = [150, 170, 173, 220];

    for (var t = 0; t < tempos.size(); t++) {
        var spm = tempos[t];
        var heard = soundedBeats(spm, evenWakeups(1800, 1000));

        // The last wake-up schedules a horizon beyond the measured window, so
        // allow the beats that fall past the final second.
        var expected = spm * 30;
        var error = heard.size() - expected;
        if (error < 0) { error = -error; }

        logger.debug(spm + "spm: beats=" + heard.size() + " expected=" + expected
                     + " error=" + error);
        Test.assertMessage(error <= 2,
            spm + "spm drifted by " + error + " beats over 30 minutes");
    }
    return true;
}

//! FATAL-IF-WRONG: Attention.vibrate raises an UNCATCHABLE error above 8
//! elements, measured on the fr165 target. A vibe profile costs a rest plus a
//! beat per beat, so the scheduler must never hand Cue more beats than that
//! budget allows for the vibe horizon Cue actually uses.
(:test)
function testVibeElementBudget(logger as Logger) as Boolean {
    // Cue truncates to VIBE_CAP, but prove the truncation is never reached at
    // the vibe horizon, so the vibration is not silently cut short either.
    var s = new BeatScheduler(220, 1);      // fastest legal tempo
    var base = 300000;
    s.restart(base);

    var worst = 0;
    for (var i = 0; i < 300; i++) {
        var offsets = s.schedule(base + i * 1000, 1000);   // vibe uses one window
        var elements = offsets.size() * 2;
        if (offsets.size() > 0 && offsets[0] == 0) { elements -= 1; }
        if (elements > worst) { worst = elements; }
    }

    logger.debug("worst vibe elements at 220spm over a 1000ms horizon = " + worst);
    Test.assertMessage(worst <= VIBE_CAP,
        "needs " + worst + " vibe elements; the uncatchable limit is " + VIBE_CAP);
    return true;
}

//! Offsets must be ascending and inside the horizon: Cue turns them into rest
//! durations, and anything else produces a negative rest.
(:test)
function testOffsetsWellFormed(logger as Logger) as Boolean {
    var tempos = [100, 150, 170, 200, 220];
    for (var t = 0; t < tempos.size(); t++) {
        var s = new BeatScheduler(tempos[t], 1);
        var base = 400000;
        s.restart(base);
        for (var i = 0; i < 200; i++) {
            var offsets = s.schedule(base + i * 1000, HORIZON);
            for (var k = 0; k < offsets.size(); k++) {
                Test.assertMessage(offsets[k] >= 0 && offsets[k] < HORIZON,
                    "offset " + offsets[k] + " outside the horizon");
                if (k > 0) {
                    Test.assertMessage(offsets[k] > offsets[k - 1],
                        "offsets must ascend within a call");
                }
            }
        }
    }
    return true;
}

//! restart() puts the next beat on the instant the runner set off.
(:test)
function testRestartAlignsToNow(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    s.restart(500000);
    s.schedule(500000, HORIZON);
    s.schedule(501000, HORIZON);

    s.restart(505000);
    var offsets = s.schedule(505000, HORIZON);
    Test.assertEqualMessage(offsets[0], 0, "restart should place the next beat at offset 0");
    return true;
}

//! Coming back after a long absence -- paused, or the clock wrapped -- must
//! re-base rather than grind through thousands of intervals or emit garbage.
(:test)
function testResyncAfterLongAbsence(logger as Logger) as Boolean {
    var s = new BeatScheduler(170, 1);
    s.restart(500000);
    s.schedule(500000, HORIZON);

    // Ten minutes later.
    var offsets = s.schedule(1100000, HORIZON);
    Test.assertMessage(offsets.size() > 0, "no beats after a long gap");
    Test.assertEqualMessage(offsets[0], 0, "should re-base to now after a long gap");

    // And a clock that went backwards (System.getTimer() wraps).
    var back = s.schedule(1000, HORIZON);
    Test.assertMessage(back.size() > 0, "no beats after the clock wrapped");
    Test.assertEqualMessage(back[0], 0, "should re-base to now after a backwards clock");
    return true;
}
