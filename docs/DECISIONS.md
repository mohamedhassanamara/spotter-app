# Decisions and deviations from the spec

Each entry: what changed, and why.

## Readiness bands shifted (confirmed with the owner)
The spec maps a combined z of 0 to a score of 60 and calls a normal day "Good". It also sets
Green at 70 or more and says Yellow blocks weight increases. Taken literally, an ordinary day
would block progression. Resolution, agreed with the owner: keep the score mapping and shift
the bands to **Green ≥ 55, Yellow 40–54, Red < 40**. The thresholds live in
`ReadinessCalculator` as constants.

## Score mapping is piecewise linear
"Clamp z to [-2, 2], map linearly to 0–100 with 0 → 60" can't be a single straight line. So the
mapping is z ∈ [-2, 0] → 0..60 (30 points per SD) and z ∈ [0, 2] → 60..100 (20 points per SD).

## Package versions
`cached_network_image` 4.0.4 and `intl` 0.20.3 need Dart 3.13. `build_runner` 2.16 needs a
`meta` version newer than the one Flutter 3.44 pins. So I pinned the newest versions this SDK
can resolve: 4.0.3, 0.20.2 and 2.15.1.

## "Weight up while e1RM down" requires an override
A normal double-progression step (all sets at the top of the range → +1 increment, reps reset to the
bottom) lowers e1RM by construction: 80×10 @ RPE 8 is 106.7 kg, the next session's 82.5×6 @ RPE 8 is
104.5 kg. Read literally, the second ego trigger flagged ordinary coach-led progression. It now also
requires that at least one of the two later sessions in the window contains override sets, so it only
fires when the lifter pushed the weight up themselves.

## Technique days are not the progression base
A Red "technique day" cuts load for recovery, not because of performance. The spec applies the
readiness modifier *after* progression, so the next session progresses from the last normal
(non-technique) session. Otherwise every Red day would cost two or three sessions of climbing back.

## Muscle mapping gaps
The dataset's `lower back`, `adductors` and `neck` have no ranking group (the spec defines back as
lats + middle back). `abductors` count towards glutes. Ranked lifts can override their groups in
`assets/strength_standards.json`. The deadlift, for example, ranks back, hamstrings and glutes as
primary, even though the dataset lists lower back as its primary muscle.

## Training-load modifier counts primary groups only
Working sets count towards an exercise's primary groups. The 4-week average uses the 28 days before
the current 7-day window, and "exceeds 1.5×" is strict (>).

## Calibration sets have no suggested weight
A calibration session ramps the weight freely, so its sets carry no suggested weight. That means no
override detection and no "followed the suggestion" XP bonus. They still earn the base 10 XP per set.

## PRs need a previous best
The first session of an exercise sets its baseline and isn't a PR. Otherwise every calibration
session would hand out +50 XP per exercise.

## Quests award XP
The spec's XP list doesn't mention quests. A completed weekly quest gives +40 XP so quests have a
reward. This is defined in `XpRules.perQuest`.

## Ego freeze base weight
The freeze's −5% is taken from the weight the coach suggested in the flagged session (or that
session's top weight if there was no suggestion). It's fixed for the 7 days, so it doesn't compound.

## Extra equipment increments
Besides barbell 2.5, dumbbell 2 and machine/cable 2.5, kettlebells use 4 kg and added load on
bodyweight lifts uses 2.5 kg. Both are editable in Settings.

## v2 phase 0: overall rank and volume
- **Overall rank.** Overall was already the mean of the group scores on the continuous scale. In
  the reported screenshot it was right: six groups (biceps, forearms, abs, quads, hamstrings,
  calves) were Silver, which averaged to 2.994 = Silver I. The real defect was at boundaries: a
  score exactly on a division threshold, or an average of identical scores that lost a floating-point
  ulp, could floor into the previous division. Tier and division floors now use a 1e-9 epsilon, and a
  test checks every tier/division (including exact boundaries) round-trips: all groups at X Y →
  overall X Y.
- **Volume.** One pure formatter (`lib/core/domain/format.dart`) is used everywhere: whole kg with
  thousands separators below 10,000 kg ("6,763 kg"), then tonnes with one decimal ("15.6 t").

