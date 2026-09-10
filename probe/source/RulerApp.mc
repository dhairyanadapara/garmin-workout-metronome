import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! TIMING RULER -- throwaway measurement probe. Not for the store.
//!
//! THE QUESTION
//! The metronome arms the firmware with a repeating profile of
//! [beat 40ms][rest 313ms] = 353ms, expecting 170spm. A recording measured the
//! period as 360ms, i.e. 166.67spm -- a systematic 2% error. 7ms per repetition
//! is being added somewhere, and the most likely cause is the firmware
//! ROUNDING each element's duration UP to some quantum (313 -> 320 would give
//! exactly the 360ms observed).
//!
//! Guessing the quantum and compensating would be exactly the kind of magic
//! number that has already been rejected once. So measure it.
//!
//! THE METHOD
//! One profile containing four beats separated by four DIFFERENT rests, chosen
//! so that each candidate quantum predicts a different set of gaps:
//!
//!   rest    no rounding   quantum 8   quantum 10   quantum 16
//!   300         340          344         340          352
//!   305         345          352         350          352
//!   310         350          352         350          352
//!   315         355          360         360          368
//!
//! Record ~30s, detect onsets, and take the median of every 4th gap. The
//! pattern of the four gaps identifies the quantum outright. Comparing the sum
//! of the four gaps against the profile's nominal 1420ms also reveals any
//! per-repetition overhead that is NOT explained by rounding.
class RulerApp extends Application.AppBase {
    private var _view as RulerField?;
    public function initialize() { AppBase.initialize(); }
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new RulerField();
        return [_view];
    }
}

class RulerField extends WatchUi.DataField {

    // Deliberately all multiples of 8 AND 10 so the beat itself is never the
    // thing being rounded -- only the rests vary.
    const BEAT_MS = 40;
    const BEAT_HZ = 2000;

    const REST_A = 300;
    const REST_B = 305;
    const REST_C = 310;
    const REST_D = 315;

    private var _armed as Boolean = false;
    private var _status as String = "arming";
    private var _ticks as Number = 0;

    public function initialize() {
        DataField.initialize();
    }

    public function compute(info as Activity.Info) as Void {
        _ticks++;
        if (_armed) {
            return;
        }

        if (!(Attention has :playTone) || !(Attention has :ToneProfile)) {
            _status = "no toneProfile";
            return;
        }

        try {
            Attention.playTone({
                :toneProfile => [
                    new Attention.ToneProfile(BEAT_HZ, BEAT_MS),
                    new Attention.ToneProfile(0, REST_A),
                    new Attention.ToneProfile(BEAT_HZ, BEAT_MS),
                    new Attention.ToneProfile(0, REST_B),
                    new Attention.ToneProfile(BEAT_HZ, BEAT_MS),
                    new Attention.ToneProfile(0, REST_C),
                    new Attention.ToneProfile(BEAT_HZ, BEAT_MS),
                    new Attention.ToneProfile(0, REST_D)
                ],
                :repeatCount => 200
            });
            _armed = true;
            _status = "armed";
        } catch (e) {
            _status = "threw";
        }
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(bg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        var cx = dc.getWidth() / 2;
        var f = Graphics.FONT_SYSTEM_XTINY;
        var lh = dc.getFontHeight(f);
        var y = 2;

        dc.drawText(cx, y, f, "TIMING RULER", Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, _status, Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, "rests 300/305/310/315", Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, "tick " + _ticks.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
