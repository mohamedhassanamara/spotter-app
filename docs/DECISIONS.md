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

## Finish plan, Phase E: body map, simplified

- **Front and back side by side** (`AnatomyGraph`, keys `body-front` / `body-back`); the 3D flip and the
  front/back button are gone. Same anatomical paths (react-native-body-highlighter, MIT) and the same
  20-muscle split.
- **Flat styling**: one fill per muscle (tier color in Rank mode, unranked = neutral grey at full opacity),
  a thin dark outline (1.2 screen px, constant at any size), and a faint top highlight. The radial
  gradients and the Platinum+ glow are gone.
- **Selection**: outline glow (blurred white stroke + 2.2 px white outline) while its sheet is open.
- **Header**: overall badge + "BODY RANK · Silver II" (`body-rank-header`). The big Overall card stays
  on the Ranks tab.
- **Mode switch**: Rank / Recovery / Volume over the same map, with a legend for each mode (tiers + Unranked;
  Ready / Recovering / Fatigued with their % ranges; volume buckets). The deep link `?mode=` takes
  `ranks | recovery | volume`; `?back=1` is accepted and ignored now that both sides always show.
- **Sheet** on tap: Rank → badge, division, LP bar, kg e1RM gap to the next division, contributing
  exercises (as before). Recovery → % (big), band, time until Ready, last session that hit it.
  Volume → as before.
- Tap targets: hit-test on the path, then the nearest muscle within ~14 screen px.
- The Recovery mode reads `recoveryProvider` (Phase F model); it's committed with this phase so the
  switch is never empty.

## Finish plan, Phase F: muscle recovery (a heuristic, not a measurement)

All constants live in `lib/features/recovery/domain/recovery_config.dart`; the model is
`lib/features/recovery/domain/recovery.dart`. These numbers are chosen to *look plausible* for a
hypertrophy program trained close to failure. They are not validated against any physiology data.

- **Fatigue per set** = muscle contribution weight (the same weights ranks use) × effort factor:
  Failure 1.0, 1 left 0.85, 2 left 0.7, 3+ left 0.5. Drop sets 0.5 each; myo cycles and static holds are
  treated the same (0.5). Sets without effort (Liftoff imports) count as Failure, matching how the
  import treats them. Warm-ups add nothing. "+ partials" adds nothing (Phase D).
