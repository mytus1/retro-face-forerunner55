import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// -------------------------------------------------------------------------
// Layout, in pixels, for the Forerunner 55's 208 x 208 round screen.
//
//             . ' | ' .              outer ring: 60 ticks, lit ones are a gauge
//            MON 16 NOV              date
//        STEPS |  KM  | KCAL         labels
//         8421 | 6.47 | 1840         values
//       ----------------------
//              19:53                 time
//       ----------------------
//          17° |  62  | 76%          values
//         TEMP | BPM  | BATT         labels
//            ~~^~~~~~~~~             bottom bar: heart-rate trace, status icons or a gauge
//
// Nudge the numbers here to move things around.  The outer columns are hemmed
// in by the round edge: they have room for a five-letter label and a value
// four numerals wide, and not a pixel more.
// -------------------------------------------------------------------------
const SCREEN_MID = 104;          // x that centred text is drawn at
const RING_MID = 103.5;          // true centre of a 208 px wide circle

const DATE_Y = 18;               // top of the date line

const TOP_LABEL_Y = 38;          // top row: label above value
const TOP_VALUE_Y = 49;
const BOTTOM_VALUE_Y = 145;      // bottom row: value above label
const BOTTOM_LABEL_Y = 163;
const LABEL_HEIGHT = 7;
const SIDE_LEFT_X = 51;          // centres of the two outer columns
const SIDE_RIGHT_X = 158;
const DIVIDER_LEFT_X = 76;       // the short vertical rules between columns
const DIVIDER_RIGHT_X = 131;

const LINE_TOP_Y = 68;           // the two horizontal rules
const LINE_BOTTOM_Y = 139;
const LINE_LEFT_X = 24;
const LINE_WIDTH = 160;
const BRACKET = 4;               // length of the turned-in ends of the rules

const TIME_Y = 76;               // top of the big numerals (they are 56 tall)
const TIME_DIGIT_STEP = 38;      // numeral width (32) + gap (6)
const TIME_COLON_STEP = 14;      // colon width (8) + gap (6)
const TIME_GAP = 6;
const TIME_HEIGHT = 56;
const TIME_COLON_W = 8;          // the colon's own width, kept clear of scanlines
const SCANLINE_STEP = 4;         // every 4th pixel row of the time is left dark

const BAR_Y = 184;               // bottom bar: 10 segments
const BAR_X = 80;
const BAR_SEGMENT_W = 3;
const BAR_SEGMENT_H = 6;
const BAR_SEGMENT_STEP = 5;

const ICON_LEFT_X = 64;          // status icons either side of the bar or trace
const ICON_RIGHT_X = 135;

const TRACE_X = 77;              // bottom bar as a heart-rate trace
const TRACE_Y = 177;
const TRACE_W = 54;
const TRACE_H = 12;

const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTH_NAMES = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

