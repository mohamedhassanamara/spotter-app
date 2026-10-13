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

## Section 3 follow-ups (owner review)

- **Shoulder Press** in Liftoff covered two pieces of equipment. The name map now picks per session
  from the session's top weight: 80 kg and up is **Machine Shoulder Press**
  (`Machine_Shoulder_Military_Press`); anything lighter is **Barbell Shoulder Press**
  (`Barbell_Shoulder_Press`). In the export every Shoulder Press session was 20–30 kg, so all of them
  import as barbell.
- **Cable Kickback** maps to the glute kickback and is imported **hidden from ranks**.
- **Hide from ranks** is a general feature: Exercise page → *Count toward ranks*. A hidden exercise
  keeps its records (history, PRs, volume) but never feeds a rank. The setting is
  `rank_excluded_exercises`, and a name-map entry can set it with `"exclude_from_ranks": true`.
- **Bodyweight on import.** Apple Health sync now stores every weigh-in from the last year, not only
  the latest, so section 8 can rank each set against the bodyweight of its day (as Liftoff does). If no
  bodyweight is known when you import, the app asks for it instead of assuming one. The summary
  generator has no default either: `LIFTOFF_BW` is required, either as one weight or as weigh-ins
  (`108@2026-04-19,106@2026-10-11`).
- **Bug fixed along the way.** The number and text prompts disposed their text controller while the
  dialog was still animating closed. That threw "TextEditingController was used after being
  disposed", for example from the Settings bodyweight prompt. The dialog now owns its controller.

## v2.1 section 8: 20 muscles, 6 regions, per-exercise strength standards

**Model.** The 12 flat groups are gone. Ranking, the body graph, the volume heatmap and the
training-load modifier use 20 muscles in 6 regions (`lib/core/domain/muscles.dart`):
- **Arms:** Biceps, Triceps, Forearms.
- **Legs:** Quadriceps, Hamstrings, Glutes, Calves, Adductors, Abductors.
- **Core:** Abdominals, Obliques.
- **Shoulders:** Front, Middle and Rear Delt.
- **Chest:** Upper and Lower Chest.
- **Back:** Lats, Upper Back, Traps, Lower Back.

Weekly quests ("Train back twice") use the regions; quests stored with an old group name map to their
region. Media matching keeps its own private coarse grouping, so 3D demo matches didn't change.

**Exercise → muscle contributions.**
- `assets/exercise_muscles.json` is hand-authored for all 111 exercises in my routines and Liftoff
  history. Its source is `tool/standards/exercise_data.py`; `python3 tool/standards/build.py` checks
  it and writes the asset.
- Every other library exercise derives its contributions: dataset primary muscles at 1.0, secondary at
  0.3, split by name keywords:
  - incline → Upper Chest; decline/dip → Lower Chest; flat → Lower 1.0 + Upper 0.6;
  - lateral raise/upright row → Middle Delt; reverse fly/face pull → Rear Delt; presses → Front Delt
    1.0 + Middle 0.5; shoulders as a helper in rows → Rear Delt;
  - twist/side bend/wood chop/Pallof → Obliques.
- A muscle counts as *primary* (for volume, the load modifier and quests) at a contribution of 0.5 or
  more.

**Strength score.**
- Each valid working set gets a score from 0 to 1000: its e1RM ÷ the bodyweight **on the day of the
  set**, placed against that exercise's standard. The score is 25 per division point, so Iron IV = 0,
  Master = 700, Grandmaster = 800, Challenger = 900, and 1000 is the cap.
- Bodyweight between weigh-ins is interpolated linearly. Apple Health sync now stores a year of
  weigh-ins, so a set from April counts at April's 108 kg, not today's 106 kg (as in Liftoff).
- For scoring, reps + reps in reserve count at most 20. Epley inflates very long sets: 30
  bodyweight back extensions would otherwise read as a 2.0× bodyweight "1RM".

**Rank levels.**
- **Exercise:** the best set score of the last 90 days. Ranks are per exercise now, not per standard,
  so Close-Grip and V-Bar pulldowns rank separately even though they share a standard.
- **Muscle:** the average of its exercises' best scores, weighted by each exercise's contribution to it.
- **Region:** the average of its ranked muscles, shown as "X/Y ranked".
- **Overall:** the average of the ranked regions.
- Same tier ladder and LP as v2.
- Exercises hidden from ranks never contribute.
- An unranked muscle lists the exercises from my routines and history that train it at ≥ 0.5, or
  says none do.

**Standards (`assets/strength_standards.json` v3).**
- Each standard has five anchors as e1RM ÷ bodyweight (beginner, novice, intermediate, advanced,
  elite) for a male lifter around 100 kg. They're calibrated per exercise from commonly published 1RM
  standards; my own numbers were never used to set them.
- Tier entry points:

  | Tier | Starts at |
  |---|---|
  | Iron | 0 |
  | Bronze | beginner |
  | Silver | novice |
  | Gold | midpoint of novice and intermediate |
  | Platinum | intermediate |
  | Emerald | midpoint of intermediate and advanced |
  | Diamond | advanced |
  | **Master** | **elite** |
  | **Grandmaster** | **elite × 1.15** |
  | **Challenger** | **elite × 1.30** |

  v2 put Master at "advanced" and Challenger at "elite". That made the apex tiers reachable by good
  gym numbers. Now Master already requires the elite anchor, and Grandmaster and Challenger require
  numbers beyond it.
- **Machines and cables** have their own standards (pec deck, machine chest press, pendulum squat,
  pushdowns…), never barbell ones. Their anchors are multiplied by **`machine_strictness` = 1.10**,
  because stacks, cams and pulleys vary between gyms and flatter the number on the pin.
- Bodyweight movements (crunches, back extensions, side leg raises…) use bodyweight-inclusive e1RM
  anchors. With the 20-rep cap, their advanced and elite anchors need added load.

**Sanity check with the real import** (`test/tool/import_summary_test.dart`, at 108 → 106 kg):
- No exercise ranks above Diamond. The test fails if one does, unless it's listed with a
  justification in this section; none are.
- The top lift is Walking Lunge at Diamond III (35 kg × 10 per leg). It's on the per-dumbbell
  standard, so if Liftoff's 35 kg meant both dumbbells together, it's over-ranked by about one tier.
  Flagged to the owner.
- Overall is Silver I. The full table is in `docs/IMPORT_SUMMARY.md` under "Rank sanity check".

**Liftoff per-leg reps.** Walking Lunge sets noted "10 per leg" were logged in Liftoff as 20 reps
(both legs). With a per-leg scheme, a set at 1.5× the target or more is now imported as reps per leg
(20 → 10), the way the app logs lunges.

**Revoking badges from the old standards** (rank model v3, `ladder_migration.dart`):
- Rank achievements (type `bestExerciseTier`) unlocked under the old standards are deleted when the
  new standards don't support them. It's silent: no notification and no rank-down animation.
  Rank changes are always computed before and after a session with the same standards, so a
  rank-down never appears.
