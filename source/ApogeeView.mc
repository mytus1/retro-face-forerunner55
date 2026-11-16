import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// -------------------------------------------------------------------------
// Layout, in pixels, for the Forerunner 55's 208 x 208 round screen.
//
//           . ' | ' .            outer ring: 60 ticks, lit ones are a gauge
//         MON 16 NOV             date
//        HEART | STEPS           labels
//          62  | 8421            values
//       ----------------
//          19:53                 time
//       ----------------
//         5.24 | 1840            values
//          KM  | KCAL            labels
//         ||||||||....           bottom bar: a second gauge
//
// Nudge the numbers here to move things around.
// -------------------------------------------------------------------------
const SCREEN_MID = 104;          // x that text is centred on
const RING_MID = 103.5;          // true centre of a 208 px wide circle

const DATE_Y = 18;               // top of the date line

const TOP_LABEL_Y = 31;          // top row: label above value
const TOP_VALUE_Y = 42;
const BOTTOM_VALUE_Y = 146;      // bottom row: value above label
const BOTTOM_LABEL_Y = 171;
const COLUMN_OFFSET = 40;        // field centres are this far left/right of centre

const LINE_TOP_Y = 67;           // the two horizontal dividers
const LINE_BOTTOM_Y = 141;
const LINE_LEFT_X = 24;
const LINE_WIDTH = 161;

const TIME_Y = 74;               // top of the big numerals
const TIME_DIGIT_STEP = 38;      // numeral width (34) + gap (4)
const TIME_COLON_STEP = 13;      // colon width (9) + gap (4)
const TIME_GAP = 4;

const BAR_Y = 184;               // bottom bar: 10 segments
const BAR_X = 80;
const BAR_SEGMENT_W = 3;
const BAR_SEGMENT_H = 6;
const BAR_SEGMENT_STEP = 5;

const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTH_NAMES = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

//! Draws the watch face.
class ApogeeView extends WatchUi.WatchFace {

    private var _fontTime as WatchUi.FontResource;
    private var _fontData as WatchUi.FontResource;
    private var _fontLabel as WatchUi.FontResource;
    private var _fontDate as WatchUi.FontResource;

    // Direction of each of the 60 ring ticks, worked out once.
    private var _tickCos as Array<Float>;
    private var _tickSin as Array<Float>;

    // Settings, cached so they are not re-read on every redraw.
    private var _colors as Array<Number>;
    private var _fields as Array<Number>;
    private var _ringMode as Number = Data.GAUGE_STEPS;
    private var _barMode as Number = Data.GAUGE_BATTERY;
    private var _showSeconds as Boolean = true;

    // True for the few seconds after you raise your wrist, when the watch
    // redraws every second.  The rest of the time it redraws once a minute.
    private var _awake as Boolean = true;

    function initialize() {
        WatchFace.initialize();

        _fontTime = WatchUi.loadResource(Rez.Fonts.FontTime) as WatchUi.FontResource;
        _fontData = WatchUi.loadResource(Rez.Fonts.FontData) as WatchUi.FontResource;
        _fontLabel = WatchUi.loadResource(Rez.Fonts.FontLabel) as WatchUi.FontResource;
        _fontDate = WatchUi.loadResource(Rez.Fonts.FontLabelBold) as WatchUi.FontResource;

        _tickCos = new [60] as Array<Float>;
        _tickSin = new [60] as Array<Float>;
        for (var i = 0; i < 60; i++) {
            var angle = Math.toRadians(i * 6 - 90);
            _tickCos[i] = Math.cos(angle).toFloat();
            _tickSin[i] = Math.sin(angle).toFloat();
        }

        _colors = Config.colors();
        _fields = [0, 0, 0, 0] as Array<Number>;
        loadSettings();
    }

    //! Re-read everything the user can configure.
    function loadSettings() as Void {
        _colors = Config.colors();
        _fields = [
            Config.getNumber("FieldTopLeft", Data.FIELD_HEART),
            Config.getNumber("FieldTopRight", Data.FIELD_STEPS),
            Config.getNumber("FieldBottomLeft", Data.FIELD_DISTANCE),
            Config.getNumber("FieldBottomRight", Data.FIELD_CALORIES)
        ] as Array<Number>;
        _ringMode = Config.getNumber("RingMode", Data.GAUGE_STEPS);
        _barMode = Config.getNumber("BarMode", Data.GAUGE_BATTERY);
        _showSeconds = Config.getBool("ShowSeconds", true);
    }

