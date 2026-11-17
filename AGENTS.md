# Handoff notes

For whoever (person or LLM) picks this project up next. `README.md` is the
user-facing guide; this file is the state of the work and how to get a build
environment going.

## What this is

Apogee is a Connect IQ **watch face for the Garmin Forerunner 55** (`fr55`),
written in Monkey C. The owner is new to Garmin development and cares most
about: a striking retro-futuristic but uncluttered look, and being able to
recolour individual parts of the face easily.

## Status

Working and feature-complete for a first version.

Verified in Garmin's simulator (SDK 9.3.0, device `fr55`, CIQ 3.4.2):

- compiles with no warnings at the strictest type-check level (`-l 3`)
- all ten themes render in the six-field layout, in both numeral styles
- bottom bar: heart-rate trace (real simulator history and synthetic), status
  icon row with every icon forced on, and the older gauges
- every data field type renders with live simulator data (weather fields that
  need a location show "--" there, as designed)
- the widest values each column can receive stay clear of the tick ring
- low battery (forced to 9%): red Battery value, red battery icon beside the
  trace, and leading the status icon row
- 24 h and 12 h modes; empty field slots; status icons
- the on-watch settings menu: every level opens, choices are stored and applied
- `dist/Apogee.prg` (the release build that is committed) loads and runs
- memory about 36 KB of the 92 KB a watch face gets

**Not verified: anything on a physical watch.** In particular nobody has yet
confirmed (a) how legible the 7 px labels are on the real screen, (b) the exact
button path to the on-watch menu on an FR55 (README says *Watch Face → Apogee →
START → Customize*), (c) whether the FR55 mounts as a plain USB drive on macOS.
If the owner reports back on these, update the README.

Phone-side settings (`resources/settings/settings.xml`) compile but can only be
exercised after a Connect IQ Store upload, so they are untested.

## Code notes

- **Battery design.** The watch redraws once a minute, and every second for
  ~10 s after a wrist raise. `ApogeeView.refresh()` does everything that need
  not change every second - reads `Data.Snapshot` (activity info, device
  settings, battery, weather), formats the six fields and the date, works out
  both gauges - once a minute and once per wrist raise (`_stale`). Per-second
  redraws only draw from those caches, plus the live heart-rate field, the
  clock, the seconds tick and the blinking colon. Keep new features on the
  right side of that line.
- Weather is only read when a weather field is shown, at most every 10 min.
- Ring tick end points are precomputed into ByteArrays; no trig per frame.
- `Data.HeartTrace` keeps running per-column totals for the bottom-bar trace
  (54 columns x 5 min). Each update shifts columns and reads only readings
  newer than the last one counted - about five. The whole window is read once,
  at start-up, capped at `TRACE_MAX_SAMPLES`. Verified in the simulator to
  match a full recalculation exactly.
- Settings are only re-read in `onShow` if `Config.changed` is set (any
  `Config.setValue` sets it); caches are only discarded when the setting they
  depend on changed. Phone changes arrive via `onSettingsChanged`.
- `_awake` starts false so a face started in low-power mode cannot freeze the
  seconds tick or hide the colon for a minute.
- Menu name lists are functions (built while the menu is open), and themes are
  9-letter strings, to keep permanent memory down.
- Warnings use `warningColor()`: red, unless the background is red.

## Performance notes (measured in the simulator, 17 Nov 2026)

Timings are from the simulator on a PC, so only the proportions mean
anything. The watchdog limit is 120,000 instructions per redraw; a full read
of the heart-rate history is about a fifth of it, which is why it only
happens once.

| Work                              | Before the efficiency pass | After |
| --------------------------------- | -------------------------- | ----- |
| heart trace, per update           | ~3.7 ms, every minute      | ~0.05 ms, every 5 min (one full read at start-up, ~7 ms) |
| full draw, each second while awake | ~1.4 ms                   | ~0.65 ms |
| data reading and formatting       | every redraw               | once a minute + once per wrist raise (~0.2 ms) |
| ring                              | ~0.15 ms                   | ~0.05 ms |
| trace drawing                     | ~0.7 ms                    | ~0.35 ms |

The efficiency pass produced pixel-identical output (checked by image diff).
Memory: 35.8 KB of 91.8 KB - unchanged, because the new caches use about what
the smaller menu lists and theme table freed. The compiler's default is
already its highest optimisation level (`-O 2` and `-O 3` produce identical
output).

## Hard constraints of the device

From the SDK's `fr55/compiler.json`:

- 208 x 208 round MIP screen, **8 colours only** (black, white, red, yellow,
  green, cyan, blue, magenta), **no anti-aliasing, no alpha blending**.
  Any other colour is snapped to the nearest of the eight.