## v2 phase 1: League-style ladder
- **Tiers:** Iron, Bronze, Silver, Gold, Platinum, Emerald and Diamond each have divisions IV → I.
  Master, Grandmaster and Challenger are apex tiers with no divisions.
- **One continuous scale:** 1 point per division, so Iron IV = 0 … Diamond I = 27, Master = 28,
  Grandmaster = 32 and Challenger = 36 (uncapped). Exercises, groups and overall all use it, so
  averaging and mapping back is exact.
- **LP:** 0–100 within a division, linear between that division's thresholds. Apex tiers show LP above
  the Master threshold, uncapped (100 LP per point). Challenger keeps the Grandmaster→Challenger slope.
- **Thresholds** (e1RM ÷ bodyweight at which each tier starts) are derived from five anchor standards
  per lift, stored in `assets/strength_standards.json` under `anchors`:
  Iron 0 · Bronze = beginner · Silver = novice · Gold = ½(novice + intermediate) ·
  Platinum = intermediate · Emerald = intermediate + ⅓(advanced − intermediate) ·
  Diamond = intermediate + ⅔(advanced − intermediate) · **Master = advanced** ·
  Grandmaster = ½(advanced + elite) · **Challenger = elite**.

  | Lift | beginner | novice | intermediate | advanced | elite |
  |---|---|---|---|---|---|
  | Bench press | 0.50 | 0.75 | 1.00 | 1.50 | 2.00 |
  | Back squat | 0.75 | 1.25 | 1.50 | 2.25 | 2.75 |
  | Deadlift | 1.00 | 1.50 | 2.00 | 2.50 | 3.00 |
  | Overhead press | 0.35 | 0.55 | 0.75 | 1.00 | 1.25 |
  | Barbell row | 0.50 | 0.75 | 1.00 | 1.50 | 1.75 |
  | Pull-up (BW + added) | 1.00 | 1.15 | 1.35 | 1.60 | 1.85 |
  | Dips (BW + added) | 1.00 | 1.20 | 1.50 | 1.80 | 2.10 |

  For example, bench press now reads: Platinum at 1.0×BW, Master at 1.5×BW, Challenger at 2.0×BW.
- **Migration:** ranks are never stored. They're computed from logged sets whenever shown, so all
  existing history re-ranks on the new ladder automatically. The only persisted rank-dependent state is
  achievements (`bestExerciseTier`, by tier index). Silver, Gold and Platinum keep their indices.
  `migrateRankLadder` runs once at startup (setting `rank_ladder_version` = 2): it keeps everything
  already earned and unlocks rank achievements the new ladder now qualifies for. Two new ones were
  added: Diamond and Master.

## v2 phase 2: rank emblems
- The emblems are original vector art drawn in code (`rank_badge.dart`, a CustomPainter), built from
  generic primitives: shield, chevrons, hexagonal gem, blades, feathered wings, crown, halo. Nothing
  was traced or copied from Riot's or Liftoff's artwork.
- **Escalation:** Iron and Bronze are matte shields with bars. Silver and Gold are metallic gradients
  with a rim and chevrons. Platinum and Emerald add a gem inset with side blades. Diamond is a crystal
  body with facets and wings. Master, Grandmaster and Challenger add a crown, a halo and an animated
  glow plus shimmer; Challenger also gets rays.
- **Sizes:** small (list rows), medium (cards), hero (rank screen, rank-up).
- **Rank-up:** a full-screen sequence (fly-in, burst, title) of 2.6 s, skippable, with a heavy haptic
  on impact. It plays when an exercise, group or overall rank moves to a better division or tier. A
  first placement isn't a rank-up. Rank-downs appear as one muted line in the summary.

## v2 phase 3: anatomical body graph
- **Source:** muscle paths from
  [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter) v3.2.0,
  **MIT License**, © 2022 ELABBASSI Hicham. I checked the LICENSE file in the repo; a copy is in
  `docs/licenses/`. The TypeScript path arrays were converted to `assets/body_map.json` without
  changing the paths. They're parsed at runtime with `path_parsing` 1.1.0.
- **Mapping** (`body_regions.dart`):
  - Ranked: chest; abs + obliques → abs; biceps; triceps; forearm → forearms; deltoids → shoulders;
    trapezius → traps; upper-back → back; gluteal → glutes; quadriceps → quads;
    hamstring → hamstrings; calves.
  - Neutral (drawn, never ranked): adductors, lower back, neck, tibialis.
  - Silhouette: head, hair, hands, feet, knees, ankles.
