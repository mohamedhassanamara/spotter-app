# Spotter

A personal, on-device strength-training app for iPhone (Flutter). It tracks workouts with ranks, XP,
streaks and a body graph, and its coach suggests weight × reps × sets for every exercise from your
lifting history and Apple Watch recovery data. It also flags ego lifting.

- Architecture, schema and packages: [`docs/PLAN.md`](docs/PLAN.md)
- Deviations from the original spec: [`docs/DECISIONS.md`](docs/DECISIONS.md)
- Design system (tokens, type, components): [`docs/DESIGN.md`](docs/DESIGN.md)
- Screenshots of the v2 screens: [`docs/screenshots/v2/`](docs/screenshots/v2/)
- Export format: [`docs/export_schema.md`](docs/export_schema.md)

## Run on your iPhone

Requirements: a Mac with Xcode and Flutter (stable), and an iPhone on iOS 17 or later.

1. `flutter pub get`
2. Open `ios/Runner.xcworkspace` in Xcode.
3. Select the **Runner** target → **Signing & Capabilities**:
   - Check **Automatically manage signing** and pick your Apple ID team. To add your account, use
     Xcode → Settings → Accounts → **+**.
   - If `com.hassan.spotter` is taken, change the **Bundle Identifier** to something unique,
     e.g. `com.<yourname>.spotter`.
   - Make sure the **HealthKit** capability is listed. The project ships `Runner/Runner.entitlements`
     with HealthKit enabled. If Xcode shows it unconfigured, click **+ Capability → HealthKit**.
4. Connect the iPhone by cable. Enable **Developer Mode** on it (Settings → Privacy & Security →
   Developer Mode) and trust the computer.
5. Run it from the project folder:
   ```sh
   flutter run --release        # or: flutter run (debug, enables the debug menu)
   ```
   The first time, iOS asks you to trust the developer: Settings → General → VPN & Device
   Management → your Apple ID → Trust.
6. During onboarding, tap **Connect Apple Health** and allow every category. To change this later:
   Health app → Profile → Apps → Spotter.

> **Free provisioning expires after 7 days.** With a free Apple ID (no paid Developer Program),
> the installed app stops launching after 7 days. Re-run `flutter run --release` from the Mac to
> reinstall it; your data is kept, because it lives in the app container. A paid account
> extends this to a year.

Readiness needs your Apple Watch to record HRV, resting heart rate and sleep: wear it to bed with
Sleep tracking on. It shows "Calibrating (X/14 days)" until 14 days of baseline exist, and treats
those days as Green for suggestions.

## ExerciseDB V2 (videos and images) setup

The exercise videos come from ExerciseDB V2 (AscendAPI) via RapidAPI. Your key lives in
`config/secrets.json`, which is git-ignored. Copy `config/secrets.example.json` to that path, put your
key in it, and pass the file to every run or build:

```sh
flutter run --dart-define-from-file=config/secrets.json
```

- Without the key, the app still works and uses the V1 GIFs.
- Enable the pre-commit check once per clone with `git config core.hooksPath .githooks`. It refuses
  any commit where the key appears in a tracked or staged file.
- Your plan allows 2,000 API calls a month; CDN media doesn't count. The app shows a warning at
  1,500 and stops calling at 1,850 until the 1st of the next month, falling back to the V1 GIFs.
  Usage is in Settings → Debug → ExerciseDB V2.

## Tests

```sh
flutter analyze
flutter test
```

- `test/domain/` holds pure unit tests with fixed fixtures and exact expected numbers. They cover
  readiness, the suggestion engine, the guardrail, ranks, streaks, XP, aggregation, quests and
  achievements.
- `test/domain/liftoff_test.dart` and `test/data/liftoff_import_test.dart` cover CSV parsing, rep-scheme
  notes, name mapping, the import itself and idempotency, using `test/fixtures/liftoff_sample.csv`.
- `test/data/seed_and_export_test.dart` seeds 12 weeks through the real logging pipeline into an
  in-memory database, then checks the JSON and CSV exports.

If you change `lib/core/db/tables.dart`, regenerate the drift code with
`dart run build_runner build --delete-conflicting-outputs`, and add a migration step in
`AppDatabase.migration` and bump `schemaVersion`.

### Integration tests (real taps on the simulator)

```sh
xcrun simctl list devices booted          # find the simulator id
flutter test integration_test -d <simulator-id>
```

Screenshots of the logging screen are written by the Push flow when you pass
`--dart-define=SHOTS_DIR=$PWD/docs/screenshots/vF`.