- **Decay**: exponential, half-life 48 h for quads, hamstrings, glutes, lats, upper back, upper and
  lower chest; 30 h for everything else (delts, arms, calves, abs, obliques, forearms, traps, and also
  adductors, abductors and lower back, which the brief didn't list).
- **Readiness** scales recovery speed: Green ×1, Yellow ×0.85, Red ×0.7 (calibrating or no Health data
  = Green). *Today's* band is applied to the whole elapsed time. A per-day replay would need
  readiness history for every past day, which isn't always there, so this simpler version is a known approximation.
- **Recovery %** = 100 × (1 − fatigue / 12), clamped. 12 ≈ a high-volume, to-failure session for one
  muscle (6 hard sets right after training → 50 %, Fatigued). **Bands**: Ready ≥ 90 %, Recovering
  60–89 %, Fatigued < 60 %. "Time until Ready" solves the decay for fatigue = 1.2.
- Only sets from the last 14 days are used; finished sessions only (the workout in progress isn't counted),
  so the heads-up reflects how you walked in.
- **Seeded from history**: imported Liftoff sessions count like any other, so it's correct on day one.
- **Display only.** Suggestions never read recovery; readiness already adjusts load.
- **UI**: body map Recovery mode (Phase E) with a sheet showing %, band, time until Ready and the last
  session that hit the muscle. Home "MUSCLE RECOVERY" card lists Ready (only muscles trained in the last two
  weeks, since all 20 fresh muscles would be noise), Recovering and Fatigued, with both chest heads shown as
  "chest", and opens the Recovery map. When a workout started from a routine has Fatigued primary
  muscles (contribution ≥ 0.5), the logger shows one dismissable line ("Heads-up: chest still fatigued"),
  which never blocks anything.
- Tests: `test/domain/recovery_test.dart` (decay, readiness scaling, bands, state from history, heads-up),
  `integration_test/body_map_flow_test.dart` (Home card → Recovery mode tap → Rank/Volume → heads-up).
- **Known consequence of the constants:** with a 48 h half-life and Ready at ≥ 90 %, a hard session
  (≈ 9 failure sets for a muscle) reads Ready only after ~5–6 days; the "Ready" line is strict. If that
  feels too slow on the phone, the knobs are `fullFatigue` (12) and `readyAt` (90) in the config file.

## Real-device fixes, Fix 0: one fixed weekly template

- **Canonical week = week 5 of the PDF.** `tool/program/canonical_week.py` builds
  `assets/programs/min_max_canonical.json` (sets, rep ranges, week-5 RIR per set, warm-ups, rest,
  supersets, substitutions, notes, videos; no `weeks`, no techniques). The 12-week extraction moved to
  `docs/program/min_max_phase2_12weeks.json` for reference and is no longer bundled. Week 5 vs the
  former week 2 differs in one place: Hack Squat RIR 1/2 → 0/2.
- **No week tracking:** `standardProgramWeek`, `programWeekProvider`, `programWeekFor`, the start-Monday
  setter and per-week RIR are gone; `prescribeSets` takes no week. Nothing in the UI shows "Week N"
  (an integration test scans Home, all five loggers and Settings). Settings → Program now says
  "One fixed weekly template".
- **Techniques are manual only:** prescriptions carry no technique, so starting a routine never
  creates drop sets, myo-reps or holds. The SET menu still offers them all (including the program
  technique entries, which create their follow-ups when *you* pick them).
- **Conversion** (`ProgramRepository.ensureCanonicalWeek`, at startup, once, keyed by
  `program_canonical_week`): deletes the old program-start setting; sets program routine rows' default
  RIR to the canonical first-slot RIR; in a workout in progress, deletes *pending* drop/myo/hold sets
  that the program created (they carry a technique id; ones you added by hand don't) and strips
  technique tags from pending working sets; clears `programWeek` on the live session. History is
  untouched (`session_exercises.program_week` stays as a historical column, no longer written).
  Test: `test/data/canonical_week_migration_test.dart`.

## Real-device fixes, Fix 1: "Counts toward rank" where you need it

- One switch widget (`RankToggle`, key `rank-toggle-<exerciseId>`) on every exercise row of the muscle
  sheet and of the Ranks tab, next to the existing exercise-page switch. All three read and write the
  same setting (`rank_excluded_exercises`), so they can't drift apart, and `ranksProvider` watches it,
  so muscle, region and overall ranks recompute on the next frame.
- The muscle sheet is now live (it watches `ranksProvider`), so a toggle redraws it in place: the row
  dims to "Not counted", the muscle's badge/LP/next-step update, and the sheet stays open.
- Switched-off exercises are still scored (`RankSummary.hidden`) but never feed a muscle. That's how
  their rows can stay visible with the switch off, so you can turn them back on from the same place.
  The Ranks tab lists them under "Hidden from ranks (n)" as dimmed cards with the switch; the old
  "Rank it" button is replaced by the switch.
- Tests: `ranks_test` (hidden exercises are scored but feed nothing), `rank_toggle_flow_test` (sheet →
  Ranks tab → exercise page round trip), `ranks_flow_test` updated.

## Real-device fixes, Fix 2: a body map you can read

- **Palette**: ten saturated tier colors, one hue family each: Iron crimson, Bronze orange, Silver
  sky blue, Gold yellow, Platinum teal, Emerald green, Diamond blue, Master violet, Grandmaster
  magenta, Challenger lime. Silver is no longer grey, which was the cause of "everything looks the same".
  `test/widget/tier_palette_test.dart` enforces: WCAG contrast ≥ 3:1 against the body fill for every
  tier, saturation ≥ 0.6, hues ≥ 24° apart for any two tiers and ≥ 25° for neighbours, and the body fill
  being a dark neutral (lightness < 0.2, saturation < 0.25). Badges and every other tier-colored UI
  pick up the same palette.
- **Body fill**: unranked muscles `#262C37`; the non-muscle silhouette (head, hands, feet, joints) a
  darker `#161A22`, so muscles read as shapes even when unranked.
- **Shapes**: `BodyView.shapes`. A muscle drawn as several fragments on one side (abs, quads, calves,
  forearms…) becomes the convex hull of those fragments: one flat shape, no internal lines. Single-piece
  muscles keep their exact outline. A 2.6 px background-colored stroke cuts the gap between muscles. The
  figures run nearly edge to edge (4 px margins, 4 px between front and back). The original parts are
  kept for the small thumbnails.
- **Tap**: the muscle glows and a callout (badge, name, rank / recovery % / sets) appears above it on
  the figure that was tapped; the sheet opens 650 ms later. Rows in the list open the sheet directly.
- **Under the map** (Rank mode): the region list ("Chest · 2/2 ranked", collapsible, muscle rows with
  the highlighted thumbnail, badge, division and LP). The Ranks tab region cards use the same title.
- **Legend**: one compact wrap with only the tiers present on your body, plus Unranked.
- Test: `body_map_readable_flow_test` (width, legend, callout before sheet, regions list → sheet).

## Real-device fixes, Fix 3: thumbnails in the 3D style only

- `ExerciseThumb` (logger, routine editor, library, history session detail): the still first frame
  of the exercise's ExerciseDB GIF, else a **generated thumbnail**: our body-map silhouette of the side
  where the exercise works most, cropped around its muscles, prime movers (≥ 0.5) lit in the accent
  color and helpers at half strength (`ExerciseMuscleThumb`). While the GIF frame decodes, the
  generated one shows. Photos (free-exercise-db, wger) are never a thumbnail.
- The exercise page and the in-workout (i) sheet use the same rule for the demo: GIF, else the
  generated figure at full size, never a photo carousel. Real photos appear only in a **Photos**
  section near the bottom of the exercise page (horizontal strip).
- Test: `thumbnails_flow_test` checks no `Image` (network photo) under any `ExerciseThumb` in the
  library, routine editor, logger and history; a GIF exercise shows the still; a photo-only exercise
  shows the generated figure and keeps its photos in the Photos section.
- Known limit: the GIF comes from the existing V1 name matcher, so a few matches are approximate
  (e.g. "Foam Roller Adductors" shows a stretch). Settings → Debug → Media matching can fix one.

## Real-device fixes, Fix 4: GIF and Jeff's video together

- **Exercise page**: no more Video/Demo/Steps tabs. Top to bottom: the 3D GIF loop (`exercise-hero`;
  the generated figure when there's no GIF), then for program exercises a **"Jeff Nippard demo"** card
  with the embedded video (autoplay off), then Steps, Muscles, Photos, history. Both, never either/or.
- **In-workout (i) sheet**: the GIF loops first; program exercises get a **"Watch Jeff's demo"**
  button that reveals the video in the sheet. The video doesn't load until you ask, which keeps the sheet
  light mid-set.
- Test: `exercise_media_flow_test` (GIF above the Jeff card on a program exercise; no card on a
  non-program one; the (i) sheet's button). `library_media_flow_test` updated for the tabless page.
- The screenshot in docs/screenshots/fixes/ shows the Jeff card's player area empty: YouTube is an
  iOS platform view, which the test's layer capture can't render. On the phone it shows the video.

## Real-device fixes, Fix 5: program fidelity

- **Incline DB Y Raise "2 sets".** The program and the routine both say 3 × 10–12 (RIR 0/0/0), and
  the logger renders 3 on a normal day (fidelity table). The 2 came from **readiness**: on a Red day
  the engine removed a set without saying so in the logger. Worse, Phase B's "Update routine"
  counted that missing set as your change and could write 2 into the routine. Now the number of
  sets readiness removed is stored with the suggestion (`setsTrimmed`), the prescription line says
  "1 set skipped today (readiness red)", and routine sync adds skipped sets back before comparing, so
  they're never a routine change. Fix 6 reworks what readiness does to isolations.
- **Supersets.** I was wrong in the last report: the extraction did capture S1/S2/S3 on Arms, but
  the routines never used them. Now:
  - `installMyRoutines` groups rows by their first slot's label (S1: EZ Bar Curl + Cable Overhead
    Triceps Extension, S2: Preacher Hammer Curl + Triceps Pushdown, S3: Cable Wrist Curl + Cable
    Reverse Wrist Curl), for fresh installs and "Reinstall my routines";
  - `ensureProgramSupersets` (startup, once) builds the same groups into your *existing* routines
    without reinstalling them (your set counts, swaps and overrides stay), and applies the rest rule:
    0 s on the first of a pair, 60 s (top of 30–60 s) on the second;
  - the logger shows the rule instead of a per-exercise timer: "No rest → A2" on the first,
    "Rest 1:00 after the round" on the second (it already rests only after the round, using the
    longest rest).
  The canonical week has supersets only on Arms (checked for every day).
- **Fidelity test** (`integration_test/program_fidelity_test.dart`): starts all five routines with
  seeded history (so nothing is in calibration) at neutral readiness and reads the *rendered* logger
  (set rows and their labels, the effort chip of each working set, warm-up rows, the prescription
  line, the rest line, the superset label), then compares with the canonical week + my_routines.json.
  It writes `docs/program/FIDELITY.md` when run with `--dart-define=REPORT_DIR=$PWD/docs/program`.
  Result: 29/29 rows match. All set counts equal the program's; the documented deviations are the
  swaps (Straight Arm Pulldown, Pendulum Squat, Decline Crunch) and the listed substitutions.
- Rules the table relies on: rest = top of the program's range; warm-ups = top of the range for the
  day's first exercise and compounds, bottom otherwise; effort chip = F for RIR 0, else the RIR.

## Real-device fixes, Fix 6: suggestion engine rework

**a) Only weights that exist.** `lib/core/domain/gym.dart`.
- Settings → **My gym equipment**: dumbbells (default 2.5–50 kg by 2.5; edit as "from-to/step" or a
  list), smallest barbell plate per side (default 2.25 kg, so barbell loads move in 4.5 kg from the
  20 kg bar), and the machine / cable stack (default first plate 5 kg, step 5 kg). Each machine or cable exercise can
  override its stack from the logger's exercise menu → **Weight steps…** (also listed, with a reset,
  under Settings). Kettlebells use a standard set (4–48 kg). Assisted machines use the stack as negative load.
- **Every weight you've logged on an exercise also counts as available** (e.g. your Triceps Pushdown
  72 kg position, which the default 5-kg stack wouldn't have). Otherwise the engine would move you off a weight
  you actually use.
- Suggestions, warm-ups, drop sets and the keypad's ± all land on this grid (`WeightGrid`): increases
  go to the *next available* weight, reductions to the next lighter one, computed loads snap down.
  The old per-category "increments" settings are gone from the UI (still used internally as a fallback).
  Property test: 2,000 random histories × readiness × recovery × nutrition × 4 grids, never off-grid.

**b) No drop spirals.**
- Readiness never cuts an **isolation** below last session's working weight. Yellow turns an increase into a
  hold. Red holds and removes one working set (recorded and shown in the logger, Fix 5).
  **Compounds** on Red: at most one step below last session, plus one fewer set.
- At most **two load decreases in a row**; a third (from a missed range, a plateau or readiness) becomes
  a hold, unless an ego freeze is active.
- **Big jumps:** if the next available weight is > 10 % heavier (7.5 → 10 kg is +33 %), the top of the
  range isn't enough: the target extends to top + 2 (aiming up to + 3) at the same weight, and the jump
  comes once every working set reaches top + 2. In the **first 2 sessions after any jump**, falling below the range holds
  the weight instead of dropping it.
- **Form reset:** exercise menu → Form reset…, or the "Form reset at X kg?" chip the engine shows
  when your last session stepped down at least one available weight from your recent best and still hit
  the top of the range, or a snackbar when you complete such a set mid-workout. Stored per exercise
  (`form_resets`); sessions before the reset date stop counting (no reductions from heavier history),
  progression restarts from the reset weight. If nothing is logged on the exercise yet that day, the
  suggestion refreshes immediately.

**c) More inputs (Apple Health), applied transparently.**
- Health now reads dietaryEnergyConsumed and dietaryProtein (schema v10 stores them per day next
  to HRV/RHR/sleep). `lib/features/coach/domain/energy.dart` computes the 7-day bodyweight average, the
  2–4 week slope (least squares, ≥ 4 weigh-ins over ≥ 14 days; losing < −0.2, gaining > +0.2 kg/week),
  7-/28-day intake and protein per kg.