- **Glow:** from Platinum up, stronger for higher tiers.
- **Volume mode:** working sets in the last 7 days ÷ the weekly average of the 28 days before (primary
  groups, the same windows as the readiness load modifier). Under-trained < 50 %, below usual < 85 %,
  on track ≤ 150 %, high > 150 %.
- **Gap to next division:** for each contributing lift, the e1RM it would need, with the others
  unchanged, for the group's weighted average to reach the next division. The sheet shows the
  smallest increase.
- **Deep links:** the Progress route takes `?tab=`, `?back=1`, `?mode=volume` and `?group=<name>`. These
  also make the states reachable for review screenshots on a headless simulator.

## v2 phase 4: exercise tutorials
- **ExerciseDB V1, license.** The GitHub repo `ExerciseDB/exercisedb-api` is **AGPL-3.0**. That covers
  the code, and since November 2025 the repo holds only a README and the LICENSE (the history was
  rewritten). The V1 dataset is served at `https://oss.exercisedb.dev/api/v1` (1,500 exercises, 180p
  GIFs on `static.exercisedb.dev`). Its OpenAPI description states no data or media license. ExerciseDB's
  public descriptions of V1 say "free, **non-commercial use only, attribution required**". I treated
  that as the governing term:
  - Spotter is a personal, non-commercial app that isn't distributed.
  - Only the metadata is bundled: `assets/exercisedb_v1.json`, fetched 2026-10-12, with no instructions
    and no media.
  - GIFs are downloaded on first view and cached on the device.
  - Every demo is credited "3D demo: ExerciseDB", and so is the README.

  If the app is ever distributed or monetised, this must be revisited: V1's terms don't allow
  commercial use, and ExerciseDB sells commercial licences.
- **IDs unchanged.** The free-exercise-db library and its IDs stay the source of truth. ExerciseDB is
  only a media source, joined through the new `media_matches` table (schema v2).
- **Matching** (`media_matcher.dart`, pure Dart):
  - Score = 0.6 × name + 0.25 × equipment + 0.15 × target muscle.
  - Name: names are normalised (lowercase; phrase fixes such as pullups → pull up and military press
    → shoulder press; plurals; stop-words), then compared as 0.7 × IDF-weighted token Dice + 0.3 ×
    character-trigram Dice.
  - Equipment: 1 = compatible, 0.6 = compatible but needs extra kit, 0 = different, 0.5 = unknown.
  - Muscle: 1 = their target is one of our primary muscles, 0.7 = one of our secondary muscles.
  - Confidence: ≥ 0.72 high, ≥ 0.5 low (used, but listed for review), below that no demo.
  - On the full library: 566 high, 222 low and 88 none before overrides. With overrides, 786 of 876
    exercises have a demo.
- **Overrides.** `assets/media_overrides.json` holds manual fixes, and `null` means "no faithful demo":
  V1 has no face pull and no barbell hip thrust, so those show library photos. Picks made in the
  debug "Media matching" screen are stored with `source = manual`, survive re-matching, and can be
  copied out in the same JSON format.
- **3D player.** The GIF is decoded into frames and driven by a ticker. That allows play/pause and 0.5×,
  which Flutter's `Image` can't do. Cached with `flutter_cache_manager` (1-year stale period). Every
  exercise in a routine is prefetched at launch and whenever routines change.
- **YouTube.** Pinned videos are stored per exercise (`pinned_videos`, with a start time) and play
  in-app via `youtube_player_iframe`. In-app search uses the YouTube Data API v3 only when you've
  stored a key. The key lives in the iOS Keychain (`flutter_secure_storage`), never in the DB or the
  exports. Without a key, you paste a link (watch, youtu.be, shorts or embed; `t=` is kept).
- **Network.** The only calls are GIF and image downloads, YouTube embeds, and the optional
  YouTube search.
- **Schema v2** adds `media_matches` and `pinned_videos`. The migration is tested with drift's schema
  verifier: `drift_schemas/` holds the v1 and v2 dumps, and `test/generated_migrations/` the helpers.

