import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;

//! Everything that touches Toybox.Attention lives here, behind capability
//! checks, so the rest of the app never has to care what the device supports.
//!
//! The tone is ARMED, not fed: one repeating profile that the firmware loops
//! on its own clock (see Metronome). The vibration cannot work that way --
//! Attention.vibrate has no repeat parameter -- so it is still topped up each
//! wake-up, within a hard element budget.
//!
//! MEASURED ON THE fr165 TARGET (not assumed):
//!   Attention has :playTone      true
//!   Attention has :ToneProfile   true
//!   playTone profile elements    32+ accepted
//!   playTone :repeatCount        accepted up to at least 10000
//!   vibrate profile elements     8 maximum
//!   vibrate with 10 elements     UNCATCHABLE "Too Many Arguments Error" that
//!                                takes the data field down. try/catch does
//!                                NOT save you. Never exceed 8.
class Cue {

    // Beat character. Short and high cuts through road noise and wind better
    // than a long low tone, and a short beat leaves a clean gap at high spm.
    const BEAT_FREQ_HZ = 2000;
    const BEAT_MS = 40;
    const BEAT_VIBE_DUTY = 65;

    // Vibration is topped up once per wake-up and must never exceed this.
    const VIBE_MAX_ELEMENTS = 8;
    const VIBE_HORIZON_MS = 1000;

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

    public function beatMs() as Number { return BEAT_MS; }
    public function vibeHorizonMs() as Number { return VIBE_HORIZON_MS; }

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

    //! Hand the firmware one beat period and let it loop.
    //!
    //! The profile is exactly `intervalMs` long:
    //!     [rest leadInMs] [beat BEAT_MS] [rest intervalMs - BEAT_MS - leadInMs]
    //! so every repetition places a beat one interval after the last. Putting
    //! the lead-in INSIDE the repeating profile, and shortening the tail to
    //! match, is what lets Metronome re-arm without shifting the phase.
    //!
    //! @return true if the firmware accepted it
    public function armBeat(intervalMs as Number, leadInMs as Number,
                            repeats as Number, config as Config) as Boolean {
        if (!config.wantsTone() || !_hasToneProfile || !tonesAudible()) {
            return false;
        }

        var tail = intervalMs - BEAT_MS - leadInMs;
        if (tail < 0) {
            // Metronome should never ask for this; refuse rather than emit a
            // profile whose length is not exactly one interval.
            return false;
        }

        var profile = [];
        if (leadInMs > 0) {
            profile.add(new Attention.ToneProfile(0, leadInMs));
        }
        profile.add(new Attention.ToneProfile(BEAT_FREQ_HZ, BEAT_MS));
        if (tail > 0) {
            profile.add(new Attention.ToneProfile(0, tail));
        }

        try {
            Attention.playTone({ :toneProfile => profile, :repeatCount => repeats });
            return true;
        } catch (e) {
            return false;
        }
    }

    //! Replace the looping profile with a moment of silence, which is the only
    //! way to stop it. Used on pause and on stop -- otherwise the firmware
    //! would happily keep beating for the rest of the arming window.
    public function silenceTone(config as Config) as Void {
        if (!_hasTone || !_hasToneProfile) { return; }
        try {
            Attention.playTone({
                :toneProfile => [new Attention.ToneProfile(0, 1)],
                :repeatCount => 1
            });
        } catch (e) {
            // Nothing useful to do; the arming will expire on its own.
        }
    }

    //! Top up the vibration for the next window. Unlike the tone this must be
    //! re-issued every wake-up, because Attention.vibrate has no repeat.
    //!
    //! HARD truncated to VIBE_MAX_ELEMENTS: going over does not throw
    //! something catchable, it kills the data field.
    //!
    //! Forerunners flatten pattern intensity, so the duty cycle mostly only
    //! decides "buzzing or not" -- the DURATIONS carry the rhythm.
    public function pulseVibe(offsetsMs as Array<Number>, config as Config) as Void {
        if (!config.wantsVibe() || !vibeEnabled() || offsetsMs.size() == 0) {
            return;
        }

        var profile = [];
        var cursor = 0;

        for (var i = 0; i < offsetsMs.size(); i++) {
            if (profile.size() + 2 > VIBE_MAX_ELEMENTS) { break; }

            var at = offsetsMs[i];
            if (at > cursor) {
                profile.add(new Attention.VibeProfile(0, at - cursor));
                cursor = at;
            }
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

    //! The out of range alert. Interrupts the looping beat -- there is only
    //! one buzzer -- and Metronome re-arms afterwards.
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

    private function safePlayTone(tone as Attention.Tone) as Void {
        try {
            Attention.playTone(tone);
        } catch (e) {
            // Ignore.
        }
    }
}
