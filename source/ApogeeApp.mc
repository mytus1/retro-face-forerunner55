import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Entry point.  The watch creates one of these when the face is selected.
class ApogeeApp extends Application.AppBase {

    private var _view as ApogeeView?;

    function initialize() {
        AppBase.initialize();
    }

    //! The view that draws the face.
    function getInitialView() {
        _view = new ApogeeView();
        return [_view];
    }

    //! Settings were changed on the phone (Garmin Connect / Connect IQ app).
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    //! The on-watch settings menu (watch face menu > Customize).
    function getSettingsView() {
        return [new SettingsMenu(), new SettingsMenuDelegate()];
    }
}
