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
//             . ' | ' .              outer ring: hour marks; lit ticks are a gauge
//            MON 16 NOV              date
//        STEPS |  KM  | KCAL         labels
//         8421 | 6.47 | 1840         values
//       [----------------------]
//              13:37                 time
//       [----------------------]
//          17° |  62  | 76%          values
//         TEMP | BPM  | BATT         labels
//            _/\__/\_.               bottom bar: heart-rate trace, status icons or a gauge
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
const TRACE_W = 54;              // one column per 5 minutes: 4.5 hours
const TRACE_H = 12;

// Ring geometry: radii of the three kinds of tick.
const RING_OUTER = 102.5;
const RING_LIT_INNER = 96.0;     // lit (gauge) ticks
const RING_HOUR_INNER = 99.0;    // unlit hour marks
const RING_SECOND_INNER = 95.0;  // the seconds tick

// Day and month abbreviations, three letters each, back to back.
const DAY_NAMES = "SUNMONTUEWEDTHUFRISAT";
const MONTH_NAMES = "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC";

//! How long a weather report is reused before it is read again.  The watch
//! itself only gets a new one from the phone every so often.
const WEATHER_SECONDS = 600;

//! Numeral styles.  The numbers match settings.xml.
enum {
    STYLE_VHS,
    STYLE_SQUARE
}

//! Draws the watch face.
//!
//! Battery: the watch redraws once a minute, and every second for about ten
//! seconds after you raise your wrist.  Anything that does not need to change
//! every second - reading activity data, formatting the fields and the date,
//! working out the gauges - is done in refresh(), once a minute and once per
//! wrist raise.  Only the clock, the seconds tick, the blinking colon and the
//! heart rate are updated every second.  The heart-rate trace is only
//! recalculated every five minutes.
class ApogeeView extends WatchUi.WatchFace {

    private var _fontTime as WatchUi.FontResource;
    private var _fontData as WatchUi.FontResource;
    private var _fontLabel as WatchUi.FontResource;
    private var _fontDate as WatchUi.FontResource;

    // End points (x1, y1, x2, y2) of every tick on the ring, worked out once
    // so drawing the ring involves no maths.
    private var _ringLit as ByteArray;       // 60 positions
    private var _ringHour as ByteArray;      // 12 positions
    private var _ringSecond as ByteArray;    // 60 positions

    // Settings, read when they change.
    private var _style as Number;
    private var _colors as Array<Number>;
    private var _fields as Array<Number>;
    private var _ringMode as Number = Data.GAUGE_STEPS;
    private var _barMode as Number = Data.BAR_HEART_TRACE;
    private var _showSeconds as Boolean = true;
    private var _scanlines as Boolean = false;
    private var _needsWeather as Boolean = false;
    private var _hasHeartField as Boolean = false;

    // Data, refreshed once a minute and on each wrist raise.
    private var _snap as Data.Snapshot;
    private var _stale as Boolean = true;          // refresh at the next redraw
    private var _dataMinute as Number = -1;        // minute of the last refresh
    private var _weatherTime as Number = 0;        // when weather was last read; 0 = never
    private var _texts as Array<Array<String> >;   // label and value of each field
    private var _dateText as String = "";
    private var _litTicks as Number = 0;           // ring gauge, in ticks (0-60)
    private var _barLevel as Float = 0.0;          // bar gauge, 0.0-1.0

    // Heart-rate trace: running totals (updated with just the new readings
    // when a new five-minute column begins) and the pixel heights drawn.
    private var _heart as Data.HeartTrace?;
    private var _trace as ByteArray?;
    private var _tracePeriod as Number = -1;

    // True for the few seconds after you raise your wrist, when the watch
    // redraws every second.  Starts false so a face that happens to start in
    // low-power mode never shows a frozen seconds tick or a missing colon.
    private var _awake as Boolean = false;

