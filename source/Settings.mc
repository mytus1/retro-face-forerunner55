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
//   +- Colours       -> nine parts -> list of the 8 colours
//   +- Data fields   -> four positions -> list of field types
//   +- Outer ring    -> list of gauges
//   +- Bottom bar    -> list of gauges
//   +- Seconds tick  (on/off)
// -------------------------------------------------------------------------

// Names shown in the lists.  The order must match the numbers in settings.xml.
const THEME_NAMES = [
    Rez.Strings.ThemeCustom,
    Rez.Strings.ThemeAmber,
    Rez.Strings.ThemeIce,
    Rez.Strings.ThemePhosphor,
    Rez.Strings.ThemeRedline,
    Rez.Strings.ThemeSynthwave,
    Rez.Strings.ThemeMono,
    Rez.Strings.ThemeDaylight,
    Rez.Strings.ThemeBlueprint,
    Rez.Strings.ThemeSodium
] as Array<ResourceId>;

const COLOR_NAMES = [
    Rez.Strings.Black,
    Rez.Strings.White,
    Rez.Strings.Red,
    Rez.Strings.Yellow,
    Rez.Strings.Green,
    Rez.Strings.Cyan,
    Rez.Strings.Blue,
    Rez.Strings.Magenta
] as Array<ResourceId>;

const PART_NAMES = [
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

const FIELD_KEYS = ["FieldTopLeft", "FieldTopRight", "FieldBottomLeft", "FieldBottomRight"] as Array<String>;

const SLOT_NAMES = [
    Rez.Strings.FieldTopLeft,
    Rez.Strings.FieldTopRight,
    Rez.Strings.FieldBottomLeft,
    Rez.Strings.FieldBottomRight
] as Array<ResourceId>;

const FIELD_NAMES = [
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
    Rez.Strings.FieldRecovery
] as Array<ResourceId>;

const GAUGE_NAMES = [
    Rez.Strings.GaugeOff,
    Rez.Strings.GaugeSteps,
    Rez.Strings.GaugeBattery,
    Rez.Strings.GaugeActive
] as Array<ResourceId>;

// The "Theme" row of the top-level menu, kept so its sub-label can be switched
// to "Custom" when a colour is edited further down.
var gThemeItem as WatchUi.MenuItem? = null;

//! Look up a name, falling back to the first entry for out-of-range values.
function nameAt(names as Array<ResourceId>, index as Number) as ResourceId {
    return names[(index >= 0 && index < names.size()) ? index : 0];
}

//! The top-level menu.
class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({ :title => Rez.Strings.AppName });
        gThemeItem = new WatchUi.MenuItem(Rez.Strings.ThemeTitle, nameAt(THEME_NAMES, Config.theme()), :theme, null);
        addItem(gThemeItem as WatchUi.MenuItem);
        addItem(new WatchUi.MenuItem(Rez.Strings.ColorsTitle, null, :colors, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.FieldsTitle, null, :fields, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.RingTitle, nameAt(GAUGE_NAMES, Config.getNumber("RingMode", 1)), :ring, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.BarTitle, nameAt(GAUGE_NAMES, Config.getNumber("BarMode", 2)), :bar, null));
        addItem(new WatchUi.ToggleMenuItem(Rez.Strings.SecondsTitle, null, :seconds, Config.getBool("ShowSeconds", true), null));
    }
}

//! Handles the top-level menu.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :theme) {
            pushChoice(Rez.Strings.ThemeTitle, THEME_NAMES, Config.theme(), new ChoiceDelegate("Theme", -1, THEME_NAMES, item));
        } else if (id == :ring) {
            pushChoice(Rez.Strings.RingTitle, GAUGE_NAMES, Config.getNumber("RingMode", 1), new ChoiceDelegate("RingMode", -1, GAUGE_NAMES, item));
        } else if (id == :bar) {
            pushChoice(Rez.Strings.BarTitle, GAUGE_NAMES, Config.getNumber("BarMode", 2), new ChoiceDelegate("BarMode", -1, GAUGE_NAMES, item));
        } else if (id == :seconds) {
            Config.setValue("ShowSeconds", (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :colors) {
            var menu = new WatchUi.Menu2({ :title => Rez.Strings.ColorsTitle });
            for (var part = 0; part < PART_NAMES.size(); part++) {
                menu.addItem(new WatchUi.MenuItem(PART_NAMES[part], nameAt(COLOR_NAMES, Config.colorIndex(part)), part, null));
            }
            WatchUi.pushView(menu, new GroupDelegate(true), WatchUi.SLIDE_LEFT);
        } else if (id == :fields) {
            var menu = new WatchUi.Menu2({ :title => Rez.Strings.FieldsMenuTitle });
            for (var slot = 0; slot < SLOT_NAMES.size(); slot++) {
                menu.addItem(new WatchUi.MenuItem(SLOT_NAMES[slot], nameAt(FIELD_NAMES, Config.getNumber(FIELD_KEYS[slot], 0)), slot, null));
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
            pushChoice(Rez.Strings.ColorTitle, COLOR_NAMES, Config.colorIndex(row), new ChoiceDelegate("", row, COLOR_NAMES, item));
        } else {
            pushChoice(Rez.Strings.FieldTitle, FIELD_NAMES, Config.getNumber(FIELD_KEYS[row], 0), new ChoiceDelegate(FIELD_KEYS[row], -1, FIELD_NAMES, item));
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