- **Clear deficit** = losing ≥ 0.25 kg/week, or 7-day intake ≤ 85 % of the 28-day average. Effect: a
  missed range holds instead of dropping, and a plateau needs three flat sessions instead of two.
  Low protein (< 1.6 g/kg) adds a note only. Nutrition never adds load.
- No nutrition in Health: skipped, and the readiness card and the "why" say so.
- **Recovery:** a Fatigued prime mover may soften by one step (an increase becomes a hold; a compound
  one step down). Readiness and recovery together never soften by more than one step.

**d) Explained.** `Suggestion.why` is the chain, one line per stage: **Base** (last session and how it's
read) → **Rule** (the progression rule that applied) → **Readiness / Recovery / Nutrition** (what each
did) → **Weight** (the load exists, or what it snapped from). The logger's ⓘ shows it with the stage
labels; the "Form reset?" line appears when relevant.

**Y Raise (the reported case).** History: 10 kg sessions, best 10 × 13; 6 Oct the deliberate 7.5 × 10,
7.5 × 12 (+ 5 × 15). The old engine on a Red day: same weight 7.5 × 11, then −10 % = 6.75, floored to its
2 kg dumbbell step = **6 kg** (a weight that doesn't exist). Now, on every band: **7.5 kg × 11** ("within
10–12 → same weight"; Red: "isolation: never below last session's 7.5 kg; one fewer working set"),
plus the form-reset hint. Regression test with that history:
`test/domain/suggestion_rework_test.dart` (it also runs the old engine to show the 6).

**Before/after for all routines:** `docs/SUGGESTIONS_BEFORE_AFTER.md` (generated by
`test/tool/suggestions_before_after_test.dart` from the Liftoff CSV, Green and Red). Sessions logged in
the app after the export (11 Oct) aren't in it.

Tests: `suggestion_rework_test` (28), `suggestion_engine_test` (updated for the intended changes: big
jumps extend first, Red isolations hold, the "Base:" prefix), `seed_and_export_test` (Pendulum
"no spiral" instead of "trend up", since the simulated lifter stops at the prescribed 2 in reserve),
`migration_test` v9 → v10, `suggestion_rework_flow_test` (settings, weight steps, 7.5 kg + why chain,
form reset, nutrition line).

## Body map: back to Phase E (v3 painted map and Fix 2 flat map removed)

- **Restored**: the Phase E map (`1bfd9e7`): front and back side by side with that figure style and
  those shapes (`body_map.dart` is byte-identical to Phase E), the "BODY RANK · tier" header with the
  badge, the Rank / Recovery / Volume switch with Phase E's colors, and the full tier legend.
- **Kept from later work**: the original v2 tier palette (pre-Fix 2, so the v2 badges render as
  designed; unranked is the original slate `#3A4255`), the "Counts toward rank" switches (Fix 1), the tap
  callout before the sheet, and the collapsible region list under the map. The generated exercise
  thumbnails (Fix 3) now draw from Phase E's parts instead of Fix 2's merged shapes.
- **Removed entirely** (no flags): the v3 satin painter, game frame, showcase screen and render tool;
  Fix 2's merged shapes (`simplifyMuscles` / `convexHull` / `BodyView.shapes`) and its flat painter.
  `AppColors.bodyBase` is Phase E's silhouette color (`#1C2230`); the palette test checks every tier at
  ≥ 3:1 against it, and that unranked is darker than every tier.
- **"Every muscle unranked" in v3, investigated.** I couldn't reproduce it. With the real Liftoff
  import in the simulator, v3 showed the ranks (Silver II overall, Gold delts/traps/calves, Bronze glutes/adductors,
  Silver elsewhere), and so does the restored map. Each candidate was checked:
  - ranks reaching the map: the app's computed `RankSummary` = the map's scores, 20/20 muscles ranked;
  - tier → color: every ranked muscle → `tierColors[tier]`, never the unranked slate;
  - palette revert: the restored constants are the v2 values;
  - HealthKit: the nutrition types added in Fix 6 can't block weight reads (reads are per type);
  - v3's picture cache: keyed by the full color set, so new ranks always re-record.
  Most likely explanation: 17 of the 20 muscles are Silver (`#B9C6D3`, a pale silver-blue), and v3's
  satin shading lightened it toward white-grey, which reads as "no color" next to the grey silhouette.
  Without a screenshot from the phone this stays a hypothesis.
  The new test guards the whole chain on real pixels, so a real regression would fail it.
- Test: `integration_test/body_map_real_ranks_test.dart`. With
  `--dart-define=LIFTOFF_CSV=<path>` it imports the real export (fixture otherwise) and asserts:
  1. computed ranks = the map's scores;
  2. each ranked muscle → its tier color;
  3. the rendered pixel at the most interior point of each ranked muscle is that tier color, not slate.

  It also taps all 20 muscles across both views (callout + the right sheet) and switches modes.
  Screenshots: `docs/screenshots/bodymap-revert/` (rank, recovery, volume).

## Never remove sets: readiness and recovery adjust the target, not the volume

- **The set count always equals the routine's.** No coaching input (readiness, recovery, nutrition,
  anything else) changes it. The Red-day "one fewer set" logic, the logger's "1 set skipped today"
  note and the routine-sync compensation for skipped sets are gone. The calibration path no longer drops a
  set on Red either.
- **When an adjustment is warranted** (Yellow or Red readiness, or a Fatigued prime mover), the coach
  picks one of two:
  1. **Repeat**: last session's top weight for its best reps at that weight (kept inside the range, up to
     the extended target), no progression today. Yellow; Red on isolations; Fatigued on any band
     except the deload case.
  2. **Small deload**: one available weight step below last session, with the same rep target (kept
     inside the range), all sets. Red on compounds (with or without Fatigued muscles). The session is
     marked so it isn't used as a progression base.
  If the progression rule already lowered the load today (a missed range), readiness adds nothing, so
  the total is never more than one step down. Isolations never go below last session's working weight for
  readiness or recovery.
- **The why line names the choice:** "Readiness: Readiness Red (30) → repeat last session (7.5 kg × 12),
  all 3 sets", "Readiness: Readiness Red (30) + quadriceps Fatigued → small deload: 35 kg × 8 (one step
  down from 40 kg), all 3 sets", "Recovery: biceps Fatigued → repeat last session (40 kg × 12)…". The
  headline starts with "Repeat:" / "Small deload:" instead of "Today:".
- **Clean-up** (`ProgramRepository.ensureRoutineSetCounts`, startup, once): a program routine row is
  restored to its `my_routines.json` set count when it has fewer sets *and* a finished session linked
  to it was a Red day with exactly that many working sets (the old trim + "Update routine"). Rows you
  reduced yourself (no such trace) are left alone. Anything restored is listed under Settings → Program
  ("Set counts restored"). On the simulator data there was nothing to restore; the phone runs this on
  first launch of this build.
- Tests: `suggestion_rework_test` (Y Raise Red → 3 sets at 7.5 kg × 12; Red + Fatigued compound →
  small deload one step; never more than one step in total; the set-count matrix of Green/Yellow/Red ×
  Ready/Recovering/Fatigued × compound/isolation over four histories and 1–4 routine sets);
  `suggestion_engine_test` updated; `canonical_week_migration_test` (restore with Red-day evidence,
  leave my own change). `docs/SUGGESTIONS_BEFORE_AFTER.md` regenerated.

## Streak rework: Liftoff-style, no weekly goal, no fixed training days

- **Rule** (`DayStreakCalculator`): every calendar day counts while the streak is alive, rest days
  included. Up to **2** consecutive days without a workout are fine. When a **3rd** consecutive day
  ends without one, the streak resets to 0, and the next workout starts it again at 1. A workout day is the
  local calendar day a finished session *started* (a session crossing midnight belongs to the day it
  started); sessions without a completed working set don't count (`streakWorkoutStarts`). Days are
  compared as calendar days (UTC-normalised day numbers), so DST's 23/25-hour days are one day each,
  and UTC timestamps count for their local day.
