import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! PHASE 1 CAPABILITY SPIKE -- throwaway. Not for the store.
//!
//! The whole product rests on one unverified assumption: that a Forerunner 165
//! actually plays a queued multi-element tone profile from inside a data
//! field, evenly, once per second. This spike answers that on real hardware
//! before any of the real app gets built on top of it.
//!
//! HOW TO READ THE RESULT
//! The field shows the capability flags and a tick counter. What matters is
//! what you HEAR:
//!   - 3 evenly spaced beeps every second      -> profile queuing works. Ship it.
//!   - 1 beep per second                       -> each playTone cancels the last.
//!                                                Tone mode is dead; go vibe-only.
//!   - beeps but uneven / stuttering            -> works but needs a shorter
//!                                                window or fewer elements.
//!   - nothing                                  -> check tonesOn on screen first.
//!
//! Also cycle to another data page and confirm the beeps CONTINUE. If they
//! stop, compute() is not running off-screen and the entire approach is void.
class SpikeApp extends Application.AppBase {
    private var _view as SpikeField?;
    public function initialize() { AppBase.initialize(); }
    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new SpikeField();
        return [_view];
    }
}

class SpikeField extends WatchUi.DataField {

    private var _ticks as Number = 0;
    private var _hasTone as Boolean = false;
    private var _hasProfile as Boolean = false;
    private var _hasVibe as Boolean = false;
    private var _tonesOn as Boolean = false;
    private var _vibeOn as Boolean = false;
    private var _lastError as String = "-";

    // Alternate tone-only and vibe-only seconds so the two outputs can be
    // judged separately by ear/wrist instead of masking each other.
    private var _phase as Number = 0;

    public function initialize() {
        DataField.initialize();

        _hasTone = (Attention has :playTone);
        _hasProfile = (Attention has :ToneProfile);
        _hasVibe = (Attention has :vibrate);

        var s = System.getDeviceSettings();
        _tonesOn = (s has :tonesOn && s.tonesOn != null) ? s.tonesOn : false;
        _vibeOn = (s has :vibrateOn && s.vibrateOn != null) ? s.vibrateOn : false;
    }

    public function compute(info as Activity.Info) as Void {
        _ticks++;

        // Only cue while the timer is genuinely running, so the spike does not
        // beep at you on the pre-start screen.
        if (!(info has :timerState) || info.timerState != Activity.TIMER_STATE_ON) {
            return;
        }

        _phase = (_phase + 1) % 2;

        if (_phase == 0) {
            tryToneWindow();
        } else {
            tryVibeWindow();
        }
    }

    //! Three beeps at 0ms, 300ms, 600ms in one queued call.
    private function tryToneWindow() as Void {
        if (!_hasTone) { _lastError = "no playTone"; return; }

        if (!_hasProfile) {
            // Fallback path: what a device without ToneProfile can manage.
            try { Attention.playTone(Attention.TONE_KEY); }
            catch (e) { _lastError = "tone threw"; }
            return;
        }

        try {
            Attention.playTone({
                :toneProfile => [
                    new Attention.ToneProfile(2000, 40),
                    new Attention.ToneProfile(0, 260),
                    new Attention.ToneProfile(2000, 40),
                    new Attention.ToneProfile(0, 260),
                    new Attention.ToneProfile(2000, 40)
                ]
            });
            _lastError = "ok";
        } catch (e) {
            _lastError = "profile threw";
            try { Attention.playTone(Attention.TONE_KEY); } catch (e2) {}
        }
    }

    //! Three buzzes on the same 300ms grid -- 5 of the 8 allowed elements.
    private function tryVibeWindow() as Void {
        if (!_hasVibe) { _lastError = "no vibrate"; return; }
        try {
            Attention.vibrate([
                new Attention.VibeProfile(65, 40),
                new Attention.VibeProfile(0, 260),
                new Attention.VibeProfile(65, 40),
                new Attention.VibeProfile(0, 260),
                new Attention.VibeProfile(65, 40)
            ]);
        } catch (e) {
            _lastError = "vibe threw";
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
        var y = 1;

        dc.drawText(cx, y, f, "t" + _hasTone.toString() + " p" + _hasProfile.toString()
                    + " v" + _hasVibe.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, "snd" + _tonesOn.toString() + " vib" + _vibeOn.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, "tick " + _ticks.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.drawText(cx, y, f, _lastError, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
