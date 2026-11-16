import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

//! Reads the numbers shown in the four data fields and the two gauges.
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
        FIELD_RECOVERY
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
    function field(type as Number) as Array<String> {
        var info = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();

        if (type == FIELD_STEPS) {
            return ["STEPS", number(info.steps)];
        }
        if (type == FIELD_HEART) {
            return ["HEART", number(heartRate())];
        }
        if (type == FIELD_BATTERY) {
            return ["BATT", (System.getSystemStats().battery + 0.5).toNumber().format("%d") + "%"];
        }
        if (type == FIELD_DISTANCE) {
            var metric = settings.distanceUnits != System.UNIT_STATUTE;
            return [metric ? "KM" : "MILES", distance(info.distance, metric)];
        }
        if (type == FIELD_CALORIES) {
            return ["KCAL", number(info.calories)];
        }
        if (type == FIELD_ACTIVE) {
            var active = info.activeMinutesWeek;
            return ["ACTIVE", number(active != null ? active.total : null)];
        }
        if (type == FIELD_ALERTS) {
            return ["ALERTS", number(settings.notificationCount)];
        }
        if (type == FIELD_TEMP) {
            return ["TEMP", temperature(settings)];
        }
        if (type == FIELD_SUN) {
            return sun(settings.is24Hour);
        }
        if (type == FIELD_RECOVERY) {
            // Hours until Garmin's recovery advisor says you are fully recovered.
            return ["REC HRS", number((info has :timeToRecovery) ? info.timeToRecovery : null)];
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

    function number(value as Number or Null) as String {
        return (value != null) ? value.format("%d") : NO_VALUE;
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

    //! Current temperature from the watch's weather data (needs a phone connection).
    function temperature(settings as System.DeviceSettings) as String {
        if (Toybox has :Weather) {
            var now = Weather.getCurrentConditions();
            var celsius = (now != null) ? now.temperature : null;
            if (celsius != null) {
                var t = celsius.toFloat();
                if (settings.temperatureUnits == System.UNIT_STATUTE) {
                    t = t * 1.8 + 32.0;
                }
                return Math.round(t).format("%d") + "°";
            }
        }
        return NO_VALUE;
    }

    //! Whichever comes next: today's sunrise, today's sunset, or tomorrow's sunrise.
    function sun(is24Hour as Boolean) as Array<String> {
        if ((Toybox has :Weather) && (Weather has :getSunrise)) {
            var conditions = Weather.getCurrentConditions();
            var where = (conditions != null) ? conditions.observationLocationPosition : null;
            if (where != null) {
                var now = Time.now();
                var rise = Weather.getSunrise(where, now);
                var set = Weather.getSunset(where, now);
                var label = "SUNRISE";
                var when = rise;
                if (rise != null && set != null && now.greaterThan(rise)) {
                    if (now.lessThan(set)) {
                        label = "SUNSET";
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
        }
        return ["SUN", NO_VALUE];
    }
}