- **Last-chance day** = the 3rd day after the last workout (two rest days behind you). That is when Home
  says "Last chance: train today or the streak resets" and the reminder fires (18:00, "Train today to
  keep your N-day streak."). The request called it "the 2nd consecutive day without a workout", but under
  its own reset rule (reset only when the 3rd rest day *ends*) the day you must train is the 3rd, so
  that's the one used. If you meant "train on the 2nd rest day", it's one constant: `maxRestDays`.
- **Home safety line**: Safe: trained today; Safe: trained yesterday, no rest days used; 1 rest day
  used; Last chance…; or "Your next workout starts a new streak" after a reset.
- **Carry-over**: the 177-day Liftoff offset stands in for everything up to its date (counted as a
  workout day); from that date on the new rule applies. A broken run's length counts its two safe rest
  days. Longest stays ≥ 177. Settings → Streak keeps the "Carried-over streak" edit.
- **Reminder**: local notification, one at a time, rescheduled whenever the streak changes (app start,
  every finished workout, settings change). Toggle in Settings → Streak ("Last-chance reminder", on by
  default; `streak_reminder`). Nothing is scheduled when the streak is 0 or 18:00 has passed.
- **Removed**: the weekly session goal (setting, Settings stepper, onboarding step, the program
  install writing it), the weekly streak (`StreakCalculator`, `WeekStatus`), smart rest (Red days lowering the goal),
  planned rest days for the streak, the "goal still achievable / paused" logic, the weekly-goal XP bonus
  (+100) and its summary banner, the smart-rest / planned-rest day dots, and the calendar's "goal met" checkmarks
  (now a session count per week). Onboarding's third step now explains the streak instead.
- **Adapted achievements** (keys kept, so earlier unlocks stay):
  - `smart_rest` "Take 5 smart rest days" → `streak_14` "Two Weeks Unbroken": a 14-day streak;
  - `streak_4` "Hit your weekly goal 4 weeks in a row" → a 28-day streak;
  - `streak_12` "… 12 weeks in a row" → an 84-day streak.
  New metric type `streakDays` (longest day streak, carry-over included); `smartRestDays` and
  `weeklyStreak` are gone.
- **Adapted quest**: "No overrides in N sessions" took N from the weekly goal − 1. It now uses your
  average sessions per week over the last 4 weeks − 1 (clamped 2–6).
- **Profile**: "This week: N sessions since Monday", display only.
- Tests: `day_streak_test` (17: two rest days continue, 3rd ends → 0, workout after reset → 1, crossing
  midnight, an empty workout through the history filter, DST in October and March, UTC timestamps,
  carry-over incl. recomputation and sessions before the import, reminder timing),
  `aggregation_quests_test` (adapted achievements, quest sizing); `streak_flow_test` (the three Home
  states with screenshots in docs/screenshots/streak/, reset, carry-over + edit, reminder toggle,
  Profile, no weekly goal in Settings).

## First real workout: four bugs

**Bug 1, edited values lost on ✓.** Root cause: ✓ completed the set from the object the screen already held
(the `activeSessionProvider` value, a drift stream) and that object is the last emitted one, so right after
the keypad's in-progress value was written it was still the old row. The set was completed with the
suggestion; touching a field again only worked because the stream had caught up by then.
- Every path now commits first (`_commit()` returns the written set id) and then re-reads the row from the
  database (`SessionRepository.workoutSet`): ✓, NEXT, Copy, PREV copy (clears the stale buffer first),
  ± , collapse, minimize / app backgrounding (lifecycle observer), the exercise menu, set delete and Finish.
- **Typed, then Finish**: a set whose value was typed but never ✓ is logged as done with what was typed
  (it was clearly lifted). Judgement call; the other reading ("drop it") would lose the number.
- Existing data: I can't open the phone's database from here. Instead a history session shows a
  "suspect sets" card listing completed working sets whose saved weight and reps both equal the suggestion;
  tapping a set opens a KG / REPS correction (`HistoryRepository.correctSet`). It is a heuristic: a set you
  really did at the suggestion is listed too, correcting it is optional.
- Latent bug found on the way: `gymEquipmentProvider` was never watched, so keypad ± / drops / form-reset
  used default equipment. It is now watched by the logger and by each exercise block.

**Bug 2, Form reset snackbar.** A `SnackBar` with an action is persistent by default; `persist: false`
with a 3 s duration fixes it. Swipe dismisses, opening the keypad hides it, and it is offered once per
exercise per workout (`form_reset_offers`, latest 300 kept).

**Bug 3, weight steps.** Every exercise has a load type (single-sided plate, two-sided plate, stack /
cable, barbell, dumbbell, kettlebell, bodyweight, assisted, other), chosen from its name and dataset
equipment (`core/domain/load_types.dart`; table in `docs/LOAD_TYPES.md`). Setting: My gym equipment →
Smallest plate (default 2.5 kg). One-sided = 1 × plate, two-sided and barbell = 2 × plate, stacks keep
their 5 kg default, dumbbells their list. The exercise menu's Weight steps sets a load type and/or stack
by hand and wins over the classification. A "machine" with no plate-loaded name is assumed to be a pin
stack. Weights you already logged count as available.

**Bug 4, swipe to delete.** `SwipeSetRow` wraps every set row. Left swipe reveals a red Delete (trash icon);
past 60 % of the width, or a fast fling, it deletes at once; a short swipe leaves it open and tappable.
Delete shows an Undo snackbar for 3 s (`restoreSet` re-inserts the row with its id, values and place).
Only horizontal drags are claimed, so the page keeps scrolling vertically. The set-menu Delete stays.
- **Swipe right to complete did not exist** in the code (only the ✓ button). Since you expected it, I added
  it: a right swipe of at least 56 px completes the set and springs back; it never un-completes one.

## Ranks: only my routines count by default; Pull swap

**Rule.** An exercise counts toward ranks when, in this order: you switched it on/off by hand (manual always
wins); else it is in one of your current routines; else you completed a working set of it in an in-app
workout (automatic); else it is off. Derived from stored state (`rank_manual` id → on/off, `rank_auto_on` ids,
the routines), not copied, so "adding to a routine switches it on" and "removing it switches it off again"
need no hook. `RankExclusions.load()` still returns the set of exercises that don't count (now the library
minus the ones that do), so ranks, the muscle sheet, the Ranks tab and the exercise page share one source.
- **Auto-enable** happens in `completeSet` for a real working set only: not a warm-up, drop / myo / hold,
  or a set with 0 reps. Un-ticking it later leaves the exercise on. Imported history never triggers it.
- **Manual off beats everything**, also adding to a routine and a completed set. Judgement call: switching a
  routine exercise off and later re-adding it to a routine does not turn it back on; flip the switch.
- **Migration (once, `rank_policy_v2`).** Exercises you had hidden that are in a routine become manual-off
  (they were deliberate); exercises with a completed working set in an in-app session are switched on
  (automatic), because that is what the new rule would have done. Everything else follows the routine rule.
- **Silent.** Ranks are derived, never stored, so nothing animates or notifies. The ladder migration is
  bumped to v5, which re-checks rank achievements against the new ranks and revokes unsupported ones
  silently, like the v4 change.
- Liftoff's "exclude from ranks" list in the import is gone (everything not in a routine is off anyway).

**Pull: Machine Single-Arm Reverse Fly.** Replaces Machine Reverse Fly in the same position (my_routines.json
for new installs; a one-time in-place step for existing ones that keeps your set count and other edits).
It is the program's 1-Arm Reverse Pec Deck: slots pull_06 + pull_07 (1×20, 1×10, both to failure, 0–1
warm-ups, rest 1–2 min); the video comes from the program slot as before.
- **History:** the exercise reuses the id the Liftoff import already made from "One Arm Machine Reverse
  Fly" (`liftoff_one_arm_machine_reverse_fly`, renamed in the library), so that history and its rank
  standard (one-arm reverse pec deck) follow it. It is thin (one session, 25 kg × 20 on 10 Oct). The 19-session
  "One Arm Cable Reverse Fly" was not used: different equipment and stack. The two-arm Machine Reverse Fly (42
  sessions) keeps its history and is now off for ranks unless you do it again.
- Tests: `rank_policy_test` (default, auto-enable, warm-up / drop / empty set, import, manual off, manual on,
  adding to a routine, migration), `single_arm_reverse_fly_test` (fresh install, in-place migration, program
  prescription, video), `rank_toggle_flow_test` (real taps). `docs/RANK_POLICY.md` has the before / after
  ranks and the first suggestions.

# Batch 2 (after a few days of real use)

## 1. Walking Lunge is per dumbbell (supersedes "combined" in Rank calibration v4)

