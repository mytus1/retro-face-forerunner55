import Toybox.Lang;
import Toybox.WatchUi;

// -------------------------------------------------------------------------
// On-watch settings menu.
//
// Offers the same options as the phone settings screen, so the face can be
// configured even when it was copied to the watch over USB (side-loaded
// faces do not get a settings screen in Garmin Connect).
//
//   Apogee
//   +- Theme         -> list of themes
//   +- Numerals      -> VHS or Squared
//   +- Colours       -> nine parts -> list of the 8 colours
//   +- Data fields   -> six positions -> list of field types
//   +- Outer ring    -> list of gauges
//   +- Bottom bar    -> heart trace, status icons or a gauge
//   +- Seconds tick  (on/off)
//   +- Scanlines     (on/off)
// -------------------------------------------------------------------------

// Names shown in the lists.  The order must match the numbers in settings.xml.
// They are functions rather than constants so the lists only take up memory
// while the menu is open, not all the time the face is running.
function themeNames() as Array<ResourceId> {
    return [
        Rez.Strings.ThemeCustom,
        Rez.Strings.ThemeAmber,
        Rez.Strings.ThemeIce,
        Rez.Strings.ThemePhosphor,
        Rez.Strings.ThemeRedline,
        Rez.Strings.ThemeSynthwave,
        Rez.Strings.ThemeMono,
        Rez.Strings.ThemeDaylight,
        Rez.Strings.ThemeBlueprint,
        Rez.Strings.ThemeSodium,
        Rez.Strings.ThemeInverse
    ] as Array<ResourceId>;
}

function colorNames() as Array<ResourceId> {
    return [
        Rez.Strings.Black,
        Rez.Strings.White,
        Rez.Strings.Red,
        Rez.Strings.Yellow,
        Rez.Strings.Green,
        Rez.Strings.Cyan,
        Rez.Strings.Blue,
        Rez.Strings.Magenta
    ] as Array<ResourceId>;
}

function partNames() as Array<ResourceId> {
    return [
        Rez.Strings.ColorBackground,
        Rez.Strings.ColorHours,
        Rez.Strings.ColorMinutes,
        Rez.Strings.ColorDate,
        Rez.Strings.ColorValues,
        Rez.Strings.ColorLabels,
        Rez.Strings.ColorLines,
        Rez.Strings.ColorRing,
        Rez.Strings.ColorAccent
    ] as Array<ResourceId>;
}

function styleNames() as Array<ResourceId> {
    return [
        Rez.Strings.StyleVhs,
        Rez.Strings.StyleSquare
    ] as Array<ResourceId>;
}

// The six field slots, in the order ApogeeView draws them.
function fieldKeys() as Array<String> {
    return [
        "FieldTopLeft",
        "FieldTopCenter",
        "FieldTopRight",
        "FieldBottomLeft",
        "FieldBottomCenter",
        "FieldBottomRight"
    ] as Array<String>;
}

function slotNames() as Array<ResourceId> {
    return [
        Rez.Strings.FieldTopLeft,
        Rez.Strings.FieldTopCenter,
        Rez.Strings.FieldTopRight,
        Rez.Strings.FieldBottomLeft,
        Rez.Strings.FieldBottomCenter,
        Rez.Strings.FieldBottomRight
    ] as Array<ResourceId>;
}

function fieldNames() as Array<ResourceId> {
    return [
        Rez.Strings.FieldNone,
        Rez.Strings.FieldSteps,
        Rez.Strings.FieldHeart,
        Rez.Strings.FieldBattery,
        Rez.Strings.FieldDistance,
        Rez.Strings.FieldCalories,
        Rez.Strings.FieldActive,
        Rez.Strings.FieldAlerts,
        Rez.Strings.FieldTemp,
        Rez.Strings.FieldSun,
        Rez.Strings.FieldRecovery,
        Rez.Strings.FieldRain,
        Rez.Strings.FieldWind,
        Rez.Strings.FieldVo2,
        Rez.Strings.FieldRestingHr
    ] as Array<ResourceId>;
}

function gaugeNames() as Array<ResourceId> {
    return [
        Rez.Strings.GaugeOff,
        Rez.Strings.GaugeSteps,
        Rez.Strings.GaugeBattery,
        Rez.Strings.GaugeActive
    ] as Array<ResourceId>;
}

// The "Theme" row of the top-level menu, kept so its sub-label can be switched
// to "Custom" when a colour is edited further down.
var gThemeItem as WatchUi.MenuItem? = null;

// The bottom bar has two extra choices on top of the gauges.
function barNames() as Array<ResourceId> {
    return [
        Rez.Strings.GaugeOff,
        Rez.Strings.GaugeSteps,
        Rez.Strings.GaugeBattery,
        Rez.Strings.GaugeActive,
        Rez.Strings.BarHeartTrace,
        Rez.Strings.BarStatus
    ] as Array<ResourceId>;
}

//! Look up a name, falling back to the first entry for out-of-range values.
function nameAt(names as Array<ResourceId>, index as Number) as ResourceId {
    return names[(index >= 0 && index < names.size()) ? index : 0];
}