The flows start from a fresh install (and an upgraded v2 install) with only your five routines.
They tap through Push typed entirely on the custom keypad (empty-cell ✓, PREV copy, effort chip,
drop set, rest in the header, minimize and resume), Pull with assisted negative load (+/−), Train → Upper (warm-ups, working sets including the 1×20 row, steppers, add/remove
set, replace via substitutions, background/resume, cold restart, finish, summary, history, start the
next routine from Home), Pull (assisted pull-ups with negative load) and Settings → Import from
Liftoff (preview, fixing an unmatched name, bodyweight prompt, import, re-import is a no-op, and the
next workout's suggestion built from the imported sessions; a fixture CSV stands in for the iOS file
picker), and Ranks (regions with X/Y ranked, muscle rows and sheet, tapping muscles on the front and
back body map, hiding an exercise from ranks, old rank badges revoked silently), and Streak (the
carried-over Liftoff streak on Home, edited in Settings, shown in days on Profile). A flow fails if anything is
written to the in-app error log.

Later flows: `library_media_flow_test` (merged library, thumbnails, Jeff's video on program
exercises), `routine_edit_flow_test` (mid-workout replace/remove/add/reorder/sets/target reps →
Update routine or Keep routine as is; routine editor overrides and Reset to program; empty
workout), `set_types_flow_test` (several drop sets, myo cycles, static hold, program technique
follow-ups, + partials; supersets from the routine editor with alternating sets and rest after the
round) and `body_map_flow_test` (Home recovery card → body map Recovery mode tap, Rank and Volume
modes, the fatigue heads-up). `body_map_flow_test` writes the screenshots in
`docs/screenshots/final/` when given `--dart-define=SHOTS_DIR=$PWD/docs/screenshots/final`.

### Reporting bugs from the phone

Settings → long-press the version label → **Error log** → **Copy all**, then paste it into a message.
It works in release builds.

## Seed data (debug builds only)

Run a debug build (`flutter run`), then open **Settings** and tap **Debug menu**, or long-press the
version label. From there:

- **Use fake Health data**: switches from HealthKit to a deterministic fake source.
- **Seed 12 weeks of history**: wipes training data and generates about 69 sessions. That's 6 a
  week on a push/pull/legs split, with gradual progression, Red-readiness rest days and three
  override episodes that trigger ego freezes, plus varied HRV, resting HR and sleep. Every session
  goes through the real coach and finish pipeline, so XP, PRs, ranks, quests and achievements are
  consistent.
- **Wipe training data** and **Recompute readiness**.

The debug menu and the fake Health source are compiled out of release builds (`kDebugMode`).

To open a specific screen at launch in debug, e.g. on the simulator: `flutter run --route=/progress`.
Useful routes:
- Progress: `/progress?tab=ranks`, `/progress?back=1&mode=volume&group=chest`
- Debug previews: `/settings/debug/badges`, `/settings/debug/rank-up-preview`, `/settings/debug/summary-preview`, `/settings/debug/media`

## Program: Min-Max Phase 2 (5x)

- The program is extracted from your own PDF into `assets/programs/min_max_phase2.json`. The schema is
  in `docs/program/SCHEMA.md` and the extraction findings and open questions are in
  `docs/program/EXTRACTION_REPORT.md`.
- To regenerate it: `pip install pdfplumber`, then
  `python tool/program/extract_min_max.py "/path/to/The Min-Max Program Phase 2 5x.pdf"`.
  **Never commit the PDF** (`private/` and `*.pdf` are git-ignored).
- Your five routines are in `assets/programs/my_routines.json`: names, set counts, and the program
  slots each row follows. They install on first launch. Settings → Program sets the current week and
  can reinstall them.
- In a workout, each set shows its own target (reps and RIR, where RIR 0 = failure). Warm-up sets are
  generated from the program's % pyramid, and Block 2 techniques appear on the last set; tap one to see
  how it works.

## Streak