## v2 phase 5: UI overhaul
- `docs/DESIGN.md` is the source of truth for tokens and components. Code: `AppColors` / `AppType` /
  `Space` / `Radii` / `Motion` in `app_theme.dart`; components in `core/widgets/game_ui.dart`.
- **Fonts:** Oxanium for display, numbers and ranks; Barlow for UI text. Both are SIL OFL, bundled
  locally, licences in `docs/licenses/`.
  - Chakra Petch was tried first and dropped: its digits are proportional (advance widths 382–652), so
    changing weights and timers would jitter.
  - Oxanium's ten digits share one width (578 units), which makes them tabular by construction. Only
    the variable font is published, so static SemiBold/Bold/ExtraBold instances were cut with
    fontTools' `varLib.instancer`.
- **Page transitions:** iOS keeps the native slide with edge swipe-back, which matters for one-handed
  use; Android uses fade-forwards. Celebration routes fade in.
- **Swipe to complete:** a `Dismissible` that never dismisses. The swipe calls complete and the row
  re-renders from the DB as done. An override set never completes from a swipe or the check: it opens
  the set sheet, because RPE and a reason are mandatory. Long-press a row for the full editor
  (warm-up, delete).
- **Debug-only preview routes** for reviewing states a headless simulator can't tap into:
  `/settings/debug/badges`, `/settings/debug/rank-up-preview`, `/settings/debug/summary-preview` and
  `/settings/debug/media`. They aren't registered in release builds.
- **Screenshots** for every visual phase are in `docs/screenshots/v2/`. They were taken on the iPhone 17
  Pro simulator with the seeded database (`p2_*` badges, `p3_*` body map, `p4_*` tutorials, `p5_*`
  overhaul).

## v2.1 sections 1–2: Min-Max Phase 2 program and your routines
- **Extraction.** The program is extracted into `assets/programs/min_max_phase2.json` by a repeatable
  script (`tool/program/extract_min_max.py`) from your personal PDF. The PDF is never committed:
  `private/` and `*.pdf` are git-ignored. It was verified by an independent second parse (0 mismatches
  across 444 slot-weeks) plus visual checks. See `docs/program/EXTRACTION_REPORT.md` and `SCHEMA.md`.
- **Routines are data** (`assets/programs/my_routines.json`): your order, names and set counts, with
  each row pointing at the program slot(s) it takes its prescription from.
  - A row can span several slots (e.g. Chest Press = 2×4–6 + 1×20).
  - They install automatically on first launch, replacing the demo routines. Settings → Program →
    "Reinstall my Min-Max routines" does it again.
- **Schema v3** adds:
  - the program day on routines;
  - program slots, relation, program exercise and your display name on routine rows;
  - program slots, program week and display name on session exercises;
  - **per-set** target rep range, target RIR and technique on sets.
  - The v1→v3 and v2→v3 migrations are tested with drift's schema verifier.
- **Per-slot suggestions.** A row spanning two slots gets one suggestion per slot. Suggestions only use
  history done at that slot's rep range (`TrainingHistory.logsForRange`), so a 1×20 back-off set never
  reads as "top of the 4–6 range reached".
- **Warm-ups.** Generated from the program's pyramid at the start of each exercise, as % of today's
  suggested working weight, rounded to the increment. The count defaults to the upper bound of the
  printed range. There are none on a calibration (ramp-up) session.
- **Assisted exercises.** Assistance is logged as negative weight, and effective load = bodyweight +
  weight. Every percentage change (−5% failure, −10% plateau or Red day, −5% freeze, calibration seed)
  is applied to the effective load and converted back. This fixed a real bug: "top working weight"
  folded from 0 and broke on all-negative sets.
- **Bodyweight-loaded lifts** now include the machine assisted pull-up, the band assisted pull-up and
  back extensions (`load_kinds.dart`).
- **Library additions.** Seven exercises missing from free-exercise-db are bundled as built-ins
  (`assets/extra_exercises.json`, ids `sp_*`). The exercise dataset version is bumped to 2.
- **Rest timer.** Uses the upper bound of the printed rest. A rest of 0 (the first exercise of a
  superset) doesn't start the timer.
- **Seed generator.** It now uses your five routines on the program's weekly layout, with the program
  week advancing and override episodes on Chest Press and Pendulum Squat.
  - Each lift is now trained once a week, so an episode spans two weeks to reach the "2 of 3 sessions"
    ego trigger.
  - The seed test's e1RM-trend check expects a gain rather than +5%.