- Achievements of every other type stay.
- If no bodyweight is known yet, nothing is revoked and the migration waits, so a missing bodyweight
  can't take badges away.
- Rank badges the new standards qualify for are unlocked.

**Body graph.** All 20 muscles are tappable on the anatomical map (react-native-body-highlighter
paths), split at load time:
- Pecs: the top 45 % is Upper Chest, the rest Lower Chest.
- Deltoids: the outer 40 % is Middle Delt; the rest is Front Delt (front view) or Rear Delt (back view).
- The back's upper-back paths: the tall piece is Lats, the two upper pieces Upper Back.
- Gluteal: the small upper piece (glute medius) is Abductors.
- Lower back, adductors and obliques are now ranked muscles, no longer drawn neutral.

The Ranks tab shows collapsible regions. Each muscle row has a thumbnail of the body with that
muscle highlighted, its badge, division and LP.

### Anchor values (v3, superseded by the v4 calibration below)

Anchors are e1RM ÷ bodyweight. Per side means per dumbbell, per arm or per leg. The last column is the
Master entry after machine strictness.

| Standard | Kind | Per side | Beginner | Novice | Intermediate | Advanced | Elite | Master entry (after strictness) |
|---|---|---|---|---|---|---|---|---|
| Back squat | free |  | 0.75 | 1.05 | 1.4 | 1.85 | 2.35 | 2.35 |
| Barbell calf raise | free |  | 0.5 | 0.8 | 1.15 | 1.55 | 2 | 2.00 |
| Barbell lunge | free |  | 0.4 | 0.6 | 0.85 | 1.15 | 1.45 | 1.45 |
| Barbell reverse wrist curl | free |  | 0.12 | 0.2 | 0.32 | 0.46 | 0.62 | 0.62 |
| Barbell row | free |  | 0.45 | 0.65 | 0.9 | 1.2 | 1.5 | 1.50 |
| Barbell wrist curl | free |  | 0.2 | 0.35 | 0.55 | 0.8 | 1.05 | 1.05 |
| Bench press | free |  | 0.6 | 0.85 | 1.15 | 1.5 | 1.9 | 1.90 |
| Close-grip dumbbell press | free | yes | 0.15 | 0.23 | 0.33 | 0.45 | 0.58 | 0.58 |
| Deadlift | free |  | 0.9 | 1.25 | 1.6 | 2.1 | 2.6 | 2.60 |
| Dumbbell Romanian deadlift | free | yes | 0.2 | 0.32 | 0.48 | 0.66 | 0.85 | 0.85 |
| Dumbbell bench press | free | yes | 0.2 | 0.3 | 0.42 | 0.57 | 0.73 | 0.73 |
| Dumbbell calf raise | free | yes | 0.15 | 0.25 | 0.38 | 0.55 | 0.72 | 0.72 |
| Dumbbell curl | free | yes | 0.09 | 0.14 | 0.21 | 0.3 | 0.4 | 0.40 |
| Dumbbell lateral raise | free | yes | 0.05 | 0.09 | 0.14 | 0.2 | 0.27 | 0.27 |
| Dumbbell lunge | free | yes | 0.1 | 0.18 | 0.28 | 0.4 | 0.52 | 0.52 |
| Dumbbell reverse fly | free | yes | 0.04 | 0.08 | 0.13 | 0.19 | 0.26 | 0.26 |
| Dumbbell reverse wrist curl | free | yes | 0.05 | 0.08 | 0.12 | 0.17 | 0.23 | 0.23 |
| Dumbbell row | free | yes | 0.2 | 0.32 | 0.48 | 0.66 | 0.86 | 0.86 |
| Dumbbell shrug | free | yes | 0.2 | 0.35 | 0.55 | 0.78 | 1.02 | 1.02 |
| Dumbbell side bend | free | yes | 0.15 | 0.25 | 0.38 | 0.52 | 0.68 | 0.68 |
| Dumbbell split squat | free | yes | 0.08 | 0.15 | 0.24 | 0.34 | 0.45 | 0.45 |
| Dumbbell wrist curl | free | yes | 0.08 | 0.13 | 0.2 | 0.29 | 0.38 | 0.38 |
| EZ-bar curl | free |  | 0.25 | 0.38 | 0.52 | 0.7 | 0.9 | 0.90 |
| Hammer curl | free | yes | 0.09 | 0.14 | 0.21 | 0.3 | 0.39 | 0.39 |
| Hand gripper | free |  | 0.2 | 0.35 | 0.55 | 0.8 | 1.1 | 1.10 |
| Hip thrust | free |  | 0.6 | 1 | 1.5 | 2.1 | 2.8 | 2.80 |
| Incline Y raise | free | yes | 0.04 | 0.065 | 0.1 | 0.14 | 0.19 | 0.19 |
| Incline bench press | free |  | 0.5 | 0.7 | 0.95 | 1.25 | 1.6 | 1.60 |
| Incline dumbbell curl | free | yes | 0.08 | 0.12 | 0.18 | 0.26 | 0.35 | 0.35 |
| Incline dumbbell press | free | yes | 0.18 | 0.27 | 0.38 | 0.52 | 0.67 | 0.67 |
| Incline hammer curl | free | yes | 0.08 | 0.12 | 0.18 | 0.26 | 0.35 | 0.35 |
| Overhead press | free |  | 0.38 | 0.52 | 0.7 | 0.92 | 1.17 | 1.17 |
| Preacher curl | free | yes | 0.08 | 0.12 | 0.18 | 0.26 | 0.34 | 0.34 |
| Romanian deadlift | free |  | 0.6 | 0.9 | 1.25 | 1.65 | 2.05 | 2.05 |
| Seated dumbbell press | free | yes | 0.13 | 0.2 | 0.3 | 0.41 | 0.53 | 0.53 |
| Skull crusher | free |  | 0.2 | 0.32 | 0.48 | 0.66 | 0.88 | 0.88 |
| Stiff-leg deadlift | free |  | 0.6 | 0.9 | 1.25 | 1.65 | 2.05 | 2.05 |
| Supine dumbbell press | free | yes | 0.12 | 0.19 | 0.28 | 0.38 | 0.5 | 0.50 |
| T-bar row | free |  | 0.5 | 0.75 | 1 | 1.3 | 1.65 | 1.65 |
| Chest-supported T-bar row | machine |  | 0.4 | 0.65 | 0.95 | 1.3 | 1.7 | 1.87 |
| Hip abduction machine | machine |  | 0.45 | 0.8 | 1.25 | 1.8 | 2.5 | 2.75 |
| Hip adduction machine | machine |  | 0.45 | 0.8 | 1.25 | 1.8 | 2.5 | 2.75 |
| Leg extension | machine |  | 0.5 | 0.85 | 1.25 | 1.75 | 2.3 | 2.53 |
| Leg press | machine |  | 1 | 1.7 | 2.6 | 3.7 | 5 | 5.50 |
| Leg press calf raise | machine |  | 1 | 1.8 | 2.8 | 4 | 5.4 | 5.94 |
| Lying leg curl | machine |  | 0.35 | 0.58 | 0.85 | 1.2 | 1.6 | 1.76 |
| Machine chest press | machine |  | 0.55 | 0.85 | 1.2 | 1.6 | 2.05 | 2.25 |
| Machine high row | machine |  | 0.45 | 0.72 | 1.05 | 1.42 | 1.85 | 2.04 |
| Machine hip thrust | machine |  | 0.7 | 1.15 | 1.7 | 2.4 | 3.2 | 3.52 |
| Machine incline chest press | machine |  | 0.45 | 0.7 | 1 | 1.35 | 1.75 | 1.93 |
| Machine lateral raise | machine |  | 0.15 | 0.28 | 0.45 | 0.66 | 0.9 | 0.99 |
| Machine row | machine |  | 0.5 | 0.8 | 1.15 | 1.55 | 2 | 2.20 |
| Machine shoulder press | machine |  | 0.4 | 0.65 | 0.95 | 1.3 | 1.7 | 1.87 |
| Machine triceps extension | machine |  | 0.3 | 0.5 | 0.75 | 1.05 | 1.4 | 1.54 |
| One-arm reverse pec deck | machine | yes | 0.1 | 0.19 | 0.3 | 0.44 | 0.6 | 0.66 |
| Pec deck | machine |  | 0.4 | 0.7 | 1.05 | 1.5 | 2 | 2.20 |
| Pendulum squat | machine |  | 0.6 | 1 | 1.5 | 2.1 | 2.8 | 3.08 |
| Reverse pec deck | machine |  | 0.2 | 0.38 | 0.6 | 0.88 | 1.2 | 1.32 |
| Single-leg extension | machine | yes | 0.25 | 0.43 | 0.63 | 0.88 | 1.15 | 1.26 |
| Smith machine bench press | machine |  | 0.6 | 0.85 | 1.15 | 1.5 | 1.9 | 2.09 |
| Smith machine calf raise | machine |  | 0.7 | 1.15 | 1.7 | 2.4 | 3.2 | 3.52 |
| Smith machine shoulder press | machine |  | 0.38 | 0.52 | 0.7 | 0.92 | 1.17 | 1.29 |
| Smith machine squat | machine |  | 0.75 | 1.05 | 1.4 | 1.85 | 2.35 | 2.59 |
| Smith split squat | machine |  | 0.35 | 0.55 | 0.8 | 1.1 | 1.45 | 1.59 |
| Standing calf raise machine | machine |  | 0.7 | 1.2 | 1.8 | 2.6 | 3.5 | 3.85 |
| Cable crunch | cable |  | 0.3 | 0.5 | 0.75 | 1.05 | 1.4 | 1.54 |
| Cable curl | cable |  | 0.2 | 0.33 | 0.5 | 0.7 | 0.95 | 1.04 |
| Cable fly | cable | yes | 0.12 | 0.22 | 0.36 | 0.54 | 0.75 | 0.83 |
| Cable front raise | cable | yes | 0.06 | 0.1 | 0.16 | 0.23 | 0.31 | 0.34 |
| Cable glute kickback | cable | yes | 0.06 | 0.12 | 0.2 | 0.3 | 0.42 | 0.46 |
| Cable hammer curl | cable |  | 0.2 | 0.33 | 0.5 | 0.7 | 0.95 | 1.04 |
| Cable hip abduction | cable | yes | 0.05 | 0.1 | 0.17 | 0.26 | 0.37 | 0.41 |
| Cable lateral raise | cable | yes | 0.035 | 0.065 | 0.1 | 0.15 | 0.21 | 0.23 |
| Cable reverse fly | cable | yes | 0.04 | 0.08 | 0.13 | 0.2 | 0.28 | 0.31 |
| Cable reverse wrist curl | cable |  | 0.12 | 0.2 | 0.32 | 0.46 | 0.62 | 0.68 |
| Cable upright row | cable |  | 0.25 | 0.4 | 0.58 | 0.8 | 1.05 | 1.16 |
| Cable wood chop | cable |  | 0.15 | 0.25 | 0.38 | 0.53 | 0.7 | 0.77 |
| Cable wrist curl | cable |  | 0.2 | 0.35 | 0.55 | 0.8 | 1.05 | 1.16 |
| Close-grip lat pulldown | cable |  | 0.48 | 0.7 | 0.95 | 1.27 | 1.63 | 1.79 |
| Face pull | cable |  | 0.2 | 0.33 | 0.5 | 0.7 | 0.95 | 1.04 |
| Lat pulldown | cable |  | 0.45 | 0.65 | 0.9 | 1.2 | 1.55 | 1.71 |
| One-arm cable curl | cable | yes | 0.1 | 0.17 | 0.25 | 0.36 | 0.48 | 0.53 |
| One-arm cable triceps extension | cable | yes | 0.11 | 0.19 | 0.29 | 0.43 | 0.58 | 0.64 |
| Overhead cable triceps extension | cable |  | 0.2 | 0.35 | 0.55 | 0.8 | 1.1 | 1.21 |
| Pallof press | cable |  | 0.1 | 0.17 | 0.26 | 0.36 | 0.48 | 0.53 |
| Rope pushdown | cable |  | 0.22 | 0.38 | 0.58 | 0.85 | 1.15 | 1.26 |
| Seated cable row | cable |  | 0.45 | 0.68 | 0.98 | 1.33 | 1.73 | 1.90 |
| Standing cable crunch | cable |  | 0.25 | 0.42 | 0.62 | 0.88 | 1.17 | 1.29 |
| Straight-arm pulldown | cable |  | 0.18 | 0.3 | 0.45 | 0.63 | 0.85 | 0.94 |
| Triceps pushdown | cable |  | 0.25 | 0.42 | 0.65 | 0.95 | 1.3 | 1.43 |
| Underhand lat pulldown | cable |  | 0.48 | 0.7 | 0.95 | 1.27 | 1.63 | 1.79 |
| Assisted dip | bodyweight |  | 0.9 | 1.1 | 1.35 | 1.65 | 1.95 | 1.95 |
| Assisted pull-up | bodyweight |  | 0.85 | 1 | 1.25 | 1.5 | 1.75 | 1.75 |
| Back extension | bodyweight |  | 1.27 | 1.4 | 1.53 | 1.75 | 2 | 2.00 |
| Crunch | bodyweight |  | 1.27 | 1.4 | 1.53 | 1.8 | 2.1 | 2.10 |
| Dragon flag | bodyweight |  | 1.07 | 1.17 | 1.27 | 1.4 | 1.55 | 1.55 |
| Hanging leg raise | bodyweight |  | 1.07 | 1.2 | 1.33 | 1.5 | 1.67 | 1.67 |
| Roman chair side bend | bodyweight |  | 1.27 | 1.4 | 1.53 | 1.8 | 2.1 | 2.10 |
| Russian twist | bodyweight |  | 1.27 | 1.4 | 1.53 | 1.8 | 2.1 | 2.10 |
| Side leg raise | bodyweight |  | 1.33 | 1.5 | 1.67 | 1.9 | 2.2 | 2.20 |
| Side lunge | bodyweight |  | 1.2 | 1.33 | 1.5 | 1.67 | 1.9 | 1.90 |
| Side-lying hip adduction | bodyweight |  | 1.33 | 1.5 | 1.67 | 1.9 | 2.2 | 2.20 |

