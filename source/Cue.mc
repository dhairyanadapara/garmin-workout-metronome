import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

//! Everything that touches Toybox.Attention lives here, behind capability
//! checks, so the rest of the app never has to care what the device supports.
//!
//! THE CENTRAL TRICK
//! A data field gets one compute() call per second and cannot use a Timer, so
//! it can never "beat" by itself. But Attention.playTone accepts a
//! :toneProfile ARRAY -- a sequence of (frequency, duration) pairs the
//! firmware plays back-to-back on its own clock. So each second we hand the
//! firmware the next second of rhythm in one call, and the beats land
//! sub-second without us being awake for them.
//!
//! Attention.vibrate takes a VibeProfile array the same way, but is capped at
//! VIBE_MAX_ELEMENTS elements -- which is exactly why the scheduling window is
//! one second and not longer.
class Cue {

    // A one second window at 220 spm is 3.7 beats -> 8 elements
    // (beat + gap per beat). That is the vibrate() ceiling, so 1000ms is the
    // largest window we can serve both outputs from. Do not raise this
    // without splitting the tone and vibe windows apart.
    const WINDOW_MS = 1000;
    const VIBE_MAX_ELEMENTS = 8;

    // Beat character. Short and high cuts through road noise and wind better
    // than a long low tone, and a short beat leaves a clean gap at high spm.
    const BEAT_FREQ_HZ = 2000;
    const BEAT_MS = 40;
    const BEAT_VIBE_DUTY = 65;

    // Deviation alert: a rising pair means "speed up", falling means
    // "slow down". Deliberately longer and two-toned so it is never confused
    // with a beat.
    const ALERT_LOW_HZ = 1200;
    const ALERT_HIGH_HZ = 2600;
    const ALERT_MS = 120;
    const ALERT_GAP_MS = 60;
    const ALERT_VIBE_DUTY = 100;
    const ALERT_VIBE_MS = 250;

    private var _hasTone as Boolean = false;
    private var _hasToneProfile as Boolean = false;
    private var _hasVibrate as Boolean = false;

    public function initialize() {
        _hasTone = (Attention has :playTone);
        _hasToneProfile = (Attention has :ToneProfile);
        _hasVibrate = (Attention has :vibrate);
    }

    //! The scheduling window length. Exposed as a method because Monkey C
    //! class consts are not reliably reachable as Cue.WINDOW_MS from outside.
    public function windowMs() as Number { return WINDOW_MS; }

    public function hasTone() as Boolean { return _hasTone; }
    public function hasToneProfile() as Boolean { return _hasToneProfile; }
    public function hasVibrate() as Boolean { return _hasVibrate; }

    //! True when the device can actually make a sound right now -- the user
    //! can mute tones system wide, in which case we must not claim to be
    //! beating audibly.
    public function tonesAudible() as Boolean {
        if (!_hasTone) { return false; }
        var settings = System.getDeviceSettings();
        if (settings has :tonesOn && settings.tonesOn != null) {
            return settings.tonesOn;
        }
        return true;
    }

    public function vibeEnabled() as Boolean {
        if (!_hasVibrate) { return false; }
        var settings = System.getDeviceSettings();
        if (settings has :vibrateOn && settings.vibrateOn != null) {
            return settings.vibrateOn;
        }
        return true;
    }

    //! Queue one window of beats.
    //! @param offsetsMs beat offsets from the window start, ascending
    //! @param config    user cue preferences
    public function playBeats(offsetsMs as Array<Number>, config as Config) as Void {
        if (offsetsMs.size() == 0) { return; }

        if (config.wantsTone() && tonesAudible()) {
            if (_hasToneProfile) {
                queueToneWindow(offsetsMs);
            } else {
                // Device has no ToneProfile support: degrade to a single beep
                // on the first beat of the window. Rhythmically useless as a
                // metronome, but better than silence -- and MetronomeView
                // tells the user their device is in degraded mode.
                safePlayTone(Attention.TONE_KEY);
            }
        }

        if (config.wantsVibe() && vibeEnabled()) {
            queueVibeWindow(offsetsMs);
        }
    }

