import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WorkoutMetronomeApp extends Application.AppBase {

    private var _view as MetronomeView?;

    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new MetronomeView();
        return [_view];
    }

    //! Last chance to silence the beat. The firmware loops independently of
    //! this app, so without this the watch can be left beeping for the rest of
    //! the arming window after the app goes away.
    public function onStop(state as Lang.Dictionary?) as Void {
        if (_view != null) {
            _view.shutdown();
        }
    }

    //! Fired when the phone pushes edited settings. Data field settings can
    //! only be changed from Garmin Connect Mobile, never on the watch, so this
    //! is the only path by which the target cadence can change -- and it can
    //! arrive mid activity, so the view has to pick it up live.
    public function onSettingsChanged() as Void {
        if (_view != null) {
            _view.reloadSettings();
        }
    }
}
