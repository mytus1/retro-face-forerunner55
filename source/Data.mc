import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;
import Toybox.Weather;

//! Reads the numbers shown in the six data fields and the two gauges.
module Data {

    //! What a data field can show.  The numbers match settings.xml.
    enum {
        FIELD_NONE,
        FIELD_STEPS,
        FIELD_HEART,
        FIELD_BATTERY,
        FIELD_DISTANCE,
        FIELD_CALORIES,
        FIELD_ACTIVE,
        FIELD_ALERTS,
        FIELD_TEMP,
        FIELD_SUN,
        FIELD_RECOVERY,
        FIELD_RAIN,
        FIELD_WIND,
        FIELD_VO2MAX,
        FIELD_RESTING_HR
    }

    //! What the outer ring and bottom bar can show.  The numbers match
    //! settings.xml.  The last two are for the bottom bar only.
    enum {
        GAUGE_OFF,
        GAUGE_STEPS,
        GAUGE_BATTERY,
        GAUGE_ACTIVE,
        BAR_HEART_TRACE,
        BAR_STATUS
    }

    //! The heart-rate trace in the bottom bar: one pixel column per five
    //! minutes, so 54 columns cover the last four and a half hours.  It is
    //! only recalculated when a new five-minute column begins.
    const TRACE_COLUMN_SECONDS = 300;

    //! At most this many heart-rate readings are read per update, newest
    //! first.  Normally an update reads about five; only the first, when the
    //! face starts, reads the whole window (about 270 at one a minute).  The
    //! cap keeps a watch that stores readings more densely well inside the
    //! watchdog's limit on work per redraw.
    const TRACE_MAX_SAMPLES = 500;

    //! Marks a trace column with no readings.
    const NO_READING = 255;

    const NO_VALUE = "--";

    //! At or below this charge (percent) the battery is shown in red.
    const LOW_BATTERY = 15.0;

    //! Everything the fields and gauges read, fetched once per redraw rather
    //! than once per field.  ApogeeView keeps one and refreshes it.
    class Snapshot {
        var info as ActivityMonitor.Info;
        var settings as System.DeviceSettings;
        var battery as Float;                          // percent, 0-100
        var weather as Weather.CurrentConditions or Null;

        function initialize() {
            info = ActivityMonitor.getInfo();
            settings = System.getDeviceSettings();
            battery = System.getSystemStats().battery;
            weather = null;
        }

        function batteryLow() as Boolean {
            return battery <= LOW_BATTERY;
        }
    }

    //! Label and value for one data field, e.g. ["STEPS", "8421"].
    //!
    //! Labels are at most five characters and values at most four numerals
    //! wide, because that is all the outer columns have room for.  The middle
    //! column is wider: pass wide = true and big counts are shown in full
    //! instead of as "12.4K".
    function field(type as Number, wide as Boolean, snap as Snapshot) as Array<String> {
        var info = snap.info;
        var settings = snap.settings;

        if (type == FIELD_STEPS) {
            return ["STEPS", count(info.steps, wide)];
        }
        if (type == FIELD_HEART) {
            return ["BPM", count(heartRate(), wide)];
        }
        if (type == FIELD_BATTERY) {
            return ["BATT", (snap.battery + 0.5).toNumber().format("%d") + "%"];
        }
        if (type == FIELD_DISTANCE) {
            var metric = settings.distanceUnits != System.UNIT_STATUTE;
            return [metric ? "KM" : "MILES", distance(info.distance, metric)];
        }
        if (type == FIELD_CALORIES) {
            return ["KCAL", count(info.calories, wide)];
        }
        if (type == FIELD_ACTIVE) {
            var active = info.activeMinutesWeek;
            return ["ACTIV", count(active != null ? active.total : null, wide)];
        }
        if (type == FIELD_ALERTS) {
            return ["NOTIF", count(settings.notificationCount, wide)];
        }
        if (type == FIELD_RECOVERY) {
            // Hours until Garmin's recovery advisor says you are fully recovered.
            return ["RECOV", count((info has :timeToRecovery) ? info.timeToRecovery : null, wide)];
        }
        if (type == FIELD_VO2MAX) {
            var profile = UserProfile.getProfile();
            return ["VO2", count((profile has :vo2maxRunning) ? profile.vo2maxRunning : null, wide)];
        }
        if (type == FIELD_RESTING_HR) {
            var profile = UserProfile.getProfile();
            return ["REST", count((profile has :restingHeartRate) ? profile.restingHeartRate : null, wide)];
        }
        if (type == FIELD_TEMP || type == FIELD_RAIN || type == FIELD_WIND || type == FIELD_SUN) {
            return weather(type, settings, snap.weather);
        }
        return ["", ""];
    }