    //! The out of range alert. Played INSTEAD of that window's beats so the
    //! two cues never overlap and fight for the buzzer.
    public function playDeviation(tooFast as Boolean, config as Config) as Void {
        if (config.wantsTone() && tonesAudible()) {
            if (_hasToneProfile) {
                var first = tooFast ? ALERT_HIGH_HZ : ALERT_LOW_HZ;
                var second = tooFast ? ALERT_LOW_HZ : ALERT_HIGH_HZ;
                try {
                    Attention.playTone({
                        :toneProfile => [
                            new Attention.ToneProfile(first, ALERT_MS),
                            new Attention.ToneProfile(0, ALERT_GAP_MS),
                            new Attention.ToneProfile(second, ALERT_MS)
                        ]
                    });
                } catch (e) {
                    safePlayTone(Attention.TONE_ALERT_HI);
                }
            } else {
                safePlayTone(Attention.TONE_ALERT_HI);
            }
        }

        if (config.wantsVibe() && vibeEnabled()) {
            try {
                Attention.vibrate([
                    new Attention.VibeProfile(ALERT_VIBE_DUTY, ALERT_VIBE_MS)
                ]);
            } catch (e) {
                // Never let a cue failure end the run.
            }
        }
    }

    //! Build [rest, beat, rest, beat, ...] covering the whole window and hand
    //! it to the firmware in one call.
    private function queueToneWindow(offsetsMs as Array<Number>) as Void {
        var profile = [];
        var cursor = 0;

        for (var i = 0; i < offsetsMs.size(); i++) {
            var at = offsetsMs[i];

            // Silence up to this beat. A zero frequency element is the
            // documented way to express a rest inside a tone profile.
            if (at > cursor) {
                profile.add(new Attention.ToneProfile(0, at - cursor));
                cursor = at;
            }

            // Deliberately NOT clamped to WINDOW_MS. A beat landing in the
            // last few ms of the window would be truncated to an inaudible
            // click, which is a far worse artefact than letting the profile
            // overrun the window by up to BEAT_MS. The overrun is harmless:
            // the next window is queued a full second later, long after this
            // tail has finished.
            profile.add(new Attention.ToneProfile(BEAT_FREQ_HZ, BEAT_MS));
            cursor = at + BEAT_MS;
        }

        if (profile.size() == 0) { return; }

        try {
            Attention.playTone({ :toneProfile => profile });
        } catch (e) {
            // Some firmware rejects an oversized profile. Drop to a single
            // beep rather than going silent or crashing.
            safePlayTone(Attention.TONE_KEY);
        }
    }

    //! Same idea for the vibration motor, but truncated to VIBE_MAX_ELEMENTS.
    //! Note: Forerunners flatten pattern intensity, so the duty cycle mostly
    //! only decides "buzzing or not" -- the DURATIONS carry the rhythm.
    private function queueVibeWindow(offsetsMs as Array<Number>) as Void {
        var profile = [];
        var cursor = 0;

        for (var i = 0; i < offsetsMs.size(); i++) {
            if (profile.size() + 2 > VIBE_MAX_ELEMENTS) { break; }

            var at = offsetsMs[i];
            if (at > cursor) {
                profile.add(new Attention.VibeProfile(0, at - cursor));
                cursor = at;
            }

            // Full-length buzz for the same reason as the tone above.
            profile.add(new Attention.VibeProfile(BEAT_VIBE_DUTY, BEAT_MS));
            cursor = at + BEAT_MS;
        }

        if (profile.size() == 0) { return; }

        try {
            Attention.vibrate(profile);
        } catch (e) {
            // A missed buzz is not worth ending the activity for.
        }
    }

    private function safePlayTone(tone as Number) as Void {
        try {
            Attention.playTone(tone);
        } catch (e) {
            // Ignore.
        }
    }
}