**Root cause.** Liftoff logged Walking Lunge as the total of both dumbbells (35 kg). The v4 decision kept that
as a special "combined weight" exercise, but the suggestion engine and the logger treat every dumbbell
exercise as per dumbbell, so the next target became 37.5 kg *per dumbbell*.
- **Data:** a one-time fix (`DataFixes.ensureLungePerDumbbell`, setting `fix_lunge_per_dumbbell_v1`) halves every
  *imported* Walking Lunge set (35 → 17.5). In-app sets are untouched. New imports halve at import time
  (`liftoffTotalLoadIds`), so a later re-import stays consistent.
- **Rule:** every dumbbell exercise is logged per dumbbell, lunges included. The "Dumbbell walking lunge"
  (combined) standard is deleted; `sp_db_walking_lunge` ranks on *Dumbbell lunge* (per dumbbell).
- **Suspects (not converted):** compared with sibling lifts in the Liftoff data, no other dumbbell exercise
  looks like a total. The ones worth a look, if the numbers feel off when you next train them:
  Dumbbell Calf Raise (max 37.5), Dumbbell Shrug (37.5), Dumbbell Romanian Deadlift (37.5). All three equal the
  heaviest pair in your gym and fit a per-dumbbell reading, so I left them.
- Tests: `lunge_per_dumbbell_test`.

## 2. Machine max load

Exercise menu → Weight steps… has an optional **Max load (kg)**; empty = unlimited (`GymEquipment.maxLoads`, stored
with the other gym settings; "Use default" clears it).
- The exercise's weight grid stops at the max (also over weights logged above it), so suggestions, calibration,
  deloads, drop sets (snap down) and the keypad's + all stay at or below it. The keypad's + at the top of the grid
  used to fall back to "+ increment"; it now clamps to the max.
- At the max with the top of the range hit, the suggestion keeps the weight and raises reps **without the usual
  range + 3 cap**, and shows "Machine max reached: progress with reps or switch variation" under the
  prescription (`Suggestion.maxReached`, stored in the suggestion JSON) and in the ⓘ explanation.
- Tests: `max_load_test` (grid, settings round trip, suggestion below / at the max, keypad), `max_load_flow_test`
  (real taps: Weight steps → 50 → + stops at 50 → clearing it).

## 3. Streak: earned days (supersedes the day-count rule of the streak rework)

Rules, exactly (`DayStreakCalculator`):
- **Today does not count until it is earned.** Before training, the streak shows the count up to yesterday.
- **Workout day:** counts the moment the workout is finished. Finish shows a flame and a counter that ticks
  old → new with a pop and a haptic (1.5 s, `StreakCelebration`). A second workout the same day adds nothing.
- **Rest day:** the 1st and 2nd consecutive rest day count when they end, at midnight. A `dayTickProvider`
  (midnight timer + app resume) refreshes the streak without a restart.
- **3rd day in a row without a workout:** when it ends, the streak is lost → 0 (`StreakSafety.lost`). From day 4 the
  Home card says "Streak lost after 3 days without training", and a snackbar announces it once per lost streak.
  It stays 0 until the next workout, which starts a new streak at 1. Opening the app days later gives the same result.
- **Carry-over:** the 177 days still count *on the import day itself*; everything after is computed under these rules.
  The longest streak keeps the lost run (workout days plus its two allowed rest days) and the carry-over.
- The last-chance reminder now says "Train today to keep your N-day streak" with the streak you have (N = shown value).
- Example: workout on the 1st → 1 on the 1st; 1 on the 2nd (morning); 2 from midnight into the 3rd; 3 from midnight
  into the 4th (last chance, train or lose it); 0 from midnight into the 5th.
- Tests: `day_streak_test` (every case above, DST, UTC, carry-over, opening late), `streak_flow_test`,
  `streak_finish_flow_test` (celebration at Finish, nothing on a second workout the same day).

## 4. Lock-screen rest timer (Live Activity)

Native WidgetKit extension `SpotterLiveActivity` (ios/SpotterLiveActivity, bundle id `com.hassan.spotter.LiveActivity`,
iOS 17) plus an own ActivityKit bridge (`ios/Runner/LiveActivityBridge.swift`, channel `spotter/live_activity`); no
package needed. `RestTimerAttributes` is compiled into both targets. Lock screen and Dynamic Island (expanded,
compact, minimal) show the upcoming exercise, a countdown and the next set's target ("Set 3 · 80 kg × 8").
- **Countdown runs on its own:** `Text(timerInterval:)` and a timer `ProgressView`, drawn by the system.
- **Ends** when the rest is skipped or runs out in the app, when the next set is completed (a rest from the set before is
  over, whether or not the new set has its own rest), and at Finish / Discard. ±15 s updates it in place.
- **Backgrounded mid-rest:** the activity is ended with a dismissal date equal to the rest's end, so it keeps counting
  down on the lock screen and removes itself at 0:00 without the app running. Coming back mid-rest it is shown again.
- Feasibility: yes, fully native; needs `NSSupportsLiveActivities` (added) and the user's Live Activities switch.
- Tests: `rest_live_activity_test` (next-set text, rest timer → activity calls, channel), `live_activity_flow_test`
  (real taps; asks native ActivityKit how many are running: ✓ → 1, next ✓ → 1, Skip → 0, Finish → 0).
- Not verified visually: the simulator screenshot did not capture the island (the rest had expired); check on a device.

## 5. Targets during a workout (plan freeze)

**What changed targets mid-workout before (audit).** Stored plans (`suggested_*` on the exercise and its sets) are
written once, at Start, from one coach snapshot; nothing re-runs the engine for exercises already in the workout.
Set completion, Health syncs and readiness / recovery refreshes did **not** rewrite them. What could differ:
1. **Swap exercise, Form reset and Add exercise** each built a *fresh* coach context at that moment, so after a Health
   sync (new readiness, recovery, nutrition) the swapped-in exercise was planned from different inputs than the rest.
2. **Add set** copies the last set's load (looks like a target change after you edited it).
3. **Drop sets** re-derive from their parent's load, and the keypad / drop grid follow live gym settings.
4. The PREV column and Home / Train previews are live views of history and readiness, not the plan.
**New rule.** (a) The coach snapshot a workout started with is kept for the whole workout (`frozenCoachProvider`,
`workoutCoachProvider`): swaps, form resets and added exercises use it, so no Health sync or readiness refresh
re-plans anything. After a cold restart mid-workout there is no snapshot, so the first such action builds one and
freezes it. (b) The one allowed change: when a working set ends **below its rep range**, the *later untouched
working sets of that exercise* move one available step lighter (`adaptLaterSets`; schema v11 `adjusted_from`,
`adjust_reason`). Done sets, sets you typed over, drops, warm-ups and other exercises never change; weight never goes up;
reps targets stay. The changed weight shows a small accent dot; tapping it says what it was, what happened and why.
Tests: `plan_freeze_test`, migration v10 → v11, `plan_freeze_flow_test` (real taps).

## 6. League of Legends tier colors

Source: the official ranked emblems from Riot's client assets (CommunityDragon,
`…/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-<tier>.png`). `tool/tier_colors/sample_emblems.py`
samples the dominant colour of each (centre crop, opaque pixels, no shadows or white highlights, most-populated hue sector,
average of its most vivid third). Only colours are used: the badge artwork stays original. `tierColors` is the single source
for the body map, badges, LP bars, legends, rank-up screen, muscle sheet and Ranks tab.

| Tier | Old | New (sampled) | Contrast vs body base |
|---|---|---|---|
| Iron | #8B8580 | **#A38887** | 4.9 |
| Bronze | #C07A4B | **#BE7F6D** | 4.9 |
| Silver | #B9C6D3 | **#8296BB** | 5.3 |
| Gold | #F2C14E | **#C49258** | 5.8 |
| Platinum | #3FD5C0 | **#2295BF** | 4.6 |
| Emerald | #2EC27E | **#3CD17C** | 8.0 |
| Diamond | #7FA7FF | **#4280CD** | 3.9 |
| Master | #B57BFF | **#AE39E6** | 3.4 |
| Grandmaster | #FF5A6E | **#EB663E** | 4.9 |
| Challenger | #FFE27A | **#B48E52** | 5.3 |

Judgement calls: Challenger's emblem is gold with blue flame edges; the gold body wins by pixel count, and the blue glow is
left out so it stays apart from Platinum and Diamond. Iron is a warm grey because its bevels are brown. All ten keep the ≥ 3:1
contrast the body map needs (`tier_palette_test`).