    //! Called when the face comes back on screen, e.g. after the settings menu.
    function onShow() as Void {
        loadSettings();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    //! Redraw the whole face.
    function onUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        var settings = System.getDeviceSettings();

        dc.setColor(_colors[Config.PART_BACKGROUND], _colors[Config.PART_BACKGROUND]);
        dc.clear();

        drawRing(dc, (_awake && _showSeconds) ? clock.sec : -1);
        drawDate(dc, clock, settings.is24Hour);
        drawFrame(dc);
        drawField(dc, _fields[0], SCREEN_MID - COLUMN_OFFSET, TOP_LABEL_Y, TOP_VALUE_Y);
        drawField(dc, _fields[1], SCREEN_MID + COLUMN_OFFSET, TOP_LABEL_Y, TOP_VALUE_Y);
        drawField(dc, _fields[2], SCREEN_MID - COLUMN_OFFSET, BOTTOM_LABEL_Y, BOTTOM_VALUE_Y);
        drawField(dc, _fields[3], SCREEN_MID + COLUMN_OFFSET, BOTTOM_LABEL_Y, BOTTOM_VALUE_Y);
        drawTime(dc, clock, settings.is24Hour);
        drawBar(dc);
        drawStatus(dc, settings);
    }

    // ---------------------------------------------------------------------
    // Outer ring
    // ---------------------------------------------------------------------

    //! 60 ticks around the edge.  Lit ticks (long, accent colour) show the
    //! ring gauge; the rest are dots with a short dash every five.
    //! second: 0-59 to show the seconds marker, or -1 to hide it.
    private function drawRing(dc as Dc, second as Number) as Void {
        var lit = (Data.gauge(_ringMode) * 60 + 0.5).toNumber();

        dc.setPenWidth(2);
        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lit; i++) {
            drawTick(dc, i, 96.0, 102.5);
        }

        dc.setColor(_colors[Config.PART_RING], Graphics.COLOR_TRANSPARENT);
        for (var i = lit; i < 60; i++) {
            if (i % 5 == 0) {
                drawTick(dc, i, 99.0, 102.5);
            } else {
                dc.fillRectangle(
                    (RING_MID + 101.0 * _tickCos[i]).toNumber(),
                    (RING_MID + 101.0 * _tickSin[i]).toNumber(),
                    2, 2);
            }
        }