    //! How full a gauge is, from 0.0 to 1.0.
    function gauge(mode as Number, snap as Snapshot) as Float {
        var value = 0.0;
        var info = snap.info;
        if (mode == GAUGE_BATTERY) {
            value = snap.battery / 100.0;
        } else if (mode == GAUGE_STEPS) {
            value = ratio(info.steps, info.stepGoal);
        } else if (mode == GAUGE_ACTIVE) {
            var active = info.activeMinutesWeek;
            value = ratio(active != null ? active.total : null, info.activeMinutesWeekGoal);
        }
        if (value < 0.0) {
            return 0.0;
        }
        return (value > 1.0) ? 1.0 : value;
    }

    //! The heart-rate trace: average heart rate per five-minute column.
    //!
    //! It keeps its running totals between updates, so each update only
    //! reads the readings that arrived since the last one (about five) and
    //! shifts the columns along.  The whole window is only read once, when
    //! the face starts.
    class HeartTrace {
        private var _sums as Array<Number>;
        private var _counts as Array<Number>;
        private var _period as Number = -1;   // five-minute period of the newest column
        private var _lastSeen as Number = 0;  // time of the newest reading already counted

        function initialize(columns as Number) {
            _sums = new [columns] as Array<Number>;
            _counts = new [columns] as Array<Number>;
            clear(0, columns);
        }

        private function clear(from as Number, to as Number) as Void {
            for (var i = from; i < to; i++) {
                _sums[i] = 0;
                _counts[i] = 0;
            }
        }

        //! Bring the columns up to date.  period: seconds since 1970 divided
        //! by TRACE_COLUMN_SECONDS; the newest column is that period.
        function update(period as Number) as Void {
            var columns = _sums.size();
            var start = (period + 1 - columns) * TRACE_COLUMN_SECONDS;
            var shift = period - _period;
            if (_period < 0 || shift < 0 || shift >= columns) {
                clear(0, columns);
                _lastSeen = start - 1;
            } else if (shift > 0) {
                for (var i = 0; i < columns - shift; i++) {
                    _sums[i] = _sums[i + shift];
                    _counts[i] = _counts[i + shift];
                }
                clear(columns - shift, columns);
            }
            _period = period;
            if (_lastSeen < start - 1) {
                _lastSeen = start - 1;
            }
            if (!(ActivityMonitor has :getHeartRateHistory)) {
                return;
            }

            // Newest first, back to the last reading already counted.
            var now = Time.now().value();
            var back = now - _lastSeen + 60;
            var history = ActivityMonitor.getHeartRateHistory(new Time.Duration(back), true);
            var sample = history.next();
            var newest = _lastSeen;
            var seen = 0;
            while (sample != null && seen < TRACE_MAX_SAMPLES) {
                var when = sample.when;
                if (when != null) {
                    var t = when.value();
                    if (t <= _lastSeen) {
                        break; // already counted
                    }
                    var column = (t - start) / TRACE_COLUMN_SECONDS;
                    if (column < columns) {
                        // (A reading beyond the newest column is left for a
                        // later update rather than marked as seen.)
                        if (t > newest) {
                            newest = t;
                        }
                        var bpm = sample.heartRate;
                        if (bpm != null && bpm != ActivityMonitor.INVALID_HR_SAMPLE && column >= 0) {
                            _sums[column] += bpm;
                            _counts[column] += 1;
                        }
                    }
                }
                seen += 1;
                sample = history.next();
            }
            _lastSeen = newest;
        }

        //! Average heart rate per column, scaled from 0.0 to 1.0, or -1.0
        //! where there are no readings.
        function levels() as Array<Float> {
            var columns = _sums.size();
            var out = new [columns] as Array<Float>;
            var low = 999.0;
            var high = 0.0;
            for (var i = 0; i < columns; i++) {
                if (_counts[i] > 0) {
                    var bpm = _sums[i].toFloat() / _counts[i];
                    out[i] = bpm;
                    low = (bpm < low) ? bpm : low;
                    high = (bpm > high) ? bpm : high;
                } else {
                    out[i] = -1.0;
                }
            }
            if (high < low) {
                return out; // no readings at all
            }

            // A quiet few hours (less than 30 bpm between lowest and highest)
            // is not stretched to fill the height, so resting jitter stays a
            // gentle wobble rather than looking like a workout.
            var range = high - low;
            if (range < 30.0) {
                low -= (30.0 - range) / 2.0;
                range = 30.0;
            }
            for (var i = 0; i < columns; i++) {
                if (_counts[i] > 0) {
                    out[i] = (out[i] - low) / range;
                }
            }
            return out;
        }