## 7. Keyboard dismissal

**Root cause.** Only the active workout had a tap-to-unfocus handler; every other screen (Library and pick-exercise
search, sheets, dialogs, settings) had none and no list dismissed on drag, and the custom logger keypad only closed from
its own hide key.
- `KeyboardDismisser` wraps the whole app (`MaterialApp.router.builder`): a tap (a pointer that travelled less than the
  touch slop) outside the focused field, measured on the whole field including its decoration and icons, unfocuses it;
  a finger-drag scroll start anywhere (not inside the field itself) unfocuses it too. Sheets and dialogs are covered
  because they live under the same builder.
- The logger keypad: each exercise's set table and the keypad share one `TapRegion` group; a tap that ends outside
  both commits and closes the keypad. Taps on other cells, ✓, NEXT or the keys are inside.
- Test: `keyboard_dismiss_flow_test` (real taps: Library search field, tap outside, tap on a result, drag the list; workout keypad
  stays for another cell, closes on the page margin).

## 8. Duplicate exercises, rank auto-enable, ranking names

**Root cause (Machine Seated Hip Adduction).** The library holds the same machine several times: the old free-exercise-db
entry `Thigh_Adductor`, the ExerciseDB entry `edbv1_oHsrypV` ("Machine Seated Hip Adduction") and wger's "Seated Hip
Adduction". The Liftoff import (name map "Hip Adduction") and the strength standard point at `Thigh_Adductor`; the workout
used `edbv1_oHsrypV`. So: (1) the workout's exercise had **no history** (Calibration) and **no strength standard**, so it
could not rank, and (2) the Ranks tab showed the *other* id under Liftoff's stored name "Hip Adduction". Abduction had
the same split. The auto-enable rule itself works for any in-app working set (`rank_policy_flow_test`, and now the
exact case in `hip_adduction_flow_test`), but an exercise with no standard shows as hidden / unranked whatever its switch says.
**Fix.**
- `assets/exercise_merges.json` + `ExerciseMerger` (every start, after an import): each duplicate is merged into the
  canonical exercise (the one with the standard / muscle weights). History and routine rows, ego freezes, media rows,
  "counts toward rank" (manual / auto), gym overrides (type, stack, max load), form resets, favourite, extra images,
  ExerciseDB id and instructions move over; sessions without their own name keep the duplicate's name ("what I logged");
  the duplicate row is deleted (a library re-seed brings it back and the next start merges it again). The canonical may be
  renamed (`canonical_name`): Thigh Adductor → **Machine Seated Hip Adduction**, Thigh Abductor → **Machine Seated Hip Abduction**.
  What each merge did is kept in setting `exercise_merges_log`.
- Ranking rows (and hints) use the name the logger shows: your routine's name for the exercise, else the library name, never a
  per-session Liftoff name. Rows already opened the exercise; muscle-sheet rows now do too.
- Auto-enable safety net: Finish switches on every exercise that has a completed working set in the workout (unless switched
  off by hand), whichever path logged the set; the rank change summary is computed with it.
- Tests: `exercise_merge_test` (merge, names, favourites/media, rank settings, idempotent, list consistency, ranks), `hip_adduction_flow_test` (real taps).

**Dedupe audit.** Run over every exercise a routine, a strength standard or the Liftoff name map points at (111), against the
whole library (2,373 entries) by normalised name and equipment, then curated by hand. I only have the Liftoff export, not the
phone's in-app sessions, so in-app history ids could not be audited; the merges below also catch whatever you logged on
them. Merges (duplicate → canonical):

| Duplicate | Canonical | Why |
|---|---|---|
| edbv1_oHsrypV Machine Seated Hip Adduction | Thigh_Adductor (renamed Machine Seated Hip Adduction) | the reported case |
| wger_12 Seated Hip Adduction | Thigh_Adductor | seated machine adduction |
| edbv1_CHpahtl Machine Seated Hip Abduction | Thigh_Abductor (renamed Machine Seated Hip Abduction) | same split |
| wger_1748 Machine Hip Abduction | Thigh_Abductor | |
| wger_1672 Seated Hip Abduction | Thigh_Abductor | |
| edbv1_myfUsKf Machine Seated Reverse Fly | Reverse_Machine_Flyes | reverse pec deck |
| edbv1_f4xtKBj Assisted Standing Pull-up | sp_assisted_pull_up_machine | |
| wger_1527 Pendulum Squat | sp_pendulum_squat | same name |
| wger_1654 Machine Lateral Raise | sp_standing_machine_lateral_raise | |
| wger_173 Crunches With Cable | Cable_Crunch | |
| edbv1_jpgqxiS Cable Standing Crunch | liftoff_standing_cable_crunch | |
| wger_95 Biceps Curl With Cable | Standing_Biceps_Cable_Curl | |
| wger_46 Barbell Lunges Standing | Barbell_Lunge | |
| wger_205 Dumbbell Lunges Standing | Dumbbell_Lunges | |
| edbv1_6TG6x2w Ez-bar Curl | EZ-Bar_Curl | |
| wger_323 Cable Cross-over | Cable_Crossover | |
| wger_158 Close-grip Lat Pull Down | Close-Grip_Front_Lat_Pulldown | |
| wger_222 Facepull | Face_Pull | |
| edbv1_1xHyxys Cable High Pulley Overhead Triceps Extension | Cable_Rope_Overhead_Triceps_Extension | |
| wger_1409 Dragon-flag | liftoff_dragon_flag | the import made a custom one |
| wger_1652 Dumbbell Romanian Deadlift | liftoff_dumbbell_romanian_deadlift | same |
| edbv1_c8f5cSY Side-lying Hip Adduction | liftoff_side_lying_hip_adduction | same |

Looked at and **not** merged (different exercise or load type): Standing Calf Raises (machine) vs wger "Standing Calf Raises"
(body only), Cable Crunch vs Cable Seated Crunch, Seated vs Standing Dumbbell Press, Russian Twist (body vs dumbbell),
Reverse Flyes (dumbbell) vs the machine one, Low Cable Crossover, Machine Triceps Extension vs wger "Machine Dip or Triceps
Extension", Incline T-raise vs Incline Y raise. The `liftoff_*` canonicals only exist after an import; until then their duplicates stay.

## 11. Added exercises start with one working set

"Add exercise" in a running workout creates the exercise with **one** working set (it used to be three), pre-filled with the
coach's weight and reps from your history, not Calibration, whenever the exercise has history (merged history counts, see item 8).
Only an exercise you have never logged calibrates. ADD SET adds more, copying the last set. Covered in `hip_adduction_flow_test`
(one set, prefilled from the Liftoff history; ADD SET → two).

## 12. Rank history and the ladder

- **Rank evolution** (Progress → Ranks, under the overall card): a line of the overall rank over time with the ten tier
  bands (in the tier colors) behind it. `rankEvolution` rebuilds the ranks for every week since the first logged session
  (the Liftoff import included), each from the 90 days before that day, using today's "counts toward rank" switches and
  today's names. Chips below pick a body region or a single muscle to see its own line; the header shows its current rank.
  Tap the line for the date and rank with LP.