## Rank calibration v4 (owner review after section 8)

**Owner corrections first.**
- **Shoulder Press:** every Liftoff "Shoulder Press" session was a barbell press, so the name maps
  straight to `Barbell_Shoulder_Press`. The weight-threshold rule is gone. The importer still supports
  `by_weight` entries, but none are used.
- **Walking Lunge:** Liftoff's 35 kg was both dumbbells together. Walking lunges (in Liftoff and in the
  app's Lower routine) log the **combined** load, and the lunge is ranked on its own standard, *Dumbbell
  walking lunge*, which uses total load. *Dumbbell lunge* stays per dumbbell. No weights were rewritten.
- **Cable Kickback:** still glute kickback, still hidden from ranks.

**Allometric scaling.**
- Loaded lifts are no longer scored as e1RM ÷ bodyweight. The scaled ratio is:

      scaled ratio = e1RM / (100 kg × (bodyweight / 100 kg)^0.67)

- Strength grows with muscle cross-section, roughly mass^⅔, so the plain ratio penalises heavier
  lifters. DOTS and Wilks correct for the same effect with fitted polynomials; the power law is simpler
  and works for every exercise, not just the three powerlifts.
- At 100 kg the scaled ratio equals the plain ratio. At 106 kg a lift counts about 4 % more than
  before, and at 120 kg about 6 % more.