//! The top-level menu.
class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => Rez.Strings.AppName });
        gThemeItem = new WatchUi.MenuItem(Rez.Strings.ThemeTitle, nameAt(themeNames(), Config.theme()), :theme, null);
        addItem(gThemeItem as WatchUi.MenuItem);
        addItem(new WatchUi.MenuItem(Rez.Strings.StyleTitle, nameAt(styleNames(), Config.getNumber("NumeralStyle", 0)), :style, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.ColorsTitle, null, :colors, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.FieldsTitle, null, :fields, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.RingTitle, nameAt(gaugeNames(), Config.getNumber("RingMode", 1)), :ring, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.BarTitle, nameAt(barNames(), Config.getNumber("BarMode", 4)), :bar, null));
        addItem(new WatchUi.ToggleMenuItem(Rez.Strings.SecondsTitle, null, :seconds, Config.getBool("ShowSeconds", true), null));
        addItem(new WatchUi.ToggleMenuItem(Rez.Strings.ScanTitle, null, :scan, Config.getBool("Scanlines", false), null));
    }
}

//! Handles the top-level menu.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    //! Leaving the menu: let go of the Theme row so it can be freed.
    function onBack() as Void {
        gThemeItem = null;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :theme) {
            var names = themeNames();
            pushChoice(Rez.Strings.ThemeTitle, names, Config.theme(), new ChoiceDelegate("Theme", -1, names, item));
        } else if (id == :style) {
            var names = styleNames();
            pushChoice(Rez.Strings.StyleTitle, names, Config.getNumber("NumeralStyle", 0), new ChoiceDelegate("NumeralStyle", -1, names, item));
        } else if (id == :ring) {
            var names = gaugeNames();
            pushChoice(Rez.Strings.RingTitle, names, Config.getNumber("RingMode", 1), new ChoiceDelegate("RingMode", -1, names, item));
        } else if (id == :bar) {
            var names = barNames();
            pushChoice(Rez.Strings.BarTitle, names, Config.getNumber("BarMode", 4), new ChoiceDelegate("BarMode", -1, names, item));
        } else if (id == :seconds) {
            Config.setValue("ShowSeconds", (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :scan) {
            Config.setValue("Scanlines", (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :colors) {
            var menu = new WatchUi.Menu2({ :title => Rez.Strings.ColorsTitle });
            var parts = partNames();
            var colors = colorNames();
            for (var part = 0; part < parts.size(); part++) {
                menu.addItem(new WatchUi.MenuItem(parts[part], nameAt(colors, Config.colorIndex(part)), part, null));
            }
            WatchUi.pushView(menu, new GroupDelegate(true), WatchUi.SLIDE_LEFT);
        } else if (id == :fields) {
            var menu = new WatchUi.Menu2({ :title => Rez.Strings.FieldsMenuTitle });
            var slots = slotNames();
            var fields = fieldNames();
            var keys = fieldKeys();
            for (var slot = 0; slot < slots.size(); slot++) {
                menu.addItem(new WatchUi.MenuItem(slots[slot], nameAt(fields, Config.getNumber(keys[slot], 0)), slot, null));
            }
            WatchUi.pushView(menu, new GroupDelegate(false), WatchUi.SLIDE_LEFT);
        }
    }
}

//! Handles the "Colours" and "Data fields" sub-menus: picking a row
//! opens the list of choices for that row.
class GroupDelegate extends WatchUi.Menu2InputDelegate {

    private var _isColors as Boolean;

    function initialize(isColors as Boolean) {
        Menu2InputDelegate.initialize();
        _isColors = isColors;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var row = item.getId() as Number;
        if (_isColors) {
            var names = colorNames();
            pushChoice(Rez.Strings.ColorTitle, names, Config.colorIndex(row), new ChoiceDelegate("", row, names, item));
        } else {
            var names = fieldNames();
            var key = fieldKeys()[row];
            pushChoice(Rez.Strings.FieldTitle, names, Config.getNumber(key, 0), new ChoiceDelegate(key, -1, names, item));
        }
    }
}

//! Show a list to pick one entry from, with the current one highlighted.
function pushChoice(title as ResourceId, names as Array<ResourceId>, current as Number, delegate as ChoiceDelegate) as Void {
    var menu = new WatchUi.Menu2({ :title => title });
    for (var i = 0; i < names.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(names[i], null, i, null));
    }
    if (current >= 0 && current < names.size()) {
        menu.setFocus(current);
    }
    WatchUi.pushView(menu, delegate, WatchUi.SLIDE_LEFT);
}

//! Stores the picked entry and goes back one level.
class ChoiceDelegate extends WatchUi.Menu2InputDelegate {

    private var _key as String;
    private var _part as Number;
    private var _names as Array<ResourceId>;
    private var _parentItem as WatchUi.MenuItem;

    //! key:  property to store the choice in, or
    //! part: Config.PART_* when picking a custom colour (key is then ignored)
    //! parentItem: the menu row that opened this list; its sub-label is updated
    function initialize(key as String, part as Number, names as Array<ResourceId>, parentItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _part = part;
        _names = names;
        _parentItem = parentItem;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var choice = item.getId() as Number;
        if (_part >= 0) {
            Config.setCustomColor(_part, choice);
            if (gThemeItem != null) {
                gThemeItem.setSubLabel(Rez.Strings.ThemeCustom);
            }
        } else {
            Config.setValue(_key, choice);
        }
        _parentItem.setSubLabel(_names[choice]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