        //! The trace as pixel heights, ready to draw: one byte per column,
        //! oldest first, from 0 (lowest) to height - 1 (highest), or
        //! NO_READING.
        function pixels(height as Number) as ByteArray {
            var levels = levels();
            var out = new [levels.size()]b;
            for (var i = 0; i < levels.size(); i++) {
                var level = levels[i];
                out[i] = (level < 0.0) ? NO_READING : (level * (height - 1) + 0.5).toNumber();
            }
            return out;
        }
    }

    // ---------------------------------------------------------------------

    //! A whole number.  Five figures only fit in the wide middle column, so
    //! elsewhere 12431 is shown as "12.4K".
    function count(value as Number or Null, wide as Boolean) as String {
        if (value == null) {
            return NO_VALUE;
        }
        if (value >= 100000 || (value >= 10000 && !wide)) {
            return (value < 100000) ? (value / 1000.0).format("%.1f") + "K" : (value / 1000).format("%d") + "K";
        }
        return value.format("%d");
    }

    function ratio(value as Number or Null, goal as Number or Null) as Float {
        if (value == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return value.toFloat() / goal;
    }

    //! Current heart rate, falling back to the most recent all-day sample.
    function heartRate() as Number or Null {
        var activity = Activity.getActivityInfo();
        if (activity != null && activity.currentHeartRate != null) {
            return activity.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    //! Today's distance.  The watch reports centimetres.
    function distance(centimetres as Number or Null, metric as Boolean) as String {
        if (centimetres == null) {
            return NO_VALUE;
        }
        var d = centimetres / (metric ? 100000.0 : 160934.4);
        if (d < 10.0) {
            return d.format("%.2f");
        }
        return (d < 100.0) ? d.format("%.1f") : d.format("%d");
    }

    //! The fields that come from the watch's weather report.  The watch gets
    //! that from your phone, for wherever the phone is, so these show "--"
    //! until the two have synced.
    //! report: the watch's current weather report, or null if it has none.
    function weather(type as Number, settings as System.DeviceSettings, report as Weather.CurrentConditions or Null) as Array<String> {

        if (type == FIELD_TEMP) {
            var celsius = (report != null) ? report.temperature : null;
            if (celsius == null) {
                return ["TEMP", NO_VALUE];
            }
            var t = celsius.toFloat();
            if (settings.temperatureUnits == System.UNIT_STATUTE) {
                t = t * 1.8 + 32.0;
            }
            return ["TEMP", Math.round(t).format("%d") + "°"];
        }
        if (type == FIELD_RAIN) {
            var chance = (report != null) ? report.precipitationChance : null;
            return ["RAIN", (chance != null) ? chance.format("%d") + "%" : NO_VALUE];
        }
        if (type == FIELD_WIND) {
            // Reported in metres per second; shown in km/h or mph.
            var speed = (report != null) ? report.windSpeed : null;
            if (speed == null) {
                return ["WIND", NO_VALUE];
            }
            var metric = settings.distanceUnits != System.UNIT_STATUTE;
            return ["WIND", Math.round(speed * (metric ? 3.6 : 2.237)).format("%d")];
        }
        return sun(report, settings.is24Hour);
    }

    //! Whichever comes next: today's sunrise, today's sunset, or tomorrow's sunrise.
    function sun(report as Weather.CurrentConditions or Null, is24Hour as Boolean) as Array<String> {
        var where = (report != null) ? report.observationLocationPosition : null;
        if (where != null && (Weather has :getSunrise)) {
            var now = Time.now();
            var rise = Weather.getSunrise(where, now);
            var set = Weather.getSunset(where, now);
            var label = "RISE";
            var when = rise;
            if (rise != null && set != null && now.greaterThan(rise)) {
                if (now.lessThan(set)) {
                    label = "SET";
                    when = set;
                } else {
                    when = Weather.getSunrise(where, now.add(new Time.Duration(Gregorian.SECONDS_PER_DAY)));
                }
            }
            if (when != null) {
                var t = Gregorian.info(when, Time.FORMAT_SHORT);
                var hour = t.hour;
                if (!is24Hour) {
                    hour = hour % 12;
                    if (hour == 0) {
                        hour = 12;
                    }
                }
                return [label, hour.format("%02d") + ":" + t.min.format("%02d")];
            }
        }
        return ["SUN", NO_VALUE];
    }
}
