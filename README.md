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

## Tests

```sh
flutter analyze
flutter test
```

- `test/domain/` holds pure unit tests with fixed fixtures and exact expected numbers. They cover
  readiness, the suggestion engine, the guardrail, ranks, streaks, XP, aggregation, quests and
  achievements.
- `test/data/seed_and_export_test.dart` seeds 12 weeks through the real logging pipeline into an
  in-memory database, then checks the JSON and CSV exports.

If you change `lib/core/db/tables.dart`, regenerate the drift code with
`dart run build_runner build --delete-conflicting-outputs`, and add a migration step in
`AppDatabase.migration` and bump `schemaVersion`.

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

## Tutorials

- Each exercise page has **3D | Video | Steps** tabs. The 3D demo loops, with play/pause and 0.5×.
- **Pin a video:** paste a YouTube link in the Video tab, or add an optional **YouTube Data API key** in
  Settings → Tutorials (stored in the iOS Keychain) to search inside the app. To get a key: Google Cloud
  Console → enable "YouTube Data API v3" → Credentials → API key.
- **Fix a wrong or missing 3D demo:** debug build → Settings → Debug menu → **Media matching**. Pick
  the right animation (stored on the device), tap the copy icon, and paste the JSON into
  `assets/media_overrides.json` to make it permanent.

## Editable data

- **Strength standards:** `assets/strength_standards.json`. For each lift: the dataset exercise
  ids it covers, 10 tier-entry thresholds as e1RM ÷ bodyweight (Iron…Challenger) derived from its `anchors`, its primary and
  secondary muscle groups, and the `bodyweight_loaded` and `per_hand` flags.
- **Achievements:** `assets/achievements.json`. Each has a key, title, description, icon, a metric
  `type` (sessions, cleanSessionStreak, smartRestDays, comebacks, weeklyStreak, bestExerciseTier (tier index 0–9),
  discipline, prs, totalVolumeKg or level) and a `threshold`.
- **Muscle mapping:** dataset muscles → the 12 ranking groups live in
  `lib/features/library/domain/muscle_mapping.dart`.
- **Exercise library:** `assets/exercises.json` comes from
  [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain). Images are
  loaded from the repo at runtime and cached. To refresh the file, download `dist/exercises.json`
  again and bump `exerciseDatasetVersion` in `lib/features/library/data/exercise_repository.dart`.
- **Increments, rep ranges, RIR, rest times and the weekly goal:** in the app's Settings.

## Credits

- Exercise library: [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public domain).
- Anatomical body map paths: [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter)
  by ELABBASSI Hicham, MIT License (`docs/licenses/react-native-body-highlighter-LICENSE.txt`).
- 3D exercise demos: [ExerciseDB](https://exercisedb.dev) V1 free dataset (non-commercial use, attribution
  required). Only metadata is bundled; GIFs download on first view.
- Fonts: [Oxanium](https://fonts.google.com/specimen/Oxanium) and [Barlow](https://fonts.google.com/specimen/Barlow) (SIL Open Font License, `docs/licenses/`).
- Rank emblems: original artwork drawn in code for this app.

## Privacy

There is no backend, account or analytics. All data stays in the on-device SQLite database. The
only network requests download exercise images and 3D demo GIFs, play embedded YouTube videos and,
if you've set a key, run YouTube searches.