//! Numeral styles.  The numbers match settings.xml.
enum {
    STYLE_VHS,
    STYLE_SQUARE
}

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
    private var _style as Number;
    private var _colors as Array<Number>;
    private var _fields as Array<Number>;
    private var _ringMode as Number = Data.GAUGE_STEPS;
    private var _barMode as Number = Data.GAUGE_BATTERY;
    private var _showSeconds as Boolean = true;
    private var _scanlines as Boolean = false;

    // Activity, settings and battery, read once per redraw.  The weather
    // report inside it is only re-read once a minute.
    private var _snap as Data.Snapshot;
    private var _weatherMinute as Number = -1;

    // The heart-rate trace is worked out once a minute, not on every redraw.
    private var _trace as Array<Float>?;
    private var _traceMinute as Number = -1;

    // True for the few seconds after you raise your wrist, when the watch
    // redraws every second.  The rest of the time it redraws once a minute.
    private var _awake as Boolean = true;

    function initialize() {
        WatchFace.initialize();

        _style = Config.getNumber("NumeralStyle", STYLE_VHS);
        _fontTime = loadTimeFont(_style);
        _fontData = loadDataFont(_style);
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
        _fields = [0, 0, 0, 0, 0, 0] as Array<Number>;
        _snap = new Data.Snapshot();
        loadSettings();
    }

    private function loadTimeFont(style as Number) as WatchUi.FontResource {
        return WatchUi.loadResource((style == STYLE_SQUARE) ? Rez.Fonts.FontTimeSquare : Rez.Fonts.FontTimeVhs) as WatchUi.FontResource;
    }

    private function loadDataFont(style as Number) as WatchUi.FontResource {
        return WatchUi.loadResource((style == STYLE_SQUARE) ? Rez.Fonts.FontDataSquare : Rez.Fonts.FontDataVhs) as WatchUi.FontResource;
    }

    //! Re-read everything the user can configure.
    function loadSettings() as Void {
        var style = Config.getNumber("NumeralStyle", STYLE_VHS);
        if (style != _style) {
            _style = style;
            _fontTime = loadTimeFont(style);
            _fontData = loadDataFont(style);
        }
        _colors = Config.colors();
        // Order: top left, top middle, top right, bottom left, bottom middle, bottom right.
        _fields = [
            Config.getNumber("FieldTopLeft", Data.FIELD_STEPS),
            Config.getNumber("FieldTopCenter", Data.FIELD_DISTANCE),
            Config.getNumber("FieldTopRight", Data.FIELD_CALORIES),
            Config.getNumber("FieldBottomLeft", Data.FIELD_TEMP),
            Config.getNumber("FieldBottomCenter", Data.FIELD_HEART),
            Config.getNumber("FieldBottomRight", Data.FIELD_BATTERY)
        ] as Array<Number>;
        _ringMode = Config.getNumber("RingMode", Data.GAUGE_STEPS);
        _barMode = Config.getNumber("BarMode", Data.BAR_HEART_TRACE);
        _traceMinute = -1;
        _weatherMinute = -1;
        _showSeconds = Config.getBool("ShowSeconds", true);
        _scanlines = Config.getBool("Scanlines", false);
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
        _snap.info = ActivityMonitor.getInfo();
        _snap.settings = settings;
        _snap.battery = System.getSystemStats().battery;
        if (clock.min != _weatherMinute) {
            _snap.weather = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            _weatherMinute = clock.min;
        }

        dc.setColor(_colors[Config.PART_BACKGROUND], _colors[Config.PART_BACKGROUND]);
        dc.clear();

        drawRing(dc, (_awake && _showSeconds) ? clock.sec : -1);
        drawDate(dc, clock, settings.is24Hour);
        drawFrame(dc);
        drawRow(dc, 0, TOP_LABEL_Y, TOP_VALUE_Y);
        drawRow(dc, 3, BOTTOM_LABEL_Y, BOTTOM_VALUE_Y);
        drawTime(dc, clock, settings.is24Hour);
        if (_barMode == Data.BAR_HEART_TRACE) {
            drawTrace(dc, clock.min);
            drawStatus(dc, settings);
        } else if (_barMode == Data.BAR_STATUS) {
            drawStatusRow(dc, settings);
        } else {
            drawBar(dc);
            drawStatus(dc, settings);
        }
    }

    // ---------------------------------------------------------------------
    // Outer ring
    // ---------------------------------------------------------------------

    //! 60 positions around the edge.  Lit ticks (long, accent colour) show
    //! the ring gauge; past them only the twelve hour marks are drawn.
    //! second: 0-59 to show the seconds marker, or -1 to hide it.
    private function drawRing(dc as Dc, second as Number) as Void {
        var lit = (Data.gauge(_ringMode, _snap) * 60 + 0.5).toNumber();

        dc.setPenWidth(2);
        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lit; i++) {
            drawTick(dc, i, 96.0, 102.5);
        }

        dc.setColor(_colors[Config.PART_RING], Graphics.COLOR_TRANSPARENT);
        for (var i = lit + (5 - lit % 5) % 5; i < 60; i += 5) {
            drawTick(dc, i, 99.0, 102.5);
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

    //! The two horizontal rules, and a short vertical rule wherever two
    //! neighbouring fields are both in use.
    private function drawFrame(dc as Dc) as Void {
        dc.setColor(_colors[Config.PART_LINES], Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(LINE_LEFT_X, LINE_TOP_Y, LINE_WIDTH, 1);
        dc.fillRectangle(LINE_LEFT_X, LINE_BOTTOM_Y, LINE_WIDTH, 1);

        // Corner brackets: the rules turn in at each end, framing the time
        // like the edges of a viewfinder.
        var right = LINE_LEFT_X + LINE_WIDTH - 1;
        dc.fillRectangle(LINE_LEFT_X, LINE_TOP_Y, 1, BRACKET);
        dc.fillRectangle(right, LINE_TOP_Y, 1, BRACKET);
        dc.fillRectangle(LINE_LEFT_X, LINE_BOTTOM_Y - BRACKET + 1, 1, BRACKET);
        dc.fillRectangle(right, LINE_BOTTOM_Y - BRACKET + 1, 1, BRACKET);

        var topHeight = LINE_TOP_Y - TOP_LABEL_Y;
        var bottomHeight = BOTTOM_LABEL_Y + LABEL_HEIGHT - LINE_BOTTOM_Y - 1;
        if (used(0) && used(1)) {
            dc.fillRectangle(DIVIDER_LEFT_X, TOP_LABEL_Y, 1, topHeight);
        }
        if (used(1) && used(2)) {
            dc.fillRectangle(DIVIDER_RIGHT_X, TOP_LABEL_Y, 1, topHeight);
        }
        if (used(3) && used(4)) {
            dc.fillRectangle(DIVIDER_LEFT_X, LINE_BOTTOM_Y + 1, 1, bottomHeight);
        }
        if (used(4) && used(5)) {
            dc.fillRectangle(DIVIDER_RIGHT_X, LINE_BOTTOM_Y + 1, 1, bottomHeight);
        }
    }

    //! Is this field slot (0-5) showing something?
    private function used(slot as Number) as Boolean {
        return _fields[slot] != Data.FIELD_NONE;
    }

    //! Three fields side by side, starting at slot first (0 = top row, 3 = bottom row).
    private function drawRow(dc as Dc, first as Number, labelY as Number, valueY as Number) as Void {
        drawField(dc, _fields[first], false, SIDE_LEFT_X, labelY, valueY);
        drawField(dc, _fields[first + 1], true, SCREEN_MID, labelY, valueY);
        drawField(dc, _fields[first + 2], false, SIDE_RIGHT_X, labelY, valueY);
    }

    //! One data field: a small label and a larger value, both centred on x.
    //! wide: true for the middle column, which has room for longer values.
    private function drawField(dc as Dc, type as Number, wide as Boolean, x as Number, labelY as Number, valueY as Number) as Void {
        if (type == Data.FIELD_NONE) {
            return;
        }
        var content = Data.field(type, wide, _snap);
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, _fontLabel, content[0], Graphics.TEXT_JUSTIFY_CENTER);
        var low = (type == Data.FIELD_BATTERY && _snap.batteryLow());
        dc.setColor(low ? warningColor() : _colors[Config.PART_VALUES], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, valueY, _fontData, content[1], Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---------------------------------------------------------------------
    // Time
    // ---------------------------------------------------------------------

    //! The time.  While the watch is awake the colon blinks once a second,
    //! and, if enabled, dark scanlines run through the numerals like an
    //! old CRT.
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
        var left = x;

        dc.setColor(_colors[Config.PART_HOURS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, TIME_Y, _fontTime, hours, Graphics.TEXT_JUSTIFY_LEFT);
        x += hours.length() * TIME_DIGIT_STEP;
        var colonX = x;

        if (!_awake || clock.sec % 2 == 0) {
            dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, TIME_Y, _fontTime, ":", Graphics.TEXT_JUSTIFY_LEFT);
        }
        x += TIME_COLON_STEP;

        dc.setColor(_colors[Config.PART_MINUTES], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, TIME_Y, _fontTime, minutes, Graphics.TEXT_JUSTIFY_LEFT);

        // Scanlines cut through the numerals but not the colon, which stays
        // a solid pair of dots.
        if (_scanlines) {
            var afterColon = colonX + TIME_COLON_W;
            var right = left + width;
            dc.setColor(_colors[Config.PART_BACKGROUND], Graphics.COLOR_TRANSPARENT);
            for (var y = TIME_Y + SCANLINE_STEP - 1; y < TIME_Y + TIME_HEIGHT; y += SCANLINE_STEP) {
                dc.fillRectangle(left, y, colonX - left, 1);
                dc.fillRectangle(afterColon, y, right - afterColon, 1);
            }
        }
    }

    // ---------------------------------------------------------------------
    // Bottom bar and status icons
    // ---------------------------------------------------------------------

    //! Ten-segment level meter.  Empty segments are drawn as short stubs.
    private function drawBar(dc as Dc) as Void {
        if (_barMode == Data.GAUGE_OFF) {
            return;
        }
        var level = Data.gauge(_barMode, _snap);
        var full = (level * 10 + 0.99).toNumber();
        var color = _colors[Config.PART_ACCENT];
        if (_barMode == Data.GAUGE_BATTERY && _snap.batteryLow()) {
            color = warningColor();
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

    //! The last few hours of heart rate as a line, like a bedside monitor,
    //! over a dotted baseline.  The newest reading is at the right, marked
    //! with a dot.
    private function drawTrace(dc as Dc, minute as Number) as Void {
        if (minute != _traceMinute || _trace == null) {
            _trace = Data.heartTrace(TRACE_W);
            _traceMinute = minute;
        }
        var points = _trace as Array<Float>;

        dc.setColor(_colors[Config.PART_LINES], Graphics.COLOR_TRANSPARENT);
        for (var x = TRACE_X; x < TRACE_X + TRACE_W; x += 3) {
            dc.drawPoint(x, TRACE_Y + TRACE_H + 1);
        }

        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        var prevX = -1;
        var prevY = 0;
        for (var i = 0; i < TRACE_W; i++) {
            var value = points[i];
            if (value < 0.0) {
                prevX = -1; // gap in the readings: lift the pen
                continue;
            }
            var x = TRACE_X + i;
            var y = TRACE_Y + TRACE_H - 1 - (value * (TRACE_H - 1) + 0.5).toNumber();
            if (prevX >= 0) {
                dc.drawLine(prevX, prevY, x, y);
            }
            dc.drawPoint(x, y);
            prevX = x;
            prevY = y;
        }
        if (prevX >= 0) {
            dc.fillRectangle(prevX, prevY - 1, 2, 3);
        }
    }

    //! A centred row of small icons, each shown only while it applies:
    //! battery low (in red), phone link (crossed out when lost), alarm set,
    //! do not disturb, and unread notifications.
    private function drawStatusRow(dc as Dc, settings as System.DeviceSettings) as Void {
        var icons = settings.phoneConnected ? "{" : "<";
        if (settings.alarmCount > 0) {
            icons += "  ^";
        }
        if ((settings has :doNotDisturb) && settings.doNotDisturb) {
            icons += "  ~";
        }
        if (settings.notificationCount > 0) {
            icons += "  >";
        }
        var x = SCREEN_MID;
        if (_snap.batteryLow()) {
            // The battery icon goes first, in its own colour, so centre the
            // row as a whole.
            var battery = "|  ";
            var batteryWidth = dc.getTextWidthInPixels(battery, _fontLabel);
            x = SCREEN_MID - (batteryWidth + dc.getTextWidthInPixels(icons, _fontLabel)) / 2;
            dc.setColor(warningColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, BAR_Y - 1, _fontLabel, battery, Graphics.TEXT_JUSTIFY_LEFT);
            x += batteryWidth;
            dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, BAR_Y - 1, _fontLabel, icons, Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, BAR_Y - 1, _fontLabel, icons, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Small icons either side of the bar: phone link lost on the left; on
    //! the right a red battery when it is low, otherwise unread
    //! notifications.  Nothing is drawn when all is well.
    private function drawStatus(dc as Dc, settings as System.DeviceSettings) as Void {
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        if (!settings.phoneConnected) {
            dc.drawText(ICON_LEFT_X, BAR_Y - 1, _fontLabel, "<", Graphics.TEXT_JUSTIFY_LEFT);
        }
        if (_snap.batteryLow()) {
            dc.setColor(warningColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(ICON_RIGHT_X, BAR_Y - 1, _fontLabel, "|", Graphics.TEXT_JUSTIFY_LEFT);
        } else if (settings.notificationCount > 0) {
            dc.drawText(ICON_RIGHT_X, BAR_Y - 1, _fontLabel, ">", Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Red, for warnings - unless the background is red, when red would be
    //! invisible and the data-value colour is used instead.
    private function warningColor() as Number {
        if (_colors[Config.PART_BACKGROUND] == Graphics.COLOR_RED) {
            return _colors[Config.PART_VALUES];
        }
        return Graphics.COLOR_RED;
    }
}
