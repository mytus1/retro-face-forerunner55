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
    const K = 0; // Black
    const W = 1; // White
    const R = 2; // Red
    const Y = 3; // Yellow
    const G = 4; // Green
    const C = 5; // Cyan
    const B = 6; // Blue
    const M = 7; // Magenta

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
    // Built-in themes.  One row per theme, one colour per part:
    //
    //   background, hours, minutes, date, values, labels, lines, ring, accent
    //
    // Row 0 is a placeholder for "Custom", which reads the nine Color*
    // properties instead.  To add a theme: add a row here, then add its name
    // to strings.xml, settings.xml and THEME_NAMES in Settings.mc.
    // ---------------------------------------------------------------------
    const THEMES = [
        [K, W, W, Y, W, Y, Y, W, Y], // 0 Custom (placeholder, also the fallback)
        [K, W, W, Y, W, Y, Y, W, Y], // 1 Amber
        [K, W, W, C, W, C, C, W, C], // 2 Ice
        [K, G, G, G, G, G, G, G, W], // 3 Phosphor
        [K, W, W, R, W, R, R, W, R], // 4 Redline
        [K, M, C, Y, W, M, C, C, Y], // 5 Synthwave
        [K, W, W, W, W, W, W, W, W], // 6 Mono
        [W, K, K, R, K, R, K, K, R], // 7 Daylight
        [B, W, W, Y, W, C, C, W, Y], // 8 Blueprint
        [K, Y, Y, W, W, Y, Y, Y, W], // 9 Sodium
        [W, K, K, K, K, K, K, K, K]  // 10 Inverted mono
    ] as Array<Array<Number> >;

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
    }

    //! The index of the theme in use (0 = Custom).
    function theme() as Number {
        var t = getNumber("Theme", 1);
        return (t >= 0 && t < THEMES.size()) ? t : 1;
    }

    //! The palette index (0-7) currently used for one part of the face.
    function colorIndex(part as Number) as Number {
        var t = theme();
        var index = THEMES[t][part];
        if (t == 0) {
            index = getNumber(COLOR_KEYS[part], index);
        }
        return (index >= 0 && index < PALETTE.size()) ? index : W;
    }

    //! The nine colours to draw with, as RGB values, indexed by PART_*.
    function colors() as Array<Number> {
        var out = new [PART_COUNT] as Array<Number>;
        for (var part = 0; part < PART_COUNT; part++) {
            out[part] = PALETTE[colorIndex(part)];
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
                setValue(COLOR_KEYS[i], THEMES[t][i]);
            }
            setValue("Theme", 0);
        }
        setValue(COLOR_KEYS[part], index);
    }
}
