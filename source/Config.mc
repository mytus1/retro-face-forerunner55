import Toybox.Application;
import Toybox.Lang;

//! Colours, themes and stored settings.
//!
//! If you want to change what a built-in theme looks like, add a theme of your
//! own, or change the defaults, this is the only source file you need to edit.
module Config {

    // ---------------------------------------------------------------------
    // The Forerunner 55 screen can show exactly these eight colours.
    // Everything on the face is drawn with one of them.
    // ---------------------------------------------------------------------
    //   K black, W white, R red, Y yellow, G green, C cyan, B blue, M magenta
    //
    // A colour's position in LETTERS is its number in the settings
    // (0 = black ... 7 = magenta) and its position in PALETTE.
    const LETTERS = "KWRYGCBM";
    const W = 1; // white, the fallback for anything unreadable

    const PALETTE = [0x000000, 0xFFFFFF, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF] as Array<Number>;

    // ---------------------------------------------------------------------
    // The parts of the face that can be coloured independently.
    // ---------------------------------------------------------------------
    enum {
        PART_BACKGROUND,
        PART_HOURS,
        PART_MINUTES,
        PART_DATE,
        PART_VALUES,
        PART_LABELS,
        PART_LINES,
        PART_RING,
        PART_ACCENT,
        PART_COUNT
    }

    //! Property that stores each part's custom colour (see resources/settings/settings.xml).
    const COLOR_KEYS = [
        "ColorBackground",
        "ColorHours",
        "ColorMinutes",
        "ColorDate",
        "ColorValues",
        "ColorLabels",
        "ColorLines",
        "ColorRing",
        "ColorAccent"
    ] as Array<String>;

    // ---------------------------------------------------------------------
    // Built-in themes.  One row per theme, one letter (see above) per part:
    //
    //   background, hours, minutes, date, values, labels, lines, ring, accent
    //
    // e.g. "KWWYWYYWY" is a black background, white hours and minutes, a
    // yellow date, and so on.
    //
    // Row 0 is a placeholder for "Custom", which reads the nine Color*
    // properties instead.  To add a theme: add a row here, then add its name
    // to strings.xml, settings.xml and themeNames() in Settings.mc.
    // ---------------------------------------------------------------------
    const THEMES = [
        "KWWYWYYWY", // 0 Custom (placeholder, also the fallback)
        "KWWYWYYWY", // 1 Amber
        "KWWCWCCWC", // 2 Ice
        "KGGGGGGGW", // 3 Phosphor
        "KWWRWRRWR", // 4 Redline
        "KMCYWMCCY", // 5 Synthwave
        "KWWWWWWWW", // 6 Mono
        "WKKRKRKKR", // 7 Daylight
        "BWWYWCCWY", // 8 Blueprint
        "KYYWWYYYW", // 9 Sodium
        "WKKKKKKKK"  // 10 Inverted mono
    ] as Array<String>;

    //! Set whenever a setting is stored from the on-watch menu, so the face
    //! only re-reads its settings when something actually changed.
    var changed as Boolean = false;

    // ---------------------------------------------------------------------
    // Reading and writing settings
    // ---------------------------------------------------------------------

    //! Read a numeric setting, tolerating missing or oddly-typed values.
    function getNumber(key as String, fallback as Number) as Number {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
        } catch (e) {
            return fallback;
        }
        if (value instanceof Number) {
            return value;
        }
        if (value instanceof Boolean) {
            return value ? 1 : 0;
        }
        if (value instanceof String || value instanceof Float) {
            var n = value.toNumber();
            return (n != null) ? n : fallback;
        }
        return fallback;
    }

    //! Read an on/off setting.
    function getBool(key as String, fallback as Boolean) as Boolean {
        var value = null;
        try {
            value = Application.Properties.getValue(key);
        } catch (e) {
            return fallback;
        }
        if (value instanceof Boolean) {
            return value;
        }
        if (value instanceof Number) {
            return value != 0;
        }
        return fallback;
    }

    //! Store a setting.
    function setValue(key as String, value as Number or Boolean) as Void {
        try {
            Application.Properties.setValue(key, value);
        } catch (e) {
            // An unknown key should never stop the face from drawing.
        }
        changed = true;
    }

    //! The colour number (0-7) a built-in theme uses for one part.
    function themeColor(t as Number, part as Number) as Number {
        var letter = THEMES[t].substring(part, part + 1);
        var index = (letter != null) ? LETTERS.find(letter) : null;
        return (index != null) ? index : W;
    }

    //! The index of the theme in use (0 = Custom).
    function theme() as Number {
        var t = getNumber("Theme", 1);
        return (t >= 0 && t < THEMES.size()) ? t : 1;
    }

    //! The palette index (0-7) currently used for one part of the face.
    function colorIndex(part as Number) as Number {
        return colorIn(theme(), part);
    }

    //! The palette index for one part under theme t.
    function colorIn(t as Number, part as Number) as Number {
        var index = themeColor(t, part);
        if (t == 0) {
            index = getNumber(COLOR_KEYS[part], index);
        }
        return (index >= 0 && index < PALETTE.size()) ? index : W;
    }

    //! The nine colours to draw with, as RGB values, indexed by PART_*.
    function colors() as Array<Number> {
        var t = theme();
        var out = new [PART_COUNT] as Array<Number>;
        for (var part = 0; part < PART_COUNT; part++) {
            out[part] = PALETTE[colorIn(t, part)];
        }
        return out;
    }

    //! Change one part's colour from the on-watch menu.
    //! If a built-in theme is active its colours are copied into the custom
    //! slots first, so you tweak what you are looking at rather than start over.
    function setCustomColor(part as Number, index as Number) as Void {
        var t = theme();
        if (t != 0) {
            for (var i = 0; i < PART_COUNT; i++) {
                setValue(COLOR_KEYS[i], themeColor(t, i));
            }
            setValue("Theme", 0);
        }
        setValue(COLOR_KEYS[part], index);
    }
}