The streak is counted in days, like Liftoff. There's no weekly goal and no fixed training days. Every
calendar day counts while the streak is alive, rest days included. Up to two days in a row without a
workout are fine; when a third one ends without one, the streak resets to 0, and the next workout
starts it again at 1. A day counts when a finished workout (at least one completed working set)
*started* that day. Home shows how safe it is ("Safe: trained today" / "1 rest day used" / "Last
chance: train today or the streak resets"), and an optional reminder fires at 18:00 on the
last-chance day (Settings → Streak). Your Liftoff streak (177 days on the import date) carries over as
an offset that you can edit in Settings → Streak.

## Muscle recovery

Display only: suggestions never use it. Each working set adds fatigue to its muscles (contribution ×
effort: F 1.0 / 1 left 0.85 / 2 left 0.7 / 3+ 0.5; drops 0.5) that halves every 48 h for large muscles
and 30 h for small ones, slower on Yellow (×0.85) and Red (×0.7) readiness days. Ready ≥ 90 %,
Recovering 60–89 %, Fatigued < 60 %. Shown as the Home card, the body map's Recovery mode and a
one-line heads-up when a routine's main muscles are still fatigued. Every constant is in
`lib/features/recovery/domain/recovery_config.dart`. It's a heuristic (see DECISIONS.md).

## Ranks

- **The model:** 20 muscles in 6 regions, as in Liftoff.
- **Scores:** every set scores 0–1000 against its exercise's standard, using your bodyweight on the
  day of the set (Apple Health weigh-ins). Loads are scaled allometrically:
  e1RM ÷ (100 × (bodyweight ÷ 100)^0.67), so heavier lifters aren't penalised.
- **Consistency:** every accessory standard is a base compound (bench, squat, deadlift, overhead press,
  barbell row) times a typical ratio, so a typical lifter ranks about the same across lifts.
- **Muscles, regions and overall:** a muscle ranks from its exercises' best scores of the last 90 days,
  weighted by how much each exercise trains it. Regions average their muscles; overall averages the
  regions.
- **Hiding an exercise:** on its exercise page, turn off *Count toward ranks*. Its records stay, but it
  never affects a rank. Hidden exercises are listed at the bottom of Progress → Ranks.

## Import from Liftoff

Settings → **Import from Liftoff**. In Liftoff, export your data as CSV and save it to Files, then
choose it in the app. Before anything is written, the preview shows:
- the new sessions and sets, and the date range;
- rows that will be skipped (cardio, timed, empty);
- every exercise name mapping with its method and confidence. Tap a name to pick a different exercise.

Importing the same file again only adds sessions that aren't already in the app.
- Name fixes that should stick go in `assets/liftoff_name_map.json`.
- `docs/IMPORT_SUMMARY.md` shows the result for your export: mappings, current best per lift, ranks
  and the first suggestion for every routine exercise. To regenerate it:
  `LIFTOFF_CSV=~/Desktop/DOCS/liftoff_workout_data.csv LIFTOFF_BW=108@2026-04-19,106@2026-10-11 flutter test test/tool/import_summary_test.dart`.
  The CSV is personal data; never commit it.

## Exercise media

- Program exercises (your routines and the program's listed substitutions) play Jeff Nippard's demo video
  from the Min-Max PDF, embedded in the app.
- Everything else shows the ExerciseDB V1 GIF, or photos, plus the Steps tab.
- Lists show a static thumbnail.
- **Fix a wrong or missing GIF:** debug build → Settings → Debug menu → **Media matching**. Pick the right
  animation, tap the copy icon, and paste the JSON into `assets/media_overrides.json`.

## Editable data

- **Strength standards and muscle contributions:** edit `tool/standards/exercise_data.py`, then run
  `python3 tool/standards/build.py`. It checks the data and writes two assets:
  - `assets/strength_standards.json`: per exercise, five anchors as e1RM ÷ bodyweight (beginner …
    elite). Machine and cable standards are stricter via `machine_strictness`.
  - `assets/exercise_muscles.json`: how much each exercise trains each of the 20 muscles (1.0 = prime
    mover).

  How tiers come from the anchors, and the full anchor table, are in `docs/DECISIONS.md`
  (section 8).
- **Achievements:** `assets/achievements.json`. Each has a key, title, description, icon, a metric
  `type` (sessions, cleanSessionStreak, comebacks, streakDays, bestExerciseTier (tier index 0–9),
  discipline, prs, totalVolumeKg or level) and a `threshold`.
- **Muscle mapping for the rest of the library:** `lib/features/library/domain/muscle_mapping.dart`
  derives contributions from the dataset's muscles plus name keywords (incline → upper chest, lateral
  raise → middle delt…).
- **Exercise library:** `assets/exercises.json` comes from
  [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain). Images are
  loaded from the repo at runtime and cached. To refresh the file, download `dist/exercises.json`
  again and bump `exerciseDatasetVersion` in `lib/features/library/data/exercise_repository.dart`.
- **Liftoff names:** `assets/liftoff_name_map.json` maps Liftoff exercise names to library ids, or defines
  a custom exercise for them.
- **Gym equipment, rep ranges, RIR, rest times and the streak reminder:** in the app's Settings.

## Credits

- Exercise library: [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain) and
  [wger](https://wger.de) exercise data and images (CC-BY-SA 3.0/4.0, CC-BY 4.0, CC0; licence and author
  per exercise, shown on its page), merged by `tool/library/build_library.py`.
- Program demo videos: Jeff Nippard, The Min-Max Program (links extracted from your own PDF by
  `tool/program/extract_videos.py`).
- Anatomical body map paths: [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter)
  by ELABBASSI Hicham, MIT License (`docs/licenses/react-native-body-highlighter-LICENSE.txt`).
- Exercise animations: [ExerciseDB](https://exercisedb.dev) V1 free dataset (non-commercial personal use,
  attribution required). Only metadata is bundled; GIFs download on first view. ExerciseDB V2 (paid,
  RapidAPI) is off by default (Settings → Debug).
- Fonts: [Oxanium](https://fonts.google.com/specimen/Oxanium) and [Barlow](https://fonts.google.com/specimen/Barlow) (SIL Open Font License, `docs/licenses/`).
- Rank emblems: original artwork drawn in code for this app.

## Privacy

There is no backend, account or analytics. All data stays in the on-device SQLite database. The
only network requests download exercise images and 3D demo GIFs, play embedded YouTube videos and,
if you've set a key, run YouTube searches.
