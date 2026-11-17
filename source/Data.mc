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

    //! What the outer ring / bottom bar can show.  The numbers match settings.xml.
    enum {
        GAUGE_OFF,
        GAUGE_STEPS,
        GAUGE_BATTERY,
        GAUGE_ACTIVE
    }

    const NO_VALUE = "--";

    //! Label and value for one data field, e.g. ["STEPS", "8421"].
    //!
    //! Labels are at most five characters and values at most four numerals
    //! wide, because that is all the outer columns have room for.  The middle
    //! column is wider: pass wide = true and big counts are shown in full
    //! instead of as "12.4K".
    function field(type as Number, wide as Boolean) as Array<String> {
        var info = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();

        if (type == FIELD_STEPS) {
            return ["STEPS", count(info.steps, wide)];
        }
        if (type == FIELD_HEART) {
            return ["BPM", count(heartRate(), wide)];
        }
        if (type == FIELD_BATTERY) {
            return ["BATT", (System.getSystemStats().battery + 0.5).toNumber().format("%d") + "%"];
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
            return weather(type, settings);
        }
        return ["", ""];
    }

    //! How full a gauge is, from 0.0 to 1.0.
    function gauge(mode as Number) as Float {
        var value = 0.0;
        if (mode == GAUGE_BATTERY) {
            value = System.getSystemStats().battery / 100.0;
        } else if (mode == GAUGE_STEPS) {
            var info = ActivityMonitor.getInfo();
            value = ratio(info.steps, info.stepGoal);
        } else if (mode == GAUGE_ACTIVE) {
            var info = ActivityMonitor.getInfo();
            var active = info.activeMinutesWeek;
            value = ratio(active != null ? active.total : null, info.activeMinutesWeekGoal);
        }
        if (value < 0.0) {
            return 0.0;
        }
        return (value > 1.0) ? 1.0 : value;
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
    function weather(type as Number, settings as System.DeviceSettings) as Array<String> {
        var report = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;

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