- Bodyweight-inclusive lifts (pull-ups, dips, crunches, back extensions…) keep e1RM ÷ bodyweight, because
  their load *is* bodyweight and already scales with the lifter.
- The anchors are expressed at the 100 kg reference. The next-division kg targets invert the same
  formula.
- The scaling lives in `strength_standards.json` → `scaling` (`reference_bodyweight`, `exponent`).

**Cross-lift consistency.**
- In v3, accessories had free-standing anchors and isolation work ranked far above the compounds: a
  10 kg Y raise was Emerald II while a 65 × 6 bench was Bronze II.
- In v4, five base compounds carry population standards for a 100 kg male: bench, squat, deadlift,
  overhead press and barbell row. Every other loaded standard is **base × factor**. The factor is the
  typical ratio of that exercise's 1RM to the compound's, from population intermediate numbers, so a
  typical lifter at a given level on the compound sits at about the same level on the accessory.
  Examples:
  - lateral raise ≈ 0.23 × overhead press per dumbbell;
  - pushdown ≈ 0.42 × bench;
  - standing calf machine ≈ 1.20 × squat;
  - leg curl ≈ 0.60 × squat.
- Machine and cable standards also keep the 1.10 strictness.
- `build.py` enforces the rule: only bodyweight-kind standards may have their own anchors. A unit test
  checks that every bundled standard equals its base × factor.
- Fixed from v3 while calibrating, because their anchors didn't follow typical ratios:
  - cable arm work (rope pushdown 0.34, overhead cable extension 0.27, cable hammer curl 0.30, cable fly
    0.16 per side);
  - pendulum squat 0.50 × squat (the sled weight isn't counted, and the lever makes loaded plates far
    lighter than a bar);
  - reverse pec deck 1.00 × OHP;
  - hip abduction and adduction machines 0.70 × squat;
  - reverse dumbbell fly 0.20 × OHP;
  - bodyweight high-rep isolation (crunches, Russian twist, side bend, back extension, side leg raise,
    side-lying adduction): 20 reps, the scoring cap, is now between novice and intermediate (1.40,
    1.60, 1.80, 2.10, 2.40), so more needs added load.
- None of the factors were fitted to my own numbers.

**Spread test with the real import.**
- `test/tool/import_summary_test.dart` fails if the highest and lowest ranked exercises (hidden ones
  excluded) are more than 2 tiers apart, ignoring only the outliers justified below.
- Result: 68 of 77 ranked exercises sit between **Bronze and Gold** (Iron 2 · Bronze 26 · Silver 23 ·
  Gold 19 · Platinum 5 · Emerald 1 · Master 1). Overall is Silver.
- Each item below is a real feature of the data, not calibration. The test also checks that every
  outlier is named here.

### Justified outliers

**Data, not strength.**
- **Triceps Pushdown** (Master, 72 kg × 12). The owner confirmed that 72 kg is correct. The gym's stack
  labels were wrong before 13 Sep 2026 and have since been fixed. The older 24–36 kg sets (and the rope
  and single-arm pushdowns on the same labels) understate the load, so this lift stands far above
  its siblings until they're re-logged on the corrected stack. The older sets are left as recorded.
- **Machine Hip Thrust** (Iron II, 42.5 kg × 12). A new machine since 13 Aug, with 4 sessions at
  35–45 kg. Plate-loaded hip thrust machines differ a lot in leverage.
- **Machine Calf Raise** (Iron, 50 kg × 12). A single session (26 Aug).

**Real strong points.** Each is above the population intermediate level in absolute terms, while the
barbell bench (78 kg e1RM) and squat (108 kg e1RM) are below novice at 106 kg. They rank high because
this lifter is relatively stronger on machines and isolation work than on barbell compounds.
- **Leg Extension** (Platinum, 110 kg × 10, e1RM 147 kg ≈ 1.41 scaled; intermediate is 1.39) and
  **Lying Leg Curl** (Platinum, 85 kg × 7, e1RM 105 kg ≈ 1.01; intermediate 0.92).
- **Sled Press Calf Raise** (Platinum, 240 kg × 12) and **Dumbbell Calf Raise** (Emerald, 37.5 kg per
  dumbbell × 15). Calves are this lifter's strongest group. The Smith calf raise (100 kg × 12, Bronze)
  is the exception, plausibly because of its range of motion.
- **Dumbbell Incline Y Raise** (Platinum, 10 kg per dumbbell × 13) and **One Arm Machine Reverse Fly**
  (Platinum, 25 kg per arm × 20). Delt isolation is well ahead of the presses (Smith shoulder press
  Bronze, seated dumbbell press Gold).

### Standards (v4)

The base compound anchors are e1RM ÷ 100 kg × (bodyweight ÷ 100)^0.67. Machine and cable anchors are
then × 1.10.

| Base compound | Beginner | Novice | Intermediate | Advanced | Elite |
|---|---|---|---|---|---|
| Bench press (`bench`) | 0.6 | 0.85 | 1.15 | 1.5 | 1.9 |
| Back squat (`squat`) | 0.75 | 1.05 | 1.4 | 1.85 | 2.35 |
| Deadlift (`deadlift`) | 0.9 | 1.25 | 1.6 | 2.1 | 2.6 |
| Overhead press (`ohp`) | 0.38 | 0.52 | 0.7 | 0.92 | 1.17 |
| Barbell row (`row`) | 0.45 | 0.65 | 0.9 | 1.2 | 1.5 |