## v2.1 review answers
- **Face Pull** was removed from the Pull routine (you add exercises freely). **Back Extension** is
  confirmed: 1 × 30 to failure via the 45° Hyperextension substitution.
- **No week plan.** Every session uses the program's standard hard week (`standardProgramWeek = 2`):
  full effort, no intro/deload easing, no automatic Block 2 techniques. You add techniques by hand.
  The week stepper and the week labels were removed.
- **Warm-ups.** The higher count for the day's first exercise and for compounds, the lower count for
  everything else (`warmupCountFor`).
- **Planned rest days.** Wednesday and Sunday come from the program's weekly layout. A Red day that
  falls on a planned rest day isn't counted as smart rest (it never lowers the goal), and the streak
  dots show those days as planned rest. Installing the routines sets the weekly goal to the program's
  5 sessions.

## Phase F: Train flow on the phone
- **Error log.** `FlutterError.onError`, `PlatformDispatcher.onError` and the app's own recovering
  catch blocks write to a persistent log (Application Support/`error_log.jsonl`, last 300 entries),
  with timestamp, error, stack and current route. Open it from Settings by long-pressing the version
  label (release builds too); it has Copy all and Clear.
- **Tap-driven integration tests** (`integration_test/`) run on the simulator against a fresh install
  (and an upgraded one) with only your routines. Each flow fails if anything lands in the error log.
- **Routines install before the first frame** (`bootstrapDatabase`, shared by `main()` and the tests).
  They used to be installed in a post-frame chain behind notification setup and the rank-ladder
  migration. On an upgraded install that chain took more than 9 s, so the old routines stayed on Train,
  and if any earlier step threw, the new routines were never installed. A newer `my_routines.json`
  version now reinstalls them.
- **Independent startup steps.** Notification setup, Health refresh and the rank-ladder migration each
  run on their own and log their own failures.
- **Readiness card.** With no recovery data it collapses to one line, so Resume/Start stays above the
  fold.
- **Dead ExerciseDB GIFs.** 176 of 1,500 V1 GIF URLs return HTTP 404. They're flagged in the asset and
  never matched (the media match version is bumped, so matches are recomputed on launch; manual picks
  are kept). Four overrides pointed at dead GIFs and now point at live duplicates. A GIF that still
  fails to load at runtime falls back to the library photos.
- **Replace exercise.** In the workout menu, replacing offers the program's exercise and its
  substitutions first, resolved to library exercises by `ExerciseNameResolver` (exact name, then
  token similarity), then library search. The replacement keeps the slot's prescription and set count.

## v2.1 section 3: Liftoff import

**What the owner's export contains** (`liftoff_workout_data.csv`, 1,692 rows, 19 Apr → 11 Oct 2026):

- **Workout Name is always empty.** A session is the set of rows sharing one exact `Date` timestamp.
  That timestamp is also the session's `external_id`, which makes re-imports idempotent (unique index
  on `sessions(source, external_id)`, schema v4).
- **129 Date values → 124 strength sessions on 117 days.** Five Date values hold only rows the importer
  skips: four Walking entries and one empty 18-second workout with no exercise. Five days have extra
  short sessions (for example a 1-minute Side Leg Raise or Hand Grippers entry hours after the main
  workout). They're kept as separate sessions, as Liftoff recorded them.
- **Set Order is 0-based and consecutive** per exercise within a session. There is no warm-up flag, so
  every imported set is a working set.
- **Weights are in pounds** and are exact conversions of kg loads at Liftoff's factor (2.20462262).
  As specified, the importer divides by 2.20462, so 20 kg arrives as 20.0000238 kg. It's stored at full
  precision and displayed rounded to 0.5 kg; multiples of 0.25 kg display exactly. Rounding helpers and
  suggestions absorb that noise (`snapNoise`, 0.001 increment tolerance), so 30 kg of assistance stays
  30 kg rather than flooring to 32.5. Two loads aren't whole quarters in kg either way: 7.2 and 22.2 kg.
- **Assisted machines** (Assisted Pull Ups, Assisted Dips) log the assistance as a positive weight.
  They're imported as negative loads (−30 = 30 kg of help), the same convention the app already uses.
  A machine Assisted Dip exercise (`sp_assisted_dip_machine`) was added for them.
