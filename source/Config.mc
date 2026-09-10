import Toybox.Application;
import Toybox.Lang;

// Cue output modes -- must match the values in resources/settings/settings.xml
// (Monkey C enums live at file scope, not inside a class body.)
enum CueMode {
    CUE_TONE = 0,
    CUE_VIBE = 1,
    CUE_BOTH = 2
}

//! Typed, crash-proof access to the app settings the user edits in Garmin
//! Connect Mobile. Every read is defended: a property can be missing on a
//! fresh install, or the wrong type if a settings.xml key was renamed between
//! versions, and either would otherwise throw inside compute() and kill the
//! data field mid-run.
class Config {

    public var targetSpm as Number = 170;
    public var stepsPerBeat as Number = 1;
    public var cueMode as Number = CUE_BOTH;

    public var deviationEnabled as Boolean = true;
    public var deviationPercent as Number = 5;
    public var deviationCooldownSec as Number = 10;
    public var deviationConfirmTicks as Number = 3;

    public function initialize() {
        load();
    }

    //! Re-read every property. Called on startup and from
    //! AppBase.onSettingsChanged() when the phone pushes new settings.
    public function load() as Void {
        targetSpm            = numberOr("targetSpm", 170, 100, 220);
        stepsPerBeat         = numberOr("stepsPerBeat", 1, 1, 4);
        cueMode              = numberOr("cueMode", CUE_BOTH, 0, 2);
        deviationEnabled     = booleanOr("deviationEnabled", true);
        deviationPercent     = numberOr("deviationPercent", 5, 1, 30);
        deviationCooldownSec = numberOr("deviationCooldownSec", 10, 3, 60);
        deviationConfirmTicks= numberOr("deviationConfirmTicks", 3, 1, 10);
    }

    public function wantsTone() as Boolean {
        return cueMode == CUE_TONE || cueMode == CUE_BOTH;
    }

    public function wantsVibe() as Boolean {
        return cueMode == CUE_VIBE || cueMode == CUE_BOTH;
    }

    private function numberOr(key as String, fallback as Number, min as Number, max as Number) as Number {
        var raw = null;
        try {
            raw = Application.Properties.getValue(key);
        } catch (e) {
            return fallback;
        }
        if (!(raw instanceof Lang.Number)) {
            // A Float or String can arrive here if the user typed into a
            // number field oddly, or after a settings.xml type change.
            if (raw instanceof Lang.Float || raw instanceof Lang.Double) {
                raw = (raw as Lang.Float).toNumber();
            } else if (raw instanceof Lang.String) {
                raw = (raw as Lang.String).toNumber();
            } else {
                return fallback;
            }
        }
        if (raw == null) { return fallback; }
        var value = raw as Number;
        if (value < min) { return min; }
        if (value > max) { return max; }
        return value;
    }

    private function booleanOr(key as String, fallback as Boolean) as Boolean {
        try {
            var raw = Application.Properties.getValue(key);
            if (raw instanceof Lang.Boolean) {
                return raw as Boolean;
            }
        } catch (e) {
            return fallback;
        }
        return fallback;
    }
}