| Standard | Kind | Per side | Base × factor | Intermediate anchor | Elite anchor |
|---|---|---|---|---|---|
| Bench press | free |  | bench press × 1 | 1.15 | 1.9 |
| Smith machine bench press | machine |  | bench press × 1.05 | 1.21 | 2 |
| Incline bench press | free |  | bench press × 0.82 | 0.943 | 1.56 |
| Dumbbell bench press | free | yes | bench press × 0.37 | 0.425 | 0.703 |
| Incline dumbbell press | free | yes | bench press × 0.33 | 0.38 | 0.627 |
| Close-grip dumbbell press | free | yes | bench press × 0.28 | 0.322 | 0.532 |
| Supine dumbbell press | free | yes | bench press × 0.25 | 0.287 | 0.475 |
| Machine chest press | machine |  | bench press × 1.05 | 1.21 | 2 |
| Machine incline chest press | machine |  | bench press × 0.9 | 1.03 | 1.71 |
| Pec deck | machine |  | bench press × 0.8 | 0.92 | 1.52 |
| Cable fly | cable | yes | bench press × 0.16 | 0.184 | 0.304 |
| Assisted dip | bodyweight |  | own anchors: 0.85, 1, 1.2, 1.5, 1.8 | 1.2 | 1.8 |
| Overhead press | free |  | overhead press × 1 | 0.7 | 1.17 |
| Smith machine shoulder press | machine |  | overhead press × 1.05 | 0.735 | 1.23 |
| Machine shoulder press | machine |  | overhead press × 1.35 | 0.945 | 1.58 |
| Seated dumbbell press | free | yes | overhead press × 0.42 | 0.294 | 0.491 |
| Dumbbell lateral raise | free | yes | overhead press × 0.23 | 0.161 | 0.269 |
| Cable lateral raise | cable | yes | overhead press × 0.16 | 0.112 | 0.187 |
| Machine lateral raise | machine |  | overhead press × 0.62 | 0.434 | 0.725 |
| Incline Y raise | free | yes | overhead press × 0.17 | 0.119 | 0.199 |
| Cable front raise | cable | yes | overhead press × 0.22 | 0.154 | 0.257 |
| Cable upright row | cable |  | overhead press × 0.8 | 0.56 | 0.936 |
| Reverse pec deck | machine |  | overhead press × 1 | 0.7 | 1.17 |
| One-arm reverse pec deck | machine | yes | overhead press × 0.5 | 0.35 | 0.585 |
| Dumbbell reverse fly | free | yes | overhead press × 0.2 | 0.14 | 0.234 |
| Cable reverse fly | cable | yes | overhead press × 0.17 | 0.119 | 0.199 |
| Face pull | cable |  | overhead press × 0.7 | 0.49 | 0.819 |
| Barbell row | free |  | barbell row × 1 | 0.9 | 1.5 |
| T-bar row | free |  | barbell row × 1.1 | 0.99 | 1.65 |
| Chest-supported T-bar row | machine |  | barbell row × 1 | 0.9 | 1.5 |
| Dumbbell row | free | yes | barbell row × 0.53 | 0.477 | 0.795 |
| Machine row | machine |  | barbell row × 1.25 | 1.12 | 1.88 |
| Machine high row | machine |  | barbell row × 1.15 | 1.03 | 1.73 |
| Seated cable row | cable |  | barbell row × 1.05 | 0.945 | 1.57 |
| Lat pulldown | cable |  | barbell row × 0.95 | 0.855 | 1.43 |
| Close-grip lat pulldown | cable |  | barbell row × 1 | 0.9 | 1.5 |
| Underhand lat pulldown | cable |  | barbell row × 1 | 0.9 | 1.5 |
| Assisted pull-up | bodyweight |  | own anchors: 0.8, 0.95, 1.15, 1.4, 1.65 | 1.15 | 1.65 |
| Straight-arm pulldown | cable |  | barbell row × 0.5 | 0.45 | 0.75 |
| Deadlift | free |  | deadlift × 1 | 1.6 | 2.6 |
| Dumbbell shrug | free | yes | deadlift × 0.34 | 0.544 | 0.884 |
| Back extension | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| EZ-bar curl | free |  | bench press × 0.45 | 0.517 | 0.855 |
| Dumbbell curl | free | yes | bench press × 0.18 | 0.207 | 0.342 |
| Incline dumbbell curl | free | yes | bench press × 0.16 | 0.184 | 0.304 |
| Preacher curl | free | yes | bench press × 0.16 | 0.184 | 0.304 |
| Hammer curl | free | yes | bench press × 0.18 | 0.207 | 0.342 |
| Incline hammer curl | free | yes | bench press × 0.16 | 0.184 | 0.304 |
| Cable curl | cable |  | bench press × 0.33 | 0.38 | 0.627 |
| Cable hammer curl | cable |  | bench press × 0.3 | 0.345 | 0.57 |
| One-arm cable curl | cable | yes | bench press × 0.15 | 0.172 | 0.285 |
| Triceps pushdown | cable |  | bench press × 0.42 | 0.483 | 0.798 |
| Rope pushdown | cable |  | bench press × 0.34 | 0.391 | 0.646 |
| Overhead cable triceps extension | cable |  | bench press × 0.27 | 0.31 | 0.513 |
| One-arm cable triceps extension | cable | yes | bench press × 0.15 | 0.172 | 0.285 |
| Machine triceps extension | machine |  | bench press × 0.65 | 0.748 | 1.24 |
| Skull crusher | free |  | bench press × 0.42 | 0.483 | 0.798 |
| Cable wrist curl | cable |  | bench press × 0.48 | 0.552 | 0.912 |
| Cable reverse wrist curl | cable |  | bench press × 0.28 | 0.322 | 0.532 |
| Barbell wrist curl | free |  | bench press × 0.48 | 0.552 | 0.912 |
| Barbell reverse wrist curl | free |  | bench press × 0.28 | 0.322 | 0.532 |
| Dumbbell wrist curl | free | yes | bench press × 0.17 | 0.196 | 0.323 |
| Dumbbell reverse wrist curl | free | yes | bench press × 0.1 | 0.115 | 0.19 |
| Hand gripper | free |  | bench press × 0.48 | 0.552 | 0.912 |
| Back squat | free |  | back squat × 1 | 1.4 | 2.35 |
| Smith machine squat | machine |  | back squat × 1 | 1.4 | 2.35 |
| Pendulum squat | machine |  | back squat × 0.5 | 0.7 | 1.18 |
| Leg press | machine |  | back squat × 1.85 | 2.59 | 4.35 |
| Leg extension | machine |  | back squat × 0.9 | 1.26 | 2.12 |
| Single-leg extension | machine | yes | back squat × 0.45 | 0.63 | 1.06 |
| Barbell lunge | free |  | back squat × 0.6 | 0.84 | 1.41 |
| Dumbbell lunge | free | yes | back squat × 0.2 | 0.28 | 0.47 |
| Dumbbell walking lunge | free |  | back squat × 0.4 | 0.56 | 0.94 |
| Dumbbell split squat | free | yes | back squat × 0.17 | 0.238 | 0.4 |
| Smith split squat | machine |  | back squat × 0.57 | 0.798 | 1.34 |
| Side lunge | bodyweight |  | own anchors: 1.2, 1.33, 1.5, 1.67, 1.9 | 1.5 | 1.9 |
| Lying leg curl | machine |  | back squat × 0.6 | 0.84 | 1.41 |
| Romanian deadlift | free |  | deadlift × 0.78 | 1.25 | 2.03 |
| Stiff-leg deadlift | free |  | deadlift × 0.78 | 1.25 | 2.03 |
| Dumbbell Romanian deadlift | free | yes | deadlift × 0.3 | 0.48 | 0.78 |
| Hip thrust | free |  | back squat × 1.07 | 1.5 | 2.51 |
| Machine hip thrust | machine |  | back squat × 1.2 | 1.68 | 2.82 |
| Cable glute kickback | cable | yes | back squat × 0.14 | 0.196 | 0.329 |
| Hip abduction machine | machine |  | back squat × 0.7 | 0.98 | 1.65 |
| Cable hip abduction | cable | yes | back squat × 0.12 | 0.168 | 0.282 |
| Side leg raise | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| Hip adduction machine | machine |  | back squat × 0.7 | 0.98 | 1.65 |
| Side-lying hip adduction | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| Leg press calf raise | machine |  | back squat × 2 | 2.8 | 4.7 |
| Standing calf raise machine | machine |  | back squat × 1.2 | 1.68 | 2.82 |
| Smith machine calf raise | machine |  | back squat × 1.2 | 1.68 | 2.82 |
| Barbell calf raise | free |  | back squat × 0.82 | 1.15 | 1.93 |
| Dumbbell calf raise | free | yes | back squat × 0.32 | 0.448 | 0.752 |
| Cable crunch | cable |  | bench press × 0.65 | 0.748 | 1.24 |
| Standing cable crunch | cable |  | bench press × 0.55 | 0.632 | 1.04 |
| Crunch | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| Hanging leg raise | bodyweight |  | own anchors: 1.07, 1.2, 1.33, 1.5, 1.67 | 1.33 | 1.67 |
| Dragon flag | bodyweight |  | own anchors: 1.07, 1.17, 1.27, 1.4, 1.55 | 1.27 | 1.55 |
| Russian twist | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| Roman chair side bend | bodyweight |  | own anchors: 1.4, 1.6, 1.8, 2.1, 2.4 | 1.8 | 2.4 |
| Dumbbell side bend | free | yes | bench press × 0.33 | 0.38 | 0.627 |
| Cable wood chop | cable |  | bench press × 0.33 | 0.38 | 0.627 |
| Pallof press | cable |  | bench press × 0.23 | 0.265 | 0.437 |