- Connect IQ API 3.4. No complications API, no floors, no body battery.
- `Toybox has :SensorHistory` throws without the SensorHistory permission -
  do not probe it. The manifest requests `UserProfile` (VO2 max, resting HR).
- Watch faces redraw once a minute except for ~10 s after a wrist raise.

## Design rules worth keeping

- Fonts are **generated**, never hand-edited: change `tools/make_fonts.py`,
  run it, commit the regenerated files in `resources/fonts`. There are two
  numeral styles (setting `NumeralStyle`): *VHS* is hand-drawn on an 8 x 14
  grid and used at 1x for data values and 4x for the time; *Squared* is built
  from seven strokes with rounded outer corners. Both must keep the same
  footprint (time 32 x 56 with a 6 px gap, data 8 x 14 with a 2 px gap) because
  the layout is shared. Labels are a hand-drawn 5x7 alphabet (plus a
  one-pixel-bolder cut used for the date).
- Six fields in two rows of three. The outer columns are hemmed in by the
  round edge: labels there must be **5 characters or fewer** and values no
  wider than four numerals (42 px); `Data.count()` abbreviates 12431 to
  "12.4K" for that reason. The middle column takes five numerals. Layout
  numbers are the constants at the top of `source/ApogeeView.mc`; they were
  worked out against the circle with almost no slack, so check the corners
  when moving anything outward.
- The owner did not want a notification count on the face by default; it is
  still offered as a field option.
- The lists in `Settings.mc`, `strings.xml` and `settings.xml` are parallel:
  an option's position in each must match its stored number (and the enums in
  `Data.mc` / theme rows in `Config.mc`).
- On-watch menu **titles** must stay short (about 8 characters) - longer ones
  wrap and clip on the round screen. Phone titles use the separate `Phone*`
  strings and can be long.

## Building

With the SDK and a developer key:

```bash
CIQ_SDK=/path/to/connectiq-sdk CIQ_KEY=/path/to/developer_key.der tools/build.sh
```

```bash
CIQ_SDK=/path/to/connectiq-sdk CIQ_KEY=/path/to/developer_key.der tools/build.sh store
```

The first writes `bin/Apogee.prg`, the second `bin/Apogee.iq`. Copy them to
`dist/` when cutting a release. The developer key is deliberately **not** in
the repository (see `.gitignore`); the owner holds the one that signed the
committed `dist/` files. Any key works for side-loading, but store updates
must be signed with the same key as the original upload.

### Headless Linux setup that worked

1. SDK: list at `https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json`,
   zips in the same folder. Needs Java.
2. Device files: Garmin only serves these through the SDK Manager with a
   login. Without one, `Devices/fr55` and the `Fonts/FNT_006B386900_*` files
   can be extracted from the layers of the public image
   `ghcr.io/matco/connectiq-tester` and placed in `~/.Garmin/ConnectIQ/`.
3. Simulator (`bin/simulator`) needs `libwebkit2gtk-4.0-37` (from Ubuntu
   22.04's repos on newer releases), `libsoup2.4-1`, `libsecret-1-0`, and runs
   fine under `Xvfb`. Push a build with `bin/monkeydo <prg> fr55`.
4. Simulator quirks: a fresh instance shows a blank white screen, then a blue
   triangle while loading; pushes to an already-running instance fail
   intermittently, so restart it per run and wait for the old process to
   exit first. Stored settings live in
   `/tmp/com.garmin.connectiq/GARMIN/APPS/SETTINGS/APOGEE.SET` - delete it to
   get the defaults back. *Settings → Trigger App Settings* opens the
   on-watch menu.

The images in `docs/` are real simulator screenshots with the clock and
activity numbers temporarily hard-coded in a throwaway copy of the source.

## Ideas not done

- Always-on seconds via `onPartialUpdate` (deliberately skipped: battery).
- A 'PLAY >' style VHS tag was offered as a toggle and not chosen. Scanlines
  (setting `Scanlines`, off by default), corner brackets, a blinking colon while awake and a
  ring without minute dots were chosen and are in.
- More data fields: alarms, do-not-disturb (glyphs `^` and `~` already exist
  in the label font), second time zone, humidity, feels-like temperature.
  Body battery and stress are not exposed to Connect IQ on this watch.
- Support for other 208 x 208 or larger round watches (would need the fonts
  generated at more sizes and the layout made relative).

## Out of scope (decided with the owner)

- Answering Claude prompts (questions, permission requests) from the watch.
  The owner wanted it to work through the Claude iPhone app over Bluetooth,
  which Connect IQ cannot do: watch apps only talk to Garmin Connect, and iOS
  lets neither read or act on another app. The workable alternative (a watch
  app plus a relay server fed by Claude Code hooks) was declined. Don't
  re-propose it unless asked.