- **Bodyweight exercises** have weight 0. **Cardio and timed rows** (Walking: distance and 2,400 s;
  Dead Hang: 30 s, 0 reps) are skipped and listed in the preview.
- **RPE is filled on 1 row (RPE 8).** Every other imported set is logged as RPE 10, i.e. taken to
  failure, as specified.
- **Notes hold the rep scheme**, written once per exercise and repeated on each row: `10-12`, `6-8/8-10`,
  `2*6-8/20` (two sets of 6–8 then one of 20), `20/10`, `10 per leg`, with an optional trailing
  technique letter (`6-8   D`, `4-6.  M`, `10-12   H`) or `Pause` / `Failure`. Each set gets its own
  target range from the scheme (the last range repeats for extra sets). The first range becomes the
  exercise range. With no note, the range is the reps actually done. The raw note is kept in the
  exercise notes; technique letters aren't interpreted.

**Name mapping.** Order: a manual pick in the preview → `assets/liftoff_name_map.json` (a library id, or
a `custom` definition that creates a stable `liftoff_<name>` exercise) → your routine names
(punctuation- and plural-insensitive, so "Chest Supported T Bar Row" = "Chest Supported T-Bar Row") →
exact library name → fuzzy token match ≥ 80 % → unmatched. An unmatched name becomes a custom exercise
of the same name unless you pick one. Fuzzy matches under 90 % and unmatched names are listed under
"Check these" in the preview. All 114 names in the export resolve with no manual picks; 13 become
custom exercises. Liftoff names whose loads aren't comparable never share one exercise (dumbbell vs
barbell RDL, machine vs barbell hip thrust, one-arm vs two-arm reverse fly, cable vs machine
abduction, standing vs kneeling cable crunch). Otherwise one history would mix 37.5 kg dumbbells with
an 85 kg barbell. Three near-identical pairs do share one: Cable Fly + High to Low Cable Fly, Machine
Lateral Raise + Standing Machine Lateral Raise, Seated Cable Row + Wide Grip Seated Cable Row. The full
mapping is in `docs/IMPORT_SUMMARY.md`.

**What imported sessions count for.** They're finished sessions with `source = 'liftoff'`, named after
the routine they share most exercises with ("Liftoff workout" otherwise). Sets carry no suggested
weight and no override flag, so they never enter discipline, override or ego statistics, and the
sessions earn no XP. They do count for history, PRs, ranks, streak days and the training-load
modifier. Achievements are re-evaluated once after the import, without XP. `liftoff_imported_at` is
saved for the section 4 streak offset.

**Suggestions after an import** build on recent performance, never the all-time best:

- Progression uses the last session at the slot's rep range; the plateau check uses the last three.
- When none of your recent sets was at that range (for example a 4–6 slot after 10–12 work in
  Liftoff), the load is re-anchored from the best e1RM of the **last 3 sessions**:
  e1RM ÷ (1 + (bottom of range + RIR) / 30).
- All-time bests are only used for PRs and history.

**Progression rules moved here from section 7.** Treating every imported set as failure broke the old
rules: an RPE 10 set meant −5 %, and an increase required RPE ≤ 8. That would have cut every imported
lift. The new rules:
- A set taken to failure is never a failed set; only missing the bottom of the range is (−5 %).
- The top of the range at the prescribed effort (RPE ≤ 10 − target RIR, so failure counts when the
  program prescribes failure) → +1 increment.
- Within the range → same load, beat the reps.
- An increase is exactly one increment above what was lifted. It no longer snaps to a 2.5 kg grid,
  which turned +2.5 kg on a 4 kg cable into +3.5 kg.
- The plateau rule is unchanged.
- The seeded-history test now checks that the main working weight trends up rather than the e1RM. The
  simulated lifter stops at the top of the range +2 reps and logs an honest low RPE when the load is
  light, so its e1RM estimates were too noisy to compare.

**Machine and cable lifts are over-ranked by the current standards.** For example, triceps pushdown at
72 kg × 12 comes out as Challenger. The import therefore unlocked the Diamond and Master rank
achievements. Section 8 replaces the standards with machine- and cable-specific ones and should revoke
rank achievements that are no longer earned.