## v2.1 section 4: day streak (Liftoff style)

- **Shown in days, decided by weeks.** The weekly-goal streak stays underneath
  (`StreakCalculator`; achievements such as "On a Roll" still use goal weeks). The day count
  (`DayStreakCalculator`) works like this:
  - **Counting:** a day counts, rest days included, while that week's goal is still achievable or
    already met.
  - **"Achievable":** sessions so far + days left in the week ≥ the week's effective goal. That
    assumes at most one session per remaining day, so a goal that would need double sessions counts
    as out of reach.
  - **Pausing:** if the goal goes out of reach mid-week, the count pauses. Home says how many sessions
    are needed and how many days are left. Logging enough sessions resumes the count.
  - **Breaking:** the streak breaks only when a week ends below its goal. The new one starts on the
    following Monday.
  - Smart rest days still lower the goal. A Red day on a planned rest day (Wed, Sun) doesn't count
    as smart rest, because you weren't going to train that day anyway.
  - With no history, the first streak starts on the first session day, not on that week's Monday.
- **The 177-day Liftoff streak is a migration offset, not sessions.** The first Liftoff import writes
  `streak_offset = {date: import date, days: 177}` (`liftoffStreakDays`).
  - On that date the streak is 177, then it counts on.
  - Weeks before that date are not evaluated, so Liftoff weeks that missed today's 5-a-week goal can't
    break it.
  - A missed week after the import breaks it like any other.
- **Longest streak** is the longest run in days, and at least the carried-over 177 (it includes the
  offset run).
- **Settings → Streak → Carried-over streak** shows and edits the offset; 0 removes it. The date stays
  the import date.
- **Fixed along the way:** onboarding showed a fixed weekly goal of 6 and saved it over the 5 sessions
  a week the program install had set. It now starts from the stored goal.
- **Known limitation:** Liftoff's extra 1-minute sessions (for example one Side Leg Raise set hours
  after the main workout) count as sessions toward the weekly goal, as recorded.

## Phase F addendum: the workout logging screen, rebuilt

The old screen (a card per set, steppers, an RPE button, big banners, a rest bar) was replaced, not
patched. Screenshots are in `docs/screenshots/vF/`: at rest, mid-edit with the keypad, and resting.

- **Exercise block, top to bottom:**
  - Header: thumbnail, name, collapse, ⋮ menu. The menu has Replace, Superset with…, Notes, How to
    and Remove, plus Move up/down until section 5 adds drag reordering.
  - Rest timer row with an on/off switch. The duration defaults from the program.
  - Rank strip: badge, division, LP bar and the kg gap ("+2.5 kg e1RM to Gold IV"). It says
    "Unranked · complete a set" or "Not ranked" instead of ever showing "???".
  - One prescription line ("2×4–6 · 1×20 · last set to failure", or a one-line calibration hint). ⓘ
    shows the coach's why, the program notes and any freeze.
  - The set table.
- **Set table: SET | PREV | KG | REPS | EFFORT | ✓.**
  - **SET:** tap it to make the set a warm-up (W, dimmed), a drop set (D, indented under the set
    above), a program technique tag, or to delete it. Higher-rep rows show their own target
    ("2 · ×20").
  - **PREV:** the matching set of the last session (warm-up i ↔ warm-up i, working ↔ working,
    drop ↔ drop). Tap it to copy.
  - **KG / REPS:** untouched cells show the coach's suggestion in grey, and ✓ logs exactly that.
    Assisted lifts show negative load ("−40").
  - **EFFORT:** one chip, F / 1 / 2 / 3+, pre-filled from the set's prescribed RIR. Tap to cycle. It's
    stored as RPE 10 / 9 / 8 / 7, and RPE appears nowhere in the UI.
  - **✓:** completes the set with a light haptic and starts the rest timer.