- **The ladder** (button under the chart, `/ladder`): all ten tiers, Challenger at the top, each with its badge for every
  division (IV → I; one badge for the apex tiers), what it asks for as best-set e1RM on bench press, back squat and deadlift
  at your current bodyweight (entry per division for the divisional tiers, from each standard's anchors), a "YOU ARE HERE"
  marker with LP on your overall tier, and a list of every ranked muscle positioned on a tier-colored ladder bar.
- Tests: `rank_history_flow_test` (real taps: chart from imported history, region and muscle series, all ten tiers, marker, muscles).

## 10. Rank-up animations

- **During the workout.** The rank strip under each exercise is live: a completed working set of this workout counts at once
  (the finished sessions are the baseline, an override set still doesn't count). When a set raises the lift's rank, the LP bar
  fills from the old score to the new one (wrapping at a division), the badge follows the number and pops in when the
  division or tier changed, with a heavy haptic (a light tick for an LP-only gain). Un-ticking a set lowers it again silently.
- **At Finish.** `SessionSummary.rankGains` lists every rank that rose, LP-only gains and first placements included (the old
  `rankChanges` only had division / tier changes). `RankSequenceScreen` plays them in turn: every lift (biggest gain first,
  each a card with badge, "+N LP", the bar climbing, "from → to" on a rank-up with a pop and haptic), then muscles, regions, then
  the overall rank. About 6.5 s in all (each row 0.4–1 s, fewer rows go slower). A tap anywhere skips. Then the full-screen
  `RankUpScreen` plays only when the **overall** rank changed a division or tier (it used to show for any rank-up); then the
  summary, which still lists the changes statically. No gains → straight to the summary.
- Fixed on the way: the live strip's controller was created lazily inside `dispose` for exercises with no rank (a framework
  assertion at Finish); it now exists from `initState`.
- Tests: `rank_gains_test` (gains, order, placements, falls), `rank_sequence_test` (order, rank-up text, tap skip, ends once),
  `rank_up_flow_test` (real taps: the strip's gap moves when the set is ticked; Finish plays the sequence; skip; summary).
  Every flow that finishes a workout now waits through the sequence with `waitForSummary`.

## 9. Safe area audit

**Method.** `safe_area_flow_test` walks 25 screens and sheets on the iPhone 17 Pro simulator (onboarding, the five tabs and Progress'
Ranks / Lifts tabs, Settings and its sub-screens, exercise detail / history / new / picker, routine editor, the workout, the
keypad, rest sheet, mini bar, exercise menu, add-exercise search, summary, rank-up). On each it takes a full-screen screenshot
(status bar, Dynamic Island and home indicator included, via `tool/device_shots.sh` answering `deviceShot` requests with
`xcrun simctl io screenshot`) into `docs/screenshots/safearea/`, and asserts that at rest no text sits under the status bar /
Dynamic Island, and with every list scrolled to its end none sits under the home indicator.
**Fixed.**
- Bottom sheets that used `useSafeArea: true` only avoid the top and sides, not the home indicator: the routine row editor, the
  program-row editor and the form-check sheet now wrap their content in `SafeArea(top: false)`; the muscle sheet's list adds the
  bottom inset to its padding.
- The workout's list now ends clear of the home indicator (32 pt + the inset) when the keypad is closed; the keypad has its own
  SafeArea.
**Checked and fine:** NavigationBar and the mini workout bar (the bar pads itself), the AppBar screens, Summary / Rank-up /
Onboarding (own SafeArea), the keypad, the rest sheet, dialogs.
**Not verifiable here:** the simulator was running with the hardware keyboard, so the soft keyboard never appeared in the screenshots;
every screen with a field is a Scaffold that resizes for the keyboard (`resizeToAvoidBottomInset` default) and the logger uses its
own keypad, but look at the real keyboard on the phone once.
Run it: `tool/device_shots.sh <sim-id> docs/screenshots/safearea &` then
`flutter test integration_test/safe_area_flow_test.dart -d <sim-id> --dart-define=SHOTS_DIR=$PWD/docs/screenshots/safearea`.

# Round 2

## 1. Valorant rank system

**Ladder.** Nine tiers: Iron, Bronze, Silver, Gold, Platinum, Diamond, **Champion** (Valorant's Ascendant, renamed), Immortal,
Radiant. Iron to Immortal have **3 divisions** (1 → 3, 3 is the highest); Radiant has none. **LP is now RR** (rank rating, 0–100 per
division; Radiant shows uncapped RR above its threshold, 100 RR per "division-sized" step of its slope).
A rank is a number of points, one per division: tier *i* spans [3*i*, 3*i* + 3), Radiant starts at 24.

**Recalibration.** Each standard still has five anchors (beginner … elite, unchanged). The nine tier entries are now:

| Tier | Starts at | Points | Strength (37.5/pt) | Bench press ratio* | Back squat* | Deadlift* |
|---|---|---|---|---|---|---|
| Iron | 0 | 0 | 0 | 0 | 0 | 0 |
| Bronze | beginner | 3 | 112 | 0.60 | 0.75 | 0.90 |
| Silver | novice | 6 | 225 | 0.85 | 1.05 | 1.25 |
| Gold | intermediate | 9 | 338 | 1.15 | 1.40 | 1.60 |
| Platinum | (intermediate + advanced) / 2 | 12 | 450 | 1.325 | 1.625 | 1.85 |
| Diamond | advanced | 15 | 563 | 1.50 | 1.85 | 2.10 |
| Champion | (advanced + elite) / 2 | 18 | 675 | 1.70 | 2.10 | 2.35 |
| Immortal | **elite** | 21 | 788 | 1.90 | 2.35 | 2.60 |
| Radiant | **elite × 1.3** | 24 | 900 | 2.47 | 3.06 | 3.38 |

\* e1RM ÷ (100 kg × (bodyweight ÷ 100)^0.67); machines and cables multiply the anchors by their strictness. The 0–1000 strength score
keeps its cap at 1000 and Radiant at 900 as before, now 37.5 per division point (it was 25).
Before: Iron … Challenger at 0, b, n, (n+i)/2, i, (i+a)/2, a, elite, elite×1.15, elite×1.3. The anchors that hold: elite = Immortal,
elite × 1.3 = Radiant. **Your overall rank** on the real export stays where it was relative to the ladder: **Silver II · 39 LP → Silver 1 · 74 RR**
(strength 260 → 253). The top lift (Walking Lunge) is Silver 3.
- **Migration:** ranks are derived from logged sets, so everything re-ranks on the next frame with no stored rank to convert and no
  rank-down animation (the Finish comparison uses the same model before and after). The ladder migration is v6: rank achievements are
  re-checked silently against the new tiers (nothing is revoked loudly, nothing notifies). The tier achievements moved to the new
  tier indices: "Diamond Hands" = Diamond, "Apex Predator" = Champion (it was Master); the full achievement rework is item 4.

## 2. Valorant colors and badges

**Colors.** The tier colors are Valorant's own: the competitive-tier data of the game (`valorant-api.com/v1/competitivetiers`, which
publishes each tier's UI `color` and `backgroundColor`), cross-checked by sampling the official tier icons. The base color is the game's
`color`; the gradient is a lighter and a deeper shade of the same hue (the game's `backgroundColor` is used for the deep end where it is
deeper, e.g. Diamond and Champion; elsewhere the deep end is derived).

| Tier | Base (official) | Gradient: lighter → deeper |
|---|---|---|
| Iron | #868986 | #B4B7B5 → #5E6160 |
| Bronze | #A5855D | #D1B085 → #7C5522 |
| Silver | #BBC2C2 | #E6EBEB → #8E9696 |
| Gold | #ECCF56 | #F7E9A2 → #C98F1E (pale gold → deep amber) |
| Platinum | #59A9B6 | #8FD8E0 → #2B7F8C |
| Diamond | #B489C4 | #DDBDEB → #763BAF |
| Champion (Ascendant) | #6AE2AF | #A6F5CF → #1C7245 |
| Immortal | #BB3D65 | #FF6E8E → #A02D55 |
| Radiant | #FFFFAA | #FFFFE6 → #E0B040 |

Used for the badges, the body-map fills (per muscle, top-left → bottom-right), RR bars (deep → light) and the legend chips. The contrast
test now checks the base and the light end at ≥ 3:1 and the deep end at ≥ 2:1 against the body map silhouette.

**Badges.** New original artwork, a faceted-crystal style drawn in code (nothing traced from Riot's emblems): a kite-shaped gem cut into
six facets shaded along the tier gradient. Iron is two flat planes, Bronze four, Silver and up are fully faceted with a catch-light;
Silver / Gold / Platinum add 1 / 2 / 3 pairs of side shards; Platinum and up glow from inside; Diamond floats shards around the
crystal; **Champion and Immortal have wings (3 / 4 feathers) and a crown (3 / 5 points)**, Immortal also a bright seam; **Radiant**
adds a pulsing glow, turning rays and a shimmer. The division is **1–3 lit diamond marks** under the gem (unlit ones dimmed); Radiant has none.

## 3. Walking Lunge, again

**Root cause (found by reproducing it from the real export).** Last round's fix was correct for what it touched, and it did run:
the 6 imported sessions went from 35 kg to 17.5 kg (stored 17.50002 because Liftoff keeps pounds). What it did **not** touch:
1. **In-app Lower workouts logged after the import.** They had followed the total-load history, so the owner logged "35 kg per
   dumbbell" and the suggestion before them said 37.5. The fix only converted `source = liftoff` rows, assuming the app's own sets
   were already per dumbbell. Those 35 kg sets were then the newest history, so the next suggestion was 37.5 again.
2. **A workout already started** keeps the plan it was started with (the plan freeze from last round), so its stored suggestion kept
   saying 37.5 whatever the history said.
Not the cause (checked): the migration not running (guarded by a setting, ran), a re-import (re-imports skip known sessions, and new
ones are halved), a duplicate exercise (the import maps Liftoff's Walking Lunge to `sp_db_walking_lunge`, the same id the Lower routine
uses), a suggestion cache (nothing caches suggestions except the per-workout plan above).
**Fix** (`DataFixes.ensureLungeInAppSets`, once, setting `fix_lunge_per_dumbbell_v2`): any non-imported Walking Lunge set heavier than
1.5 × the heaviest converted imported set (26.25 kg) is halved to a dumbbell step (35 → 17.5, 37.5 → 17.5), with its suggested weight, in
finished sessions and in the active one; the stored suggestion of those exercise rows (weight and the "NN kg" figures in its text) too.
Sets at or below the threshold, i.e. what was logged per dumbbell since, are left alone, and a second run changes nothing.
**Result on the real data:** history max 17.5 kg; today's suggestion for the Lower routine is **17.5 kg × 11** (the 20 kg step is +14 %,
so reps extend first).
**Tests** (`walking_lunge_regression_test`, built from the real rows in `test/fixtures/walking_lunge_real.csv`): the stored history after
the import; the suggestion after the import alone; the stuck case (in-app 35 / 37.5 sets and a stale 37.5 plan in an active workout)
converted, idempotent; the suggestion afterwards, with a later per-dumbbell 17.5 set untouched.

## 4. Achievements and weekly challenges

**Achievements: 52, in six categories** (`assets/achievements.json`, schema 2). Families have bronze / silver / gold steps (shown as a
tag and in the detail); the rest are one-offs.
| Category | Achievements |
|---|---|
| Consistency | First Rep; Workouts 25 / 100 / 250; Streak 14 / 30 / 100 days |
| Strength | First PR; PRs 5 / 25 / 100; best lift reaches Silver … Radiant (7); overall Silver … Champion (5); muscles at Gold+: 1 / 5 / 10; every region ranked; every region Silver+ |
| Volume | Lifetime kg 100 t / 500 t / 1,000 t; working sets 250 / 1,000 / 5,000; 10,000 kg in one workout |
| Exploration | Exercises tried 10 / 25 / 50; 10 muscles ranked; all 20 muscles ranked |
| Recovery & readiness | Workouts on a Green readiness day 5 / 25 / 50; sleeping 7+ h in a row (Apple Health) 3 / 7 / 14 nights |
| Program | A week with every routine done: 1 / 4 / 12 weeks; level 5 / 10 / 25 |
Removed because they depended on following suggestions: Patience, Monk Mode, Disciplined, and Comeback (it needed a coach-prescribed
deload). Silently on the next start (ladder migration v7): retired ones disappear, ones the new definitions qualify for unlock without a
notification, rank-based ones the new ladder doesn't support are revoked.
**Weekly challenges.** Three per Monday from a pool of **24** (`weeklyChallengePool`): 3 or 4 workouts; train a region twice (6 regions); top of the
rep range on 2 / 3 lifts; log effort on every working set in 3 workouts; try a never-logged exercise; set 1 / 2 PRs; 60 / 90 working sets;
15,000 / 25,000 kg volume; warm up in 3 workouts; train on a Green day; 4 different regions; 5 sets to failure; 7+ h sleep on 5 nights; a
workout in 75 minutes or less. The pick is deterministic per Monday, never two of a kind, never last week's, and skips the sleep and
Green-day ones when there's no Health data. Challenges still on file from before ("follow every suggestion", "no override") are removed and the
week is topped back up to three.

## 6 (part). Suggestions are just suggestions: rewards

No XP, challenge, achievement or badge looks at the suggestion any more. The per-set XP is a flat 10 for every completed working set (the
+15 "followed it" bonus is gone, and so is the 0 XP for override sets); PR XP and challenge XP are unchanged. The Discipline stat stays on
Profile as information only and says so.

## 5. Weight dropped after hitting the top of the range; unexplained decreases

**The case:** 6–8 reps, last week 10 kg × 8 (top of the range), this week 7.5 kg × 8, no explanation.
**Root cause.** Tracing the round-1 engine step by step for that history (dumbbell grid 2.5, 5, 7.5, 10, 12.5…), only two rules can turn
"10 kg × 8 at the top of 6–8" into "7.5 kg × 8":
1. **The readiness "small deload" on a Red day** (compound lifts): *one step down the grid from last session's top weight, same reps*.
   On a dumbbell grid one step from 10 kg is 7.5 kg, a 25 % cut, with the reps repeated (8). It ran *after* the progression rule, so it
   cancelled a correct "extend the reps / +1 step" and its reason sat only in ⓘ.
2. The plateau deload (−10 % after two sessions without progress, which includes a top-of-range session logged above the prescribed
   effort): 10 × 0.9 = 9 → the next lighter dumbbell, 7.5, reps kept.
The other suspects are cleared: the failure rule would give 7.5 × **6** (reps reset to the bottom); the big-jump rule (10 → 12.5 is +25 %)
only ever *holds* and extends reps; effort saved differently only makes the top "not counted" (same weight, own the reps); a stale ego flag
shows its own "Rule: ego flag" line; the nutrition deficit only ever *held* the weight; duplicate history is item 9. Since the user's
in-app sessions are not in the Liftoff export, the exact session can't be replayed here; the same pattern is in the real data, see below.
**The scan of all my routine exercises** (`docs/SUGGESTION_DECREASES_BEFORE.md`, round-1 engine, Green and Red readiness): 23 suggestions were
lower than the last working weight, **2 of them right after a top-of-range session**, both by the Red small deload:
Chest Supported T-Bar Row 57.5 kg × 8 (top of 6–8) → 55 kg × 8, and Walking Lunge 17.5 kg × 10 (top of 10) → 15 kg × 10. The other 21: a Red deload
after a non-top session (7), or the −5 % "a set fell below the range" rule (14: Lying Leg Curl 85 → 80, Close-Grip Lat Pulldown 68 → 64 and 52 → 48,
Cable Wrist Curl 40 → 36, Cable Reverse Wrist Curl 12 → 10, Cable Lateral Raise 8 → 6, …).
**New rules** (`SuggestionEngine`):
- **Top of the range at the prescribed effort never leads to a lower weight:** +1 step, or the same weight with the reps pushed past the range when
  the step is over 10 %. Property test: for **every exercise in the library** (2,355) × 3 weights × 4 ranges × RIR 0 / 2 × Green / Yellow / Red × fatigued × deficit
  (≈ 170,000 cases) the next weight is the same or the next step, never lower, and carries no decrease note.
- **Missing reps hold the weight** and try again for the bottom of the range. Only after **3 sessions in a row below the range at the same weight** does the
  exercise show a chip, **"Lighter option: X kg"** (−5 % on the next available weight): tapping it moves the sets not done yet, with the target-changed
  marker; it is never applied automatically. (This removes the −5 % rule, the "no third drop" and "after a jump" special cases, and the plateau deload.)
- **Red readiness repeats** (last session's weight and reps); the weight is never lowered for readiness, recovery or nutrition.
- **No silent decreases:** whenever the target is below last time's weight for that slot, the block shows **"↓ from 10 kg: reason"** inline (no ⓘ needed).
  The only remaining ways down are the ego-flag freeze (5 % below the base, with its days left), a calibration or an exercise with no sets at that rep range
  re-anchoring the load, a max-load cap, and a weight that doesn't exist in the gym. Each states itself; an unexplained one trips a debug assertion, and a 20,000-history
  random test asserts "lower ⇒ note". A back-off slot with no sets at its own rep range yet has no "last time", so no note.
**After (same real data, same scan):** 0 suggestions below the last working weight (`docs/SUGGESTION_DECREASES.md`); `docs/SUGGESTIONS_BEFORE_AFTER.md` is the
re-run before/after table (round-1 engine vs now): 17 of 37 slots change.
**Tests:** `suggestion_engine_test` and `suggestion_rework_test` (rewritten to the new rules), `no_silent_decrease_test` (the two property tests and the notes),
`no_silent_decrease_flow_test` (real taps: three bad sessions → weight held and the chip; the chip applies; an ego flag shows the inline note).