    function initialize() {
        WatchFace.initialize();

        _style = Config.getNumber("NumeralStyle", STYLE_VHS);
        _fontTime = loadTimeFont(_style);
        _fontData = loadDataFont(_style);
        _fontLabel = WatchUi.loadResource(Rez.Fonts.FontLabel) as WatchUi.FontResource;
        _fontDate = WatchUi.loadResource(Rez.Fonts.FontLabelBold) as WatchUi.FontResource;

        _ringLit = new [240]b;
        _ringHour = new [48]b;
        _ringSecond = new [240]b;
        for (var i = 0; i < 60; i++) {
            var angle = Math.toRadians(i * 6 - 90);
            var c = Math.cos(angle).toFloat();
            var s = Math.sin(angle).toFloat();
            storeTick(_ringLit, i, c, s, RING_LIT_INNER);
            storeTick(_ringSecond, i, c, s, RING_SECOND_INNER);
            if (i % 5 == 0) {
                storeTick(_ringHour, i / 5, c, s, RING_HOUR_INNER);
            }
        }

        _colors = Config.colors();
        _fields = [0, 0, 0, 0, 0, 0] as Array<Number>;
        _texts = [["", ""], ["", ""], ["", ""], ["", ""], ["", ""], ["", ""]] as Array<Array<String> >;
        _snap = new Data.Snapshot();
        loadSettings();
    }

    //! Work out one tick's end points and store them at slot `index`.
    private function storeTick(table as ByteArray, index as Number, c as Float, s as Float, inner as Float) as Void {
        var k = index * 4;
        table[k] = (RING_MID + inner * c + 0.5).toNumber();
        table[k + 1] = (RING_MID + inner * s + 0.5).toNumber();
        table[k + 2] = (RING_MID + RING_OUTER * c + 0.5).toNumber();
        table[k + 3] = (RING_MID + RING_OUTER * s + 0.5).toNumber();
    }

    private function loadTimeFont(style as Number) as WatchUi.FontResource {
        return WatchUi.loadResource((style == STYLE_SQUARE) ? Rez.Fonts.FontTimeSquare : Rez.Fonts.FontTimeVhs) as WatchUi.FontResource;
    }

    private function loadDataFont(style as Number) as WatchUi.FontResource {
        return WatchUi.loadResource((style == STYLE_SQUARE) ? Rez.Fonts.FontDataSquare : Rez.Fonts.FontDataVhs) as WatchUi.FontResource;
    }

    //! Re-read everything the user can configure.  Caches are only thrown
    //! away when the setting they depend on actually changed.
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
        _showSeconds = Config.getBool("ShowSeconds", true);
        _scanlines = Config.getBool("Scanlines", false);