- **Custom keypad:** digits, point, backspace, ± the equipment increment, Copy (PREV, else the set
  above), +/− for assisted lifts, NEXT (KG → REPS → next set's KG) and hide. The edited cell scrolls
  above the keypad; the integration test checks that the keypad never covers it.
- **Rest:** never full screen. While resting, the header shows "REST 1:26" instead of the elapsed
  time. Tapping it opens a small sheet with the ring, −15, +15 and Skip. Fixed along the way: Skip
  closed the sheet twice, and the second pop closed the workout.
- **Minimize:** ↓ collapses the workout to a mini bar above the tab bar, on every tab. Tap it to
  resume.
- **Guardrail in the row:** a load more than 5 % over the suggestion shows an amber "+n%" badge on
  the KG cell. The reason sheet appears only when that set's reps also fall below the range.
- **Section 7 logic moved here, its UI replaced by the EFFORT chip:**
  - ego set = override + reps below the range;
  - failure inside the range is never ego;
  - discipline = load within ±5 % and reps in range;
  - the ego trigger "2 of the last 3 sessions" now counts these ego sets instead of overrides at
    RPE ≥ 9.5.
- **Section 6 groundwork (schema v5):**
  - `workout_sets.set_type` ('drop'): drop sets count for volume, never for e1RM, ranks, PRs or
    progression, and there's no rest between drops.
  - `session_exercises.rest_enabled`.
  - `session_exercises.superset_group`: a colored bar plus A1/A2 labels, with rest only after the
    round, using the group's longest rest.
- **Exercise thumbnails** use `Image.network` with a small decode size (in-memory cache) rather than
  the disk cache manager. They are 40 px, and the disk cache needs SQLite and a temp directory,
  which widget tests don't have.

## v2.2: ExerciseDB V2 (AscendAPI via RapidAPI), commits 1–2

- **Secrets.** The key lives only in `config/secrets.json`. It's git-ignored, which `git check-ignore`
  and a unit test both verify, and it's passed with `--dart-define-from-file`.
  `.githooks/pre-commit` (enable with `git config core.hooksPath .githooks`) refuses any commit whose
  tracked or staged files contain the key. The client never logs headers; its debug log records path,
  query and status only.
- **Budget guard.**
  - A persistent per-month call count, which RapidAPI's `x-ratelimit-requests-limit` / `-remaining`
    headers override whenever they're present.
  - A warning at 1,500 calls and a hard stop at 1,850 until the 1st of the next month.
  - Usage and the call log are in Settings → Debug → ExerciseDB V2.
  - The library list never calls the API.
- **AscendAPI caching policy, as read before writing code** (`guides/caching`):
  - Exercise IDs are permanent, so the mapping table stores IDs.
  - Media URLs rotate every Monday 00:00 UTC.
  - On a plan without caching rights, "you must not store any data returned by the API".

  Two places store small pieces of API data and need the owner's OK if the plan forbids caching:
  - the review queue keeps candidate **names** (with IDs), so the review screen works offline;
  - commit 3's derived muscle contributions come from V2 muscle names.

  Images in the review screen come from a fresh search held in memory only.
- **Mapping.**
  - One fuzzy search per exercise. Candidates are scored 70 % on name tokens (equipment words
    excluded) and 30 % on equipment named in the candidate's name.
  - Leftover budget fetches the top candidate's details for a target-muscle check (±0.1).
  - Auto-accept needs ≥ 0.85 and a lead of ≥ 0.08 over the runner-up. Everything else is queued.
  - Confirmed and auto mappings export to `assets/edb_v2_map.json`, which seeds a fresh install.
- **Initial run** (my routines first, then my Liftoff history; 111 exercises): 145 of the 150 allowed
  calls. 24 auto-accepted, 84 queued, 3 with no candidates.
  - Search quality is the limiting factor: many staples (leg press, leg extension, lat pulldown,
    pec deck, chest press, shrug) return unrelated exercises. Either the catalog visible on this plan
    doesn't contain them, or its fuzzy search doesn't surface them.
  - Several auto-accepts reached exactly 85 % only because the candidate name names no equipment
    ("Bench Press" for the Smith machine bench, "Romanian Deadlift" for the dumbbell RDL). They're
    worth a look in the review screen.

## Finish plan, Phase A: exercise library and media (free sources only)

- **ExerciseDB V2 is off by default.**
  - Settings → Debug → "Use ExerciseDB V2". While it's off, `edbApiProvider` returns `EdbDisabled`,
    which fails every call without opening a connection, so the app makes zero API calls.
  - The review queue keeps no candidate data. `assets/edb_v2_map.json` holds IDs and statuses only.
  - No muscle data is derived from V2.
- **Unified library** (`tool/library/build_library.py` → `assets/library_sources.json`, seeded as
  dataset v4, schema v7). It grew from 884 to **2,372** exercises:
  - **free-exercise-db** (public domain): 873 + 11 built-in (`sp_…`) entries stay canonical, with
    unchanged ids. A migration test checks that ids, favorites and history references survive.
  - **wger** (wger.de exercise data, fetched from the public API with no key): 925 exercises.
    187 were duplicates of existing entries and attach their images to them; **738 are new**
    (`wger_<id>`).

    Licences are per item, mostly CC-BY-SA 4.0 (772), CC-BY-SA 3.0 (132) and CC0 (21). Images are
    CC-BY-SA 4.0 or 3.0. Licence and author are kept per exercise and per image, shown on the
    exercise page ("Sources: …") and summarised under Settings → About → Credits. Attribution is the
    obligation; nothing is modified.
  - **ExerciseDB V1 free data** (non-commercial personal use, as before): 1,324 entries with a live GIF.
    574 were duplicates (their GIF becomes the canonical exercise's own GIF); **750 are new**
    (`edbv1_<id>`).

  How duplicates are detected:
  - **Key:** normalised name tokens (equipment words and noise such as "medium grip" removed;
    plurals and pull-up/chin-up/push-up spellings unified) + dataset equipment + primary muscle group.
  - **Same name + equipment** is also a duplicate, because sources disagree on the primary muscle
    (wger lists lats first for deadlifts).
  - **Nested names:** a name that contains another plus one word is a duplicate, unless that word
    changes the movement (incline, close, single, seated, hammer…).
  - **Machine lifts from wger:** wger has no "machine" equipment, so it's inferred from the name
    (Multipress, Hackenschmidt, Leg Extension, Lat Pull Down…).

  Exercises with only an image, or none, are kept: 526 of the new entries have no media.
- **Media rules.**
  - **Lists** (logger, routine editor, library and pickers) use a static thumbnail. The order is:
    free-exercise-db photo → wger image → the first frame of the V1 GIF (decoded once, never
    animated) → a placeholder with an equipment icon. They never show YouTube thumbnails.
  - **Exercise page and in-workout (i):** program exercises play Jeff Nippard's video. Everything
    else shows the V1 GIF, else photos, plus Steps.
  - YouTube search, pinning and the YouTube API key were removed. The `pinned_videos` table stays,
    unused.
- **Jeff's videos** (`tool/program/extract_videos.py`):
  - The PDF links every exercise and substitution name through link annotations, and the link
    text alone doesn't contain the URL. The words inside each annotation's rectangle rebuild the
    name. A name wrapped over two lines has two rectangles with the same URL that overlap by a
    pixel, and they're joined.
  - **73 of 73** program names (exercises and listed substitutions) have a video, each a distinct
    URL. None carry a timestamp, so they open at 0:00.
  - The player is youtube_player_iframe, embedded, with autoplay off.
  - **Matching rules:**
    - a program row gets its own slot's video;
    - a substitution row gets only the video of the listed substitution it is (my "Cable Reverse
      Wrist Curl" is the listed "Cable Wrist Extension");
    - my swaps (Pendulum Squat, Straight Arm Pulldown, Decline Crunch) get none, because the PDF
      doesn't list them;
    - any other library exercise matching a program name at ≥ 0.85 gets that name's video.

## Finish plan, Phase B: section 5, editing routines mid-workout

- **Session ↔ routine link (schema v8).** `session_exercises.routine_exercise_id` records which routine row each
  exercise came from; `targets_edited` marks a mid-workout target-reps change. A replacement keeps the link,
  so "Replace" is recognised as a replacement of that row and not as a remove plus an add.
- **What counts as a difference** at Finish: added exercises, removed routine rows, replaced exercises,
  a different order, a different number of working sets (warm-ups and drop sets don't count; the number is
  the planned working sets in the session, completed or not, so adding or deleting a set changes it) and edited target reps.
  Changing kg/reps/effort is logging, not a routine change, so it never triggers the prompt.
- **Update routine** rewrites the routine rows to match the session: order, set counts, exercise ids, new rows
  for added exercises (marked `extra` when they carry program slots), deletes removed rows. An edited target
  range on a program row becomes that row's rep-range override. A replacement on a program row becomes a
  `substitution` when the program lists it for that slot, otherwise a `swap`.
  **Keep routine as is** changes nothing. Dismissing the dialog (tapping outside) cancels Finish and returns to the workout.
- **Program rows in the routine editor** edit the rep range (stored as an override, applied to every
  prescribed working set; drop sets keep the program's reps), working sets and rest. **Reset to program** restores the slots'
  working-set total and the first slot's rest and range, and clears the override. Free (non-program) rows keep the
  old editor (range, sets, RIR, rest).
- **Mid-workout menu**: Replace (program substitutions first, then library search), Target reps, Superset,
  Notes, How to, Move up/down, Reorder exercises (drag sheet), Remove. Sets are added with ADD SET and
  deleted from the set-label sheet (unchanged from the logging rebuild).
- A session with no linked exercises against a non-empty routine (a workout left running across the v8 upgrade)
  is not compared: without links everything would look removed and re-added. Neither is a session whose routine
  has since been deleted.
- **Empty workouts** start from Train → "Start empty workout"; finishing one never shows the routine prompt.
- Tests: `test/data/routine_sync_test.dart` (diff + apply), `integration_test/routine_edit_flow_test.dart`
  (two flows). `train_flow_test` now accepts the prompt with "Keep routine as is" when its edits trigger it.

## Finish plan, Phase C: section 6, drop sets, myo-reps, static holds, supersets

- **Set types** (`lib/features/workout/domain/set_kinds.dart`): working, warm-up (W), drop (D), myo-rep
  cycle (M), weighted static hold (H). Drop / myo / hold are *follow-ups*: stored as `set_type` drop | myo | hold,
  shown under their working set with a colored left rail, never numbered, never used for e1RM, ranks,
  PRs, progression or the routine's set count. Drops and myo cycles count for volume. A hold stores
  **seconds in `reps`** (cell shows "30s") and adds no volume. No schema change was needed.
- **Drop sets**: as many per set as wanted (set menu → "Add drop set", then "ANOTHER DROP" under the last
  completed drop). Each is pre-filled from the set above it: 25 % lighter for the program's
  `drop_sets_2x25`, 20 % for a manual drop (both inside the requested 20–25 %), rounded to the
  equipment increment from Settings, always at least one increment lighter, never below 0 kg (assisted
  lifts add assistance instead). Changing the parent's KG re-derives drops that aren't done yet.
- **Program technique pre-creation**: at session start, a prescribed set carrying a technique gets its
  follow-ups right away: two 25 % drops, one myo cycle, or one 30 s hold. Choosing a technique on a
  set from the set menu does the same, unless follow-ups are already there. Techniques only appear in weeks 8–12
  (program block 2), so on the standard week the program creates none.
- **Rest**: none before a drop or a hold; **5 s** before a myo cycle (the program's rest_s); the normal
  rest after the last follow-up.
- **Myo-reps**: one cycle (same load, 2 reps) is pre-created; "ANOTHER CYCLE" adds the next one. The UI
  doesn't decide when to stop: the program says to stop when you miss 2 full reps.
- **Supersets**: made in the routine editor (link button between consecutive rows; tapping a linked
  link splits the group) or mid-workout (exercise menu → Superset with…). Colored bar + A1/A2 labels in both
  places; groups of one aren't shown as supersets. In the workout the keypad's NEXT goes A1 set 1 →
  A2 set 1 → A1 set 2…; rest starts when the round is done (every partner's set i and its follow-ups) and uses the longest
  rest in the group. Routine groups are re-keyed to session exercise ids at start so they can't clash
  with groups made mid-workout. "Update routine" writes the session's groups back.
- The program itself has no supersets in this version (every slot's `superset` is null), so none are created
  automatically.
- Tests: `test/data/set_types_test.dart` (8), `integration_test/set_types_flow_test.dart` (2 flows).

## Finish plan, Phase D: section 7 check

Audit of v2.1 section 7 (failure-based effort logging) against the code:

| Requirement | Status | Where / test |
|---|---|---|
| One-tap effort selector F / 1 left / 2 left / 3+ left | already in (logger rebuild) | `Effort`, EFFORT column cycles on tap; `train_flow_test` "cycle effort" |
| Maps to RPE 10 / 9 / 8 / 7 | already in | `guardrail_test` "effort selector…" |
| Default from the program's prescription | already in | `Effort.fromRir(targetRir)`; same test |
| **"+ partials" flag** | **added now** | schema v9 `workout_sets.partials`; SET menu switch "+ partials" or long-press the effort chip; shows `F+P`; history "+ partials"; JSON export `partials`; `set_types_flow_test`, `guardrail_test` "+ partials is a flag only…", `migration_test` v8 → v9 |
| Top of range at the prescribed effort (failure counts) → +1 increment | already in | `suggestion_engine_test` "failure prescribed: top of the range at failure → +1 increment" |
| Within range → same load, beat the reps | already in | "within the range → same weight, +1 rep…", "a set to failure inside the range is not a failed set…" |
| Below the bottom → −5 % | already in | "a set below the bottom of the range → −5% rounded down" |
| Ego = load above suggestion + reps below range; failure in range never ego | already in | `guardrail_test` "ego = …", "failure inside the range is never ego" |
| Discipline = load within ±5 % and reps in range | already in | `guardrail_test` "discipline needs…" |

- **Partials are informational.** The reps field stays full reps, so e1RM, records, volume, progression
  and recovery fatigue ignore the flag. Partials past failure don't make the full-rep performance
  any stronger, and counting them would inflate e1RM.
- Holds (seconds) and warm-ups don't offer the flag.