        if (second >= 0) {
            dc.setPenWidth(4);
            dc.setColor(_colors[Config.PART_HOURS], Graphics.COLOR_TRANSPARENT);
            drawTick(dc, second, 95.0, 102.5);
        }
        dc.setPenWidth(1);
    }

    //! One radial line of the ring, from radius inner to radius outer.
    private function drawTick(dc as Dc, index as Number, inner as Float, outer as Float) as Void {
        var c = _tickCos[index];
        var s = _tickSin[index];
        dc.drawLine(
            (RING_MID + inner * c + 0.5).toNumber(), (RING_MID + inner * s + 0.5).toNumber(),
            (RING_MID + outer * c + 0.5).toNumber(), (RING_MID + outer * s + 0.5).toNumber());
    }

    // ---------------------------------------------------------------------
    // Date, dividers, data fields
    // ---------------------------------------------------------------------

    //! "MON 16 NOV", plus AM/PM when the watch is set to 12-hour time.
    private function drawDate(dc as Dc, clock as System.ClockTime, is24Hour as Boolean) as Void {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = DAY_NAMES[(today.day_of_week as Number) - 1] + " " + today.day.format("%02d") + " "
            + MONTH_NAMES[(today.month as Number) - 1];
        if (!is24Hour) {
            text += (clock.hour < 12) ? " AM" : " PM";
        }
        dc.setColor(_colors[Config.PART_DATE], Graphics.COLOR_TRANSPARENT);
        dc.drawText(SCREEN_MID, DATE_Y, _fontDate, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! The two horizontal rules and the short vertical ones between fields.
    private function drawFrame(dc as Dc) as Void {
        dc.setColor(_colors[Config.PART_LINES], Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(LINE_LEFT_X, LINE_TOP_Y, LINE_WIDTH, 1);
        dc.fillRectangle(LINE_LEFT_X, LINE_BOTTOM_Y, LINE_WIDTH, 1);
        if (_fields[0] != Data.FIELD_NONE && _fields[1] != Data.FIELD_NONE) {
            dc.fillRectangle(SCREEN_MID, TOP_LABEL_Y, 1, LINE_TOP_Y - TOP_LABEL_Y);
        }
        if (_fields[2] != Data.FIELD_NONE && _fields[3] != Data.FIELD_NONE) {
            dc.fillRectangle(SCREEN_MID, LINE_BOTTOM_Y + 1, 1, BOTTOM_LABEL_Y + 7 - LINE_BOTTOM_Y - 1);
        }
    }

    //! One data field: a small label and a larger value, both centred on x.
    private function drawField(dc as Dc, type as Number, x as Number, labelY as Number, valueY as Number) as Void {
        if (type == Data.FIELD_NONE) {
            return;
        }
        var content = Data.field(type);
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 1, labelY, _fontLabel, content[0], Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(_colors[Config.PART_VALUES], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 1, valueY, _fontData, content[1], Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---------------------------------------------------------------------
    // Time
    // ---------------------------------------------------------------------

    private function drawTime(dc as Dc, clock as System.ClockTime, is24Hour as Boolean) as Void {
        var hour = clock.hour;
        var hours;
        if (is24Hour) {
            hours = hour.format("%02d");
        } else {
            hour = hour % 12;
            hours = ((hour == 0) ? 12 : hour).format("%d");
        }
        var minutes = clock.min.format("%02d");

        // Each numeral sits in a fixed-width cell so the colon never shifts.
        var width = (hours.length() + 2) * TIME_DIGIT_STEP + TIME_COLON_STEP - TIME_GAP;
        var x = SCREEN_MID - width / 2;

        dc.setColor(_colors[Config.PART_HOURS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, TIME_Y, _fontTime, hours, Graphics.TEXT_JUSTIFY_LEFT);
        x += hours.length() * TIME_DIGIT_STEP;

        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, TIME_Y, _fontTime, ":", Graphics.TEXT_JUSTIFY_LEFT);
        x += TIME_COLON_STEP;

        dc.setColor(_colors[Config.PART_MINUTES], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, TIME_Y, _fontTime, minutes, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ---------------------------------------------------------------------
    // Bottom bar and status icons
    // ---------------------------------------------------------------------

    //! Ten-segment level meter.  Empty segments are drawn as short stubs.
    private function drawBar(dc as Dc) as Void {
        if (_barMode == Data.GAUGE_OFF) {
            return;
        }
        var level = Data.gauge(_barMode);
        var full = (level * 10 + 0.99).toNumber();
        var color = _colors[Config.PART_ACCENT];
        // A battery that is nearly flat turns red (unless red would be invisible).
        if (_barMode == Data.GAUGE_BATTERY && level <= 0.15 && _colors[Config.PART_BACKGROUND] != Graphics.COLOR_RED) {
            color = Graphics.COLOR_RED;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 10; i++) {
            var x = BAR_X + i * BAR_SEGMENT_STEP;
            if (i < full) {
                dc.fillRectangle(x, BAR_Y, BAR_SEGMENT_W, BAR_SEGMENT_H);
            } else {
                dc.fillRectangle(x, BAR_Y + BAR_SEGMENT_H - 2, BAR_SEGMENT_W, 2);
            }
        }
    }

    //! Small icons either side of the bar: phone link lost (left) and
    //! unread notifications (right).  Nothing is drawn when all is well.
    private function drawStatus(dc as Dc, settings as System.DeviceSettings) as Void {
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        if (!settings.phoneConnected) {
            dc.drawText(BAR_X - 14, BAR_Y - 1, _fontLabel, "<", Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (settings.notificationCount > 0) {
            dc.drawText(BAR_X + 53, BAR_Y - 1, _fontLabel, ">", Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}