        var needsWeather = false;
        var hasHeart = false;
        for (var i = 0; i < 6; i++) {
            var type = _fields[i];
            needsWeather = needsWeather || type == Data.FIELD_TEMP || type == Data.FIELD_RAIN
                || type == Data.FIELD_WIND || type == Data.FIELD_SUN;
            hasHeart = hasHeart || type == Data.FIELD_HEART;
        }
        if (needsWeather && !_needsWeather) {
            _weatherTime = 0; // a weather field was just added: read it now
        }
        _needsWeather = needsWeather;
        _hasHeartField = hasHeart;
        if (_barMode != Data.BAR_HEART_TRACE) {
            _heart = null; // not shown: free it
            _trace = null;
        }
        _stale = true;
        Config.changed = false;
    }

    //! The face is back on screen (after a widget, a menu or a notification).
    //! Settings are only re-read if something was changed in the menu.
    function onShow() as Void {
        if (Config.changed) {
            loadSettings();
        }
        _stale = true;
    }

    function onExitSleep() as Void {
        _awake = true;
        _stale = true; // fresh numbers for the person who just looked
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    //! Redraw the whole face.
    function onUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        if (_stale || clock.min != _dataMinute) {
            refresh(clock);
        } else if (_hasHeartField && _awake) {
            refreshHeart();
        }

        dc.setColor(_colors[Config.PART_BACKGROUND], _colors[Config.PART_BACKGROUND]);
        dc.clear();

        drawRing(dc, (_awake && _showSeconds) ? clock.sec : -1);
        dc.setColor(_colors[Config.PART_DATE], Graphics.COLOR_TRANSPARENT);
        dc.drawText(SCREEN_MID, DATE_Y, _fontDate, _dateText, Graphics.TEXT_JUSTIFY_CENTER);
        drawFrame(dc);
        drawRow(dc, 0, TOP_LABEL_Y, TOP_VALUE_Y);
        drawRow(dc, 3, BOTTOM_LABEL_Y, BOTTOM_VALUE_Y);
        drawTime(dc, clock, _snap.settings.is24Hour);
        if (_barMode == Data.BAR_HEART_TRACE) {
            drawTrace(dc);
            drawStatus(dc);
        } else if (_barMode == Data.BAR_STATUS) {
            drawStatusRow(dc);
        } else {
            drawBar(dc);
            drawStatus(dc);
        }
    }

    // ---------------------------------------------------------------------
    // Data
    // ---------------------------------------------------------------------

    //! Read the watch's data and work out everything drawn from it.
    private function refresh(clock as System.ClockTime) as Void {
        _snap.info = ActivityMonitor.getInfo();
        _snap.settings = System.getDeviceSettings();
        _snap.battery = System.getSystemStats().battery;

        var now = Time.now().value();
        if (!_needsWeather) {
            _snap.weather = null;
        } else if (_weatherTime == 0 || now - _weatherTime >= WEATHER_SECONDS) {
            _snap.weather = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            _weatherTime = now;
        }

        for (var slot = 0; slot < 6; slot++) {
            var type = _fields[slot];
            if (type != Data.FIELD_NONE) {
                _texts[slot] = Data.field(type, slot % 3 == 1, _snap);
            }
        }

        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var d = ((today.day_of_week as Number) - 1) * 3;
        var m = ((today.month as Number) - 1) * 3;
        var text = (DAY_NAMES.substring(d, d + 3) as String) + " " + today.day.format("%02d") + " "
            + (MONTH_NAMES.substring(m, m + 3) as String);
        if (!_snap.settings.is24Hour) {
            text += (clock.hour < 12) ? " AM" : " PM";
        }
        _dateText = text;

        _litTicks = (Data.gauge(_ringMode, _snap) * 60 + 0.5).toNumber();
        _barLevel = (_barMode <= Data.GAUGE_ACTIVE) ? Data.gauge(_barMode, _snap) : 0.0;

        if (_barMode == Data.BAR_HEART_TRACE) {
            var period = now / Data.TRACE_COLUMN_SECONDS;
            if (_heart == null) {
                _heart = new Data.HeartTrace(TRACE_W);
            }
            if (period != _tracePeriod || _trace == null) {
                var heart = _heart as Data.HeartTrace;
                heart.update(period);
                _trace = heart.pixels(TRACE_H);
                _tracePeriod = period;
            }
        }

        _dataMinute = clock.min;
        _stale = false;
    }

    //! While the watch is awake the heart rate is kept live, every second.
    private function refreshHeart() as Void {
        for (var slot = 0; slot < 6; slot++) {
            if (_fields[slot] == Data.FIELD_HEART) {
                _texts[slot] = Data.field(Data.FIELD_HEART, slot % 3 == 1, _snap);
            }
        }
    }

    // ---------------------------------------------------------------------
    // Outer ring
    // ---------------------------------------------------------------------

    //! Lit ticks (long, accent colour) show the ring gauge; past them only
    //! the twelve hour marks are drawn.
    //! second: 0-59 to show the seconds tick, or -1 to hide it.
    private function drawRing(dc as Dc, second as Number) as Void {
        var lit = _litTicks;
        var t = _ringLit;

        dc.setPenWidth(2);
        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < lit * 4; k += 4) {
            dc.drawLine(t[k], t[k + 1], t[k + 2], t[k + 3]);
        }

        t = _ringHour;
        dc.setColor(_colors[Config.PART_RING], Graphics.COLOR_TRANSPARENT);
        for (var k = ((lit + 4) / 5) * 4; k < 48; k += 4) {
            dc.drawLine(t[k], t[k + 1], t[k + 2], t[k + 3]);
        }

        if (second >= 0) {
            t = _ringSecond;
            var k = second * 4;
            dc.setPenWidth(4);
            dc.setColor(_colors[Config.PART_HOURS], Graphics.COLOR_TRANSPARENT);
            dc.drawLine(t[k], t[k + 1], t[k + 2], t[k + 3]);
        }
        dc.setPenWidth(1);
    }

    // ---------------------------------------------------------------------
    // Dividers and data fields
    // ---------------------------------------------------------------------

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
        drawField(dc, first, SIDE_LEFT_X, labelY, valueY);
        drawField(dc, first + 1, SCREEN_MID, labelY, valueY);
        drawField(dc, first + 2, SIDE_RIGHT_X, labelY, valueY);
    }

    //! One data field: a small label and a larger value, both centred on x.
    private function drawField(dc as Dc, slot as Number, x as Number, labelY as Number, valueY as Number) as Void {
        var type = _fields[slot];
        if (type == Data.FIELD_NONE) {
            return;
        }
        var content = _texts[slot];
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
        var full = (_barLevel * 10 + 0.99).toNumber();
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
    //! with a dot.  The pixel heights come ready-made from refresh().
    private function drawTrace(dc as Dc) as Void {
        dc.setColor(_colors[Config.PART_LINES], Graphics.COLOR_TRANSPARENT);
        for (var x = TRACE_X; x < TRACE_X + TRACE_W; x += 3) {
            dc.drawPoint(x, TRACE_Y + TRACE_H + 1);
        }

        var heights = _trace;
        if (heights == null) {
            return;
        }
        var bottom = TRACE_Y + TRACE_H - 1;
        dc.setColor(_colors[Config.PART_ACCENT], Graphics.COLOR_TRANSPARENT);
        var prevX = -1;
        var prevY = 0;
        for (var i = 0; i < TRACE_W; i++) {
            var h = heights[i];
            if (h == Data.NO_READING) {
                prevX = -1; // gap in the readings: lift the pen
                continue;
            }
            var x = TRACE_X + i;
            var y = bottom - h;
            if (prevX >= 0) {
                dc.drawLine(prevX, prevY, x, y);
            } else {
                dc.drawPoint(x, y);
            }
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
    private function drawStatusRow(dc as Dc) as Void {
        var settings = _snap.settings;
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
        if (_snap.batteryLow()) {
            // The battery icon goes first, in its own colour, so centre the
            // row as a whole.
            var battery = "|  ";
            var batteryWidth = dc.getTextWidthInPixels(battery, _fontLabel);
            var x = SCREEN_MID - (batteryWidth + dc.getTextWidthInPixels(icons, _fontLabel)) / 2;
            dc.setColor(warningColor(), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, BAR_Y - 1, _fontLabel, battery, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + batteryWidth, BAR_Y - 1, _fontLabel, icons, Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }
        dc.setColor(_colors[Config.PART_LABELS], Graphics.COLOR_TRANSPARENT);
        dc.drawText(SCREEN_MID, BAR_Y - 1, _fontLabel, icons, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! Small icons either side of the bar: phone link lost on the left; on
    //! the right a red battery when it is low, otherwise unread
    //! notifications.  Nothing is drawn when all is well.
    private function drawStatus(dc as Dc) as Void {
        var settings = _snap.settings;
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
