# Spotter: Flutter → React Native port spec

**Phase 1: analysis only.** No React Native code has been written and the Flutter repo has not been modified.
Source analysed: `spotter-app` working tree on top of `d8b74e8` (Flutter, Dart SDK ^3.12, Riverpod 3, drift schema v12). The tree had uncommitted changes from 2026-10-27 (modified: `common.dart`, `program_widgets.dart`, `rank_evolution.dart`, `routine_repository.dart`, `active_workout_screen.dart`, `exercise_block.dart`, `routine_editor_screen.dart`; untracked: `replace_sheet.dart`, `integration_test/small_fixes_flow_test.dart`). The spec describes the tree as it was on disk, not the commit. Written 2026-10-30.

## 0. How to read this document

- **Parts 1–10 are the spec.** They are written to be read top to bottom and link into the appendices for detail.
- **Appendices A–E are the evidence.** Each is a section-by-section dump of one area of the code with the Dart/Swift quoted verbatim and a `path:line` citation next to every number. When a rule in Parts 1–10 matters to you, check it against the quote in the appendix.

  | Appendix | Area |
  |---|---|
  | A | Ranks and body ranking |
  | B | Gamification (streak, XP, quests, achievements), readiness, muscle recovery |
  | C | Coach: suggestion engine, ego guardrail, energy, load grids, set kinds, settings |
  | D1 | Screens, flows, navigation, UI components, design tokens |
  | D2 | Data models, migrations, logging/finish pipeline, program, library, import/export, media |
  | E | State management (every provider), dependencies, platform integrations |

- **Code wins over docs.** `docs/DECISIONS.md`, `docs/PLAN.md`, `docs/DESIGN.md` and parts of the README are stale in many places (old tier names, a "−5 % deload" rule that no longer exists, weekly-goal wording, 2.25 kg plates). Every disagreement found is listed as an `OQ:` in the appendices. Treat those docs as history.
- **Quote verification.** I checked every fenced code block that cites a source file against that file, line by line. About 3,600 Dart/Swift lines were checked and every line matched except three kinds, none of which change a number or rule:
  1. lines the author marked `(condensed)` or abbreviated with `...` (e.g. a `case "sync": ...` summary);
  2. re-wrapped map literals (`media_matcher.dart` token maps, export CSV column list);
  3. non-Dart excerpts (JSON asset samples, the achievements table, entitlements XML).

  Appendices B/C contain a few blocks whose file is named only by a bare `:254-316` range; those matched when searched across the repo. Anything *not* in a fenced block (prose, tables, line-number claims) is the analysts' reading and is **not** mechanically verified. Spot checks I did by hand against source: XP constants, level curve, readiness weights and bands, `maxRestDays = 2`, the rank ladder, and the suggestion engine's step 0–6 all match.
- **Not read in full** (so not spec'd in detail): the Swift Live Activity views (`ios/Shared/WorkoutActivityViews.swift`, `ios/SpotterLiveActivity/WorkoutLiveActivity.swift`; they are native code you would reuse, not port), debug-only screens (skimmed), `*.g.dart`, generated migration test schemas, `docs/IMPORT_SUMMARY.md` beyond its header, and the Python build tooling under `tool/` (listed in E §3.7). `FireStreak` painter lines 93–152 are summarised, not quoted (B §2.1); re-read `fire_streak.dart` when porting it.

### 0.1 Where the code differs from the brief

These are facts a reader of the brief would otherwise get wrong:

1. **"Body ranking" is the rank system.** There is no separate feature: a muscle's rank comes from its exercises' best scores, regions average muscles, overall averages regions (A §1.9). 20 muscles, 6 regions, 9 tiers (Iron … Olympian, Immortal) with 3 divisions each.
2. **Streak is day-based, not weekly.** Two rest days in a row are allowed; a third resets it. There is no weekly goal and no fixed training days (B §1.1). Some UI strings and docs still say "weeks"/"goal" (stale).
3. **Suggestions never lower the weight by themselves.** Missing reps holds the weight; Yellow, Red and "Fatigued" all mean "repeat last session". The only ways down are the ego freeze, calibration re-anchoring, a max-load cap, and an off-grid weight (C §0, §1.4).
4. **Recovery is not display-only.** README/DECISIONS say it is, but the suggestion engine reads each exercise's Fatigued prime movers (C §1.4 step 4; B OQ). The port should follow the code.
5. **The finish screens run Summary → Rank → Streak → Home**, not rank → streak → summary (D1 §1.10).
6. **There is no standalone history/calendar screen.** Sessions are reachable from Exercise detail and from the Progress screen (D1 §1.11).
7. **Much more than the brief lists exists:** a Min-Max program engine (12-week program, warm-up pyramids, techniques), Liftoff CSV import, ExerciseDB GIF matching, a merged exercise library (free-exercise-db + wger + ExerciseDB V1), a Live Activity, rest-timer and streak notifications, JSON/CSV export, XP/levels/quests/achievements, ego-lift guardrail, muscle recovery model, bodyweight-what-if rank projections, and an in-app error log.
8. **Android is a stub** (HealthKit returns false/empty, Live Activity is a no-op, no notification permission). This is an iOS app.

---

# Part 1. Feature inventory

Full screen-by-screen detail is **Appendix D1 §1–2** (about 330 lines, including every menu action and the exact order of effects when a set is completed). This is the map.

## 1.1 Screens

| Route | Screen | What it does |
|---|---|---|
| `/onboarding` | Onboarding (3 pages) | Bodyweight (30–300 kg), connect Apple Health (+ notification permission), streak explainer, then `onboarded = true`. |
| `/home` (tab) | Home | Hero card (overall rank badge, level, XP), readiness card, recovery card, "no bodyweight" prompt, primary action (Resume / Start next routine), ego-flag banners, 3 weekly challenges, streak card with Mon–Sun dots and safety line. Pull-to-refresh syncs Health. |
| `/train` (tab) | Train | Routine list (reorderable), create routine, start routine, start empty workout, resume. |
| `/library` (tab), `/pick-exercise` | Library | Search with aliases, filters (favorites, muscle, equipment), favorite stars, create custom exercise. Same screen in "pick mode" returns an exercise id to the caller. |
| `/progress` (tab) | Progress | Ranks (body map, regions, muscles), Lifts, history. Query params `tab`, `mode`, `back`, `group`. Owned by Appendix A §2.1; `?group=chest` resolves to nothing (A OQ). |
| `/profile` (tab) | Profile | Level and XP, streak and longest, sessions this week, discipline score, bodyweight, achievements grid grouped by category. |
| `/workout` | Active workout (full screen) | Core logging UI: exercise blocks, set table, custom keypad, rest timer, supersets, set types, swipe actions, replace/add/remove, finish. |
| `/summary`, `/rank-sequence`, `/streak` | After-workout chain | Summary (XP, stats, PRs, rank changes, guardrail, unlocks, Health save status), rank-up / rank-sequence animation, streak animation. Each step has Skip. |
| `/routine/:id` | Routine editor | Rename, delete, add/replace/remove/reorder, superset link, targets (reps, sets, RIR, rest), program-row overrides. |
| `/exercise/:id` (+ `/history`, `/edit`) | Exercise detail | Tabs About (demo GIF, Jeff's video, muscles, steps, photos), Rank (ladder, "Count toward ranks" switch), Stats (e1RM chart, best sets), History. Custom exercises can be edited/deleted. |
| `/exercise-new` | Custom exercise | Name, primary/secondary muscles, equipment, compound/isolation, notes. |
| `/session/:id` | Session detail | Per-exercise sets with override/ego marking; tap a set to correct KG/REPS; delete session. |
| `/ladder` | Ladder | Threshold tables (A §2.3). |
| `/settings` (+ `/errors`, `/import-liftoff`) | Settings | Training defaults, gym equipment (dumbbells, plates, stacks, per-exercise overrides), bodyweight, Apple Health, notifications, program reinstall, Liftoff import, streak offset and reminder, JSON/CSV export, error log (long-press the version label). |
| `/settings/debug/*` | Debug menu and previews | `kDebugMode` only: fake Health, seed 12 weeks, media matching, exercise audit, badge gallery. **Do not port.** |

## 1.2 Cross-cutting flows

(Each is specified step by step in D1 §2; the ones with non-obvious rules:)

- **Start workout:** if one is active, just open it. Else build a coach context (history, readiness, recovery, gym, energy, freezes), **freeze it for the whole session** (a Health sync mid-workout never re-plans), write the plan once at start (D2 §2.1.2).
- **Log a set:** keypad types into an in-memory buffer; commits on cell change, NEXT, tap-outside, menu action, app backgrounding, Finish. ✓ re-reads the DB row, toggles complete, may ask an "override reason" sheet (heavier than suggested **and** below the rep range), adapts later sets after a miss, shows praise, starts the rest timer, may offer a "form reset" (D1 §1.9).
- **Rest timer:** end time persisted in settings, so it survives app kill; a local notification and the Live Activity are scheduled from it; at 0 a heavy haptic fires only while a `WorkoutClock` is mounted (D1 OQ; E §1.2).
- **Finish:** commit keypad → complete a typed-but-unticked set quietly → warn if 0 working sets or sets pending → offer "Update routine / Keep routine as is" if the session differs from its routine → Calculating (min 1.8 s) → `FinishService.finish` (D2 §2.1.5 gives the exact order) → Summary → Rank → Streak → Home.
- **Session history edits:** correct individual sets, delete whole session. No add/remove set, no rename.
- **Liftoff import:** pick CSV → non-destructive preview with name mappings (user can re-map) → commit; idempotent via `(source, external_id)`; bodyweight required; imported sets count as taken to failure (D1 §1.15, D2 §2.7).
- **Export:** JSON or CSV via the share sheet (D2 §1.7).

---

# Part 2. Data models

Complete column lists, defaults, FKs, indexes and the full v1→v12 migration code are in **Appendix D2 §1**. Summary:

- **Engine:** SQLite via drift, file `spotter.sqlite`. `DateTimeColumn` is stored as **INTEGER unix seconds** (local `DateTime` on read). Booleans are `INTEGER 0/1`. List/JSON columns are TEXT. `PRAGMA foreign_keys = ON`. `schemaVersion = 12`.
- **Indexes** created only in `onCreate` (not `onUpgrade`): `idx_sessions_started`, `idx_session_ex_session`, `idx_session_ex_exercise`, `idx_sets_session_ex`, `idx_routine_ex_routine`. The unique `idx_sessions_external (source, external_id)` is created in both paths. (D2 OQ-1: users who upgraded from v<4 may lack the five.)

## 2.1 Tables (16)

| Table | PK | Purpose and key fields |
|---|---|---|
| `exercises` | `id` TEXT | Library: dataset id (`Barbell_Bench_Press_-_Medium_Grip`, `sp_*`, `wger_*`, `edbv1_*`, `liftoff_*`, `custom_*`), name, primary/secondary muscles (JSON, 17 dataset muscle names), equipment, mechanic (`compound`/`isolation`), instructions, images, `extra_images`, `source`, `credit` (JSON), `edb_v1_id`, `is_custom`, `is_favorite`, `notes`. |
| `routines` | autoinc | name, position, `created_at`, `program_day`. |
| `routine_exercises` | autoinc | FK routine (CASCADE), FK exercise, position, `rep_min/max`, `target_sets`, `rest_seconds`, `target_rir` (2), `program_slots` (JSON), `program_relation` (`program`/`substitution`/`swap`/`extra`), `program_exercise`, `display_name`, `override_rep_min/max`, `superset_group`. |
| `sessions` | autoinc | `routine_id` (no FK), name, `started_at`, `ended_at`, notes, `status` (`active`/`finished`), `readiness_score/band` snapshot, `health_synced`, `xp_earned`, `source` (`app`/`liftoff`), `external_id`. |
| `session_exercises` | autoinc | FK session (CASCADE), FK exercise, position, rep range, `target_sets`, `rest_seconds`, `target_rir`, **suggestion snapshot** (`suggestion_kind`, `suggested_weight/reps/sets`, `suggestion_json`), program fields, `rest_enabled`, `superset_group`, `routine_exercise_id` (no FK), `targets_edited`. |
| `workout_sets` | autoinc | FK session_exercise (CASCADE), position, `is_warmup`, `weight` (kg, negative = assisted), `reps` (**seconds for `hold`**), `rpe`, `completed`, `completed_at`, suggestion snapshot, `is_override`, `override_reason`, per-set target range/RIR, `technique`, `set_type` (`drop`/`myo`/`hold`/null), `partials`, `adjusted_from`, `adjust_reason`, `rest_seconds` (actual rest taken before the set). |
| `daily_metrics` | `date` TEXT yyyy-MM-dd | HRV, resting HR, sleep minutes, active energy, dietary kcal, protein, `readiness_score/band`, `calibrating`, `explanation`. |
| `body_weights` | autoinc | `measured_at`, `kg`, `source` (`health`/`manual`). |
| `ego_freezes` | autoinc | `exercise_id`, `started_at`, `until`, `base_weight`, `reason`. |
| `xp_events` | autoinc | `at`, `amount`, `reason` (`session`/`quest`), `session_id`, `week_start`. |
| `achievements_unlocked` | `key` | `unlocked_at`. |
| `quests` | autoinc | `week_start` (Monday), `key`, `params` JSON, `title`, `completed_at`. |
| `app_settings` | `key` | KV store (all settings, onboarded flag, rest-timer end, streak offset…). |
| `media_matches` | `exercise_id` | ExerciseDB V1 GIF match (`edb_id`, `gif_url`, `confidence`, `source`). |
| `pinned_videos` | `exercise_id` | **Unused** feature (only touched by the library merger). |
| `edb_v2_maps` | `exercise_id` | ExerciseDB V2 mapping; V2 is off by default and `candidates` is always `'[]'`. |

Also stored but **not** in DB: ranks (always recomputed from history, never persisted), form resets and gym equipment (JSON values in `app_settings` under keys `form_resets`, `form_reset_offered` and `GymEquipment.key`; see D2 §1.4 and C §1.13), error log (`error_log.jsonl`, max 300 entries).

## 2.2 Relationships

`routines 1—N routine_exercises` (cascade) · `sessions 1—N session_exercises 1—N workout_sets` (cascade) · `exercises 1—N routine_exercises/session_exercises` (no cascade). **Soft, unenforced links** that can dangle: `sessions.routine_id`, `session_exercises.routine_exercise_id`, `xp_events.session_id`, `ego_freezes.exercise_id`, the media tables. `routines.program_day` and `program_slots` reference ids in `assets/programs/min_max_canonical.json`.

## 2.3 Domain value types the logic runs on

`LoggedSet`, `ExerciseSessionLog`, `HistSession`/`TrainingHistory`, `SuggestionInput/Suggestion`, `CoachContext`, `GymEquipment`/`WeightGrid`, `RankScore`/`ExerciseRank`/`RankSummary`, `DayStreak`, `ReadinessResult`, `RecoveryState`, `SessionSummary` (C §2, A §3.2, B §3.2). The set predicates everything depends on:

- `isWorking = !isWarmup && completed` (drop sets included)
- `isFollowUp = isDrop || isMyo || isHold`
- `isEgoSet = isOverride && belowRange`
- `isValidForRecords = isWorking && !isFollowUp && !isEgoSet`
- `workingSets (exercise log) = isWorking && !isFollowUp`

## 2.4 Bundled assets

| Asset | Size | Role |
|---|---|---|
| `exercises.json` | ~1.0 MB | free-exercise-db library |
| `library_sources.json` | ~0.8 MB | merged free-exercise-db + wger (built by `tool/library/build_library.py`) |
| `exercisedb_v1.json` | ~0.37 MB | ExerciseDB V1 metadata (GIFs download on first view) |
| `strength_standards.json` | 37 KB | per-exercise anchors (beginner…elite) |
| `exercise_muscles.json` | 10 KB | exercise → 20-muscle contribution weights |
| `body_map.json` | 42 KB | SVG paths for the body figure |
| `programs/min_max_canonical.json`, `my_routines.json` | 42 KB, 10 KB | program definition and the owner's 5 routines |
| `achievements.json` | 13 KB | 52 achievement defs |
| `edb_v2_map.json`, `exercise_merges.json`, `extra_exercises.json`, `liftoff_name_map.json`, `media_overrides.json` | small | mappings |

Seeding is versioned (`exerciseDatasetVersion = 5`, `mediaMatchVersion = 4`) and preserves `is_favorite` across re-seed (D2 §1.5).

---

# Part 3. Business logic

The exact formulas, thresholds and edge cases are quoted in the appendices. This part is an **index of the rules**, short enough to review, with the appendix section to verify each against. Where a number appears here, it is one I checked against the quoted code.

## 3.1 Ranks and body ranking (Appendix A)

| Rule | Detail | Verify |
|---|---|---|
| Ladder | One continuous double `value` = **points**: 1 point per division, 3 divisions per tier. Iron…Olympian = points 0–24 (8 tiers × 3), **Immortal ≥ 24**, uncapped, no divisions. Division label 1–3 (3 highest). RR = 0–99 within a division; Immortal RR is uncapped (100 per point). Epsilon `1e-9` guards boundary floats. | A §1.1 |
| Strength score | `round(value × 37.5)` clamped 0–1000 (Iron 1 = 0, Immortal = 900). | A §1.2 |
| Scoring e1RM | `load × (1 + min(reps + RIR, 20) / 30)` with `RIR = 10 − (rpe ?? 9)`. Own formula, **not** the general `estimateOneRm` used by PRs and the Lifts tab (no cap there). Unscored if `reps ≤ 0` or `load ≤ 0`. | A §1.3 |
| Which sets count | Completed, non-warm-up, not drop/myo/hold, not ego sets, within the **90-day** window, each scored at **the bodyweight of the day it was done** (timeline interpolated linearly between weigh-ins). No bodyweights at all → empty rank summary. | A §1.4 |
| Standard → threshold | Each exercise has a standard of five anchors (e1RM ÷ bodyweight at beginner…elite), multiplied by a strictness (machine/cable stricter), turned into tier thresholds by `thresholdsFromAnchors`; ratio → score is piecewise linear. | A §1.5, §1.7 |
| Bodyweight scaling | Non-bodyweight kinds: ratio = `e1RM ÷ (100 × (bw/100)^0.67)` (allometric). Bodyweight-loaded kinds (pull-ups, dips…): plain `e1RM ÷ bw`, and the load **includes** bodyweight (assisted machines subtract assistance). | A §1.6 |
| Muscle rank | Contribution-weighted mean of the best scores of the exercises that train it (weights from `exercise_muscles.json` or derived by keyword in `muscle_mapping.dart`). | A §1.9, §1.10 |
| Region / overall | Region = mean of its **ranked** muscles; overall = mean of ranked regions. Identical scores average back to the same rank. | A §1.9 |
| Count toward ranks | Per-exercise toggle. Default rules: routine exercises on, imported-only off, a completed set switches an exercise on, a manual off stays off, adding to a routine switches it on. | A §1.11 |
| Next-rank target | Weight/reps needed for the next division; bodyweight what-if searches ±10 % of the 7-day mean bodyweight on a 0.5 kg grid and only upward. | A §1.12, §1.13 |
| Evolution chart | Weekly recompute of overall/region/muscle scores over the whole history (unmemoised O(history), A OQ). | A §1.14 |
| Rank-up detection | On finish, before/after diff per lift, muscle, region, overall; a change is any label change (division or tier). Only overall and lift gains are animated. | A §1.15 |
| Ladder migration | One-shot at startup when `rank_ladder_version` is behind; silently revokes old rank-based achievements. | A §1.16 |

## 3.2 Streaks, XP, quests, achievements (Appendix B)

| Rule | Detail | Verify |
|---|---|---|
| Streak day | A day counts when a **finished** session with ≥ 1 completed working set **started** that local day. Several sessions in a day count once. | B §1.1 |
| Streak rule | `maxRestDays = 2`. A gap of more than 3 calendar days between workouts breaks the run; if `today − lastWorkoutDay > 3` the streak is `lost` (days = 0). Today counts only once earned. Day math uses `Date.UTC(y,m,d)/86400000` on the local date (DST-proof). | B §1.1 |
| Liftoff offset | `StreakOffset(date, days)` carries an imported streak (177 at import) and is editable in Settings; days at or before the offset date are ignored. | B §1.1 |
| Safety states | trainedToday / safe / oneRestDay / lastChance / none / lost, each with fixed Home text (D1 §1.3). | B §1.1, D1 |
| Reminder | Notification at **18:00** local on the last-chance day, only if enabled (default on), streak > 0, and 18:00 still in the future. | B §1.1, E §3.3 |
| XP | 10 per completed working set, 50 per PR, 40 per quest. Following, beating or ignoring the suggestion earns the same. Override sets earn no XP (summary copy). | B §1.2 |
| Level | Cost to go from level L to L+1 = `round(100 × L^1.5)`. | B §1.2 |
| PR | `previousBest > 0 && sessionBest > previousBest + 0.05`; the first-ever session of an exercise is a baseline, not a PR. Uses the general e1RM over valid-for-records sets. | B §1.2 |
| Quests | 3 per Monday-week from a pool of 24 (14 kinds), chosen by a **seeded Dart shuffle**, reward 40 XP awarded only inside the finish pipeline. A JS port will choose different quests for the same Monday (see Part 9). | B §1.4 |
| Achievements | 52 definitions in `achievements.json`, 16 metric types, evaluated at finish. DECISIONS.md names `streak_4`/`streak_12` that do not exist (stale). | B §1.5 |

## 3.3 Readiness and muscle recovery (Appendix B)

| Rule | Detail | Verify |
|---|---|---|
| Inputs | HRV (SDNN), resting HR, sleep. Weights **0.4 / 0.3 / 0.3**. Bands **Green ≥ 55, Yellow ≥ 40**, else Red. A short-sleep penalty and a 1.5× training-load penalty also apply. | B §1.6 |
| Baseline | 30-day baseline, **14 days to calibrate**; while calibrating the app shows "Calibrating (X/14 days)" and treats the day as Green for suggestions. | B §1.6, README |
| Health aggregation | Night window `[D−1 18:00, D 12:00)` local, merged asleep intervals, HRV mean within the sleep span, resting HR mean in `[D−1 00:00, D 12:00)`. | E §3.1, B §1.7 |
| Recovery model | Each working set adds fatigue to its muscles: contribution × effort factor (F 1.0, 1-left 0.85, 2-left 0.7, 3+ 0.5; drop/myo/hold 0.5; unknown effort = failure). Decays with half-life **48 h** (quads, hamstrings, glutes, lats, upper back, upper/lower chest) or **30 h** (the rest), slowed on Yellow (×0.85) and Red (×0.7). `fullFatigue = 12`. Bands: Ready ≥ 90 %, Recovering ≥ 60 %, Fatigued < 60 %. 14-day horizon. | B §1.8 |

## 3.4 The coach (Appendix C)

**Double progression on a weight grid.** The engine only ever suggests loads that exist in the user's gym (plates, dumbbell list, stack). Steps, in order (all quoted in C §1.4):

0. History = sessions with ≥ 1 working set; a form reset drops older sessions; no history and no reset → **calibration** (C §1.5).
1. Base: after a calibration or when there is no history at this rep range, re-anchor from the best e1RM of the last 3 sessions: `weight = e1RM / (1 + (range.min + RIR)/30) − bodyweight`, reps = range.min. Otherwise judge the **last** session only:
   - any working set below `range.min` → **hold** the weight (`addReps`); a lighter option appears (never applied) after **3** such sessions in a row at the same weight;
   - all sets at `range.max` at the prescribed effort (`RPE ≤ 10 − targetRIR`; unlogged RPE counts as 9) → next weight on the grid, reps reset to `range.min`; if the jump is > **10 %** of load, first extend to `max + 2 … max + 3` reps; at the machine's max load reps keep growing;
   - otherwise same weight, `min(range.max, bestReps + 1)`.
2. Set count never changes.
3. **Ego freeze:** `weight = min(weight, snapDown((base + bw) × 0.95 − bw))`, reps = `range.min`.
4. **Readiness/recovery:** Green and nothing Fatigued → no change. Yellow, Red or any Fatigued prime mover → if the weight is ≥ last top and there is no freeze, **repeat last session** (weight = last top, reps = best reps at that weight clamped to `[min, max + 3]`). Never lowered.
5. **Nutrition/bodyweight trend:** explanatory text only.
6. Snap to the grid (`snapDown` if the exact value isn't on it). **Every decrease must carry a stated reason** (`downNote`); the code asserts this.
7. Result carries a visible "why" chain (`Base:`, `Rule:`, `Readiness:`, `Recovery:`, `Nutrition:`, `Weight:`).

Other coach rules (all in Appendix C):

- **Ego guardrail** (runs at finish, not in the engine): an override set that is below the bottom of the rep range is an *ego set*; it is excluded from PRs and ranks and can create a 7-day freeze row that the engine reads. "Good override" = heavier than suggested but inside the range. (C §1.9)
- **Load grids per equipment kind** (barbell pair steps, one- vs two-sided plate machines, stacks, dumbbell lists, per-exercise overrides, max load). (C §1.6, §1.7)
- **Set kinds:** working, warm-up, drop (pre-filled 20–25 % lighter, no rest), myo (5 s rest, 2 reps), static hold (REPS = seconds). Program technique follow-ups. (C §1.12)
- **Rest:** exercise rest seconds; after the last warm-up 90 s; none inside a superset until the round is complete, then the longest member rest. (C §1.12, D1 §1.9)
- **Settings and defaults:** compound reps 6–10, isolation 10–15, default RIR 2, rest 150 s / 90 s, streak reminder on, smallest plate 2.5 kg (migrated from 2.25). (C §1.14, E §1.4)

## 3.5 Logging, finish and history (Appendix D2 §2.1)

The finish pipeline's **order of operations** is quoted in D2 §2.1.5. Two facts to know before porting: only "prune empty sets" and "set status" run inside a DB transaction (the rest is sequential and **not atomic**; D2 OQ), and rank changes, quests, achievements and XP are computed from a before/after of the whole history.

---

# Part 4. State management

Full provider table (≈45 providers, with what each watches and who writes it) is **Appendix E §1.4**.

**Today:** Riverpod 3 with hand-written providers. Data flows `drift tables → repository classes → StreamProvider/FutureProvider → derived sync Providers (pure domain calc) → ConsumerWidgets`. Writes go straight from UI into repositories; DB streams re-emit and everything recomputes.

**What owns what:**

| State | Owner | Persistence |
|---|---|---|
| All domain data | SQLite | persistent |
| Settings, onboarded flag, rest-timer end/total, streak offset | `app_settings` KV table | persistent (**not** shared_preferences, which is declared but unused) |
| **Active workout "draft"** | DB rows (`sessions.status='active'` + exercises + sets), written on every edit | survives app kill |
| "Minimized" workout | no state; the route is just popped and `MiniWorkoutBar` shows whenever an active session exists | n/a |
| Coach context for the running workout | `frozenCoachProvider`, in memory | rebuilt and re-frozen after a cold restart |
| Praise count, last summary, rank-target mode toggle, Health sync status, rest `_activity`/skip marks | in-memory notifiers | lost on restart |
| Whole finished history | `historyProvider` loads **all** finished sessions into memory | derived |

**The hub:** `historyProvider` reloads the entire history whenever finished sessions change (a version counter driven by `watchFinishedChanges()`), and ranks, evolution, recovery, group volume, overload, streak, marks, discipline, achievements, quests and weight grids all derive from it. There is no manual invalidation.

**Time:** `clockProvider` is an injectable `now`. Only the streak providers watch `dayTickProvider` (bumped at each local midnight and on resume), so readiness/recovery "today" does not refresh at midnight until data changes (E §4 OQ).

**Bootstrap order** (before first frame, E §1.1): load muscle table → seed exercises → merge duplicates → install program routines and fix-ups → data fixes → mark saved values fixed → ensure smallest plate → migrate rank exclusions → seed EDB map. After the first frame, each independently try/caught: notifications init, Health sync, rank-ladder migration. App-level listeners keep the Live Activity, streak reminder, equipment re-snap and media prefetch in sync (D1 §0).

---

# Part 5. Navigation map

Full table with params and transitions: **Appendix D1 §3**.

```
/onboarding                       (redirect target while !onboarded)
Shell (5 tabs, all kept mounted, 180 ms fade; MiniWorkoutBar above the tab bar)
  /home  /train  /library  /progress?tab&mode&back&group  /profile
Root-level (cover the tab bar, push):
  /workout                         ← push from Home/Train/MiniWorkoutBar
  /summary → /rank-sequence → /streak → /home      (pushReplacement chain, fade for last two)
  /ladder   /pick-exercise (returns exercise id)   /exercise-new
  /routine/:id   /exercise/:id (+/history → Stats tab, +/edit)   /session/:id
  /settings (+/errors, +/import-liftoff, +/debug/* in debug builds only)
```

Redirect, verbatim from `router.dart:70-75`: not onboarded and not at `/onboarding` → `/onboarding`; onboarded and at `/onboarding` → `/home`. Driven by a `ValueNotifier` fed from settings. No deep links or URL schemes are registered. Minimize pops `/workout` (or `go('/home')` if it cannot pop); there is no back-guard on the summary chain (D1 OQ).

---

# Part 6. Dependencies

Version pins and where each is used: **Appendix E §2**. The Flutter → React Native mapping (my proposal, to be spiked where marked):

| Flutter package | Used for | Proposed RN/Expo replacement | Notes |
|---|---|---|---|
| flutter_riverpod 3.4.3 | state/DI | **Zustand** + pure selectors | see Part 10.3 |
| drift 2.35.2 / drift_flutter | SQLite ORM, streams | **expo-sqlite** + typed repos, `PRAGMA user_version` migrations | no reactive streams; see Part 10.3 |
| go_router 18 | routing, shell, redirect | **Expo Router** | |
| health 13.3.2 | HealthKit read/write | HealthKit library with an Expo config plugin (spike) | needs dev client, not Expo Go |
| fl_chart 1.2 | line charts, tooltips | victory-native (Skia) or react-native-gifted-charts | |
| flutter_local_notifications 22.3 (+ timezone, flutter_timezone) | rest-done, streak reminder | **expo-notifications** | `timezone`/`flutter_timezone` unnecessary: JS `Date` is local |
| share_plus 13.3 | export share sheet | expo-sharing (+ expo-file-system) | |
| file_picker 13.1 | choose Liftoff CSV | expo-document-picker | |
| path_provider / path | temp + support dirs | expo-file-system | |
| youtube_player_iframe 6.0 | program videos | react-native-youtube-iframe (WebView) | |
| flutter_cache_manager 3.4 | GIF cache | expo-image disk cache or expo-file-system | see Part 8 (GIF control) |
| http 1.6 | ExerciseDB V2 | `fetch` | V2 off by default; propose dropping |
| intl 0.20 | dates/numbers | `Intl` + small helpers | |
| path_parsing 1.1 | SVG path parsing for body map | react-native-svg | parses path strings natively |
| **declared, never imported:** shared_preferences, url_launcher, cached_network_image, collection | nothing | **drop** | E §4 OQ |
| fonts Barlow, Oxanium (TTF bundled, OFL) | typography | expo-font with the same TTFs | weights 400–700 / 600–800 |

Dev-only (not ported): drift_dev, build_runner, flutter_launcher_icons, integration_test. The Python scripts in `tool/` that build the JSON assets keep working unchanged and should stay as the source of truth for `strength_standards.json` / `exercise_muscles.json`.

---

# Part 7. Platform integrations

Detail with quoted channel names, type lists and notification ids: **Appendix E §3**.

| Integration | What it does | Data / contract |
|---|---|---|
| **Apple Health read** | HRV SDNN, resting HR, sleep (asleep/core/deep/REM only), active energy, body weight, dietary energy, dietary protein. | Read-only except workouts. Sync window default 45 days; body mass history 365 days; sync on launch, resume, Home pull-to-refresh, readiness card, Settings. iOS never reveals read denial: "missing" is inferred from empty results. |
| **Apple Health write** | One `WORKOUT`, `TRADITIONAL_STRENGTH_TRAINING`, session start/end, title = session name, on Finish. | Success sets `sessions.health_synced`. |
| **Permissions copy** | Info.plist usage strings (read + update); entitlement `com.apple.developer.healthkit` true, `.access` empty. | Read string omits nutrition (OQ). |
| **Live Activity** | WidgetKit extension `SpotterLiveActivity` (bundle `com.hassan.spotter.LiveActivity`, iOS 17) + shared `WorkoutActivityAttributes`; Dart ↔ Swift over MethodChannel `spotter/live_activity` (`sync`, `end`, `available`, `activeCount`, `renderPreview`). Payload fields: `phase` (warmup/working/rest/done), `workoutName`, `exerciseName`, `nextTarget`, `setLabel`, `workoutStartMillis`, `restStartMillis?`, `restEndMillis?`, `warmups[{text,done}]`, `warmupsMore`. | Timer text is drawn by the system from dates so it runs while the app is suspended. Local updates only (`pushType: nil`), no App Group. |
| **Local notifications** | id **1001** "Rest done" scheduled at the rest end time; id **1002** "Streak" at 18:00 on the last-chance day. | Permission requested on onboarding page 2 and Settings; init requests none. Foreground presentation needs `UNUserNotificationCenter.delegate`. |
| **Share / file / clipboard** | JSON export (1 file) or CSV (3 files: sessions, sets, readiness-days); CSV import of Liftoff exports; error log "Copy all". | Export schema in D2 §1.7 and `docs/export_schema.md`. |
| **Network** | ExerciseDB V1 GIFs (first view, cached), free-exercise-db photos, YouTube iframe, optional ExerciseDB V2 (RapidAPI, key via `--dart-define-from-file`, budget 1500 warn / 1850 stop of 2000). | Privacy copy: no backend, account or analytics. |
| **Haptics / orientation** | `selectionClick`, `lightImpact` (set ✓), `mediumImpact` (praise), `heavyImpact` (rest end, PR ×2, tier change). Portrait lock on iPhone. | |
| **Android** | Manifest only declares INTERNET. | Stub. |

---

# Part 8. Gaps: no clean React Native equivalent

Each row has my proposed solution. Items marked **spike** are choices I have not validated and should be tried before committing.

| # | Flutter feature | Why there is no direct equivalent | Proposed solution |
|---|---|---|---|
| 1 | **Live Activity** (rest timer + workout, Dynamic Island) | RN/Expo has no first-party ActivityKit. | Reuse the existing Swift `ios/Shared` + `SpotterLiveActivity` files almost verbatim as an Apple-target extension created through an Expo config plugin, with a small native module exposing `sync/end` (same payload as today). **Spike** `@bacons/apple-targets` or an Expo live-activity library; fall back to hand-written plugin. Port it **last** with HealthKit. |
| 2 | **HealthKit** | Needs custom native code and entitlements. | Use a maintained HealthKit library with a config plugin; development build instead of Expo Go. The `HealthDataSource` interface (real + fake) maps cleanly to a TS interface so the fake source stays for tests. **Spike**: confirm it supports sleep category samples, SDNN and workout write. |
| 3 | **Custom in-app keypad + "outside-tap" tap region + scroll-to-cell** | No native keyboard involved, but Flutter's `TapRegion` groups, per-cell `GlobalKey`, `Scrollable.ensureVisible` have no counterpart. | A `WorkoutKeypad` component (pure TS buffer logic is directly portable: reps ≤ 3 digits, KG ≤ 2 decimals, `.`→`0.`, step/snap rules, sign toggle for assisted), plus a full-screen transparent `Pressable` for outside-tap, `measureLayout` + `scrollTo` for visibility, and committing on `AppState` change. |
| 4 | **Swipe-to-delete / swipe-to-complete set rows** (partial reveal, thresholds 44/56/60 % width, velocity 1200) | Fine-grained gesture rules. | `react-native-gesture-handler` `ReanimatedSwipeable` or a `Pan` with `activeOffsetX`/`failOffsetY` so vertical scroll still wins. |
| 5 | **CustomPainter art**: multi-tier crystal rank badge (gradients, blur, Immortal loop), `FireStreak` (flame + 46 sparks), anatomy body map with clip operations, progress rings, hex medallions, rank evolution chart | Biggest visual-fidelity risk. | **@shopify/react-native-skia** for badges, fire, rings, glow and blur; `react-native-svg` for the body map and static shapes. Port the painters after the data/behaviour work, from the verbatim sources (A §2.5–2.6, B §2.1). |
| 6 | **GIF decoded to frames, driven by a ticker** (pause, 0.5× speed, first-frame thumbnails) | Image components do not expose speed/pause. | **Spike**: expo-image animated playback controls; if insufficient, pre-extract first frames for thumbnails and play the GIF via video (re-encoded MP4/WebP) with `playbackRate`. |
| 7 | **Hero shared-element transition** (library thumb → detail) | Unstable in RN. | Drop it (cosmetic) or use Reanimated shared transitions later. |
| 8 | **Stateful tab shell** with all 5 tabs mounted + fade + `TickerMode` pause + `MiniWorkoutBar` docked above the tab bar | | Expo Router `Tabs` with `lazy: false`, `freezeOnBlur`, and a custom `tabBar` that renders `MiniWorkoutBar` above the bar. |
| 9 | **Push-for-result** (`context.push<String>('/pick-exercise')` returns an id) | Expo Router has no return values. | A `pickerStore` (Zustand): caller registers a one-shot callback or reads `pickedId` after `router.back()`. |
| 10 | **Modal sheets that return values** (~15) and dialogs with controllers | | `@gorhom/bottom-sheet` or `Modal`; promise-based helpers `promptNumber/promptText/confirm` keep call sites simple. |
| 11 | **Reorderable lists** (routines, routine editor, reorder sheet) | | `react-native-draggable-flatlist`. |
| 12 | **Snackbars with Undo, 3 s** | No built-in. | A small toast host with action support. |
| 13 | **Reactive DB streams** (`watch()` everywhere) | expo-sqlite has no drift-style streams. | See Part 10.3: in-memory `historyStore` plus explicit version bump in the write path (optionally `addDatabaseChangeListener`; **verify** in current expo-sqlite docs). |
| 14 | **Seeded `Random` shuffle** for weekly quests | Dart's PRNG sequence cannot be reproduced without porting its algorithm. | Port a deterministic PRNG and accept different picks for **new** weeks (existing weeks are stored in `quests`). Confirm in Part 9. |
| 15 | **Dart numeric/date semantics** | `round()` is half-away-from-zero (JS: half-up; identical for non-negatives, differs for negatives); `%` on doubles; `DateTime` local arithmetic incl. DST; `addDays` is calendar arithmetic (keeps wall-clock), not +24 h. | A tested `dates.ts` (day index via `Date.UTC(y,m,d)`), a `roundHalfAwayFromZero` helper where negatives are possible (assisted loads), and the Flutter test fixtures as golden tests (Part 10.5). |
| 16 | **iOS Reduce Motion handling everywhere** | | `AccessibilityInfo.isReduceMotionEnabled` + listener, Reanimated `ReduceMotion`. |
| 17 | **Rest-timer buzz tied to a mounted `WorkoutClock`** | Behaviour quirk (D1 OQ): the rest never "stops" if no clock widget is mounted. | Make the rest timer a store with an end timestamp; the notification is the source of truth when backgrounded. Fixing the quirk is a deliberate behaviour change; list in Part 9. |
| 18 | **Tabular figures for timers** (Oxanium equal-width digits) | | Load the same TTFs; `fontVariant: ['tabular-nums']`. |

---

# Part 9. Open questions

Per-area lists are at the end of each appendix (A ≈25, B ≈22, C 24, D1 17, D2 31, E 9). They are mostly "code vs doc disagreement" and "dead code". **The ones that need your decision before the port starts:**

## 9.1 Scope decisions (need an answer)

1. **Android in or out?** Today it is a stub. Assuming iOS only unless you say otherwise.
2. **Does existing Flutter data need to move to the RN app?** The app has JSON/CSV export but **no import of its own export**. A migration would need a new importer or a direct copy of `spotter.sqlite` (schema v12, timestamps in seconds).
3. **Port the Liftoff importer?** It is specific to your history (mappings in `liftoff_name_map.json`, a carried-over 177-day streak). I plan it in the polish layer, but it is only needed if you will import again.
4. **Drop these?** (proposed: yes) ExerciseDB V2 client and budget (off by default, paid, needs a key), `pinned_videos` (unused), `edb_v2_maps.candidates` (always `[]`), all `/settings/debug/*` screens, seed generator, exercise audit, media matching tool, `TechniqueChip`, `StepperBox`, `HealthAccess`, four unused packages.
5. **Program content licensing:** `min_max_canonical.json` and the demo-video links come from your own copy of Jeff Nippard's PDF. Fine for personal use; confirm before any wider distribution.

## 9.2 Behaviour decisions (code ≠ docs, or looks like a bug)

6. **Recovery feeds suggestions in code** but docs say display-only. Port the code behaviour? (Proposed: yes.)
7. **Finish pipeline is not atomic.** Port as one transaction (safer, behaviour change) or reproduce exactly? (Proposed: one transaction.)
8. **Hold sets count differently in two volume formulas** (`HistSession.volume` vs `LoggedSet.tonnage`). Which is right for each surface?
9. **Override and discipline checks for assisted (negative) loads look wrong** (C OQ). Reproduce or fix?
10. **Readiness/recovery do not refresh at midnight** until data changes. Reproduce or fix?
11. **Quest selection cannot be reproduced** (Dart seeded shuffle). Accept different picks for new weeks?
12. **`/progress?group=chest` deep link resolves to nothing.** Remove or implement?
13. **Reinstalling program routines deletes user-created routines** (D2 OQ). Keep?
14. **Summary hard-codes "+50 XP"/"+40 XP"** next to the real constants (equal today). Derive from constants?
15. **Rank evolution is an unmemoised O(history) recompute.** Fine at current history size; memoise in the port.
16. **Body map source.** `body_map.json` is derived from react-native-body-highlighter (MIT) but with Flutter-side geometry splitting for chest/deltoids/upper-back/gluteal (A §2.5). Reuse the JSON as-is (proposed) or adopt the library directly?
17. **Old data compatibility:** `suggestion_kind` in stored sessions may contain `reduce` and `plateauDeload` from earlier engine versions, and Session detail labels them ("Reduced (−5%)", "Plateau deload (−10%)"). Keep those enum values for display even though the engine no longer emits them.
18. **Date precision:** Flutter stores seconds; I propose milliseconds in the RN schema (Part 10.4). No behaviour change.

## 9.3 Documentation drift to ignore

`DECISIONS.md` still describes a Red "small deload", a −5 % rule, a plateau deload, 2.25 kg plates, 45 s warm-up rest, 25 pts per rank point (code: 37.5), achievements `streak_4/12`, a 1.5 s streak animation (code: 2800 ms), and the old tier names (Emerald/Master/Grandmaster/Challenger/Radiant, "LP"). `PLAN.md` says shared_preferences holds the onboarded flag (it is a DB row). `DESIGN.md` is stale on `LpBar` (code: `RrBar`), tier colours, ✓ haptic (code: light), button height (code: 60). Appendices cite the code, not these.

---

# Part 10. Proposed architecture

Principles: **translate the architecture, not the widgets.** The Flutter codebase already separates pure domain logic (`domain/`) from IO (`data/`) from UI (`presentation/`); that separation is the thing to keep. Everything in `domain/` becomes plain TypeScript functions and types with no React or SQLite imports, which is also what makes it testable against the existing Flutter fixtures.

## 10.1 Stack

| Concern | Choice | Note |
|---|---|---|
| Runtime | **Expo SDK (current), development builds** | HealthKit and Live Activity require native code, so Expo Go is out; keep everything else managed via config plugins and continuous native generation (no committed `ios/`, except possibly the Swift sources the plugin copies in). |
| Language | **TypeScript, `strict`** | |
| Routing | **Expo Router** (file-based) | |
| State | **Zustand** | |
| Persistence | **expo-sqlite** | versioned migrations via `PRAGMA user_version` |
| Animation/gesture | react-native-reanimated, react-native-gesture-handler | |
| Graphics | react-native-svg + @shopify/react-native-skia | |
| Tests | Vitest (or Jest) for `domain/`; Jest + RNTL for UI; Maestro/Detox later for flows | |

## 10.2 Folder structure

```
spotter-rn/
├─ app/                          # Expo Router (routes only; thin screens)
│  ├─ _layout.tsx                # providers, fonts, bootstrap gate, onboarded redirect
│  ├─ onboarding.tsx
│  ├─ (tabs)/
│  │  ├─ _layout.tsx             # Tabs + custom tabBar (MiniWorkoutBar above it)
│  │  ├─ home.tsx  train.tsx  library.tsx  progress.tsx  profile.tsx
│  ├─ workout.tsx                # full screen, above tabs
│  ├─ summary.tsx  rank-sequence.tsx  streak.tsx
│  ├─ ladder.tsx  pick-exercise.tsx  exercise-new.tsx
│  ├─ routine/[id].tsx
│  ├─ exercise/[id]/index.tsx  exercise/[id]/history.tsx  exercise/[id]/edit.tsx
│  ├─ session/[id].tsx
│  └─ settings/index.tsx  settings/errors.tsx  settings/import-liftoff.tsx
├─ src/
│  ├─ domain/                    # PURE TS, no IO. Ported + golden-tested first.
│  │  ├─ dates.ts  format.ts  training.ts  history.ts
│  │  ├─ ranks/                  # ladder.ts  scoring.ts  standards.ts  aggregate.ts  targets.ts  whatIf.ts  evolution.ts  exclusions.ts
│  │  ├─ gamification/           # streaks.ts  xp.ts  quests.ts  achievements.ts  stats.ts
│  │  ├─ readiness/              # readiness.ts  metricsAggregator.ts
│  │  ├─ recovery/               # recovery.ts  config.ts
│  │  ├─ coach/                  # suggestionEngine.ts  guardrail.ts  energy.ts  praise.ts  context.ts
│  │  ├─ gym/                    # equipment.ts  weightGrid.ts  loadTypes.ts  logGuide.ts
│  │  ├─ workout/                # setKinds.ts  supersets.ts  rest.ts  resnap.ts  workoutActivity.ts  keypadBuffer.ts
│  │  ├─ program/                # program.ts  warmups.ts
│  │  └─ library/                # filter.ts  aliases.ts  nameResolver.ts  muscleMapping.ts
│  ├─ data/                      # IO. Repositories take a db handle, return plain objects.
│  │  ├─ db/                     # open.ts  migrations/  (v1…)  schema.sql  seed.ts  dataFixes.ts
│  │  ├─ repos/                  # sessions.ts  routines.ts  exercises.ts  history.ts  gamification.ts  readiness.ts  bodyWeights.ts  gym.ts  settings.ts  media.ts
│  │  ├─ finish/                 # finishService.ts (single transaction)
│  │  ├─ import/                 # liftoff.ts   (polish layer)
│  │  ├─ export/                 # exportService.ts
│  │  └─ assets/                 # typed loaders for bundled JSON
│  ├─ platform/                  # thin adapters, each behind an interface
│  │  ├─ health/                 # HealthDataSource.ts  healthkit.ts  fake.ts
│  │  ├─ liveActivity/           # LiveActivityService.ts  native.ts  noop.ts
│  │  ├─ notifications/          # notifications.ts
│  │  └─ haptics.ts  share.ts  filePicker.ts
│  ├─ stores/                    # Zustand
│  │  ├─ appStore.ts             # settings + onboarded + clock tick
│  │  ├─ catalogStore.ts  routinesStore.ts
│  │  ├─ historyStore.ts         # all finished sessions + version counter
│  │  ├─ workoutStore.ts         # active session (write-through to SQLite)
│  │  ├─ restTimerStore.ts  pickerStore.ts  transientStore.ts (praise, lastSummary, rankTargetMode)
│  │  └─ selectors/              # memoised derivations: ranks, streak, quests, readiness, recovery…
│  ├─ ui/                        # design system
│  │  ├─ theme/                  # tokens.ts (colours, type, spacing, radii, motion)
│  │  ├─ components/             # GameCard, RrBar, ProgressRing, Skeleton, BigButton, StepperField, EmptyState, AsyncBody, Sheet, Toast, prompts
│  │  └─ graphics/               # RankBadge, FireStreak, BodyMap, AnatomyGraph (Skia/SVG)
│  └─ features/                  # screen-level components grouped by feature (home, workout, library, progress, profile, settings…)
├─ assets/                       # same JSON + TTFs, copied from Flutter
├─ modules/                      # local Expo modules (live-activity bridge) + ios-targets/ (Swift sources reused)
├─ tools/                        # existing Python asset builders (kept)
└─ __tests__/ + fixtures/        # golden fixtures extracted from the Flutter tests
```

## 10.3 State architecture (Zustand) and the "no streams" problem

Riverpod's value here is *automatic recomputation from DB streams*. The idiomatic RN replacement is simpler and explicit:

1. **Load once, bump on write.** `historyStore` loads all finished sessions into memory at bootstrap (Flutter already does this: `historyProvider`). Every write that changes finished sessions (finish, delete session, correct set, import, merge) ends with `historyStore.reload()` which increments `version`.
2. **Selectors, not providers.** `ranks`, `rankEvolution`, `dayStreak`, `streakMarks`, `quests progress`, `recovery`, `groupVolume`, `overloadedGroups`, `discipline`, `achievements` are pure functions of `(history, catalog, standards, bodyweights, settings, now, …)` memoised on the store versions. Zustand + `useShallow`/`reselect`-style memoisation gives the same dependency graph as the provider table in E §1.4, written once.
3. **Active workout:** `workoutStore` holds the active session in memory for responsive UI and writes through to SQLite on every edit (optimistic update, then persist), so a kill mid-workout restores exactly as today. It also enforces the "coach frozen at start" rule (`frozenCoach` per session id).
4. **Settings and rest timer:** `appStore` mirrors the `app_settings` KV table; the rest timer persists `rest_ends_at`/`rest_total` there, exactly as Flutter.
5. **Time:** one `clock()` function injected into selectors (tests override), a `dayTick` counter bumped at local midnight and on `AppState` active, and **also bump readiness/recovery** (decision 10).
6. **DB change listener** (expo-sqlite) is an optional alternative to step 1. **Verify against the current expo-sqlite docs** before relying on it.

Imperative services (`restTimer`, `workoutActivitySync`, `equipmentSync`, notifications) become plain modules subscribed to store changes, mirroring the single-writer pattern in E §3.2.

## 10.4 Proposed SQLite schema

Mirrors schema v12 (Appendix D2 §1.1) with these deliberate changes: **datetimes are epoch milliseconds (`INTEGER`)**, `pinned_videos` and `edb_v2_maps` are omitted (proposal 9.1 #4), all indexes are created in the migration (fixing D2 OQ-1), and soft links stay soft to preserve behaviour (dangling `routine_id` is legal today).

```sql
PRAGMA foreign_keys = ON;
-- migrations tracked with PRAGMA user_version; v1 of the RN schema == Flutter v12 content-wise

CREATE TABLE exercises (
  id               TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  primary_muscles  TEXT NOT NULL DEFAULT '[]',   -- JSON array of dataset muscle names
  secondary_muscles TEXT NOT NULL DEFAULT '[]',
  equipment        TEXT,
  level            TEXT,
  mechanic         TEXT,                          -- 'compound' | 'isolation' | NULL
  category         TEXT,
  instructions     TEXT NOT NULL DEFAULT '[]',
  images           TEXT NOT NULL DEFAULT '[]',    -- free-exercise-db repo-relative paths
  extra_images     TEXT NOT NULL DEFAULT '[]',    -- full URLs
  source           TEXT,                          -- 'fedb' | 'wger' | 'edb_v1' | 'custom'
  credit           TEXT,                          -- JSON [{source, license, author, images}]
  edb_v1_id        TEXT,
  is_custom        INTEGER NOT NULL DEFAULT 0 CHECK (is_custom IN (0,1)),
  is_favorite      INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0,1)),
  notes            TEXT
);

CREATE TABLE routines (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  position    INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  program_day TEXT
);

CREATE TABLE routine_exercises (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  routine_id        INTEGER NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  exercise_id       TEXT    NOT NULL REFERENCES exercises(id),
  position          INTEGER NOT NULL,
  rep_min           INTEGER NOT NULL,
  rep_max           INTEGER NOT NULL,
  target_sets       INTEGER NOT NULL,
  rest_seconds      INTEGER NOT NULL,
  target_rir        INTEGER NOT NULL DEFAULT 2,
  program_slots     TEXT,                          -- JSON array of slot ids
  program_relation  TEXT,                          -- 'program' | 'substitution' | 'swap' | 'extra'
  program_exercise  TEXT,
  display_name      TEXT,
  override_rep_min  INTEGER,
  override_rep_max  INTEGER,
  superset_group    INTEGER                        -- id of first row in the group
);
CREATE INDEX idx_routine_ex_routine ON routine_exercises (routine_id);

CREATE TABLE sessions (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  routine_id      INTEGER,                         -- soft link (no FK), as in Flutter
  name            TEXT NOT NULL,
  started_at      INTEGER NOT NULL,
  ended_at        INTEGER,
  notes           TEXT NOT NULL DEFAULT '',
  status          TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'finished'
  readiness_score INTEGER,
  readiness_band  TEXT,                            -- 'green' | 'yellow' | 'red'
  health_synced   INTEGER NOT NULL DEFAULT 0 CHECK (health_synced IN (0,1)),
  xp_earned       INTEGER NOT NULL DEFAULT 0,
  source          TEXT NOT NULL DEFAULT 'app',     -- 'app' | 'liftoff'
  external_id     TEXT
);
CREATE INDEX idx_sessions_started ON sessions (started_at);
CREATE UNIQUE INDEX idx_sessions_external ON sessions (source, external_id);

CREATE TABLE session_exercises (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id          INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  exercise_id         TEXT    NOT NULL REFERENCES exercises(id),
  position            INTEGER NOT NULL,
  notes               TEXT NOT NULL DEFAULT '',
  rep_min             INTEGER NOT NULL,
  rep_max             INTEGER NOT NULL,
  target_sets         INTEGER NOT NULL,
  rest_seconds        INTEGER NOT NULL,
  target_rir          INTEGER NOT NULL DEFAULT 2,
  suggestion_kind     TEXT NOT NULL DEFAULT 'none', -- keep 'reduce' / 'plateauDeload' readable for old rows
  suggested_weight    REAL,
  suggested_reps      INTEGER,
  suggested_sets      INTEGER,
  suggestion_json     TEXT,
  program_slots       TEXT,
  display_name        TEXT,
  rest_enabled        INTEGER NOT NULL DEFAULT 1 CHECK (rest_enabled IN (0,1)),
  superset_group      INTEGER,
  routine_exercise_id INTEGER,                      -- soft link (no FK)
  targets_edited      INTEGER NOT NULL DEFAULT 0 CHECK (targets_edited IN (0,1))
);                                                  -- program_week omitted: "no longer written" (D2)
CREATE INDEX idx_session_ex_session  ON session_exercises (session_id);
CREATE INDEX idx_session_ex_exercise ON session_exercises (exercise_id);

CREATE TABLE workout_sets (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  session_exercise_id INTEGER NOT NULL REFERENCES session_exercises(id) ON DELETE CASCADE,
  position            INTEGER NOT NULL,
  is_warmup           INTEGER NOT NULL DEFAULT 0 CHECK (is_warmup IN (0,1)),
  weight              REAL    NOT NULL DEFAULT 0,   -- kg, negative = assisted
  reps                INTEGER NOT NULL DEFAULT 0,   -- seconds when set_type = 'hold'
  rpe                 REAL,
  completed           INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0,1)),
  completed_at        INTEGER,
  suggested_weight    REAL,
  suggested_reps      INTEGER,
  is_override         INTEGER NOT NULL DEFAULT 0 CHECK (is_override IN (0,1)),
  override_reason     TEXT,                         -- 'feltStrong' | 'testingMax' | 'justDidIt'
  target_rep_min      INTEGER,
  target_rep_max      INTEGER,
  target_rir          INTEGER,
  technique           TEXT,                         -- e.g. 'drop_sets_2x25'
  set_type            TEXT,                         -- NULL | 'drop' | 'myo' | 'hold'
  partials            INTEGER NOT NULL DEFAULT 0 CHECK (partials IN (0,1)),
  adjusted_from       REAL,
  adjust_reason       TEXT,
  rest_seconds        INTEGER
);
CREATE INDEX idx_sets_session_ex ON workout_sets (session_exercise_id);

CREATE TABLE daily_metrics (
  date               TEXT PRIMARY KEY,              -- yyyy-MM-dd (local)
  hrv_ms             REAL,
  resting_hr         REAL,
  sleep_minutes      REAL,
  active_energy_kcal REAL,
  dietary_kcal       REAL,
  protein_g          REAL,
  readiness_score    INTEGER,
  readiness_band     TEXT,
  calibrating        INTEGER NOT NULL DEFAULT 1 CHECK (calibrating IN (0,1)),
  explanation        TEXT NOT NULL DEFAULT '',
  updated_at         INTEGER NOT NULL
);

CREATE TABLE body_weights (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  measured_at INTEGER NOT NULL,
  kg          REAL    NOT NULL,
  source      TEXT    NOT NULL                       -- 'health' | 'manual'
);

CREATE TABLE ego_freezes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  exercise_id TEXT    NOT NULL,                      -- soft link
  started_at  INTEGER NOT NULL,
  until       INTEGER NOT NULL,
  base_weight REAL    NOT NULL,
  reason      TEXT    NOT NULL
);

CREATE TABLE xp_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  at         INTEGER NOT NULL,
  amount     INTEGER NOT NULL,
  reason     TEXT    NOT NULL,                       -- 'session' | 'quest'
  session_id INTEGER,
  week_start TEXT                                    -- yyyy-MM-dd (Monday)
);

CREATE TABLE achievements_unlocked (
  key         TEXT PRIMARY KEY,
  unlocked_at INTEGER NOT NULL
);

CREATE TABLE quests (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  week_start   TEXT    NOT NULL,                     -- Monday, yyyy-MM-dd
  key          TEXT    NOT NULL,                     -- QuestKey
  params       TEXT    NOT NULL DEFAULT '{}',
  title        TEXT    NOT NULL,
  completed_at INTEGER
);

CREATE TABLE app_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE media_matches (
  exercise_id TEXT PRIMARY KEY,
  edb_id      TEXT,
  edb_name    TEXT,
  gif_url     TEXT,
  confidence  REAL NOT NULL DEFAULT 0,
  source      TEXT NOT NULL DEFAULT 'auto',          -- 'auto' | 'override' | 'manual' | 'library'
  updated_at  INTEGER NOT NULL
);
```

Notes: (a) form resets (`form_resets`, `form_reset_offered`) and gym equipment (`GymEquipment.key`) stay JSON values in `app_settings`, as in Flutter (`gym_repository.dart:13-14, 30-32`; D2 §1.4, C §1.13). (b) Dates: convert at the repo boundary (`new Date(ms)`), never in domain code, which takes `Date`/epoch ms. (c) SQLite has no `autoincrement` surprises here; ids are plain integers, same as drift.

## 10.5 Verification strategy: port the tests, not just the code

The Flutter repo has **~340 domain tests and ~99 data tests** with fixed fixtures and exact expected numbers (`test/domain/`, `test/data/`). That is the strongest safety net for a logic-heavy port:

1. Extract each fixture and expected value into JSON/TS in `__tests__/fixtures/` while porting its domain module. The key suites: `ranks_test`, `rank_target_test`, `rank_gains_test`, `bodyweight_what_if_test`, `day_streak_test`, `streaks_xp_test`, `aggregation_quests_test`, `readiness_test`, `recovery_test`, `suggestion_engine_test`, `suggestion_rework_test`, `guardrail_test`, `no_silent_decrease_test`, `max_load_test`, `load_types_test`, `weight_steps_change_test`, `set_types_test`, `liftoff_test`, `migration_test`.
2. Port **domain before UI**, and do not mark a domain module done until its ported tests pass with the same numbers.
3. The README's `LIFTOFF_CSV` + `docs/IMPORT_SUMMARY.md` flow gives a real-data regression: import the same file in both apps and compare ranks and first suggestions per routine exercise.
4. Seed a 12-week history (the debug seed generator's output is deterministic) in both and compare ranks, streak and quests.

## 10.6 Porting order (layers)

Each layer ends in something verifiable. Estimates are deliberately omitted; sizes come from the Flutter line counts.

**Layer 0: Setup**
- Expo project (TypeScript strict, Expo Router, development build), lint/format, Vitest, CI.
- Fonts (Oxanium, Barlow), `ui/theme/tokens.ts` from the design-token table (D1 §4.1; colours and radii are quoted there).
- Copy `assets/` (JSON + TTF) and the Python `tool/` builders.
- **Spikes now, not later** (so the plan survives contact): HealthKit library + config plugin on a dev build; Live Activity extension via config plugin; expo-image GIF control; Skia rank badge feasibility. Each is a throwaway branch with a pass/fail note.

**Layer 1: Data layer**
- `domain/` foundations: `dates`, `format`, `training` predicates, `history` types, with tests.
- SQLite open, migrations (single v1 = Flutter v12 content), seeding (versioned), data fixes, typed repos, `settings`.
- Repos: exercises, routines, sessions, history, bodyWeights, gym, gamification, readiness.
- Asset loaders; program install (`min_max_canonical`, `my_routines`).
- Exit: seed from assets, create/read a session, round-trip through repos; schema test.

**Layer 2: Navigation**
- Expo Router tree (Part 5 and 10.2), tab shell with `MiniWorkoutBar` slot, onboarded redirect, `pickerStore`, empty screens, error log + global handlers.
- Exit: every route reachable, back/replace semantics match Part 5.

**Layer 3: Core features** (domain first, then UI, in this order)
1. Gym equipment + weight grids + load types + log guide (needed by everything that suggests).
2. Readiness + recovery domain (with neutral fake data), energy.
3. **Coach**: suggestion engine, guardrail, praise, calibration. Port its tests.
4. Workout logging: `workoutStore`, keypad buffer, set kinds, supersets, rest rules, active workout UI, rest timer store (notification can wait), routines and routine editor, Train, Library + exercise detail (About/Stats/History, no GIF control yet).
5. **Finish pipeline** (single transaction): XP, PRs, ego guardrail, quests, achievements, streak write, rank diff; Summary screen.
6. **Ranks**: ladder, scoring, standards, aggregation, targets; Progress/Ranks screens with a static (non-Skia) badge first; Ladder; rank-up and rank-sequence screens.
7. Streak (domain + Home card + streak step), Profile, quests UI, achievements.
8. Session detail (correct set, delete), Settings (all sections except Health/Import/Notifications), Home.
- Exit per sub-step: ported tests green with identical numbers.

**Layer 4: Polish**
- Skia/SVG: rank badge (all 9 tiers + Immortal loop), FireStreak, body map + anatomy graph, rank evolution chart, progress rings, glow.
- Animations/haptics, Reduce Motion, toasts with Undo, swipe rows, reorder lists.
- GIF demo + thumbnails + YouTube player, media matching bootstrap/prefetch.
- Liftoff import (if kept), JSON/CSV export, wger/free-exercise-db merge fix-ups.
- Rest-timer local notification and streak reminder (`expo-notifications`) and their permission flow.
- Exit: visual comparison against `docs/screenshots/`.

**Layer 5: HealthKit and native, last**
- `HealthDataSource` real implementation behind the existing interface (fake stays), permission flow in onboarding and Settings, sync (45 days, body mass 365), workout write on Finish, `daily_metrics` upsert and score recompute.
- Live Activity: reuse the Swift sources, the bridge module, the `workoutActivitySync` single writer.
- Exit: on-device checks against the Flutter app for the same Health data (readiness score for a given day, body weight timeline, Live Activity layout).

## 10.7 Risks to watch

1. **Numeric parity**: rank scores, e1RM and the engine's grid snapping are float-heavy; tolerances in the Flutter tests should be carried over, not loosened.
2. **Date/DST**: day-index and `addDays` semantics (item 15 in Part 8). A single `dates.ts`, tested around DST boundaries, no `getTime()+86400000`.
3. **History size**: loading all sessions into memory is what Flutter does; fine for years of one person's data, but keep selectors memoised (A's unmemoised evolution recompute is the known hotspot).
4. **Active-workout fidelity**: the ✓ sequence (D1 §1.9) has many ordered side effects; port it as one tested function (`completeSet`), not scattered across components.
5. **Native modules** (Live Activity, HealthKit) are the only places "managed Expo" stops. They are last by design.

---

*Stop point.* This is the end of the Phase 1 spec. Nothing has been implemented. Appendices A–E follow; please review Part 9 first, because items 9.1 #1–#4 change scope and 9.2 #6–#11 change behaviour.


---

# Appendix A. Ranks and body ranking

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `A §n`).

## Section A: Ranks and body ranking (Flutter "Spotter" -> React Native port spec, analysis only)

Repo root: `/Users/hassan/IdeaProjects/spotter-app`. All paths below are relative to it. Code wins over docs; disagreements are listed as `OQ:` in section 4. Many docs/DECISIONS.md sections and the `description` of assets/strength_standards.json are STALE (they describe earlier ladders: Emerald/Master/Grandmaster/Challenger, Radiant, LP, IV->I). Only the code below is authoritative.

---------------------------------------------------------------------------------------------------
### 1. BUSINESS LOGIC

#### 1.1 Tiers, divisions, points (the ladder model)

A rank is ONE continuous double `value` ("points"): 1 point per division, 3 divisions per tier, 8 divisional tiers (Iron..Olympian = points 0..24) then Immortal (>= 24, uncapped, no divisions). Ranks are never stored; always derived from logged sets (`lib/features/ranks/data/ladder_migration.dart:25-26` doc).

`lib/features/ranks/domain/ranks.dart:5-24`
```dart
/// Valorant-style ladder: 8 divisional tiers (1 → 3, 3 is the highest) and Immortal on top, without divisions.
enum Tier {
  iron('Iron'),
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold'),
  platinum('Platinum'),
  diamond('Diamond'),
  champion('Champion'),
  olympian('Olympian'),
  immortal('Immortal');

  const Tier(this.label);
  final String label;

  bool get isApex => this == Tier.immortal;

  static const int divisionalTiers = 8;
  static const int divisionsPerTier = 3;
}
```

`lib/features/ranks/domain/ranks.dart:26-92` (RankScore: tier/division/RR/progress/label derivation; `_eps` guards float boundaries)
```dart
/// A position on the ladder as a continuous number of **points**: one point per division.
///
/// - Divisional tiers: tier i spans points [3i, 3i + 3); division 1 = 3i, 2 = 3i + 1, 3 = 3i + 2.
/// - Immortal starts at 24 (uncapped).
///
/// Groups and the overall rank average points directly, so the mean of identical ranks maps back
/// to exactly that rank.
class RankScore {
  RankScore(double value) : value = value < 0 ? 0 : value;

  /// Builds the score for a given tier, division (1 = lowest … 3 = highest) and RR (0–100), mainly for tests.
  /// Immortal has no divisions: [rr] is the rank rating above its threshold (uncapped).
  factory RankScore.of(Tier tier, {int division = 1, double rr = 0}) {
    if (tier.isApex) return RankScore(apexPoints + rr / 100);
    return RankScore(tier.index * 3.0 + (division - 1) + rr / 100);
  }

  final double value;

  static const double apexPoints = 24;

  // Floors use a small epsilon so a score on a boundary (or an average of identical scores that
  // lost an ulp) never drops into the previous division.
  static const double _eps = 1e-9;

  int get _point => (value + _eps).floor();

  Tier get tier {
    if (value + _eps >= apexPoints) return Tier.immortal;
    return Tier.values[(_point ~/ 3).clamp(0, Tier.divisionalTiers - 1)];
  }

  bool get isApex => tier.isApex;

  /// 0 = division 1 (lowest) … 2 = division 3 (highest); −1 for Immortal.
  int get divisionIndex => isApex ? -1 : _point % 3;

  /// "1".."3", empty for Immortal.
  String get divisionLabel => isApex ? '' : '${divisionIndex + 1}';

  String get label => isApex ? tier.label : '${tier.label} $divisionLabel';

  /// Rank rating: 0–100 within a division; for Immortal, RR above its threshold (uncapped).
  int get rr {
    if (isApex) return ((value - apexPoints) * 100 + _eps).floor();
    return (((value - _point) * 100) + _eps).floor().clamp(0, 99);
  }

  /// 0..1 progress to the next division (Immortal: per 100 RR).
  double get divisionProgress {
    if (isApex) return ((value - apexPoints) % 1).clamp(0.0, 1.0);
    return (value - _point).clamp(0.0, 1.0);
  }

  /// Label of the next step up, or null at Immortal.
  String? get nextLabel {
    if (isApex) return null;
    if (divisionIndex < 2) return '${tier.label} ${divisionIndex + 2}';
    return tier == Tier.olympian ? Tier.immortal.label : '${Tier.values[tier.index + 1].label} 1';
  }

  /// "Gold 2 · 42 RR", "Immortal · 135 RR".
  String get labelWithRr => '$label · $rr RR';

  @override
  String toString() => label;
}
```
Notes: negative values clamp to 0. Dart `%` on doubles (`(value-24) % 1`) is non-negative for positives (same as JS `%` for positives). `.floor()`/`.round()` on non-negative ints: Dart `round()` is half-away-from-zero, JS `Math.round` is half-up: identical for non-negative numbers.

**Score -> tier table (derived from the code above, 37.5 strength per point)**

| Tier (index) | Points range | Divisions start at points | Strength at tier start (`round`) |
|---|---|---|---|
| Iron (0) | [0,3) | 0,1,2 | 0 |
| Bronze (1) | [3,6) | 3,4,5 | 112.5 -> 113 |
| Silver (2) | [6,9) | 6,7,8 | 225 |
| Gold (3) | [9,12) | 9,10,11 | 337.5 -> 338 |
| Platinum (4) | [12,15) | 12,13,14 | 450 |
| Diamond (5) | [15,18) | 15,16,17 | 562.5 -> 563 |
| Champion (6) | [18,21) | 18,19,20 | 675 |
| Olympian (7) | [21,24) | 21,22,23 | 787.5 -> 788 |
| Immortal (8) | [24, inf) | n/a (RR above 24, 100 RR per point) | 900 |
Division label is "1","2","3" (1 lowest, 3 highest), label e.g. "Gold 2"; Immortal label is just "Immortal". Test `test/domain/ranks_test.dart:101-107` confirms strength(12)=450, (21)=788, (24)=900, (55)=1000.

#### 1.2 Per-set score 0-1000 ("strength")

`lib/features/ranks/domain/ranks.dart:94-103`
```dart
/// Strength score 0–1000: 37.5 per division point, so Iron 1 = 0, each division = 37.5, Olympian = 787, Immortal = 900,
/// and 1000 is the cap.
const double strengthPerPoint = 37.5;

extension StrengthScore on RankScore {
  int get strength => (value * strengthPerPoint).round().clamp(0, 1000);
}

RankScore scoreFromStrength(num strength) => RankScore(strength / strengthPerPoint);
```
(Doc comment says Olympian = 787 but code gives 788; see OQ.) Strength is a display of `RankScore.value*37.5`; the underlying score of a set is the RankScore (points).

#### 1.3 e1RM formula (scoring)

Scoring uses its OWN e1RM (Epley on reps + RIR, with reps+RIR capped at 20), not the general `estimateOneRm`.

`lib/features/ranks/domain/ranks.dart:232-241`
```dart
/// Epley is unreliable for long sets: for scoring, reps + reps in reserve count up to 20.
const int scoringRepCap = 20;

/// e1RM used for strength scores: load (plus bodyweight for bodyweight lifts) with reps + RIR capped.
double scoringE1rm({required double load, required int reps, double? rpe}) {
  if (reps <= 0 || load <= 0) return 0;
  final rir = 10 - (rpe ?? 9.0);
  final effective = (reps + rir).clamp(0, scoringRepCap.toDouble());
  return load * (1 + effective / 30);
}
```
General (non-capped) e1RM used elsewhere (PRs, Lifts tab; not for ranks): `lib/core/domain/training.dart:9-15`, default RPE `lib/core/domain/training.dart:5`
```dart
const double defaultRpe = 9.0;
...
/// Estimated 1RM: Epley on effective reps, `weight × (1 + (reps + RIR) / 30)` with RIR = 10 − RPE.
double estimateOneRm(double weight, int reps, double? rpe) {
  if (reps <= 0 || weight <= 0) return 0;
  final rir = 10 - (rpe ?? defaultRpe);
  return weight * (1 + (reps + rir) / 30);
}
```
Edge cases: load <= 0 -> 0 -> set unscored (assisted load that exceeds bodyweight -> load<=0 -> null). RPE null -> 9 (RIR 1). `rir` can be negative if rpe > 10 (clamp lower bound 0 only on the sum). `(reps+rir).clamp(0, 20)` returns a num; result double.

#### 1.4 Which sets count ("valid working sets", 90-day window, bodyweight of the day)

`lib/core/domain/training.dart:85-104` (set validity)
```dart
  /// Completed, not a warm-up (drop sets included: they count for volume).
  bool get isWorking => !isWarmup && completed;
  ...
  /// Ego lifting (section 7): load above the suggestion *and* reps below the bottom of the range,
  /// i.e. it was too heavy. Going to failure inside the range is never ego lifting.
  bool get isEgoSet => isOverride && belowRange;
  ...
  /// Valid for ranks and PRs: a completed working set that isn't a drop set or an ego set.
  bool get isValidForRecords => isWorking && !isFollowUp && !isEgoSet;
```
`lib/core/domain/training.dart:75` -> `bool get isFollowUp => isDrop || isMyo || isHold;` and `:196` -> `List<LoggedSet> get workingSets => sets.where((s) => s.isWorking && !s.isFollowUp).toList();` (`belowRange => targetMin != null && reps < targetMin!`, `training.dart:90`).

`lib/features/ranks/data/ranks_repository.dart:14-100` (window and set selection; ALL of it)
```dart
  /// Ranks from valid working sets of the last 90 days, each scored at the bodyweight of its day.
  /// [myExerciseIds] (routines and history) are offered as hints for unranked muscles.
  static RankSummary compute({
    required TrainingHistory history,
    required List<StrengthStandard> standards,
    required Map<String, ExerciseInfo> catalog,
    required BodyweightTimeline bodyweights,
    required DateTime now,
    Set<String> excluded = const {},
    Set<String> myExerciseIds = const {},
    Map<String, String> displayNames = const {},
  }) {
    if (bodyweights.isEmpty) return RankSummary.empty;
    final from = addDays(dateOnly(now), -RankCalculator.windowDays);
    final sets = <RankedSet>[
      for (final s in history.sessions)
        if (!s.startedAt.isBefore(from) && !s.startedAt.isAfter(now))
          for (final e in s.exercises)
            for (final set in e.workingSets)
              if (set.isValidForRecords)
                RankedSet(
                  exerciseId: e.exerciseId,
                  name: displayNames[e.exerciseId] ?? catalog[e.exerciseId]?.name ?? e.name,
                  weight: set.weight,
                  reps: set.reps,
                  rpe: set.rpe,
                  date: s.startedAt,
                  bodyweight: bodyweights.at(s.startedAt),
                ),
    ];
    // Ranks show the name the logger shows: your routine's name for it, else the library's.
    final names = <String, String>{
      for (final s in history.sessions)
        for (final e in s.exercises) e.exerciseId: displayNames[e.exerciseId] ?? catalog[e.exerciseId]?.name ?? e.name,
    };
    final mine = {...myExerciseIds, ...history.exerciseIds};
    return RankCalculator(standards).compute(
      sets: sets,
      targets: {for (final e in catalog.values) e.id: e.targets},
      currentBodyweight: bodyweights.latest,
      excluded: excluded,
      hintNames: {for (final id in mine) if (catalog[id] != null) id: names[id] ?? catalog[id]!.name},
    );
  }
```
Details: window start = local midnight of (now - 90 days) (`addDays` = `DateTime(y,m,d+days,h,m,s)` `lib/core/domain/dates.dart:23`, `dateOnly` `:4`); filter uses session `startedAt` (inclusive both ends), NOT set time. Imported (Liftoff) sessions count if exercise is "on". No bodyweights at all -> `RankSummary.empty` (everything unranked). Per-set bodyweight = `BodyweightTimeline.at(session.startedAt)`.

`lib/features/ranks/domain/ranks.dart:243-278` (BodyweightTimeline)
```dart
class BodyweightTimeline {
  BodyweightTimeline(Iterable<(DateTime, double)> samples) : _s = [...samples]..sort((a, b) => a.$1.compareTo(b.$1));

  final List<(DateTime, double)> _s;

  static final empty = BodyweightTimeline(const []);

  bool get isEmpty => _s.isEmpty;

  double get latest => _s.isEmpty ? 0 : _s.last.$2;

  /// Mean of the weigh-ins in the [days] up to [now]; the latest weigh-in when there is none in that span.
  double recentAverage(DateTime now, {int days = 7}) {
    final from = now.subtract(Duration(days: days));
    final recent = [for (final (t, w) in _s) if (!t.isBefore(from) && !t.isAfter(now)) w];
    return recent.isEmpty ? latest : recent.fold<double>(0, (a, w) => a + w) / recent.length;
  }

  double at(DateTime t) {
    if (_s.isEmpty) return 0;
    if (!t.isAfter(_s.first.$1)) return _s.first.$2;
    if (!t.isBefore(_s.last.$1)) return _s.last.$2;
    for (var i = 1; i < _s.length; i++) {
      final (t1, w1) = _s[i];
      if (t.isAfter(t1)) continue;
      final (t0, w0) = _s[i - 1];
      final span = t1.difference(t0).inSeconds;
      if (span <= 0) return w1;
      return w0 + (w1 - w0) * t.difference(t0).inSeconds / span;
    }
    return _s.last.$2;
  }
}
```
Samples come from table `body_weights` (`measuredAt` DateTime, `kg` real, `source` 'health'|'manual') via `RanksRepository.timeline` (`ranks_repository.dart:45`): `BodyweightTimeline([for (final r in rows) (r.measuredAt, r.kg)])`. Test `ranks_test.dart:144-150`: flat before first / after last, linear between; `bodyweight_what_if_test.dart:144-153` for recentAverage ("last 7 days, else latest"). Manual entry validation in UI: kg must be 30..300 (`progress_screen.dart:99-104`: `if (kg == null || kg < 30 || kg > 300) return;`).

#### 1.5 Strength standards, anchors -> thresholds (per exercise)

`lib/features/ranks/domain/ranks.dart:122-230` (StrengthStandard)
```dart
enum StandardKind {
  free,
  machine,
  cable,

  /// e1RM includes bodyweight (assisted machines subtract the assistance).
  bodyweight;

  static StandardKind fromName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => free);
}

/// Strength standard for one or more exercises: tier entry thresholds as e1RM ÷ bodyweight, derived
/// from five anchors (beginner … elite). See assets/strength_standards.json.
class StrengthStandard {
  StrengthStandard({
    required this.id,
    required this.name,
    required this.kind,
    required this.exerciseIds,
    required this.anchors,
    this.perHand = false,
    double strictness = 1,
    this.scaling = BodyweightScaling.linear,
  }) : thresholds = thresholdsFromAnchors([for (final a in anchors) a * strictness]);
  ...
  bool get bodyweightLoaded => kind == StandardKind.bodyweight;

  /// The thresholds derive from the anchors; the multiple at which each tier (Iron..Immortal) starts.
  /// Iron 0, Bronze = beginner, Silver = novice, Gold = intermediate, Platinum = midpoint intermediate–advanced,
  /// Diamond = advanced, Champion = midpoint advanced–elite, Olympian = elite, Immortal = elite × 1.3.
  /// (docs/DECISIONS.md, "Valorant ladder")
  static List<double> thresholdsFromAnchors(List<double> a) {
    if (a.length != 5) throw const FormatException('A standard needs 5 anchors');
    for (var i = 1; i < 5; i++) {
      if (a[i] <= a[i - 1]) throw const FormatException('Anchors must ascend');
    }
    return [0, a[0], a[1], a[2], (a[2] + a[3]) / 2, a[3], (a[3] + a[4]) / 2, a[4], a[4] * 1.3];
  }

  factory StrengthStandard.fromJson(Map<String, dynamic> j, {double machineStrictness = 1, BodyweightScaling scaling = BodyweightScaling.linear}) {
    final kind = StandardKind.fromName(j['kind'] as String?);
    final a = j['anchors'] as Map<String, dynamic>;
    return StrengthStandard(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: kind,
      exerciseIds: (j['exercise_ids'] as List<dynamic>).cast<String>(),
      anchors: [for (final k in const ['beginner', 'novice', 'intermediate', 'advanced', 'elite']) (a[k] as num).toDouble()],
      perHand: j['per_hand'] as bool? ?? false,
      strictness: kind == StandardKind.machine || kind == StandardKind.cable ? machineStrictness : 1,
      scaling: scaling,
    );
  }
```
Thresholds index = Tier index (9 values: Iron 0, Bronze, Silver, Gold, Platinum, Diamond, Champion, Olympian, Immortal). Machine/cable strictness (bundled `machine_strictness`=1.1) multiplies anchors BEFORE thresholds (test `ranks_test.dart:109-120`). Bodyweight-kind and free kinds are not scaled by strictness. Throws FormatException if not exactly 5 anchors or not strictly ascending. Example thresholds for anchors [0.5,0.75,1.0,1.4,1.6]: `[0,0.5,0.75,1.0,1.2,1.4,1.5,1.6,2.08]` (`ranks_test.dart:10-18,44-46`).

#### 1.6 Allometric bodyweight scaling

`lib/features/ranks/domain/ranks.dart:105-120` and `:147-154`
```dart
/// How bodyweight normalises a load. Allometric: scaled = e1RM / (reference × (bodyweight / reference)^exponent).
/// Exponent 1 is the plain e1RM ÷ bodyweight ratio; 0.67 (strength scales with muscle cross-section,
/// i.e. mass^⅔) stops heavier lifters being penalised for not lifting in proportion to bodyweight.
class BodyweightScaling {
  const BodyweightScaling({this.referenceBodyweight = 100, this.exponent = 1});

  final double referenceBodyweight;
  final double exponent;

  static const linear = BodyweightScaling();
  static const allometric = BodyweightScaling(exponent: 0.67);

  /// The load that counts as "1× bodyweight" for a lifter of [bodyweight] kg.
  double normalizer(double bodyweight) =>
      exponent == 1 ? bodyweight : referenceBodyweight * math.pow(bodyweight / referenceBodyweight, exponent);
}
```
```dart
  /// Allometric scaling for loaded lifts. Bodyweight lifts always use the plain ratio: their load is
  /// bodyweight itself, so it already scales with the lifter.
  final BodyweightScaling scaling;

  /// The divisor that turns an e1RM into the ratio the thresholds are expressed in.
  double normalizer(double bodyweight) => bodyweightLoaded ? bodyweight : scaling.normalizer(bodyweight);

  double ratioFor(double e1rm, double bodyweight) => bodyweight <= 0 ? 0 : e1rm / normalizer(bodyweight);
```
Bundled JSON uses `"scaling": {"reference_bodyweight": 100, "exponent": 0.67}` (applies to ALL non-bodyweight kinds incl. machine/cable; parsed `ranks_repository.dart:18-31`). Fallback if the `scaling` key is absent: `BodyweightScaling.linear`. `ratioFor` returns 0 when bodyweight <= 0.

#### 1.7 Ratio -> RankScore (piecewise linear) and the inverse

`lib/features/ranks/domain/ranks.dart:197-230`
```dart
  double get _olympian => thresholds[Tier.olympian.index];
  double get _immortal => thresholds[Tier.immortal.index];

  /// Linear in ratio within every division; Immortal continues with the Olympian slope (uncapped).
  RankScore scoreForRatio(double ratio) {
    if (ratio >= _immortal) {
      return RankScore(RankScore.apexPoints + (ratio - _immortal) / (_immortal - _olympian) * Tier.divisionsPerTier);
    }
    var i = 0;
    while (i + 1 < Tier.divisionalTiers && ratio >= thresholds[i + 1]) {
      i++;
    }
    final lo = thresholds[i], hi = thresholds[i + 1];
    final f = ((ratio - lo) / (hi - lo)).clamp(0.0, 1.0);
    return RankScore(i * 3 + f * 3);
  }

  /// Bodyweight multiple at which a point value is reached (inverse of [scoreForRatio]).
  double ratioForPoints(double points) {
    if (points >= RankScore.apexPoints) {
      return _immortal + (points - RankScore.apexPoints) / Tier.divisionsPerTier * (_immortal - _olympian);
    }
    final i = (points ~/ 3).clamp(0, Tier.divisionalTiers - 1);
    final f = (points - i * 3) / 3;
    return thresholds[i] + f * (thresholds[i + 1] - thresholds[i]);
  }

  /// e1RM (kg, bodyweight included for bodyweight lifts) needed for the next division, or null at Challenger.
  double? nextThresholdKg(RankScore current, double bodyweight) {
    if (current.tier == Tier.immortal) return null;
    final target = (current.value + 1e-9).floorToDouble() + 1;
    return ratioForPoints(target) * normalizer(bodyweight);
  }
```
Note: within a tier the 3 divisions are equal thirds in RATIO (linear), so division boundaries are at thresholds[i] + k/3*(thresholds[i+1]-thresholds[i]). `nextThresholdKg` doc says "Challenger" (stale), returns null at Immortal. Negative ratio: `f` clamps to 0 -> 0 points. Dart `~/` = integer truncating division (points >= 0 here).

#### 1.8 Per-exercise best set, hidden/excluded, hints

`lib/features/ranks/domain/ranks.dart:485-556` (RankCalculator: scoreSet + compute)
```dart
class RankCalculator {
  RankCalculator(this.standards) : _byExercise = {for (final s in standards) for (final id in s.exerciseIds) id: s};

  final List<StrengthStandard> standards;
  final Map<String, StrengthStandard> _byExercise;

  static const int windowDays = 90;

  StrengthStandard? standardFor(String exerciseId) => _byExercise[exerciseId];

  /// Points for one set, or null when the exercise has no standard or no bodyweight is known.
  RankScore? scoreSet({required String exerciseId, required LoggedSetLike set, required double bodyweight}) {
    final s = _byExercise[exerciseId];
    if (s == null || bodyweight <= 0) return null;
    final load = set.weight + (s.bodyweightLoaded ? bodyweight : 0);
    final e = scoringE1rm(load: load, reps: set.reps, rpe: set.rpe);
    if (e <= 0) return null;
    return s.scoreForRatio(s.ratioFor(e, bodyweight));
  }

  RankSummary compute({
    required List<RankedSet> sets,
    required Map<String, MuscleTargets> targets,
    required double currentBodyweight,
    Set<String> excluded = const {},
    Map<String, String> hintNames = const {},
  }) {
    final best = <String, ExerciseRank>{};
    for (final x in sets) {
      final s = _byExercise[x.exerciseId];
      final score = scoreSet(exerciseId: x.exerciseId, set: x, bodyweight: x.bodyweight);
      if (s == null || score == null) continue;
      final cur = best[x.exerciseId];
      if (cur != null && cur.score.value >= score.value) continue;
      best[x.exerciseId] = ExerciseRank(
        exerciseId: x.exerciseId,
        name: x.name,
        standard: s,
        score: score,
        bestE1rm: scoringE1rm(load: x.weight + (s.bodyweightLoaded ? x.bodyweight : 0), reps: x.reps, rpe: x.rpe),
        bodyweight: x.bodyweight,
        weight: x.weight,
        reps: x.reps,
        rpe: x.rpe,
        date: x.date,
        targets: targets[x.exerciseId] ?? MuscleTargets.empty,
        nextThresholdKg: s.nextThresholdKg(score, currentBodyweight > 0 ? currentBodyweight : x.bodyweight),
      );
    }
    final ranks = [for (final r in best.values) if (!excluded.contains(r.exerciseId)) r];
    final hidden = [for (final r in best.values) if (excluded.contains(r.exerciseId)) r];

    final agg = aggregateRanks(ranks);
    final hints = <Muscle, List<RankHint>>{
      for (final m in Muscle.values)
        if (!agg.muscles.containsKey(m))
          m: [
            for (final e in hintNames.entries)
              if (!excluded.contains(e.key) && (targets[e.key]?.weightFor(m) ?? 0) >= MuscleTargets.primaryThreshold && _byExercise.containsKey(e.key))
                RankHint(exerciseId: e.key, name: e.value, mine: true),
          ],
    };
    return RankSummary(
      exercises: ranks,
      muscles: agg.muscles,
      regions: agg.regions,
      overall: agg.overall,
      unrankedHints: hints,
      hidden: hidden,
    );
  }
}
```
Rules: ranking is PER EXERCISE ID (not per standard); several exercises can share one standard (`exerciseIds` list; a standard maps N ids -> 1). Exercise rank = the single set with the highest score in the window (ties keep the first encountered because of `>=`). Exercises with no standard are silently unranked. An exercise with no `targets` entry gets `MuscleTargets.empty` -> contributes to no muscle (but still appears in exercise list and in `bestTierIndex`). `bestE1rm` stored = scoring e1RM (bodyweight included for bodyweight kind). `excluded` set = exercises that do NOT count; they are still scored into `hidden`. Hints: for each unranked muscle, "my" exercises (routines + history) with a standard and `weightFor(m) >= 0.5` that are not excluded; `mine` always true (no library suggestions are ever generated).

#### 1.9 Muscle rank, region rank, overall rank

`lib/features/ranks/domain/ranks.dart:449-481`
```dart
/// Muscle rank: weighted average (by contribution) of the best scores of the exercises training it.
/// Region rank: mean of its ranked muscles. Overall: mean of the ranked regions.
({Map<Muscle, MuscleRank> muscles, Map<BodyRegion, RegionRank> regions, RankScore? overall}) aggregateRanks(List<ExerciseRank> ranks) {
  final muscles = <Muscle, MuscleRank>{};
  for (final m in Muscle.values) {
    final contributions = [
      for (final r in ranks)
        if (r.targets.weightFor(m) > 0) MuscleContribution(r, r.targets.weightFor(m)),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
    if (contributions.isEmpty) continue;
    final totalW = contributions.fold<double>(0, (a, c) => a + c.weight);
    final value = contributions.fold<double>(0, (a, c) => a + c.rank.score.value * c.weight) / totalW;
    muscles[m] = MuscleRank(muscle: m, score: RankScore(value), contributions: contributions);
  }
  final regions = <BodyRegion, RegionRank>{};
  for (final r in BodyRegion.values) {
    final ranked = [for (final m in r.muscles) ?muscles[m]?.score];
    regions[r] = RegionRank(
      region: r,
      score: ranked.isEmpty ? null : averageScore(ranked),
      ranked: ranked.length,
      total: r.muscles.length,
    );
  }
  final rankedRegions = [for (final r in regions.values) ?r.score];
  return (muscles: muscles, regions: regions, overall: rankedRegions.isEmpty ? null : averageScore(rankedRegions));
}

/// Mean of rank scores on the same continuous scale. Identical scores average back to the same rank.
RankScore averageScore(Iterable<RankScore> scores) {
  final list = scores.toList();
  return RankScore(list.fold<double>(0, (a, s) => a + s.value) / list.length);
}
```
- Muscle = weighted mean of the best-set point values of every counted exercise with weight > 0 on that muscle (weight = hand-authored 0-1 contribution; ANY weight > 0 counts, including 0.3 secondaries; there is NO min-weight threshold for ranking; 0.5 is only for hints/volume). Contributions sorted strongest weight first (stable-sort not guaranteed in Dart list sort; ties order unspecified).
- Region = UNWEIGHTED mean of its ranked muscles; unranked muscles are skipped (not counted as 0); `ranked`/`total` shown as "X/Y ranked".
- Overall = unweighted mean of ranked regions (6 regions: arms, legs, core, shoulders, chest, back; enum order `lib/core/domain/muscles.dart:3-9`); null if no region ranked.
- No region/muscle floor of minimum counts.

`lib/core/domain/muscles.dart:1-85` (full enums; region->muscle mapping; keys used in JSON/deep links)
```dart
enum BodyRegion {
  arms('Arms'),
  legs('Legs'),
  core('Core'),
  shoulders('Shoulders'),
  chest('Chest'),
  back('Back');
  ...
  List<Muscle> get muscles => [for (final m in Muscle.values) if (m.region == this) m];
  static BodyRegion? fromName(String name) {...}
}

enum Muscle {
  biceps('Biceps', BodyRegion.arms, 'biceps'),
  triceps('Triceps', BodyRegion.arms, 'triceps'),
  forearms('Forearms', BodyRegion.arms, 'forearms'),
  quadriceps('Quadriceps', BodyRegion.legs, 'quadriceps'),
  hamstrings('Hamstrings', BodyRegion.legs, 'hamstrings'),
  glutes('Glutes', BodyRegion.legs, 'glutes'),
  calves('Calves', BodyRegion.legs, 'calves'),
  adductors('Adductors', BodyRegion.legs, 'adductors'),
  abductors('Abductors', BodyRegion.legs, 'abductors'),
  abdominals('Abdominals', BodyRegion.core, 'abdominals'),
  obliques('Obliques', BodyRegion.core, 'obliques'),
  frontDelt('Front Delt', BodyRegion.shoulders, 'front_delt'),
  middleDelt('Middle Delt', BodyRegion.shoulders, 'middle_delt'),
  rearDelt('Rear Delt', BodyRegion.shoulders, 'rear_delt'),
  upperChest('Upper Chest', BodyRegion.chest, 'upper_chest'),
  lowerChest('Lower Chest', BodyRegion.chest, 'lower_chest'),
  lats('Lats', BodyRegion.back, 'lats'),
  upperBack('Upper Back', BodyRegion.back, 'upper_back'),
  traps('Traps', BodyRegion.back, 'traps'),
  lowerBack('Lower Back', BodyRegion.back, 'lower_back');
  ...
  static Muscle? fromKey(String key) {
    for (final m in values) {
      if (m.key == key || m.name == key) return m;
    }
    return null;
  }
}

class MuscleTargets {
  const MuscleTargets(this.weights);
  final Map<Muscle, double> weights;
  static const empty = MuscleTargets({});

  /// Weight ≥ 0.5: counts for volume, the training-load modifier and quests.
  static const double primaryThreshold = 0.5;
  Set<Muscle> get primary => {for (final e in weights.entries) if (e.value >= primaryThreshold) e.key};
  Set<Muscle> get secondary => {for (final e in weights.entries) if (e.value > 0 && e.value < primaryThreshold) e.key};
  ...
  double weightFor(Muscle m) => weights[m] ?? 0;
  List<MapEntry<Muscle, double>> get ranked => weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
```
(20 muscles, 6 regions; the `muscles` getter order = enum declaration order, which is also the UI order.)

#### 1.10 Where an exercise's muscle weights come from

`lib/features/library/domain/muscle_mapping.dart:27-138`: hand-authored `assets/exercise_muscles.json` table first, else derived. Verbatim logic:
```dart
/// Contributions for an exercise: the hand-authored table, else derived from its dataset muscles.
MuscleTargets targetsFor(String id, String name, Iterable<String> primaryMuscles, Iterable<String> secondaryMuscles) =>
    ExerciseMuscleTable.lookup(id) ?? deriveTargets(name, primaryMuscles, secondaryMuscles);

/// Default contributions: dataset primary muscles at 1.0 and secondary at 0.3, split into the 20
/// ranking muscles by name keywords (incline → upper chest, decline/dip → lower chest, lateral raise
/// → middle delt, reverse fly/face pull → rear delt, twists and side bends → obliques).
MuscleTargets deriveTargets(String name, Iterable<String> primaryMuscles, Iterable<String> secondaryMuscles) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  final out = <Muscle, double>{};
  void add(Muscle m, double w) => out[m] = math.max(out[m] ?? 0, w);

  void map(String dataset, double w) {
    switch (dataset.toLowerCase().trim()) {
      case 'chest':
        if (has(['incline'])) {
          add(Muscle.upperChest, w);
          add(Muscle.lowerChest, w * 0.5);
        } else if (has(['decline', 'dip'])) {
          add(Muscle.lowerChest, w);
          add(Muscle.upperChest, w * 0.3);
        } else {
          add(Muscle.lowerChest, w);
          add(Muscle.upperChest, w * 0.6);
        }
      case 'shoulders':
        if (has(['reverse fly', 'reverse flye', 'rear delt', 'face pull', 'rear lateral', 'bent over lateral', 'bent-over lateral', 'reverse machine'])) {
          add(Muscle.rearDelt, w);
        } else if (has(['lateral', 'upright row', 'side raise', 'y raise', 'y-raise'])) {
          add(Muscle.middleDelt, w);
        } else if (has(['front raise', 'front cable raise', 'front plate', 'front dumbbell raise', 'front incline'])) {
          add(Muscle.frontDelt, w);
        } else if (has(['row', 'pull', 'chin'])) {
          // Shoulders as a helper in pulling: the rear delts.
          add(Muscle.rearDelt, w);
        } else {
          add(Muscle.frontDelt, w);
          if (has(['press', 'military', 'overhead', 'arnold', 'push press', 'jerk', 'handstand'])) add(Muscle.middleDelt, w * 0.5);
        }
      case 'lats':
        add(Muscle.lats, w);
      case 'middle back':
        add(Muscle.upperBack, w);
      case 'traps':
        add(Muscle.traps, w);
      case 'lower back':
        add(Muscle.lowerBack, w);
      case 'abdominals':
        if (has(['oblique', 'twist', 'side bend', 'woodchop', 'wood chop', 'side plank', 'pallof', 'russian', 'windmill', 'side jackknife'])) {
          add(Muscle.obliques, w);
          add(Muscle.abdominals, w * 0.4);
        } else {
          add(Muscle.abdominals, w);
        }
      case 'biceps':
        add(Muscle.biceps, w);
      case 'triceps':
        add(Muscle.triceps, w);
      case 'forearms':
        add(Muscle.forearms, w);
      case 'quadriceps':
        add(Muscle.quadriceps, w);
      case 'hamstrings':
        add(Muscle.hamstrings, w);
      case 'glutes':
        add(Muscle.glutes, w);
      case 'calves':
        add(Muscle.calves, w);
      case 'abductors':
        add(Muscle.abductors, w);
      case 'adductors':
        add(Muscle.adductors, w);
      case 'neck':
        add(Muscle.traps, w * 0.3);
    }
  }

  for (final m in secondaryMuscles) {
    map(m, 0.3);
  }
  for (final m in primaryMuscles) {
    map(m, 1.0);
  }
  return MuscleTargets(out);
}
```
Table loader: `ExerciseMuscleTable.load(json)` reads `exercises` map; keys via `Muscle.fromKey(key)` (unknown keys dropped via `?`), values `num->double` (`muscle_mapping.dart:37-46`). `datasetMuscles` list (17 names) `muscle_mapping.dart:7-25`. `ExerciseInfo` (`lib/features/library/domain/exercise_info.dart:28-29`) computes `targets = targetsFor(id,name,primaryMuscles,secondaryMuscles)` and `equipmentKind = EquipmentKind.fromDataset(equipment)` in its constructor; the ranks code reads `catalog[id].targets` (`ranks_repository.dart:85`).

#### 1.11 "Counts toward rank" toggle: policy and default rules

`lib/features/ranks/data/rank_exclusions.dart:1-113` (entire file; THE source of truth for exclusions)
```dart
/// Where an exercise's "Counts toward rank" switch comes from.
enum RankSource { manualOn, manualOff, routine, auto, off }

/// Which exercises feed ranks. An exercise counts when:
/// 1. you switched it on or off by hand (manual always wins), else
/// 2. it is in one of your current routines, else
/// 3. you completed a working set of it in an in-app workout (automatic), else it is off.
/// Imported (Liftoff) history never switches anything on. Their sets stay in history and PRs either way.
class RankPolicy {
  ...
  RankSource sourceOf(String id) {
    final m = manual[id];
    if (m != null) return m ? RankSource.manualOn : RankSource.manualOff;
    if (routineIds.contains(id)) return RankSource.routine;
    if (auto.contains(id)) return RankSource.auto;
    return RankSource.off;
  }

  bool get isOn(String id) => ... // manualOn || routine || auto => true; manualOff || off => false
}

class RankExclusions {
  static const legacyKey = 'rank_excluded_exercises';
  static const manualKey = 'rank_manual';
  static const autoKey = 'rank_auto_on';
  static const migratedKey = 'rank_policy_v2';
  ...
  Future<Set<String>> _routineIds() async =>
      {for (final r in await _db.select(_db.routineExercises).get()) r.exerciseId};
  ...
  /// Every exercise that does NOT count toward ranks (the whole library minus [RankPolicy.isOn]).
  Future<Set<String>> load() async {
    final p = await policy();
    final ids = (await _db.customSelect('SELECT id FROM exercises').get()).map((r) => r.read<String>('id'));
    return {for (final id in ids) if (!p.isOn(id)) id};
  }

  /// Re-emits when settings or the routines change.
  Stream<Set<String>> watch() => _db
      .customSelect('SELECT 1', readsFrom: {_db.appSettings, _db.routineExercises, _db.exercises})
      .watch()
      .asyncMap((_) => load());

  /// The switch on the muscle sheet, the Ranks tab and the exercise page: a manual choice.
  Future<void> set(String id, {required bool excluded}) async {
    final m = _decodeManual(await _db.getSetting(manualKey));
    m[id] = !excluded;
    await _putManual(m);
  }

  /// A completed in-app working set switches the exercise on, unless you chose by hand.
  Future<void> autoEnable(String id) async {
    if (_decodeManual(await _db.getSetting(manualKey)).containsKey(id)) return;
    final auto = _decodeSet(await _db.getSetting(autoKey));
    if (auto.add(id)) await _db.putSetting(autoKey, jsonEncode(auto.toList()..sort()));
  }

  /// One time: exercises you had hidden that are in a routine stay off (by hand); exercises you did in
  /// in-app workouts are switched on (automatic). Everything else follows the routine rule.
  static Future<void> ensureMigrated(AppDatabase db) async {
    if (await db.getSetting(migratedKey) != null) return;
    final repo = RankExclusions(db);
    final legacy = _decodeSet(await db.getSetting(legacyKey));
    final inRoutines = await repo._routineIds();
    final manual = _decodeManual(await db.getSetting(manualKey));
    for (final id in legacy) {
      if (inRoutines.contains(id)) manual.putIfAbsent(id, () => false);
    }
    final done = await db.customSelect('''
      SELECT DISTINCT se.exercise_id AS id FROM workout_sets w
      JOIN session_exercises se ON se.id = w.session_exercise_id
      JOIN sessions s ON s.id = se.session_id
      WHERE s.source = 'app' AND w.completed = 1 AND w.is_warmup = 0 AND w.set_type IS NULL AND w.reps > 0
    ''').get();
    final auto = {for (final r in done) r.read<String>('id')}..removeAll(manual.keys);
    await repo._putManual(manual);
    await db.putSetting(autoKey, jsonEncode(auto.toList()..sort()));
    await db.putSetting(migratedKey, DateTime.now().toIso8601String());
  }
}
```
Persistence: `app_settings` key/value table (`lib/core/db/tables.dart:239-244`, `key` PK text, `value` text). `rank_manual` = JSON object `{exerciseId: bool}` (true = on by hand); `rank_auto_on` = sorted JSON array of ids; `rank_policy_v2` = ISO timestamp migration marker; `rank_excluded_exercises` = legacy JSON array. `routine_exercises` rows (any routine) = "in a routine". `load()` returns the library (`exercises` table, incl. custom) minus counted ones (i.e. EXCLUDED ids; default for any id not in a routine/auto/manual = excluded). Ids not in the `exercises` table are never in the excluded set (so an unknown id counts).

Auto-enable triggers (two places): (1) on set completion `lib/features/workout/data/session_repository.dart:678-681`
```dart
    // A real working set (not a warm-up, a drop / myo / hold, or an empty one) switches the exercise on for ranks.
    if (!isWarmup && reps > 0 && set.setType == null) {
      final ex = await (_db.select(_db.sessionExercises)..where((t) => t.id.equals(set.sessionExerciseId))).getSingleOrNull();
      if (ex != null) await RankExclusions(_db).autoEnable(ex.exerciseId);
    }
```
(2) a safety net at Finish `lib/features/workout/data/finish_service.dart:228-229`: `if (e.workingSets.any((s) => s.reps > 0)) await RankExclusions(_db).autoEnable(e.exerciseId);` (before computing `excludedNow`). Un-ticking leaves it on. Manual off beats everything (even adding to routine / completing sets; re-adding to a routine does not turn it back on).

UI: `RankToggle` (`lib/features/ranks/presentation/rank_toggle.dart:1-26`) = Material Switch, value `!hidden.contains(id)`, onChanged -> `RankExclusions.set(id, excluded: !on)`; Tooltip "Counts toward rank"; key `rank-toggle-<exerciseId>`; reads `rankExclusionsProvider` (stream). Used on muscle sheet rows, Ranks tab lift cards, hidden rows, exercise page.

Tests (edge cases) `test/data/rank_policy_test.dart`: default = routine-only; completed working set auto-enables (`RankSource.auto`); no auto from warm-up / drop (`setType:'drop'`) / 0 reps; imported Liftoff (`source:'liftoff'`) never switches on, even after re-running migration; manual off survives completed set (`RankSource.manualOff`); manual on stays; adding to routine -> `RankSource.routine`; migration: legacy-hidden routine exercise -> manualOff, legacy-hidden non-routine -> `off`, exercise done in-app -> on.

#### 1.12 Rank targets / "next rank" logic

(a) Next division e1RM (kg): `StrengthStandard.nextThresholdKg` (quoted in 1.7). Target points = `(value + 1e-9).floor() + 1` (i.e. the start of the next division; at division 3 that's the next tier's division 1; at Olympian 3 -> 24 = Immortal). `ExerciseRank.nextThresholdKg` computed at `compute()` with `currentBodyweight` = LATEST weigh-in (`bodyweights.latest`) if > 0 else the best set's day bodyweight (`ranks.dart:531`); null at Immortal. The kg is an e1RM incl. bodyweight for bodyweight-kind lifts.

(b) Turn the e1RM into a concrete set `lib/features/ranks/domain/rank_target.dart:1-67` (verbatim, whole file's logic)
```dart
/// A concrete set that would reach the next rank: [reps] × [weight] kg on the exercise's own weight grid.
class RankTargetSet {
  const RankTargetSet({required this.reps, required this.weight, required this.atMax});
  final int reps;

  /// The logged load: negative for an assisted machine (assistance), 0 for bodyweight.
  final double weight;

  /// The lightest-load answer didn't exist within the max load, so this is the heaviest load with more reps.
  final bool atMax;

  /// "6 × 72.5 kg", "12 × 80 kg (max)", "8 × BW", "8 × −30 kg".
  String get text => '$reps × ${weight == 0 ? 'BW' : '${formatKg(weight).replaceFirst('-', '−')} kg'}${atMax ? ' (max)' : ''}';
  ...
}

const String rankTargetUnreachable = 'Next rank: increase max load or switch variation';

RankTargetSet? rankTargetSet({
  required StrengthStandard standard,
  required double bodyweight,
  required double targetE1rm,
  required int repMin,
  required int rir,
  required WeightGrid grid,
}) {
  if (grid.values.isEmpty || targetE1rm <= 0) return null;
  final rpe = 10.0 - rir;
  final base = standard.bodyweightLoaded ? bodyweight : 0.0;
  final reps = repMin < 1 ? 1 : repMin;
  double e1rm(double w, int r) => scoringE1rm(load: w + base, reps: r, rpe: rpe);
  const eps = 1e-6;
  for (final w in grid.values) {
    if (e1rm(w, reps) >= targetE1rm - eps) return RankTargetSet(reps: reps, weight: w, atMax: false);
  }
  final top = grid.values.last;
  for (var r = reps + 1; r + rir <= scoringRepCap; r++) {
    if (e1rm(top, r) >= targetE1rm - eps) return RankTargetSet(reps: r, weight: top, atMax: true);
  }
  return null;
}

/// "6 × 72.5 kg → Gold 2", or [rankTargetUnreachable]; null when there is no next rank.
String? rankTargetLine(RankTargetSet? set, String? nextLabel) {
  if (nextLabel == null) return null;
  return set == null ? rankTargetUnreachable : '${set.text} → $nextLabel';
}
```
Grid = ascending `WeightGrid.values` (de-duplicated, sorted; `lib/core/domain/gym.dart:242-243`) for that exercise from gym equipment + weights logged; assisted machines: negative values (assistance). Weight formatting uses `formatKg` (`lib/features/coach/domain/suggestion_engine.dart`; NOT in this area; check Section for coach) and replaces "-" with a real minus "−". Prescription (repMin, rir) source `lib/features/ranks/presentation/rank_target_line.dart:9-19`:
```dart
final rankPrescriptionProvider = Provider.family<({int repMin, int rir}), String>((ref, exerciseId) {
  final routines = ref.watch(routinesProvider).value ?? const [];
  for (final r in routines) {
    for (final e in r.exercises) {
      if (e.exerciseId == exerciseId) return (repMin: e.repMin, rir: e.targetRir);
    }
  }
  return (repMin: ref.watch(catalogProvider).value?[exerciseId]?.defaultRange().min ?? 6, rir: 2);
});
```
Inside a running workout, `repMin`/`rir` come from the exercise's prescription (`exercise_block.dart` `_RankStrip` params). Tests `test/domain/rank_target_test.dart`: snaps UP to next grid weight; exact-grid target uses it; higher RIR => lighter weight; above max load => more reps at top weight flagged `(max)` (`12 × 80 kg (max)`); unreachable -> null -> `Next rank: increase max load or switch variation`; no next rank -> null line; per-hand uses dumbbell grid; assisted: lowest passing weight is the most assistance that still reaches it (grid `[0, -5..-80]` ascending after sort: -80 ... -5, 0), text `8 × −20 kg`, bodyweight 0 shows `10 × BW`.

(c) Muscle next step: `lib/features/ranks/domain/ranks.dart:369-397`
```dart
MuscleNextStep? muscleNextStep(MuscleRank m) {
  final label = m.score.nextLabel;
  if (label == null) return null;
  final target = (m.score.value + 1e-9).floorToDouble() + 1;
  final totalW = m.contributions.fold<double>(0, (a, c) => a + c.weight);
  MuscleNextStep? best;
  for (final c in m.contributions) {
    final r = c.rank;
    if (r.bodyweight <= 0) continue;
    final needPoints = r.score.value + (target - m.score.value) * totalW / c.weight;
    final targetE1rm = r.standard.ratioForPoints(needPoints) * r.standard.normalizer(r.bodyweight);
    final kg = targetE1rm - r.bestE1rm;
    if (best == null || kg < best.kg) best = MuscleNextStep(rank: r, kg: kg, targetE1rm: targetE1rm, nextLabel: label);
  }
  return best;
}
```
= for each contributing lift, the e1RM it alone would need (others unchanged) for the weighted average to hit the next division; pick the smallest e1RM increase (kg). Uses the bodyweight of the best set's day (`r.bodyweight`). Test `ranks_test.dart:186-193` (expected Bench +1.6 kg, nextLabel 'Platinum 3'). The muscle sheet then converts `targetE1rm` to a set with `rankTargetSet(standard: r.standard, bodyweight: r.bodyweight, targetE1rm: step.targetE1rm, repMin: rx.repMin, rir: rx.rir, grid: grid)` -> text "Next step: <set.text> on <name> moves <muscle> to <nextLabel>." else "<name>: Next rank: increase max load or switch variation" (`muscle_sheet.dart:165-175`).

#### 1.13 Bodyweight what-if (projection; never stored)

`lib/features/ranks/domain/bodyweight_what_if.dart` (entire file; algorithms)
```dart
/// How far from the current bodyweight a "what if" may go: ±10%.
const double whatIfBand = 0.10;

/// The bodyweights a projection may use around [current] (7-day average).
({double min, double max}) whatIfRange(double current) => (min: current * (1 - whatIfBand), max: current * (1 + whatIfBand));

/// Slider bounds on a 0.5 kg grid, always inside [whatIfRange].
({double min, double max}) whatIfSliderRange(double current) {
  final r = whatIfRange(current);
  return (min: (r.min * 2).ceil() / 2, max: (r.max * 2).floor() / 2);
}

enum BodyweightOutcome {
  /// [BodyweightTarget.bodyweight] reaches the next rank.
  reachable,
  /// Not within the ±10% band (or bodyweight doesn't move this rank at all).
  unreachable,
  /// More bodyweight lowers the rank, so there is no gain to chase that way.
  worse,
  /// No next rank (top of the ladder) or no bodyweight to start from.
  none,
}
...
const String bodyweightUnreachable = 'Not reachable by bodyweight alone';
const String bodyweightWorse = 'More bodyweight would lower this rank';

BodyweightTarget solveBodyweight({required double Function(double bw) score, required double target, required double current}) {
  if (current <= 0) return BodyweightTarget.none;
  const eps = 1e-9;
  final max = whatIfRange(current).max;
  final here = score(current);
  if (score(max) < here - eps) return const BodyweightTarget(BodyweightOutcome.worse);
  if (here >= target - eps) return BodyweightTarget(BodyweightOutcome.reachable, current);
  if (score(max) < target - eps) return const BodyweightTarget(BodyweightOutcome.unreachable);
  var lo = current, hi = max;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (score(mid) >= target - eps) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  // The scale and the slider work in 0.5 kg, so the answer is rounded up to it: it never undershoots the target.
  var bw = (hi * 2).ceil() / 2;
  while (score(bw) < target - eps) {
    bw += 0.5;
  }
  return BodyweightTarget(BodyweightOutcome.reachable, bw);
}

double _nextPoints(RankScore s) => (s.value + 1e-9).floorToDouble() + 1;

BodyweightTarget bodyweightTargetFor(ExerciseRank rank, double current) =>
    rank.score.isApex ? BodyweightTarget.none : solveBodyweight(score: (bw) => rank.atBodyweight(bw).score.value, target: _nextPoints(rank.score), current: current);

BodyweightTarget bodyweightTargetForMuscle(MuscleRank muscle, double current) {
  if (muscle.score.isApex) return BodyweightTarget.none;
  final totalW = muscle.contributions.fold<double>(0, (a, c) => a + c.weight);
  double at(double bw) => muscle.contributions.fold<double>(0, (a, c) => a + c.rank.atBodyweight(bw).score.value * c.weight) / totalW;
  return solveBodyweight(score: at, target: _nextPoints(muscle.score), current: current);
}

/// "Your 6 × 70 kg at 101 kg bodyweight → Gold 2", or why there is no such target. Always a projection, never advice.
String? bodyweightTargetLine(ExerciseRank rank, BodyweightTarget t, String? nextLabel) {
  if (nextLabel == null) return null;
  return switch (t.outcome) {
    BodyweightOutcome.none => null,
    BodyweightOutcome.unreachable => bodyweightUnreachable,
    BodyweightOutcome.worse => bodyweightWorse,
    BodyweightOutcome.reachable =>
      'Your ${RankTargetSet(reps: rank.reps, weight: rank.weight, atMax: false).text} at ${formatKg(t.bodyweight!)} kg bodyweight → $nextLabel',
  };
}

/// Muscle version: "At 101 kg bodyweight → Gold 2 for Chest".
String? muscleBodyweightTargetLine(BodyweightTarget t, String? nextLabel, String muscleLabel) {
  ... // reachable => 'Your current lifts at ${formatKg(t.bodyweight!)} kg bodyweight → $nextLabel for $muscleLabel'
}
```
Re-scoring a best set at another bodyweight `lib/features/ranks/domain/ranks.dart:324-343`
```dart
  ExerciseRank atBodyweight(double bw) {
    final e = scoringE1rm(load: weight + (standard.bodyweightLoaded ? bw : 0), reps: reps, rpe: rpe);
    final projected = e <= 0 || bw <= 0 ? RankScore(0) : standard.scoreForRatio(standard.ratioFor(e, bw));
    return ExerciseRank(... score: projected, bestE1rm: e, bodyweight: bw, weight: weight, reps: reps, rpe: rpe, date: date, targets: targets,
      nextThresholdKg: standard.nextThresholdKg(projected, bw));
  }
```
and `RankSummary.atBodyweight(bw)` re-scores every counted AND hidden exercise at `bw`, then re-aggregates via `aggregateRanks(projected)` (muscles/regions/overall), keeping hints (`ranks.dart:433-446`). Note: every best set is re-scored at ONE bodyweight (not each set's own day bodyweight): at the set's own bodyweight it reproduces the real rank (test `bodyweight_what_if_test.dart:131-134`).
Solver only searches `[current, current*1.10]` (upward); the "current" used is `currentBodyweightProvider` = 7-day mean of weigh-ins else latest, 0 if none (`app_providers.dart:287-291`). Slider (Body tab): min/max = `whatIfSliderRange(current)`, step 0.5 kg; initial = `((current*2).round()/2).clamp(min,max)` (`progress_screen.dart:274-276`). Tests: rising score `0.1/kg above 100` target 0.52 => 105.5; already reached => `reachable(current)`; beyond +10% => unreachable; exactly +10% reachable (110); flat => unreachable; allometric loaded lift => `worse`; assisted lift (weight -50) => reachable at heavier BW; plain-ratio pull-up with BW only => unreachable; weighted dip (+20) => worse; Immortal => `BodyweightTarget.none`.

Mode switch: `RankTargetMode { lift, bodyweight }`, a global `NotifierProvider` defaulting to `lift` (`app_providers.dart:294-302`); one setting for all targets (rank strip in workout, exercise page rank card, muscle sheet). Display helper `whatIfText` prefixes italic "What if · " and bolds the first match of regex `(\d+(?:\.\d+)? kg) (bodyweight)` (`rank_target_line.dart:76-98`).

#### 1.14 Rank history / evolution (chart data)

`lib/features/ranks/domain/rank_history.dart:1-100` (whole file)
```dart
List<RankPoint> rankEvolution({
  required TrainingHistory history,
  required List<StrengthStandard> standards,
  required Map<String, ExerciseInfo> catalog,
  required BodyweightTimeline bodyweights,
  required Set<String> excluded,
  required DateTime now,
  Map<String, String> displayNames = const {},
  int stepDays = 7,
  int dailyDays = 31,
}) {
  if (history.sessions.isEmpty || bodyweights.isEmpty) return const [];
  final first = history.sessions.map((s) => s.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final days = <DateTime>[];
  // One point per [stepDays] over the whole history, one per day over the last [dailyDays] so the Week and Month ranges have a line.
  final dailyFrom = addDays(dateOnly(now), -dailyDays);
  for (var d = dateOnly(first); d.isBefore(dailyFrom); d = addDays(d, stepDays)) {
    days.add(d.add(const Duration(hours: 23, minutes: 59)));
  }
  for (var d = dateOnly(first).isAfter(dailyFrom) ? dateOnly(first) : dailyFrom; d.isBefore(dateOnly(now)); d = addDays(d, 1)) {
    days.add(d.add(const Duration(hours: 23, minutes: 59)));
  }
  days.add(now);
  final out = <RankPoint>[];
  for (final day in days) {
    final s = RanksRepository.compute(history: history, standards: standards, catalog: catalog, bodyweights: bodyweights,
      now: day, excluded: excluded, displayNames: displayNames);
    if (s.overall == null) continue;
    out.add(RankPoint(date: day, overall: s.overall,
      regions: {for (final r in s.regions.values) if (r.score != null) r.region: r.score!},
      muscles: {for (final m in s.muscles.values) m.muscle: m.score}));
  }
  return out;
}

enum EvolutionRange {
  week('Week', 7),
  month('Month', 30),
  threeMonths('3 Months', 90),
  year('Year', 365),
  all('All', null);
  ...
}

typedef EvolutionSample = ({DateTime date, double value});

({DateTime start, List<EvolutionSample> samples}) windowSamples(List<EvolutionSample> all, EvolutionRange range, DateTime now) {
  if (all.isEmpty) return (start: now, samples: const []);
  final days = range.days;
  if (days == null) return (start: all.first.date, samples: all);
  final start = now.subtract(Duration(days: days));
  final inside = [for (final p in all) if (!p.date.isBefore(start)) p];
  final before = all.where((p) => p.date.isBefore(start)).lastOrNull;
  if (before != null && inside.isNotEmpty && inside.first.date.isAfter(start)) {
    final next = inside.first;
    final span = next.date.difference(before.date).inSeconds;
    final f = span <= 0 ? 1.0 : start.difference(before.date).inSeconds / span;
    inside.insert(0, (date: start, value: before.value + (next.value - before.value) * f));
  }
  return (start: start, samples: inside);
}
```
Rules: each point = full `RanksRepository.compute` as of end-of-day (23:59) with its own 90-day window and that day's bodyweight timeline; uses TODAY's exclusion set for all past dates and today's display names; one point per 7 days from first session day until 31 days before today, then one per day for the last 31 days, then `now`. Days with `overall == null` (nothing ranked) are skipped. Series: overall / region (6) / muscle (20) from `RankPoint.regions/muscles` (only present entries). Performance note: O(#points) full recomputations over the whole history (e.g. 52-100+ points). The chart's value is the `RankScore.value` (points); y axis shows tier bands. `ranksProvider`/`rankEvolutionProvider`: `lib/app_providers.dart:269-322`.

#### 1.15 Rank change / rank-up detection (post-workout)

`lib/features/workout/data/finish_service.dart:24-40, 348-408`
```dart
enum RankChangeScope { exercise, muscle, region, overall }

class RankChange {
  const RankChange({required this.name, required this.fromScore, required this.toScore, required this.scope});
  final String name;
  final RankScore? fromScore;
  final RankScore toScore;
  final RankChangeScope scope;

  String? get from => fromScore?.label;
  String get to => toScore.label;

  /// A first placement counts as up.
  bool get up => fromScore == null || toScore.value > fromScore!.value;

  /// Moved to a better division or tier (not just RR), i.e. worth a rank-up animation.
  bool get isRankUp => fromScore != null && toScore.value > fromScore!.value;
}
...
  static const _minGain = 0.005;
  /// Every rank that rose between [before] and [after] (including a first placement), lifts first, then muscles,
  /// regions, and the overall rank last. Order within a group: biggest gain first.
  static List<RankChange> rankGains(RankSummary before, RankSummary after) {
    bool rose(RankScore? from, RankScore to) => from == null || to.value - from.value > _minGain;
    List<RankChange> sorted(List<RankChange> l) => l..sort((a, b) => (b.toScore.value - (b.fromScore?.value ?? 0)).compareTo(a.toScore.value - (a.fromScore?.value ?? 0)));
    ... // lifts: after.exercises where rose(beforeEx[id], r.score); muscles; regions (score != null); overall ('Overall')
    return [...lifts, ...muscles, ...regions, if (overall != null && rose(before.overall, overall)) RankChange(name: 'Overall', ...)];
  }

  static List<RankChange> _rankChanges(RankSummary before, RankSummary after) {
    // exercise / muscle / region / overall: add a RankChange when prev == null || prev.label != now.label (division or tier label changed; includes drops)
  }
```
- `rankGains` (any RR rise > 0.005 points ≈ 0.5 RR, or first placement) drives the Finish rank sequence. `_rankChanges` (label change, includes rank-downs and first placements) -> `SessionSummary.rankChanges`; `rankUps = rankChanges.where(isRankUp)`; `overallRankUp = rankChanges.where(scope==overall && isRankUp).firstOrNull`; `rankDowns = rankChanges.where(!up)` (`finish_service.dart:111-115`).
- Before = ranks computed from history BEFORE the session with exclusion set before; After = history after the session with exclusion set `excludedNow` (re-loaded after auto-enable) (`finish_service.dart:~184-290`: `ranksAfter = await _ranks(after,...,excludedNow)`; before: `_ranks(before,...,excluded)`), both at the same `now`.
- Rank-up screen shown at Finish ONLY if the overall rank changed label upward (`RankStepScreen`: `_showRankUp = _summary?.overallRankUp != null`, `after_workout_screens.dart:50-66`). First placement (from == null) is NOT a rank-up. Then `RankSequenceScreen` with `gains: [if (up == null) ...overall, ...lifts]` (muscle and region gains are computed but NOT shown in that flow; only overall (if it did not already get the full-screen) and lifts).
- Live in-workout detection in `_RankStrip` (`exercise_block.dart:692-780`): baseline = ranksProvider best set; live best = max over the current workout's completed working sets (excluding `isOverride && reps < targetRepMin`), scored with the same formula at the LATEST weigh-in; animation triggers when `live.value > to.value` by >= 0.0005, haptic heavy if the label changed else selection click; un-tick lowers silently.
- Achievement stat: `RanksRepository.bestTierIndex(s) = s.exercises.fold(-1, max tier.index)` (`ranks_repository.dart:98-99`).

#### 1.16 Ladder migration (rank_ladder_version)

`lib/features/ranks/data/ladder_migration.dart:1-69` (whole)
```dart
/// Current rank model. v1: 7 tiers × 3 divisions. v2: League-style 10-tier ladder.
/// v3: per-exercise standards (machines and cables stricter, apex tiers above "elite").
/// v4: allometric bodyweight scaling, accessories anchored to their base compound.
/// v5: only exercises in your routines (or done in an in-app workout) count toward ranks.
/// v6: Valorant ladder: 9 tiers (Iron … Immortal × 3 divisions, Radiant), RR instead of LP.
/// v7: the achievement rework (≈ 50 achievements, none rewarding following suggestions).
/// v8: Olympian joins above Champion (old Immortal's place) and Immortal becomes the top tier (old Radiant's): ranks are
/// derived so they shift by themselves; stored lift achievements are renamed (immortal → olympian, radiant → immortal).
const int rankLadderVersion = 8;
const String rankLadderVersionKey = 'rank_ladder_version';
const String _tierRenameKey = 'rank_tier_rename_v8';
...
Future<LadderMigration> migrateRankLadder({
  required AppDatabase db,
  required AchievementStats stats,
  required List<AchievementDef> defs,
  required DateTime now,
  bool ranksKnown = true,
}) async {
  final current = int.tryParse(await db.getSetting(rankLadderVersionKey) ?? '') ?? 1;
  if (current >= rankLadderVersion) return const LadderMigration();
  final repo = GamificationRepository(db);
  // Silent rename, once (the migration itself can stay pending without bodyweight): old Immortal is Olympian now, old
  // Radiant is Immortal. Order matters, and nothing is announced.
  if (current < 8 && await db.getSetting(_tierRenameKey) == null) {
    final old = await repo.watchUnlocked().first;
    await repo.revoke(['lift_immortal', 'lift_radiant']);
    if (old['lift_immortal'] != null) await repo.unlock(['lift_olympian'], old['lift_immortal']!);
    if (old['lift_radiant'] != null) await repo.unlock(['lift_immortal'], old['lift_radiant']!);
    await db.putSetting(_tierRenameKey, '1');
  }
  if (!ranksKnown) return const LadderMigration();
  final have = await repo.unlockedKeys();
  const eval = AchievementEvaluator();
  final known = {for (final d in defs) d.key};
  // Silently: achievements this version no longer has (e.g. Patience, Disciplined, Comeback) go, earned ones that the
  // new definitions also qualify for unlock, and rank-based ones the new ladder doesn't support are revoked.
  final retired = [for (final k in have) if (!known.contains(k)) k];
  final fresh = eval.newlyUnlocked(defs, stats, have).map((d) => d.key).toList();
  final revoked = [
    for (final d in defs)
      if (d.isRankBased && have.contains(d.key) && !eval.isMet(d, stats)) d.key,
  ];
  if (fresh.isNotEmpty) await repo.unlock(fresh, now);
  if (retired.isNotEmpty || revoked.isNotEmpty) await repo.revoke([...retired, ...revoked]);
  await db.putSetting(rankLadderVersionKey, '$rankLadderVersion');
  return LadderMigration(unlocked: fresh, revoked: [...retired, ...revoked]);
}
```
Rank-based achievement types (`lib/features/gamification/domain/achievements.dart:88-94`): `bestExerciseTier, overallTier, musclesAtTier, regionsAtTier, musclesRanked`. Runs once at startup (`rankLadderMigrationProvider`, `app_providers.dart:552-562`; `ranksKnown: !bodyweights.isEmpty`). Without bodyweight: only the rename step runs; nothing revoked; version key is NOT stamped (stays pending). Missing version setting = 1. Ranks themselves are never persisted. Tests `test/data/ladder_migration_test.dart`: v7 retires gone achievements, revokes unsupported rank ones (`rank_silver`, `rank_master`, `lift_diamond`...), unlocks `lift_silver/gold/platinum` for `bestExerciseTierIndex 4`, second run no-op; fresh install unlocks `lift_silver, lift_gold` for index 3; no bodyweight => no revoke and version stays null; v8 rename keeps unlock dates and happens exactly once even if pending. (Achievements area belongs to another section.)

#### 1.17 Bodyweight-loaded exercises

- `StandardKind.bodyweight` => e1RM load = logged weight + bodyweight (assisted machines log NEGATIVE weight = assistance). Scaling for these is always plain ratio `e1RM / bodyweight` (`normalizer` returns bodyweight). 12 bodyweight standards in the bundle (assisted_dip, assisted_pull_up, back_extension, side_lunge, side_leg_raise, side_lying_hip_adduction, crunch, lying_leg_raise, hanging_leg_raise, dragon_flag, russian_twist, roman_chair_side_bend).
- `RanksRepository.bodyweightLoadedIds` (`ranks_repository.dart:37-43`) = ids of bodyweight standards + catalog entries with `equipmentKind == EquipmentKind.bodyweight` + `extraBodyweightExerciseIds` (`lib/features/library/domain/load_kinds.dart:3-8`: `assistedExerciseIds = {'sp_assisted_pull_up_machine','sp_assisted_dip_machine','Band_Assisted_Pull-Up'}`; extra adds `'Hyperextensions_Back_Extensions'`). This id set is used for PRs/Lifts tab; the rank scorer itself uses ONLY `standard.kind == bodyweight` (see OQ).

#### 1.18 Other rank-adjacent constants (body map / volume heatmap, same files)

`lib/features/ranks/domain/body_regions.dart:66-78` (Volume heatmap buckets used by the body graph)
```dart
VolumeLevel volumeLevel(GroupVolume? v) {
  if (v == null || (v.recentSets == 0 && v.weeklyAverage == 0)) return VolumeLevel.none;
  final r = v.ratio;
  if (r == null) return VolumeLevel.new_;
  if (r < 0.5) return VolumeLevel.under;
  if (r < 0.85) return VolumeLevel.low;
  if (r <= 1.5) return VolumeLevel.onTrack;
  return VolumeLevel.high;
}
```
(`ratio = weeklyAverage > 0 ? recentSets / weeklyAverage : null`; counts = last 7 days vs weekly average of the prior 28 days, `TrainingLoad().counts(...)` in readiness domain, belongs to another section; test `body_map_test.dart:62-75`: `c[Muscle.lats] == (10, 5.0)`.)
`muscleOnBack` (which view shows the muscle): `{triceps, hamstrings, glutes, calves, abductors, rearDelt, lats, upperBack, traps, lowerBack}` -> back, all others front (`body_regions.dart:43-54`).

---------------------------------------------------------------------------------------------------
### 2. SCREENS AND FLOWS

All Flutter files in `lib/features/ranks/presentation/`. Providers are Riverpod (`lib/app_providers.dart`); RN port needs equivalent stores/queries.

Global providers used (`lib/app_providers.dart`):
- `standardsProvider` (`:253`) -> `RanksRepository.loadStandards()` (cached bundle parse of `assets/strength_standards.json`).
- `rankExclusionsProvider` (`:262`) -> `RankExclusions(db).watch()` stream of excluded ids (re-emits when `app_settings`, `routine_exercises`, `exercises` tables change).
- `bodyweightTimelineProvider` (`:265`) -> `watchAll()` of `body_weights` mapped to `BodyweightTimeline`.
- `ranksProvider` (`:269-285`) -> `RanksRepository.compute(history, standards, catalog, bodyweights, now: clock(), excluded, myExerciseIds: routines' exerciseIds, displayNames: routine displayName else catalog name)`.
- `currentBodyweightProvider` (`:287`) -> `timeline.recentAverage(clock())` (7-day mean; latest if none; 0 if no data).
- `latestBodyWeightProvider` (`:178`) -> latest `body_weights` row (used by ladder, lift tabs, in-workout strip).
- `rankTargetModeProvider` (`:302`), `rankEvolutionProvider` (`:307-322`), `rankLadderMigrationProvider` (`:552`), `groupVolumeProvider`, `recoveryProvider`, `exerciseGridProvider(exerciseId)` (`:155`: `gridForExercise(gym equipment, history, info)`), `bodyMapProvider` (`anatomy_graph.dart:15`).

#### 2.1 Progress screen (`progress_screen.dart`, 1047 lines)
Route `/progress`, deep-linkable `?tab=body|ranks|lifts|history`, `?back=1`, `?mode=ranks|recovery|volume`, `?group=<muscle key or enum name>` (`ProgressScreen.fromQuery`, `:41-46`). TabBar with 4 tabs: Body, Ranks, Lifts, History. (Lifts and History tabs live in the same file; Lifts = per-exercise e1RM list with sparkline, History = month calendar + session tiles. Those two are probably owned by another section; they are summarized in 2.9.)

**Body tab** (`_BodyTab`, `:110-255`): shows
- "Bodyweight needed" warning card when no weigh-in exists (tap -> `promptNumber` 30..300 kg -> `bodyWeightRepository.addManual`).
- `_BodyRankHeader`: small overall RankBadge + "BODY RANK · <label>" (or "Unranked").
- Segmented control Rank | Recovery | Volume (`BodyGraphMode`, enum order ranks, recovery, volume; `fromName` default ranks).
- In Rank mode and when `currentBw > 0 && real.exercises.isNotEmpty`: "What if" button -> `_WhatIfPanel`: banner "Projection at X kg", Reset, Slider (min/max = `whatIfSliderRange`, divisions = (max-min)*2, snaps to 0.5), caption "What if you weighed this much with your current best lifts. A projection only: nothing is saved and your real ranks don't change." While on, the whole body map, header and muscle sheet use `real.atBodyweight(whatIf)`; state `_whatIf` is local, never persisted.
- `AnatomyGraph` (front and back side by side), tier legend / volume legend / recovery legend (recovery: Ready >= 90%, Recovering 60-89%, Fatigued < 60%), caption text per mode, and in Rank mode a list of 6 `_RegionCard`s.
- Tap muscle: sets `_selected`, shows `MuscleCallout` (badge + name + trailing: rank label / recovery % / "N sets") above the muscle for 650 ms (`calloutDelay`), then opens `showMuscleSheet`; deep-link opens the sheet without callout once. Mode change clears selection.
- Inputs: `ranksProvider`, `latestBodyWeightProvider`, `groupVolumeProvider`, `recoveryProvider`, `currentBodyweightProvider`.

**Ranks tab** (`_RanksTab`, `:447-519`): `_OverallCard` (76px badge, "OVERALL RANK", label, `RrBar` with `rr`, "Next: <nextLabel> | Top of the ladder · strength <n> · <rankedRegions>/6 regions"), `RankEvolutionCard`, button "The ladder: every tier and what it takes" -> `/ladder`, "Regions" (6 `_RegionCard`s, expandable to `_MuscleRow`s with thumbnail, badge, "Label · RR", RR bar or hint "Try A or B" / "None of your exercises trains it as a main muscle"), "Exercises · best set, last 90 days" (`_LiftRankCard` sorted by score desc: badge, name, strength int, "label · RR", `RrBar`, line `liftLine` + "e1RM X kg · ×R BW (per side)", "<next kg> kg e1RM for <next label>", `RankToggle`; tap -> exercise page `Routes.exercise(id)`), then "Hidden from ranks (n)" (dimmed 0.55 opacity cards for `summary.hidden` and ids that are excluded AND logged but have no set in the 90-day window: "Records kept · not counted"). Hidden list filters excluded ids to those the user has logged (`history.exerciseIds`).

**Region card** (`_RegionCard`): badge 44, "<Region> · X/Y ranked", label, RR bar; toggle expands to the region's muscles. **Muscle row**: `MuscleThumbnail`, label, "label · RR RR", bar; tap -> muscle sheet (mode ranks, `volume: null`).

#### 2.2 Muscle sheet (`muscle_sheet.dart`)
Modal bottom sheet (`DraggableScrollableSheet` initial 0.6, max 0.92) with 3 content modes (rank/volume/recovery) chosen by `BodyGraphMode`; rank content is LIVE (`ref.watch(ranksProvider)`, falls back to passed summary - which is the what-if projection when active in the Body tab).
- Ranked muscle: `RankBadge` medium (84), region caption, muscle name, tier-colored label, `ProgressBar(divisionProgress)`, "<rr> RR · next: <nextLabel> · strength <n>" (Immortal: "<rr> RR · top of the ladder · strength n"), `MuscleThumbnail`; a "next step" box (flag icon) from `muscleNextStep` (see 1.12) with a Lift/Bodyweight toggle (`RankTargetModeToggle`): lift mode text above; bodyweight mode = `whatIfText(muscleBodyweightTargetLine(bodyweightTargetForMuscle(g, currentBodyweight), nextLabel, muscle.label))`; list "CONTRIBUTING EXERCISES" rows (badge 36, name, "<label · RR> · <strength> · ×<weight (0 or 1 decimal)> · <liftLine>", `RankToggle`, tap -> pop sheet + push exercise page), then "NOT COUNTED" hidden rows (opacity .55, "Not counted · <label> · <liftLine>"), footer sentence: "A muscle's rank is the weighted average of its exercises' best strength scores in the last 90 days (×1 = prime mover, lower = helper). Each set is scored against your bodyweight on that day."
- Unranked muscle: grey thumbnail, "Unranked", hints list ("Unranked. Log any of these (from your routines and history) to place it on the ladder:" with hint names) or "None of your exercises trains <muscle> as a main muscle yet. Add one that does to rank it.", plus "NOT COUNTED" rows if hidden exercises train it.
- `liftLine(r)`: `"65 kg × 6 on 6 Oct · 106.5 kg BW"`; assist: "X kg assist"; weight 0: "BW" (`muscle_sheet.dart:199-202`).
- Volume mode: dot + label, 3 StatTiles (Last 7 days sets, 4-week avg / week, Ratio %), per-level sentence, footnote "Counts working sets where this muscle does at least half the work (contribution ≥ 0.5)."
- Recovery mode: `recoveryContent` (belongs to the recovery section).

#### 2.3 Ladder screen (`ladder_screen.dart`, route `Routes.ladder` `/ladder`)
AppBar "The ladder"; intro text; 9 tier cards in REVERSE order (Immortal first); each card: tier name upper-case in tier color, "YOU ARE HERE · <overall label> · <rr> RR" chip if overall tier == tier (card accent + glow), and (if bodyweight > 0, else "Add your bodyweight to see what it takes.") "At X kg bodyweight (best set, e1RM)" + table: columns = divisions (mini badges 34 + "1/2/3"; Immortal: one column, start 24), rows = reference lifts `['bench_press','back_squat','deadlift']`, cells = `(ratioForPoints(points) * normalizer(bodyweight)).round()` kg; the user's current division cell per lift is highlighted (`scoreForRatio(e1rm/normalizer(bw)).value` in [points, points+1) (Immortal: no upper bound), where e1rm = best of `summary.exercises` with `standard.id == s.id`), and under the table "<lift>: You: X kg" or "You: –". Below: "Where each muscle sits": every ranked muscle sorted by score desc with a 9-segment tier bar (flex 3 each, Immortal 2; total 'top' = 26 points) and a marker at `(score.value/26).clamp(0,1)` + label. Uses `latestBodyWeightProvider` (NOT the 7-day average), `ranksProvider`, `standardsProvider`.

#### 2.4 Rank evolution card (`rank_evolution.dart`)
Card "RANK EVOLUTION": current label (top right, tier color), series title, 5 range pills (Week/Month/3 Months/Year/All; default All), chart (230 px high), horizontal scrolling chips: Overall, 6 regions, 20 muscles. `fl_chart` `LineChart`: tier background bands (`HorizontalRangeAnnotation` per tier, alpha 0.16, y = tier points; Immortal band = 24..27), y-range = whole tiers around data (`minY = floor(lo/3)*3`, `maxY = ceil((hi+0.01)/3)*3`, at least 6 tall), left axis one tier label per band (64 px column), x axis date labels per range (`_axisFor`: week 'EEE' every 1 day, month 'd MMM' every 7, 3 months 'd MMM' every 30, year 'MMM' every 91, all: 'MMM yy' if span > 400 days else 'd MMM', interval max(1, span/3)); white 3px curved line (`isCurved: spots.length > 2`, `preventCurveOverShooting`), dots r3 when <= 30 spots; a plot inset of 24 px; tap snaps to nearest point by x (hover/touch tooltips disabled), selected dot r6 white with accent stroke, tooltip card (150x72): date 'd MMM yy', `labelWithRr`, "Score x.xx" (2 decimals of points), tap outside dismisses. Empty states: "Log a few weeks of ranked lifts to draw this." (range All) / "Not enough ranked lifts in this range yet." (needs >= 2 points). Window logic in 1.14. COMPLEXITY: needs a custom chart (e.g. victory-native/skia or react-native-svg) with range bands, snapping tooltip, dynamic axes.

#### 2.5 Anatomy graph / body map (`anatomy_graph.dart`, `data/body_map.dart`, `domain/body_regions.dart`)
- `AnatomyGraph`: FRONT and BACK figures side by side (`_ViewCanvas`, aspect ratio = union bounds of the view), each drawn by `CustomPainter` from SVG path strings: fills by mode (Rank: `tierColors[tier]` or unranked `#3A4255`; Volume: `volumeColor`; Recovery: `recoveryColor`), rank mode adds tier gradient shader (`tierGradients`, top-left -> bottom-right) per muscle path, a subtle white top highlight (alpha 0.10 -> 0, stops [0,0.6]), 1.2px (screen-constant) dark outline (`AppColors.background`), selected muscle glow (stroke 6/s alpha .55 with Gaussian blur 4/s + stroke 2.2/s white). Structure parts (head/hair/hands/feet/knees/ankles) = `AppColors.bodyBase`; neutral parts (neck, tibialis) = `#2A3142`. Tap hit-testing: iterate parts in reverse, `path.contains(point)`, else nearest part center within 14 screen px; haptic selection click.
- `BodyMap` (`data/body_map.dart`): parses `assets/body_map.json` (SVG path `d` strings via `path_parsing`), splits shapes per muscle with GEOMETRIC heuristics tied to the JSON coordinate system: chest top 45% -> upper chest rest lower chest; deltoids outer 40% (by x, outer determined vs. the union center X) -> middle delt, inner -> front delt (front view) / rear delt (back view); upper-back pieces: height > 100 -> lats else upper back; gluteal: height < 70 -> abductors else glutes. Each split piece is made with `Path.combine(PathOperation.intersect, path, rect)` (needs an SVG `clipPath`/rect clip equivalent in RN). Constants verbatim `body_map.dart:71-72` and `:96-118`:
```dart
  static const double upperChestFraction = 0.45;
  static const double middleDeltFraction = 0.40;
  ...
          case 'chest':
            final cut = b.top + b.height * upperChestFraction;
            parts.add(BodyPart(slug: slug, path: _clip(path, Rect.fromLTRB(b.left - 1, b.top - 1, b.right + 1, cut)), muscle: Muscle.upperChest));
            parts.add(BodyPart(slug: slug, path: _clip(path, Rect.fromLTRB(b.left - 1, cut, b.right + 1, b.bottom + 1)), muscle: Muscle.lowerChest));
          case 'deltoids':
            final outerIsLeft = b.center.dx < centerX;
            final cut = outerIsLeft ? b.left + b.width * middleDeltFraction : b.right - b.width * middleDeltFraction;
            ...
            parts.add(BodyPart(slug: slug, path: _clip(path, outer), muscle: Muscle.middleDelt));
            parts.add(BodyPart(slug: slug, path: _clip(path, inner), muscle: isBack ? Muscle.rearDelt : Muscle.frontDelt));
          case 'upper-back':
            parts.add(BodyPart(slug: slug, path: path, muscle: b.height > 100 ? Muscle.lats : Muscle.upperBack));
          case 'gluteal':
            parts.add(BodyPart(slug: slug, path: path, muscle: b.height < 70 ? Muscle.abductors : Muscle.glutes));
          default:
            parts.add(BodyPart(slug: slug, path: path, muscle: bodySlugToMuscle[slug]));
```
  (`centerX` = center x of the union of all path bounds in that view; parts are created per path of `common`, `left`, `right` arrays in that order.) Slug mapping `body_regions.dart:17-34`:
```dart
const Map<String, Muscle> bodySlugToMuscle = {
  'abs': Muscle.abdominals,
  'obliques': Muscle.obliques,
  'biceps': Muscle.biceps,
  'triceps': Muscle.triceps,
  'forearm': Muscle.forearms,
  'trapezius': Muscle.traps,
  'lower-back': Muscle.lowerBack,
  'quadriceps': Muscle.quadriceps,
  'hamstring': Muscle.hamstrings,
  'calves': Muscle.calves,
  'adductors': Muscle.adductors,
};
const Set<String> splitBodySlugs = {'chest', 'deltoids', 'upper-back', 'gluteal'};
const Set<String> neutralBodySlugs = {'neck', 'tibialis'};
```
  Structure slugs (anything else): head, hair, hands, feet, knees, ankles.
- `MuscleThumbnail` (`anatomy_graph.dart:287-336`): square window centred on the muscle's bounds, side = `max(view.bounds.height/3, max(target.w,target.h)*1.6)`, other parts `#3A4255` (muscle/neutral) or `#232A3A` (structure), highlighted muscle in given color.
- `ExerciseMuscleThumb` / `ExerciseBodyFigures` (`:370-475`): exercise-level thumbnails: view = back if summed weights on back muscles > front; window side = `max(view.bounds.height/2.6, max(w,h)*1.35)` around primary muscles (weight >= 0.5); colors: primary `AppColors.accent`, secondary accent alpha .45, none `#3A4252`; legend dots Primary/Secondary on exercise page.
- Fidelity: the source SVG paths are from react-native-body-highlighter v3.2.0 (MIT; `assets/body_map.json` `source` field), i.e. the same library is directly available for RN (but this app splits chest/deltoids/back/glutes into 20 muscles, so the stock library's slugs are not sufficient).

#### 2.6 Rank badge (`rank_badge.dart`, 538 lines) - HEAVY custom painting
`RankBadge(score: RankScore?, size small=30 / medium=68 / hero=184, animate, width)`; null score = "Unranked" grey gem with "?" glyph. Aspect height/width = 130/120. `EmblemPainter(tier, division(1..3 or 0), phase)` paints in a 120x130 design box: kite-gem crystal polygon (top (60,14), ur (90,36), lr (80,86), bot (60,106), ll (40,86), ul (30,36), table points t1..t4), 6 facets shaded along the tier gradient, tier escalation (Iron 2 flat planes, Bronze 5 facets, Silver+ full facets + catch-light, Silver/Gold/Platinum side shards 1/2/3 pairs, Platinum+ inner glow (blurred circle) and radial table light, Diamond floating shards, Champion/Olympian/Immortal wings (3/4/5 feathers) + crown (Champion 3 points, Olympian & Immortal 5) with crown base lifted, Olympian blue body (`#5C86F0` -> deep) with gold accents, Olympian & Immortal central beam, Immortal rays (10 rotating spikes), black facets + shimmer sweep + double glow), division marks (1-3 diamond pips under the gem, lit up to the division), division 2 adds inlay outline (74% scale, white alpha .55) + two shoulder studs, division 3 adds edge glow (blur 5) + bright white edge + crest facet. Immortal animates (2600 ms loop: glow alpha `0.5 + 0.25*sin`, ray rotation, shimmer) only when `animate && score.isApex`. Uses blur MaskFilters, gradient shaders, clipPath, HSL shading. RN needs react-native-svg (LinearGradient/RadialGradient/feGaussianBlur filters not natively supported -> Skia recommended) + Reanimated for the Immortal loop. Tier palette `lib/core/theme/app_theme.dart:72-96`:
```dart
const List<Color> tierColors = [
  Color(0xFF868986), // Iron
  Color(0xFFA5855D), // Bronze
  Color(0xFFBBC2C2), // Silver
  Color(0xFFECCF56), // Gold
  Color(0xFF59A9B6), // Platinum
  Color(0xFFB489C4), // Diamond
  Color(0xFF6AE2AF), // Champion (Valorant's Ascendant)
  Color(0xFF4F7DFF), // Olympian (royal blue and gold)
  Color(0xFFBB3D65), // Immortal
];
const List<(Color, Color)> tierGradients = [
  (Color(0xFFB4B7B5), Color(0xFF5E6160)), // Iron: pale steel → dark steel
  (Color(0xFFD1B085), Color(0xFF7C5522)), // Bronze: sand → deep bronze
  (Color(0xFFE6EBEB), Color(0xFF8E9696)), // Silver: bright → slate
  (Color(0xFFF7E9A2), Color(0xFFC98F1E)), // Gold: pale gold → deep amber
  (Color(0xFF8FD8E0), Color(0xFF2B7F8C)), // Platinum: ice → deep teal
  (Color(0xFFDDBDEB), Color(0xFF763BAF)), // Diamond: lilac → deep violet
  (Color(0xFFA6F5CF), Color(0xFF1C7245)), // Champion: mint → deep green
  (Color(0xFFFFD25E), Color(0xFF2F58D0)), // Olympian: bright gold → deep royal blue
  (Color(0xFFFF6E8E), Color(0xFFA02D55)), // Immortal: rose → deep crimson
];
```
(unranked `#3A4255` `app_theme.dart:29`.) `RrBar` (`lib/core/widgets/game_ui.dart:95-148`): rounded bar on `AppColors.surfaceTop`, fill widthFactor = progress clamp 0..1, gradient `[deep, light]` of the tier (or `lerp(color, black .25) -> color`), glow shadow `color alpha .45 blur 8`, optional "<rr> RR" text.

#### 2.7 Finish flow: rank sequence and rank-up (`rank_sequence_screen.dart`, `rank_up_screen.dart`; used by `lib/features/workout/presentation/after_workout_screens.dart:50-82`)
- `RankStepScreen` (after workout step 2): if `summary.overallRankUp != null` -> `RankUpScreen(changes: [up])` first; then `RankSequenceScreen(title:'RANK PROGRESS', gains: [if (up == null) ...overallGain, ...liftGains])` with a Skip button; Continue -> next step (`advanceAfterWorkout(..., AfterStep.rank)`).
- `RankUpScreen`: 2600 ms controller; hero = overall change else highest `toScore`; timeline: badge fly-in (easeOutBack 0..0.30, translateY (1-fly)*420, scale 0.4+0.6*fly), burst painter (radial glow, expanding ring, 28 seeded sparks (`Random(7)`), 16 rays) from 0.25..0.60, title "RANK UP" (letter-spacing 6, font Oxanium) at 0.38..0.60, label upper-case 36px + "<name> · from <from>", other badges (up to 6, 40px) at 0.55..0.80, "Tap to continue"; heavy haptic at value >= 0.27; tap anywhere ends; `onDone` called once; has `loop` debug mode (replays after 900 ms) and `demoRankUps()`. Debug route in `router.dart:179`.
- `RankSequenceScreen`: rows = headers (LIFTS / MUSCLES / REGIONS / OVERALL RANK) + gains; total budget 6500 ms, per-row = clamp(6500/changes, 380, 1000) ms, controller duration = rowTime*changes + 700 ms; each `_GainRow`: opacity easeOut(progress*4), badge shows interpolated `RankScore(from + (to-from)*easeOutCubic)`, pop (elasticOut, scale up to 1.28 after 70% when label changed), "+N RR" (= round((to-from)*100)) or "NEW" for first placement ("Placed: <label · RR>"), label text "<from> → <to>" once progress >= .99 and label changed, RR bar (`barProgress`: first placement fills to `to.divisionProgress*eased`), card glow when label changed and progress > .9; haptics at each row end (heavy when label changed else selection); tap = fast-forward (`_c.value = 1`) and show "Continue"; empty: "No rank moved in this workout."; reverse-scroll column keeping newest rows visible. Row keys `gain-<scope>-<name>`.

#### 2.8 Other rank surfaces (outside `ranks/presentation`, same logic)
- In-workout rank strip (`lib/features/workout/presentation/exercise_block.dart:692-860`): badge, label, RR bar, target line (Lift: `rankTargetLine(rankTargetSet(...))` with `next = baseline.nextThresholdKg` or `standard.nextThresholdKg(target, bodyweight>0 ? latest : baseline.bodyweight)`; Bodyweight: `bodyweightTargetLine(baseline, bodyweightTargetFor(baseline, currentBodyweight), baseline.score.nextLabel)`), "top of the ladder" for Immortal, "Hidden from ranks", "Unranked · complete a set to place it" / "Not ranked (no strength standard)", plus `RankTargetModeToggle`.
- Exercise detail rank card (`lib/features/library/presentation/exercise_detail_screen.dart:470-510`): badge 64, `labelWithRr`, RR bar, "Best e1RM X kg · W kg × R", target line (both modes, `rankTargetLineFor` uses `rank.bodyweight`), toggle; plus a `_LadderPosition` widget and the exercise body figures.
- Home/Profile show the overall badge (`home_screen.dart:95`, `profile_screen.dart:182`); summary screen lists rank changes (`summary_screen.dart:310`).
- Debug screens: badge gallery/sheet (`lib/features/debug/presentation/badge_*.dart`).

#### 2.9 Lifts / History tabs inside `progress_screen.dart` (not rank logic; for the other section)
Lifts: for each exercise with working sets, `bestE1rm(bodyweight: bwLoaded ? latest bw : 0, validOnly: true)` per session -> sparkline (last 12 points, `SparklinePainter`), "Last d MMM · N sessions · best e1RM X kg", tap -> `Routes.exerciseHistory(id)`. History: month calendar (Mon-first rows, per-day workout/rest icons from `streakMarksProvider`, weekly session count column, selected-day filter) + session tiles (`Routes.session(id)`).

---------------------------------------------------------------------------------------------------
### 3. DATA

#### 3.1 DB tables touched
- `body_weights` (`lib/core/db/tables.dart:197-202`): `id` int autoinc, `measured_at` DateTime, `kg` real, `source` text ('health' | 'manual').
- `app_settings` (`tables.dart:239-244`): `key` text PK, `value` text. Rank keys: `rank_manual` (JSON `{id: bool}`), `rank_auto_on` (JSON sorted `[id]`), `rank_policy_v2` (ISO string marker), `rank_excluded_exercises` (legacy JSON `[id]`), `rank_ladder_version` ('8'), `rank_tier_rename_v8` ('1').
- `routine_exercises` (read for `routineIds` = every `exercise_id`; also `rep_min`, `target_rir`, `display_name` used for prescription/names): presence of an exercise in ANY routine = counts.
- `exercises` (library; `id` read by `SELECT id FROM exercises`), `sessions` (`source`: 'app' | 'liftoff'; `started_at`; `status`), `session_exercises` (`session_id`, `exercise_id`, `position`, `rep_min`, `rep_max`, `target_sets`, `rest_seconds`), `workout_sets` (`session_exercise_id`, `position`, `weight`, `reps`, `rpe`, `is_warmup`, `set_type` null|'drop'|'myo'|'hold', `completed`, `is_override`, `completed_at`, `rest_seconds`, `override_reason`) - the in-memory domain objects are `TrainingHistory` / `HistSession` / `LoggedSet` (`lib/core/domain/history.dart`, `training.dart`; owned by another section).
- Achievements tables via `GamificationRepository` (unlock/revoke/unlockedKeys/watchUnlocked) for the migration (other section).

#### 3.2 Domain models (field/type)
- `RankScore { double value }` (+ derived tier/division/rr/progress/label/strength).
- `StrengthStandard { String id, String name, StandardKind kind(free|machine|cable|bodyweight), List<String> exerciseIds, List<double> anchors(5), bool perHand, BodyweightScaling scaling, List<double> thresholds(9) }`.
- `BodyweightScaling { double referenceBodyweight=100, double exponent=1 }` (`allometric` const = exponent 0.67).
- `RankedSet { String exerciseId, String name, double weight, int reps, double? rpe, DateTime date, double bodyweight }` (input, implements `LoggedSetLike{weight,reps,rpe}`).
- `ExerciseRank { String exerciseId, String name, StrengthStandard standard, RankScore score, double bestE1rm, double bodyweight, double weight, int reps, double? rpe, DateTime date, MuscleTargets targets, double? nextThresholdKg }` + derived `ratio = bestE1rm/bodyweight` (plain), `scaledRatio`, `strength`.
- `MuscleContribution { ExerciseRank rank, double weight }`; `MuscleRank { Muscle muscle, RankScore score, List<MuscleContribution> contributions (strongest first) }`; `RegionRank { BodyRegion region, RankScore? score, int ranked, int total }`; `MuscleNextStep { ExerciseRank rank, double kg, double targetE1rm, String nextLabel }`; `RankHint { String exerciseId, String name, bool mine }`.
- `RankSummary { List<ExerciseRank> exercises, Map<Muscle,MuscleRank> muscles, Map<BodyRegion,RegionRank> regions (always all 6), RankScore? overall, Map<Muscle,List<RankHint>> unrankedHints (key for every unranked muscle), List<ExerciseRank> hidden }`; `rankedRegions` = count of regions with score; `RankSummary.empty`.
- `RankPoint { DateTime date, RankScore? overall, Map<BodyRegion,RankScore> regions, Map<Muscle,RankScore> muscles }`; `EvolutionSample { DateTime date, double value }`; `EvolutionRange { week 7, month 30, threeMonths 90, year 365, all null }`.
- `RankTargetSet { int reps, double weight, bool atMax }`; `BodyweightTarget { BodyweightOutcome outcome(reachable|unreachable|worse|none), double? bodyweight }`.
- `RankPolicy { Map<String,bool> manual, Set<String> auto, Set<String> routineIds }`, `RankSource { manualOn, manualOff, routine, auto, off }`.
- `RankChange { String name, RankScore? fromScore, RankScore toScore, RankChangeScope scope(exercise|muscle|region|overall) }` (`finish_service.dart`); `LadderMigration { List<String> unlocked, revoked }`.
- `GroupVolume { int recentSets, double weeklyAverage }`, `VolumeLevel { none, under, low, onTrack, high, new_ }`.
- `BodyPart { String slug, Path path, RegionRole role(muscle|neutral|structure), Muscle? muscle }`, `BodyView { parts, bounds }`, `BodyMap { front, back }`.

#### 3.3 JSON assets
**`assets/strength_standards.json`** (36,682 bytes; `schema_version: 4`; 103 standards: 39 free, 26 machine, 26 cable, 12 bodyweight).
Top-level keys: `schema_version`, `description` (STALE tier names), `scaling {reference_bodyweight:100, exponent:0.67}`, `machine_strictness: 1.1`, `bases` (5 base compounds), `standards` (array). Bases (anchors at 100 kg reference):
```json
"bases": {"bench": {"beginner":0.6,"novice":0.85,"intermediate":1.15,"advanced":1.5,"elite":1.9}, "squat": {"beginner":0.75,"novice":1.05,"intermediate":1.4,"advanced":1.85,"elite":2.35}, "deadlift": {"beginner":0.9,"novice":1.25,"intermediate":1.6,"advanced":2.1,"elite":2.6}, "ohp": {"beginner":0.38,"novice":0.52,"intermediate":0.7,"advanced":0.92,"elite":1.17}, "row": {"beginner":0.45,"novice":0.65,"intermediate":0.9,"advanced":1.2,"elite":1.5}}
```
Standard entry shapes (91 loaded have `base`+`factor`; 12 bodyweight have none; the app reads only `id, name, kind, exercise_ids, anchors, per_hand`; `base`/`factor` are build-time provenance, enforced equal by a test: loaded anchors = base x factor within 1e-3, bodyweight must NOT have `base`, `machine_strictness` is applied by the app at load):
```json
{"id":"bench_press","name":"Bench press","kind":"free","per_hand":false,"base":"bench","factor":1.0,"exercise_ids":["Barbell_Bench_Press_-_Medium_Grip"],"anchors":{"beginner":0.6,"novice":0.85,"intermediate":1.15,"advanced":1.5,"elite":1.9}}
{"id":"smith_machine_bench_press","name":"Smith machine bench press","kind":"machine","per_hand":false,"base":"bench","factor":1.05,"exercise_ids":["Smith_Machine_Bench_Press"],"anchors":{"beginner":0.63,"novice":0.8925,"intermediate":1.2075,"advanced":1.575,"elite":1.995}}
{"id":"dumbbell_bench_press","name":"Dumbbell bench press","kind":"free","per_hand":true,"base":"bench","factor":0.37,"exercise_ids":["Dumbbell_Bench_Press"],"anchors":{"beginner":0.222,"novice":0.3145,"intermediate":0.4255,"advanced":0.555,"elite":0.703}}
{"id":"assisted_dip","name":"Assisted dip","kind":"bodyweight","per_hand":false,"exercise_ids":["sp_assisted_dip_machine"],"anchors":{"beginner":0.85,"novice":1.0,"intermediate":1.2,"advanced":1.5,"elite":1.8}}
```
Note: in the JSON, machine/cable `anchors` ALREADY include their factor (e.g. smith bench 0.6*1.05=0.63) but NOT the 1.1 strictness (applied at load; test: machine chest press Gold threshold = 1.15 * 1.05 * 1.10, `ranks_test.dart:278-279`). Every id in `exercise_muscles.json` must be covered by some standard's `exercise_ids` (test `ranks_test.dart:256-262`). Every standard's Immortal threshold > 1.29 x Olympian threshold (`:274-277`) and `scaling.exponent == 0.67`.

**`assets/exercise_muscles.json`** (10,230 bytes): `{"schema_version":1,"description":"...","exercises":{"<exerciseId>":{"<muscle key snake_case>": weight 0..1, ...}, ...}}`; 111 exercises, e.g.
```json
"Barbell_Bench_Press_-_Medium_Grip": {"lower_chest":1.0,"upper_chest":0.6,"front_delt":0.5,"triceps":0.4}
"Barbell_Deadlift": {"lower_back":1.0,"glutes":0.8,"hamstrings":0.8,"quadriceps":0.5,"traps":0.5,"forearms":0.4,"lats":0.3}
```
Keys = `Muscle.key` (`front_delt, middle_delt, rear_delt, upper_chest, lower_chest, upper_back, lower_back` etc.; `Muscle.fromKey` also accepts the camelCase enum name).

**`assets/body_map.json`** (42,034 bytes): `{"source": "react-native-body-highlighter v3.2.0 (MIT, ...)", "front": [ {slug, common?:[d...], left?:[d...], right?:[d...]} ... ], "back": [...]}`; `front` has 19 slugs (chest, obliques, abs, biceps, triceps, neck, trapezius, deltoids, adductors, quadriceps, knees, tibialis, calves, forearm, hands, ankles, feet, head, hair), `back` has 16 (neck, trapezius, deltoids, upper-back, triceps, lower-back, forearm, gluteal, adductors, hamstring, calves, ankles, feet, hands, head, hair). Each `common|left|right` entry is an array of SVG path `d` strings (M/L/C/Z only: the `PathProxy` implements moveTo/lineTo/cubicTo/close). Coordinates are unitless; the split heuristics (height > 100, height < 70, 45%, 40%) depend on its coordinate scale. Counts per slug e.g. `upper-back: left 3 right 3`, `gluteal: left 2 right 2`, `chest: left 1 right 1`, `deltoids: left 1 right 1`, `obliques: left 8 right 8`.

#### 3.4 Bundled-data test guards (reproduce in RN tests)
Test `body_map_test.dart:13-49`: every slug classified; union of front and back muscles == all 20; front contains upperChest, lowerChest, frontDelt, middleDelt, abdominals, obliques; back contains rearDelt, middleDelt, lats, upperBack, abductors, glutes, lowerBack; front has no rearDelt; upper chest center above lower chest; abductors center above glutes; every muscle has bounds in its `viewFor` view.

---------------------------------------------------------------------------------------------------
### 4. OPEN QUESTIONS

- OQ: `StrengthScore` doc says "Olympian = 787" (`ranks.dart:95`) but `(21*37.5).round()` = 788 (also test `ranks_test.dart:103` expects 788). docs/DECISIONS.md Valorant table lists Bronze 112 / Gold 338 / Diamond 563 / Immortal(elite) 788: rounding of x.5 is half-away-from-zero in Dart. Confirm the RN port must reproduce `round()` (JS `Math.round` matches for non-negatives).
- OQ: `RankChange.isRankUp` doc says "Moved to a better division or tier (not just RR)" but the code is `fromScore != null && toScore.value > fromScore!.value` (any increase). It is only ever applied to `_rankChanges`, which are label-change-filtered, so effective behaviour matches the doc; but `isRankUp` on a `rankGains` entry is true for any RR-only gain (e.g. used in `rank_gains_test.dart:57`). Confirm intent.
- OQ: Stale docs: docs/DECISIONS.md phase 1 ("League-style, Emerald/Master/Grandmaster/Challenger, IV->I, LP"), "v2 phase 3" neutral muscles (adductors, lower back are described as neutral but are ranked muscles in code), "Fix 1" says exclusion setting is `rank_excluded_exercises` (code: `rank_manual`/`rank_auto_on`), "Rank evolution" section says "ten tier bands"/Challenger (code: nine tiers, Immortal top), strength "25 per point" (code 37.5), and `assets/strength_standards.json` `description` still lists Emerald/Master/Grandmaster/Challenger. Code comments in `nextThresholdKg` ("Challenger"), `ladder_migration.dart` v6 text (Radiant) are also stale. Only code was used for this spec.
- OQ: `docs/RANK_POLICY.md` is a generated report (13 Oct 2026) with old tier names (e.g. "Immortal 2" for Triceps Pushdown predates the Olympian/Immortal rename); informational only.
- OQ: `docs/DECISIONS.md` says the deep link example `?group=chest`, but `Muscle.fromKey('chest')` returns null (chest is split into `upper_chest`/`lower_chest`; there is no 'chest' muscle key). Valid values are muscle `key` (snake_case) or enum `name` (camelCase). Confirm intended deep-link vocabulary (the doc's `group=chest` yields no sheet).
- OQ: Inconsistent bodyweight bases for the "next rank" numbers: `ExerciseRank.nextThresholdKg` uses the LATEST weigh-in (`ranks.dart:531`), the ladder screen and in-workout strip use the latest weigh-in too, but what-if / `currentBodyweightProvider` use the 7-day mean; and `muscleNextStep` and `rankTargetLineFor` (exercise page) use the bodyweight of the best set's DAY (`r.bodyweight`) for the normalizer / bodyweight-lift base load while the exercise-page `targetE1rm` was computed at the latest weigh-in. For bodyweight-kind lifts this may yield a set whose e1RM (computed with day-of-set bodyweight as base) does not reach the target computed at the latest bodyweight. Confirm whether to port as-is.
- OQ: `bodyweightLoadedIds` includes any catalog item with `EquipmentKind.bodyweight` and extras like `Hyperextensions_Back_Extensions`, but the scorer treats an exercise as bodyweight-loaded ONLY if its standard `kind == bodyweight`. An exercise in the id set whose standard is `free` would score without bodyweight, while PR/Lifts-tab code adds bodyweight. (Check that `back_extension` etc. are all `kind: bodyweight` in the bundle; they are, for the 12 listed.) Confirm no mismatch is expected.
- OQ: `RankHint.mine` is always true; "library suggestions" (non-mine hints) are documented in the field comment but never produced. Dead branch.
- OQ: `RankPoint`/`rankEvolution` use today's exclusion set and today's display names for all historical dates (by design, per doc comment) but `myExerciseIds` is omitted (irrelevant for muscles/regions). Performance: O(sessions weeks + 31) full `compute()` calls; the Flutter code recomputes on every dependency change (history, bodyweight, exclusions, routines) with no memoisation. RN needs memoisation/worker.
- OQ: `LoggedSet.isValidForRecords` comment says "isn't a drop set" but the code excludes `isDrop || isMyo || isHold` (`isFollowUp`) and ego sets; in `compute`, sets come from `e.workingSets` (which already filters `isFollowUp`) plus `isValidForRecords`. In the live strip `_live` (`exercise_block.dart:~719`) the filter is `set.isWorkingSet` and `!(isOverride && reps < targetRepMin)`; whether `isWorkingSet` excludes drop/myo/hold is not verifiable from this area. Confirm equivalence.
- OQ: Auto-enable SQL in the migration uses `w.set_type IS NULL` (excludes drop/myo/hold by non-null set_type), while the Finish safety net uses `e.workingSets.any(reps > 0)` (workingSets = completed, non-warm-up, non-follow-up). Equivalent only if every drop/myo/hold set has non-null `set_type` and the `isDrop/isMyo/isHold` getters derive solely from it. Not verified.
- OQ: Ties for the best set: `if (cur != null && cur.score.value >= score.value) continue;` keeps the first set encountered; the order depends on `history.sessions` iteration order (not verified here to be chronological), so which of two equal-score sets is shown (date/weight/reps) may depend on that order.
- OQ: `aggregateRanks` sorts contributions by weight with Dart `List.sort` (not stable); equal-weight contributions have unspecified order. The order affects UI list order and `muscleNextStep` tie-breaking (first min wins with `<`).
- OQ: Region and overall averages are UNWEIGHTED over ranked members, so a region with one ranked muscle out of 5 counts the same as a fully ranked one, and the overall averages regions regardless of "X/Y ranked". Presumably intended (`rank_policy` tables), confirm.
- OQ: `ProgressScreen._BodyTab` what-if with `summary.hidden` -> `atBodyweight` also re-scores hidden exercises; the hidden rows in the muscle sheet then show projected values. Intended? (it is "a projection").
- OQ: In the Finish flow `RankStepScreen` only passes overall and LIFT gains to `RankSequenceScreen`; muscle and region gains are computed (`rankGains`) and used elsewhere (summary static list) but never animated there although the screen itself supports headers MUSCLES/REGIONS. Confirm that muscle/region rows are intentionally dropped from the animation.
- OQ: `bodyweightTargetFor` only searches upward in bodyweight even though `whatIfRange` offers -10%; for "lighter would help" lifts (allometric loaded lifts) the answer is `worse` ("More bodyweight would lower this rank") rather than a lighter target. Test name says "lighter would help, heavier is worse" but the projection never proposes a lighter weight. Confirm intent.
- OQ: `RankScore.divisionProgress` for Immortal is `(value-24) % 1` (wraps every 100 RR), while `rr` is uncapped; `nextLabel` null at Immortal. UI uses divisionProgress for the bar so the Immortal bar loops. Confirm as intended.
- OQ: `BodyweightTimeline.recentAverage` default 7 days uses `now.subtract(Duration(days:7))` (timestamp, not date). Weigh-ins in the future (after `now`) are ignored there, but `at()` still holds/interpolates them.
- OQ: `RanksRepository.compute` returns `RankSummary.empty` if the timeline is empty but a timeline with a 0 kg sample would produce unscored sets (score null since bodyweight <= 0). Unknown whether 0 kg weigh-ins can be stored (UI limits manual entry to 30-300 kg; Health import not checked).
- OQ: `Tier` enum-based tier palette is shared across the app (`tierColors`), but `RrBar`, `GameCard`, `AppType`, `AppColors` are in `lib/core/` (not in this area); exact values for non-tier colors (AppColors.background, bodyBase `#1C2230` per docs, accent, surfaceTop...) were not read here.
- OQ: `formatKg` (from `lib/features/coach/domain/suggestion_engine.dart`) is imported by rank_target.dart and the what-if lines but is not in this area; its rounding/format must be ported exactly because the target text depends on it (tests expect `72.5`, `105.5`, `-20` -> "−20").
- OQ: Hint filter in `compute` requires `_byExercise.containsKey(e.key)` (has standard) and non-excluded, but ignores whether the exercise already has a score; any exercise from routines/history that trains the unranked muscle at >= 0.5 is shown, even when its muscle would be unranked because the exercise has no sets in the 90-day window. (Intended: "log any of these".)
- OQ: Dead/debug code: `RankUpScreen.loop` and `demoRankUps()` are debug-only (route in `router.dart:179`, `badge_gallery_screen.dart`); `nextDivisionLabel(RankScore)` in progress_screen.dart is a trivial alias of `RankScore.nextLabel`; `musclesText` (`ranks_repository.dart:102-103`) not used in this area.

---

# Appendix B. Gamification, readiness and recovery

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `B §n`).

## Section B: Gamification, streaks, readiness, recovery

All paths relative to `/Users/hassan/IdeaProjects/spotter-app`. Code wins over docs. "Today"/"now" always come from `clockProvider` (injectable clock, app_providers.dart). All calendar logic is LOCAL time, weeks start Monday (lib/core/domain/dates.dart:1-25).

Shared date helpers (needed by everything below):

`lib/core/domain/dates.dart:4-25`
```dart
DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Monday 00:00 of the week containing [t].
DateTime weekStart(DateTime t) {
  final d = dateOnly(t);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// `yyyy-MM-dd` key for a local date.
String dayKey(DateTime t) {
  final d = dateOnly(t);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

DateTime parseDayKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);
```
RN note: `addDays` is calendar arithmetic (keeps wall-clock time, DST-safe), NOT +24h.

Set predicates used throughout (lib/core/domain/training.dart, outside my area but load-bearing):

`lib/core/domain/training.dart:78-104`
```dart
  double get tonnage => isHold ? 0 : weight * reps;
...
  /// Completed, not a warm-up (drop sets included: they count for volume).
  bool get isWorking => !isWarmup && completed;
...
  bool get isValidForRecords => isWorking && !isFollowUp && !isEgoSet;
```
`lib/core/domain/history.dart:51-52,86-88` (HistExercise/HistSession)
```dart
  List<LoggedSet> get loggedSets => [for (final s in sets) s.set];
  List<LoggedSet> get workingSets => [for (final s in sets) if (s.set.isWorking) s.set];
...
  Iterable<LoggedSet> get workingSets => exercises.expand((e) => e.workingSets);
  double get volume => workingSets.fold<double>(0, (v, s) => v + s.weight * s.reps);
```

---------------------------------------------------------------------------
### 1. BUSINESS LOGIC

#### 1.1 Day streak (`lib/features/gamification/domain/streaks.dart`)

**What counts as a workout day.** A finished session with at least one exercise that has a working set (completed, non-warm-up). The day is the LOCAL calendar day of `startedAt` (crossing midnight does not move it). Several sessions the same day count once.

`lib/features/gamification/domain/streaks.dart:220-224`
```dart
/// Start times of finished sessions that count for the streak (at least one completed working set).
List<DateTime> streakWorkoutStarts(TrainingHistory history) => [
      for (final s in history.sessions)
        if (s.exercises.any((e) => e.workingSets.isNotEmpty)) s.startedAt,
    ];
```
(`history.sessions` = finished sessions only; see history_repository, other section.)

**Day-boundary / timezone handling.** Day index = integer days since epoch of the local Y/M/D taken as UTC (DST-proof). Every timestamp is converted `.toLocal()` first.

`streaks.dart:95-101`
```dart
/// Calendar-day number of a local date: DST-proof (a 23- or 25-hour day is still one day).
int _dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

DateTime _fromIndex(int i) {
  final u = DateTime.fromMillisecondsSinceEpoch(i * Duration.millisecondsPerDay, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}
```
RN: use local y/m/d -> Date.UTC(y,m,d)/86400000; convert stored UTC instants to device-local first. "now" in `compute` is also `.toLocal()`'d (line 118).

**Constants and the full algorithm.**

`streaks.dart:111-181` (complete, verbatim)
```dart
class DayStreakCalculator {
  const DayStreakCalculator();

  static const int maxRestDays = 2;

  /// [workoutStarts]: start times of finished sessions that had at least one completed working set.
  DayStreak compute({required Iterable<DateTime> workoutStarts, required DateTime now, StreakOffset? offset}) {
    final today = _dayIndex(now.toLocal());
    final offsetDay = offset == null ? null : _dayIndex(offset.date);
    final days = <int>{
      for (final s in workoutStarts)
        if (_dayIndex(s.toLocal()) <= today && (offsetDay == null || _dayIndex(s.toLocal()) > offsetDay)) _dayIndex(s.toLocal()),
    };
    if (offsetDay != null && offsetDay <= today) days.add(offsetDay);
    if (days.isEmpty) return DayStreak.empty;

    final sorted = days.toList()..sort();
    var longest = offset?.days ?? 0;
    // The run alive at the end of the walk.
    int? runStart;
    var carried = false;
    int? last;
    for (final d in sorted) {
      if (last != null && d - last > maxRestDays + 1) {
        // The (maxRestDays + 1)-th rest day ended before this workout: the previous run broke.
        longest = math.max(longest, last + maxRestDays - runStart! + 1);
        runStart = null;
        carried = false;
      }
      if (runStart == null) {
        if (offsetDay != null && d == offsetDay) {
          runStart = offsetDay - offset!.days + 1;
          carried = true;
        } else {
          runStart = d;
        }
      }
      last = d;
    }
    final gap = today - last!;
    if (gap > maxRestDays + 1) {
      final lostRun = last + maxRestDays - runStart! + 1;
      longest = math.max(longest, lostRun);
      return DayStreak(
        days: 0,
        longestDays: longest,
        safety: StreakSafety.lost,
        carriedOver: false,
        lastWorkoutDay: _fromIndex(last),
        lostRunDays: lostRun,
      );
    }
    // Through today when a workout is done today, else through yesterday (today is not earned yet).
    final current = today - runStart! + (gap == 0 ? 1 : 0);
    longest = math.max(longest, current);
    return DayStreak(
      days: current,
      longestDays: longest,
      safety: switch (gap) {
        0 => StreakSafety.trainedToday,
        1 => StreakSafety.safe,
        2 => StreakSafety.oneRestDay,
        _ => StreakSafety.lastChance,
      },
      carriedOver: carried,
      lastWorkoutDay: _fromIndex(last),
      lastChanceDay: _fromIndex(last + maxRestDays + 1),
      runStart: _fromIndex(runStart),
    );
  }
}
```
Plain-language rules derived from it (D = set of distinct workout day indexes, `today` index):
- Workout days after "today" (future sessions) are ignored (`<= today`).
- Run breaks between consecutive workout days d_prev, d when `d - d_prev > 3` (i.e. 3+ rest days between them). Run length of a broken run = `last + 2 - runStart + 1` (the last workout day plus its two allowed rest days).
- Current streak = `today - runStart` (days up to YESTERDAY, includes ended rest days) `+ 1` only if a workout happened today (`gap == 0`). So today never counts until earned; rest days count when they end (midnight).
- `gap = today - lastWorkoutDay`. gap 0 trainedToday, 1 safe, 2 oneRestDay, 3 lastChance, `> 3` lost (days = 0). When lost: `carriedOver:false`, `lastChanceDay/runStart` null, `lostRunDays` set. `longestDays` always includes the lost run.
- Empty set of days => `DayStreak.empty` (days 0, longest 0, safety none). NOTE: with an offset but zero sessions the offset day itself is in `days` (if offsetDay <= today), so streak continues from the offset.
- `lastChanceDay = last + 3` (the 3rd day after last workout) = the day you must train; `daysOnLastChance = lastChanceDay - runStart + 1`.

`streaks.dart:25-44` StreakSafety enum (names and meanings)
```dart
enum StreakSafety {
  /// A workout was finished today (today is earned).
  trainedToday,

  /// Trained yesterday; today may be a rest day.
  safe,

  /// Yesterday was a rest day (one of the two allowed).
  oneRestDay,

  /// Two rest days in a row are behind you: train today or the streak resets tonight.
  lastChance,

  /// No streak running (never started).
  none,

  /// The streak was lost: a 3rd day in a row ended without a workout. Shows 0 until the next workout.
  lost,
}
```
Result object `streaks.dart:52-93`: fields `days, longestDays, safety, carriedOver, lastWorkoutDay?, lastChanceDay?, runStart?, lostRunDays=0`; `lost => safety==lost`; `earnedToday => safety==trainedToday`; `static const lostMessage = 'Streak lost after 3 days without training';`; `static const empty = DayStreak(days: 0, longestDays: 0, safety: StreakSafety.none, carriedOver: false);`

**Liftoff offset (carry-over).** A setting (key/value table `app_settings`), JSON `{"date":"yyyy-MM-dd","days":N}`. It stands in for every day up to and including `date` (that day counts as a workout day, run starts at `date - days + 1`); real sessions on or before `date` are ignored; from `date + 1` the normal rules apply (so 3 rest days after the offset day resets it, `longest` keeps >= offset.days).

`streaks.dart:7-23`
```dart
class StreakOffset {
  const StreakOffset({required this.date, required this.days});
  final DateTime date;
  final int days;

  static const settingKey = 'streak_offset';

  String encode() => jsonEncode({'date': dayKey(date), 'days': days});

  static StreakOffset? decode(String? raw) {
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return StreakOffset(date: parseDayKey(j['date'] as String), days: (j['days'] as num).toInt());
  }
}
```
Where the offset is written/edited:
- Liftoff import, first import only, and only if no offset exists: `lib/features/import/data/liftoff_import_service.dart:27` `const int liftoffStreakDays = 177;` and `:216-218`
```dart
        if (await _db.getSetting(StreakOffset.settingKey) == null) {
          await _db.putSetting(StreakOffset.settingKey, StreakOffset(date: now, days: liftoffStreakDays).encode());
        }
```
- Settings tile (`lib/features/settings/presentation/settings_screen.dart:387-420`): number prompt "Carried-over streak" (days). `if (v == null || v < 0 || v > 5000) return;` `v == 0` deletes the setting; otherwise writes `StreakOffset(date: offset?.date ?? ref.read(clockProvider)(), days: v.round())` (date kept if one exists, else today).
Compute-time filter, note: the offset is applied even when `offset.date` is in the future relative to now? `offsetDay <= today` guard prevents adding it, but `longest` still starts at `offset.days` (line 128).

**Calendar marks** (History calendar + after-workout week + Home dots). Workout days = `StreakDayMark.workout`; rest days that kept the streak alive = `rest`; everything else no mark. Today never gets a rest mark.

`streaks.dart:183-218`
```dart
enum StreakDayMark {
  /// A workout was finished that day.
  workout,

  /// No workout, but it was the 1st or 2nd rest day in a row inside a running streak (it kept the streak alive).
  rest,
}
...
Map<DateTime, StreakDayMark> streakDayMarks({required Iterable<DateTime> workoutStarts, required DateTime now, StreakOffset? offset}) {
  final today = _dayIndex(now.toLocal());
  final offsetDay = offset == null ? null : _dayIndex(offset.date);
  final workouts = <int>{
    for (final s in workoutStarts)
      if (_dayIndex(s.toLocal()) <= today && (offsetDay == null || _dayIndex(s.toLocal()) > offsetDay)) _dayIndex(s.toLocal()),
  };
  if (offsetDay != null && offsetDay <= today) workouts.add(offsetDay);
  final sorted = workouts.toList()..sort();
  final marks = <int, StreakDayMark>{for (final d in sorted) d: StreakDayMark.workout};
  const maxRest = DayStreakCalculator.maxRestDays;
  for (var i = 0; i < sorted.length; i++) {
    final d = sorted[i];
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    final rest = next == null ? maxRest : math.min(maxRest, next - d - 1);
    // A gap longer than the allowance broke the streak at its 3rd day: only the first two days of it kept it alive.
    for (var k = 1; k <= rest; k++) {
      final day = d + k;
      if (day < today) marks[day] = StreakDayMark.rest;
    }
  }
  return {for (final e in marks.entries) _fromIndex(e.key): e.value};
}
```
Keys are local midnight `DateTime`s (callers look up with `dateOnly(...)`).

**Providers/refresh.** `dayStreakProvider`, `streakMarksProvider` watch `dayTickProvider` (a counter bumped at next local midnight +1 s and on app resume) so rest days "count at midnight" without restart.

`lib/app_providers.dart:337-374` (DayTickNotifier + dayStreakProvider)
```dart
  void _arm() {
    _timer?.cancel();
    final now = ref.read(clockProvider)();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      bump();
    });
  }
...
final dayStreakProvider = Provider<DayStreak?>((ref) {
  ref.watch(dayTickProvider);
  final history = ref.watch(historyProvider).value;
  if (history == null) return null;
  return const DayStreakCalculator().compute(
    workoutStarts: streakWorkoutStarts(history),
    now: ref.watch(clockProvider)(),
    offset: ref.watch(streakOffsetProvider).value,
  );
});
```
`lib/app.dart:51-54` app resume: `ref.read(dayTickProvider.notifier).bump();` (also rest-timer resync + health refresh).

**Streak at Finish.** `lib/features/workout/data/finish_service.dart:298-302`
```dart
    final offset = StreakOffset.decode(await _db.getSetting(StreakOffset.settingKey));
    int streakOn(TrainingHistory h) =>
        const DayStreakCalculator().compute(workoutStarts: streakWorkoutStarts(h), now: now, offset: offset).days;
    final streakBefore = streakOn(before), streakAfter = streakOn(after);
```
`finish_service.dart:107` `bool get streakGrew => streakAfter > streakBefore;` (a second workout the same day => no growth => no Streak screen; an empty workout earns nothing).
Longest streak for achievements: `finish_service.dart:411-412` same compute `.longestDays` (offset included).

**Lost-streak snackbar** (Home, `lib/features/home/presentation/home_screen.dart:310-321`): when `days.lost`, once per lost streak (guard setting `_lostSeenKey` = `dayKey(lastWorkoutDay)`), SnackBar text `DayStreak.lostMessage`, 4 s. (`_lostSeenKey` constant defined elsewhere in home_screen.dart; value not read - see OQ.)

**Home status text/colour** (`home_screen.dart:344-351`)
```dart
      StreakSafety.trainedToday => ('Safe: trained today', AppColors.green),
      StreakSafety.safe => ('Safe: trained yesterday, no rest days used', AppColors.green),
      StreakSafety.oneRestDay => ('1 rest day used', AppColors.warning),
      StreakSafety.lastChance => ('Last chance: train today or the streak resets', AppColors.danger),
      StreakSafety.none => ('Your next workout starts a new streak', AppColors.textSecondary),
      StreakSafety.lost => (DayStreak.lostMessage, AppColors.danger),
```
Subtitle `home_screen.dart:~383`: `days.days > 0 && !days.earnedToday ? 'Longest ${days.longestDays} days · today counts when you finish a workout' : 'Longest ${days.longestDays} days'`. Dots for Mon..Sun: trained if any finished session that week started that day OR mark==workout; rest if mark==rest; future/today/empty otherwise. Warning icon (`warning_amber_rounded`) if lastChance else `shield_outlined`. Card taps to Profile. (Home screen belongs to another section; listed only because it renders streak state.)

**Reminder (last chance).** `streaks.dart:232-243`
```dart
({DateTime at, String body})? streakReminderPlan(DayStreak streak, DateTime now, {required bool enabled}) {
  final day = streak.lastChanceDay;
  if (!enabled || day == null || streak.days == 0) return null;
  final at = DateTime(day.year, day.month, day.day, streakReminderHour);
  if (!at.isAfter(now)) return null;
  return (at: at, body: 'Train today to keep your ${streak.days}-day streak.');
}

const int streakReminderHour = 18;
```
Wiring: `streakReminderProvider` (app_providers.dart:388-392) = `streakReminderPlan(dayStreak, clock(), enabled: currentSettings.streakReminder)`; `lib/app.dart:39-42` listens (fireImmediately) and schedules/cancels:
```dart
      _step(() => plan == null ? n.cancelStreakReminder() : n.scheduleStreakReminder(plan.at, body: plan.body));
```
`lib/core/notifications/notification_service.dart:15,74-93`: notification id 1002 (`streakReminderId`), always cancel-then-schedule (single pending), skip if `!at.isAfter(DateTime.now())`, title `'Streak'`, body from plan, iOS alert/sound/banner, Android channel `'streak'` / `'Streak reminder'` default importance, `AndroidScheduleMode.inexactAllowWhileIdle`, zoned via `tz.local`. Setting `streakReminder` default true: `lib/core/settings/app_settings.dart:10,78` `streakReminder: m[kStreakReminder] != 'false'`. (Because it is derived from the live provider, it is rescheduled on every streak change, midnight tick and resume.)

**Profile helper (display only).** `streaks.dart:226-230`
```dart
int sessionsThisWeek(TrainingHistory history, DateTime now) {
  final start = weekStart(dateOnly(now));
  return history.sessions.where((s) => !dateOnly(s.startedAt).isBefore(start) && !s.startedAt.isAfter(now)).length;
}
```
Note: counts ALL finished sessions (even empty ones), unlike the streak filter.

#### 1.2 XP and levels (`lib/features/gamification/domain/xp.dart`)

`xp.dart:6-19`
```dart
class XpRules {
  const XpRules();

  static const int perWorkingSet = 10;
  static const int perPr = 50;
  static const int perQuest = 40;

  /// 10 XP per completed working set. Nothing here looks at the suggestion: following it, beating it or ignoring it
  /// earns the same.
  int forSet(LoggedSet s) => s.isWorking ? perWorkingSet : 0;

  int forSession({required Iterable<LoggedSet> sets, required int prCount}) =>
      sets.fold<int>(0, (sum, s) => sum + forSet(s)) + prCount * perPr;
}
```
Level curve and PR rule:

`xp.dart:21-47`
```dart
/// XP needed to go from [level] to level + 1: `100 × level^1.5`.
int xpToAdvance(int level) => (100 * math.pow(level, 1.5)).round();

LevelInfo levelFor(int totalXp) {
  var level = 1;
  var remaining = math.max(0, totalXp);
  while (remaining >= xpToAdvance(level)) {
    remaining -= xpToAdvance(level);
    level++;
  }
  return LevelInfo(level: level, xpIntoLevel: remaining, xpForNext: xpToAdvance(level), totalXp: totalXp);
}

/// PR detection: a session's best valid e1RM beats the previous all-time best valid e1RM.
/// The first ever session of an exercise is not a PR (it sets the baseline).
bool isPr({required double previousBest, required double sessionBest}) =>
    previousBest > 0 && sessionBest > previousBest + 0.05;
```
`LevelInfo.progress = xpForNext == 0 ? 0 : xpIntoLevel / xpForNext` (xp.dart:28). Test anchors (test/domain/streaks_xp_test.dart:40-52): xpToAdvance(1)=100, (2)=283, (3)=520; levelFor(100).level==2; levelFor(383).level==3; levelFor(500) -> level 3, into 117, forNext 520. JS `Math.round` differs from Dart `round()` on negative halves only; values are positive so same (Dart rounds half away from zero; JS half up; equal for positives).

**XP storage and awarding.** XP is an append-only ledger (`xp_events` table); total = SUM(amount). Awarded in `finish_service.dart:238-260`:
```dart
    final xpSession = _xp.forSession(sets: session.workingSets, prCount: prs.length);
    await _gami.addXp(at: now, amount: xpSession, reason: 'session', sessionId: sessionId);
...
        await _gami.completeQuest(q.row.id, now);
        await _gami.addXp(at: now, amount: XpRules.perQuest, reason: 'quest', sessionId: sessionId, week: week);
        bonus += XpRules.perQuest;
```
`session.xpEarned` column written = `xpSession + bonus` (finish_service ~295). `addXp` skips `amount == 0` (gamification_repository.dart:48). Note `session.workingSets` includes drop/myo/hold sets (isWorking only checks !warmup && completed), so each earns 10 XP. PRs (`findPrs`, 1.3) in THIS session x 50. Imported Liftoff sessions earn no XP (docs/DECISIONS.md:331; code: import service calls `reevaluateAchievements`, "Awards no XP", finish_service.dart:177).
Level shown from `levelFor(sum)`; `totalXpProvider` streams the SUM; `levelProvider = levelFor(totalXp ?? 0)` (app_providers.dart:324-326). The level used for the `level` achievement at finish uses `xpBefore + xpSession + bonus` (finish_service.dart:290).

#### 1.3 PRs and aggregate stats (`lib/features/gamification/domain/stats.dart`)

`stats.dart:21-40` findPrs (replays history chronologically; `history.sessions` order assumed chronological ascending)
```dart
List<PrRecord> findPrs(TrainingHistory history, {Set<String> bodyweightLoaded = const {}, double bodyweight = 0}) {
  final best = <String, double>{};
  final out = <PrRecord>[];
  for (final s in history.sessions) {
    for (final e in s.exercises) {
      final bw = bodyweightLoaded.contains(e.exerciseId) ? bodyweight : 0.0;
      var sessionBest = 0.0;
      for (final set in e.workingSets) {
        if (set.isValidForRecords) sessionBest = math.max(sessionBest, set.e1rm(bodyweight: bw));
      }
      final prev = best[e.exerciseId] ?? 0;
      if (isPr(previousBest: prev, sessionBest: sessionBest)) {
        out.add(PrRecord(sessionId: s.id, exerciseId: e.exerciseId, name: e.name, e1rm: sessionBest, previous: prev));
      }
      if (sessionBest > prev) best[e.exerciseId] = sessionBest;
    }
  }
  return out;
}
```
(e1RM = `estimateOneRm(weight + bodyweight, reps, rpe)` in core/domain, other section. `bodyweight` is the LATEST bodyweight, not per-day, for PR purposes.)

Achievement stats builder (`stats.dart:48-84`):
```dart
  final distinct = <String>{
    for (final s in history.sessions)
      for (final e in s.exercises)
        if (e.workingSets.isNotEmpty) e.exerciseId,
  };
  final bestLift = ranks == null ? -1 : ranks.exercises.fold<int>(-1, (m, r) => r.score.tier.index > m ? r.score.tier.index : m);
  return AchievementStats(
    sessions: history.sessions.length,
    longestStreakDays: longestStreakDays,
    prs: prCount,
    totalVolumeKg: history.sessions.fold<double>(0, (v, s) => v + s.volume),
    totalSets: history.sessions.fold<int>(0, (n, s) => n + s.workingSets.length),
    maxSessionVolumeKg: history.sessions.fold<double>(0, (m, s) => math.max(m, s.volume)),
    level: levelFor(totalXp).level,
    bestExerciseTierIndex: bestLift,
    overallTierIndex: ranks?.overall?.tier.index ?? -1,
    muscleTierIndexes: [for (final m in ranks?.muscles.values ?? const <MuscleRank>[]) m.score.tier.index],
    regionTierIndexes: [for (final r in ranks?.regions.values ?? const <RegionRank>[]) if (r.score != null) r.score!.tier.index],
    distinctExercises: distinct.length,
    greenSessions: history.sessions.where((s) => s.readinessBand == 'green' && s.workingSets.isNotEmpty).length,
    longestSleepStreak: longestSleepStreak({for (final e in sleepMinutesByDay.entries) dayNumber(parseDayKey(e.key)): e.value}),
    fullProgramWeeks: fullProgramWeeks(
      [for (final s in history.sessions) (dayNumber(weekStart(dateOnly(s.startedAt))) ~/ 7, s.routineId)],
      routineIds,
    ),
  );
```
with `int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;` (line 57). Tier indexes: 0 Iron ... 8 Immortal (achievements.dart:14, ranks section owns `Tier`). Week number = `dayNumber(monday) ~/ 7` (epoch day 0 was Thursday, so this is just a unique Monday-aligned bucket id).

Other stats helpers in stats.dart:
- `disciplineLast30` (info only, Profile): `const Guardrail().disciplinePct(history.setsSince(addDays(dateOnly(now), -30)))` (line 43-44). `disciplineProvider` app_providers.dart:394-398.
- `weekActivity` (87-117) builds `QuestWeek` for the week of `anyDayInWeek` from `history.inWeek` (sessions whose `startedAt` in [Monday 00:00, next Monday 00:00)); `isNew` = first session (iteration order) in which the exercise has a working set; `durationMinutes = endedAt - startedAt` in whole minutes (null if `endedAt` null); `prCount` = PRs whose sessionId equals session id; each ExerciseActivity gets `primaryRegions: e.targets.primaryRegions` (muscle weight >= 0.5, see muscles.dart `primaryThreshold = 0.5`), `repMax: e.range.max`, `sets: e.loggedSets` (all sets, incl. warm-ups and uncompleted).
- Dead (no callers found): `rpeLoggedPct` (120-124, last 30 days % of working sets with rpe != null), `regionSetsLast4Weeks` (127-138, from = today-28 days, counts sets of each primary region), see OQ.

#### 1.4 Weekly challenges / quests (`lib/features/gamification/domain/quests.dart`)

Three challenges per Monday-week, pool of 24. Reward when completed: +40 XP (`XpRules.perQuest`), awarded ONLY inside `FinishService.finish` (see 1.2); in the UI a quest `done` also if live progress >= target: `bool get done => quest.row.completedAt != null || progress >= quest.def.target;` (app_providers.dart:~410).

QuestKey enum (14 kinds) `quests.dart:8-23`: sessions, trainGroup, topOfRange, logRpe, newExercise, pr, workingSets, volume, warmups, greenDay, regions, toFailure, sleep, quickSession.

Pool (`quests.dart:91-112`, verbatim):
```dart
final List<QuestDef> weeklyChallengePool = [
  const QuestDef(key: QuestKey.sessions, target: 3),
  const QuestDef(key: QuestKey.sessions, target: 4),
  for (final r in const [BodyRegion.chest, BodyRegion.back, BodyRegion.legs, BodyRegion.shoulders, BodyRegion.arms, BodyRegion.core])
    QuestDef(key: QuestKey.trainGroup, target: 2, group: r),
  const QuestDef(key: QuestKey.topOfRange, target: 2),
  const QuestDef(key: QuestKey.topOfRange, target: 3),
  const QuestDef(key: QuestKey.logRpe, target: 3),
  const QuestDef(key: QuestKey.newExercise, target: 1),
  const QuestDef(key: QuestKey.pr, target: 1),
  const QuestDef(key: QuestKey.pr, target: 2),
  const QuestDef(key: QuestKey.workingSets, target: 60),
  const QuestDef(key: QuestKey.workingSets, target: 90),
  const QuestDef(key: QuestKey.volume, target: 15000),
  const QuestDef(key: QuestKey.volume, target: 25000),
  const QuestDef(key: QuestKey.warmups, target: 3),
  const QuestDef(key: QuestKey.greenDay, target: 1),
  const QuestDef(key: QuestKey.regions, target: 4),
  const QuestDef(key: QuestKey.toFailure, target: 5),
  const QuestDef(key: QuestKey.sleep, target: 5),
  const QuestDef(key: QuestKey.quickSession, target: 1),
];
```
(2 + 6 + 2 + 1 + 1 + 2 + 2 + 2 + 1 + 1 + 1 + 1 + 1 + 1 = 24.)

Id and titles (`quests.dart:32-68`):
```dart
  String get id => '${key.name}:$target:${group?.name ?? ''}';

  String get title {
    switch (key) {
      case QuestKey.sessions:
        return 'Complete $target workouts this week';
      case QuestKey.trainGroup:
        return 'Train ${group!.label.toLowerCase()} ${target == 2 ? 'twice' : '$target times'}';
      case QuestKey.topOfRange:
        return 'Hit the top of your rep range on $target lifts';
      case QuestKey.logRpe:
        return 'Log your effort on every working set in $target workouts';
      case QuestKey.newExercise:
        return 'Try an exercise you have never logged';
      case QuestKey.pr:
        return target == 1 ? 'Set a personal record' : 'Set $target personal records';
      case QuestKey.workingSets:
        return 'Complete $target working sets';
      case QuestKey.volume:
        return 'Lift ${_thousands(target)} kg of total volume';
      case QuestKey.warmups:
        return 'Warm up before your lifts in $target workouts';
      case QuestKey.greenDay:
        return 'Train on a Green readiness day';
      case QuestKey.regions:
        return 'Train $target different body regions';
      case QuestKey.toFailure:
        return 'Take $target sets to failure';
      case QuestKey.sleep:
        return 'Sleep 7+ hours on $target nights';
      case QuestKey.quickSession:
        return 'Finish a workout in 75 minutes or less';
    }
  }

  static String _thousands(int n) => n >= 1000 ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}' : '$n';
```

**Generation** (`quests.dart:194-218`) - deterministic seeded shuffle. RN needs the SAME PRNG only if cross-compat with existing DB weeks is wanted; otherwise any seeded PRNG. Dart `math.Random(seed)` is a specific algorithm (Dart VM/JS differ in sequence; tests only check properties, not specific picks).
```dart
  List<QuestDef> generate(QuestGenInput input, {int count = 3}) {
    final week = DateTime.utc(input.weekStart.year, input.weekStart.month, input.weekStart.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay ~/ 7;
    final rng = math.Random(week * 7919 + 13);
    final pool = [
      for (final q in weeklyChallengePool)
        if (!(q.key == QuestKey.sleep && !input.hasSleepData) && !(q.key == QuestKey.greenDay && !input.hasReadinessData)) q,
    ]..shuffle(rng);
    final fresh = [for (final q in pool) if (!input.recentIds.contains(q.id)) q];
    final ordered = [...fresh, for (final q in pool) if (input.recentIds.contains(q.id)) q];
    final picked = <QuestDef>[];
    final kinds = {...input.exclude};
    for (final q in ordered) {
      if (kinds.contains(q.key)) continue;
      picked.add(q);
      kinds.add(q.key);
      if (picked.length == count) break;
    }
    return picked;
  }
```
Rules: never two of a kind (`key`, not id; two `trainGroup` regions can't coexist), last week's ids (`recentIds`) placed after all fresh ones (fallback only), sleep quest only if any DailyMetric has sleepMinutes, greenDay quest only if readiness data exists.
Inputs built in `questsProvider` (app_providers.dart:~417-433):
```dart
        hasSleepData: days.any((d) => d.sleepMinutes != null),
        hasReadinessData: days.any((d) => d.readinessScore != null) || history.sessions.any((s) => s.readinessBand != null),
```
Persistence/top-up (`gamification_repository.dart:104-121`): in a transaction: delete retired kinds, read this week's rows, `if (existing.length >= 3) return;` else insert `3 - existing.length` generated (excluding existing kinds). Row: weekStart=`dayKey(weekStart(week))`, key=`q.key.name`, params=`jsonEncode({'target':..,'group':..?})`, title=`q.title`. `previousQuestIds` = ids of quests of the previous week (`addDays(weekStart(week), -7)`).
Retired keys (`quests.dart:88`): `const retiredQuestKeys = ['followAll', 'noOverride'];` - deleted from ALL weeks at every `ensureQuests`; unknown keys in DB are skipped on read (`tryFromParams` null).
Legacy group names map (`quests.dart:115-127`): biceps/triceps/forearms->arms; abs->core; quads/hamstrings/glutes/calves->legs; traps->back; else `BodyRegion.fromName`.

**Progress** (`quests.dart:220-263`, verbatim)
```dart
  int progress(QuestDef quest, QuestWeek week) {
    final sessions = week.sessions;
    switch (quest.key) {
      case QuestKey.sessions:
        return sessions.length;
      case QuestKey.trainGroup:
        return sessions.where((s) => s.exercises.any((e) => e.primaryRegions.contains(quest.group) && e.working.isNotEmpty)).length;
      case QuestKey.topOfRange:
        final lifts = <String>{};
        for (final s in sessions) {
          for (final e in s.exercises) {
            final w = e.working;
            if (w.isNotEmpty && w.every((x) => x.reps >= e.repMax)) lifts.add(e.exerciseId);
          }
        }
        return lifts.length;
      case QuestKey.logRpe:
        return sessions.where((s) {
          final w = s.workingSets.toList();
          return w.isNotEmpty && w.every((x) => x.rpe != null);
        }).length;
      case QuestKey.newExercise:
        return {for (final s in sessions) for (final e in s.exercises) if (e.isNew && e.working.isNotEmpty) e.exerciseId}.length;
      case QuestKey.pr:
        return sessions.fold<int>(0, (n, s) => n + s.prCount);
      case QuestKey.workingSets:
        return sessions.fold<int>(0, (n, s) => n + s.workingSets.length);
      case QuestKey.volume:
        return sessions.fold<double>(0, (v, s) => v + s.volume).round();
      case QuestKey.warmups:
        return sessions.where((s) => s.exercises.any((e) => e.sets.any((x) => x.isWarmup && x.completed))).length;
      case QuestKey.greenDay:
        return sessions.where((s) => s.readinessBand == 'green' && s.workingSets.isNotEmpty).length;
      case QuestKey.regions:
        return {for (final s in sessions) for (final e in s.exercises) if (e.working.isNotEmpty) ...e.primaryRegions}.length;
      case QuestKey.toFailure:
        return sessions.fold<int>(0, (n, s) => n + s.workingSets.where((x) => x.rpe != null && x.rpe! >= 9.9).length);
      case QuestKey.sleep:
        return week.sleepNights;
      case QuestKey.quickSession:
        return sessions.where((s) => s.workingSets.isNotEmpty && s.durationMinutes != null && s.durationMinutes! <= 75).length;
    }
  }
```
Helper definitions `quests.dart:146,161-162`:
```dart
  List<LoggedSet> get working => sets.where((s) => s.isWorking).toList();
...
  Iterable<LoggedSet> get workingSets => exercises.expand((e) => e.working);
  double get volume => workingSets.fold<double>(0, (v, s) => v + s.tonnage);
```
Sleep nights (7+ h): computed outside the engine in two places, Monday..Sunday of the week, `m >= 420` minutes, keyed by `dayKey(addDays(monday, i))` on DailyMetric.date:
`app_providers.dart:~436-441` and `finish_service.dart:~247-252`
```dart
  for (var i = 0; i < 7; i++) {
    final m = sleep[dayKey(addDays(monday, i))];
    if (m != null && m >= 420) nights++;
  }
```
At finish the quest week is `weekStart(session.startedAt)` (not "now"), quests read with `_gami.quests(session.startedAt)`; completed ones (`completedAt != null`) skipped; for each with `progress >= target`: `completeQuest(id, now)` + 40 XP.
Provider streams quests with live progress: `repo.watchQuests(now)` mapped to `QuestProgress(q, QuestEngine().progress(q.def, week))` (app_providers.dart:~444-448). Also the debug seed generator calls `ensureQuests` (not product).

`quests.dart:266-271` `sessionsPerWeekLast4` - dead code (see OQ): `(n / 4).round().clamp(1, 14)` over `now - 28 days`.

#### 1.5 Achievements (`lib/features/gamification/domain/achievements.dart`, `assets/achievements.json`)

Definitions are data (JSON, 52 entries, schema_version 2); metric/threshold semantics are in code. Unlock rule: `value >= threshold`; unlocks are permanent (insert-or-ignore) except rank-based ones which may be revoked silently by a migration.

`achievements.dart:193-206`
```dart
class AchievementEvaluator {
  const AchievementEvaluator();

  bool isMet(AchievementDef def, AchievementStats stats) => stats.valueFor(def) >= def.threshold;

  /// 0..1 progress for display.
  double progress(AchievementDef def, AchievementStats stats) {
    if (def.threshold <= 0) return isMet(def, stats) ? 1 : 0;
    return (stats.valueFor(def) / def.threshold).clamp(0.0, 1.0);
  }

  List<AchievementDef> newlyUnlocked(List<AchievementDef> defs, AchievementStats stats, Set<String> alreadyUnlocked) =>
      [for (final d in defs) if (!alreadyUnlocked.contains(d.key) && isMet(d, stats)) d];
}
```
Metric value per type (`achievements.dart:155-190`):
```dart
      case AchievementType.sessions:
        return sessions.toDouble();
      case AchievementType.streakDays:
        return longestStreakDays.toDouble();
      case AchievementType.prs:
        return prs.toDouble();
      case AchievementType.totalVolumeKg:
        return totalVolumeKg;
      case AchievementType.totalSets:
        return totalSets.toDouble();
      case AchievementType.maxSessionVolumeKg:
        return maxSessionVolumeKg;
      case AchievementType.level:
        return level.toDouble();
      case AchievementType.bestExerciseTier:
        return bestExerciseTierIndex.toDouble();
      case AchievementType.overallTier:
        return overallTierIndex.toDouble();
      case AchievementType.musclesAtTier:
        return muscleTierIndexes.where((t) => t >= (d.param ?? 0)).length.toDouble();
      case AchievementType.regionsAtTier:
        return regionTierIndexes.where((t) => t >= (d.param ?? 0)).length.toDouble();
      case AchievementType.musclesRanked:
        return muscleTierIndexes.length.toDouble();
      case AchievementType.distinctExercises:
        return distinctExercises.toDouble();
      case AchievementType.greenSessions:
        return greenSessions.toDouble();
      case AchievementType.sleepStreak:
        return longestSleepStreak.toDouble();
      case AchievementType.fullProgramWeeks:
        return fullProgramWeeks.toDouble();
```
`AchievementStats` defaults (`achievements.dart:119-135`): `level = 1`, `bestExerciseTierIndex = -1`, `overallTierIndex = -1`, empty tier lists, others 0. -1 means "unranked" so tier achievements (threshold >= 2 etc.) are not met.
Rank-based set (`achievements.dart:88-94`): `{bestExerciseTier, overallTier, musclesAtTier, regionsAtTier, musclesRanked}.contains(type)`.
Enums: categories `consistency('Consistency'), strength('Strength'), volume('Volume'), exploration('Exploration'), recovery('Recovery & readiness'), program('Program')`; levels `bronze/silver/gold` (labels Bronze/Silver/Gold). `fromJson` (96-114) defaults: `icon` -> `'star'`, unknown `category` -> consistency, `level` null unless given (a bad level string THROWS - `firstWhere` without orElse), unknown `type` throws FormatException, `threshold` num -> double, `param` num? -> int?.

Helper algorithms (`achievements.dart:208-231`):
```dart
int longestSleepStreak(Map<int, double> sleepMinutesByDay, {double minMinutes = 420}) {
  final days = [for (final e in sleepMinutesByDay.entries) if (e.value >= minMinutes) e.key]..sort();
  var best = 0, run = 0;
  int? last;
  for (final d in days) {
    run = last != null && d == last + 1 ? run + 1 : 1;
    if (run > best) best = run;
    last = d;
  }
  return best;
}

int fullProgramWeeks(Iterable<(int week, int? routineId)> sessionRoutines, Set<int> routineIds) {
  if (routineIds.isEmpty) return 0;
  final byWeek = <int, Set<int>>{};
  for (final (week, routine) in sessionRoutines) {
    if (routine != null && routineIds.contains(routine)) (byWeek[week] ??= {}).add(routine);
  }
  return byWeek.values.where((s) => s.length == routineIds.length).length;
}
```
Sleep map day key: DailyMetric.date (yyyy-MM-dd, the wake-up day) -> epoch day number; "7+ hours" = 420 min.

When evaluated (all in finish_service.dart): (a) `finish()` after XP: `newlyUnlocked(defs, stats, unlockedKeys)` then `_gami.unlock(keys, now)` (`insertOrIgnore`), returned in summary; (b) `reevaluateAchievements` after Liftoff import, no XP (lines ~177-199). (c) Rank ladder migration at startup (`lib/features/ranks/data/ladder_migration.dart`, other section) revokes `['lift_immortal','lift_radiant']` and rank-based ones no longer qualified (`repo.revoke`), silently. Display: `achievementsProvider` merges defs + unlocked map; progress = 1 if unlocked else `eval.progress(def, stats)` (app_providers.dart:~482-490). `achievementStatsProvider` uses `ranksProvider`, latest bodyweight, `dayStreakProvider.longestDays`, XP total, routines ids, daily metrics.

Achievement catalogue (all 52, from `assets/achievements.json`; all `description` strings in file). Format: key | title | type | threshold | category | family/level | param | icon.
```
first_workout | First Rep | sessions | 1 | consistency | - | - | fitness
sessions_25 | Regular | sessions | 25 | consistency | Workouts/bronze | fitness
sessions_100 | Centurion | sessions | 100 | consistency | Workouts/silver | fitness
sessions_250 | Iron Habit | sessions | 250 | consistency | Workouts/gold | trophy
streak_14 | Two Weeks Unbroken | streakDays | 14 | consistency | Streak/bronze | fire
streak_30 | Month of Iron | streakDays | 30 | consistency | Streak/silver | fire
streak_100 | Unbreakable | streakDays | 100 | consistency | Streak/gold | fire
first_pr | New Personal Best | prs | 1 | strength | - | star
pr_5 | Record Setter | prs | 5 | strength | Personal records/bronze | star
pr_25 | Record Breaker | prs | 25 | strength | Personal records/silver | star
pr_100 | Record Machine | prs | 100 | strength | Personal records/gold | star
lift_silver | Silver Lining | bestExerciseTier | 2 | strength | rank
lift_gold | Gold Standard | bestExerciseTier | 3 | strength | rank
lift_platinum | Platinum Plates | bestExerciseTier | 4 | strength | rank
lift_diamond | Diamond Hands | bestExerciseTier | 5 | strength | rank
lift_champion | Apex Predator | bestExerciseTier | 6 | strength | crown
lift_olympian | Olympian Lift | bestExerciseTier | 7 | strength | crown
lift_immortal | Immortal Lift | bestExerciseTier | 8 | strength | crown
overall_silver | Rising | overallTier | 2 | strength | rank
overall_gold | Well Rounded | overallTier | 3 | strength | rank
overall_platinum | Proven | overallTier | 4 | strength | rank
overall_diamond | Elite Body | overallTier | 5 | strength | crown
overall_champion | Champion Body | overallTier | 6 | strength | crown
muscles_gold_1 | First Gold Muscle | musclesAtTier | 1 | strength | Strong muscles/bronze | param 3 | target
muscles_gold_5 | Golden Five | musclesAtTier | 5 | strength | Strong muscles/silver | param 3
muscles_gold_10 | Golden Ten | musclesAtTier | 10 | strength | Strong muscles/gold | param 3
regions_ranked | Whole Body | regionsAtTier | 6 | strength | param 0 | layers
regions_silver | Silver Everywhere | regionsAtTier | 6 | strength | param 2 | layers
volume_100t | 100 Tonnes | totalVolumeKg | 100000 | volume | Lifetime volume/bronze | weight
volume_500t | Half a Kiloton | totalVolumeKg | 500000 | volume | Lifetime volume/silver
volume_1000t | Kiloton | totalVolumeKg | 1000000 | volume | Lifetime volume/gold
sets_250 | Set Starter | totalSets | 250 | volume | Lifetime sets/bronze | weight
sets_1000 | Set Collector | totalSets | 1000 | volume | Lifetime sets/silver
sets_5000 | Set Hoarder | totalSets | 5000 | volume | Lifetime sets/gold
big_day | Big Day | maxSessionVolumeKg | 10000 | volume | - | bolt
explore_10 | Curious | distinctExercises | 10 | exploration | Exercises tried/bronze | compass
explore_25 | Explorer | distinctExercises | 25 | exploration | .../silver
explore_50 | Collector | distinctExercises | 50 | exploration | .../gold
muscles_10 | Half the Map | musclesRanked | 10 | exploration | compass
muscles_all | Every Muscle | musclesRanked | 20 | exploration | compass
green_5 | Green Light | greenSessions | 5 | recovery | Green-day workouts/bronze | leaf
green_25 | Ready to Lift | greenSessions | 25 | recovery | .../silver
green_50 | Peak Condition | greenSessions | 50 | recovery | .../gold
sleep_3 | Early Nights | sleepStreak | 3 | recovery | Sleep streak/bronze | moon
sleep_7 | Sleep Week | sleepStreak | 7 | recovery | .../silver
sleep_14 | Sleep Fortnight | sleepStreak | 14 | recovery | .../gold
program_1 | Full Week | fullProgramWeeks | 1 | program | Complete weeks/bronze | calendar
program_4 | Full Month | fullProgramWeeks | 4 | program | .../silver
program_12 | Full Quarter | fullProgramWeeks | 12 | program | .../gold
level_5 | Level 5 | level | 5 | program | Level/bronze | bolt
level_10 | Double Digits | level | 10 | program | .../silver
level_25 | Level 25 | level | 25 | program | .../gold
```
Icons used: fitness, trophy, fire, star, rank, crown, target, layers, weight, bolt, compass, leaf, moon, calendar. Descriptions (exact text) are in the JSON, e.g. `"Keep a 14-day streak (no more than two rest days in a row)."`, `"Finish your first workout."`; RN should copy the JSON asset verbatim (no transformation needed). Test contract (aggregation_quests_test.dart:241-280): 48..60 defs, unique keys, all six categories used, families have exactly bronze/silver/gold ascending thresholds, text must not contain suggest/override/discipline/coach.

#### 1.6 Readiness (`lib/features/readiness/domain/readiness.dart`)

Inputs per calendar day (`DayMetrics`): `hrvMs`, `restingHr`, `sleepMinutes` (all nullable doubles); `hasAny` = any non-null. Today's row may be absent => all-missing.

Constants `readiness.dart:103-123`:
```dart
  static const int baselineWindowDays = 30;
  static const int calibrationDays = 14;
  static const int minBaselineSamples = 3;
  static const double weightHrv = 0.4;
  static const double weightRhr = 0.3;
  static const double weightSleep = 0.3;
  static const double shortSleepMinutes = 360;

  /// Extra negative z per hour of sleep under 6 h, regardless of baseline.
  static const double shortSleepPenaltyPerHour = 1.0;

  /// Band thresholds (shifted so that a normal day, score 60, is Green — see docs/DECISIONS.md).
  static const int greenMin = 55;
  static const int yellowMin = 40;
  static const int neutralScore = 60;

  /// Readiness penalty for an exercise whose muscle group is over its usual weekly load.
  static const int loadPenalty = 10;
```
Bands and score mapping (`readiness.dart:125-136`):
```dart
  static ReadinessBand bandFor(int score) {
    if (score >= greenMin) return ReadinessBand.green;
    if (score >= yellowMin) return ReadinessBand.yellow;
    return ReadinessBand.red;
  }

  /// Piecewise-linear map of a clamped z in [-2, 2] to 0–100 with z = 0 → 60.
  static int scoreFromZ(double z) {
    final c = z.clamp(-2.0, 2.0);
    final s = c <= 0 ? 60 + c * 30 : 60 + c * 20;
    return s.round().clamp(0, 100);
  }
```
(Dart `round()` = half away from zero; s is always in [0,100] so JS Math.round matches except exact .5 positive - equal. Negative never occurs.)

Baseline stats (`readiness.dart:34-48`): mean and SAMPLE sd (n-1; sd = 0 if n<2):
```dart
  static Baseline? of(List<double> values) {
    if (values.isEmpty) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.length < 2
        ? 0.0
        : values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / (values.length - 1);
    return Baseline(mean, math.sqrt(variance), values.length);
  }
```
Compute (`readiness.dart:138-210`, verbatim):
```dart
  ReadinessResult compute(DayMetrics today, Iterable<DayMetrics> history) {
    final day = dateOnly(today.date);
    final windowStart = addDays(day, -baselineWindowDays);
    final baselineDaysList = history.where((m) {
      final d = dateOnly(m.date);
      return !d.isBefore(windowStart) && d.isBefore(day);
    }).toList();

    final baselineDays = baselineDaysList.where((m) => m.hasAny).length;
    final calibrating = baselineDays < calibrationDays;

    Baseline? baselineOf(double? Function(DayMetrics) pick) =>
        Baseline.of([for (final m in baselineDaysList) ?pick(m)]);

    double? zOf(double? value, Baseline? b, {bool invert = false}) {
      if (value == null || b == null || b.n < minBaselineSamples) return null;
      if (b.sd <= 1e-9) return 0;
      final z = (value - b.mean) / b.sd;
      return invert ? -z : z;
    }

    final hrvB = baselineOf((m) => m.hrvMs);
    final rhrB = baselineOf((m) => m.restingHr);
    final sleepB = baselineOf((m) => m.sleepMinutes);

    final hrvZ = zOf(today.hrvMs, hrvB);
    final rhrZ = zOf(today.restingHr, rhrB, invert: true);
    double? sleepZ = zOf(today.sleepMinutes, sleepB);
    final sleepMin = today.sleepMinutes;
    if (sleepMin != null && sleepMin < shortSleepMinutes) {
      final hoursShort = (shortSleepMinutes - sleepMin) / 60;
      sleepZ = math.min(sleepZ ?? 0, 0) - hoursShort * shortSleepPenaltyPerHour;
    }

    final parts = <(double, double)>[
      if (hrvZ != null) (hrvZ, weightHrv),
      if (rhrZ != null) (rhrZ, weightRhr),
      if (sleepZ != null) (sleepZ, weightSleep),
    ];
    double? combined;
    int? score;
    if (parts.isNotEmpty) {
      final totalW = parts.fold<double>(0, (s, p) => s + p.$2);
      combined = parts.fold<double>(0, (s, p) => s + p.$1 * p.$2) / totalW;
      combined = combined.clamp(-2.0, 2.0);
      score = scoreFromZ(combined);
    }
    ...
    final band = calibrating ? ReadinessBand.green : bandFor(score ?? neutralScore);
```
Rules extracted:
- Baseline window = rows with date in `[day-30, day)` (today excluded, 30 days back inclusive). Calibration counts rows in that window that have ANY metric; `< 14` => calibrating => band forced Green, `coachScore` = 60, but `score` and per-metric z still computed and shown.
- Per metric: needs `n >= 3` baseline samples of THAT metric; sd ~0 => z = 0; RHR z inverted (lower is better). No cross-metric baseline sharing.
- Short sleep (< 360 min): sleepZ := `min(sleepZ ?? 0, 0) - hoursShort*1.0` even when the baseline is insufficient (sleepZ null) or sleep above baseline (negative z clamped to 0 first).
- Missing metrics: weights renormalised over available ones. No usable metric => `score = null`, `combinedZ = null`; band then `bandFor(60)` = green (or green when calibrating).
- `coachScore => (calibrating || score == null) ? ReadinessCalculator.neutralScore : score!` (line 99).
- `missing` list: names `'HRV'`, `'resting heart rate'`, `'sleep'` for metrics null TODAY (independent of z being null).
- Load penalty: `loadPenalty = 10` is applied by suggestion engine (`lib/features/coach/domain/suggestion_engine.dart:43` `loadPenaltyGroups.isEmpty ? score : score - ReadinessCalculator.loadPenalty`), not here.

Reason text (`readiness.dart:212-240`), thresholds: HRV pct vs baseline |pct| >= 5; RHR delta |d| >= 2 bpm; sleep shown if `< 360` or |pct| >= 10:
```dart
    if (missing.length == 3) return 'No recovery data for last night — using a neutral readiness.';
    final bits = <String>[];
    final hp = hrv.pctVsBaseline;
    if (hp != null && hp.abs() >= 5) {
      bits.add('HRV ${hp.abs().round()}% ${hp < 0 ? 'below' : 'above'} your baseline');
    }
    final rv = rhr.value, rb = rhr.baseline;
    if (rv != null && rb != null) {
      final d = rv - rb.mean;
      if (d.abs() >= 2) bits.add('resting HR ${d.abs().round()} bpm ${d > 0 ? 'above' : 'below'} baseline');
    }
    final sv = sleep.value;
    if (sv != null) {
      final sp = sleep.pctVsBaseline;
      if (sv < shortSleepMinutes || (sp != null && sp.abs() >= 10)) bits.add('${formatSleep(sv)} sleep');
    }
    String text;
    if (bits.isEmpty) {
      text = 'All recovery metrics close to your baseline';
    } else if (bits.length == 1) {
      text = _capitalise(bits.first);
    } else {
      text = '${_capitalise(bits.sublist(0, bits.length - 1).join(', '))} and ${bits.last}';
    }
    if (calibrating) text = 'Calibrating ($baselineDays/$calibrationDays days). $text';
    return text;
```
`pctVsBaseline = (v - b.mean) / b.mean * 100` (null if b.mean == 0) (line 60-64); `formatSleep(minutes)`: `final m = minutes.round(); return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';` (246-249). Note the RHR/pct branches use baseline even if `n < 3` (z null) - the reason can mention baseline-based deltas without z.

Training-load modifier (`readiness.dart:259-311`, also feeds Readiness card + coach + body map volume):
```dart
  static const double threshold = 1.5;

  Map<Muscle, double> ratios(DateTime today, Iterable<GroupSetEntry> entries) {
    final day = dateOnly(today);
    final recentStart = addDays(day, -6); // last 7 days including today
    final priorStart = addDays(day, -34); // 28 days before that
    ...
      if (d.isAfter(day)) continue;
      final Map<Muscle, int>? bucket =
          !d.isBefore(recentStart) ? recent : (!d.isBefore(priorStart) ? prior : null);
    ...
    for (final g in Muscle.values) {
      final avg = (prior[g] ?? 0) / 4;
      if (avg <= 0) continue;
      out[g] = (recent[g] ?? 0) / avg;
    }
    return out;
  }
  ...
  Set<Muscle> overloaded(DateTime today, Iterable<GroupSetEntry> entries) =>
      {for (final e in ratios(today, entries).entries) if (e.value > threshold) e.key};
```
`counts()` (292-307) returns for every Muscle `(recentSets, priorSets/4)` with same windows (`d.isBefore(priorStart)` excluded, `d.isAfter(day)` excluded). Entries (`lib/features/coach/data/coach_context.dart:158-163`): one per session exercise with working sets: `GroupSetEntry(date: s.startedAt, groups: e.targets.primary, sets: e.workingSets.length)`. Strict `>` 1.5 (exactly 1.5 is NOT overloaded; test). No prior history => muscle skipped (no modifier). `groupVolumeProvider` (app_providers.dart:~560-566) wraps `counts` for the body-graph volume heatmap.

Result flow: `ReadinessRepository.computeFor(day, rows)` (readiness_repository.dart:35-40): rows -> DayMetrics list; today = row matching `dayKey(day)` else empty `DayMetrics(date: dateOnly(day))`; `_calc.compute(today, allMetrics)`. `todayReadinessProvider` = computeFor(clock(), dailyMetrics rows) (app_providers.dart:143-147).
Session snapshot at workout start: `session_repository.dart:184-185`: `readinessScore: Value(r == null || r.calibrating ? null : r.score)`, `readinessBand: Value(r == null || r.calibrating ? null : r.band.name)` (so calibrating/unknown => null band, which quests/achievements treat as "not green").
Persisted per-day (`readiness_repository.dart:116-137` `recomputeScores`): for every stored day >= today - sinceDays: update `readinessScore` (nullable), `readinessBand` (`calibrating ? null : band.name`), `calibrating`, `explanation` (reason text).

#### 1.7 Daily metrics aggregation / Health sync (`lib/features/readiness/domain/metrics_aggregator.dart`, `data/readiness_repository.dart`)

Aggregation for day D (HealthKit samples -> per-day), `metrics_aggregator.dart:26-73`:
```dart
  static DateTime nightStart(DateTime day) => DateTime(day.year, day.month, day.day - 1, 18);
  static DateTime nightEnd(DateTime day) => DateTime(day.year, day.month, day.day, 12);

  DayMetrics aggregate({required DateTime day, required List<TimedValue> hrv, required List<TimedValue> restingHr, required List<TimeInterval> asleep}) {
    final d = dateOnly(day);
    final ns = nightStart(d), ne = nightEnd(d);

    final clipped = <TimeInterval>[];
    for (final i in asleep) {
      final s = i.start.isBefore(ns) ? ns : i.start;
      final e = i.end.isAfter(ne) ? ne : i.end;
      if (e.isAfter(s)) clipped.add(TimeInterval(s, e));
    }
    final merged = mergeIntervals(clipped);
    final sleepMinutes = merged.isEmpty
        ? null
        : merged.fold<int>(0, (sum, i) => sum + i.duration.inSeconds) / 60.0;

    List<TimedValue> hrvInWindow;
    if (merged.isNotEmpty) {
      final spanStart = merged.first.start, spanEnd = merged.last.end;
      hrvInWindow = hrv.where((v) => !v.from.isBefore(spanStart) && !v.from.isAfter(spanEnd)).toList();
    } else {
      final start = DateTime(d.year, d.month, d.day - 1, 12);
      hrvInWindow = hrv.where((v) => !v.from.isBefore(start) && v.from.isBefore(ne)).toList();
    }

    final rhrStart = DateTime(d.year, d.month, d.day - 1);
    final rhrInWindow = restingHr.where((v) => !v.from.isBefore(rhrStart) && v.from.isBefore(ne)).toList();

    return DayMetrics(date: d, hrvMs: _mean(hrvInWindow), restingHr: _mean(rhrInWindow), sleepMinutes: sleepMinutes);
  }
```
- Night window [D-1 18:00, D 12:00); sleep = union (merged, touching intervals merge: `!i.start.isAfter(last.end)`) of clipped asleep intervals, minutes = sum of seconds / 60 (float); null when none.
- HRV = plain mean of SDNN samples with `from` in [sleepSpanStart, sleepSpanEnd] (inclusive both ends; span is first merged start to last merged end, i.e. includes gaps between merged blocks); if no sleep, samples with `from` in [D-1 12:00, D 12:00).
- Resting HR = mean of samples with `from` in [D-1 00:00, D 12:00).
- `TimedValue(from, to, value)`, `TimeInterval(start, end)`.

Sync (`readiness_repository.dart:43-106`): defaults `days = 45`; `from = DateTime(today.year, today.month, today.day - days - 1, 12)`, `to = now`; parallel reads: hrvSdnn, restingHeartRate, activeEnergy, dietaryEnergy (errors -> []), dietaryProtein (errors -> []); then `asleepIntervals`. Per-day sums for energy/food/protein keyed by `dayKey(sample.to)` (sum). Loop `i = days .. 0`: aggregate for `addDays(today,-i)`, upsert `DailyMetricsCompanion` (insert w/ `onConflict: DoUpdate((_) => r)`) with `activeEnergyKcal/dietaryKcal/proteinG` (null if no entry) and `updatedAt: now`; then `recomputeScores(sinceDays: days, now)`; then body mass: stores `bodyMassHistory(now - 365 days, now)` entries (dedupe on source='health' && measuredAt equal) plus `latestBodyMass()` (errors swallowed via debugPrint). Returns `SyncResult(days: days+1, daysWithData, bodyMass)`. Triggers: app start/resume `_refreshHealth` (app.dart), manual refresh icon on the readiness card (`healthSyncProvider.sync()`, ignores re-entry while syncing; state holds `syncing,lastSync,lastResult,error`). Health source abstraction `HealthDataSource` in lib/core/health (other section).

#### 1.8 Muscle recovery (`lib/features/recovery/domain/recovery_config.dart`, `recovery.dart`)

All constants (`recovery_config.dart:6-57`, verbatim):
```dart
  static const Map<Effort, double> effortFactor = {
    Effort.failure: 1.0,
    Effort.oneLeft: 0.85,
    Effort.twoLeft: 0.7,
    Effort.threePlus: 0.5,
  };

  /// A set logged without effort (imported history) counts as failure: the lifter trains to failure.
  static const Effort unknownEffort = Effort.failure;

  /// Drop sets and myo-rep cycles: half a set each, whatever the effort. Static holds likewise.
  static const double dropFactor = 0.5;
  static const double myoFactor = 0.5;
  static const double holdFactor = 0.5;

  /// Recovery half-life in hours.
  static const double largeHalfLifeH = 48;
  static const double smallHalfLifeH = 30;

  static const Set<Muscle> large = {
    Muscle.quadriceps,
    Muscle.hamstrings,
    Muscle.glutes,
    Muscle.lats,
    Muscle.upperBack,
    Muscle.upperChest,
    Muscle.lowerChest,
  };

  static double halfLifeH(Muscle m) => large.contains(m) ? largeHalfLifeH : smallHalfLifeH;

  /// Today's readiness band → recovery speed (Green normal).
  static const Map<String, double> readinessSpeed = {'green': 1.0, 'yellow': 0.85, 'red': 0.7};

  static const double fullFatigue = 12;

  /// Bands, in recovery %.
  static const double readyAt = 90;
  static const double recoveringAt = 60;

  /// Sets older than this are ignored (their residual is negligible).
  static const Duration horizon = Duration(days: 14);

  /// A session "hit" a muscle when it gave it at least this much fatigue (for "last session").
  static const double hitThreshold = 0.5;
```
Effort mapping from stored RPE (`training.dart:146-151`):
```dart
  static Effort? fromRpe(double? rpe) {
    if (rpe == null) return null;
    if (rpe >= 9.75) return failure;
    if (rpe >= 8.75) return oneLeft;
    if (rpe >= 7.75) return twoLeft;
    return threePlus;
  }
```
Model (`recovery.dart:16-47`):
```dart
  static RecoveryBand of(double pct) => pct >= RecoveryConfig.readyAt
      ? ready
      : pct >= RecoveryConfig.recoveringAt
          ? recovering
          : fatigued;

double setFatigue(LoggedSet s) {
  if (!s.isWorking) return 0;
  if (s.isDrop) return RecoveryConfig.dropFactor;
  if (s.isMyo) return RecoveryConfig.myoFactor;
  if (s.isHold) return RecoveryConfig.holdFactor;
  final effort = Effort.fromRpe(s.rpe) ?? RecoveryConfig.unknownEffort;
  return RecoveryConfig.effortFactor[effort]!;
}

double decay(double fatigue, double hours, Muscle muscle, {double speed = 1}) {
  if (hours <= 0) return fatigue;
  return fatigue * math.pow(0.5, hours * speed / RecoveryConfig.halfLifeH(muscle)).toDouble();
}

/// 100 % = fully recovered.
double recoveryPct(double fatigue) => (100 * (1 - fatigue / RecoveryConfig.fullFatigue)).clamp(0, 100).toDouble();

double hoursUntilReady(double fatigue, Muscle muscle, {double speed = 1}) {
  final target = RecoveryConfig.fullFatigue * (1 - RecoveryConfig.readyAt / 100);
  if (fatigue <= target) return 0;
  return RecoveryConfig.halfLifeH(muscle) / speed * (math.log(fatigue / target) / math.ln2);
}
```
State computation (`recovery.dart:79-118`):
```dart
RecoveryState computeRecovery(TrainingHistory history, {required DateTime now, String? readinessBand}) {
  final speed = RecoveryConfig.readinessSpeed[readinessBand?.toLowerCase()] ?? 1.0;
  final fatigue = {for (final m in Muscle.values) m: 0.0};
  final last = <Muscle, (DateTime, String)>{};
  final from = now.subtract(RecoveryConfig.horizon);
  for (final s in history.sessions) {
    final at0 = s.endedAt ?? s.startedAt;
    if (at0.isBefore(from) || at0.isAfter(now)) continue;
    final perSession = <Muscle, double>{};
    for (final e in s.exercises) {
      for (final h in e.sets) {
        final f = setFatigue(h.set);
        if (f == 0) continue;
        final at = h.completedAt ?? at0;
        final hours = now.difference(at).inMinutes / 60;
        for (final w in e.targets.weights.entries) {
          final add = w.value * f;
          fatigue[w.key] = fatigue[w.key]! + decay(add, hours, w.key, speed: speed);
          perSession[w.key] = (perSession[w.key] ?? 0) + add;
        }
      }
    }
    for (final p in perSession.entries) {
      if (p.value < RecoveryConfig.hitThreshold) continue;
      final cur = last[p.key];
      if (cur == null || at0.isAfter(cur.$1)) last[p.key] = (at0, s.name);
    }
  }
  return RecoveryState({ for (final m in Muscle.values) m: MuscleRecovery(muscle: m, fatigue: fatigue[m]!, pct: recoveryPct(fatigue[m]!), hoursToReady: hoursUntilReady(fatigue[m]!, m, speed: speed), lastSession: last[m]?.$2, lastHitAt: last[m]?.$1) }, speed: speed);
}
```
Notes: fatigue contributes for ALL muscles in `targets.weights` (weights 0-1; secondary included), not only primary. `inMinutes / 60` truncates to whole minutes. Today's readiness band speeds up/slows the ENTIRE elapsed time (documented approximation). Provider: `recoveryProvider` (app_providers.dart:~574-579) passes `readinessBand: r == null || r.calibrating ? null : r.band.name` (null => speed 1.0). Same call at `coachContextBuilderProvider` (app_providers.dart:213). Recovery is display-only for UI, BUT `coach_context.dart:~138` uses `fatiguedPrimaries` for the coach "why" and docs say softening may apply - see OQ (docs: "Display only. Suggestions never read recovery" vs `DECISIONS.md:1281` and coach_context).

Heads-up (`recovery.dart:121-124`): primary muscles (weight >= 0.5) of planned exercises that are Fatigued: 
```dart
List<Muscle> fatiguedPrimaries(RecoveryState state, Iterable<MuscleTargets> exercises) {
  final primary = <Muscle>{for (final t in exercises) ...t.primary};
  return [for (final m in Muscle.values) if (primary.contains(m) && state.of(m).band == RecoveryBand.fatigued) m];
}
```
Muscle enum order (20; used for ordering of lists): biceps, triceps, forearms, quadriceps, hamstrings, glutes, calves, adductors, abductors, abdominals, obliques, frontDelt, middleDelt, rearDelt, upperChest, lowerChest, lats, upperBack, traps, lowerBack (lib/core/domain/muscles.dart). `halfLife 48h` set = quadriceps, hamstrings, glutes, lats, upperBack, upperChest, lowerChest; all others 30 h.
Test anchors (recovery_test.dart): 8 failure sets on lowerChest right now => Fatigued; 48 h after 8 sets => pct ~ `100*(1-4/12)`=66.7; decay(8,48,quads)=4.

---------------------------------------------------------------------------
### 2. SCREENS / WIDGETS

#### 2.1 FireStreak (`lib/features/gamification/presentation/fire_streak.dart`) - CUSTOM PAINTING + ANIMATION
Props: `from`, `to` (ints), `onDone`, `startDelay` (default 0), `height` (default 320; after-workout passes 220). `static const duration = Duration(milliseconds: 2800);`
Behaviour:
- Two controllers: `_show` (0->1 over 2800 ms, once; started immediately or after `startDelay` via Timer; `onDone` on completion) and `_loop` (1 s, repeating forever, drives sway/sparks).
- Haptic `heavyImpact` once when `_show.value >= 0.5` (the number swap moment).
- Reduce-motion (`reduceMotion(context)` from core/motion.dart; =MediaQuery/platform disable-animations): `_show.value = 1`, painter `time` fixed 0.3, shows `to` directly.
- Display: `shown = t < 0.5 ? from : to`; text `'$shown-day streak'` (AppType.displayL, color AppColors.warning, fontSize 34), scaled by `pop`; subtitle `'Today counts: workout finished'` (bodyS, textSecondary). Keys `streak-celebration`, `streak-celebration-count`.
- `flare = easeOutCubic((t/0.5).clamp(0,1))`; `pop = t < 0.5 ? 1.0 : 1 + 0.35 * (1 - ((t-0.5)/0.5).clamp(0,1)) * elasticOut(((t-0.5)/0.3).clamp(0,1))`.
- Painter `_FirePainter(time, flare)`: base y = `height*0.88`, flame height `h = height*(0.38 + 0.5*flare)`, width `w = h*0.62`; ground glow oval (radial gradient #FF7A18 alpha 0.45*flare -> transparent; width `w*2.2`, height `h*0.28`); five flame tongues (cubic Bezier teardrop, vertical linear gradient bottom->top, sway `sin(time*2π*1.3+phase)*fw*0.10` tip shift x1.8, wobble `sin(time*2π*2.1+phase*2)*fw*0.05`): `flame(0.78,-w*0.34,1.7,[E03A0A,FF8A1E])`, `flame(0.72,w*0.36,3.1,[E03A0A,FF9A2E])`, `flame(1.0,0,0,[FF4D0D,FF9D1F,FFC93C])`, `flame(0.66,0,2.2,[FFB02E,FFE27A])`, `flame(0.36,0,4.0,[FFF1B0,FFFFFF])`; 46 sparks (`_sparks = 46`), each seeded `math.Random(i*7919)` (speed 0.55+r*0.9, phase `(time*speed + r) % 1`, rise `h*(0.55+r*0.9)*(0.4+0.6*flare)`, x jitter + `sin(phase*7+i)*w*0.12`, alpha `(1-phase)*flare*0.95`, color lerp FFE27A->FF5A1A by phase, radius `(1.2 + r*2.6)*(1-phase*0.6)`). Painter time = `_loop.value + _show.value*3`. Repaint when time or flare change. RN: needs react-native-skia (or SVG + Reanimated); Dart comment says "drawn in code (no asset)". Exact code is in file lines 93-152 (read it directly when porting; not fully reproduced here).

#### 2.2 StreakWeek (`streak_week.dart`) - ANIMATION + haptic
Props `marks: Map<DateTime, StreakDayMark>`, `today`, `stamp: Animation<double>` (0->1). `static const double landsAt = 0.75;` Haptic `mediumImpact` when stamp passes 0.75 (once). Card (`AppCard`, key `streak-week`) with 7 columns Mon..Sun: letter (`M T W T F S S`), 34 px circle, day-of-month. Animation phases: `appear = easeOut((t/0.3).clamp(0,1))` (fade + 12 px slide-up), `drop = ((t-0.3)/(0.75-0.3)).clamp(0,1)`, `settle = ((t-0.75)/0.25).clamp(0,1)`. Today: hollow primary-colour ring (2 px); stamp = primary-filled circle with dumbbell icon (size 18, colour #06210F, glow shadow alpha 0.5 blur 10) falling from scale `1 + 1.6*(1-easeIn(drop)) + 0.18*(1-easeOut(settle))*(drop>=1?1:0)` with rotation `-0.35*(1-easeIn(drop))` rad, opacity=drop; after landing an expanding ring (`size*(1+0.9*settle)`, opacity `1-settle`). Other days: future = outline circle (AppColors.outline); `workout` mark = primary circle + dumbbell icon (size 17), key `streak-week-workout-<yyyy-MM-dd>`; `rest` mark = surfaceTop circle with `restDayColor`(#8FA3FF, game_ui.dart:194) alpha 0.5 border + moon icon (`Icons.bedtime_rounded`, size 16), key `streak-week-rest-<key>`; else plain surfaceTop circle. Reduce motion => t=1. Under the week: `StreakLegend` (core/widgets/game_ui.dart:258): "Workout" (dumbbell, primary) and "Rest day, streak kept" (moon, restDayColor). Icons: `workoutDayIcon = Icons.fitness_center_rounded`, `restDayIcon = Icons.bedtime_rounded` (game_ui.dart:192-193).

#### 2.3 StreakStepScreen (after-workout screen 3) (`lib/features/workout/presentation/after_workout_screens.dart:81-148`)
Route `Routes.streak`. Reads `lastSummaryProvider` (SessionSummary: `streakBefore`, `streakAfter`), `clockProvider`, `streakMarksProvider`. `_calendarShow = Duration(milliseconds: 1300)` drives `_stamp` (forward once on first build; reduce-motion sets value=1). Marks: `{...streakMarks, today: StreakDayMark.workout}` (forces today as workout even if history hasn't caught up). Layout: Skip button (top right -> Home), Spacer, title `'STREAK'` (displayL, letterSpacing 4, size 24), `StreakWeek`, `FireStreak(from: streakBefore, to: streakAfter, height: 220, startDelay: reduce ? 0 : 1300ms, onDone: -> _over=true)`, Spacer, `BigButton 'Continue'` (key `after-continue`, arrow icon) appearing only after `_over`, else 60 px spacer. If `lastSummaryProvider` is null the FireStreak is omitted (Continue never appears; Skip only).
Flow planner (`lib/features/workout/domain/after_workout.dart:1-17`):
```dart
enum AfterStep { congrats, rank, streak }

List<AfterStep> afterWorkoutSteps(SessionSummary s) => [
      AfterStep.congrats,
      if (s.rankGains.isNotEmpty || s.overallRankUp != null) AfterStep.rank,
      if (s.streakGrew) AfterStep.streak,
    ];

AfterStep? stepAfter(SessionSummary s, AfterStep step) {
  final steps = afterWorkoutSteps(s);
  final i = steps.indexOf(step);
  return i < 0 || i + 1 >= steps.length ? null : steps[i + 1];
}
```
Navigation (`after_workout_screens.dart:19-33`): `routeForStep` congrats -> `Routes.summary`, rank -> `Routes.rankSequence`, streak -> `Routes.streak`; `advanceAfterWorkout`: next null (or summary null) -> `context.go(Routes.home)`, else `context.pushReplacement(route)`. `AfterSkipButton` (key `after-skip`, text "Skip") -> `context.go(Routes.home)`. Also in the file (rank section owns details): `RankStepScreen` (shows `RankUpScreen` when `summary.overallRankUp != null` then `RankSequenceScreen(title: 'RANK PROGRESS', gains: [if (up == null) ...overall, ...lifts])`, onDone advances).

#### 2.4 ReadinessCard (`lib/features/readiness/presentation/readiness_card.dart`) - Home card
Reads: `todayReadinessProvider`, `healthSyncProvider`, `healthSourceProvider` (`.name`), `overloadedGroupsProvider`, `dailyMetricsProvider` + `clockProvider` (yesterday's `activeEnergyKcal`), `energyProvider.describe()` (nutrition line key `nutrition-line`). States:
1. `r == null` -> `Skeleton(height: 210)`.
2. `r.missing.length == 3` -> compact GameCard row: heart-outline icon, text `'Readiness: no recovery data from ${source.name}. Suggestions use a neutral readiness.'`, optional nutrition line, refresh IconButton (tooltip `'Refresh from Health'`, disabled while syncing).
3. Full card: `ProgressRing(value: (score ?? 60)/100, size 88, stroke 8)` with score text (`'—'` when null); colour `calibrating ? AppColors.accent : bandColor(band)`; label: calibrating `'Calibrating (${baselineDays}/14 days)'`, score null `'No data · neutral'`, else band label (Green/Yellow/Red); `READINESS` caption; `r.reason`; three `_Metric` columns HRV (`'${v.round()} ms'`), Resting HR (`'${v.round()} bpm'`), Sleep (`formatSleep`): value or `'missing'`, `'base <fmt(mean)>'` or `'no baseline'`; value colour by z: `z <= -0.5` red, `z >= 0.5` green, else primary text; calibrating note `'Suggestions treat today as Green until 14 days of baseline exist.'`; missing note (warning, info icon) `'Missing ${missing.join(' and ')} — readiness re-weighted over the other metrics.'`; overload note (trending-up icon) `'High load: <labels joined ', '> volume is above 1.5× your 4-week average. Readiness −10 for exercises training it/them.'`; footer `[source.name, 'synced HH:mm' (if lastSync), 'active energy yesterday N kcal' (if energy), 'sync failed' (if error)].join(' · ')` + refresh button with spinner while syncing. Band colours: `bandColor` (common.dart:89) green/yellow/red/textSecondary(null). `ProgressRing`, `GameCard`, `Skeleton` are shared widgets (core/widgets) - no custom painting in this file.

#### 2.5 RecoveryCard (`lib/features/recovery/presentation/recovery_card.dart`) - Home card
Reads `recoveryProvider` (null => nothing). Taps -> `context.go('${Routes.progress}?tab=body&mode=recovery')`. Content: heart-healing icon coloured red if any Fatigued else yellow if any Recovering else green; `MUSCLE RECOVERY` caption; if no muscle has `lastHitAt` (none trained in horizon): `'Everything is fresh: nothing trained in the last two weeks.'`; lines "Ready: ..." (only muscles with `lastHitAt != null` AND band ready), "Recovering: ..." and "Fatigued: ..." (ALL muscles in that band), each line label coloured by `recoveryColor(band)` (green/yellow/red, `AppColors.unranked` null), keys `recovery-ready|recovering|fatigued`. `muscleNames` merges both chest heads into "chest" when both present, otherwise lowercase labels in Muscle enum order, joined `', '`.
Heads-up banner in the logger (`active_workout_screen.dart:~1024-1050`, other section): one dismissable line when `fatiguedPrimaries` non-empty (key `fatigue-heads-up`, red tint alpha 0.1, border alpha 0.35, healing icon).

#### 2.6 Quest/achievement/XP/level UI
Not in this area's files (Home level chip `home_screen.dart:83`, Profile `profile_screen.dart:44-47`, summary screen, achievements screen). Providers feeding them: `levelProvider`, `totalXpProvider`, `questsProvider` (List<QuestProgress>), `achievementsProvider` (List<AchievementState(def, unlockedAt, progress)>).

---------------------------------------------------------------------------
### 3. DATA

#### 3.1 Tables (drift, `lib/core/db/tables.dart`)
```dart
class DailyMetrics extends Table {   // :177-193
  TextColumn get date => text()(); // yyyy-MM-dd   (PK)
  RealColumn get hrvMs => real().nullable()();
  RealColumn get restingHr => real().nullable()();
  RealColumn get sleepMinutes => real().nullable()();
  RealColumn get activeEnergyKcal => real().nullable()();
  RealColumn get dietaryKcal => real().nullable()();
  RealColumn get proteinG => real().nullable()();
  IntColumn get readinessScore => integer().nullable()();
  TextColumn get readinessBand => text().nullable()();
  BoolColumn get calibrating => boolean().withDefault(const Constant(true))();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();
}
class BodyWeights extends Table {    // :195-200
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get measuredAt => dateTime()();
  RealColumn get kg => real()();
  TextColumn get source => text()(); // health | manual
}
class XpEvents extends Table {       // :213-220
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get at => dateTime()();
  IntColumn get amount => integer()();
  TextColumn get reason => text()();            // 'session' | 'quest'
  IntColumn get sessionId => integer().nullable()();
  TextColumn get weekStart => text().nullable()(); // yyyy-MM-dd for weekly bonuses
}
class AchievementsUnlocked extends Table {  // :222-228  PK key
  TextColumn get key => text()();
  DateTimeColumn get unlockedAt => dateTime()();
}
class Quests extends Table {         // :230-237
  IntColumn get id => integer().autoIncrement()();
  TextColumn get weekStart => text()(); // yyyy-MM-dd (Monday)
  TextColumn get key => text()();
  TextColumn get params => text().withDefault(const Constant('{}'))();
  TextColumn get title => text()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}
class AppSettings extends Table {    // :239-245  key/value text; PK key
```
Also `Sessions.readinessScore (int?)`, `Sessions.readinessBand (text?, 'green'|'yellow'|'red'|null)`, `Sessions.xpEarned` (tables.dart:~86). drift DateTime columns are stored as unix seconds (drift default) - RN storage decision for the persistence section. Settings keys in this area: `streak_offset` (JSON), `streak_reminder` (`!= 'false'` => on), `_lostSeenKey` (home_screen), `liftoff_imported_at`.

#### 3.2 Entities (Dart classes)
- `DayStreak{days,longestDays,safety,carriedOver,lastWorkoutDay?,lastChanceDay?,runStart?,lostRunDays}`; `StreakOffset{date,days}`; `StreakDayMark{workout,rest}`.
- `XpRules`, `LevelInfo{level,xpIntoLevel,xpForNext,totalXp}`.
- `PrRecord{sessionId,exerciseId,name,e1rm,previous}`.
- `QuestDef{key,target,group?}` (+ id/title/toParams); `StoredQuest{row: Quest, def}`; `QuestProgress{quest,progress,done}`; `QuestWeek{sessions,sleepNights}`; `SessionActivity{date,exercises,durationMinutes?,readinessBand?,prCount}`; `ExerciseActivity{exerciseId,primaryRegions,repMax,sets,isNew}`; `QuestGenInput{weekStart,recentIds,exclude,hasSleepData,hasReadinessData}`.
- `AchievementDef{key,title,description,icon,type,threshold(double),category,family?,level?,param?}`; `AchievementStats` (15 fields, 3.1/1.5); `AchievementState{def,unlockedAt?,progress}`.
- `DayMetrics`, `Baseline{mean,sd,n}`, `MetricReading{value?,baseline?,z?}`, `ReadinessResult{date,score?,band,calibrating,baselineDays,hrv,restingHr,sleep,combinedZ?,reason,missing}`, `ReadinessBand{green,yellow,red}` with `fromName(name)`, `GroupSetEntry{date,groups,sets}`, `TimedValue`, `TimeInterval`, `SyncResult{days,daysWithData,bodyMass?}`.
- `RecoveryBand{ready,recovering,fatigued}`, `MuscleRecovery{muscle,fatigue,pct,hoursToReady,lastSession?,lastHitAt?}`, `RecoveryState{muscles,speed}` (`of(m)`, `inBand(b)`).

#### 3.3 Repository queries
GamificationRepository (`lib/features/gamification/data/gamification_repository.dart`):
- `watchTotalXp()/totalXp()`: `SELECT SUM(amount) FROM xp_events` (null -> 0).
- `addXp(at, amount, reason, sessionId?, week?)`: INSERT (skip when amount == 0); `weekStart` stored as `dayKey(week)`.
- `xpEvents()`: all rows ordered by `at` asc (unused).
- `watchUnlocked()/unlockedKeys()`: all `achievements_unlocked` rows (map key -> unlockedAt).
- `unlock(keys, at)`: batch INSERT OR IGNORE. `revoke(keys)`: DELETE WHERE key IN (...).
- `watchQuests(week)/quests(week)`: `SELECT * FROM quests WHERE week_start = dayKey(weekStart(week)) ORDER BY id ASC`; rows with unknown key skipped.
- `previousQuestIds(week)`: ids of `quests(addDays(weekStart(week), -7))`.
- `retireSuggestionQuests()`: `DELETE FROM quests WHERE key IN ('followAll','noOverride')`.
- `ensureQuests(week, generate)`: transaction (retire; read this week; if >= 3 return; insert missing).
- `completeQuest(id, at)`: `UPDATE quests SET completed_at = at WHERE id = ?`.
- `loadAchievementDefs()`: loads+caches (static) `assets/achievements.json` -> `raw['achievements']`.
- `sleepByDayRows(days)`: `{date: sleepMinutes}` for rows with non-null sleep.
ReadinessRepository: `watchDays()/allDays()`: all `daily_metrics` ordered by date asc; sync/recompute as in 1.7. BodyWeightRepository: `watchAll/all` (asc by measuredAt), `watchLatest/latest` (ORDER BY measuredAt DESC, id DESC LIMIT 1), `addManual(kg, at?)` (source 'manual').

#### 3.4 assets/achievements.json schema
Top-level `{ "schema_version": 2, "description": "<long text>", "achievements": [ ... ] }`. Each item: `key` (string, unique, stable id), `title`, `description`, `icon` (string; default 'star'), `type` (one of the 16 AchievementType names: sessions, streakDays, prs, totalVolumeKg, totalSets, maxSessionVolumeKg, level, bestExerciseTier, overallTier, musclesAtTier, regionsAtTier, musclesRanked, distinctExercises, greenSessions, sleepStreak, fullProgramWeeks), `threshold` (number), `category` (consistency|strength|volume|exploration|recovery|program), optional `family` (string) + `level` (bronze|silver|gold), optional `param` (int; tier index for musclesAtTier/regionsAtTier). Example: `{"key":"muscles_gold_5","title":"Golden Five","description":"Get 5 muscles to Gold or better.","icon":"target","type":"musclesAtTier","threshold":5,"category":"strength","family":"Strong muscles","level":"silver","param":3}`.

---------------------------------------------------------------------------
### 4. OPEN QUESTIONS

- OQ: docs/DECISIONS.md:1400-1403 says `streak_4` (28 days) and `streak_12` (84 days) were the adapted keys; assets/achievements.json (code) has `streak_14`, `streak_30`, `streak_100` and no `streak_4/streak_12`. A later migration (ladder_migration.dart, not read) presumably retired them; which keys exist in a real DB is unknown.
- OQ: docs/DECISIONS.md:1523 says the Finish flame is "1.5 s, `StreakCelebration`"; code is `FireStreak` with `duration = Duration(milliseconds: 2800)` plus a 1300 ms calendar stamp phase. Code used here.
- OQ: DECISIONS.md:1819 says best-lift achievements go "Silver ... Radiant (7)" and README mentions tier index 0-9; code/JSON stop at Immortal=8 (Radiant removed, DECISIONS.md:2112-2124). Code wins.
- OQ: docs/DECISIONS.md:1106 and README say recovery is "Display only: suggestions never use it" but DECISIONS.md:1281 says "a Fatigued prime mover may soften by one step" and `lib/features/coach/data/coach_context.dart:138` uses `fatiguedPrimaries`; `coachContextBuilderProvider` passes `recovery:` into CoachContext (app_providers.dart:213). The suggestion engine is in another section; UI heads-up and coach differ in whether recovery matters. Also DECISIONS.md:1340-1356 ("never remove sets").
- OQ: `streakWorkoutStarts` counts sessions with >= 1 working set where working = completed && !warmup; drop/myo/hold sets count as working for this filter. Whether a session consisting ONLY of drop sets should count is not specified.
- OQ: `sessionsThisWeek` (streaks.dart:227) counts all finished sessions incl. empty ones, while the streak filters out empty ones; Profile may show a count that includes sessions that do not count for the streak.
- OQ: Volume definitions disagree: `HistSession.volume` (history.dart:88) = `weight * reps` for every working set including holds (reps = seconds, so holds add fake volume) and is used for `totalVolumeKg`/`maxSessionVolumeKg` achievements and Congrats; `SessionActivity.volume` (quests.dart:162) uses `tonnage` (holds = 0) for the volume quest.
- OQ: Quest "done" is `completedAt != null || progress >= target` in the UI (app_providers.dart), but XP/`completedAt` are only written at `FinishService.finish`; a quest met by a later edit/import never earns the 40 XP, and progress can fall back below target (e.g., session deleted) while `completedAt` stays set. Not specified.
- OQ: At finish, the quest week is `weekStart(session.startedAt)`; the live provider uses the week of `clock()`. A workout started Sunday night and finished after Monday 00:00 awards quest XP for the previous week's quests (generated rows for that older week must already exist). Behaviour for missing rows = no quest checked.
- OQ: `QuestEngine.generate` uses Dart's `math.Random(seed)` + `List.shuffle`; results for a given Monday are only reproducible with Dart's exact PRNG. Tests check properties, not specific picks. RN port will produce different (but equally valid) weekly picks; already-stored weeks stay in the DB.
- OQ: `isNew` for quests (`weekActivity`) = first session in `history.sessions` iteration order in which the exercise has a working set; correct only if `history.sessions` is sorted chronologically ascending (also relied on by `findPrs`). Sort order is defined in history_repository.dart (other section); not verified here.
- OQ: `findPrs` uses the CURRENT bodyweight for all bodyweight-loaded lifts (not per-day), unlike ranks which use per-day weight (DECISIONS.md:414). Intentional? Not documented.
- OQ: `sleepNights` threshold literal `420` is duplicated in app_providers.dart, finish_service.dart and `longestSleepStreak(minMinutes: 420)`; the sleep day key is the DailyMetric `date` (wake-up day), and the quest week counts Mon-Sun of that key.
- OQ: When the Readiness baseline for a metric has `n < 3` but baseline exists, `_reason` still describes HRV%/RHR delta/sleep% vs that thin baseline, and the card shows `base X` while z is null (colour primary). Edge not documented.
- OQ: `ReadinessCalculator.compute` returns band Green while calibrating but also stores `readinessBand = null` for the day and for sessions; `recoveryProvider` treats calibrating as normal speed. `ReadinessBand.fromName(null)` -> null. Quests/achievements `greenDay`/`greenSessions` therefore never count sessions started while calibrating.
- OQ: `scoreFromZ` -> `reason`/band use `score ?? neutralScore (60)` when no data (Green) but `ReadinessResult.score` is null; UI shows `'—'`.
- OQ: DECISIONS.md:1099 says "calibrating or no Health data = Green" for recovery speed; code maps unknown/null band to speed 1.0 which is the same as Green.
- OQ: `RecoveryState.names` (recovery.dart:74) duplicates `muscleNames` (recovery_card.dart:14) but only the latter merges chest heads; the former appears unused (dead).
- OQ: Dead/unused code found in this area: `sessionsPerWeekLast4` (quests.dart:267), `rpeLoggedPct` and `regionSetsLast4Weeks` (stats.dart:120,127), `GamificationRepository.xpEvents()` (:58), `DayStreak.daysOnLastChance`/`carriedOver`/`lostRunDays`/`runStart` (only used by tests or not at all in UI), `ReadinessRepository` trailing empty lines. DECISIONS.md:1406 says an adapted "no overrides" quest used sessionsPerWeekLast4; that quest no longer exists.
- OQ: Recovery decay uses `inMinutes / 60` (truncating) and `at0.isAfter(now)` skips sessions in the future; sets whose `completedAt` is after `now` get `hours <= 0` => undecayed. Imported sessions have completedAt interpolated across the duration (liftoff_import_service). Fine but note for tests with fake clocks.
- OQ: Streak offset edit sets `date = offset?.date ?? now` so editing days later keeps the OLD date; the Settings message says "Your streak in days on <date>". Whether the date should be re-anchored to today is not stated.
- OQ: `_lostSeenKey` constant value (home_screen.dart) and the remaining Home streak card details (lines 322-343) were only partially read; the Home screen belongs to another section.
- OQ: Streak reminder is scheduled via `DateTime.now()` check inside `scheduleStreakReminder` but plan uses the injectable clock; with a faked clock in tests these can disagree (production unaffected).

---

# Appendix C. Coach, suggestion engine and training rules

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `C §n`).

## Section C: Coach / suggestion logic and training domain rules

All paths are relative to `/Users/hassan/IdeaProjects/spotter-app`. Code wins over docs; disagreements are listed as `OQ:` in part 3.
Readiness thresholds (`readiness.dart`) and recovery (`recovery.dart`) are outside this area but the engine depends on them; the few constants needed are quoted (marked "outside area").

---------------------------------------------------------------------
## 0. Big picture (how the pieces connect)

1. `CoachContext.suggest(info, range, targetSets, targetRir)` builds a `SuggestionInput` and calls `SuggestionEngine.suggest`. (`lib/features/coach/data/coach_context.dart:121-142`)
2. The engine does **double progression on a weight grid** (only loads that physically exist), then applies readiness / recovery as "repeat, never lower", adds Nutrition text only, snaps to grid, and attaches a visible "why" chain.
3. **The engine never lowers the weight by itself.** The only ways down: ego freeze, calibration/seeded re-anchor, max-load cap, weight not on grid. Each states a reason in `downNote`.
4. Readiness bands Green/Yellow/Red behave **identically** inside the engine except for text/headline: any non-Green band (or any Fatigued prime mover) means "Repeat last session". See 1.4.
5. Ego guardrail runs at workout finish (`finish_service.dart`), not in the engine; it creates a 7-day freeze row that the engine reads.

---------------------------------------------------------------------
## 1. BUSINESS LOGIC

### 1.1 Primitive constants and formulas (`lib/core/domain/training.dart`)

`lib/core/domain/training.dart:4-15`
```dart
/// RPE assumed when the lifter didn't log one.
const double defaultRpe = 9.0;

/// RPE at or above which an override set counts as an ego set.
const double egoRpeThreshold = 9.5;

/// Estimated 1RM: Epley on effective reps, `weight × (1 + (reps + RIR) / 30)` with RIR = 10 − RPE.
double estimateOneRm(double weight, int reps, double? rpe) {
  if (reps <= 0 || weight <= 0) return 0;
  final rir = 10 - (rpe ?? defaultRpe);
  return weight * (1 + (reps + rir) / 30);
}
```
Note: `egoRpeThreshold` is declared but I found no use in the files I read (OQ-12). e1RM is 0 when weight <= 0 (so bodyweight-only/assisted sets contribute 0 unless bodyweight is added by `LoggedSet.e1rm(bodyweight:)`).

`lib/core/domain/training.dart:17-33` default rep ranges
```dart
class RepRange {
  const RepRange(this.min, this.max) : assert(min <= max);
  final int min;
  final int max;

  static const compound = RepRange(6, 10);
  static const isolation = RepRange(10, 15);

  @override
  String toString() => min == max ? '$min' : '$min–$max';
```
(`toString` uses an en dash; it is embedded in the "why" strings, e.g. "6–8".)

#### Effort selector (stored as RPE, shown as F / 1 / 2 / 3+)
`lib/core/domain/training.dart:124-153`
```dart
enum Effort {
  failure('F', 10),
  oneLeft('1', 9),
  twoLeft('2', 8),
  threePlus('3+', 7);

  const Effort(this.label, this.rpe);
  final String label;
  final double rpe;

  Effort get next => values[(index + 1) % values.length];

  /// From a prescribed RIR (0 = failure).
  static Effort fromRir(int? rir) => switch (rir) {
        null => twoLeft,
        <= 0 => failure,
        1 => oneLeft,
        2 => twoLeft,
        _ => threePlus,
      };

  static Effort? fromRpe(double? rpe) {
    if (rpe == null) return null;
    if (rpe >= 9.75) return failure;
    if (rpe >= 8.75) return oneLeft;
    if (rpe >= 7.75) return twoLeft;
    return threePlus;
  }
}
```
Tap cycles F -> 1 -> 2 -> 3+ -> F (`next`). Default effort = from prescribed RIR (null RIR -> "2").

#### Suggestion kind (how coach framed a session)
`lib/core/domain/training.dart:155-175`
```dart
enum SuggestionKind {
  calibration,
  seeded,
  increase,
  addReps,
  reduce,
  plateauDeload,
  egoFreeze,
  none;

  /// Sessions where the load was deliberately reduced (used by the "Comeback" achievement).
  bool get isDeload => this == reduce || this == plateauDeload || this == egoFreeze;
```
Stored by `.name`; `fromName` falls back to `none`. `reduce` and `plateauDeload` are never produced by the current engine (OQ-1).

### 1.2 LoggedSet, ExerciseSessionLog (what counts as a working set)

`lib/core/domain/training.dart:35-115`
```dart
class LoggedSet {
  const LoggedSet({
    required this.weight,
    required this.reps,
    this.rpe,
    this.isWarmup = false,
    this.isOverride = false,
    this.suggestedWeight,
    this.completed = true,
    this.isDrop = false,
    this.isMyo = false,
    this.isHold = false,
    this.partials = false,
    this.targetMin,
    this.targetMax,
    this.targetRir,
  });
  ...
  /// Drop, myo or hold: a technique follow-up, never a working set for e1RM, ranks, PRs or progression.
  bool get isFollowUp => isDrop || isMyo || isHold;

  /// weight × reps (0 for a static hold).
  double get tonnage => isHold ? 0 : weight * reps;
  ...
  /// Completed, not a warm-up (drop sets included: they count for volume).
  bool get isWorking => !isWarmup && completed;

  double get effectiveRpe => rpe ?? defaultRpe;

  bool get belowRange => targetMin != null && reps < targetMin!;

  /// Ego lifting (section 7): load above the suggestion *and* reps below the bottom of the range,
  /// i.e. it was too heavy. Going to failure inside the range is never ego lifting.
  bool get isEgoSet => isOverride && belowRange;

  /// A good override: heavier than the suggestion (more than 5 %) and still inside the rep range (or above it) at the
  /// prescribed effort. It counts as disciplined, progression accepts the weight, and it is never an ego flag.
  bool get isGoodOverride =>
      isOverride && isWorking && !isFollowUp && targetMin != null && !belowRange && (rpe == null || targetRir == null || rpe! <= 10 - targetRir! + 1e-9);

  /// Valid for ranks and PRs: a completed working set that isn't a drop set or an ego set.
  bool get isValidForRecords => isWorking && !isFollowUp && !isEgoSet;

  /// e1RM including [bodyweight] for bodyweight-loaded lifts.
  double e1rm({double bodyweight = 0}) => estimateOneRm(weight + bodyweight, reps, rpe);

  /// Discipline: load within ±5 % of the suggestion and reps inside the prescribed range, or a good override.
  bool get isDisciplined => followedSuggestion || isGoodOverride;

  /// Within ±5 % of the suggestion and reps inside the prescribed range.
  bool get followedSuggestion =>
      followsSuggestion(weight, suggestedWeight) && !belowRange && (targetMax == null || reps <= targetMax!);
}

/// ±5 % tolerance. A suggestion of 0 kg (bodyweight) is followed only by 0 kg.
bool followsSuggestion(double weight, double? suggested) {
  if (suggested == null) return false;
  if (suggested <= 0) return weight <= 0;
  return (weight - suggested).abs() <= suggested * 0.05 + 1e-9;
}
```
`lib/core/domain/training.dart:177-229` (per-exercise-per-session log)
```dart
  /// Working sets for progression and e1RM: completed, not warm-ups, not drop sets.
  List<LoggedSet> get workingSets => sets.where((s) => s.isWorking && !s.isFollowUp).toList();

  bool get hasWorkingSets => sets.any((s) => s.isWorking && !s.isFollowUp);
  ...
  double get topWeight {
    final w = workingSets;
    if (w.isEmpty) return 0;
    return w.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
  }

  List<LoggedSet> get topSets => workingSets.where((s) => s.weight == topWeight).toList();

  double bestE1rm({double bodyweight = 0, bool validOnly = false}) {
  ...
  bool get hasOverrides => workingSets.any((s) => s.isOverride);

  /// Overrides that were not good ones (reps fell below the range, or beyond the prescribed effort).
  bool get hasBadOverrides => workingSets.any((s) => s.isOverride && !s.isGoodOverride);

  bool get hasEgoOverrides => workingSets.any((s) => s.isEgoSet);

  /// Drop sets and myo cycles included; static holds add none.
  double get volume => sets.where((s) => s.isWorking).fold<double>(0, (v, s) => v + s.tonnage);
```
Notes: `topWeight` is the max (for assisted lifts, negative values: -20 > -25, so "heavier" = less assistance). `topSets` compares with exact `==` on doubles. `volume` includes drop and myo, excludes holds (tonnage 0), excludes warm-ups. `HistSession.volume` (history.dart:88) is `weight * reps` over `workingSets` of `HistExercise` = `isWorking` only (no follow-up filter; holds would add weight*seconds there) (OQ-13).

### 1.3 Inputs to the engine

`lib/features/coach/domain/suggestion_engine.dart:56-113`
```dart
class SuggestionInput {
  const SuggestionInput({
    required this.range,
    required this.targetSets,
    required this.targetRir,
    required this.increment,
    required this.equipment,
    required this.history,
    required this.readiness,
    required this.now,
    this.freeze,
    this.bodyweight = 0,
    this.assisted = false,
    this.rangeMatched = true,
    this.grid,
    this.compound = false,
    this.fatigued = const [],
    this.energy = EnergyContext.none,
    this.formReset,
  });
  ...
  /// Finished sessions of this exercise, oldest first.
  final List<ExerciseSessionLog> history;
  ...
  /// False when none of [history] was done at [range] (e.g. imported 10–12 work for a 4–6 slot):
  /// the load is then re-anchored from the best e1RM of the last 3 sessions.
  final bool rangeMatched;
  /// Compound lifts may drop one step on a Red day; isolations never go below last session.
  final bool compound;
```
How CoachContext fills them (`coach_context.dart:121-142`):
```dart
  Suggestion suggest(ExerciseInfo info, RepRange range, int targetSets, int targetRir) => _engine.suggest(SuggestionInput(
        range: range,
        targetSets: targetSets,
        targetRir: targetRir,
        increment: increments.of(info.equipmentKind),
        equipment: info.equipmentKind,
        history: history.logsForRange(info.id, range),
        readiness: exerciseReadiness(readiness, overloaded, info.targets),
        now: now,
        freeze: freezeFor(info.id),
        bodyweight: bodyweightLoaded.contains(info.id) ? bodyweight : 0,
        assisted: isAssisted(info.id),
        rangeMatched: history.logsFor(info.id).isEmpty || history.hasLogsAtRange(info.id, range),
        grid: gridFor(info),
        compound: info.isCompound,
        fatigued: [
          if (recovery != null)
            for (final m in fatiguedPrimaries(recovery!, [info.targets])) m.label,
        ],
        energy: energy,
        formReset: formResets[info.id],
      ));
```
`history.logsForRange` (`lib/core/domain/history.dart:120-140`): sessions restricted to sets whose own `targetRange ?? exercise.range == range`; sessions with no working set at that range are skipped; falls back to all logs if empty.
```dart
        final sets = [for (final h in e.sets) if ((h.targetRange ?? e.range) == range) h.set];
        if (!sets.any((x) => x.isWorking)) continue;
   ...
    return out.isEmpty ? logsFor(exerciseId) : out;
```
`logsFor` / `_byExercise` are built per session in chronological (startedAt) order: `ExerciseSessionLog.date = session.startedAt` (`history.dart:97-110`). `bodyweightLoaded` and `bodyweight` come from the coach context (latest bodyweight from Health); `bodyweight` only when exercise is bodyweight-loaded. Assisted ids: `lib/features/library/domain/load_kinds.dart:5-10`:
```dart
const Set<String> assistedExerciseIds = {'sp_assisted_pull_up_machine', 'sp_assisted_dip_machine', 'Band_Assisted_Pull-Up'};

/// Bodyweight exercises whose dataset equipment isn't "body only" (logged as optional added load).
const Set<String> extraBodyweightExerciseIds = {...assistedExerciseIds, 'Hyperextensions_Back_Extensions'};

bool isAssisted(String exerciseId) => assistedExerciseIds.contains(exerciseId);
```
Per-exercise readiness (`coach_context.dart:46-53`):
```dart
ExerciseReadiness exerciseReadiness(ReadinessResult? today, Set<Muscle> overloaded, MuscleTargets targets) {
  final score = today?.coachScore ?? ReadinessCalculator.neutralScore;
  final groups = [
    for (final g in targets.primary)
      if (overloaded.contains(g)) g.label,
  ];
  return ExerciseReadiness(score: score, calibrating: today?.calibrating ?? false, loadPenaltyGroups: groups);
}
```
`ExerciseReadiness` (`suggestion_engine.dart:26-46`):
```dart
  int get adjustedScore =>
      loadPenaltyGroups.isEmpty ? score : score - ReadinessCalculator.loadPenalty;

  ReadinessBand get band => ReadinessCalculator.bandFor(adjustedScore);
```
Outside area (`lib/features/readiness/domain/readiness.dart:117-129`, `:99`):
```dart
  static const int greenMin = 55;
  static const int yellowMin = 40;
  static const int neutralScore = 60;

  /// Readiness penalty for an exercise whose muscle group is over its usual weekly load.
  static const int loadPenalty = 10;

  static ReadinessBand bandFor(int score) {
    if (score >= greenMin) return ReadinessBand.green;
    if (score >= yellowMin) return ReadinessBand.yellow;
    return ReadinessBand.red;
  }
  ...
  int get coachScore => (calibrating || score == null) ? ReadinessCalculator.neutralScore : score!;
```
So: Green >= 55, Yellow 40-54, Red < 40; calibrating or no Health data = 60 (Green); training-load penalty -10 (from any primary muscle group whose 7-day volume > 1.5x 28-day average; `readiness.dart:259-264`, threshold `1.5`, strict `>` per DECISIONS "Training-load modifier counts primary groups only") makes a neutral 60 into 50 = Yellow.

### 1.4 The engine, step by step (`lib/features/coach/domain/suggestion_engine.dart`)

#### Constants
`suggestion_engine.dart:182-197`
```dart
class SuggestionEngine {
  const SuggestionEngine();

  static const double failureReduction = 0.05;
  static const double freezeReduction = 0.05;
  static const double calibrationStopRpe = 8;

  /// A jump to the next available weight bigger than this (relative) waits for extended reps.
  static const double bigJump = 0.10;

  /// Extended rep target before a big jump: top of the range + 2 (aim up to + 3).
  static const int extendBy = 2;
  static const int extendMax = 3;

  /// Sessions in a row below the range, at the same weight, before a lighter weight is offered (never applied).
  static const int lighterOptionAfter = 3;
```

#### Step 0: history selection, calibration entry, technique days
`suggestion_engine.dart:199-212`
```dart
  Suggestion suggest(SuggestionInput input) {
    final grid = input.grid ?? _plainGrid(input);
    var all = input.history.where((l) => l.hasWorkingSets).toList();
    final reset = input.formReset;
    if (reset != null) all = [for (final l in all) if (!dateOnlyOf(l.date).isBefore(dateOnlyOf(reset.at))) l];
    if (all.isEmpty && reset == null) return _calibration(input, grid);

    // Readiness is applied after progression, so a small-deload day (load cut for recovery,
    // not performance) is not the progression base. Use the last normal session instead.
    final normal = all.where((l) => !l.techniqueDay).toList();
    final logs = normal.isEmpty ? all : normal;
```
- Only sessions with at least one completed non-warm-up non-follow-up set count.
- Form reset drops sessions whose date (date-only) is before the reset date.
- No history and no reset -> calibration (1.5).
- `techniqueDay` sessions excluded from progression base unless nothing else exists. (The engine itself never sets `techniqueDay: true` on its output; see OQ-2.)

#### Step 1: base weight, reps, kind
Case A: form reset with nothing logged since (`:225-232`)
```dart
    if (logs.isEmpty) {
      // Form reset with nothing logged since: start from the reset weight.
      lastTop = reset!.weight;
      weight = reset.weight;
      reps = range.min;
      kind = SuggestionKind.seeded;
      why.add('Base: form reset on ${_d(reset.at)} at ${_loadText(reset.weight)}; nothing logged since.');
      why.add('Rule: progression restarts from the reset weight at ${range.min} reps.');
```
Case B: last session was a calibration, OR no history at this rep range -> re-anchor from best e1RM of last 3 sessions (`:234-253`)
```dart
      final last = logs.last;
      lastTop = last.topWeight;
      ...
      if (last.suggestionKind == SuggestionKind.calibration || !input.rangeMatched) {
        final recent = logs.sublist(math.max(0, logs.length - 3));
        final best = recent.map((l) => _bestSet(l, input.bodyweight)).reduce(
            (a, b) => b.e1rm(bodyweight: input.bodyweight) > a.e1rm(bodyweight: input.bodyweight) ? b : a);
        final e1rm = best.e1rm(bodyweight: input.bodyweight);
        weight = e1rm / (1 + (range.min + input.targetRir) / 30) - input.bodyweight;
        reps = range.min;
        kind = SuggestionKind.seeded;
        ...
        decreaseWhy = last.suggestionKind == SuggestionKind.calibration
            ? 'your calibration sets set the starting load for $range'
            : 'you have no recent sets at $range, so it starts from your best estimated max';
```
Formula: `weight = e1RM / (1 + (range.min + targetRir)/30) - bodyweight`, target reps = `range.min`. Weight is then snapped DOWN to grid (step 5). Example from test: 62.5x12 @RPE10 -> e1RM 87.5 -> 69.08 -> 67.5 (`test/domain/suggestion_engine_test.dart:124-135`). `_bestSet` picks highest e1RM among `log.workingSets` of each session.

Case C: normal progression (`:254-316`)
```dart
        final working = last.workingSets;
        // Effort is judged against the prescription: going to failure is never a failed set, only
        // missing the bottom of the range is. The top only counts at the prescribed effort.
        final maxRpe = 10.0 - input.targetRir;
        final failed = working.any((s) => s.reps < range.min);
        final allTop = working.every((s) => s.reps >= range.max && s.effectiveRpe <= maxRpe);
        final minTopReps = last.topSets.map((s) => s.reps).reduce(math.min);
```
Notes: `maxRpe = 10 - targetRir`; missing RPE counts as 9 (`defaultRpe`), so with targetRir=2 (maxRpe 8) unlogged RPE never counts as "top at prescribed effort" (test `suggestion_engine_test.dart:76-80`). With targetRir=0, maxRpe=10 so anything counts. Evaluation uses only the LAST normal session `logs.last`.

C1. Failed (any working set below range.min) (`:263-278`)
```dart
        if (failed) {
          // Missing reps never lowers the weight by itself: hold it and try again. A lighter weight is only offered
          // (as an optional choice, never applied) after three sessions in a row below the range at this weight.
          kind = SuggestionKind.addReps;
          weight = lastTop;
          reps = range.min;
          why.add('Rule: a working set fell below $range → hold ${_loadText(lastTop)} and try again for ${range.min} reps '
              '(the weight only goes down if you choose it).');
          if (_belowRangeStreak(logs, range) >= lighterOptionAfter) {
            lighter = _reduced(input, grid, lastTop, failureReduction);
            if (lighter >= lastTop - 0.01) lighter = null;
            if (lighter != null) {
              why.add('Option: three sessions in a row below $range at ${_loadText(lastTop)} → a lighter option, ${_loadText(lighter)}, '
                  'is offered. It is never applied for you.');
            }
          }
```
`_belowRangeStreak` (`:427-437`): counts sessions backwards from last with same top weight (+-0.01) that each contained a working set below range.min; breaks at first non-matching session.
```dart
    final w = logs.last.topWeight;
    var n = 0;
    for (var i = logs.length - 1; i >= 0; i--) {
      final l = logs[i];
      if ((l.topWeight - w).abs() > 0.01 || !l.workingSets.any((s) => s.reps < range.min)) break;
      n++;
    }
```
`_reduced` (`:485-492`): the lighter option = `grid.snapDown((lastTop + bw) * (1 - 0.05) - bw)`; if not at least one step lighter, use `grid.previous(lastTop)`; floored at `_minLoad`.
```dart
    var w = grid.snapDown((lastTop + bw) * (1 - fraction) - bw);
    if (w >= lastTop - 0.01) w = grid.previous(lastTop) ?? lastTop;
    return math.max(w, _minLoad(input));
```
`lighterOption` is only exposed on the Suggestion; the UI shows a "Lighter option: X kg" chip and applies only on tap (session_repository / UI, outside area; DECISIONS item 5).

C2. All sets at top at prescribed effort (`:279-307`)
```dart
        } else if (allTop) {
          final next = grid.next(lastTop);
          final jump = grid.nextJump(lastTop, bodyweight: input.bodyweight);
          final target = range.max + extendBy;
          if (next == null && grid.atMax(lastTop)) {
            // The machine's max load: reps keep progressing past the range, with no cap.
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = minTopReps + 1;
            why.add('Rule: top of $range at the max load (${_loadText(lastTop)}) → same weight, aim for $reps reps. $maxReachedMessage.');
          } else if (next == null) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = math.min(range.max + extendMax, minTopReps + 1);
            why.add('Rule: top of $range, but ${_loadText(lastTop)} is the heaviest you have → keep it and add reps.');
          } else if (jump != null && jump > bigJump && minTopReps < target) {
            kind = SuggestionKind.addReps;
            weight = lastTop;
            reps = math.min(range.max + extendMax, math.max(range.max + 1, minTopReps + 1));
            why.add('Rule: top of $range, but the next weight (${_loadText(next)}) is +${(jump * 100).round()} % '
                '→ extend to $target–${range.max + extendMax} reps at ${_loadText(lastTop)} before jumping.');
          } else {
            kind = SuggestionKind.increase;
            weight = next;
            reps = range.min;
            why.add('Rule: all working sets hit the top of $range at the prescribed effort '
                '(${input.targetRir == 0 ? 'failure' : 'RPE ≤ ${formatRpe(maxRpe)}'})${jump != null && jump > bigJump ? ' and the extended reps' : ''} '
                '→ next available weight ${_loadText(next)}, reps reset to ${range.min}.');
          }
```
Big-jump relative size uses effective load (`WeightGrid.nextJump`, gym.dart:297-304): `(next - w) / max(1.0, w + bodyweight)`. Example: 7.5->10 kg dumbbell = +33% -> extend to top+2..top+3 reps first (`suggestion_rework_test.dart:198-206`).

C3. Otherwise (within range, or top reached at too-high effort) (`:308-315`)
```dart
        } else {
          kind = SuggestionKind.addReps;
          weight = lastTop;
          reps = math.min(range.max, minTopReps + 1);
          why.add(minTopReps >= range.max
              ? 'Rule: top of $range reached but past the prescribed effort → same weight, own the reps.'
              : 'Rule: within $range → same weight, beat last time\'s reps on at least one set.');
        }
```

#### Step 1b: Form-reset hint (not applied, only offered)
`:317-325`
```dart
        // A deliberate step down at the top of the range looks like a form reset.
        final previous = logs.length > 1 ? logs.sublist(math.max(0, logs.length - 4), logs.length - 1) : const <ExerciseSessionLog>[];
        final prevBest = previous.isEmpty ? null : previous.map((l) => l.topWeight).reduce(math.max);
        final hitTop = last.topSets.any((s) => s.reps >= range.max);
        if (prevBest != null && grid.previous(prevBest) != null && lastTop <= grid.previous(prevBest)! + 0.01 && hitTop && !last.techniqueDay) {
          resetHint = lastTop;
```
Rule: the best top weight of up to the 3 sessions before last; if last session's top weight is at least one grid step below that AND some top set reached range.max reps -> `formResetHint = lastTop`. The user can apply "Form reset" (`GymRepository.setFormReset`, 1.11), which is stored per exercise in `form_resets` and restarts progression (Step 0 filter).

#### Step 2: set count never changes
`:329-335`
```dart
    // The routine's set count is never changed by any coaching input.
    final sets = input.targetSets;
    // "Repeat" means last session's top weight for its best reps at that weight, kept inside the range
    // (up to the extended target) so a short session never becomes today's goal.
    final repeatReps = logs.isEmpty
        ? range.min
        : logs.last.topSets.map((s) => s.reps).reduce(math.max).clamp(range.min, range.max + extendMax).toInt();
```

#### Step 3: Ego freeze overrides progression
`:337-347`
```dart
    final freeze = input.freeze;
    if (freeze != null && freeze.isActive(input.now)) {
      final frozen = grid.snapDown((freeze.baseWeight + input.bodyweight) * (1 - freezeReduction) - input.bodyweight);
      if (frozen < weight - 0.01) decreaseWhy = 'ego flag: progression is frozen ${freeze.daysLeft(input.now)} more day(s) at 5 % below ${formatKg(freeze.baseWeight)} kg';
      weight = math.min(weight, frozen);
      kind = SuggestionKind.egoFreeze;
      reps = range.min;
      why.add('Rule: ego flag, progression frozen for ${freeze.daysLeft(input.now)} more day(s) '
          '→ 5 % below ${formatKg(freeze.baseWeight)} kg.');
    }
```
`FreezeState` (`:9-23`):
```dart
  bool isActive(DateTime now) => now.isBefore(until);

  int daysLeft(DateTime now) {
    if (!isActive(now)) return 0;
    return (until.difference(now).inHours / 24).ceil();
  }
```
Example: base 80, no bodyweight -> 76 -> snapDown on plain 2.5 grid -> 75, reps = range.min (`suggestion_engine_test.dart:343-351`). The weight is `min(weight, frozen)` so a freeze never raises.

#### Step 4: Readiness + recovery (the "Repeat" rule)
`:349-375`
```dart
    final r = input.readiness;
    final band = r.band;
    var adjustment = '';
    if (r.loadPenaltyGroups.isNotEmpty) {
      why.add('Readiness: ${r.loadPenaltyGroups.join(', ')} volume over the last 7 days is above 1.5× your 4-week average '
          '→ readiness −${ReadinessCalculator.loadPenalty} for this exercise.');
    }
    final scoreText = r.calibrating ? 'calibrating, treated as Green' : '${r.adjustedScore}';
    final fatigued = input.fatigued.isNotEmpty;
    final cause = [
      if (band != ReadinessBand.green) 'Readiness ${band.label} ($scoreText)',
      if (fatigued) '${input.fatigued.map((m) => m.toLowerCase()).join(', ')} Fatigued',
    ].join(' + ');
    if (!fatigued && band == ReadinessBand.green) {
      why.add('Readiness: Green ($scoreText) → no change.');
    } else if (weight >= lastTop - 0.01 && kind != SuggestionKind.egoFreeze) {
      weight = lastTop;
      reps = repeatReps;
      if (kind == SuggestionKind.increase) kind = SuggestionKind.addReps;
      adjustment = 'Repeat';
      why.add('${band == ReadinessBand.green ? 'Recovery' : 'Readiness'}: $cause → repeat last session (${_loadText(weight)} × $reps), all $sets sets. '
          'The weight is never lowered for readiness.');
    } else {
      why.add('${band == ReadinessBand.green ? 'Recovery' : 'Readiness'}: $cause → no extra change.');
    }
```
Behaviour:
- Green and no fatigued prime mover: no change.
- Yellow, Red, or any Fatigued prime mover (muscle recovery band "Fatigued" = recovery < 60%, outside area): if the progression weight is >= last top weight and no ego freeze -> weight := last top weight, reps := `repeatReps` (best reps at top weight clamped to [range.min, range.max+3]); an `increase` becomes `addReps`; headline prefix "Repeat". Otherwise nothing extra ("no extra change"), e.g. when the weight is already lower (seed/freeze/max-load).
- **Yellow and Red are treated the same**; `compound` is ignored. Sets and weights are never lowered.
- Calibrating text "treated as Green" is shown whenever `r.calibrating`, but band still computed from `adjustedScore` (with load penalty could be Yellow) (OQ-9).
- Fatigued muscles come from `fatiguedPrimaries(recovery, [info.targets])` = primary muscles of the exercise whose RecoveryBand == fatigued (`lib/features/recovery/domain/recovery.dart:121-124`).

#### Step 5: Nutrition / bodyweight (text only; no effect on load)
`:377-389`
```dart
    if (!energy.hasNutrition && energy.trend == null) {
      why.add('Nutrition: no nutrition or bodyweight trend data in Apple Health, so it isn\'t used.');
    } else {
      if (energy.deficit) {
        why.add('Nutrition: deficit (${energy.deficitReason}): stalls are expected, so missing reps holds the weight and nothing is lowered.');
      } else if (energy.trend != null) {
        why.add('Nutrition: bodyweight ${energy.trend!.label}${energy.hasNutrition ? '' : ' (no food logged in Health)'} → no effect.');
      }
      if (energy.lowProtein) {
        why.add('Nutrition: protein ${energy.proteinPerKg!.toStringAsFixed(1)} g/kg over the last 7 days is under ${EnergyConfig.lowProteinPerKg} g/kg; loads unchanged.');
      }
    }
```
No numeric change to weight/reps from energy, whatever the values (tests: `suggestion_rework_test.dart:278-291`).

#### Step 6: snap to grid, down-note
`:391-409`
```dart
    weight = math.max(weight, _minLoad(input));
    final exact = weight;
    weight = grid.contains(exact) ? grid.snap(exact) : grid.snapDown(exact);
    if (weight < _minLoad(input)) weight = grid.snapUp(_minLoad(input));
    why.add(grid.contains(exact)
        ? 'Weight: ${_loadText(weight)} exists in your gym.'
        : 'Weight: ${formatKg(exact)} kg isn\'t available → ${_loadText(weight)} (the next lighter one you have).');

    // The visible reason whenever the target is below last time's weight *for this slot*. Nothing else may lower it.
    // A slot with no sets at its rep range yet (a back-off set after top sets) has no "last time" to be below.
    String? downNote;
    if (logs.isNotEmpty && input.rangeMatched && weight < lastTop - 0.01) {
      if (decreaseWhy == null && grid.maxLoad != null && lastTop > grid.maxLoad! + 0.01) decreaseWhy = 'your max load for this exercise is ${formatKg(grid.maxLoad!)} kg';
      if (decreaseWhy == null && !grid.contains(exact) && exact >= lastTop - 0.01) decreaseWhy = 'that weight isn\'t available in your gym';
      assert(decreaseWhy != null,
          'Unexplained decrease: ${_loadText(lastTop)} → ${_loadText(weight)} (${kind.name}). Every decrease needs a stated rule.');
      downNote = '↓ from ${_loadText(lastTop)}: ${decreaseWhy ?? 'see the explanation'}';
    }
```
`_minLoad` (`:495-496`): `input.assisted ? -input.bodyweight : 0`.

#### Step 7: result
`:411-424`
```dart
    return Suggestion(
      kind: kind,
      weight: weight,
      reps: reps,
      sets: sets,
      rir: input.targetRir,
      band: band,
      headline: _headline(weight, reps, sets, input.targetRir, adjustment, input.equipment),
      why: why,
      formResetHint: resetHint,
      maxReached: grid.atMax(weight),
      downNote: downNote,
      lighterOption: lighter,
    );
```
Headline (`:468-473`):
```dart
  static String _headline(double w, int reps, int sets, int rir, String adjustment, EquipmentKind eq) {
    final load = (w == 0 && eq == EquipmentKind.bodyweight) ? 'Bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg');
    final core = '$load × $reps, $sets ${sets == 1 ? 'set' : 'sets'}, stop at $rir reps in reserve';
    return '${adjustment.isEmpty ? 'Today' : adjustment}: $core';
  }
```
Examples: `Today: 82.5 kg × 6, 3 sets, stop at 2 reps in reserve`; `Repeat: 80 kg × 10, 3 sets, stop at 2 reps in reserve`.

`Suggestion` fields (`:115-162`): `kind`, `weight`, `reps`, `sets`, `rir`, `headline`, `why` (List<String>, each line starts with a stage label "Base:", "Rule:", "Readiness:", "Recovery:", "Nutrition:", "Weight:"; plus "Option:" in lighter-option case and "Form reset?" hint line), `techniqueDay`(default false), `rampUp`(default false), `band`(default green), `formResetHint`, `maxReached`, `downNote`, `lighterOption`.

#### Display helpers
`suggestion_engine.dart:164-178`
```dart
const String maxReachedMessage = 'Machine max reached: progress with reps or switch variation';

String formatKg(double kg) {
  final quarters = kg * 4;
  if ((quarters - quarters.roundToDouble()).abs() > 1e-6) kg = (kg * 2).roundToDouble() / 2;
  if (kg == kg.roundToDouble()) return kg.toStringAsFixed(0);
  final s = kg.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

String formatRpe(double rpe) => rpe == rpe.roundToDouble() ? rpe.toStringAsFixed(0) : rpe.toStringAsFixed(1);
```
`_loadText` (`:498`): `w == 0 ? 'bodyweight' : (w < 0 ? '${formatKg(-w)} kg assistance' : '${formatKg(w)} kg')`. `_d(d)` => `'${d.day}/${d.month}'`. `_describe` (`:510-520`): "last session (D/M): 80 kg × 10, 10, 10 @ RPE 8, 8, 7.5." (multiple weights -> "80×10, 82.5×8"; missing RPE shown as "–").
`formatVolume` (`lib/core/domain/format.dart:7-10`):
```dart
String formatVolume(double kg) {
  if (kg.abs() < 10000) return '${_grouped.format(kg.round())} kg';
  return '${(kg / 1000).toStringAsFixed(1)} t';
}
```
(`#,##0` en_US grouping.)

### 1.5 Calibration (no history for the exercise)

`suggestion_engine.dart:439-466`
```dart
  Suggestion _calibration(SuggestionInput input, WeightGrid grid) {
    // Assisted machines start with about half of bodyweight as assistance.
    final raw = input.assisted ? -input.bodyweight * 0.5 : startingWeight(input.equipment, input.increment);
    final start = input.assisted ? grid.snapDown(raw) : grid.snapUp(raw);
    final r = input.readiness;
    final sets = input.targetSets;
    final why = <String>[
      'Base: no history for this exercise → calibration session.',
      'Rule: start at ${_loadText(start)} and add weight each set while form stays clean. '
          'Stop every set at RPE ${formatRpe(calibrationStopRpe)} (2 reps left). Your best working set today seeds future suggestions.',
    ];
    if (r.band == ReadinessBand.red) {
      why.add('Readiness: Red (${r.adjustedScore}) → ramp up conservatively; all $sets sets.');
    }
    why.add('Weight: ${_loadText(start)} is the lightest you have for it.');
    final loadText = _loadText(start);
    return Suggestion(
      kind: SuggestionKind.calibration,
      weight: start,
      reps: input.range.min,
      sets: sets,
      rir: 2,
      rampUp: true,
      band: r.band,
      headline: 'Calibration: start at $loadText and ramp up, $sets sets, stop each set at RPE 8',
      why: why,
    );
  }
```
Starting weights `lib/core/domain/equipment.dart:88-104`:
```dart
double startingWeight(EquipmentKind kind, double increment) {
  switch (kind) {
    case EquipmentKind.barbell:
      return 20.0; // empty Olympic bar
    case EquipmentKind.dumbbell:
      return increment; // lightest dumbbell step
    case EquipmentKind.machineCable:
      return increment * 2;
    case EquipmentKind.kettlebell:
      return 8.0;
    case EquipmentKind.bodyweight:
      return 0.0; // no added load
    case EquipmentKind.other:
      return 0.0;
  }
}
```
`start = grid.snapUp(raw)` (non-assisted) so lightest available >= raw; assisted = `snapDown(-bodyweight*0.5)`. Calibration sets carry no suggested weight (DECISIONS "Calibration sets have no suggested weight": no override detection). Warm-ups are not generated for ramp-up (`session_repository.dart:422-424`: `if (!main.rampUp)`). The calibration session's best set seeds the next session (Case B above).

### 1.6 Weight grid / rounding to plate steps (`lib/core/domain/gym.dart`)

#### Equipment settings model
`gym.dart:25-66`
```dart
class GymEquipment {
  const GymEquipment({
    this.dumbbells = defaultDumbbells,
    this.smallestPlate = defaultSmallestPlate,
    this.barWeight = 20,
    this.stack = const StackSpec(start: 5, step: 5),
    this.perExercise = const {},
    this.typeOverrides = const {},
    this.maxLoads = const {},
  });
  ...
  static const double defaultSmallestPlate = 2.5;

  static const List<double> defaultDumbbells = [
    2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25, 27.5, 30, 32.5, 35, 37.5, 40, 42.5, 45, 47.5, 50, //
  ];
  ...
  /// A pair of the smallest plates: the step of a barbell and of two-sided plate machines.
  double get barbellStep => smallestPlate * 2;
```
Field meanings: `dumbbells` = per-hand weights available; `smallestPlate` = smallest plate (one-sided machines step by it; two-sided + barbell step by 2x); `barWeight` = 20 (no setter found in copyWith... `copyWith` keeps `barWeight`); `stack` = default machine/cable stack start/step; `perExercise` = per-exercise `StackSpec` overrides by exercise id; `typeOverrides` = per-exercise LoadType override; `maxLoads` = per-exercise cap (absent = unlimited).

`stepFor` (`gym.dart:89-96`):
```dart
  double? stepFor(String exerciseId, LoadType type) => switch (type) {
        LoadType.plateOneSide => smallestPlate,
        LoadType.plateBothSides || LoadType.barbell => barbellStep,
        LoadType.stack || LoadType.assisted => stackFor(exerciseId).step,
        LoadType.bodyweight || LoadType.other => 2.5,
        LoadType.dumbbell || LoadType.kettlebell => null,
      };
```
#### Which loads exist per load type (`gridFor`, gym.dart:102-170)
```dart
    final loadType = typeOverrides[exerciseId] ??
        type ??
        (assisted
            ? LoadType.assisted
            : switch (kind) {
                EquipmentKind.barbell => LoadType.barbell,
                EquipmentKind.dumbbell => LoadType.dumbbell,
                EquipmentKind.kettlebell => LoadType.kettlebell,
                EquipmentKind.bodyweight => LoadType.bodyweight,
                EquipmentKind.machineCable => LoadType.stack,
                _ => LoadType.other,
              });
    final values = <double>{};
    void stepped(double start, double step, double top) {
      if (step <= 0) return;
      for (var w = start; w <= top + 1e-9; w += step) {
        values.add(_q(w));
      }
    }

    switch (loadType) {
      case LoadType.assisted:
        // Assistance is negative load: 0 and every stack position below it.
        final st = stackFor(exerciseId);
        values.add(0);
        for (var w = st.start; w <= 150; w += st.step) {
          values.add(_q(-w));
        }
      case LoadType.dumbbell:
        values.addAll(dumbbells);
      case LoadType.barbell:
        stepped(barWeight, barbellStep, 400);
      case LoadType.plateBothSides:
        stepped(barbellStep, barbellStep, 600);
      case LoadType.plateOneSide:
        stepped(smallestPlate, smallestPlate, 400);
      case LoadType.stack:
        final st = stackFor(exerciseId);
        stepped(st.start, st.step, 300);
      case LoadType.kettlebell:
        values.addAll(const [4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 36, 40, 48]);
      case LoadType.bodyweight:
        values.add(0);
        stepped(2.5, 2.5, 100); // added load: plates / a dumbbell between the legs
      case LoadType.other:
        values.add(0);
        stepped(2.5, 2.5, 300);
    }
```
Resulting grids with defaults (smallestPlate 2.5, bar 20, stack 5/5): barbell 20,25,...400; plateBothSides 5,10,...600; plateOneSide 2.5,5,...400; stack 5,10,...300; dumbbell list 2.5..50 by 2.5; kettlebell fixed list; bodyweight 0,2.5,...100; other 0,2.5,...300; assisted 0 and -5,-10,...-150 (using stack start/step).

Logged weights and max load (`gym.dart:157-170`):
```dart
    // A weight you have logged exists by definition, unless you told the app how this exercise is loaded (Weight steps…): then your
    // starting weight, step and type are the truth, and weights logged under an earlier setting must not keep the old grid alive.
    if (!typeOverrides.containsKey(exerciseId) && !perExercise.containsKey(exerciseId)) {
      for (final w in logged) {
        values.add(_q(w));
      }
    }
    final max = maxLoads[exerciseId];
    if (max == null) return WeightGrid(values);
    // Nothing above the cap; if everything is above it (a cap under the lightest load) the cap itself exists.
    final capped = values.where((v) => v <= max + 1e-9).toSet();
    if (capped.isEmpty) capped.add(max);
    return WeightGrid(capped, maxLoad: max);
```
`_q(w) = (w*20).roundToDouble()/20` (0.05 kg precision, `gym.dart:173`). `logged` in coach (`coach_context.dart:149-155`):
```dart
WeightGrid gridForExercise(GymEquipment gym, TrainingHistory history, ExerciseInfo info) => gym.gridFor(
      exerciseId: info.id,
      kind: info.equipmentKind,
      type: loadTypeOf(info),
      assisted: isAssisted(info.id),
      logged: [for (final l in history.logsFor(info.id)) for (final s in l.sets) if (!s.isWarmup) snapNoise(s.weight)],
    );
```
(includes weights of drop/myo/hold sets; excludes warm-ups; includes not-completed sets - OQ-10.)

#### WeightGrid operations (`gym.dart:241-305`)
```dart
class WeightGrid {
  WeightGrid(Iterable<double> values, {this.maxLoad}) : values = (values.toSet().toList()..sort());
  ...
  bool atMax(double w) => maxLoad != null && w >= maxLoad! - _eps;
  static const double _eps = 0.01;
  bool contains(double w) => values.any((v) => (v - w).abs() < _eps);
  /// Heaviest available load ≤ [w] (the lightest one if [w] is below all).
  double snapDown(double w) {
    double? best;
    for (final v in values) {
      if (v <= w + _eps) best = v;
    }
    return best ?? values.first;
  }
  /// Lightest available load ≥ [w] (the heaviest one if [w] is above all).
  double snapUp(double w) {
    for (final v in values) {
      if (v >= w - _eps) return v;
    }
    return values.last;
  }
  /// Nearest available load; ties go down.
  double snap(double w) {
    final d = snapDown(w), u = snapUp(w);
    return (w - d) <= (u - w) ? d : u;
  }
  double? next(double w) { for (final v in values) { if (v > w + _eps) return v; } return null; }
  double? previous(double w) { double? best; for (final v in values) { if (v < w - _eps) best = v; } return best; }
  double? nextJump(double w, {double bodyweight = 0}) {
    final n = next(w);
    if (n == null) return null;
    final base = math.max(1.0, w + bodyweight);
    return (n - w) / base;
  }
}
```
Plain grid fallback when no gym grid is passed (`suggestion_engine.dart:475-483`):
```dart
    final inc = input.increment <= 0 ? 2.5 : input.increment;
    final lo = input.assisted ? -(input.bodyweight <= 0 ? 150 : input.bodyweight) : 0.0;
    return WeightGrid([
      for (var w = lo; w <= 400; w += inc) (w * 1000).roundToDouble() / 1000,
      for (final l in input.history) for (final s in l.sets) snapNoise(s.weight),
    ]);
```
Per-category increments (`lib/core/domain/equipment.dart:41-86`), used only for this fallback, `startingWeight`, warm-up rounding and drop-set rounding:
```dart
  static const defaults = Increments({
    EquipmentKind.barbell: 2.5,
    EquipmentKind.dumbbell: 2.0,
    EquipmentKind.machineCable: 2.5,
    EquipmentKind.kettlebell: 4.0,
    EquipmentKind.bodyweight: 2.5,
    EquipmentKind.other: 2.5,
  });
```
Rounding helpers (`equipment.dart:61-86`):
```dart
const double _eps = 1e-3;

double roundToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean((weight / increment).roundToDouble() * increment);
}

double floorToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean(((weight / increment) + _eps).floorToDouble() * increment);
}

double ceilToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean(((weight / increment) - _eps).ceilToDouble() * increment);
}

/// Removes conversion noise: values within 0.001 kg of a 0.25 kg step snap to it, others stay.
double snapNoise(double v) {
  final q = (v * 4).roundToDouble() / 4;
  return (v - q).abs() < 1e-3 ? q : v;
}

double _clean(double v) => (v * 1000).roundToDouble() / 1000;
```
`EquipmentKind.fromDataset` mapping (`equipment.dart:14-31`): barbell/'e-z curl bar' -> barbell; dumbbell -> dumbbell; machine/cable -> machineCable; kettlebells -> kettlebell; 'body only' -> bodyweight; else other (trimmed, lowercased).

#### Dumbbell-list parsing (settings text input) `gym.dart:221-238`
```dart
    final range = RegExp(r'^(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$').firstMatch(t);
    if (range != null) {
      final a = double.parse(range.group(1)!), b = double.parse(range.group(2)!), s = double.parse(range.group(3)!);
      if (s <= 0 || b < a) return null;
      return [for (var w = a; w <= b + 1e-9; w += s) _q(w)];
    }
    final parts = t.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    final out = <double>[];
    for (final p in parts) {
      final v = double.tryParse(p);
      if (v == null || v <= 0) return null;
      out.add(_q(v));
    }
    return out.isEmpty ? null : (out.toSet().toList()..sort());
```
`describeDumbbells`: "2.5–50 kg, 2.5 kg steps" when one distinct step, else "2.5–50 kg (20 pairs)"; "none" when empty (`gym.dart:212-217`).

#### Settings JSON persistence (`gym.dart:176-204`)
Key `gym_equipment`; JSON keys: `dumbbells` (list<num>), `smallest_plate`, `bar`, `stack` {start, step}, `per_exercise` {id: {start, step}}, `type_overrides` {id: LoadType.name}, `max_loads` (only written if non-empty). decode: null/empty -> defaults; dumbbells sorted; unknown LoadType names dropped; missing keys -> defaults (old settings decode with smallest plate 2.5, `load_types_test.dart:104-109`).

### 1.7 Load types (per-load-type behaviour)

`lib/core/domain/load_types.dart:1-37` enum values and labels:
```dart
enum LoadType {
  barbell('Barbell'),
  plateBothSides('Plate-loaded, both sides'),
  plateOneSide('Plate-loaded, one side'),
  stack('Stack / cable'),
  dumbbell('Dumbbell'),
  kettlebell('Kettlebell'),
  bodyweight('Bodyweight'),
  assisted('Assisted stack'),
  other('Other');
  ...
  /// The types you can pick for one exercise from the logger's menu.
  static const List<LoadType> pickable = [stack, plateOneSide, plateBothSides];
}
```
Classification (`load_types.dart:39-78`):
```dart
final RegExp _oneSide = RegExp(r't[- ]?bar|landmine|pendulum|belt squat', caseSensitive: false);
final RegExp _bothSides = RegExp(
  r'smith|leg press|hack squat|hack calf|\bsled\b|v[- ]squat|plate[- ]loaded|hammer strength|iso[- ]?lateral|leverage',
  caseSensitive: false,
);

({LoadType type, String why}) explainLoad({required String name, required String? equipment, bool assisted = false}) {
  if (assisted) return (type: LoadType.assisted, why: 'assisted machine');
  final one = _oneSide.firstMatch(name);
  if (one != null) return (type: LoadType.plateOneSide, why: 'name: "${one.group(0)}"');
  final eq = equipment?.toLowerCase().trim();
  switch (eq) {
    case 'dumbbell':
      return (type: LoadType.dumbbell, why: 'dumbbell');
    case 'kettlebells':
      return (type: LoadType.kettlebell, why: 'kettlebell');
    case 'barbell':
    case 'e-z curl bar':
      return (type: LoadType.barbell, why: 'barbell');
    case 'body only':
      return (type: LoadType.bodyweight, why: 'bodyweight');
    case 'machine':
      final both = _bothSides.firstMatch(name);
      return both != null
          ? (type: LoadType.plateBothSides, why: 'machine, name: "${both.group(0)}"')
          : (type: LoadType.stack, why: 'machine with no plate-loaded name: assumed pin stack');
    case 'cable':
      return (type: LoadType.stack, why: 'cable');
    default:
      return (type: LoadType.other, why: 'no equipment listed');
  }
}
```
Priority: assisted flag > one-sided name regexes (any equipment, so "Landmine press"/barbell -> plateOneSide) > equipment string > both-sides regex (machine only). Precedence applied at grid time: `typeOverrides[exerciseId] ?? type ?? (assisted/kind fallback)` (`gym.dart:109`). Set from the logger menu "Weight steps…" (`GymRepository.setLoadType/setStack/setMaxLoad`, 1.11).

Behaviour summary per type (grid from 1.6; log guide from 1.8):
| LoadType | grid (defaults) | what the user logs | e1RM / bodyweight |
|---|---|---|---|
| barbell | 20 + k*5 up to 400 | total on bar incl. 20 kg bar | external weight |
| plateBothSides | 5k up to 600 | total plates both sides (carriage not counted) | external |
| plateOneSide | 2.5k up to 400 | total plates on sleeve | external |
| stack | start/step stack, up to 300 | pin number | external |
| dumbbell | list (per ONE dumbbell) | one dumbbell | external |
| kettlebell | fixed list 4..48 | the bell | external |
| bodyweight | 0, 2.5..100 (added load) | only added weight | `bodyweight + weight` for e1RM/jump % if exercise is in `bodyweightLoaded` |
| assisted | 0 and -start..-150 | assistance as NEGATIVE kg | `bodyweight + weight` |
| other | 0, 2.5..300 | whatever added | external |
"Per-side" handling: no separate grid for unilateral exercises; `isUnilateralName` only changes log-guide text (1.8).

### 1.8 Log guide (`lib/features/library/domain/log_guide.dart`)

`log_guide.dart:19-27`
```dart
final RegExp _unilateral = RegExp(r'one[- ]arm|single[- ]arm|one[- ]leg|single[- ]leg|one[- ]hand|single[- ]hand|unilateral|alternating|\bsingle\b', caseSensitive: false);

bool isUnilateralName(String name) => _unilateral.hasMatch(name);

LogGuide logGuideFor({required String name, required String? equipment, bool assisted = false, LoadType? override, double barWeight = 20, bool bodyweightLoaded = false}) {
  var type = override ?? classifyLoad(name: name, equipment: equipment, assisted: assisted);
  if (override == null && type == LoadType.other && bodyweightLoaded) type = LoadType.bodyweight;
  final one = isUnilateralName(name);
  final bar = barWeight == barWeight.roundToDouble() ? barWeight.round().toString() : barWeight.toString();
```
Per type (headline | detail | includes) - `log_guide.dart:29-102`:
- assisted: "Log the assistance as negative" | "Enter −30 when the machine takes 30 kg off your bodyweight; 0 means unassisted. Less assistance is a heavier lift." | "Your bodyweight is added automatically for ranks; you only log the assistance."
- dumbbell: "Log the weight of ONE dumbbell" | one ? "One side at a time: the dumbbell in your working hand." : "Two dumbbells of 20 kg is logged as 20, not 40." | "Just the dumbbell: nothing else is added."
- plateBothSides: one ? "Log the weight for one side" : "Log total plates on both sides" | one ? "The plates on the machine while you train one side." : "Add up the plates on the left and the right: 2 × 20 kg plates is logged as 40." | "Plates only: the sled or carriage’s own weight is not counted."
- plateOneSide: "Log total plates on the sleeve" | "This machine has a single loading sleeve or horn: add up everything on it." | "Plates only: the lever or arm’s own weight is not counted."
- stack: one ? "Log the weight for one side" : "Log the stack weight" | one ? "The stack weight (the number at the pin) while you train one side." : "The number at the pin on the weight stack or cable." | "Just the stack: handles, ropes and bars are not counted."
- barbell: "Log the total weight on the bar" | "Both sides’ plates plus the bar: a 20 kg bar with 2 × 20 kg plates is logged as 60." | "The bar ($bar kg) is included."
- kettlebell: "Log the weight of the kettlebell" | one ? "One side at a time." : "The weight stamped on the kettlebell." | "Just the kettlebell."
- bodyweight: "Log only the weight you add" | "Leave it at 0 for plain bodyweight; add a belt, vest or held plate as kilos." | "Your bodyweight is added automatically for ranks; it is not part of the number."
- other: one ? "Log the weight for one side" : "Log the total weight you move" | "No equipment is listed for this exercise: log whatever load you add, and 0 for none. Set its load type from the workout menu (Weight steps…) for exact steps." | "Only what you add."
`LogGuide` fields: `type, headline, detail, includes, unilateral`.

Equipment tiles (`log_guide.dart:105-150`): `EquipmentTile = ({IconData icon, String label})`; dataset equipment -> label: barbell "Barbell", e-z curl bar "EZ bar", dumbbell "Dumbbells", kettlebells "Kettlebell", cable "Cable", machine "Smith machine"/"Machine" (name contains "smith"), bands "Resistance band", body only "Bodyweight", medicine ball "Medicine ball", exercise ball "Exercise ball", foam roll "Foam roller", null/'other' "No equipment listed"; plus name-implied: "smith" -> Smith machine; `bench|incline|decline|preacher|lying|supine|chest[- ]supported|seated` (equipment != 'machine') -> "Preacher bench" if name contains preacher else "Bench"; "rope" -> Rope; `pull[- ]?up|chin[- ]?up|hanging` and not "assisted" -> Pull-up bar; `\bdip\b|dips` not assisted and not machine -> Dip bars. Icons are Material icons (RN: substitute).

### 1.9 Ego-lifting guardrail (`lib/features/coach/domain/guardrail.dart`)

Override reasons (`:3-17`): `feltStrong('Felt strong')`, `testingMax('Testing a max')`, `justDidIt('Just did it')`; `fromName` by enum `.name`, null if unknown. Stored as `HistSet.overrideReason: String?`.

Override detection (`:42-51`)
```dart
  static const double overrideTolerance = 0.05;
  static const Duration freezeDuration = Duration(days: 7);

  /// A working set more than 5 % heavier than the suggestion is an override.
  /// With a bodyweight suggestion (0 kg), any added load is an override.
  bool isOverride({required double weight, required double? suggested, required bool isWarmup}) {
    if (isWarmup || suggested == null) return false;
    if (suggested <= 0) return weight > 0;
    return weight > suggested * (1 + overrideTolerance) + 1e-9;
  }
```
Called from `SessionRepository.wouldOverride` (`lib/features/workout/data/session_repository.dart:631`): `!set.isFollowUp && _guardrail.isOverride(weight: weight, suggested: set.suggestedWeight, isWarmup: isWarmup ?? set.isWarmup)`. Note for negative suggested (assisted) `suggested <= 0` branch makes `weight > 0` the test (OQ-6).

Ego set vs. good override (training.dart quotes above): ego set = override AND reps < targetMin (too heavy). Good override = override, working, not follow-up, has targetMin, reps >= targetMin (above range ok), and (rpe null OR targetRir null OR rpe <= 10 - targetRir). Bad override (neither good): below range or past prescribed effort. A reason is asked only for an ego set (DECISIONS item 7 / Phase D).

Ego flag evaluation (`:19-36`, `:53-79`)
```dart
enum EgoTrigger { repeatedMaxOverrides, weightUpE1rmDown }
  ...
  EgoFlagResult evaluate(List<ExerciseSessionLog> history, {DateTime? since, double bodyweight = 0}) {
    final logs = history
        .where((l) => l.hasWorkingSets && (since == null || l.date.isAfter(since)))
        .toList();
    if (logs.length < 2) return const EgoFlagResult({});
    final last3 = logs.sublist(logs.length < 3 ? 0 : logs.length - 3);
    final triggers = <EgoTrigger>{};

    final egoSessions = last3.where((l) => l.hasEgoOverrides).length;
    if (egoSessions >= 2) triggers.add(EgoTrigger.repeatedMaxOverrides);

    // Weight up while e1RM down. A coach-prescribed increase resets reps to the bottom of the
    // range and lowers e1RM by design, so the heavier sessions must contain the lifter's own
    // overrides for this to count as ego lifting (see docs/DECISIONS.md).
    if (last3.length == 3) {
      final first = last3.first, latest = last3.last;
      final selfImposed = last3.skip(1).any((l) => l.hasBadOverrides);
      if (selfImposed &&
          latest.topWeight > first.topWeight &&
          latest.bestE1rm(bodyweight: bodyweight) < first.bestE1rm(bodyweight: bodyweight)) {
        triggers.add(EgoTrigger.weightUpE1rmDown);
      }
    }
    return EgoFlagResult(triggers);
  }
```
Message (`:27-35`):
```dart
    final parts = <String>[
      if (triggers.contains(EgoTrigger.repeatedMaxOverrides))
        '2 of your last 3 sessions had sets heavier than suggested that fell below the rep range',
      if (triggers.contains(EgoTrigger.weightUpE1rmDown))
        'the weight went up while your estimated 1RM went down',
    ];
    return 'Ego lifting detected: ${parts.join(' and ')}. Progression is frozen for 7 days at −5%.';
```
Freeze expiry: `freezeUntil(start) = start.add(7 days)`; active while `now.isBefore(until)`.

Who creates the freeze (finish flow, outside area, `lib/features/workout/data/finish_service.dart:264-281`):
```dart
    // Ego flags → freezes.
    final flags = <GuardrailFlag>[];
    final freezes = latestFreezes(await _freezes.all());
    for (final e in session.exercises) {
      final existing = freezes[e.exerciseId];
      if (existing != null && existing.until.isAfter(now)) continue;
      final result = _guardrail.evaluate(
        after.logsFor(e.exerciseId),
        since: existing?.startedAt,
        bodyweight: bwLoaded.contains(e.exerciseId) ? bodyweight : 0,
      );
      if (!result.flagged) continue;
      final top = e.workingSets.map((s) => s.weight).fold<double>(double.negativeInfinity, (m, w) => w > m ? w : m);
      final base = e.suggestedWeight ?? top;
      final until = _guardrail.freezeUntil(now);
      await _freezes.add(exerciseId: e.exerciseId, start: now, until: until, baseWeight: base, reason: result.message);
      flags.add(GuardrailFlag(exerciseName: e.name, message: result.message, freezeUntil: until));
    }
```
So: evaluated per exercise of the finished session; skipped when a freeze is still active; considers only sessions started after the previous freeze's `startedAt`; freeze base = the exercise's suggested weight (else top working weight of this session); freeze starts at finish time `now`, lasts 7 days; one new row per flag (`EgoFreeze` row: exerciseId, startedAt, until, baseWeight, reason - `coach_context.dart:23-30`); latest row per exercise wins (`latestFreezes`, `:36-43`); `CoachContext.freezeFor` returns the state only if still active (`:114-119`).

Discipline % (info only, `:83-95`):
```dart
  double? disciplinePct(Iterable<LoggedSet> sets) {
    var total = 0, followed = 0;
    for (final s in sets) {
      if (!s.isWorking || s.suggestedWeight == null) continue;
      total++;
      if (s.isDisciplined) followed++;
    }
    if (total == 0) return null;
    return followed / total * 100;
  }
```
(used by `stats.dart:44` over `setsSince(today-30 days)`.) Note `isWorking` here includes drop/myo/hold and warm-up excluded.

### 1.10 Praise (`lib/features/coach/domain/praise.dart`)
```dart
  static const int perWorkout = 2;

  static const List<String> messages = [
    'Beat the target and owned it.',
    'Heavier than planned, and every rep clean. Nice.',
    'You went up and held the range. Disciplined.',
    'Extra weight, still on target. Good call.',
    'That one was earned.',
  ];

  String? next({required LoggedSet set, required int exerciseKey, required Set<int> praisedExercises, required int given, int seed = 0}) {
    if (!set.isGoodOverride || given >= perWorkout || praisedExercises.contains(exerciseKey)) return null;
    return messages[(seed.abs() + given) % messages.length];
  }
```
Rules: only after a good override; max 2 per workout; max 1 per exercise per workout; wording `messages[(abs(seed)+given) % 5]` where seed = session id. Tracking per session is persisted by the caller (DECISIONS item 7: survives close/reopen).

### 1.11 Energy model (Apple Health bodyweight trend + nutrition) (`lib/features/coach/domain/energy.dart`)

`energy.dart:5-23`
```dart
abstract final class EnergyConfig {
  /// Slope over the last 28 days, needing ≥ 4 weigh-ins spread over ≥ 14 days.
  static const int slopeWindowDays = 28;
  static const int minSlopeSpanDays = 14;
  static const int minSlopePoints = 4;

  /// kg per week: below −0.2 = losing, above +0.2 = gaining.
  static const double trendThreshold = 0.2;

  /// Losing at least this fast counts as a clear deficit.
  static const double deficitSlope = -0.25;

  /// 7-day intake ≤ 85 % of the 28-day average counts as a clear deficit (needs ≥ 4 logged days in
  /// the last 7 and ≥ 10 in the 28).
  static const double deficitIntakeRatio = 0.85;

  /// Protein below this many g per kg bodyweight gets a one-line note.
  static const double lowProteinPerKg = 1.6;
}
```
Derived values (`:41-85`):
```dart
  bool get hasNutrition => kcal7 != null || protein7 != null;

  WeightTrend? get trend => slopePerWeek == null
      ? null
      : slopePerWeek! < -EnergyConfig.trendThreshold
          ? WeightTrend.losing
          : (slopePerWeek! > EnergyConfig.trendThreshold ? WeightTrend.gaining : WeightTrend.stable);

  double? get proteinPerKg => protein7 == null || avg7 == null || avg7! <= 0 ? null : protein7! / avg7!;

  bool get lowProtein => proteinPerKg != null && proteinPerKg! < EnergyConfig.lowProteinPerKg;

  String? get deficitReason {
    final reasons = <String>[
      if (slopePerWeek != null && slopePerWeek! <= EnergyConfig.deficitSlope) 'bodyweight ${slopePerWeek!.toStringAsFixed(1)} kg/week',
      if (kcal7 != null && kcal28 != null && kcal28! > 0 && kcal7! <= kcal28! * EnergyConfig.deficitIntakeRatio)
        'eating ${((1 - kcal7! / kcal28!) * 100).round()} % under your 4-week average',
    ];
    return reasons.isEmpty ? null : reasons.join(', ');
  }

  bool get deficit => deficitReason != null;
```
Compute (`:98-134`):
```dart
  static EnergyContext compute({required DateTime now, required List<(DateTime, double)> bodyweights, required List<DayNutrition> nutrition}) {
    final today = dateOnly(now);
    final from7 = addDays(today, -6), from28 = addDays(today, -27);
    final w7 = [for (final (t, kg) in bodyweights) if (!dateOnly(t).isBefore(from7) && !t.isAfter(now)) kg];
    final w28 = [for (final (t, kg) in bodyweights) if (!dateOnly(t).isBefore(from28) && !t.isAfter(now)) (t, kg)];
    double? slope;
    if (w28.length >= EnergyConfig.minSlopePoints) {
      final first = w28.map((e) => e.$1).reduce((a, b) => a.isBefore(b) ? a : b);
      final last = w28.map((e) => e.$1).reduce((a, b) => a.isAfter(b) ? a : b);
      if (last.difference(first).inDays >= EnergyConfig.minSlopeSpanDays) {
        // Least squares, x in days.
        final xs = [for (final e in w28) e.$1.difference(first).inMinutes / 1440];
        final ys = [for (final e in w28) e.$2];
        final mx = xs.reduce((a, b) => a + b) / xs.length, my = ys.reduce((a, b) => a + b) / ys.length;
        var num = 0.0, den = 0.0;
        for (var i = 0; i < xs.length; i++) {
          num += (xs[i] - mx) * (ys[i] - my);
          den += (xs[i] - mx) * (xs[i] - mx);
        }
        if (den > 0) slope = num / den * 7;
      }
    }
    double? avg(Iterable<double?> v, int minDays) {
      final xs = v.whereType<double>().toList();
      return xs.length < minDays ? null : xs.reduce((a, b) => a + b) / xs.length;
    }

    final n7 = nutrition.where((d) => !dateOnly(d.day).isBefore(from7) && !d.day.isAfter(now));
    final n28 = nutrition.where((d) => !dateOnly(d.day).isBefore(from28) && !d.day.isAfter(now));
    return EnergyContext(
      avg7: w7.isEmpty ? null : w7.reduce((a, b) => a + b) / w7.length,
      slopePerWeek: slope,
      kcal7: avg(n7.map((d) => d.kcal), 4),
      kcal28: avg(n28.map((d) => d.kcal), 10),
      protein7: avg(n7.map((d) => d.proteinG), 4),
    );
  }
```
Windows: 7-day = today-6..today; 28-day = today-27..today (inclusive, local calendar days). Slope = ordinary least squares of weight vs days, x in fractional days, result kg/week (x7). `describe()` (`:88-96`) builds one line for the readiness card: "Bodyweight 106.0 kg (7-day), losing -0.4 kg/week · 2000 kcal/day · protein 1.4 g/kg (low)" and "No nutrition data in Apple Health, so it isn't used." when no nutrition.
Engine effect: text only (1.4 Step 5). `DayNutrition(day, kcal?, proteinG?)`.

### 1.12 Rest rules, warm-ups, set kinds, supersets, resnap, live activity

#### Rest after warm-ups (`lib/features/workout/domain/rest_rules.dart`)
```dart
  /// Between the last warm-up and the first working set: not in the program; 1:30 for the heavier first set.
  static const int beforeFirstWorking = 90;

  /// The rest to run after the warm-up [done] of [sets] (the exercise's sets in order): 1:30 when the next set is the first
  /// working set, none between warm-ups, none after the last set or before a follow-up (drop, myo, hold).
  static int? after(List<WorkoutSet> sets, WorkoutSet done) {
    final i = sets.indexWhere((s) => s.id == done.id);
    if (i < 0 || i + 1 >= sets.length) return null;
    final next = sets[i + 1];
    if (next.isFollowUp || next.isWarmup) return null;
    return beforeFirstWorking;
  }
```
Other rest facts (DECISIONS, cited because the code lives outside my files): none before a drop or hold, 5 s before a myo cycle (`myoRestSeconds`), the group's longest rest used in a superset round, per-exercise `restSeconds` stored on the session exercise (from routine / program, e.g. 90 in tests). Defaults in settings: compound 150 s, isolation 90 s (1.14). Rest-taken marker (`workout_sets.rest_seconds`), unticking cancels the rest: DECISIONS "8. Rest marker between sets" / "10. Unchecking a set cancels its rest" (UI/data, not read as code).

#### Warm-up generation (lives in program module, referenced by this area)
`lib/features/program/domain/program.dart:16-17`, `:296-312`
```dart
int warmupCountFor(ProgramSlot slot, {required bool firstOfDay, required bool compound}) =>
    (firstOfDay || compound) ? slot.warmupSets.max : slot.warmupSets.min;
...
List<WarmupSet> warmupSets({required Program program, required int count, required double workingWeight, required double increment}) {
  if (count <= 0) return const [];
  final steps = program.warmupByCount[math.min(count, program.warmupByCount.keys.reduce(math.max))] ?? const [];
  return [
    for (final s in steps)
      WarmupSet(
        weight: workingWeight <= 0 ? 0 : math.max(increment, roundToIncrement(workingWeight * s.pct / 100, increment)),
        reps: s.reps.min,
        pct: s.pct,
        repRange: s.reps,
      ),
  ];
}
```
Pyramid data (`assets/programs/min_max_canonical.json`, `method.warmup.exercise_specific.by_count`): 1 set: 60% x 6-10; 2: 50% x6-10, 70% x4-6; 3: 45% x6-10, 65% x4-6, 85% x3-4; 4: 45% x6-10, 60% x4-6, 75% x3-5, 85% x2-4; `rest_between_s` {0..60}. Warm-ups are inserted at session start (`session_repository.dart:421-441`), not for calibration (`!main.rampUp`), each warm-up weight `coach.gridFor(info).snap(w.weight)` when `main.weight > 0`. The warm-up count per slot comes from the slot's `warmup_sets` range (`warmupCountFor`) or an override. (Program section owner should detail slots.)

#### Set kinds (`lib/features/workout/domain/set_kinds.dart`)
```dart
enum SetKind {
  working('working', '', 'Working set'),
  warmup('warmup', 'W', 'Warm-up'),
  drop('drop', 'D', 'Drop set'),
  myo('myo', 'M', 'Myo-rep cycle'),
  hold('hold', 'H', 'Static hold');

  bool get isFollowUp => this == drop || this == myo || this == hold;

  /// Stored in `workout_sets.set_type` (null for working and warm-up sets).
  String? get setType => isFollowUp ? id : null;

  static SetKind of({required bool isWarmup, String? setType}) => switch (setType) {
        'drop' => drop,
        'myo' => myo,
        'hold' => hold,
        _ => isWarmup ? warmup : working,
      };

  static SetKind fromId(String id) => values.firstWhere((k) => k.id == id, orElse: () => working);
}
```
`WorkoutSet` extension: `kind`, `isFollowUp`, `isWorkingSet` (kind == working). Constants (`:43-75`):
```dart
const int myoRestSeconds = 5;
const int myoRepsPerCycle = 2;

/// Weighted static hold (program technique `weighted_static_hold_30s`).
const int holdSeconds = 30;

/// Default drop when the set isn't a program drop-set technique (the program's is 25 %).
const int defaultDropPct = 20;
...
const String dropTechnique = 'drop_sets_2x25';
const String myoTechnique = 'myo_reps';
const String holdTechnique = 'weighted_static_hold_30s';
const int programDropPct = 25;
const int programDrops = 2;

List<SetKind> followUpsFor(String? technique) => switch (technique) {
      dropTechnique => const [SetKind.drop, SetKind.drop],
      myoTechnique => const [SetKind.myo],
      holdTechnique => const [SetKind.hold],
      _ => const [],
    };
```
Drop weight (`:55-67`):
```dart
double dropWeight(double from, {required int pct, required double increment}) {
  final inc = increment <= 0 ? 1.0 : increment;
  if (from < 0) {
    // Assisted: a "drop" adds assistance.
    final raw = from - from.abs() * pct / 100;
    final r = (raw / inc).round() * inc;
    return r >= from ? from - inc : r;
  }
  final raw = from * (1 - pct / 100);
  var r = (raw / inc).round() * inc;
  if (r >= from) r = from - inc;
  return r < 0 ? 0 : double.parse(r.toStringAsFixed(2));
}
```
Tests: 100 -> 75 (25%, inc 2.5); 75 -> 57.5 (56.25 rounds half-up to 57.5); 40 @20%/inc5 -> 30; 5 @20%/5 -> 0; assisted -20 @25%/5 -> -25 (`set_types_test.dart:33-47`). Dart `.round()` rounds half away from zero (use `Math.round` carefully for negatives in RN).
Semantics (DECISIONS Phase C + doc comments + tests): drop/myo/hold are follow-ups under a working set, shown under it, never numbered; drops and myo count for volume (`tonnage`), hold stores SECONDS in `reps` and adds zero volume; none count for e1RM, ranks, PRs, progression, set count. `partials` is an informational flag only (e1RM, records, volume use full reps; `guardrail_test.dart:159-165`). Myo: pre-created one cycle (same load, 2 reps); hold: same load, 30 s; added drop = from parent (each new drop 20% under the one above; changing parent KG re-derives not-done drops: `set_types_test.dart:99-118`). Adding a working set copies the working set, not a drop (`:120-138`). The program creates no techniques on the standard week (`:140-159`).
`setSetKind` (`session_repository.dart:718-729`) on switching kind: follow-up kinds clear `suggestedWeight` and target rep range; hold sets reps=30, myo reps=2.

#### Supersets / rounds (`lib/features/workout/domain/superset_rounds.dart`)
```dart
List<List<WorkoutSet>> _rounds(ActiveExercise e) {
  final rounds = <List<WorkoutSet>>[];
  for (final s in e.sets) {
    if (s.isWarmup) continue;
    if (s.isFollowUp && rounds.isNotEmpty) {
      rounds.last.add(s);
    } else {
      rounds.add([s]);
    }
  }
  return rounds;
}
```
`supersetOrder`: exercises sharing `row.supersetGroup`: all members' warm-ups first (A1 warm-ups, A2 warm-ups), then rounds i = 0..max: member A's round i sets (working + follow-ups), then B's, ... `supersetRoundDone(members, exerciseId, setId)`: true when every partner that has that round index has all other sets in that round completed (the just-completed set counts as done); `round < 0` -> true. Rest only starts after the round ends and uses the longest rest in the group (DECISIONS Phase C). Groups of one are not supersets. Created in routine editor or mid-workout via `sessions.superset(a, b)`.

#### Next-set text / Live Activity helpers
`rest_preview.dart`: `nextSetAfter(session, ex, done)`: in a superset, scan the group's members in order for the first open set (not done, `id != done.id`); else next open set in the same exercise after `done`; else first open set in following exercises, then wrap to earlier exercises; null if none. `loadReps(s)`: weight 0 -> no load part; negative -> "25 kg assist"; hold shows "30 s"; joins "80 kg × 8" (reps part only if `s.reps > 0`). `nextLabel`: "Next: " + ('' for warm-up, 'working set ' for working, '<label lower> ' for others) + loadReps. `setTarget`: "Set N · 80 kg × 8" (N = index among working sets) or kind label ("Warm-up · 40 kg × 8", "Drop set · 60 kg × 8").
`workout_activity.dart`: `_maxWarmupLines = 4`; phases 'rest' | 'warmup' | 'working'; label "Warm-up 2 of 3" / "Set 2 of 3" (empty for follow-ups); warm-up chips text `BW×8` when weight 0 else `${formatKg(abs weight)}×reps`; shows from index `firstOpen-1` (or last 4 if all done), "+N more". Final: exerciseName 'Workout', nextTarget 'Last set done. Finish when ready.'. `after_workout.dart`: `AfterStep {congrats, rank, streak}`; always congrats; rank if `rankGains.isNotEmpty || overallRankUp != null`; streak if `streakGrew`.

#### Equipment resnap (`lib/features/workout/domain/equipment_resnap.dart`)
```dart
List<SetResnap> planResnap({required Iterable<WorkoutSet> sets, required WeightGrid grid, required double? oldSuggested, required double? newSuggested}) {
  final out = <SetResnap>[];
  for (final s in sets) {
    if (s.completed) continue;
    final untouched = !s.isWarmup && oldSuggested != null && (s.weight - oldSuggested).abs() < 0.01 && newSuggested != null;
    final wanted = untouched ? newSuggested : s.weight;
    var w = grid.snap(wanted);
    final max = grid.maxLoad;
    if (max != null && w > max) w = max;
    final changed = (w - s.weight).abs() >= 0.01;
    final sugg = s.suggestedWeight == null ? null : (untouched ? w : grid.snap(s.suggestedWeight!));
    final suggChanged = sugg != null && (sugg - (s.suggestedWeight ?? sugg)).abs() >= 0.01;
    if (!changed && !suggChanged) continue;
    final capped = max != null && s.weight > max + 0.01;
    out.add(SetResnap(
      setId: s.id, weight: w, suggested: sugg, from: s.adjustedFrom ?? s.weight,
      reason: changed
          ? 'Weight steps updated: ${formatKg(s.weight)} kg is now ${formatKg(w)} kg'
              '${capped ? ' (the max load is ${formatKg(max)} kg)' : ' (the nearest weight on the new steps)'}.'
          : 'Weight steps updated.',
    ));
  }
  return out;
}
```
Rules: completed sets never change; a not-done, non-warm-up set still at the OLD suggestion takes the NEW suggestion; typed weights are only snapped (nearest, ties down); capped at max load; warm-ups only snapped; the marker keeps the original weight (`from`). Applied by `SessionRepository.applyEquipmentChange` (`weight_steps_change_test.dart:148-181`: returns count of changed sets; 3 of 4 when first done).

#### Mid-workout lighten after a miss (only sanctioned plan change, outside area but part of engine behaviour)
`session_repository.dart:689-715`: after completing a non-warm-up, non-follow-up set with weight > 0 and reps > 0 and `reps < (targetRepMin ?? exerciseRepMin)`, later untouched working sets (still at their planned weight and heavier than `grid.previous(done.weight)`) move to `grid.previous(done.weight)`, store `adjustedFrom` and `adjustReason` "Set N: R reps at W kg, below the A–B rep range. This set moves one step lighter (X → Y kg) so it can stay in range."; never goes up; weight never changes on done sets, drops, warm-ups.

### 1.13 Gym repository (`lib/features/coach/data/gym_repository.dart`)
- Keys: `form_resets` (JSON map exerciseId -> {weight, at ISO8601}), `form_reset_offered` (JSON list of session-exercise ids, latest 300 kept), `smallest_plate_2_5` (migration flag '1'), `gym_equipment` (1.6).
- `setStack(id, spec|null)`, `setLoadType(id, type|null)`, `setMaxLoad(id, kg)` (`kg == null || kg <= 0` removes), each read-modify-write the whole `gym_equipment` JSON.
- Startup migration (`:58-70`):
```dart
  static const platesMigratedKey = 'smallest_plate_2_5';
  static Future<void> ensureSmallestPlate(AppDatabase db) async {
    if (await db.getSetting(platesMigratedKey) != null) return;
    final raw = await db.getSetting(GymEquipment.key);
    if (raw != null) {
      final g = GymEquipment.decode(raw);
      if ((g.smallestPlate - 2.25).abs() < 1e-9) await db.putSetting(GymEquipment.key, g.encode()...smallestPlate -> 2.5);
    }
    await db.putSetting(platesMigratedKey, '1');
  }
```
(actual code: `g.copyWith(smallestPlate: GymEquipment.defaultSmallestPlate).encode()`, `gym_repository.dart:67`). Only matters for migrating the original app's DB.
- `FormReset(weight, at)` (`suggestion_engine.dart:48-54`): "you chose a lighter weight on purpose. Progression restarts from [weight] on [at]; older, heavier sessions no longer count".
- `EgoFreezeRepository`: watchAll/all/add/deleteAll over table `egoFreezes`.

### 1.14 App settings (`lib/core/settings/app_settings.dart`)
Typed view over the `app_settings` key/value table (string values). Keys / types / defaults / meaning:
```dart
  static const kOnboarded = 'onboarded';
  static const kStreakReminder = 'streak_reminder';
  static const kIncrements = 'increments';
  static const kCompoundRange = 'compound_range';
  static const kIsolationRange = 'isolation_range';
  static const kDefaultRir = 'default_rir';
  static const kRestCompound = 'rest_compound';
  static const kRestIsolation = 'rest_isolation';
  static const kFakeHealth = 'fake_health';
  static const kHealthRequested = 'health_requested';
  static const kRestEndsAt = 'rest_ends_at';
  static const kRestTotal = 'rest_total';
```
| key | field | type | default | parse | meaning |
|---|---|---|---|---|---|
| `onboarded` | onboarded | bool | false | `== 'true'` | onboarding completed |
| `streak_reminder` | streakReminder | bool | true | `!= 'false'` | 18:00 reminder on streak last-chance day |
| `increments` | increments | Increments (JSON {EquipmentKind.name: kg}) | barbell 2.5, dumbbell 2.0, machineCable 2.5, kettlebell 4.0, bodyweight 2.5, other 2.5 | each entry must be `num > 0` and a known kind; others default | fallback increments (see 1.6) |
| `compound_range` | compoundRange | RepRange | 6-10 | "a-b", a>=1, b>=a else default | default range for compound exercises |
| `isolation_range` | isolationRange | RepRange | 10-15 | same | default range for isolation |
| `default_rir` | defaultRir | int | 2 | `int.tryParse ?? 2` | default reps in reserve |
| `rest_compound` | defaultRestCompound | int sec | 150 | tryParse ?? 150 | default rest, compound |
| `rest_isolation` | defaultRestIsolation | int sec | 90 | tryParse ?? 90 | default rest, isolation |
| `fake_health` | useFakeHealth | bool | false | `== 'true'` | debug builds: deterministic fake Health data |
| `health_requested` | healthPermissionsRequested | bool | false | `== 'true'` | Health permission prompt shown |
| `rest_ends_at` | restEndsAt | DateTime? | null | `DateTime.tryParse` | running rest timer end (survives restart) |
| `rest_total` | restTotalSeconds | int? | null | tryParse | running rest timer total seconds |
Encoding (`app_settings.dart:92-95`): `encodeIncrements` = `jsonEncode({for (e in inc.values.entries) e.key.name: e.value})`; `encodeRange` = `'${r.min}-${r.max}'`.
Other settings keys seen in this area: `gym_equipment`, `form_resets`, `form_reset_offered`, `smallest_plate_2_5`. Outside area (seen only in DECISIONS): `fix_lunge_per_dumbbell_v1`, streak offset (`StreakOffset.settingKey`).

### 1.15 Library helpers

#### Exercise search/filter (`lib/features/library/domain/exercise_filter.dart`, `exercise_aliases.dart`)
- `ExerciseFilter{query, muscle?, equipment?, favoritesOnly}`; `noEquipment = 'none'` matches `equipment == null`. `matches`: favorites; muscle in primary OR secondary; equipment (null -> 'none'); query matches name or any alias via `searchMatches`. `apply` sorts by `rank = (isFavorite ? 0 : 2) + (muscle != null && !primary.contains(muscle) ? 1 : 0)` then name lowercased.
- `searchTokens(text, stem)`: lowercase, non-`[a-z0-9]` -> space, split, then `_stem`:
```dart
String _stem(String w) {
  if (w.length <= 3) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('yes')) return w.substring(0, w.length - 2); // flyes → fly
  if (RegExp(r'(ches|shes|sses|xes)$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}
```
- `searchMatches(name, query)`: try unstemmed then stemmed; `q.every(spaced.contains) || compact.contains(q.join())` where `spaced = tokens.join(' ')`, `compact = tokens.join()`; empty query true.
- `buildAliases` merges: used display names; my_routines.json (`name`, `program_exercise`, `program_slots` -> slot map); canonical program slots (`exercise` + substitutions, via slot id -> exercise id); Liftoff map values (string id, {id}, {by_weight:[{id}]}).

#### Name resolver (`name_resolver.dart`)
Exact key = lowercase with non `[a-z0-9]` removed; abbreviations expanded: `DB`->dumbbell, `RDL`->romanian deadlift, `Flye`->fly, `Pressdown`->pushdown. Token similarity = Dice over `MediaMatcher.normalizeTokens(...)`; candidates sorted by score desc then shorter name; `resolve(name, minScore = 0.6)`; exact match scores 1. `MediaMatcher.normalizeTokens` is in `lib/features/tutorials/domain/media_matcher.dart:164-178` (outside area; stop-words, phrase and singular tables not read).

### 1.16 Dates, history helpers
`lib/core/domain/dates.dart` (local time; Monday week start): `dateOnly`, `weekStart(t) = Monday 00:00`, `dayKey` 'yyyy-MM-dd', `parseDayKey`, `addDays(d, n) = DateTime(y, m, d+n, h, min, s)` (calendar add, DST-safe), `sameDay`. `TrainingHistory` (`history.dart:96-187`): sessions sorted by `startedAt`; `logsFor`, `logsForRange`, `hasLogsAtRange`, `without(sessionId)`, `before(t)`, `bestValidE1rm({from,to,bodyweightLoaded,bodyweight})` (valid-for-records sets only, per exercise max e1RM), `inRange(from,to)` half-open, `inWeek`, `setsSince(from)`.

---------------------------------------------------------------------
## 2. DATA (models, enums, value objects, keys)

| Type | File:line | Fields |
|---|---|---|
| `RepRange` | training.dart:17 | `int min, max` (min<=max assert); `compound=6-10`, `isolation=10-15` |
| `LoggedSet` | training.dart:36 | `double weight` (kg external; negative = assistance), `int reps` (seconds for hold), `double? rpe`, `bool isWarmup=false, isOverride=false, completed=true, isDrop=false, isMyo=false, isHold=false, partials=false`, `double? suggestedWeight`, `int? targetMin, targetMax, targetRir` |
| `Effort` enum | training.dart:125 | failure('F',10), oneLeft('1',9), twoLeft('2',8), threePlus('3+',7) |
| `SuggestionKind` enum | training.dart:156 | calibration, seeded, increase, addReps, reduce, plateauDeload, egoFreeze, none |
| `ExerciseSessionLog` | training.dart:178 | `int sessionId, DateTime date, List<LoggedSet> sets, SuggestionKind suggestionKind=none, bool techniqueDay=false` |
| `HistSet` | history.dart:9 | `int id, LoggedSet set, DateTime? completedAt, String? overrideReason, RepRange? targetRange` |
| `HistExercise` | history.dart:20 | `id, exerciseId, name, MuscleTargets targets, EquipmentKind equipment, RepRange range, int targetSets, SuggestionKind suggestionKind, bool techniqueDay=false, double? suggestedWeight, int? suggestedReps, String notes, List<HistSet> sets` |
| `HistSession` | history.dart:55 | `id, name, int? routineId, startedAt, DateTime? endedAt, notes, int? readinessScore, String? readinessBand, int xpEarned, List<HistExercise> exercises, bool imported=false` (imported = Liftoff, no suggestions/XP); `duration = (endedAt ?? startedAt) - startedAt` |
| `EquipmentKind` enum | equipment.dart:2 | barbell('Barbell'), dumbbell('Dumbbell'), machineCable('Machine / cable'), kettlebell('Kettlebell'), bodyweight('Bodyweight (added load)'), other('Other') |
| `Increments` | equipment.dart:42 | `Map<EquipmentKind,double> values` |
| `LoadType` enum | load_types.dart:2 | barbell, plateBothSides, plateOneSide, stack, dumbbell, kettlebell, bodyweight, assisted, other (labels in 1.7); `pickable=[stack, plateOneSide, plateBothSides]` |
| `StackSpec` | gym.dart:8 | `double start, step` (JSON {start, step}) |
| `GymEquipment` | gym.dart:25 | `List<double> dumbbells, double smallestPlate=2.5, barWeight=20, StackSpec stack=(5,5), Map<String,StackSpec> perExercise, Map<String,LoadType> typeOverrides, Map<String,double> maxLoads` |
| `WeightGrid` | gym.dart:242 | `List<double> values (sorted unique), double? maxLoad` |
| `FreezeState` | suggestion_engine.dart:10 | `DateTime until, double baseWeight` |
| `ExerciseReadiness` | :26 | `int score, bool calibrating, List<String> loadPenaltyGroups`; `neutral = (60, false)` |
| `FormReset` | :50 | `double weight, DateTime at` |
| `SuggestionInput` / `Suggestion` | :56 / :115 | see 1.3 / 1.4 |
| `OverrideReason` | guardrail.dart:3 | feltStrong 'Felt strong', testingMax 'Testing a max', justDidIt 'Just did it' |
| `EgoTrigger` | guardrail.dart:19 | repeatedMaxOverrides, weightUpE1rmDown |
| `EgoFlagResult` | guardrail.dart:21 | `Set<EgoTrigger> triggers`; `flagged`, `message` |
| `EgoFreeze` (DB row) | coach_context.dart:23 (insert) | exerciseId, startedAt, until, baseWeight, reason |
| `EnergyContext`, `DayNutrition`, `WeightTrend`, `EnergyConfig` | energy.dart | see 1.11 |
| `SetKind` | set_kinds.dart:6 | id/letter/label: working '', 'Working set'; warmup 'W' 'Warm-up'; drop 'D' 'Drop set'; myo 'M' 'Myo-rep cycle'; hold 'H' 'Static hold' |
| `SetResnap` | equipment_resnap.dart:6 | `setId, weight, suggested?, from, reason` |
| `LogGuide` | log_guide.dart:8 | `type, headline, detail, includes, unilateral` |
| `NameMatch` | name_resolver.dart:4 | `ExerciseInfo exercise, double score` |
| `SettingsModel` | app_settings.dart:7 | table in 1.14 |
| `WorkoutSet` DB columns referenced | various | id, sessionExerciseId, position, isWarmup, weight, reps, rpe, completed, isOverride, partials, setType ('drop'/'myo'/'hold'/null), technique, suggestedWeight, suggestedReps, targetRepMin, targetRepMax, adjustedFrom, adjustReason, restSeconds |
| Session exercise columns referenced | session_repository.dart:410-420 | repMin, repMax, targetSets, restSeconds, targetRir, suggestionKind(name), suggestedWeight, suggestedReps, suggestedSets, suggestionJson (StoredSuggestion), programSlots (JSON ids), displayName, supersetGroup |

Settings / persistence keys in this area: `gym_equipment`, `form_resets`, `form_reset_offered`, `smallest_plate_2_5`, plus the 12 `SettingsModel` keys. Library `ExerciseInfo.isCompound = mechanic == 'compound'`; `equipmentKind = EquipmentKind.fromDataset(equipment)` (`exercise_info.dart:29,58-61`); default range by compound (`:67`).

Tests as spec (behavioural fixtures to port): `test/domain/suggestion_engine_test.dart`, `suggestion_rework_test.dart`, `no_silent_decrease_test.dart` (property tests: 2,355 library exercises x ... ~170k cases: top-of-range never lower; 20,000 random histories: lower => `downNote` starts with "↓ from "), `guardrail_test.dart`, `max_load_test.dart`, `load_types_test.dart`, `log_guide_test.dart`, `warmup_rest_test.dart`, `name_resolver_test.dart`, `test/data/weight_steps_change_test.dart`, `set_types_test.dart`. `test/tool/legacy/suggestion_engine_r1.dart` and `suggestion_engine_v1.dart` are archived copies of old engines (round-1 / v1) used only by tests and report generators (`suggestion_rework_test.dart:10` imports v1 to prove the old 6 kg bug); not part of the shipped logic. `test/tool/*_report_test.dart` generate the docs tables (LOAD_TYPES.md, LOG_GUIDE.md, SUGGESTIONS_BEFORE_AFTER.md).

Key fixture values worth porting verbatim (from tests):
- `80x10,10,10 @RPE 8,8,7.5` (compound 6-10, RIR2, barbell plain grid 2.5) -> increase, 82.5, reps 6, sets 3, headline "Today: 82.5 kg × 6, 3 sets, stop at 2 reps in reserve", why.first "Base: last session (1/5): 80 kg × 10, 10, 10 @ RPE 8, 8, 7.5." (`suggestion_engine_test.dart:52-60`).
- `80x8,8,7 @8` -> addReps, 80, reps 8. `80x10 @9 x3` -> addReps 80 reps 10. Missing RPE x3 at 10 -> hold.
- `80x7@9, 80x6@9.5, 80x5@10` -> hold 80, reps 6, no note, no lighter option.
- Three bad sessions at 80 (5,5 / 5,4 / 5,5) -> lighterOption 75; two sessions or a different weight in between -> none.
- Failure prescribed (RIR 0): `80x10@10 x2` -> increase 82.5; RIR 1: hold.
- Dumbbell isolation 10-15 grid step 2 (plain grid): 22x15 @8 -> 24; 10x15@7 x2 -> 10, reps 16, mentions "extend"; 10x17@7 -> 12.
- Yellow (score 45, band yellow) on top-at-8 history: weight 80, reps 10, sets 3, kind addReps; Red: headline "Repeat: 80 kg × 10, 3 sets, stop at 2 reps in reserve"; load penalty ['Chest'] with score 60 -> Yellow, why starts with "Readiness: Chest volume".
- Assisted (bodyweight 80, RIR 0, 4-6): -25x6@8 x3 -> increase -22.5; -25x3@10 x2 -> hold -25; `-80x2@10` -> -80 (never beyond bodyweight).
- Barbell calibration: weight 20, rampUp, headline "Calibration: start at 20 kg and ramp up, 3 sets, stop each set at RPE 8"; dumbbell calibration weight 2 (increment 2.0, plain grid). Calibration seeded: sets 20x8@6, 40x8@7, 60x6@8 -> 60 x 6.
- Ego freeze: base 80, until now+3 days -> egoFreeze, weight 75, reps 6; expired freeze (-1 min) -> increase.
- Y Raise regression (rework test) -> 7.5 kg on every band, reps 11 (Green) / 12 (Yellow, Red), why.last "Weight: 7.5 kg exists in your gym.", formResetHint 7.5.
- Max load 50 (stack 2.5 steps): 47.5x12x3 (range 8-12, RIR2) -> 50, maxReached true; 50x12 -> addReps reps 13, why contains maxReachedMessage; 50x16 -> reps 17 (no cap); keypad + stops at 50.
- Guardrail: `isOverride(84, 80)` false, `(84.5, 80)` true; suggested 0: any >0 is override; discipline example -> 75 %; freeze 7 days: `daysLeft` at +6d = 1, +2d1h = 5, +7d inactive, 0.
- Grids: barbell 20,25,30; smith/plateBothSides 5,10,15; plateOneSide 2.5,5,7.5,10; stack 5,10,15; custom stack start 7 step 5 -> 7,12,17,22 and `snap(60)` = 62; smallest plate 1.25 -> one-sided step 1.25, two-sided 2.5.
- Warm-up rest: warm-up -> warm-up null; last warm-up -> working 90; warm-up -> drop/myo/hold null; unknown set null; a lone warm-up with nothing after null.

---------------------------------------------------------------------
## 3. OPEN QUESTIONS

- OQ-1: `SuggestionKind.reduce` and `plateauDeload` are never produced by the current engine (only the enum, `isDeload` ("Comeback" achievement) and legacy tests use them). `isDeload` therefore effectively only fires for `egoFreeze` (plus old stored rows). Keep the enum values for stored data; unclear if achievements still depend on them. (`training.dart:156-167`; `suggestion_engine_test.dart:157-166` builds a `plateauDeload` history fixture.)
- OQ-2: `Suggestion.techniqueDay` is never set to true and no engine path creates a "small deload"; yet `ExerciseSessionLog.techniqueDay`, `HistExercise.techniqueDay` and the engine's `normal`-filter and `!last.techniqueDay` checks still exist (legacy of the removed Red "small deload"). Dead for new data; may matter for imported/older rows.
- OQ-3: `SuggestionInput.compound` is passed everywhere and documented ("Compound lifts may drop one step on a Red day") but the engine never reads it. DECISIONS "Never remove sets..." still describes a Red-on-compounds "small deload one step below" which the code no longer does ("Repeat" for all). Code wins: Repeat for Yellow/Red/Fatigued regardless of compound.
- OQ-4: DECISIONS.md is largely historical and contradicts current code in several places; I did not find an explicit "superseded" mark on all of them: (a) "Below the bottom -> -5%" (Phase D table, `DECISIONS.md:1052`-ish) and Fix 6b "at most two decreases in a row", "first 2 sessions after a jump", plateau deload: all removed (Round 2 item 5). (b) Fix 6b "Yellow turns an increase into a hold; Red holds and removes one working set" (sets are never removed now). (c) Fix 6c "A clear deficit ... plateau needs three flat sessions": engine uses deficit for text only. (d) Fix 6a "smallest barbell plate per side (default 2.25 kg, ... 4.5 kg)" vs code `defaultSmallestPlate = 2.5` and step = 2 x plate = 5 kg (and `ensureSmallestPlate` migration). (e) Phase C "Rest after warm-ups: between warm-up sets 45 s" (Round 2 item 11) vs Round 3 item 6 + code: none between warm-ups, 90 s after the last. Follow the code (this doc's quotes).
- OQ-5: `docs/SUGGESTIONS_BEFORE_AFTER.md` header says "barbell plates 2.25 kg a side" (generated earlier); current default is 2.5 kg plates (barbell 5 kg steps). Table numbers may not reproduce with current defaults.
- OQ-6: Override detection for assisted (negative) suggestions: `isOverride` uses `suggested <= 0 -> weight > 0`, so an assisted suggestion of -25 treats any positive weight as an override and weights between -25 and 0 (less assistance, i.e. heavier lift) as NOT overrides. Likewise `followsSuggestion` for `suggested <= 0` requires `weight <= 0` (any assistance >= suggested counts as followed). Probably unintended for assisted lifts; not verified in tests.
- OQ-7: Freeze base weight. DECISIONS "Ego freeze base weight" says it is the coach-suggested weight of the flagged session (or top weight); code uses `e.suggestedWeight ?? top` where `e.suggestedWeight` is the exercise-level suggestion (`finish_service.dart:277`). Matches, but for exercises with several program slots (different rep ranges) which suggestion is stored on the exercise row is not visible in my files.
- OQ-8: `Guardrail.evaluate` first trigger with only 2 sessions: `logs.length < 2` returns none, but with exactly 2 sessions both with ego sets the flag fires although the message says "2 of your last 3 sessions". Also `since` filter uses `isAfter(since)` where `since` = previous freeze `startedAt` (the finish time), so the same-day finishing session (its `date` = session startedAt, earlier than finish time) is excluded by a freeze that started at a later finish; confirm intended.
- OQ-9: `ExerciseReadiness.calibrating` only changes the text ("calibrating, treated as Green") while the band is still `bandFor(adjustedScore)` where score is 60 (`coachScore`) minus 10 if a load penalty exists, so a calibrating user with an overloaded muscle gets Yellow ("Readiness Yellow (calibrating, treated as Green)" contradiction possible).
- OQ-10: `gridForExercise` adds every non-warm-up weight from history, including drop/myo/hold set weights and not-completed sets, and including hold sets whose weight is a load (fine) but also sets from any rep range. So a drop-set weight (e.g. 32.5) becomes a legal "available" weight and can be suggested later. Unclear if intended.
- OQ-11: `dropWeight` rounds to the per-category `increment` only (`set_kinds.dart:55-67`); DECISIONS (Batch 2 item 2) says drop sets snap down to the grid and stay below the max load. The grid snapping is probably applied by the caller in `session_repository.dart` (not read here). Also `.round()` is half-away-from-zero in Dart (56.25/2.5 = 22.5 -> 23 -> 57.5): the JS `Math.round` differs for negative halves (assisted).
- OQ-12: `egoRpeThreshold = 9.5` (training.dart:8) is documented as "RPE at or above which an override set counts as an ego set" but the code's `isEgoSet` ignores RPE (override AND reps below range). I did not find a usage of the constant in the files read.
- OQ-13: `HistSession.volume` (`history.dart:88`) uses `weight * reps` of `isWorking` sets of `HistExercise.workingSets` (includes drops/myo and also hold sets, which would multiply weight by seconds) while `ExerciseSessionLog.volume` / `LoggedSet.tonnage` zeroes holds. Inconsistent unless holds are filtered elsewhere.
- OQ-14: `bodyweightLoaded` classification mismatch: `LOAD_TYPES.md` lists Back Extension ("Hyperextensions") as load type "Other", step 2.5; `LOG_GUIDE.md` shows "Bodyweight". Code: `logGuideFor(bodyweightLoaded: true)` upgrades `other` -> `bodyweight` for the guide only; `loadTypeOf`/`gridForExercise` do not (so grid = `other`: 0, 2.5..300 rather than bodyweight 0, 2.5..100). Effect on suggestions is nil under 100 kg, differs above.
- OQ-15: Calibration start for barbell is hard-coded 20.0 (`startingWeight`), not `GymEquipment.barWeight`; machine/cable calibration = `increments.of(machineCable) * 2` = 5 kg regardless of the stack `start`/`step`; the grid `snapUp` then moves it to the first available weight >= raw (e.g. stack start 7 -> 7). `barWeight` has no setter in `GymRepository` (no UI found in these files).
- OQ-16: In release builds, an unexplained decrease shows `'↓ from X: see the explanation'` (the `assert` is debug-only). Cases that still can reach it: `weight` lowered by `_minLoad`/snap in unusual grids; not exercised by tests since tests run with asserts on.
- OQ-17: When a freeze is active but `frozen >= weight` (e.g. a big grid step), `kind` becomes `egoFreeze` and `reps = range.min` even though the weight is not lowered and no `decreaseWhy`; also the readiness block is skipped for "Repeat" under egoFreeze (`kind != egoFreeze`), so a freeze at Red/Yellow produces "no extra change".
- OQ-18: Rest defaults `defaultRestCompound=150`, `defaultRestIsolation=90` and `defaultRir=2`, compound/isolation default ranges are in `SettingsModel`; where each is applied (routine creation, add exercise, program override) is outside my files. Per-exercise `restSeconds` also comes from routine/program rows. Needed from the Workout/Program section owner.
- OQ-19: `ExerciseSessionLog.date = session.startedAt` while the form-reset filter compares `dateOnly(date)` with `dateOnly(reset.at)` (`reset.at` = "the day of the lighter session"); sessions on the reset day itself count (`!isBefore`).
- OQ-20: `energy.deficit` uses `slope <= -0.25` while trend "losing" uses `< -0.2`: stated in docs; consistent. But `EnergyContext.compute` includes bodyweights up to `now` only; Apple Health trend unit assumed kg.
- OQ-21: Readiness text claims: the why-line hard-codes "above 1.5× your 4-week average" while the real threshold lives in `readiness.dart` (`threshold = 1.5`); and DECISIONS says the 4-week average is "the 28 days before the current 7-day window". Not re-derived here (readiness module is another section).
- OQ-22: `MediaMatcher.normalizeTokens` (stop-words, phrase table, singular table) determines `ExerciseNameResolver` results and was not in my file list; the RN port needs that file to reproduce `resolve()` (and `minScore` 0.6 semantics).
- OQ-23: `lighterOption` application path (tap on chip moves not-done sets) and `adaptLaterSets` call site (`active_workout_screen.dart:468`) are UI/data outside my files; behaviour described from `session_repository.dart:689-715` and DECISIONS only.
- OQ-24: `docs/DECISIONS.md` Round 2 item 5 says "calibration or an exercise with no sets at that rep range re-anchoring" and "weight that doesn't exist" are the other decrease paths: the code matches, but the `rangeMatched` computation `history.logsFor(info.id).isEmpty || history.hasLogsAtRange(info.id, range)` means an exercise with history but never at this range always re-anchors from e1RM (3 last sessions) even if one recent session was at a nearby range.

---

# Appendix D1. Screens, flows, navigation and UI components

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `D1 §n`).

## D1. Feature inventory: screens, flows, navigation, UI components

Source root: `/Users/hassan/IdeaProjects/spotter-app/lib` (abbrev. `L/`). Docs: `docs/DESIGN.md`, `docs/PLAN.md`.
Out of my scope (owned by other agents, only mentioned where embedded): ranks/gamification/readiness/recovery presentation (`RankBadge`, `RankSequenceScreen`, `RankUpScreen`, `LadderScreen`, `ProgressScreen`, `ReadinessCard`, `RecoveryCard`, `StreakWeek`, `FireStreak`, `anatomy_graph`, `muscle_sheet`, `RankTargetModeToggle`, `rank_target_line`).

Conventions: "provider X" = Riverpod provider in `L/app_providers.dart` (not read by me). `repo` = `sessionRepositoryProvider` unless stated. The app is **dark-only, portrait, iOS-first** (themeMode forced dark, app.dart:106).

---
### 0. App bootstrap glue (`L/app.dart`)

- `SpotterApp` waits on `settingsProvider` (loading: centered spinner MaterialApp; error: text "Failed to open database: $e") then builds `MaterialApp.router` once (app.dart:92-110). Router is built once, with `onboarded` ValueNotifier seeded from settings so no bounce through /onboarding (app.dart:96-100).
- `KeyboardDismisser` wraps every route (app.dart:108): see section 3.
- Startup listeners (all in `initState`, app.dart:27-63). Each is a hook the RN port needs:
  1. `settingsProvider` -> `_onboarded` notifier (drives router redirect).
  2. `mediaBootstrapProvider` (exercise<->ExerciseDB matching + GIF prefetch for routine exercises; re-runs when routines change). Errors -> `ErrorLog.recordCaught`.
  3. `streakReminderProvider`: `plan == null ? notifications.cancelStreakReminder() : scheduleStreakReminder(plan.at, body: plan.body)`, fireImmediately.
  4. `activeSessionProvider` -> `workoutActivitySyncProvider.refresh()` (Live Activity follows active session: sets ticked, exercises added). Also on `catalogProvider` change.
  5. `gymEquipmentProvider` change (only if `encode()` differs) -> `equipmentSyncProvider.onGymChanged(b)`: re-snaps not-yet-done sets of the running workout.
  6. `AppLifecycleListener.onResume`: `dayTickProvider.bump()`, `restTimerProvider.resync()` (re-show Live Activity forced), `_refreshHealth()`.
  7. Post-frame: `notificationService.init()`, `_refreshHealth()`, `rankLadderMigrationProvider.future`. Each step isolated by `_step` (errors logged, never block others, app.dart:65-72).
  - `_refreshHealth`: skip unless `onboarded` and (`healthPermissionsRequested` or `useFakeHealth`); else `healthSyncProvider.notifier.sync()` (app.dart:75-79).
- Home also pull-to-refresh calls the same sync.

---
### 1. SCREEN INVENTORY

#### 1.1 Onboarding: `/onboarding` (`L/features/onboarding/presentation/onboarding_screen.dart`)
Purpose: first-run, 3 non-swipeable pages (`PageView`, `NeverScrollableScrollPhysics`), top progress segments (3 bars, filled `i <= _page`).
- Page 1 "Spotter": welcome copy; **Bodyweight** text field (decimal keypad, kg). Valid = 30..300 (line 30-33). Button label `Skip for now` if invalid/empty else `Next`. `_next` unfocuses, animates page 280 ms easeOutCubic.
- Page 2 "Connect Apple Health": button -> `_connectHealth` (lines 40-61): `healthSource.requestPermissions()` -> `settingsController.setHealthRequested(true)` -> `notificationService.requestPermission()` (rest-timer alerts piggybacks here) -> `healthSyncProvider.notifier.sync()`. Status text depends on result: `!ok` => "Apple Health isn't available. Spotter will work without it and readiness stays neutral."; `days==0` => "Connected. No recovery data found yet ..."; else "Connected. Found recovery data for N of the last M days." If Health returned body mass and the field is empty, it pre-fills `bw`. Button label: `Connect Apple Health` / `Ask again` after first try / `Connect fake data (debug)` if `healthSource.isFake`. Secondary: `Not now` or `Next`.
- Page 3 "Your streak": copy ("Take up to two rest days in a row; if a third one ends without a workout, the streak starts over. No weekly goal, no fixed training days."). `Let's lift` -> `_finish` (63-68): if bw valid AND Health returned **no** body mass -> `bodyWeightRepository.addManual(bw)`; then `settingsController.setOnboarded(true)`. Router `refreshListenable` redirects to `/home`.
- No back navigation; no routine creation here. Health permissions only requested via this button (not automatic).

#### 1.2 Shell (bottom tabs) (`L/router.dart:194-222`)
`_Shell`: Scaffold, body = `StatefulShellRoute` branches; bottom = Column[`MiniWorkoutBar` (hidden when no active session), `NavigationBar` (height 72)]. 5 tabs: Home, Train, Library, Progress, Profile (icons outlined/filled pairs). Tap: `shell.goBranch(i, initialLocation: i == shell.currentIndex)` (re-tap current tab resets it to its root). Branch container `FadeBranches` (`core/motion.dart`): all 5 kept alive offstage (IndexedStack-like, state preserved, `TickerMode` off for hidden), 180 ms fade-in of the incoming tab (skipped under Reduce Motion).

#### 1.3 Home: `/home` (`features/home/presentation/home_screen.dart`)
AppBar: weekday UPPERCASE label + `d MMMM` date; Settings gear -> `push /settings`. Body `ListView` in `RefreshIndicator` (-> `healthSyncProvider.notifier.sync()`). Top to bottom:
1. `_HeroCard` (GameCard, accent = overall tier colour, glow if ranked; tap -> `go /progress`): `RankBadge` (92 wide), "OVERALL RANK", label (or "Unranked"), `RrBar` (division progress + "N RR") else text "Log a ranked lift to place on the ladder."; divider; level row: `ProgressRing` (52) with level number, "Level N", "`xpIntoLevel` / `xpForNext` XP to level N+1", total XP. Loading (`ranksProvider` loading w/o value): `Skeleton(190)`. Providers: `ranksProvider`, `levelProvider`.
2. `ReadinessCard` (readiness agent).
3. `RecoveryCard` (recovery agent; it navigates `go '/progress?tab=body&mode=recovery'`, recovery_card.dart:55).
4. Bodyweight-missing card (only `latestBodyWeightProvider.hasValue && value == null`): amber GameCard "No bodyweight in Apple Health. Tap to enter it so your lifts can be ranked." -> `enterBodyweight(context, ref)` (defined in progress_screen).
5. `_PrimaryAction`: if active session -> `BigButton "Resume <name>"` -> `push /workout`. Else take `nextRoutine(routines, lastRoutineId)` (workout_actions.dart:28: the routine after the most recently *used* routine cyclically by list order, else first; `lastRoutineId` = most recent finished session with a routineId from `historyProvider`). None -> `BigButton "Create your first routine"` -> `go /train`. Else `BigButton "Start <name>"` (disabled if routine has no exercises) -> `startWorkout(routine: next)`, plus one-line `a · b · c` exercise-name preview and `Other` text button -> `go /train`.
6. `_EgoFlags` (only if `activeFreezesProvider` non-empty): SectionLabel "Ego flags"; per freeze a `GuardrailBanner(egoFlag)` titled `"<ex>: frozen <1 more day|N more days>, suggestions 5% below <kg> kg"`, details = freeze reason. Days = `ceil(hours/24)`, `<=1` -> "1 more day" (home_screen.dart:223).
7. `_Quests`: SectionLabel "Weekly challenges" trailing "+40 XP each"; GameCard of rows (icon tile, title with line-through if done, `RrBar` with `progress/target`). Loading `Skeleton(170)`; error shows `$e`. Provider `questsProvider`.
8. `_Streak`: SectionLabel "Streak"; GameCard (tap -> `go /profile`; accent colour only if `days.days>0`): fire icon, `"{days}-day streak"`, line `Longest N days` (+ ` · today counts when you finish a workout` if streak>0 and not earnedToday), `DayDots` Mon..Sun (state: trained if session that day or mark workout; rest if mark rest; future; today; empty), safety line from `days.safety`:
   - trainedToday: "Safe: trained today" (green); safe: "Safe: trained yesterday, no rest days used" (green); oneRestDay: "1 rest day used" (warning); lastChance: "Last chance: train today or the streak resets" (danger); none: "Your next workout starts a new streak"; lost: `DayStreak.lostMessage` (danger). (home_screen.dart:344-351; these encode streak rules; underlying logic in gamification domain, other agent.)
   - Loss announcement: when `days.lost` and `lastWorkoutDay` not null, once per streak (setting key `streak_lost_seen` = yyyy-MM-dd of last workout day) show SnackBar(`DayStreak.lostMessage`, 4 s) (home_screen.dart:297-321). Skeleton(120) while loading.

#### 1.4 Train: `/train` (`features/workout/presentation/train_screen.dart`)
AppBar "Train"; FAB.extended "Routine" -> `promptText("New routine", hint "e.g. Push A")` -> `routineRepository.create(name)` -> `push /routine/{id}` (empty/blank name aborts).
Body (`AsyncBody(routinesProvider)`, `ListView` pad bottom 96):
- If active session: `FilledButton "Resume <name>"` -> `push /workout`; else `OutlinedButton "Start empty workout"` -> `startWorkout()` with no routine.
- SectionHeader "Routines". Empty: EmptyState "No routines yet" + hint. Else `ReorderableListView` (default handles off, handle = drag_indicator in each card via `ReorderableDragStartListener`); reorder -> `routineRepository.reorderRoutines(ids)`. `FadeSlideIn(index)` entrance per card.
- `_RoutineCard`: tap -> `push /routine/{id}`; name, "N exercises", names joined " · " (plain text; "No exercises yet — tap to edit." if none); `Start` button enabled only if `active == null` and routine has exercises -> `startWorkout(routine)`.

#### 1.5 Library: `/library` and `/pick-exercise` (`features/library/presentation/library_screen.dart`)
Same `LibraryScreen(pickMode)`. Title "Library" / "Add exercise". FAB.extended "Custom" -> `push /exercise-new` (distinct `heroTag` per mode).
- Search `TextField` (hint "Search {n} exercises", clear button, `onChanged` -> `ExerciseFilter.copyWith(query: trimmed)`). Matching uses `exerciseAliasesProvider`; a tile shows "also known as X" (primary colour) when an alias matched (`_filter.matchedAlias`).
- Horizontal chips: `Favorites` (toggle), `Muscle` (opens `_OptionSheet` of `datasetMuscles`; "Any" button clears), `Equipment` (sheet of distinct `equipment` values across catalog sorted, null equipment = sentinel `ExerciseFilter.noEquipment` labelled "None listed"/chip "No equipment"), `Clear` (when `_filter.isActive`; also clears search text).
- Count line "N exercise(s)". Empty: EmptyState "No matches". `ListView.builder` with `FadeSlideIn(index)`.
- `ExerciseListTile`: `ExerciseThumb` 56 (wrapped in `Hero('ex-hero-{id}')` except pick mode), name (2 lines), `muscleSummary · Equipment · Custom`, star favorite toggle -> `exerciseRepository.setFavorite(id, !fav)`. Tap: pickMode -> `context.pop(id)` (returns String id to caller of `context.push<String>`); normal -> `push /exercise/{id}`.
- Callers of pick mode: active workout "Add exercise", Replace sheet search, Routine editor FAB, Liftoff import "pick for this name". Search/filter state is local `_filter` (not persisted); not retained across pick invocations.

#### 1.6 Exercise detail: `/exercise/:id`, `/exercise/:id/history` (initial tab Stats), (`features/library/presentation/exercise_detail_screen.dart`)
Not found: EmptyState "Exercise not found". Loading: full-screen spinner. `DefaultTabController` 4 tabs `ExerciseTab {about, rank, stats, history}`; initial index from route (`/history` => stats; note the enum value `history` is a different tab, see OQ).
AppBar actions: favorite star toggle; if `isCustom`: Edit -> `push /exercise/{id}/edit`, Delete -> confirm "Delete exercise?" -> `exerciseRepository.deleteCustomIfUnused(id)`; true -> `pop`; false -> SnackBar "This exercise is used in a routine or a logged session, so it can't be deleted."
Header: title; if `activeFreezesProvider[id]`: red AppCard "Progression frozen · N day(s) left" + reason (`FreezeState.daysLeft(now)`).
- **About tab**: `ExerciseDemo` (GIF player, see 1.18) inside Hero (flight shows the thumbnail not the animated GIF); if `programVideosProvider[id]` exists, corner chip "Jeff's demo" -> bottom sheet with YouTube iframe player (`ProgramVideoPlayer`). Button "How to log?" -> bottom sheet with `logGuideFor(name, equipment, assisted, override=gym.typeOverrides[id], barWeight, bodyweightLoaded)`: headline, detail, includes, "Load type: X" (+ " · one side at a time" if unilateral). "Muscles worked": `ExerciseBodyFigures` (front/back body, rank agent). "Primary muscle"/"Secondary muscles" tiles (104 wide, `MuscleThumbnail`; tap -> `ranksProvider.future` then `showMuscleSheet(group, mode ranks)`). Equipment tiles via `equipmentTiles(info)`. Instructions numbered list (+ notes) ("No steps for this exercise." if none). Credit line "Sources: ..." (free-exercise-db public domain + `credits` entries joined `source, license, author`). "Photos" horizontal strip of network images (only if `imageUrls` non-empty; photos are only shown here).
- **Rank tab**: if no `ExerciseRank`: card "Unranked" with text depending on whether a `StrengthStandard` exists (no standard => "This exercise has no strength standard, so it does not get a rank. Its sets still count in your history and PRs."; else `Ranked as "<standard.name>". Log a working set to place it.`). Else `_RankCard` (badge 64, `labelWithRr`, RrBar, "Best e1RM X kg · W kg × R", rank target line or bodyweight what-if line depending on `rankTargetModeProvider`, `RankTargetModeToggle`). "Ladder" card: nine tier segments (current is taller, glow; tiers <= current are coloured), text "You are <label> of 9 tiers, N to go" (Immortal omits suffix). SwitchListTile **"Count toward ranks"** -> `RankExclusions(db).set(id, excluded: !on)`. Footer "Standard: name (per side)".
- **Stats tab** (`ExerciseStatsTab`, history/presentation/exercise_history_screen.dart): `historyProvider` -> logs with working sets; empty => "No history yet". Stat tiles: Best e1RM, Sessions, Best set (`w×r`), Volume; bodyweight note if exercise is in `bodyweightLoadedIdsProvider` ("e1RM includes your bodyweight (X kg)."). "Estimated 1RM" fl_chart line chart (x = days from first point, y = e1RM 1 dp; curved if >2 points, preventOvershoot; dots only if <=40; area fill 12% primary; y pad = max(2, 15% of range), floor/ceil; bottom axis ~4 intervals `d MMM`; tooltip "X kg\ndate"). Ego-set note "N ego set(s) (heavier than suggested and below the rep range) excluded from the chart, PRs and ranks." "Best sets": top 5 by e1RM over `isValidForRecords` working sets; tap -> `push /session/{id}`.
- **History tab** (`ExerciseSessionsTab`): every session (newest first): date `d MMM`, working sets as `w×r, ...`, warning icon if `hasBadOverrides` (red if ego); tap -> `push /session/{id}`.

#### 1.7 Custom exercise: `/exercise-new`, `/exercise/:id/edit` (`features/library/presentation/custom_exercise_screen.dart`)
Create/edit. Fields: Name (words caps), Primary muscles (multi-select FilterChips of `datasetMuscles`; "Pick at least one." in warning if empty), Secondary muscles (primary-selected ones disabled; on save `secondary = secondary - primary`), Equipment dropdown (`customEquipmentOptions`: barbell, dumbbell, cable, machine, kettlebells, body only, bands, e-z curl bar, other, None(null); default `barbell`), Type SegmentedButton Compound/Isolation (default compound; helper "Compounds default to 6–10 reps, isolations to 10–15."), Notes (4 lines). Bottom `FilledButton` ("Create exercise"/"Save changes") enabled iff name non-empty and >=1 primary. Save -> `exerciseRepository.createCustom(...)` or `updateCustom(editId, ...)` then `pop` (create does NOT return the new id to a pick-mode caller; see OQ). Edit loads via `exerciseRepository.byId`.

#### 1.8 Routine editor: `/routine/:id` (`features/workout/presentation/routine_editor_screen.dart`)
`routineRepository.watchRoutine(id)`; null => EmptyState "Routine deleted". AppBar title is tappable (pencil icon) -> `promptText("Rename routine")` -> `repo.rename`. Delete icon -> confirm "Delete routine?" ("Past sessions are kept.") -> `repo.delete`, `pop`. FAB.extended "Exercise" -> `push<String> /pick-exercise` -> `repo.addExercise(routineId, info, currentSettings)`.
Empty: EmptyState "Add exercises" ("Compounds default to 6–10 reps, isolations to 10–15, with a target of 2 reps in reserve."). Else `ReorderableListView` (drag handle at row end; `repo.reorder(ids)`). Each row (AppCard; tap -> `push /exercise/{exId}`): superset colour bar + label (A1/A2...), thumb 44, name, line `"{sets} × {min}–{max} · RIR {rir} · rest m:ss"` or, for rows with `programSlots`, `_ProgramRowInfo` (prescription from `prescribeSets`, warm-up count, rest text, "Effort RIR a / b / F", relation text: substitution/swap/extra/program). Row buttons: link (superset with next; coloured when the next row shares a group; `repo.toggleSupersetWithNext(e, next, all)`; absent on last row), swap (`_replace` -> program substitutions sheet or library search; `repo.replaceExercise(e, info, program)`; keeps row's prescription), tune (`_editTargets`), close (`repo.removeExercise(id)` no confirm), drag handle.
- `_editTargets` (non-program row): bottom sheet with 5 `StepperField`s: Min reps (clamp 1..max), Max reps (clamp min..50), Sets (1..10), Target RIR (0..5), Rest (step 15 s, 15..900). Save -> `repo.updateExercise(id, range, targetSets, restSeconds, targetRir)`.
- `_editProgramRow` (row has program slots): shows "Program: {workingSets} × {range} reps · rest {text|none}"; steppers Min/Max reps, Working sets (1..10), Rest (step 15, 0..900); `Save` -> `repo.setProgramOverrides(id, range: keepOverride ? range : null, targetSets, restSeconds)` where `keepOverride = existing override != null || range != program range`; `Reset to program` -> `repo.resetToProgram(e, program)`.

#### 1.9 Active workout: `/workout` (root navigator, full screen) (`features/workout/presentation/active_workout_screen.dart`, `exercise_block.dart`, `keypad.dart`, `swipe_set_row.dart`, `rest_timer.dart`)
Watches `gymEquipmentProvider` + `historyProvider` (kept live because keypad ±, drops, form-reset read grids with `ref.read`, line 86-89), `activeSessionProvider`, `catalogProvider`.
States: `_finishing` -> `CalculatingResults`; loading spinner; error text; no session -> EmptyState "No workout in progress" + `Go to Train` (`go /train`).
AppBar: leading chevron-down = **Minimize**; title: tappable session name (-> `promptText("Workout name")` -> `renameSession`, non-blank only) + `WorkoutClock`; action `Finish` FilledButton (spinner while finishing).
Body: `ListView` (padding 10; bottom 32 + home-indicator inset only when keypad closed) in a `GestureDetector` that unfocuses text on tap; then the `WorkoutKeypad` pinned below when a cell is focused.
List contents in order:
1. `_FatigueHeadsUp` (only if session has a `routineId`, not dismissed this visit, and `recoveryProvider` != null and `fatiguedPrimaries(...)` non-empty): red one-liner "Heads-up: <muscles> still fatigued" with X dismiss (state-local `_headsUpDismissed`). Informational only.
2. Notes `TextField` ("Workout notes", expands to 4 lines when focused; tap closes keypad; saved on focus loss, minimize, finish via `setSessionNotes`). Loaded once from `session.session.notes`.
3. One `ExerciseBlock` per exercise (details below).
4. Empty: "Empty workout. Add your first exercise."
5. `Add exercise` OutlinedButton: closes keypad, `push<String> /pick-exercise`, then `sessionRepository.addExercise(sessionId, info, range: info.defaultRange(compound, isolation settings), targetSets: 1 ("an added exercise starts with one working set; ADD SET adds more", line 908), restSeconds: compound? defaultRestCompound : defaultRestIsolation, targetRir: defaultRir, coach: workoutCoachProvider(sessionId))`.
6. `Discard workout` (danger text) -> confirm "Discard workout?" ("All sets logged in this session will be deleted.") -> `restTimer.stop()`, `repo.discard(id)`, `go /home`.
Also `WidgetsBindingObserver`: any non-`resumed` lifecycle state commits typed keypad text (line 342).

**ExerciseBlock** (card: surface fill, 20 radius, outline; superset members get a 5 px coloured left bar + "A1" label chip):
- Header: `ExerciseThumb` 40 (tap -> commit keypad then `push /exercise/{exerciseId}`), superset label, name (tap same), collapse/expand toggle (commits first), overflow menu.
- Menu items (`PopupMenuButton`, exercise_block.dart:329-342): Replace; `Superset with…`/`Remove from superset`; Target reps; Form reset…; Weight steps… (hidden for dumbbell and bodyweight equipment kinds); Notes; How to; Move up; Move down; Reorder exercises; Remove. Every menu action first calls `_commit()` (typed value never lost).
- Rest row: timer icon + text `Rest Timer m:ss ✎` (tap -> chip sheet 30/60/90/120/150/180/240/300 s -> `repo.setRest(id, seconds)`); in a superset the text is replaced by `supersetRestNote` ("No rest → A2" on non-last members; "Rest m:ss after the round ✎" on last, using the longest member rest). `Switch` toggles `repo.setRest(id, enabled)` (`row.restEnabled`).
- `_RankStrip`: live rank of this exercise (see below).
- Prescription line (tap toggles ⓘ details): `"{n}×{range} · ... · effort · last set: <technique>"`; effort text: all RIR 0 => "all sets to failure"; last RIR 0 => "last set to failure"; else "{firstRir} left in the tank"; calibration (`suggestion.rampUp`) => "Calibration: ramp up each set, stop 2 reps short". Details panel lists `suggestion.headline`, `why[]`, "Program: notes", "Progression frozen: reason", "Notes: ..."; lines beginning `Base|Rule|Readiness|Recovery|Nutrition|Weight|Form reset?` render with an accent bold prefix (regex exercise_block.dart:479).
- Suggestion chips/notes: `maxReachedMessage` (accent), `downNote` (warning), `Lighter option: X kg` ActionChip -> `repo.applyLighterOption(ex, kg)`, `Form reset at X kg?` ActionChip -> menu action form-reset. Chips hidden once any set is completed.
- **Set table** (a `TapRegion` group `keypadTapGroup`; outside tap = `onTapOutside`): header `SET | PREV | KG | REPS | EFFORT | (check)`; "N warm-up(s) hidden" muted line when hidden; each `_SetRow` inside `SwipeSetRow`; a `_RestMarker` ("⏱ m:ss", actual rest taken = `set.restSeconds`) before each completed set (not index 0); under the last completed drop/myo of a chain a `+ ANOTHER DROP` / `+ ANOTHER CYCLE` button; bottom row `ADD SET` -> `repo.addSet(ex)` and `Hide warm-ups`/`Show warm-ups` (only if warm-ups exist; toggle is **screen-wide** `_hideWarmups`).
- `_SetRow` columns: SET label (working sets numbered 1..n among working sets only; others show kind letter W/D/M/H; sub-label: drop `−N%` vs row above, myo `5s`, hold `HOLD`, technique tag `DS/MYO/HOLD/LP`, or `×range` when a later set's rep range differs from the first working set's); tap label (not completed) -> set menu. A blue dot on the label when `adjustReason != null` + caption "Target updated · why?" -> dialog "Target changed" explaining (two texts: "Weight steps updated..." = re-plan of running workout, else "Only later sets of the same exercise change, and only from how your earlier sets went...", exercise_block.dart:892-906). PREV cell: previous session's matched set `w × r` ("BW" for 0 kg; negative loads printed via `formatKg`), tap (if not completed) -> `onCopyPrev`. KG cell, REPS cell (tap = focus keypad; disabled when completed; hold sets display `{n}s`). EFFORT chip (36x28): label cycles `F -> 1 -> 2 -> 3+ -> F` (`Effort.next`; RPE 10/9/8/7); tap (not completed) -> `repo.updateSet(id, rpe)`; long-press -> toggle `partials` (label shows `+P`); `—` for warm-up and hold. Check button (44x38) -> `onComplete(set)` (toggles: tapping on a completed set un-completes).
- Cell visuals: grey (tertiary) if the value is still the untouched suggestion (`entered` false), white if completed, edited, or differs from suggested; focused cell has accent border + `surfaceTop`; amber `+N%` badge on KG when heavier than suggested (override) unless it's a "good override" (green `+N%`, only when completed and `isGoodOverride`). Warm-up rows at 60% opacity when not completed. Completed rows tinted 14% primary. Follow-up rows indented with a 3 px coloured rail.
- **Set type sheet** (tap the set label): SET TYPE: Working set, Warm-up, Drop set ("Lighter, to failure, no rest. Volume only, not e1RM or ranks"), Myo-rep cycle ("Same load: rest 5 s, 2 reps. Repeat until you miss"), Weighted static hold ("Hold the stretched position; REPS is seconds"); `ADD UNDER THIS SET` (not for warm-ups): Add drop set ("Pre-filled 20–25 % lighter"), Add myo-rep cycle, Add 30 s static hold; `+ partials` switch (not warm-up/hold; "Partial reps after the last full rep (reps stay full reps)"); `PROGRAM TECHNIQUE ON THIS SET` (only if program has techniques and set is a working set) -> `setSetKind(s, kind: 'technique:<id>')` and, if no follow-ups below, add `followUpsFor(id)` follow-ups (two 25 % drops, myo cycle, 30 s hold); Delete set. Follow-up parent = nearest preceding non-follow-up set (`_parentOf`). Handler map: `working/warmup/drop/myo/hold` -> `repo.setSetKind`; `follow:<kind>` -> `repo.addFollowUp(ex, parent, kind, increment, grid, technique)`; `partials:on/off` -> `repo.setPartials`; `delete` -> `deleteSetWithUndo`.
- **Swipe** (`SwipeSetRow`, swipe_set_row.dart): horizontal drag only. Left: reveals red "Delete" button 88 px wide; release past 44 px snaps open; release at `dx <= -0.6*width` or (velocity < -1200 and dx < -88) deletes immediately; tap on revealed button deletes. Right: green check reveal capped at 90 px; release at `>= 56` fires `onSwipeRight` (complete; only if set not completed) and springs back. Animations 180 ms easeOut. Delete = `deleteSetWithUndo`: commit keypad, fetch fresh row, `repo.deleteSet(row)`, SnackBar "Set deleted" 3 s with `Undo` -> `repo.restoreSet(row)`.
- **_RankStrip** (exercise_block.dart:699-862): shows badge+label+RrBar+target line. Hidden-from-ranks exercises show "Hidden from ranks"; unranked shows "Unranked · complete a set to place it" or "Not ranked (no strength standard)". Live score = best of finished-history baseline and this workout's completed working sets (set counts unless it is an override AND reps < `targetRepMin`; hold/warm-up/follow-up excluded; load includes bodyweight if standard is bodyweight-loaded; `scoringE1rm(load, reps, rpe)`). When live score rises: 1100 ms animation of the bar/badge; if the label (tier/division) changed: scale pop (to 1.45x with elasticOut over t in 0.6..1) + `heavyImpact`, else `selectionClick`. Un-ticking a set drops the score silently. Target line: `rankTargetLine(rankTargetSet(...))` or what-if bodyweight line per `rankTargetModeProvider`; `top of the ladder` at apex. (Logic in ranks domain: other agent.)

**Completing a set** (`_complete`, active_workout_screen.dart:428-473), in order:
1. If this set's keypad is open: `_closeKeypad()` (commits typed value) else `_commit()`.
2. Re-read the set from DB (the stream may lag): `repo.workoutSet(id)`.
3. If already completed: `repo.uncompleteSet(id)` and `restTimer.cancelIfFor(setId, latestDone: set was the most recently completed)`; return.
4. `rpe` = null for warm-up and hold; else existing `rpe` or `Effort.fromRir(set.targetRir ?? exercise.targetRir).rpe`.
5. If `repo.needsReason(set, weight, reps, exerciseRepMin)` (heavier than suggestion AND reps below rep-range minimum): bottom sheet "Heavier than suggested and short of the range" ("`w` kg vs `s` kg suggested, `r` reps. This set won't count for ranks or PRs. Why the extra weight?") listing `OverrideReason.values` labels; dismiss = abort the completion.
6. `HapticFeedback.lightImpact()` then `repo.completeSet(set, weight, reps, rpe, isWarmup, reason, now: clock(), exerciseRepMin, restEndedAt: _skippedRestEnd)` (`restEndedAt` = when the previous rest was skipped via `restTimer.takeSkip(prevCompletedAt)`, for the rest marker).
7. If not `quiet`: `repo.adaptLaterSets(set, grid, exerciseRepMin)` (missed reps re-target later sets of the same exercise only) -> `_maybePraise` -> `_startRest` -> `_maybeOfferFormReset`.
- Praise (`PraisePolicy().next(...)`, once per exercise, max twice per workout, seeded by session id; state `praiseProvider`): SnackBar 3 s with trending-up icon + `mediumImpact`.
- Form reset offer: for a *working* set whose weight <= one grid step below the recent best (last 3 sessions' top weight) done at >= top of rep range, once per session-exercise (`gym.formResetOffered()` / `markFormResetOffered(row.id)`), unless the saved reset weight equals this weight: SnackBar 3 s `"{w} kg × {r}, lighter than your recent {best} kg. Fixing form?"` with action `Form reset` -> form-reset menu action.
- **Rest start** (`_startRest`, lines 553-576): if exercise `restEnabled` false -> `timer.stop()`. Warm-up: no timer between warm-ups, `WarmupRest.after` = 90 s after the last warm-up when next set is the first working set (rest_rules.dart:13-22), else stop. If next set is a follow-up: myo => `timer.start(5 s)`, drop/hold => `timer.stop()`. Else `restSeconds` of exercise; in a superset: stop unless `supersetRoundDone(members, ex.id, set.id)`, and then use the **max** `restSeconds` across members. Each start passes a `RestPreview` (workoutName, next exercise name, next target label or "Last set done. Finish when ready.", via `nextSetAfter`/`nextLabel`). Starting a new rest (or stop) always ends a prior running rest.

**Keypad** (`keypad.dart`; state held by the screen: `_target KeypadTarget(setId, field)`, `_buffer KeypadBuffer`, `_edited` set):
- Layout: left 3 cols digits `1-9`, bottom row `.` (KG only), `0`, backspace; right 2 cols: `−inc` `+inc` (inc = equipment increment kg or "1" for reps), `Copy` `+/−` (sign toggle enabled only for assisted exercises on KG), `NEXT` (primary), hide-keyboard. Each key 48 high, selectionClick haptic; shown in a bottom SafeArea panel; part of `TapRegion` group with the set tables.
- Buffer rules (keypad.dart:27-82): empty or "-" counts as empty; reps max 3 digits; KG max 2 decimals; leading "0" replaced by next digit; `.` on empty inserts "0." (keeps "-"); backspace removes one char; `step(dir)`: reps +-1 clamped 0..999 from typed or cell value; KG snaps to `grid.next/previous(base)` else `base + dir*increment`, capped at `grid.maxLoad` going up; `toggleSign` flips leading "-"; formatPlain drops trailing zeros (2 dp).
- Focus (`_focus`): hide snackbar, unfocus text, commit previous cell, then set target + new buffer (for an assisted exercise KG buffer starts as "-"), then after frame `Scrollable.ensureVisible(cell, alignment 0.35, 200 ms)`.
- Commit (`_commit`): empty buffer => nothing. KG: `repo.updateSet(id, weight: v)` then `repo.refreshDrops(setId, increment, grid)` (pending drop sets under it follow its new load). REPS: `repo.updateSet(id, reps: round().clamp(0,999))`. Adds target to `_edited`, clears buffer text.
- NEXT: commit; if KG -> focus REPS of same set; else next incomplete set in `supersetOrder(exercises)` (skipping hidden warm-ups) -> its KG, or close keypad if none.
- Copy: previous session's matched set (`PrevSets.forSet`: matches kind and index among same-kind sets; kinds warmup/working/drop/myo/hold) else the set above in the same exercise; writes both weight & reps via `updateSet` and clears buffer.
- PREV tap: `updateSet(weight, reps)` from previous, marks both cells edited, clears typed buffer for that set.
- Tap outside table+keypad (`TapRegion` outside): commit, remember `_pendingTypedSetId`, close keypad. `Finish` later treats a typed-but-not-ticked set as done (`_complete(..., quiet: true)`, i.e. no adapt/praise/rest).
- Keypad is also closed when its set disappears (post-frame).

**Other exercise-menu actions** (active_workout_screen.dart:615-694):
- `replace` -> `_replace`: program slot substitutions resolved to library (`programOptions`), confirm "Replace exercise?" ("Sets already logged on this exercise will be removed.") if any completed set; `pickReplacement` (sheet with star = program's own exercise, swap icon = substitution, disabled if not in library or current, "Search the library" -> `/pick-exercise`; no options => straight to search); -> `repo.replaceExercise(old, info, coach, program)`.
- `superset`: if grouped -> `repo.leaveSuperset(id)` and if the group is left with one member also leave that one; else sheet "Superset with…" over other exercises -> `repo.superset(ex, picked)`.
- `targets`: sheet with Min/Max reps steppers (min clamp 1..max, max clamp min..50) -> `repo.setTargetReps(ex, RepRange)`; "this workout only (offered to the routine at Finish)".
- `form-reset`: `promptNumber("Form reset", kg, message "Progression restarts from this weight; heavier sessions before it stop counting.")`, initial = `suggestion.formResetHint` else last working top weight else first set weight; saves `gymRepository.setFormReset(exerciseId, weight, at: date of last session at/under weight)`; if no set completed, `repo.replaceExercise(old: ex, info, coach(sessionId), program)` to regenerate today's suggestion; SnackBar "Form reset: progression restarts from X kg".
- `weight-steps`: `editLoad` dialog (radio: stack / plate one side / plate both sides; first plate + step for stack; Max load optional) -> `gymRepo.setLoadType/setStack/setMaxLoad` (null = "Use default"). A gym change re-snaps unfinished sets (app.dart listener).
- `reorder`: sheet with `ReorderableListView` + Done -> `repo.reorderExercises(ids)`; `up/down` swap with neighbour via same call.
- `notes`: `promptText("Exercise notes", maxLines 3)` -> `repo.setExerciseNotes`. `howto`: `showFormCheckSheet` (1.18). `remove`: confirm "Remove exercise?" ("Its sets in this workout will be deleted.") -> `repo.removeExercise`.

**Minimize / resume**: Minimize chevron: close keypad (commit), save notes, `context.pop()` (or `go /home` if cannot pop). Session keeps running (it is DB state). `MiniWorkoutBar` (56 high, above NavigationBar in `_Shell`; shown whenever `activeSessionProvider` has a session on any tab): dumbbell, name, `WorkoutClock`, chevron-up; tap -> `push /workout`. Home/Train also show Resume buttons; `startWorkout` with an active session just `push /workout`.

**Finish** (`_finish`, lines 923-981), in order:
1. `_commit()` (or pending typed set id), close keypad, save notes, reload active.
2. A typed-but-unticked set is completed quietly.
3. If 0 completed working sets: confirm "No working sets completed" ("Complete at least one working set to finish, or discard this workout.") action Discard -> `_discard`; returns.
4. If pending (unticked) sets: confirm "Finish workout?" "`N` set(s) not completed will be dropped." action Finish.
5. `_offerRoutineUpdate` (only if session has `routineId`): skips if routine deleted, or session predates links (`routineExerciseId` all null and routine non-empty), or diff empty; else dialog **"Update routine?"** "This workout differs from the routine:" + bullet lines from `diffSessionAgainstRoutine`; buttons `Keep routine as is` (false) / `Update routine` (true -> `updateRoutineFromSession(db, routineId, session, catalog, program)`); dismissing (null) cancels the finish and stays in the workout.
6. `_finishing = true` -> `CalculatingResults`; `restTimer.stop()`; `Future.wait([finishService.finish(sessionId, now, catalog, settings, health: healthSourceProvider), delay(1800 ms)])`; `lastSummaryProvider.set(summary)`; `pushReplacement /summary`. On error: log, `_finishing=false`, SnackBar "Could not finish: $e".

**CalculatingResults** (`calculating_results.dart`): full-screen loader, min 1800 ms: 120 px ring (custom painter: grey ring + 5 px primary arc rotating 3 turns, arc length oscillates `pi*(0.5+0.5 sin(pi*t))`), dumbbell pulsing (scale 1+0.08 sin(6*pi*t)), text "Calculating your results" with animated 1-3 dots (`floor(t*9) % 3`), 220 px progress bar easeInOut. Reduce Motion: static ring/scale.

#### 1.10 After-workout chain: `/summary`, `/rank-sequence`, `/streak` (`workout/presentation/summary_screen.dart`, `after_workout_screens.dart`, `domain/after_workout.dart`)
Order rule (after_workout.dart): steps = [congrats(summary)] + [rank if `rankGains.isNotEmpty || overallRankUp != null`] + [streak if `streakGrew`]. After a step, `advanceAfterWorkout` does `pushReplacement` to the next step route, or `go /home` after the last. Every step has a `Skip` text button (top right) -> `go /home`. (The summary shows Skip only if more steps follow.) `rank-sequence` and `streak` use fade transitions (router.dart:94-109); summary uses default page transition.
- **Summary** (`SummaryScreen`; no summary => EmptyState "Nothing to show" + Home): sections staggered 70 ms apart (cap 560 ms delay, 320 ms each, fade+18 px slide) over a radial primary glow. Sections: Hero ("WORKOUT COMPLETE" + name), XP card (`CountUp` "+N XP" 1400 ms, "{xpSession} from sets and PRs · {xpBonus} bonus"; "LEVEL UP → N" pill pop if `levelAfter > levelBefore`), stats 2x2 (Duration, Effort "RPE x.x" or "—", Volume, PRs count gold if >0), PR cards (if any; two `heavyImpact` 120 ms apart starting 450 ms after build; each "e1RM X kg · was Y" and hard-coded "+50 XP"), Rank changes (only `rankChanges` with `up`; badge + "from → to" or "Placed: to"; plus quiet line `Slipped: <name to>, ... Ranks use your best e1RM of the last 90 days.` for `rankDowns`), Guardrail (override count banner "N override set(s) today" with details "Override sets earn no XP. If they also fell below the rep range they don't count for ranks or PRs."; per `flags` ego banner "<exercise>: progression frozen" with message + "Frozen until EEE d MMM."), Unlocks (achievements tiles; quests tiles with hard-coded "+40 XP"), health line ("Saved to Apple Health as Traditional Strength Training." / "Not saved to Apple Health (no write permission or Health unavailable)."). Bottom `BigButton` "Continue" (arrow) or "Done" (check) depending on `stepAfter`.
- **Rank step** (`RankStepScreen`): reads `lastSummaryProvider` once. If `overallRankUp != null`: first shows full-screen `RankUpScreen(changes: [up])` (rank agent); `onDone` flips to `RankSequenceScreen(title 'RANK PROGRESS', gains: [overall gains only when no rank-up] + exercise-scope gains)` with `onDone` = advance. Skip overlay on top.
- **Streak step** (`StreakStepScreen`): title STREAK, `StreakWeek(marks ∪ {today: workout}, today, stamp)` (stamp animation 1300 ms) then `FireStreak(from: streakBefore, to: streakAfter, height 220, startDelay 1300 ms)`; `Continue` button appears when FireStreak `onDone`. Reduce Motion: stamp value=1, no delay. (StreakWeek/FireStreak are gamification-agent widgets.)
- DESIGN.md says summary haptics `heavyImpact x2` for PRs: matches.

#### 1.11 Session detail: `/session/:id` (`features/history/presentation/session_detail_screen.dart`)
`sessionDetailProvider(id)` = `historyRepository.loadSession(id, catalog)` (re-evaluated when `historyProvider` changes). AppBar "Session" + delete icon -> confirm "Delete session?" ("Its sets, volume and session XP will be removed. Achievements already unlocked stay.") -> `historyRepository.deleteSession(id)` -> `pop`. Not found => EmptyState "Session not found".
Content: name, `EEEE d MMMM y · HH:mm`; stat card (Duration, Volume, XP "+N", Readiness score coloured by band). "Suspect sets" card (amber) when `suspectSetsProvider` non-empty: sets (sessions before `savedValuesFixedAt`, not imported) whose saved numbers equal the suggestion; text explains old keypad bug; those rows show "= the suggestion · tap to correct". Notes block, "Exercises" per exercise AppCard: header tap -> `push /exercise/{id}/history` (note: Stats tab); caption `"{Kind label} · {range} reps · suggested X kg"` (labels for `SuggestionKind` at lines 35-44: Calibration, Seeded from calibration, Weight increase, Hold weight, add reps, Reduced (−5%), Plateau deload (−10%), Ego freeze (−5%), No suggestion); set rows: badge `W` or working index, `"{kg} kg × {reps}[ + partials][ @ RPE x]"`, "Good override: heavier than suggested, inside the range" / `Override[: reason]` + ` · excluded from ranks` for ego sets, `e1RM x.x` (non-warm-up). Tap a completed set -> `_CorrectSetDialog` (KG signed-decimal, REPS int >=0) -> `historyRepository.correctSet(setId, weight, reps)` + `ref.invalidate(historyProvider)`. So **history edit = correct individual sets and delete whole session**; no add/remove sets, no name/date edit. Follow-up (drop/myo/hold) kinds are not distinguished in this screen (they show as numbered rows; OQ).
- Entry points: exercise Stats "best sets", exercise History tab, and `ProgressScreen` (progress_screen.dart:1018, rank agent). **There is no standalone history/calendar list screen in this tree** (PLAN.md lists a "calendar"; see OQ).

#### 1.12 Exercise history: `/exercise/:id/history`
Routes to `ExerciseDetailScreen(initialTab: stats)`; `ExerciseStatsTab` / `ExerciseSessionsTab` are defined in history/presentation (described in 1.6). Linked from session detail and ProgressScreen.

#### 1.13 Profile: `/profile` (`features/profile/presentation/profile_screen.dart`)
AppBar "Profile" + Settings gear -> `push /settings`. Cards: Level (ProgressRing 96 with "LVL"/number, RrBar with %, "xpIntoLevel / xpForNext XP to level N+1", total XP with locale grouping); two AppCards Streak ("N days", "Longest: N days") and This week (`sessionsThisWeek(history, now)`, "session(s) since Monday"); `_DisciplineCard` (ring; colour rule: >=85 green, >=70 yellow, else red; null = grey "—" with "Log sets with a suggestion to measure it."; verdicts "Mostly on the suggestion." / "Often a different weight than suggested." / "Mostly your own weights."; description text: "Working sets within ±5% of the suggestion, or heavier and still inside the rep range, last 30 days. Information only: it never earns or blocks anything."); Bodyweight card (value + source "Apple Health"/"Manual" + date, "tap to update"; or "Bodyweight not set"; tap -> `enterBodyweight`; overall RankBadge 44); Achievements: header "n/total", grouped by `AchievementCategory` (consistency, strength, volume, exploration, recovery, program; each with unlocked/total count), 3-column grid aspect 0.7 of `_AchievementTile` (hexagon medallion 72; locked = dark silhouette, faint icon, lock glyph, progress ring; level label BRONZE/SILVER/GOLD, unlock date). Tile tap -> AlertDialog with larger medallion, description, "family · level", "Unlocked d MMM yyyy" or progress bar. `achievementColor`: level bronze/silver/gold map to `tierColors[bronze/silver/gold]`; unlevelled by category (consistency primary, strength tier-coloured for bestExerciseTier/overallTier else `0xFFFFC93C`, volume `0xFFFF7A45`, exploration accent, recovery green, program xp). Icon name map `achievementIcon` lines 18-37 (17 names). Loading: `Skeleton(320)`.
- Home streak card links here (`go /profile`).

#### 1.14 Settings: `/settings` (+ `/settings/errors`, `/settings/import-liftoff`, debug) (`features/settings/presentation/settings_screen.dart`, `gym_equipment_card.dart`, `error_log_screen.dart`)
Sections in order (all inside `AppCard`s):
1. **Training**: Compound rep range (dialog with Minimum/Maximum counters: min >=1 and <= max; max >= min and <= 30; `ctrl.setCompoundRange`), Isolation rep range (`setIsolationRange`), Target reps in reserve counter 0..5 (`setDefaultRir`), Rest after compounds / isolations (`promptNumber` seconds; accepted only 15..900 -> `setRestCompound/Isolation`).
2. **My gym equipment** (`GymEquipmentCard`): Dumbbells (prompt text, format `from-to/step` e.g. `2.5-50/2.5` or comma list; invalid => SnackBar 'Use "from-to/step" or a list of weights'; `GymEquipment.parseDumbbells`/`describeDumbbells`), Smallest plate (number, accepted (0,25], `copyWith(smallestPlate)`; subtitle explains one-sided plate machines step = plate, two-sided and barbell step = `barbellStep` pair), Machines and cables default stack (dialog first plate + step; first >=0, step >0), then one dense row per per-exercise override (`typeOverrides`, `perExercise` keys) with an X resetting `setStack(id,null)` + `setLoadType(id,null)`. Saves via `gymRepositoryProvider.save(g.copyWith(...))`.
3. **Body**: Bodyweight tile (`promptNumber`; valid 30..300 else SnackBar "Enter a bodyweight between 30 and 300 kg"; `bodyWeightRepository.addManual`).
4. **Apple Health**: status tile (`health.name`, sync text: Syncing… / "Last sync failed: e" / "Not synced yet this session" / "Synced at HH:mm · d/N days with data[ · no body mass| · body mass X kg]"), "Sync now", "Request permissions again" (requestPermissions + setHealthRequested(true) + sync; SnackBar "Apple Health is not available on this device" if !ok; subtitle tells the user to change via Health app Sharing → Apps → Spotter).
5. **Notifications**: "Enable rest-timer alerts" -> `notificationService.requestPermission()`; SnackBar "Rest-timer alerts enabled" / "Notifications are off. Enable them in iOS Settings → Spotter."
6. **Program**: static description of the fixed Min-Max template (name from `programProvider`); optional "Set counts restored" tile (`ProgramRepository.restoredSetCounts(db)` list; legacy fix notice); "Reinstall my Min-Max routines" -> confirm "Replace routines?" -> `programRepository.installMyRoutines(program, definition: ProgramRepository.loadMyRoutines(), catalog, settings, now)`; SnackBar "Routines installed" or "Installed; skipped: a, b". **Replaces ALL routines** (history kept).
7. **Import**: "Import from Liftoff" -> `push /settings/import-liftoff`.
8. **Streak**: "Carried-over streak" tile (`streakOffsetProvider`; prompt days 0..5000; 0 deletes setting `StreakOffset.settingKey`, else stores `StreakOffset(date: existing date ?? today, days)`), "Last-chance reminder" switch (`ctrl.setStreakReminder`; subtitle "18:00 on the day you must train to keep the streak (after two rest days)"; the app.dart listener schedules/cancels).
9. **Export**: two buttons `Export JSON` / `Export CSV` -> `exportService.share(csv, origin: button rect)` (iPad popover origin) with busy spinner; failure SnackBar "Export failed: $e". Copy: "All sessions, sets and readiness days, with ISO timestamps and a schema_version." (Export format = other agent.)
10. **About**: tile "Spotter 1.0.0" ("All data stays on this iPhone. Long-press for the error log."); **long-press -> `push /settings/errors`** (available in release); Credits tile (static text: free-exercise-db, wger.de, ExerciseDB V1 free data, Jeff Nippard program videos, body map `react-native-body-highlighter (MIT)`); `kDebugMode` only: "Debug menu" -> `/settings/debug`.
- **Error log** (`ErrorLogScreen`): list newest first (`ErrorLog.instance.entries()` + live `changes` stream); card per entry (accent warning if `source == 'caught'` else danger): `d MMM HH:mm:ss · source · route`, error, first 6 stack lines in Courier 11; Clear (confirm "Clear the error log?") ; bottom `Copy all (N)` -> clipboard `exportText()` + SnackBar "Copied. Paste it into a message."; empty EmptyState "No errors". The router keeps `ErrorLog.instance.currentRoute` in sync via routerDelegate listener (router.dart:187-190).

#### 1.15 Liftoff import: `/settings/import-liftoff` (`features/import/presentation/liftoff_import_screen.dart`)
Three states in one screen. (a) Intro: card ("In Liftoff: Settings → Export data → CSV. Save the file to Files, then choose it here. Nothing is written until you confirm. Re-importing the same file adds only new workouts.") + `Choose CSV file` BigButton -> `liftoffCsvSourceProvider()` (file picker `.csv`, utf8 decode allowMalformed; overridable in tests) -> `liftoffImportService.preview(csv, catalog, manual)`. Errors: `FormatException.message` shown inline; other => ErrorLog + "Could not read that file: $e". (b) Preview: stat tiles New sessions / New sets; card with date range (`yMMMd → yMMMd`) or "No workouts in this file", counts line ("N sessions in the file · M already imported · K exercise names · R rows skipped (cardio, timed or empty)"), note "Imported sets count as taken to failure. They feed history, PRs, ranks and suggestions (from your last 2–3 sessions), not discipline stats or XP."; "Check these (n)" list = `preview.toReview` mappings; "All exercise names (n)" list showing first 8, "Show all n"/"Show fewer"; each `_MappingTile`: Liftoff name, "→ <exercise>" or "No match: becomes a custom exercise. Tap to pick one.", right label `METHOD [conf%]` (colour danger unmatched / warning fuzzy needing review), "N sets"; tap -> `push<String> /pick-exercise` -> `_manual[liftoffName] = id` and re-preview. Button "Import N sessions" (disabled "Nothing new to import"), "Choose a different file". Import: `_ensureBodyweight` (if `bodyWeightRepository.latest()==null`, prompt kg 30..300 with explanatory message, else error "Import needs a bodyweight between 30 and 300 kg."), then `service.commit(preview, catalog, settings, now)`. (c) Done: "IMPORT COMPLETE", "N sessions · M sets", optional "N custom exercises created", "Achievements unlocked: a, b"; `Done` -> `pop`.

#### 1.16 Debug (debug builds only; routes registered only under `kDebugMode`, router.dart:165)
`/settings/debug` DebugMenuScreen (fake Health toggle -> `setUseFakeHealth` + sync; recompute readiness; links to Error log, Media matching, Exercise audit, Rank badges & rank-up preview, Badge sheet; ExerciseDB V2 enable switch (`edbEnabledKey`) + usage card (calls/2000, warn/hard limits); Seed 12 weeks of history (confirm, `SeedGenerator.seed`, sets onboarded) / Wipe training data; table row counts). `/settings/debug/badges` (badge gallery + rank-up preview trigger), `/badge-sheet`, `/media` (MediaMatchingScreen: review unmatched/low-confidence 3D demos, export `media_overrides.json`), `/audit` (ExerciseAuditScreen), `/summary-preview` (SummaryScreen with `demoSummary()`), `/rank-up-preview` (`RankUpScreen(changes: demoRankUps(), loop: true)`). `edb_v2_review.dart` is an embedded widget (copy `edb_v2_map.json`), not routed. The `Routes` consts `badgeGallery/badgeSheet/mediaMatching/exerciseAudit` exist but there is no `summaryPreview/rankUpPreview` const (string-only). **Skip in RN port.**

#### 1.17 Tutorials / program presentation
- `ExerciseDemo` (`tutorials/presentation/exercise_demo.dart`): square (aspect 1) white framed container. `mediaMatchProvider(exerciseId)` (stream of `MediaMatchRow`): loading -> light shimmer; no `gifUrl` -> `ExerciseMuscleThumb` (generated body silhouette with muscles lit); has GIF -> `_GifPlayer`: GIF is **decoded into frames** via `gifCacheManager.getSingleFile(url)` + `ui.instantiateImageCodec`, frame durations <=10 ms treated as 100 ms, driven by a `Ticker` (not a native GIF view) supporting pause (tap image or pause pill), 0.5x speed pill (`1x`/`0.5×`); on error falls back to generated figure. Caption "3D demo: ExerciseDB · <edbName>". `compact` = smaller radius.
- `ExerciseThumb` (library): static still of first frame of the GIF (decoded at `targetWidth: 200`, `gifFirstFrameProvider`, cached per URL per session) on white square; falls back to `ExerciseMuscleThumb`. Comment: never a photo, never YouTube image, never animated.
- `showFormCheckSheet(context, exerciseId)` (in-workout "How to"): modal sheet (scrollable): name, `ExerciseDemo(compact)` max width 300, "Watch Jeff's demo" button revealing inline YouTube player (if `programVideosProvider[id]`), first 3 instruction bullets, `Exercise page` button (pops sheet then `push /exercise/{id}`).
- `ProgramVideoPlayer`: `youtube_player_iframe` (autoPlay false, start at link timestamp, fullscreen button, strictRelatedVideos, playsInline) + caption "Demo: Jeff Nippard · <programName> (Min-Max Program)". `programVideosProvider` maps exerciseId -> video for routine rows + program substitutions.
- `TechniqueChip` / `showTechniqueSheet` (`program/presentation/program_widgets.dart`): purple chip "LAST SET: <TECHNIQUE>" opening a sheet (name, `when`, description, "From the Min-Max Phase 2 program."). **No usage found in lib/** (dead code candidate; see OQ). Technique tags are shown in the set row and set menu instead.

---
### 2. USER FLOWS (end to end)

**F1 Onboarding.** Cold start -> `settingsProvider` loads -> router redirect (`!onboarded && not at /onboarding => /onboarding`) -> 3 pages -> `setOnboarded(true)` -> `/home` via refreshListenable. No routines exist after onboarding (Home shows "Create your first routine" -> Train); routines come from the user or Settings > "Reinstall my Min-Max routines". Health + notification permission are requested together on page 2 only.

**F2 Start workout.** Entry points: Home primary button (next routine in rotation), Train card `Start`, Train `Start empty workout`, Resume buttons, MiniWorkoutBar. `startWorkout` (workout_actions.dart:12-25): if `sessionRepository.activeSession() != null` -> just `push /workout`. Else load catalog, `coachContextBuilderProvider()` (coach context incl. readiness/recovery/history, `coach.now`), name = routine name or `"<EEEE> workout"`, program, `sessions.start(name, coach, catalog, routine, program)`, `frozenCoachProvider.freeze(id, coach)` (plan stays as at start; later "add exercise"/"replace" use `workoutCoachProvider(sessionId)`), then `push /workout`.

**F3 Logging a set** (all details in 1.9): focus KG/REPS cell -> custom keypad types into a buffer (commits on cell change/NEXT/tap outside/menu/app background/Finish) -> PREV tap or `Copy` key to copy numbers -> effort chip cycles F/1/2/3+ (long-press = +partials) -> ✓ button or swipe right to complete -> reason sheet only for too-heavy-and-below-range sets -> haptic lightImpact -> adaptation of later sets -> praise snackbar -> rest timer -> form-reset snackbar. Un-complete by tapping ✓ again (cancels the rest it started). Warm-ups: tagged W, 60% opacity, hideable (screen-wide), only a 90 s rest after the last one. Drop/myo/hold: added via set menu or `+ ANOTHER DROP/CYCLE`; no rest before drop/hold, 5 s before myo; drops pre-filled 20-25% lighter and follow parent weight edits (`refreshDrops`). Supersets: created from exercise menu (or routine editor link), A1/A2 labels with colour bar; no rest until the round (one set of each partner) is done then the longest member rest. Deleting: swipe left or set menu with 3 s Undo.

**F4 Rest timer / Live Activity / notifications.** Trigger points: `RestTimerController.start` (called from `_startRest`) writes `restEndsAt/restTotalSeconds` into settings (`settingsController.setRestTimer(endsAt, seconds)`, survives app kill), schedules a local notification `notificationService.scheduleRestDone(endsAt)`, stores a `RestActivity` (workoutName, exerciseName, nextTarget, startsAt, endsAt) and calls `workoutActivitySyncProvider.refresh()` (Live Activity). `adjust(+-15)` reschedules the notification and updates the activity end; if result <= now -> stop. `skip()` records `_skippedAt` (used for the rest marker) and stops. `stop()` clears settings, `cancelRest()` notification, activity. `resync()` on app resume forces a Live Activity refresh (iOS may have ended it). `cancelIfFor(setId, latestDone)` on un-ticking. Finish and Discard call `stop()`. UI: `WorkoutClock` (in the workout AppBar and MiniWorkoutBar) updates every 500 ms: shows elapsed `formatClock(now - startedAt)` in primary, or `REST m:ss` in accent on a tinted chip while resting; tap while resting -> `_RestSheet` (modal bottom sheet, progress ring 72, `-15`, `+15`, `Skip`; auto-closes when rest ends). At 0: `heavyImpact` once and `restTimer.stop()` (post-frame). The workout Live Activity itself also refreshes on `activeSessionProvider`/`catalogProvider` changes (app.dart). Streak reminder notification: separate, scheduled from `streakReminderProvider`.

**F5 Minimize/resume.** See 1.9. Navigation stack is [shell, /workout]; minimize pops (shell visible with MiniWorkoutBar); resume pushes again; swiping back (iOS) also pops.

**F6 Replace / add / remove exercise mid-workout, then routine diff.** Add: `Add exercise` -> pick mode library -> `addExercise` (1 set, defaults from settings). Replace: menu -> program subs sheet or library search -> removes logged sets after confirm -> `replaceExercise` with fresh coach. Remove: menu -> confirm. Target reps change: this workout only. At Finish, if the session came from a routine and differs (`diffSessionAgainstRoutine`: adds/removes/replacements/rep-range changes), dialog offers `Update routine` vs `Keep routine as is`; dismiss aborts finish.

**F7 Finish -> calculating -> rank-up -> streak -> summary.** Order actually shown: CalculatingResults (>=1.8 s) -> **Summary first** -> (if rank moved) Rank step [overall RankUpScreen if overall division/tier changed, then RankSequenceScreen per lift] -> (if streak grew) Streak step -> Home. Each is `pushReplacement`, so back never returns to the workout. Skip anywhere -> Home. (Spec text said "calculating -> rank-up -> streak -> summary": actual order is summary BEFORE rank/streak.)

**F8 History / session detail edit / delete.** Reach session detail from exercise Stats "Best sets", exercise History tab, or ProgressScreen. Edit = tap a completed set -> correct KG/REPS dialog (`historyRepository.correctSet`). Delete session from AppBar. Exercise delete only for custom exercises not used anywhere.

**F9 Library.** Search (name + aliases), filters (Favorites, Muscle sheet, Equipment sheet), favorite stars, tap -> detail; FAB Custom -> create form (routes `/exercise-new`); edit/delete from detail AppBar for custom ones; pick mode returns exercise id to caller.

**F10 Exercise detail tabs.** About / Rank / Stats / History, with Hero transition from list thumbnail, `Count toward ranks` switch, freeze banner. Opened also from: set-block thumbnail/name in workout, routine editor row, form-check sheet "Exercise page".

**F11 Routine editor.** See 1.8. Created on Train via FAB (name prompt) and immediately opened. Routine rows can be linked as supersets, replaced, targets edited, removed, reordered by drag.

**F12 Settings sections.** See 1.14. **F13 Profile.** See 1.13.

**F14 Liftoff import.** See 1.15. Preview is non-destructive; commit is idempotent for already imported sessions.

**F15 Export/share.** Settings > Export JSON / CSV -> OS share sheet (`share_plus` on origin rect). Error log: clipboard copy.

---
### 3. NAVIGATION MAP (`L/router.dart`)

Library: `go_router` 18, `initialLocation: /home`, `navigatorKey: rootNavigatorKey`, `refreshListenable: onboarded` (ValueNotifier<bool>).
Redirect (verbatim, router.dart:70-75):
```
final atOnboarding = state.matchedLocation == Routes.onboarding;
if (!onboarded.value && !atOnboarding) return Routes.onboarding;
if (onboarded.value && atOnboarding) return Routes.home;
return null;
```
| Path | Screen | Params | Presentation |
|---|---|---|---|
| `/onboarding` | OnboardingScreen | none | top-level |
| `/home`, `/train`, `/library`, `/progress`, `/profile` | shell branches (StatefulShellRoute, FadeBranches) | `/progress?...` query via `ProgressScreen.fromQuery(queryParameters)`; known use `tab=body&mode=recovery` (recovery_card.dart:55) | tabs |
| `/workout` | ActiveWorkoutScreen | none | root navigator (covers tab bar), default platform transition |
| `/rank-sequence` | RankStepScreen | none (reads `lastSummaryProvider`) | root, fade |
| `/streak` | StreakStepScreen | none | root, fade |
| `/summary` | SummaryScreen | none | root |
| `/ladder` | LadderScreen (ranks agent) | none | root; pushed from ProgressScreen |
| `/pick-exercise` | LibraryScreen(pickMode true) | returns `String` exercise id via pop | root |
| `/exercise-new` | CustomExerciseScreen | none | root |
| `/routine/:id` | RoutineEditorScreen | `id` int.parse | root |
| `/exercise/:id` | ExerciseDetailScreen | `id` is `Uri.encodeComponent`'d (ids contain `_`, `-`, spaces possibly) | root |
| `/exercise/:id/history` | ExerciseDetailScreen(initialTab stats) | | root |
| `/exercise/:id/edit` | CustomExerciseScreen(editId) | | root |
| `/session/:id` | SessionDetailScreen | int | root |
| `/settings` | SettingsScreen | | root |
| `/settings/errors` | ErrorLogScreen | | root; release too |
| `/settings/import-liftoff` | LiftoffImportScreen | | root |
| `/settings/debug` (+ `badges`, `badge-sheet`, `media`, `audit`, `summary-preview`, `rank-up-preview`) | debug screens | | debug builds only |
All non-shell routes use `parentNavigatorKey: rootNavigatorKey` (full screen above the tab bar; MiniWorkoutBar is part of the shell, so it is hidden when any of these is on top). Route builders: `Routes.exercise(id)`, `exerciseHistory`, `editExercise`, `routine(id)`, `session(id)`.
Navigation verbs used: `push` (detail screens, `/workout`, `/pick-exercise` expecting results), `go` (tabs, Home after chain, Train from empty states, `/progress`, `/profile`), `pushReplacement` (finish -> summary -> rank -> streak), `pop` (delete session, custom exercise save, pick result `context.pop(id)`, Done in import), `canPop()?pop:go(/home)` on minimize.
Back behaviour: iOS swipe-back on every pushed route (Cupertino page transitions, with Reduce-Motion no-animation wrapper); Android fade-forwards. Active workout has no confirm-on-back; leaving = minimize. `/summary` etc: back is possible via swipe? They are `pushReplacement` on top of the stack ([shell, summary]); swipe-back would pop to the shell (OQ: no WillPop guard seen).
Deep links: none registered in router (no scheme/universal link handling seen); the only query param is `/progress`'s `tab`/`mode`.
Hero transitions: library list thumbnail -> exercise About demo (`ex-hero-{id}`; shuttle shows the thumbnail).

---
### 4. REUSABLE UI COMPONENTS & HEAVY UI

#### 4.1 Design tokens (`core/theme/app_theme.dart`, DESIGN.md)
| Group | Tokens |
|---|---|
| Colours | background `#090C12`, surface `#11161F`, surfaceHigh `#18202D`, surfaceTop `#212B3B`, outline `#263043`, outlineBright `#34405A`, primary `#7CF29C`, accent `#5AB8FF`, warning `#FFC145`, danger `#FF5D6C`, textPrimary `#F2F5FA`, textSecondary `#9AA6BC`, textTertiary `#667189`, xp `#B98CFF`, hold `#4FD8C4`, green `#3DDC84`, yellow `#FFC145`, red `#FF5D6C`, unranked `#3A4255`, bodyBase `#1C2230`, restDay `#8FA3FF`, on-primary `#06210F`, PR gold `#FFC93C`, superset colours accent/xp/warning/`#FF7A45` |
| Tier colours (Iron..Immortal) | `#868986 #A5855D #BBC2C2 #ECCF56 #59A9B6 #B489C4 #6AE2AF #4F7DFF #BB3D65` (note: Champion/Olympian names; DESIGN.md table is outdated "Iron #8B8580 → Challenger") |
| Tier gradients | Iron `#B4B7B5->#5E6160`, Bronze `#D1B085->#7C5522`, Silver `#E6EBEB->#8E9696`, Gold `#F7E9A2->#C98F1E`, Platinum `#8FD8E0->#2B7F8C`, Diamond `#DDBDEB->#763BAF`, Champion `#A6F5CF->#1C7245`, Olympian `#FFD25E->#2F58D0`, Immortal `#FF6E8E->#A02D55` |
| Fonts | Oxanium (display/numbers; equal-width digits) and Barlow (UI); both bundled (OFL); `tabularFigures` where needed |
| Type | displayXL 44/800 h1.05; displayL 32/800; titleL 24/700; title 18/700; number 22/800; body 16/500 h1.35; bodyS 14/500; label 12/700 +1.2 tracking UPPERCASE |
| Spacing | 4 · 8 · 12 · 16 · 20 · 24 · 32 (`Space.xs..xxxl`); screen pad 16, card gap 12, card pad 16-18 |
| Radii | chip 10, control 14, card 20, sheet 28 |
| Motion | fast 150, base 250, slow 450 ms; enter curve easeOutCubic, pop easeOutBack; FadeSlideIn 40 ms x index (cap 10) + 280 ms, 14 px rise |
| Targets | >=48; primary 56-60; steppers 64 (StepperField) / 52 or 44 dense (StepperBox) |
| Theme overrides | AppBar bg background, title Oxanium 24/800, left-aligned; Card radius 20 outline border no elevation; FilledButton min 64x56 radius 14 Oxanium 17/800; OutlinedButton min 52 border outlineBright; TextButton min 48; SegmentedButton selected 18% primary; inputs filled surfaceHigh, radius 14, focus border primary 1.5; NavigationBar height 72, indicator primary 16%; TabBar indicator primary, Oxanium 15; bottom sheet radius 28 with drag handle; dialog title Oxanium 20/700; SnackBar floating |
Haptics (DESIGN.md + code): `selectionClick` keypad keys/stepper/muscle select; `lightImpact` set complete (code: lightImpact; DESIGN.md says mediumImpact, mismatch); `mediumImpact` praise; `heavyImpact` rest over, PR (x2), rank tier change on the exercise strip.

#### 4.2 `core/widgets`
- `common.dart`: `AsyncBody<T>` (data/loading `SkeletonList`/error text "Something went wrong:\n$e" in danger), `SectionHeader` (=SectionLabel), `AppCard` (wraps GameCard), `EmptyState(icon,title,message,action)`, `bandColor(ReadinessBand)`, `tierColor`, `tierGradient`, `TierBadge` (pill with `RankBadge`), `ProgressBar`, `StatTile`, `StepperField` (label + 64 px round - / + buttons + tappable value 34/900), `promptNumber`/`promptText` (AlertDialog with owned controller, autofocus, number keyboard, comma->dot, OK/Save), `confirm(title,message,action,destructive)` -> Future<bool>, `formatDuration` ("Xh MMm" or "Nm"), `formatClock` ("m:ss"/"h:mm:ss", negative prefix "-"), `SheetBody` (safe-area, max height 85%, scrollable, optional fixed header). Re-exports `core/domain/format.dart` and `game_ui.dart`.
- `game_ui.dart`: `GameCard` (3-stop diagonal gradient surface->lerped->darker; border outline or accent 45% at 1.4; optional glow shadow blur 24 alpha .18; `fill` override), `SectionLabel`, `RrBar` (tier gradient fill + glow + "N RR"/trailing text), `ProgressRing` (CustomPaint arc, sweep gradient from darkened to colour, round cap, starts at 12 o'clock), `DayDots` (7 states; 26 px circles with dumbbell/moon icons; labels M T W T F S S), `StreakLegend`, `Skeleton` (shimmer gradient sweeping 1300 ms loop) / `SkeletonList`, `CountUp` (integer tween with easeOutCubic 1400 ms default; zero under Reduce Motion), `BigButton` (60 px high despite doc "56"; glow shadow; `busy` spinner), `StepperBox` (long-press auto-repeat every 110 ms, selection haptic; dense 44/ normal 52 px; value in FittedBox; **not referenced in the files I read**, only StepperField is; OQ), `GuardrailBanner` (tone override/ego/info; 4 px left stripe; expandable details).
- `keyboard_dismisser.dart`: app-wide `Listener`+`NotificationListener`: pointer-up within `kTouchSlop` of pointer-down and outside the focused `EditableText`'s `InputDecorator` rect (inflated 2 px) unfocuses; a user drag scroll starting outside the text field unfocuses (dismiss-on-drag).
- `core/motion.dart`: `reduceMotion(context)` (iOS Reduce Motion via `MediaQuery.disableAnimations`), `motion(ctx, d)`, `FadeSlideIn`, `ReduceMotionTransitions`, `FadeBranches`.
- Other presentation helpers: `ExerciseThumb`, `ExerciseListTile`, `EmptyState`, `superset_style.dart` (`supersetLabels` -> map item id -> label "A1"/"B2" and colour for groups with >=2 members, colours cycle 4), `kindColor` (warmup warning, drop xp, myo accent, hold hold-teal, working textPrimary).

#### 4.3 Heavy custom UI / gestures / no clean React Native equivalent (for the Gaps section)
1. **In-app custom keypad with TapRegion groups**: the set table + keypad form one "tap region"; outside taps close it while committing; per-cell `GlobalKey`s + `Scrollable.ensureVisible` to keep the focused cell above the keypad; text typed in an in-memory buffer (no native text input, so no native keyboard is shown for KG/REPS). RN needs a custom keypad component, hit-testing for "outside tap", scroll-to-cell (`measure`), and committing on `AppState` change to background.
2. **Swipe-to-act rows** (`SwipeSetRow`): custom two-direction swipe with partial reveal, full-swipe delete threshold (60% of width or velocity), swipe-right action with spring-back; only horizontal drags claimed, so vertical scroll must still win. RN: `react-native-gesture-handler` Swipeable/Pan + Reanimated with `activeOffsetX`/`failOffsetY`.
3. **GIF decoded to frames and driven by a ticker** (play/pause, 0.5x) + first-frame still thumbnails with per-URL decode cache; no native animated GIF speed control. RN: `expo-image`/`react-native-fast-image` cannot change speed or pause; needs frame extraction or video re-encode (`react-native-video` with rate).
4. **CustomPainters**: `ProgressRing` (sweep-gradient arc), CalculatingResults ring, hex medallion with blur glow & HSL shading (`_HexPainter`), anatomy body graphs / badges / fire (other agents). RN: `react-native-svg` (+ gradients), `@shopify/react-native-skia` for blur glow/sweep gradients.
5. **Glow/shadow on cards and bars**: coloured soft shadows (blur 8-24, spread -2), `Ink` gradient card, layered 3-stop gradient. RN: Skia or SVG; iOS `shadowColor` works but Android elevation does not colour.
6. **Hero shared-element transition** library thumb -> detail demo (with custom shuttle). RN: `react-native-reanimated` shared transitions (unstable) or skip.
7. **Stateful tab shell with fade and Offstage/TickerMode**: all five tabs mounted and paused when hidden (`FadeBranches`); MiniWorkoutBar docked above the tab bar. RN: bottom-tabs with `lazy:false` + `freezeOnBlur` and a custom tab bar wrapper.
8. **Live Activity** (rest timer + workout; `core/live_activity`, not read here) and **local notifications scheduled with exact end time** that survive app kill (end time in settings): needs native ActivityKit module/Widget extension; Expo/RN lacks first-party support.
9. **YouTube iframe player** (`youtube_player_iframe`, start offset, fullscreen): RN `react-native-youtube-iframe` (WebView).
10. **iOS-style Reduce Motion handling** everywhere (`reduceMotion` gating durations and page transitions): `AccessibilityInfo.isReduceMotionEnabled` + listener.
11. **Reorderable lists** (routines on Train, routine editor, workout reorder sheet) with drag handles. RN: `react-native-draggable-flatlist`.
12. **Haptics**: `selectionClick`, `lightImpact`, `mediumImpact`, `heavyImpact` (expo-haptics equivalents exist).
13. **Charts**: `fl_chart` LineChart with touch tooltip, curved, area fill (other screens use charts too: progress agent). RN: `victory-native`/`react-native-gifted-charts`/Skia.
14. **Modal bottom sheets** used ~15 times (scrollable with fixed header, `useSafeArea`, `isScrollControlled`, sheets that return values); **AlertDialogs that own TextEditingControllers** (to avoid disposing during fade-out; not an RN concern). RN: `@gorhom/bottom-sheet`/`Modal`.
15. **Snackbars with actions/undo and per-snackbar `persist:false` 3 s**: RN has no built-in; need a toast with action.
16. **Number formatting / time**: tabular figures for timers (Oxanium equal-width digits); RN font loading of Oxanium/Barlow with weights 600-800.
17. **File picker + share sheet + clipboard** (`file_picker`, `share_plus` with iPad popover origin rect, `Clipboard`).
18. **Pull-to-refresh** on Home triggers Health sync.

---
### 5. OPEN QUESTIONS

- OQ: `ExerciseTab.history` vs `Routes.exerciseHistory` (`/exercise/:id/history`) opens `ExerciseTab.stats`, while a separate "History" tab exists; naming is ambiguous. Route comment doesn't say whether stats-first is intended.
- OQ: No standalone history list / calendar screen exists in the files I read, though PLAN.md lists `history/ {calendar, session detail, per-exercise charts}`. Session lists come from ProgressScreen (progress_screen.dart:1018, rank agent). Confirm whether Progress contains the session list/calendar.
- OQ: Order of after-workout screens: code is Summary -> Rank -> Streak (after_workout.dart); the task brief listed "rank-up -> streak -> summary". Code taken as authoritative.
- OQ: `TechniqueChip`/`showTechniqueSheet` have no references under `lib/` (dead code?). `StepperBox` (game_ui) also appears unused in the files I read (workout uses `StepperField`); `TierBadge`, `ProgressBar`, `bandColor` usage not verified (may be used by other agents' files); `Routes.rankSequence` etc. fine.
- OQ: DESIGN.md is stale vs code: refers to `LpBar` (code: `RrBar`, "RR" not "LP"), tier colours "Iron #8B8580 -> Challenger" (code: 9 tiers Iron..Immortal with Champion/Olympian, Valorant-like), "Set completed haptic mediumImpact" (code uses `lightImpact` on ✓; mediumImpact only for praise), "BigButton 56 px" (code 60), `Motion` class lacks `slow` use, PLAN.md says RPE chip/coach strip layout ("TARGET" prefix, steppers) which no longer matches the compact SET/PREV/KG/REPS/EFFORT table, PLAN.md pins `shared_preferences` for the onboarded flag while app.dart reads `settings.onboarded` from the DB. Treat DESIGN.md/PLAN.md as historical.
- OQ: The Streak model is **day-based with rest days** (home_screen/onboarding text), while DESIGN.md/PLAN.md and some Settings strings ("Weeks before that date are not checked against your goal" in the carried-over streak prompt, settings_screen.dart:409) refer to weekly goals/weeks; stale string?
- OQ: Summary screen hard-codes "+50 XP" per PR and "+40 XP" per quest (summary_screen.dart:282, 410; Home also "+40 XP each"); real XP constants live in gamification domain (not verified equal).
- OQ: Custom exercise creation from pick mode: `CustomExerciseScreen` pops with no value, so after creating you return to the picker without auto-selecting the new exercise (callers get no id). Intended?
- OQ: `/summary`, `/rank-sequence`, `/streak` have no back-guard; swipe-back after `pushReplacement` would reveal the shell (not the workout). Not verified whether `PopScope` exists inside `RankSequenceScreen`/`RankUpScreen`/`FireStreak`.
- OQ: Session detail does not display drop/myo/hold labelling (all rows numbered by `index` among non-warm-ups, `HistSet` may have `kind`); unverified whether follow-up sets appear in `HistExercise.sets`.
- OQ: Weight-steps menu is hidden only for dumbbell/bodyweight `EquipmentKind`; the settings text claims machines use "Override per exercise from its menu". Behaviour for `EquipmentKind.other` unclear.
- OQ: `_ExportButton.share(origin)` and iPad popover only matter on iPad; app is iPhone-only per copy ("Everything stays on this iPhone"), confirm target devices for RN.
- OQ: `Credits` tile mentions `react-native-body-highlighter (MIT)` for the Body map (settings_screen.dart:210), but the Flutter app draws its own `anatomy_graph`; either the body map assets were derived from that RN library (useful for the port) or the string is stale. Check anatomy_graph (ranks agent).
- OQ: `PrevSets.forSet` and the `Copy` key rely on `historyProvider.sessions.reversed...firstOrNull` meaning "most recent finished session containing the exercise" (including imported Liftoff sessions); I assumed ordering oldest->newest by `startedAt`; not verified in `HistoryRepository`.
- OQ: `WorkoutClock` buzzes/stops the rest only while a `WorkoutClock` widget is mounted (workout screen or MiniWorkoutBar). If the user is on a shell tab with no active session shown, expiry relies on the notification and `restEndsAt` only; `restTimer.stop()` on expiry never runs (stale `restEndsAt` in settings until next start/resume). Check if `workout_activity_sync` clears it.

---

# Appendix D2. Data models, persistence, pipelines, import/export and media

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `D2 §n`).

## SEC D2: Data models, persistence, repositories, import/export, program, library, tutorials/media

Scope: Flutter app `/Users/hassan/IdeaProjects/spotter-app` (analysis only). Paths below are relative to that root. Code wins over docs; disagreements are listed as `OQ:` in section 3. Where a quoted block is marked "(condensed)" the original has one item per line; values are identical.

---------------------------------------------------------------------------------------------------
## 1. DATA MODELS
---------------------------------------------------------------------------------------------------

### 1.0 Storage engine facts (drift / SQLite)

- Engine: drift on SQLite, file `Documents/spotter.sqlite` (`driftDatabase(name: 'spotter')`) (`lib/core/db/database.dart:33-34`).
- `DateTimeColumn` is stored as **INTEGER unix seconds** (`"store_date_time_values_as_text": false` in `drift_schemas/drift_schema_v12.json` options): sub-second precision is lost; values come back as local `DateTime`. Bool columns are `INTEGER 0/1 CHECK (x IN (0,1))`. JSON-ish columns are plain TEXT.
- `PRAGMA foreign_keys = ON` in `beforeOpen` (`database.dart:111-113`). FKs exist only where `references(...)` is written (below).
- `schemaVersion` = **12** (`database.dart:36-37`). Schema snapshots: `drift_schemas/drift_schema_v1.json` .. `v12.json` (12 files); generated test helpers `test/generated_migrations/schema_v1..v12.dart` + `schema.dart`.
- Custom indexes (NOT in the drift schema JSON; created with `customStatement`):

```dart
lib/core/db/database.dart:41-48
          await m.createAll();
          await customStatement('CREATE INDEX idx_sessions_started ON sessions (started_at)');
          await customStatement('CREATE INDEX idx_session_ex_session ON session_exercises (session_id)');
          await customStatement('CREATE INDEX idx_session_ex_exercise ON session_exercises (exercise_id)');
          await customStatement('CREATE INDEX idx_sets_session_ex ON workout_sets (session_exercise_id)');
          await customStatement('CREATE INDEX idx_routine_ex_routine ON routine_exercises (routine_id)');
          await customStatement(_externalIdIndex);
```
```dart
lib/core/db/database.dart:116
  static const _externalIdIndex = 'CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_external ON sessions (source, external_id)';
```
  Only `onCreate` creates the 5 non-unique indexes; `onUpgrade` creates only `idx_sessions_external` (at v4). See OQ-1.
- Settings KV helpers (`database.dart:120-131`): `getSetting(key)`, `putSetting` (insertOnConflictUpdate), `deleteSetting`, `watchSettings()` -> `Map<String,String>` stream.

### 1.1 Tables (16). Source `lib/core/db/tables.dart`. SQL column names are snake_case of the Dart getter; table names snake_case plural.

Legend: PK primary key; `?` nullable; `=v` default; `since vN` added by migration step N.

#### exercises (`tables.dart:4-33`) PK `id` TEXT (not autoincrement)
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | no | | dataset id (`Barbell_Bench_Press_-_Medium_Grip`), `sp_*`, `wger_<id>`, `edbv1_<id>`, `liftoff_<slug>`, `custom_<microsecondsSinceEpoch>` |
| name | TEXT | no | | |
| primary_muscles | TEXT JSON list | no | `'[]'` | dataset muscle names (17 values, `datasetMuscles` `muscle_mapping.dart:7-25`) |
| secondary_muscles | TEXT JSON list | no | `'[]'` | |
| equipment | TEXT | yes | | dataset equipment ("barbell","dumbbell","cable","machine","body only","e-z curl bar","bands","kettlebells","medicine ball","exercise ball","foam roll","other") |
| level | TEXT | yes | | |
| mechanic | TEXT | yes | | `compound` / `isolation` (null => non-compound) |
| category | TEXT | yes | | |
| instructions | TEXT JSON list | no | `'[]'` | |
| images | TEXT JSON list | no | `'[]'` | free-exercise-db repo-relative paths only |
| is_custom | BOOL | no | false | |
| is_favorite | BOOL | no | false | preserved across re-seed |
| notes | TEXT | yes | | |
| extra_images | TEXT JSON list | no | `'[]'` | since v7; full URLs (wger etc.) |
| source | TEXT | yes | | since v7; `fedb`/`wger`/`edb_v1`/`custom` |
| credit | TEXT JSON | yes | | since v7; list of `{source, license, author, images}` |
| edb_v1_id | TEXT | yes | | since v7; own ExerciseDB V1 GIF id |

#### routines (`tables.dart:35-43`) PK `id` INTEGER autoincrement
`name` TEXT; `position` INT =0; `created_at` DATETIME; `program_day` TEXT? (since v3, e.g. `upper`).

#### routine_exercises (`tables.dart:45-75`) PK `id` autoinc
| column | type | null | default | notes |
|---|---|---|---|---|
| routine_id | INT | no | | FK routines.id **ON DELETE CASCADE** |
| exercise_id | TEXT | no | | FK exercises.id (no cascade) |
| position | INT | no | | |
| rep_min, rep_max | INT | no | | |
| target_sets | INT | no | | |
| rest_seconds | INT | no | | |
| target_rir | INT | no | 2 | |
| program_slots | TEXT JSON list of slot ids | yes | | since v3 |
| program_relation | TEXT | yes | | since v3: `program`/`substitution`/`swap`/`extra` |
| program_exercise | TEXT | yes | | since v3: program exercise name stood in for |
| display_name | TEXT | yes | | since v3: owner's name |
| override_rep_min / override_rep_max | INT | yes | | since v8: routine-level rep range overriding program ranges; null = follow program |
| superset_group | INT | yes | | since v8: group id = id of first row of the group |

#### sessions (`tables.dart:77-96`) PK `id` autoinc
| column | type | null | default | notes |
|---|---|---|---|---|
| routine_id | INT | yes | | **no FK** (can dangle) |
| name | TEXT | no | | |
| started_at | DATETIME | no | | |
| ended_at | DATETIME | yes | | |
| notes | TEXT | no | `''` | |
| status | TEXT | no | `'active'` | `active`/`finished` |
| readiness_score | INT | yes | | snapshot at start (null while calibrating) |
| readiness_band | TEXT | yes | | `green`/`yellow`/`red` |
| health_synced | BOOL | no | false | |
| xp_earned | INT | no | 0 | written at finish |
| source | TEXT | no | `'app'` | since v4: `app`/`liftoff` |
| external_id | TEXT | yes | | since v4: Liftoff Date string |
Unique index `idx_sessions_external (source, external_id)` (NULL external ids of app sessions never collide). Index `idx_sessions_started (started_at)` (onCreate only).

#### session_exercises (`tables.dart:98-133`) PK `id` autoinc
`session_id` INT FK sessions.id **CASCADE**; `exercise_id` TEXT FK exercises.id; `position` INT; `notes` TEXT =`''`; `rep_min`,`rep_max`,`target_sets`,`rest_seconds` INT not null; `target_rir` INT =2; `suggestion_kind` TEXT =`'none'` (values per docs: calibration, seeded, increase, addReps, reduce, plateauDeload, egoFreeze, none); `suggested_weight` REAL?; `suggested_reps` INT?; `suggested_sets` INT?; `suggestion_json` TEXT? (shape in 2.1.3); `program_slots` TEXT? JSON list (v3); `program_week` INT? (v3, no longer written); `display_name` TEXT? (v3); `rest_enabled` BOOL =true (v5); `superset_group` INT? (v5); `routine_exercise_id` INT? (v8, **no FK**; link for "Update routine"); `targets_edited` BOOL =false (v8).
Indexes (onCreate only): `idx_session_ex_session (session_id)`, `idx_session_ex_exercise (exercise_id)`.

#### workout_sets (`tables.dart:135-174`) PK `id` autoinc
| column | type | null | default | since | notes |
|---|---|---|---|---|---|
| session_exercise_id | INT | no | | | FK session_exercises.id CASCADE |
| position | INT | no | | | negative values used transiently for added warm-ups; `_renumber` rewrites 0..n-1 |
| is_warmup | BOOL | no | false | | |
| weight | REAL | no | 0 | | external load kg (negative = assisted) |
| reps | INT | no | 0 | | for `hold` sets stores seconds |
| rpe | REAL | yes | | | |
| completed | BOOL | no | false | | |
| completed_at | DATETIME | yes | | | |
| suggested_weight | REAL | yes | | | null for warm-ups / calibration |
| suggested_reps | INT | yes | | | |
| is_override | BOOL | no | false | | |
| override_reason | TEXT | yes | | | `feltStrong`/`testingMax`/`justDidIt` |
| target_rep_min / target_rep_max | INT | yes | | v3 | per-set prescription |
| target_rir | INT | yes | | v3 | |
| technique | TEXT | yes | | v3 | e.g. `drop_sets_2x25` |
| set_type | TEXT | yes | | v5 | null = working/warm-up; `drop`, `myo`, `hold` |
| partials | BOOL | no | false | v9 | informational |
| adjusted_from | REAL | yes | | v11 | planned weight before auto-adjust |
| adjust_reason | TEXT | yes | | v11 | |
| rest_seconds | INT | yes | | v12 | rest actually taken before this set |
Index (onCreate only): `idx_sets_session_ex (session_exercise_id)`.

#### daily_metrics (`tables.dart:176-195`) PK `date` TEXT `yyyy-MM-dd`
`hrv_ms` REAL?; `resting_hr` REAL? (Dart `restingHr`); `sleep_minutes` REAL?; `active_energy_kcal` REAL?; `dietary_kcal` REAL? (v10); `protein_g` REAL? (v10); `readiness_score` INT?; `readiness_band` TEXT?; `calibrating` BOOL =true; `explanation` TEXT =`''`; `updated_at` DATETIME not null.

#### body_weights (`tables.dart:197-202`) PK autoinc: `measured_at` DATETIME; `kg` REAL; `source` TEXT (`health`/`manual`).
#### ego_freezes (`tables.dart:204-211`) PK autoinc: `exercise_id` TEXT (no FK); `started_at` DT; `until` DT; `base_weight` REAL; `reason` TEXT.
#### xp_events (`tables.dart:213-220`) PK autoinc: `at` DT; `amount` INT; `reason` TEXT (`session`,`quest`); `session_id` INT? (no FK); `week_start` TEXT? (yyyy-MM-dd).
#### achievements_unlocked (`tables.dart:222-228`) PK `key` TEXT; `unlocked_at` DT.
#### quests (`tables.dart:230-237`) PK autoinc: `week_start` TEXT (Monday yyyy-MM-dd); `key` TEXT (QuestKey name); `params` TEXT JSON =`'{}'`; `title` TEXT; `completed_at` DT?.
#### app_settings (`tables.dart:239-245`) PK `key` TEXT; `value` TEXT. KV store; known keys in 1.4.
#### media_matches (`tables.dart:247-264`, data class `MediaMatchRow`; since v2) PK `exercise_id` TEXT
`edb_id` TEXT?; `edb_name` TEXT?; `gif_url` TEXT?; `confidence` REAL =0; `source` TEXT =`'auto'` (declared `auto | override | manual`; code also writes `library`, OQ-9); `updated_at` DT.
#### pinned_videos (`tables.dart:266-277`; since v2) PK `exercise_id`
`video_id` TEXT; `title` TEXT =`''`; `channel` TEXT =`''`; `start_seconds` INT =0; `pinned_at` DT. **Unused feature** (DECISIONS: "`pinned_videos` table stays, unused"); only touched by ExerciseMerger.
#### edb_v2_maps (`tables.dart:279-301`, data class `EdbV2Map`; since v6) PK `exercise_id`
`edb_id` TEXT?; `status` TEXT (`auto`/`confirmed`/`queued`/`none`); `confidence` REAL =0; `query` TEXT =`''`; `candidates` TEXT JSON =`'[]'` (always written `'[]'`, OQ-10); `updated_at` DT.

#### Relationships
routines 1-N routine_exercises (cascade); exercises 1-N routine_exercises / session_exercises (no cascade); sessions 1-N session_exercises 1-N workout_sets (cascade). Soft (unenforced) links: `sessions.routine_id`, `session_exercises.routine_exercise_id`, `xp_events.session_id`, `ego_freezes.exercise_id`, `media_matches/pinned_videos/edb_v2_maps.exercise_id`. `routines.program_day` and `program_slots` reference ids in `assets/programs/min_max_canonical.json`.

### 1.2 Migration history (v1 -> v12), quoted from `onUpgrade` (`database.dart:50-110`)

v1 (initial, `drift_schemas/drift_schema_v1.json`): 13 tables (exercises, routines, routine_exercises, sessions, session_exercises, workout_sets, daily_metrics, body_weights, ego_freezes, xp_events, achievements_unlocked, quests, app_settings) with only the columns not tagged "since" above.

```dart
lib/core/db/database.dart:52-109
          if (from < 2) {
            await m.createTable(mediaMatches);
            await m.createTable(pinnedVideos);
          }
          if (from < 3) {
            await m.addColumn(routines, routines.programDay);
            await m.addColumn(routineExercises, routineExercises.programSlots);
            await m.addColumn(routineExercises, routineExercises.programRelation);
            await m.addColumn(routineExercises, routineExercises.programExercise);
            await m.addColumn(routineExercises, routineExercises.displayName);
            await m.addColumn(sessionExercises, sessionExercises.displayName);
            await m.addColumn(sessionExercises, sessionExercises.programSlots);
            await m.addColumn(sessionExercises, sessionExercises.programWeek);
            await m.addColumn(workoutSets, workoutSets.targetRepMin);
            await m.addColumn(workoutSets, workoutSets.targetRepMax);
            await m.addColumn(workoutSets, workoutSets.targetRir);
            await m.addColumn(workoutSets, workoutSets.technique);
          }
          if (from < 4) {
            await m.addColumn(sessions, sessions.source);
            await m.addColumn(sessions, sessions.externalId);
            await customStatement(_externalIdIndex);
          }
          if (from < 5) {
            await m.addColumn(workoutSets, workoutSets.setType);
            await m.addColumn(sessionExercises, sessionExercises.restEnabled);
            await m.addColumn(sessionExercises, sessionExercises.supersetGroup);
          }
          if (from < 6) {
            await m.createTable(edbV2Maps);
          }
          if (from < 7) {
            await m.addColumn(exercises, exercises.extraImages);
            await m.addColumn(exercises, exercises.source);
            await m.addColumn(exercises, exercises.credit);
            await m.addColumn(exercises, exercises.edbV1Id);
          }
          if (from < 8) {
            await m.addColumn(routineExercises, routineExercises.overrideRepMin);
            await m.addColumn(routineExercises, routineExercises.overrideRepMax);
            await m.addColumn(routineExercises, routineExercises.supersetGroup);
            await m.addColumn(sessionExercises, sessionExercises.routineExerciseId);
            await m.addColumn(sessionExercises, sessionExercises.targetsEdited);
          }
          if (from < 9) {
            await m.addColumn(workoutSets, workoutSets.partials);
          }
          if (from < 10) {
            await m.addColumn(dailyMetrics, dailyMetrics.dietaryKcal);
            await m.addColumn(dailyMetrics, dailyMetrics.proteinG);
          }
          if (from < 11) {
            await m.addColumn(workoutSets, workoutSets.adjustedFrom);
            await m.addColumn(workoutSets, workoutSets.adjustReason);
          }
          if (from < 12) {
            await m.addColumn(workoutSets, workoutSets.restSeconds);
          }
```
Summary: v2 media_matches+pinned_videos; v3 program columns; v4 session source/external_id + unique index; v5 set_type, rest_enabled, session superset_group; v6 edb_v2_maps; v7 library merge columns; v8 routine overrides/supersets + session->routine link + targets_edited; v9 partials; v10 dietary_kcal/protein_g; v11 adjusted_from/adjust_reason; v12 rest_seconds. No data backfills inside migrations (new columns rely on defaults; v4 `source` default `'app'` marks old sessions). Tests: `test/data/migration_test.dart` (v1->current creates media tables; each step; v6->v7 keeps exercise ids/history; v1->v12 in one go).

### 1.3 Startup order and data fixes (each guarded by a setting so it runs once)

```dart
lib/bootstrap.dart:16-31
Future<void> bootstrapDatabase(AppDatabase db) async {
  if (!ExerciseMuscleTable.isLoaded) ExerciseMuscleTable.load(await rootBundle.loadString('assets/exercise_muscles.json'));
  await ExerciseRepository(db).ensureSeeded();
  await ExerciseMerger(db).apply(); // duplicate library entries → one canonical exercise (history merged)
  await ProgramRepository.ensureMyRoutinesInstalled(db);
  await ProgramRepository.ensureCanonicalWeek(db);
  await ProgramRepository.ensureProgramSupersets(db);
  await ProgramRepository.ensureRoutineSetCounts(db);
  await ProgramRepository.ensureSingleArmReverseFly(db);
  await DataFixes.runAll(db);
  await HistoryRepository.markSavedValuesFixed(db, DateTime.now());
  await GymRepository.ensureSmallestPlate(db);
  await RankExclusions.ensureMigrated(db);
  // ExerciseDB V2 mappings survive a reinstall through the bundled asset.
  await EdbMappingRepository(db).seedFromAsset(await rootBundle.loadString(EdbMappingRepository.assetPath),
      now: DateTime.now(), skip: {for (final m in await ExerciseMerger.loadAsset()) m.duplicate});
}
```
Runs before the first frame (shared with integration tests). Not in bootstrap: `MediaRepository.ensureMatched` (needs catalog), `migrateRankLadder`, `GamificationRepository.ensureQuests`.

`lib/core/db/data_fixes.dart`:
```dart
lib/core/db/data_fixes.dart:10-28
  static const lungeKey = 'fix_lunge_per_dumbbell_v1';
  static const lungeV2Key = 'fix_lunge_per_dumbbell_v2';
  static const lungeExerciseId = 'sp_db_walking_lunge';
  static Future<int> ensureLungePerDumbbell(AppDatabase db) async {
    if (await db.getSetting(lungeKey) != null) return 0;
    final ids = liftoffTotalLoadIds.map((id) => "'$id'").join(',');
    final changed = await db.customUpdate(
      '''UPDATE workout_sets SET weight = weight / 2
         WHERE session_exercise_id IN (
           SELECT se.id FROM session_exercises se JOIN sessions s ON s.id = se.session_id
           WHERE se.exercise_id IN ($ids) AND s.source = '$liftoffSource')''',
      updates: {db.workoutSets},
    );
    await db.putSetting(lungeKey, '$changed');
    return changed;
  }
```
Round 2 (`data_fixes.dart:37-89`, key `fix_lunge_per_dumbbell_v2`): runs v1 first; `m` = MAX(weight) of imported (source liftoff) Walking Lunge sets; if `m != null && m > 0`: `limit = m * 1.5`; every non-imported Walking Lunge set with `weight > limit OR suggested_weight > limit` has weight and suggested_weight halved (each only if over limit); non-imported `session_exercises` of that exercise whose `suggested_weight > limit` get halved weight and every `NN kg` figure > limit in `suggestion_json` rewritten via regex `(\d+(?:\.\d+)?) kg`. Stores changed-count.
```dart
lib/core/db/data_fixes.dart:91-94
  /// Half of a total load, down to a dumbbell step (2.5 kg): 35 → 17.5, 37.5 → 17.5.
  static double _half(double total) => ((total / 2 / 2.5) + 1e-9).floorToDouble() * 2.5;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
```
Other one-time conversions: see 2.4 (program), 2.8 (ranks), `GymRepository.ensureSmallestPlate` (stored smallest plate 2.25 -> `GymEquipment.defaultSmallestPlate` (2.5); key `smallest_plate_2_5`).

### 1.4 app_settings keys seen in this area
| key | value | where |
|---|---|---|
| `exercise_dataset_version` | int string (5) | `library/data/exercise_repository.dart:16` |
| `media_match_version` | int string (4) | `tutorials/data/media_repository.dart:39` |
| `exercise_merges_log` | JSON list of `{duplicate,duplicate_name,canonical,canonical_name,history_rows,routine_rows}` | `exercise_merger.dart:52,77-92` |
| `program_routines_installed` | int string = my_routines.json schema_version (2) | `program_repository.dart:14,254` |
| `program_start_monday` | legacy; deleted by canonical-week conversion | `:13` |
| `program_canonical_week` | "5" | `:30` |
| `routine_set_counts_restored` | JSON list of strings | `:71` |
| `pull_single_arm_reverse_fly` | ISO datetime | `:128` |
| `program_supersets_applied` | "1" | `:150` |
| `fix_lunge_per_dumbbell_v1` / `_v2` | changed row count | data_fixes |
| `saved_values_fixed_at` | ISO datetime | `history_repository.dart:129` |
| `liftoff_imported_at` | ISO datetime | `liftoff_import_service.dart:23` |
| `streak_offset` | JSON `{"date":"yyyy-MM-dd","days":int}` | `gamification/domain/streaks.dart:14-16` |
| `rank_manual` (JSON map id->bool), `rank_auto_on` (sorted JSON list), `rank_policy_v2` (ISO), `rank_excluded_exercises` (legacy list) | | `ranks/data/rank_exclusions.dart:43-46` |
| `rank_ladder_version` ("8"), `rank_tier_rename_v8` ("1") | | `ranks/data/ladder_migration.dart:13-15` |
| `gym_equipment` (GymEquipment JSON incl. `type_overrides`,`per_exercise`,`max_loads`), `form_resets` (JSON map id->{weight,at ISO}), `form_reset_offered` (JSON int list, latest 300), `smallest_plate_2_5` ("1") | | `coach/data/gym_repository.dart:13-14,58` |
| `edb_v2_enabled` ("true" = on), `edb_budget` (JSON), `edb_log` (JSON list, max 100) | | `edb_providers.dart:11`, `edb_client.dart:161-163` |
| `SettingsModel.kFakeHealth` | "true" (set by the seed generator) | `seed_generator.dart` |

### 1.5 Bundled JSON assets (`assets/`, loaded with `rootBundle.loadString`)

| file | size | shape | counts | loader / versioning |
|---|---|---|---|---|
| `exercises.json` | 1.0 MB | **array** of free-exercise-db entries `{id,name,force,level,mechanic,equipment,primaryMuscles[],secondaryMuscles[],instructions[],category,images[]}` | 876 | `ExerciseRepository.ensureSeeded`; re-imported when `exerciseDatasetVersion` differs from stored |
| `extra_exercises.json` | 5 KB | `{schema_version:1,description,exercises[]}` same shape; ids `sp_*` plus `liftoff_one_arm_machine_reverse_fly` | 9 | same seeding (source `fedb`) |
| `library_sources.json` | 807 KB | `{schema_version:1,description,attach:{<existingId>:{images[],credits[],edb_v1_id}},exercises:[{id,source:wger\|edb_v1,name,equipment,primaryMuscles,secondaryMuscles,category,instructions,images,credit{source,license,author,images[]},edb_v1_id?}]}` | attach 513; new 1488 (wger 738, edb_v1 750) | same seeding; built by `tool/library/build_library.py` |
| `exercisedb_v1.json` | 373 KB | `{source,exercises:[{exerciseId,name,gifUrl,bodyParts[],equipments[],targetMuscles[],secondaryMuscles[],gifAvailable?}]}` | 1500 (176 `gifAvailable:false`) | `MediaRepository.loadEdb` (static cache) |
| `media_overrides.json` | 1 KB | `{schema_version:1,description,overrides:{<exerciseId>:<edbV1Id>\|null}}` | 19 | `MediaRepository.loadOverrides` |
| `edb_v2_map.json` | 16 KB | `{schema_version:1,description,mappings:{<exerciseId>:{edbId\|null,status,confidence,query}}}` | 111 | `EdbMappingRepository.seedFromAsset` (insert only if row absent) |
| `exercise_merges.json` | 3 KB | `{schema_version:1,description,merges:[{duplicate,canonical,canonical_name?,reason}]}` | 22 | `ExerciseMerger.loadAsset` |
| `exercise_muscles.json` | 10 KB | `{schema_version:1,description,exercises:{<id>:{<muscleKey>:0..1}}}` (20 ranking muscles) | 111 | `ExerciseMuscleTable.load` at startup |
| `liftoff_name_map.json` | 5.6 KB | `{schema_version:1,description,map:{<LiftoffName>: "<id>" \| {id,exclude_from_ranks} \| {by_weight:[{min_kg,id,name}]} \| {custom:{name,primaryMuscles,secondaryMuscles,equipment,compound}}}}` | 57 | `LiftoffNameMap.parse` |
| `strength_standards.json` | 37 KB | `{schema_version:4,description,scaling{reference_bodyweight:100,exponent:0.67},machine_strictness:1.1,bases{bench,squat,deadlift,ohp,row:{beginner,novice,intermediate,advanced,elite}},standards:[{id,name,kind:free\|machine\|cable\|bodyweight,per_hand,base,factor,exercise_ids[],anchors{beginner..elite}}]}` | 103 (free 39, machine 26, cable 26, bodyweight 12) | `RanksRepository.loadStandards` (static cache) |
| `achievements.json` | 13 KB | `{schema_version:2,description,achievements:[{key,title,description,icon,type,threshold,category,family?,level?,param?}]}` | 52 (types: bestExerciseTier 7, overallTier 5, sessions 4, prs 4, streakDays 3, musclesAtTier 3, totalVolumeKg 3, totalSets 3, distinctExercises 3, greenSessions 3, sleepStreak 3, fullProgramWeeks 3, level 3, regionsAtTier 2, musclesRanked 2, maxSessionVolumeKg 1; categories strength 21, consistency 7, volume 7, recovery 6, program 6, exploration 5) | `GamificationRepository.loadAchievementDefs` (cache). Unlocked when metric >= threshold |
| `body_map.json` | 42 KB | `{source,front:[{slug,common?,left?,right?:[svg path d]}],back:[...]}` (19 front, 16 back slugs; react-native-body-highlighter v3.2.0, MIT) | | `BodyMap.load` |
| `programs/min_max_canonical.json` | 42 KB | see 1.6 | 5 days / 37 slots | `ProgramRepository.load` (static cache) |
| `programs/my_routines.json` | 9.7 KB | see 1.6 | 5 routines (Upper 5, Lower 6, Push 5, Pull 6, Arms 7 rows) | `ProgramRepository.loadMyRoutines`; `schema_version` 2 |
| `fonts/` | | | | |

#### Versioned seeding
```dart
lib/features/library/data/exercise_repository.dart:9-10
/// Bump when assets/exercises.json is refreshed so existing installs re-import it.
const int exerciseDatasetVersion = 5; // v5: + Machine Single-Arm Reverse Fly (the id the Liftoff import already uses); v2: + extra_exercises.json; v3: + Assisted Dip (Machine); v4: + library_sources.json (wger, ExerciseDB V1)
```
```dart
lib/features/library/data/exercise_repository.dart:21-23,28-35,36-71   (ensureSeeded; condensed where marked)
    final current = int.tryParse(await _db.getSetting(_datasetKey) ?? '');
    if (current == exerciseDatasetVersion) return;
    final list = [
      ...(jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>(),
      // Built-in additions (Pendulum Squat, machine Assisted Pull-Up…), same shape, ids start with sp_.
      ...((jsonDecode(extraRaw) as Map<String, dynamic>)['exercises'] as List<dynamic>).cast<Map<String, dynamic>>(),
    ];
    final added = (sources['exercises'] as List<dynamic>).cast<Map<String, dynamic>>();
    await _db.batch((b) {
      void put(Map<String, dynamic> e, {required String source}) {
        final a = attach[e['id']];
        final images = (e['images'] as List<dynamic>? ?? const []).cast<String>();
        final full = images.where((u) => u.startsWith('http')).toList();
        final companion = ExercisesCompanion.insert(
          id: e['id'] as String,
          name: e['name'] as String,
          primaryMuscles: Value(jsonEncode(e['primaryMuscles'] ?? const [])),
          secondaryMuscles: Value(jsonEncode(e['secondaryMuscles'] ?? const [])),
          equipment: Value(e['equipment'] as String?),
          level: Value(e['level'] as String?),
          mechanic: Value(e['mechanic'] as String?),
          category: Value(e['category'] as String?),
          instructions: Value(jsonEncode(e['instructions'] ?? const [])),
          images: Value(jsonEncode([for (final i in images) if (!i.startsWith('http')) i])),
          extraImages: Value(jsonEncode([...full, ...?(a?['images'] as List<dynamic>?)?.cast<String>()])),
          source: Value(source),
          credit: Value(jsonEncode([if (e['credit'] != null) e['credit'], ...?(a?['credits'] as List<dynamic>?)])),
          edbV1Id: Value((e['edb_v1_id'] ?? a?['edb_v1_id']) as String?),
        );
        b.insert(
          _db.exercises,
          companion,
          onConflict: DoUpdate((old) => companion.copyWith(isFavorite: const Value.absent())),
        );
      }

      for (final e in list) {
        put(e, source: 'fedb');
      }
      for (final e in added) {
        put(e, source: e['source'] as String);
      }
    });
    await _db.putSetting(_datasetKey, '$exerciseDatasetVersion');
```
Semantics: UPSERT by id; `isFavorite`, `isCustom` and `notes` are not in the companion so they are preserved on update; custom exercises (`custom_*`, `liftoff_*`) are never touched; merged-away duplicates are re-created and re-merged at next start. `images` entries starting `http` go to `extra_images`; repo paths resolved with `exerciseImageBaseUrl = 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/'` (`exercise_info.dart:6`); `imageUrls = [images -> base+path (or as-is if http)..., ...extraImages]` (`exercise_info.dart:64`).

Other versions: `mediaMatchVersion = 4` (`media_repository.dart:16`), `rankLadderVersion = 8`, `exportSchemaVersion = 1`, `my_routines.json schema_version = 2` (reinstall trigger), `canonical_week = 5`.

### 1.6 Program assets

`assets/programs/min_max_canonical.json` (schema_version 2) parsed by `Program.fromJson` (`program/domain/program.dart:148-225`):
- `program{id:'min_max_phase2_5x', name, author, source, split[5], week_layout[7], canonical_week:5}`; `week_layout = ["Upper","Lower","Rest","Push","Pull","Arms","Rest"]` (Mon..Sun) -> `plannedRestWeekdays` = ISO weekdays {3,7}; `sessionsPerWeek` = 5.
- `method{effort{scale,definition,rir0_default,rir0_safety_exception,warmup_sets_effort,first_set_to_failure}, warmup{general{duration,items,tip}, exercise_specific{by_count{"1".."4":[{pct,reps{min,max}}]}, basis, rest_between_s{min:0,max:60}}}, techniques{drop_sets_2x25{drops:2,drop_pct:25}, myo_reps{rest_s:5,reps_per_cycle:2}, weighted_static_hold_30s{hold_s:30}, lengthened_partials{used_in_this_version:false}}, progression{rule,fallback,tracking}}`.
- `days[]`: `{id:upper|lower|push|pull|arms, name, slots[]}` (slot counts 7/7/7/8/8). Slot: `{slot_id:'<day>_<nn>', exercise, superset:'S1'..|null, warmup_sets{min,max}, working_sets:int, rep_range{min,max,per_side,text}, rest{min_s,max_s,text}|null, substitutions[], notes, rir0_attempt_failure, video{url,start_s}?, substitution_videos{<name>:{url,start_s}}?, rir:[int|null per working set]}`. Top-level `videos_source` string.
- Warm-up pyramid by_count: 1 set: 60% x6-10; 2: 50% x6-10, 70% x4-6; 3: 45% x6-10, 65% x4-6, 85% x3-4; 4: 45% x6-10, 60% x4-6, 75% x3-5, 85% x2-4. Example slot `upper_01` Machine Chest Press: warmups {2,3}, 2 working sets, 4-6 reps, rest 120-180 s, `rir:[0,0]`.

`assets/programs/my_routines.json` (schema_version 2): `{schema_version, program_id, description, routines:[{day, name, exercises:[{name, exercise_id, sets, program_slots[], relation: program|substitution|swap|extra, program_exercise, (inherit_from, needs_confirmation, assisted, bodyweight annotations)}]}]}`. Example row: `{"name":"Chest Press","exercise_id":"Leverage_Chest_Press","sets":3,"program_slots":["upper_01","upper_02"],"relation":"program","program_exercise":"Machine Chest Press"}`.

### 1.7 Export format (`export/data/export_service.dart`, `export/domain/export_schema.dart`, `docs/export_schema.md`)

- `exportSchemaVersion = 1`. Timestamps `isoLocal` = `yyyy-MM-ddTHH:mm:ss+HH:MM` (local offset, seconds precision); file stamp `yyyyMMdd-HHmm`. CSV: RFC 4180 quoting (`[",\r\n]` triggers quotes, inner quotes doubled), CRLF line endings, nulls empty, integer-valued doubles printed without decimals.
- Only `status='finished'` sessions (all sources, incl. Liftoff-imported; `source` is not exported) ordered by `started_at`; exercises by position; sets by position (`export_service.dart:77-98`). Active session is never exported.
- JSON top level: `schema_version, app:'spotter', exported_at, units{weight:kg,sleep:minutes,energy:kcal,hrv:ms,heart_rate:bpm}, bodyweights[{id,measured_at,kg,source}], routines[{id,name,position,created_at,exercises[{exercise_id,exercise_name,position,rep_min,rep_max,target_sets,target_rir,rest_s}]}], sessions[...], readiness_days[...], custom_exercises[{id,name,primary_muscles,secondary_muscles,equipment,mechanic,notes}], ego_freezes[{id,exercise_id,started_at,until,base_weight_kg,reason}], xp_events[{id,at,amount,reason,session_id,week_start}], achievements[{key,unlocked_at}]`.
- Session object: `id,name,routine_id,started_at,ended_at,duration_s,notes,readiness_score,readiness_band,xp_earned,health_synced,exercises[{session_exercise_id,exercise_id,exercise_name,position,rep_min,rep_max,target_sets,target_rir,rest_s,suggestion_kind,suggested_weight,suggested_reps,suggested_sets,notes,sets[]}]`.
```dart
lib/features/export/data/export_service.dart:26-49
  Map<String, Object?> _setMap(WorkoutSet s) {
    final working = s.completed && !s.isWarmup;
    final e1rm = working ? estimateOneRm(s.weight, s.reps, s.rpe) : null;
    return {
      'set_id': s.id,
      'position': s.position,
      'is_warmup': s.isWarmup,
      'weight_kg': s.weight,
      'reps': s.reps,
      'rpe': s.rpe,
      'rir': s.rpe == null ? null : 10 - s.rpe!,
      'completed': s.completed,
      'completed_at': isoLocalOrNull(s.completedAt),
      'suggested_weight_kg': s.suggestedWeight,
      'suggested_reps': s.suggestedReps,
      'is_override': s.isOverride,
      'override_reason': s.overrideReason,
      'e1rm_kg': e1rm == null || e1rm == 0 ? null : double.parse(e1rm.toStringAsFixed(2)),
      'set_type': s.setType ?? (s.isWarmup ? 'warmup' : 'working'),
      'partials': s.partials,
      'rest_seconds': s.restSeconds,
      'is_ego_set': s.isOverride && s.targetRepMin != null && s.reps < s.targetRepMin!,
    };
  }
```
- Readiness day JSON/CSV fields: `date,hrv_ms,resting_hr_bpm,sleep_minutes,active_energy_kcal,readiness_score,readiness_band,calibrating,explanation` (`dietary_kcal`/`protein_g` not exported).
- CSV files: `spotter-sessions-<stamp>.csv` columns `id,name,routine_id,started_at,ended_at,duration_s,notes,readiness_score,readiness_band,xp_earned,health_synced`; `spotter-sets-<stamp>.csv` (denormalised, `session_id, session_started_at, session_exercise_id, exercise_id, exercise_name, exercise_position, rep_min, rep_max, target_rir, suggestion_kind` then set fields); `spotter-readiness-days-<stamp>.csv`.
```dart
lib/features/export/domain/export_schema.dart:59-85   (condensed)
const setCsvColumns = [
  'session_id', 'session_started_at', 'session_exercise_id', 'exercise_id', 'exercise_name', 'exercise_position',
  'rep_min', 'rep_max', 'target_rir', 'suggestion_kind', 'set_id', 'position', 'is_warmup', 'weight_kg', 'reps',
  'rpe', 'rir', 'completed', 'completed_at', 'suggested_weight_kg', 'suggested_reps', 'is_override',
  'override_reason', 'e1rm_kg', 'is_ego_set',
];
```
(`set_type`, `partials`, `rest_seconds` are NOT CSV columns; OQ-5.) Delivery: temp dir + iOS share sheet via share_plus (`export_service.dart:254-264`); RN equivalent = cache-dir files + Share API.

---------------------------------------------------------------------------------------------------
## 2. BUSINESS LOGIC
---------------------------------------------------------------------------------------------------

### 2.1 Session logging pipeline

#### 2.1.1 Start session (`session_repository.dart:170-221`)
One DB **transaction**: insert `sessions` row (name, routine_id, `started_at = coach.now`, readiness score/band only when readiness exists and not calibrating); for each routine exercise in order (skipping ids missing from `catalog`) insert a `session_exercises` row + its `workout_sets` (2.1.2); then remap superset groups to the **session-exercise id of the group's first exercise**:
```dart
lib/features/workout/data/session_repository.dart:212-216
          final g = re.supersetGroup;
          if (g != null) {
            await (_db.update(_db.sessionExercises)..where((t) => t.id.equals(exId)))
                .write(SessionExercisesCompanion(supersetGroup: Value(groups[g] ??= exId)));
          }
```
Routine rows with both `override_rep_min/max` non-null pass an `overrideRange` (replaces every slot's range).

#### 2.1.2 Plan freeze: the plan is written once, at Start
The suggestion comes from `coach.suggest(info, range, targetSets, targetRir)` (engine = another section) and is persisted in `session_exercises.suggested_*` + `suggestion_json` and on every set (`suggested_weight`, `suggested_reps`). Nothing re-runs the engine for exercises already in the workout.

Non-program exercise (`:315-343`): one set row per `s.sets` with `weight=s.weight`, `reps=s.reps`; calibration (`rampUp`) sets carry no suggested weight:
```dart
lib/features/workout/data/session_repository.dart:331-341
    // Calibration sets ramp freely, so they carry no suggested weight (no override detection).
    final suggested = s.rampUp ? null : s.weight;
    for (var i = 0; i < s.sets; i++) {
      await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
            sessionExerciseId: exId,
            position: i,
            weight: Value(s.weight),
            reps: Value(s.reps),
            suggestedWeight: Value(suggested),
            suggestedReps: Value(s.reps),
          ));
    }
```
Program exercise (`_insertProgramExercise` `:349-463`): `prescribeSets` -> per-set prescriptions (each `.withRange(overrideRange)` if override); consecutive sets grouped by slot; one `coach.suggest` per group using `g.first.targetRir ?? 0`; combined headline appends `' · then ${formatKg(s.weight)} kg × ${groups[i].first.repRange}'` per extra group and `why.add('${repRange} set(s): ${s.headline}')`; `downNote` lines joined with `\n`; stored exercise row uses first slot's range (or override), `targetRir = groups.first.first.targetRir ?? 0`, `program_slots = jsonEncode(slotIds)`. Warm-ups are not created when `main.rampUp`:
```dart
lib/features/workout/data/session_repository.dart:423-442
    // Warm-ups (not for calibration, where the lifter ramps up anyway).
    if (!main.rampUp) {
      final count = warmupOverride ?? warmupCountFor(firstSlot, firstOfDay: position == 0, compound: info.isCompound);
      for (final w in warmupSets(
        program: program,
        count: count,
        workingWeight: main.weight,
        increment: coach.increments.of(info.equipmentKind),
      )) {
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              sessionExerciseId: exId,
              position: pos++,
              isWarmup: const Value(true),
              // Warm-ups land on weights that exist too.
              weight: Value(main.weight > 0 ? coach.gridFor(info).snap(w.weight) : w.weight),
              reps: Value(w.reps),
              targetRepMin: Value(w.repRange.min),
              targetRepMax: Value(w.repRange.max),
            ));
      }
    }
```
Then every prescribed working set, always ("coaching inputs change targets, never the routine's volume", `:446`): `weight=s.weight, reps=s.reps, suggested_weight = s.rampUp ? null : s.weight, suggested_reps = s.reps, target_rep_min/max = prescription range, target_rir = prescription RIR` (nullable).

Coach context freeze (in-memory, per session id) (`app_providers.dart:228-247`):
```dart
lib/app_providers.dart:228-247
class FrozenCoachNotifier extends Notifier<({int sessionId, CoachContext coach})?> {
  @override
  ({int sessionId, CoachContext coach})? build() => null;
  void freeze(int sessionId, CoachContext coach) => state = (sessionId: sessionId, coach: coach);
}

final frozenCoachProvider = NotifierProvider<FrozenCoachNotifier, ({int sessionId, CoachContext coach})?>(FrozenCoachNotifier.new);

final workoutCoachProvider = Provider<Future<CoachContext> Function(int sessionId)>((ref) {
  return (sessionId) async {
    final frozen = ref.read(frozenCoachProvider);
    if (frozen != null && frozen.sessionId == sessionId) return frozen.coach;
    final fresh = await ref.read(coachContextBuilderProvider)();
    ref.read(frozenCoachProvider.notifier).freeze(sessionId, fresh);
    return fresh;
  };
});
```
After a cold restart mid-workout the first swap / form reset / add builds a fresh context and freezes it.

Added exercise (`addExercise` `:223-244`): position = max+1; plain `_insertExercise` (no program => no warm-ups); set count from `coach.suggest(...).sets` (DECISIONS item 11: starts with one working set when the exercise has history). Replace exercise (`:468-495`, transaction): deletes old sets + exercise (logged sets discarded) and re-inserts at same position with the same slots/target sets/rest/RIR/superset/routine link, `displayName: info.name`, `overrideRange` kept only if `targetsEdited`.

The only automatic mid-workout plan change after a ✓ below range:
```dart
lib/features/workout/data/session_repository.dart:689-715
  Future<List<int>> adaptLaterSets(WorkoutSet done, {required WeightGrid? grid, required int exerciseRepMin}) async {
    if (done.isWarmup || done.isFollowUp || done.weight <= 0 || done.reps <= 0 || grid == null) return const [];
    final min = done.targetRepMin ?? exerciseRepMin;
    if (done.reps >= min) return const [];
    final lighter = grid.previous(done.weight);
    if (lighter == null) return const [];
    final sets = await _setsOf(done.sessionExerciseId);
    final number = sets.where((s) => s.isWorkingSet).toList().indexWhere((s) => s.id == done.id) + 1;
    final max = done.targetRepMax;
    final range = max == null ? '$min+' : '$min–$max';
    final changed = <int>[];
    for (final s in sets) {
      if (s.position <= done.position || s.completed || !s.isWorkingSet) continue;
      final planned = s.suggestedWeight;
      // Untouched: still at its planned weight, and heavier than the step down.
      if (planned == null || (s.weight - planned).abs() > 0.01 || s.weight <= lighter + 0.01) continue;
      await (_db.update(_db.workoutSets)..where((t) => t.id.equals(s.id))).write(WorkoutSetsCompanion(
        weight: Value(lighter),
        suggestedWeight: Value(lighter),
        adjustedFrom: Value(s.adjustedFrom ?? s.weight),
        adjustReason: Value('Set $number: ${done.reps} reps at ${formatKg(done.weight)} kg, below the $range rep range. '
            'This set moves one step lighter (${formatKg(s.adjustedFrom ?? s.weight)} → ${formatKg(lighter)} kg) so it can stay in range.'),
      ));
      changed.add(s.id);
    }
    return changed;
  }
```
Other permitted mutations: `applyLighterOption` (`:499-509`; not-completed working sets whose weight differs by >= 0.01 move to the chosen weight; reason `'You chose the lighter option (X kg) after three sessions below the rep range at Y kg.'`); `applyEquipmentChange` (`:514-533`, "the one exception to the frozen plan": `planResnap` (`workout/domain/equipment_resnap.dart`: for not-completed sets snap to nearest grid load, cap at max load; sets still at the old suggestion take the new one; reason `'Weight steps updated: A kg is now B kg (the nearest weight on the new steps).'` or `(the max load is M kg)`), transaction, also updates the exercise `suggested_weight` when it changes >= 0.01); `setTargetReps` (`:536-545` txn: exercise `rep_min/rep_max`, `targets_edited=true`, plus `target_rep_min/max` on each `isWorkingSet`); `refreshDrops`.

Equipment sync (`workout/data/equipment_sync.dart:15-37`): `onGymChanged(next)`: no-op with no active session or when `before.gym.encode() == next.encode()`; else `coach = before.withGym(next)`, re-freeze it, and for every exercise (skip if catalog entry missing or all sets completed) compare old/new `WeightGrid`; if different call `repo.applyEquipmentChange(ex, grid: grid)`; returns number of changed sets. Outside a workout nothing is stored.
```dart
lib/features/workout/data/equipment_sync.dart:36-37
  static bool _sameGrid(WeightGrid a, WeightGrid b) =>
      a.maxLoad == b.maxLoad && a.values.length == b.values.length && [for (var i = 0; i < a.values.length; i++) (a.values[i] - b.values[i]).abs() < 0.005].every((x) => x);
```
Workout Live Activity sync (`workout_activity_sync.dart`): single writer; `refresh({force})` rebuilds `WorkoutActivity` from active session + running rest, sends only when it differs from `_last`; ends the activity when there is no active session; reschedules itself at `rest.endsAt - now + 300 ms`.

#### 2.1.3 `suggestion_json` shape (`session_repository.dart:65-75`)
`{headline, why:[string], technique:bool, ramp:bool, band:'green|yellow|red', reset?:double, max?:true, down?:string, lighter?:double}` plus columns `suggestion_kind`, `suggested_weight/reps/sets`. History `techniqueDay` = `suggestion_json.technique == true` (`history_repository.dart:121-125`).

#### 2.1.4 Per-set logging (✓)
UI order (`workout/presentation/active_workout_screen.dart:422-476`): close keypad / commit typed values -> re-read set from DB (`repo.workoutSet`) -> if already completed: `uncompleteSet` (clears completed, completedAt, isOverride, overrideReason, restSeconds) and cancel its rest timer; else rpe = `s.isWarmup || s.kind == SetKind.hold ? null : (s.rpe ?? Effort.fromRir(s.targetRir ?? ex.row.targetRir).rpe)` -> if `needsReason` ask for reason (cancel aborts) -> `completeSet` -> `adaptLaterSets` -> praise -> start rest timer -> maybe offer form reset.

`completeSet` (`:639-682`): one UPDATE (no transaction) + one side effect. **No XP, PR, quest, achievement, streak or rank-score writes happen per set.** Only `RankExclusions.autoEnable`.
```dart
lib/features/workout/data/session_repository.dart:629-636
  /// Would completing this set with [weight] count as an override (more than 5 % above the suggestion)?
  bool wouldOverride(WorkoutSet set, double weight, {bool? isWarmup}) =>
      !set.isFollowUp && _guardrail.isOverride(weight: weight, suggested: set.suggestedWeight, isWarmup: isWarmup ?? set.isWarmup);

  /// Section 7: a reason is asked for only when the set was too heavy, i.e. an override whose reps also
  /// fell below the bottom of its range. Failure inside the range is never flagged.
  bool needsReason(WorkoutSet set, {required double weight, required int reps, required int exerciseRepMin}) =>
      wouldOverride(set, weight) && reps < (set.targetRepMin ?? exerciseRepMin);
```
```dart
lib/features/workout/data/session_repository.dart:650-681
    final override = wouldOverride(set, weight, isWarmup: isWarmup);
    if (exerciseRepMin != null && needsReason(set, weight: weight, reps: reps, exerciseRepMin: exerciseRepMin) && reason == null) {
      throw StateError('A set that was too heavy (override below the rep range) needs a reason');
    }
    // The rest actually taken before this set: from the previous done set of the exercise to this ✓, or to the moment the
    // rest timer was skipped (then it is over, whatever came after).
    int? rest;
    if (set.setType == null) {
      final before = (await _setsOf(set.sessionExerciseId))
          .where((x) => x.completed && x.completedAt != null && x.setType == null && x.position < set.position)
          .lastOrNull;
      if (before != null) {
        final end = restEndedAt != null && restEndedAt.isAfter(before.completedAt!) && !restEndedAt.isAfter(now) ? restEndedAt : now;
        rest = end.difference(before.completedAt!).inSeconds.clamp(0, 3 * 3600);
      }
    }
    await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id))).write(WorkoutSetsCompanion(
      weight: Value(weight),
      reps: Value(reps),
      rpe: Value(rpe),
      isWarmup: Value(isWarmup),
      completed: const Value(true),
      completedAt: Value(now),
      isOverride: Value(override),
      overrideReason: Value(override ? reason?.name : null),
      restSeconds: Value(rest),
    ));
    // A real working set (not a warm-up, a drop / myo / hold, or an empty one) switches the exercise on for ranks.
    if (!isWarmup && reps > 0 && set.setType == null) {
      final ex = await (_db.select(_db.sessionExercises)..where((t) => t.id.equals(set.sessionExerciseId))).getSingleOrNull();
      if (ex != null) await RankExclusions(_db).autoEnable(ex.exerciseId);
    }
```
Constants involved:
```dart
lib/features/coach/domain/guardrail.dart:42-51
  static const double overrideTolerance = 0.05;
  static const Duration freezeDuration = Duration(days: 7);

  /// A working set more than 5 % heavier than the suggestion is an override.
  /// With a bodyweight suggestion (0 kg), any added load is an override.
  bool isOverride({required double weight, required double? suggested, required bool isWarmup}) {
    if (isWarmup || suggested == null) return false;
    if (suggested <= 0) return weight > 0;
    return weight > suggested * (1 + overrideTolerance) + 1e-9;
  }
```
```dart
lib/core/domain/training.dart:4-15
/// RPE assumed when the lifter didn't log one.
const double defaultRpe = 9.0;

/// RPE at or above which an override set counts as an ego set.
const double egoRpeThreshold = 9.5;

/// Estimated 1RM: Epley on effective reps, `weight × (1 + (reps + RIR) / 30)` with RIR = 10 − RPE.
double estimateOneRm(double weight, int reps, double? rpe) {
  if (reps <= 0 || weight <= 0) return 0;
  final rir = 10 - (rpe ?? defaultRpe);
  return weight * (1 + (reps + rir) / 30);
}
```
```dart
lib/core/domain/training.dart:93-104   (condensed: comments + the two getters)
  bool get isEgoSet => isOverride && belowRange;       // belowRange = targetMin != null && reps < targetMin!
  bool get isValidForRecords => isWorking && !isFollowUp && !isEgoSet;   // isWorking = !isWarmup && completed
```
Other set operations: `addSet` (`:570-591`: copies last non-follow-up set's load; warm-up = 0.5 x load rounded to 2.5, reps 5, position negative then `_renumber`; working set copies previous working set's target range/RIR, never technique); `deleteSet` + `restoreSet` (undo: shift positions >= old, `insertOrReplace` same id, renumber); `setSetKind` (SET menu: working/warmup/drop/myo/hold/`technique:<id>`; non-working kinds null the `suggested_weight`; hold sets reps=30, myo reps=2; follow-ups null the target rep range); `addFollowUp` (`:735-763`, transaction; drop weight from parent or the last drop above, pct = `dropPct ?? (technique == dropTechnique ? programDropPct : defaultDropPct)`, myo/hold copy parent weight; `target_rir=0`); `refreshDrops` (re-derive not-done drops after parent load change); `_drop`:
```dart
lib/features/workout/data/session_repository.dart:785-791
  static double _drop(double from, int pct, double increment, WeightGrid? grid) {
    final w = dropWeight(from, pct: pct, increment: increment);
    if (grid == null) return w;
    final snapped = grid.snapDown(w);
    return snapped < from - 0.01 ? snapped : (grid.previous(from) ?? w);
  }
```
```dart
lib/features/workout/domain/set_kinds.dart:43-75
const int myoRestSeconds = 5;
const int myoRepsPerCycle = 2;
const int holdSeconds = 30;
const int defaultDropPct = 20;
double dropWeight(double from, {required int pct, required double increment}) {
  final inc = increment <= 0 ? 1.0 : increment;
  if (from < 0) {
    // Assisted: a "drop" adds assistance.
    final raw = from - from.abs() * pct / 100;
    final r = (raw / inc).round() * inc;
    return r >= from ? from - inc : r;
  }
  final raw = from * (1 - pct / 100);
  var r = (raw / inc).round() * inc;
  if (r >= from) r = from - inc;
  return r < 0 ? 0 : double.parse(r.toStringAsFixed(2));
}
const String dropTechnique = 'drop_sets_2x25';
const String myoTechnique = 'myo_reps';
const String holdTechnique = 'weighted_static_hold_30s';
const int programDropPct = 25;
const int programDrops = 2;
```
Exercise-level ops: `removeExercise` (txn), `reorderExercises` (txn; position = index), `setExerciseNotes`, `setSessionNotes`, `renameSession`, `setRest(enabled, seconds)`, `superset(a,b)` (group = `a.group ?? b.group ?? a.row.id`; both rows updated), `leaveSuperset`, `setPartials`, `discard(sessionId)` (txn deleting sets, exercises, session).

#### 2.1.5 Finish (`finish_service.dart:202-345`): ORDER OF OPERATIONS
Only step 1 is wrapped in a DB transaction; steps 2-12 are sequential autocommit writes (OQ-3).
0. Read (outside txn): standards, achievement defs, `bwLoaded`, latest bodyweight kg (0 if none), `excluded = RankExclusions.load()`, `before = history.load(catalog)` (all finished sessions; this one is still active so absent), `xpBefore = totalXp`.
1. **Transaction**: `_prune` (delete uncompleted sets; delete exercises with no sets left) + `status='finished'`, `ended_at=now`.
```dart
lib/features/workout/data/finish_service.dart:136-144, 218-222
  /// Drops sets that were never completed and exercises left without sets.
  Future<void> _prune(int sessionId) async {
    final exRows = await (_db.select(_db.sessionExercises)..where((t) => t.sessionId.equals(sessionId))).get();
    for (final e in exRows) {
      await (_db.delete(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(e.id) & t.completed.equals(false))).go();
      final left = await (_db.select(_db.workoutSets)..where((t) => t.sessionExerciseId.equals(e.id))).get();
      if (left.isEmpty) await (_db.delete(_db.sessionExercises)..where((t) => t.id.equals(e.id))).go();
    }
  }
    await _db.transaction(() async {
      await _prune(sessionId);
      await (_db.update(_db.sessions)..where((t) => t.id.equals(sessionId)))
          .write(SessionsCompanion(status: const Value('finished'), endedAt: Value(now)));
    });
```
2. `after = history.load(catalog)`; rank safety net: every exercise with any working set `reps > 0` -> `RankExclusions.autoEnable` (unless a manual choice exists); reload `excludedNow`.
3. PRs: `findPrs(after, bodyweightLoaded, bodyweight)` filtered to this session (PRs are derived by replaying history; there is no PR table).
```dart
lib/features/gamification/domain/stats.dart:22-40
List<PrRecord> findPrs(TrainingHistory history, {Set<String> bodyweightLoaded = const {}, double bodyweight = 0}) {
  final best = <String, double>{};
  final out = <PrRecord>[];
  for (final s in history.sessions) {
    for (final e in s.exercises) {
      final bw = bodyweightLoaded.contains(e.exerciseId) ? bodyweight : 0.0;
      var sessionBest = 0.0;
      for (final set in e.workingSets) {
        if (set.isValidForRecords) sessionBest = math.max(sessionBest, set.e1rm(bodyweight: bw));
      }
      final prev = best[e.exerciseId] ?? 0;
      if (isPr(previousBest: prev, sessionBest: sessionBest)) {
        out.add(PrRecord(sessionId: s.id, exerciseId: e.exerciseId, name: e.name, e1rm: sessionBest, previous: prev));
      }
      if (sessionBest > prev) best[e.exerciseId] = sessionBest;
    }
  }
  return out;
}
```
4. Session XP, inserted as `xp_events(reason:'session', session_id)` (skipped when amount == 0):
```dart
lib/features/gamification/domain/xp.dart:9-19,31-32,46-47
  static const int perWorkingSet = 10;
  static const int perPr = 50;
  static const int perQuest = 40;
  int forSet(LoggedSet s) => s.isWorking ? perWorkingSet : 0;
  int forSession({required Iterable<LoggedSet> sets, required int prCount}) =>
      sets.fold<int>(0, (sum, s) => sum + forSet(s)) + prCount * perPr;
/// XP needed to go from [level] to level + 1: `100 × level^1.5`.
int xpToAdvance(int level) => (100 * math.pow(level, 1.5)).round();
bool isPr({required double previousBest, required double sessionBest}) =>
    previousBest > 0 && sessionBest > previousBest + 0.05;
```
5. Quests: `week = weekStart(session.startedAt)`; sleep nights this week with `>= 420` minutes; `weekActivity(...)`; each stored, not-yet-completed quest of that week whose `progress >= def.target` -> `completeQuest` (`completed_at = now`), xp_event `reason:'quest'`, `amount 40`, `session_id`, `week_start`; `bonus += 40`.
```dart
lib/features/workout/data/finish_service.dart:246-262
    final sleepRows = await _db.select(_db.dailyMetrics).get();
    final sleep = sleepByDayRows(sleepRows);
    var nights = 0;
    for (var i = 0; i < 7; i++) {
      final m = sleep[dayKey(addDays(week, i))];
      if (m != null && m >= 420) nights++;
    }
    final activity = weekActivity(after, session.startedAt, prs: findPrs(after, bodyweightLoaded: bwLoaded, bodyweight: bodyweight), sleepNights: nights);
    for (final q in await _gami.quests(session.startedAt)) {
      if (q.row.completedAt != null) continue;
      if (_quests.progress(q.def, activity) >= q.def.target) {
        await _gami.completeQuest(q.row.id, now);
        await _gami.addXp(at: now, amount: XpRules.perQuest, reason: 'quest', sessionId: sessionId, week: week);
        bonus += XpRules.perQuest;
        questsDone.add(q.def.title);
      }
    }
```
6. Ego flags -> freezes: for each exercise of the session: skip if an unexpired freeze exists (`existing.until.isAfter(now)`); `_guardrail.evaluate(after.logsFor(id), since: existing?.startedAt, bodyweight: bwLoaded.contains(id) ? bodyweight : 0)`; if flagged: `base = e.suggestedWeight ?? top working weight`, `until = now + 7 days`, insert `ego_freezes`, record `GuardrailFlag`.
```dart
lib/features/coach/domain/guardrail.dart:55-79
  EgoFlagResult evaluate(List<ExerciseSessionLog> history, {DateTime? since, double bodyweight = 0}) {
    final logs = history
        .where((l) => l.hasWorkingSets && (since == null || l.date.isAfter(since)))
        .toList();
    if (logs.length < 2) return const EgoFlagResult({});
    final last3 = logs.sublist(logs.length < 3 ? 0 : logs.length - 3);
    final triggers = <EgoTrigger>{};

    final egoSessions = last3.where((l) => l.hasEgoOverrides).length;
    if (egoSessions >= 2) triggers.add(EgoTrigger.repeatedMaxOverrides);

    // Weight up while e1RM down. ...
    if (last3.length == 3) {
      final first = last3.first, latest = last3.last;
      final selfImposed = last3.skip(1).any((l) => l.hasBadOverrides);
      if (selfImposed &&
          latest.topWeight > first.topWeight &&
          latest.bestE1rm(bodyweight: bodyweight) < first.bestE1rm(bodyweight: bodyweight)) {
        triggers.add(EgoTrigger.weightUpE1rmDown);
      }
    }
    return EgoFlagResult(triggers);
  }
```
Message: `'Ego lifting detected: <2 of your last 3 sessions had sets heavier than suggested that fell below the rep range | the weight went up while your estimated 1RM went down>. Progression is frozen for 7 days at −5%.'`.
7. `overrideSets` = working sets with `isOverride`.
8. Rank changes: `ranksAfter = compute(after, excludedNow)` vs `compute(before, excluded)`; `rankChanges` by label difference (exercise, muscle, region, overall; first placement counts); `rankGains` for animations:
```dart
lib/features/workout/data/finish_service.dart:347-354
  /// Minimum gain (in points; 1 point = 100 RR) worth animating: half an RR.
  static const _minGain = 0.005;
  static List<RankChange> rankGains(RankSummary before, RankSummary after) {
    bool rose(RankScore? from, RankScore to) => from == null || to.value - from.value > _minGain;
    // sorted(): biggest gain first within a group; order: lifts, muscles, regions, overall last
```
9. Achievements: `buildAchievementStats(after, longestStreak, totalXp = xpBefore + xpSession + bonus, prCount, ranksAfter, sleep by day, routine ids)`; `AchievementEvaluator.newlyUnlocked(defs, stats, unlockedKeys)`; insert into `achievements_unlocked` (`insertOrIgnore`). Achievements award no XP.
10. `sessions.xp_earned = xpSession + bonus`.
11. Streak: **no streak row is written**. The streak is derived (`DayStreakCalculator.compute(workoutStarts: streakWorkoutStarts(history), now, offset)`) from finished sessions + the `streak_offset` setting; `streakBefore`/`streakAfter` computed from `before`/`after` only for the summary.
12. Apple Health: `health.writeStrengthWorkout(start: session.startedAt, end: now, title: session.name)` inside try/catch (failure -> `saved=false`, `debugPrint`); success sets `sessions.health_synced = true`.
13. Return `SessionSummary` (duration = `now - startedAt`; volume, workingSets, prs, xp, levels via `levelFor`, rank changes/gains, override sets, flags, achievements, quests, health result, `disciplinePct` via `Guardrail.disciplinePct`, `avgEffort` = mean RPE of working sets that have one, streak before/after).
`reevaluateAchievements` (`:178-200`) = steps 8-9 only, no XP (used after the Liftoff import).

#### 2.1.6 History queries (`workout/data/history_repository.dart`)
- `load(catalog, {excludeSessionId})`: all `status='finished'` sessions ordered by `started_at ASC`; then `session_exercises WHERE session_id IN ids ORDER BY position` and `workout_sets WHERE session_exercise_id IN ids ORDER BY position`; assembled in memory into `TrainingHistory/HistSession/HistExercise/HistSet`. Exercise name = `displayName ?? catalog[id].name ?? id`; `imported = source != 'app'`; per-set `targetRange` from `target_rep_min/max`; `loggedSetFromRow` maps `set_type` to `isDrop/isMyo/isHold` and falls back to the exercise row's range/RIR for targets.
- `loadSession(id)` any status. `watchFinishedChanges()` = table updates on `sessions` only (set edits within the active session do not trigger it).
- `correctSet(setId, weight, reps)`: txn updating the set + a no-op `UPDATE sessions SET notes = notes ...` to fire the sessions stream.
- `deleteSession(id)`: txn deleting sets, session_exercises, **that session's xp_events**, session (OQ-19).
- `suspectSetIds(sessionId)`: completed working sets (`set_type IS NULL`, not warm-up) with `ABS(weight - suggested_weight) < 0.001 AND reps = suggested_reps` (debug aid for a past keypad bug; `saved_values_fixed_at`).

### 2.2 Routines and "routine sync"

Routine CRUD (`routine_repository.dart`): `create` position = current routine count, blank name -> 'New routine'; `delete` removes exercises then routine in txn; `addExercise` position = existing row count, rep range `exercise.defaultRange(compound: settings.compoundRange, isolation: settings.isolationRange)` (defaults `RepRange.compound = RepRange(6, 10)`, `RepRange.isolation = RepRange(10, 15)`), `targetSets: 3`, `restSeconds = exercise.isCompound ? settings.defaultRestCompound : settings.defaultRestIsolation`, `targetRir = settings.defaultRir`; `reorder` / `reorderRoutines` (txn; position = index).
```dart
lib/features/workout/data/routine_repository.dart:96-107
  Future<void> resetToProgram(RoutineExercise row, Program program) {
    final slots = [for (final id in decodeSlots(row.programSlots)) ?program.slot(id)];
    if (slots.isEmpty) return Future.value();
    return (_db.update(_db.routineExercises)..where((t) => t.id.equals(row.id))).write(RoutineExercisesCompanion(
      targetSets: Value(slots.fold(0, (n, s) => n + s.workingSets)),
      restSeconds: Value(slots.first.rest?.maxSeconds ?? 0),
      repMin: Value(slots.first.repRange.min),
      repMax: Value(slots.first.repRange.max),
      overrideRepMin: const Value(null),
      overrideRepMax: const Value(null),
    ));
  }
```
Replace exercise on a routine row (`:112-136`): relation = `program` if the slot's exercise name equals the new exercise's name (case-insensitive), `substitution` if listed in `slot.substitutions`, else `swap`; `repMin/Max` reset to slot range unless an override exists or the row has no slots; `displayName = info.name`; `exerciseId` replaced; past sessions untouched.
Superset toggle (`:140-162`): `toggleSupersetWithNext(row, next, all)`: if already together -> split the group at the link (rows from `next` on get group id `after.first.id` if > 1 member else null; a lone remaining `before` member is dissolved); else group = `row.supersetGroup ?? row.id`, merge next's whole group into it.

`workout/data/routine_sync.dart` is **session -> routine** sync (not program sync):
- `diffSessionAgainstRoutine` (`:54-87`): `added` (session exercise without a matching `routine_exercise_id`), `removed` (routine rows not seen), `replaced` ('Old → New' when `exerciseId` differs), `reordered` (routine-order ids of seen rows != session order), `setCounts` ('Name: 3 → 4 sets' where working sets = `!isWarmup && setType == null`), `targets` ('Name: 8–10 reps' when `targetsEdited`).
- `updateRoutineFromSession` (txn, `:93-151`):
```dart
lib/features/workout/data/routine_sync.dart:104-148
      for (var i = 0; i < session.length; i++) {
        final e = session[i];
        final r = e.row.routineExerciseId == null ? null : byId[e.row.routineExerciseId];
        final sets = _workingSets(e).clamp(1, 20);
        final override = e.row.targetsEdited ? RepRange(e.row.repMin, e.row.repMax) : null;
        if (r != null) {
          keep.add(r.id);
          final replacedWith = r.exerciseId != e.row.exerciseId;
          String? relation = r.programRelation;
          if (replacedWith && r.programSlots != null && program != null) {
            final slot = program.slot(decodeSlots(r.programSlots).first);
            final name = (catalog[e.row.exerciseId]?.name ?? '').toLowerCase();
            relation = slot != null && slot.substitutions.any((x) => x.toLowerCase() == name) ? 'substitution' : 'swap';
          }
          await (db.update(db.routineExercises)..where((t) => t.id.equals(r.id))).write(RoutineExercisesCompanion(
            exerciseId: Value(e.row.exerciseId),
            position: Value(i),
            targetSets: Value(sets),
            displayName: replacedWith ? Value(e.row.displayName ?? catalog[e.row.exerciseId]?.name) : const Value.absent(),
            programRelation: Value(relation),
            overrideRepMin: override == null ? const Value.absent() : Value(override.min),
            overrideRepMax: override == null ? const Value.absent() : Value(override.max),
            repMin: override == null ? const Value.absent() : Value(override.min),
            repMax: override == null ? const Value.absent() : Value(override.max),
            supersetGroup: Value(e.row.supersetGroup),
          ));
        } else {
          final id = await db.into(db.routineExercises).insert(RoutineExercisesCompanion.insert(
                routineId: routineId, exerciseId: e.row.exerciseId, position: i,
                repMin: e.row.repMin, repMax: e.row.repMax, targetSets: sets, restSeconds: e.row.restSeconds,
                targetRir: Value(e.row.targetRir), programSlots: Value(e.row.programSlots),
                programRelation: Value(e.row.programSlots == null ? null : 'extra'),
                displayName: Value(e.row.displayName), supersetGroup: Value(e.row.supersetGroup),
              ));   // (condensed)
          keep.add(id);
          await (db.update(db.sessionExercises)..where((t) => t.id.equals(e.row.id)))
              .write(SessionExercisesCompanion(routineExerciseId: Value(id)));
        }
      }
      await db.delete(db.routineExercises)..where((t) => t.routineId.equals(routineId) & t.id.isNotIn(keep))).go();
```
(The final delete line is `await (db.delete(db.routineExercises)..where(...)).go();` in source.) Program<->routine linkage lives in 2.4.

### 2.3 Program: slots, rest, prescribeSets, warm-up pyramid (`program/domain/program.dart`)
There are no weeks/phases in code (one fixed canonical week; DECISIONS "Fix 0": no week tracking, techniques manual only).
```dart
lib/features/program/domain/program.dart:14-17
/// Warm-up sets for a slot: the higher count for the day's first exercise and for compounds,
/// the lower count for isolation work (the owner trains to failure and wants to get to work sets fast).
int warmupCountFor(ProgramSlot slot, {required bool firstOfDay, required bool compound}) =>
    (firstOfDay || compound) ? slot.warmupSets.max : slot.warmupSets.min;
```
```dart
lib/features/program/domain/program.dart:258-284
List<SetPrescription> prescribeSets({required Program program, required List<String> slotIds, required int sets}) {
  final out = <SetPrescription>[];
  final slots = [for (final id in slotIds) ?program.slot(id)];
  if (slots.isEmpty) return out;
  for (final s in slots) {
    for (var i = 0; i < s.workingSets && out.length < sets; i++) {
      out.add(SetPrescription(
        slotId: s.id,
        repRange: s.repRange,
        targetRir: i < s.rir.length ? s.rir[i] : null,
        restSeconds: s.rest?.maxSeconds,
        rir0AttemptFailure: s.rir0AttemptFailure,
      ));
    }
  }
  while (out.length < sets) {
    final last = out.last;
    out.add(SetPrescription(
      slotId: last.slotId,
      repRange: last.repRange,
      targetRir: last.targetRir,
      restSeconds: last.restSeconds,
      rir0AttemptFailure: last.rir0AttemptFailure,
    ));
  }
  return out;
}
```
```dart
lib/features/program/domain/program.dart:297-309
List<WarmupSet> warmupSets({required Program program, required int count, required double workingWeight, required double increment}) {
  if (count <= 0) return const [];
  final steps = program.warmupByCount[math.min(count, program.warmupByCount.keys.reduce(math.max))] ?? const [];
  return [
    for (final s in steps)
      WarmupSet(
        weight: workingWeight <= 0 ? 0 : math.max(increment, roundToIncrement(workingWeight * s.pct / 100, increment)),
        reps: s.reps.min,
        pct: s.pct,
        repRange: s.reps,
      ),
  ];
}
```
```dart
lib/core/domain/equipment.dart:65-78
double roundToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  return _clean((weight / increment).roundToDouble() * increment);
}
double _clean(double v) => (v * 1000).roundToDouble() / 1000;
```
(Dart `roundToDouble` rounds half away from zero.) Session warm-ups are additionally snapped with `coach.gridFor(info).snap(w.weight)` when working weight > 0 (2.1.2). `ProgramSlot.rest` is null for the first exercise of a superset (no rest). `rir` entries may be null ("no target"); the stored exercise row uses `?? 0`. `rir0_attempt_failure` defaults true when missing. `Program.fromJson` uses `canonical_week ?? 5`.

### 2.4 Program installation / conversions (`program/data/program_repository.dart`)
- `ensureMyRoutinesInstalled`: run `installMyRoutines` when setting `program_routines_installed` is absent or `< definition.schema_version` (2). **`installMyRoutines` deletes ALL `routine_exercises` and ALL `routines`** (user-created too), then recreates the 5 routines (sessions kept) (`:211-256`):
```dart
lib/features/program/data/program_repository.dart:211-256
    await _db.transaction(() async {
      await _db.delete(_db.routineExercises).go();
      await _db.delete(_db.routines).go();
      var rPos = 0;
      for (final r in (definition['routines'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final routineId = await _db.into(_db.routines).insert(RoutinesCompanion.insert(
              name: r['name'] as String,
              position: Value(rPos++),
              createdAt: now,
              programDay: Value(r['day'] as String),
            ));
        var pos = 0;
        final supersets = <String, int>{};
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = e['exercise_id'] as String;
          final slots = (e['program_slots'] as List<dynamic>).cast<String>();
          final first = program.slot(slots.first);
          if (catalog[id] == null || first == null) {
            skipped.add(e['name'] as String);
            continue;
          }
          final rowId = await _db.into(_db.routineExercises).insert(RoutineExercisesCompanion.insert(
                routineId: routineId,
                exerciseId: id,
                position: pos++,
                repMin: first.repRange.min,
                repMax: first.repRange.max,
                targetSets: (e['sets'] as num).toInt(),
                restSeconds: first.rest?.maxSeconds ?? 0,
                targetRir: Value(first.rir.firstOrNull ?? settings.defaultRir),
                programSlots: Value(jsonEncode(slots)),
                programRelation: Value(e['relation'] as String?),
                programExercise: Value(e['program_exercise'] as String?),
                displayName: Value(e['name'] as String?),
              ));
          // The program's S1/S2/S3 labels: rows sharing a label in a day are one superset.
          final label = first.superset;
          if (label != null) {
            await (_db.update(_db.routineExercises)..where((t) => t.id.equals(rowId)))
                .write(RoutineExercisesCompanion(supersetGroup: Value(supersets[label] ??= rowId)));
          }
        }
      }
      await _db.putSetting(routinesInstalledKey, '${definition['schema_version'] ?? 1}');
    });
```
- `ensureCanonicalWeek` (once; key `program_canonical_week` = `'${p.canonicalWeek}'`; txn): delete `program_start_monday`; for routine rows with `program_slots`, set `target_rir` = first slot's first RIR if it differs; in every active session: delete not-completed sets with `technique IS NOT NULL AND set_type IN ('drop','myo','hold')`, null `technique` of not-completed working sets (`set_type IS NULL`), null `program_week` on its exercises.
- `ensureRoutineSetCounts` (once; key `routine_set_counts_restored`; txn): for routines whose name exists in `my_routines.json`, program rows matched to the definition row by `program_slots.join(',')`; if `row.targetSets < def.sets` and some finished session exercise linked via `routine_exercise_id` has `suggestion_json.technique == true` with exactly `row.targetSets` working sets (`is_warmup = 0 AND set_type IS NULL`) -> `target_sets = def.sets`; stores JSON list of `"<routine> · <displayName ?? exerciseId>: a → b"`.
- `ensureSingleArmReverseFly` (once; only if exercise `liftoff_one_arm_machine_reverse_fly` exists): routine rows with exercise `Reverse_Machine_Flyes` -> `liftoff_one_arm_machine_reverse_fly`, `displayName 'Machine Single-Arm Reverse Fly'`.
- `ensureProgramSupersets` (once; setting `program_supersets_applied == '1'`): per routine, rows by position; group by the first slot's `superset` label (`groups[label] ??= r.id`), `restSeconds = slot.rest?.maxSeconds ?? 0`.
- Helpers: `decodeSlots(raw)` = JSON string list or empty; `rangeOf(min,max)`.

### 2.5 Library: seeding, custom exercises, search ranking, aliases, name resolver, muscle mapping
- Seeding: 1.5. `watchCatalog` = all exercises ordered by name -> `Map<id, ExerciseInfo>`; `ExerciseInfo` computes `targets = targetsFor(...)` and `equipmentKind = EquipmentKind.fromDataset(equipment)`; `isCompound = mechanic == 'compound'`; `source` = `'custom'` when `is_custom`; `muscleSummary` = first 3 of primary+secondary joined `', '` or 'No muscles listed'.
- Custom exercises: id `'custom_${DateTime.now().microsecondsSinceEpoch}'`; mechanic `compound|isolation`; category `'strength'`; `is_custom = true`; notes trimmed or null; `updateCustom` only if `is_custom`; `deleteCustomIfUnused` blocks if any `session_exercises` or `routine_exercises` row references it; `setFavorite`.
- Library filter and sort (`library/domain/exercise_filter.dart`):
```dart
lib/features/library/domain/exercise_filter.dart:30-69
  bool matches(ExerciseInfo e, {Map<String, Set<String>> aliases = const {}}) {
    if (favoritesOnly && !e.isFavorite) return false;
    if (muscle != null && !e.primaryMuscles.contains(muscle) && !e.secondaryMuscles.contains(muscle)) return false;
    if (equipment != null) {
      final eq = e.equipment ?? noEquipment;
      if (eq != equipment) return false;
    }
    if (query.isNotEmpty && searchTokens(query).isNotEmpty) {
      // Each name on its own (a word of one name never combines with a word of another):
      // "high to low", "high-to-low" and "hightolow" all find "High-to-Low Cable Fly".
      if (![e.name, ...?aliases[e.id]].any((n) => searchMatches(n, query))) return false;
    }
    return true;
  }
  ...
  List<ExerciseInfo> apply(Iterable<ExerciseInfo> all, {Map<String, Set<String>> aliases = const {}}) {
    final out = all.where((e) => matches(e, aliases: aliases)).toList();
    int rank(ExerciseInfo e) {
      var r = 0;
      if (!e.isFavorite) r += 2;
      if (muscle != null && !e.primaryMuscles.contains(muscle)) r += 1;
      return r;
    }

    out.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
```
`noEquipment = 'none'` matches exercises with null equipment. There is no relevance score: order = favourites first, primary-muscle before secondary, then name (case-insensitive). `matchedAlias(e, aliases)` returns the alias that caused the match when the exercise's own name did not.
```dart
lib/features/library/domain/exercise_aliases.dart:59-87
List<String> searchTokens(String text, {bool stem = true}) {
  final out = <String>[];
  for (final raw in text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').split(' ')) {
    if (raw.isEmpty) continue;
    out.add(stem ? _stem(raw) : raw);
  }
  return out;
}

String _stem(String w) {
  if (w.length <= 3) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('yes')) return w.substring(0, w.length - 2); // flyes → fly
  if (RegExp(r'(ches|shes|sses|xes)$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

/// Whether the search [query] finds [name]: spaces, hyphens and plurals are ignored, and a word typed half-way ("ons") still matches.
bool searchMatches(String name, String query) {
  bool tryWith(bool stem) {
    final q = searchTokens(query, stem: stem), t = searchTokens(name, stem: stem);
    if (q.isEmpty) return true;
    final spaced = t.join(' '), compact = t.join();
    return q.every(spaced.contains) || compact.contains(q.join());
  }

  return tryWith(false) || tryWith(true);
}
```
- Alias map `buildAliases(usedNames, myRoutines, canonicalProgram, liftoffMap)` (`exercise_aliases.dart:3-56`): (a) routine/session `displayName` per exercise id; (b) `my_routines.json` rows' `name` and `program_exercise` per `exercise_id`, plus slot->exercise-id map; (c) program slots' `exercise` and each substitution (string, or map `name`/`exercise`) aliased to the exercise id filling that slot; (d) Liftoff name map: string value, `{id}`, each `by_weight[].id`, aliased with the Liftoff name.
- `ExerciseNameResolver` (`name_resolver.dart`): exact key (lowercase, strip non `[a-z0-9]`) -> score 1; else Dice of `MediaMatcher.normalizeTokens(_expand(name))` sets, where `_expand` maps `\bDB\b`->'dumbbell', `\bRDL\b`->'romanian deadlift', `\bFlye\b`->'fly' (case-insens.), `\bPressdown\b`->'pushdown' (case-insens.); candidates sorted score desc then shorter library name; entries with `score > 0` kept, default `limit` 3; `resolve(name, minScore = 0.6)` returns the best if `>= minScore`.
- Muscle mapping (`muscle_mapping.dart`): hand-authored table `assets/exercise_muscles.json` (111 ids) overrides; else `deriveTargets(name, primary, secondary)`: secondary at 0.3 then primary at 1.0 mapped to 20 ranking muscles (later `max`): chest -> `incline` => upperChest w + lowerChest w*0.5; `decline|dip` => lowerChest w + upperChest w*0.3; else lowerChest w + upperChest w*0.6; shoulders -> rear-delt words (`reverse fly|reverse flye|rear delt|face pull|rear lateral|bent over lateral|bent-over lateral|reverse machine`) => rearDelt; `lateral|upright row|side raise|y raise|y-raise` => middleDelt; `front raise|front cable raise|front plate|front dumbbell raise|front incline` => frontDelt; `row|pull|chin` => rearDelt; else frontDelt (+ middleDelt w*0.5 if `press|military|overhead|arnold|push press|jerk|handstand`); lats->lats; middle back->upperBack; traps->traps; lower back->lowerBack; abdominals -> (`oblique|twist|side bend|woodchop|wood chop|side plank|pallof|russian|windmill|side jackknife` => obliques w + abdominals w*0.4) else abdominals; biceps/triceps/forearms/quadriceps/hamstrings/glutes/calves/abductors/adductors 1:1; neck->traps w*0.3. Port from `muscle_mapping.dart:60-138`. Muscle keys (snake_case, from the JSON asset): lower_chest, upper_chest, front_delt, middle_delt, rear_delt, upper_back, lower_back, lats, traps, biceps, triceps, forearms, abdominals, obliques, quadriceps, hamstrings, glutes, calves, abductors, adductors.
- Load kinds (`library/domain/load_kinds.dart`): `assistedExerciseIds = {'sp_assisted_pull_up_machine','sp_assisted_dip_machine','Band_Assisted_Pull-Up'}` (assistance logged as negative weight; effective load = bodyweight + weight); `extraBodyweightExerciseIds = {...assistedExerciseIds, 'Hyperextensions_Back_Extensions'}`.

### 2.6 Exercise merge (`library/data/exercise_merger.dart`)
Runs at every start (after seeding) and after the Liftoff import; idempotent and cheap when nothing to merge. `apply({merges})`: read `existing id->name`; in ONE transaction for each merge in file order: skip if canonical row missing; rename canonical when `canonical_name` differs; skip if duplicate row absent; `_mergeOne`; drop duplicate from `existing`. If anything merged, append `{duplicate,duplicate_name,canonical,canonical_name,history_rows,routine_rows}` to the `exercise_merges_log` setting.
```dart
lib/features/library/data/exercise_merger.dart:97-117
  Future<MergeResult> _mergeOne(ExerciseMerge m, String dupName, String canonName) async {
    final dup = Variable.withString(m.duplicate), canon = Variable.withString(m.canonical);
    final hist = await _count('session_exercises', m.duplicate);
    final routine = await _count('routine_exercises', m.duplicate);

    // What the logs called it stays: sessions without their own name keep the duplicate's.
    await _db.customUpdate('UPDATE session_exercises SET display_name = ? WHERE exercise_id = ? AND display_name IS NULL',
        variables: [Variable.withString(dupName), dup], updates: {_db.sessionExercises});
    for (final table in const ['session_exercises', 'routine_exercises', 'ego_freezes']) {
      await _db.customUpdate('UPDATE $table SET exercise_id = ? WHERE exercise_id = ?', variables: [canon, dup]);
    }
    // One row per exercise: the canonical's wins, the duplicate's is only used when it has none.
    for (final table in const ['media_matches', 'pinned_videos', 'edb_v2_maps']) {
      await _db.customUpdate('UPDATE OR IGNORE $table SET exercise_id = ? WHERE exercise_id = ?', variables: [canon, dup]);
      await _db.customUpdate('DELETE FROM $table WHERE exercise_id = ?', variables: [dup]);
    }
    await _carryOver(m);
    await _rekeySettings(m);
    await _db.customUpdate('DELETE FROM exercises WHERE id = ?', variables: [dup], updates: {_db.exercises});
    return MergeResult(merge: m, historyRows: hist, routineRows: routine, duplicateName: dupName, canonicalName: canonName);
  }
```
`_carryOver`: canonical `isFavorite = canon || dup`; `images` from dup only if canonical's list empty; `extraImages` = union (canonical first, dedup); `edbV1Id` from dup if canonical null; `instructions` from dup if canonical empty; `notes` from dup if canonical empty/null. `_rekeySettings` (duplicate key -> canonical; `putIfAbsent` so canonical's own choice wins): `rank_manual` map, `rank_auto_on` list (adds canonical, sorted), `gym_equipment` JSON sub-maps `type_overrides`,`per_exercise`,`max_loads`, `form_resets` map. 22 merges in `exercise_merges.json` (e.g. `edbv1_oHsrypV` -> `Thigh_Adductor`, renamed "Machine Seated Hip Adduction"). Test (`exercise_merge_test.dart:105`): no chains, canonicals have a standard or muscle weights, no self-merge.

### 2.7 Liftoff CSV import
Header: `Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes`. Required columns (by name, after trimming and stripping BOM): Date, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, RPE, Notes; missing -> `FormatException('Not a Liftoff export: missing "<col>" column')`; empty file -> `FormatException('Empty file')`. Workout Name is ignored (always empty in the owner's export).
```dart
lib/features/import/domain/liftoff.dart:6-8,51-58
const double lbPerKg = 2.20462;
double lbToKg(double lb) => lb / lbPerKg;
Duration parseLiftoffDuration(String s) {  // "01 hours 20 minutes 14 seconds"
  int part(String unit) => int.tryParse(RegExp('(\\d+)\\s*$unit').firstMatch(s)?.group(1) ?? '') ?? 0;
  return Duration(hours: part('hour'), minutes: part('minute'), seconds: part('second'));
}
DateTime parseLiftoffDate(String s) => DateTime.parse(s.trim().replaceFirst(' ', 'T'));  // local time
```
Row rules (`parseLiftoff` `:170-229`): custom RFC4180 parser (quoted fields, doubled quotes, CRLF/LF, skips blank rows); sessions keyed by exact `Date` string; exercises grouped within a session by exact name in file order; sets sorted by `Set Order` (fallback running index); weight = `lbToKg(Weight)` full precision (unparsable -> 0); RPE optional double. Skipped rows (`SkippedRow(line, reason, exercise)`): empty exercise or date -> `'no exercise'`; `reps<=0 && (distance>0 || seconds>0)` -> `'cardio/timed (distance ${dist}km, ${secs.round()}s)'`; `reps<=0` -> `'0 reps'`. Sessions sorted by start.
Note scheme (`parseNote`): first non-empty note of the exercise; flags `pause`, `failure`, `perSide` (`per leg|per side|per arm`); trailing technique letter via `[.\s]+([A-Za-z])\s*$` when the remainder contains a digit (kept as uninterpreted letter); `per (leg|side|arm)` removed; split on `/`; each part regex `^(?:(\d+)\s*\*\s*)?(\d+)(?:\s*-\s*(\d+))?$` => `times` copies of `RepRange(lo,hi)` (part skipped if `hi < lo` or `times > 10`). `rangeFor(i)` = `ranges[min(i, last)]` (null if none).
```dart
lib/features/import/domain/liftoff.dart:77-83
  int repsFor(int index, int logged) {
    final r = rangeFor(index);
    if (!perSide || r == null) return logged;
    return logged >= r.max * 1.5 ? (logged / 2).round() : logged;
  }
```
Name mapping (`import/domain/liftoff_mapping.dart`), names iterated sorted; precedence per name: (1) manual pick (id in catalog) -> `manual`, conf 1; (2) name-map `by_weight` rules (all ids in catalog) -> `override`, conf 1, `exerciseId` = lightest band (last rule; rules sorted heaviest first), resolved per session by `topKg >= minKg`; (3) name-map id in catalog -> `override`, conf 1, displayName = routine's name if a routine row with the same `nameKey` has the same exercise id else the Liftoff name; (4) name-map `custom` -> `custom`, conf 1, id `liftoffCustomId`; (5) routine name (`nameKey` equal, exercise in catalog) -> `routine`, conf 1, displayName = routine's name; (6) `ExerciseNameResolver(catalog.where(!isCustom || id startsWith 'liftoff_')).resolve(name, minScore: 0.8)` -> `exact` if `nameKey` equal else `fuzzy`, confidence = score; (7) otherwise `unmatched` -> custom exercise of the same name (`liftoffCustomId(name)`, `CustomSpec(name)`), confidence = best candidate score or 0.
```dart
lib/features/import/domain/liftoff_mapping.dart:38-40,143-155
String liftoffCustomId(String liftoffName) =>
    'liftoff_${liftoffName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '')}';
  bool get needsReview => method == MatchMethod.unmatched || (method == MatchMethod.fuzzy && confidence < 0.9);
String nameKey(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .map((t) => t.length > 3 && t.endsWith('s') && !t.endsWith('ss') ? t.substring(0, t.length - 1) : t)
    .join(' ');
const double fuzzyAcceptScore = 0.8;
```
`MatchMethod` labels: manual 'Picked', override 'Name map', routine 'My routine', exact 'Exact', fuzzy 'Fuzzy', custom 'New custom', unmatched 'Unmatched'. Preview (`liftoff_import_service.dart:79-109`): parse, count sets per name, map names (routine names = `displayName ?? catalog name ?? id` of all routine exercise rows), compare session keys with existing `sessions` of source `liftoff` -> `newSessions` / `alreadyImported`; "Check these" = `needsReview` mappings.
Bodyweight prompt (UI, `import/presentation/liftoff_import_screen.dart:79-98`): before commit, if `BodyWeightRepository.latest()` is null show "Your bodyweight" number prompt (kg; message "Apple Health has no weight for you. Ranks compare your lifts to your bodyweight, so enter it once (you can change it in Settings)."); `kg == null || kg < 30 || kg > 300` -> error 'Import needs a bodyweight between 30 and 300 kg.' and abort; else `addManual(kg)` (source `manual`).
Commit (`:115-232`), idempotent; all inserts in ONE transaction:
```dart
lib/features/import/data/liftoff_import_service.dart:149-212
      for (final s in preview.newSessions) {
        final already = await (_db.select(_db.sessions)
              ..where((t) => t.source.equals(liftoffSource) & t.externalId.equals(s.key)))
            .getSingleOrNull();
        if (already != null) continue;
        final resolved = [
          for (final e in s.exercises) mapping[e.name]!.resolveFor(e.sets.map((x) => x.weightKg).reduce(math.max)),
        ];
        final ids = [for (final r in resolved) r.$1];
        final routine = _guessRoutine(ids, routines);
        final sessionId = await _db.into(_db.sessions).insert(SessionsCompanion.insert(
              name: routine?.$2 ?? 'Liftoff workout',
              routineId: Value(routine?.$1),
              startedAt: s.start,
              endedAt: Value(s.end),
              status: const Value('finished'),
              notes: const Value('Imported from Liftoff'),
              source: const Value(liftoffSource),
              externalId: Value(s.key),
            ));
        sessions++;
        final total = math.max(1, s.setCount);
        var setIndex = 0;
        for (var i = 0; i < s.exercises.length; i++) {
          final e = s.exercises[i];
          final scheme = e.scheme;
          final reps = [for (var j = 0; j < e.sets.length; j++) scheme.repsFor(j, e.sets[j].reps)];
          final observed = RepRange(reps.reduce(math.min), reps.reduce(math.max));
          final first = scheme.rangeFor(0) ?? observed;
          final (exerciseId, displayName) = resolved[i];
          final assisted = isAssisted(exerciseId) || isLiftoffAssisted(e.name);
          final loadScale = liftoffTotalLoadIds.contains(exerciseId) ? 0.5 : 1.0;
          final exId = await _db.into(_db.sessionExercises).insert(SessionExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: exerciseId,
                position: i,
                repMin: first.min,
                repMax: first.max,
                targetSets: e.sets.length,
                restSeconds: 120,
                targetRir: const Value(0),
                notes: Value(e.sets.map((x) => x.note).firstWhere((n) => n.isNotEmpty, orElse: () => '')),
                displayName: Value(displayName),
              ));
          for (var j = 0; j < e.sets.length; j++) {
            final x = e.sets[j];
            final target = scheme.rangeFor(j);
            await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
                  sessionExerciseId: exId,
                  position: j,
                  weight: Value((assisted ? -x.weightKg.abs() : x.weightKg) * loadScale),
                  reps: Value(scheme.repsFor(j, x.reps)),
                  rpe: Value(x.rpe ?? 10),
                  completed: const Value(true),
                  // Liftoff only keeps the session start and length; spread the sets across it.
                  completedAt: Value(s.start.add(s.duration * ((setIndex + 1) / total))),
                  targetRepMin: Value(target?.min),
                  targetRepMax: Value(target?.max),
                  targetRir: const Value(0),
                ));
            setIndex++;
            sets++;
          }
        }
      }
```
```dart
lib/features/import/data/liftoff_import_service.dart:19-31,260-272
const liftoffSource = 'liftoff';
const liftoffImportedAtKey = 'liftoff_imported_at';
const int liftoffStreakDays = 177;
const liftoffTotalLoadIds = {'sp_db_walking_lunge'};
  static (int, String)? _guessRoutine(List<String> ids, List<(int, String, Set<String>)> routines) {
    (int, String)? best;
    var bestHits = 0;
    for (final (id, name, set) in routines) {
      final hits = ids.where(set.contains).length;
      if (hits > bestHits) {
        bestHits = hits;
        best = (id, name);
      }
    }
    return bestHits * 2 >= ids.length && bestHits > 0 ? best : null;
  }
```
Rules summary: idempotency key = (`source='liftoff'`, `external_id` = CSV Date string) via unique index + per-session pre-check; custom exercises are created first with `insertOrIgnore` (name from `CustomSpec`, mechanic compound|isolation, category `strength`, `is_custom=true`, notes 'Created by the Liftoff import.', skipped when id already in the catalog); session name = routine sharing the most exercises when hits*2 >= number of exercises, else 'Liftoff workout'; no suggested weights/overrides; RPE default 10 (RIR 0); `xp_earned` stays 0 (no XP); assisted (`isAssisted(id)` or Liftoff name contains 'assisted') stored as negative load; Walking Lunge halved; `completedAt` spread evenly over the session duration. Inside the same transaction, after all sessions: if `sessions > 0` and `liftoff_imported_at` unset, set it (ISO now) and, if `streak_offset` unset, write `StreakOffset(date: now, days: 177)`. After the transaction: `ExerciseMerger(_db).apply()` then (if sessions > 0) `FinishService(_db).reevaluateAchievements(...)` (no XP). Result: sessions, sets, customsCreated, achievements. Imported history never switches an exercise on for ranks. Owner's file (docs/IMPORT_SUMMARY.md header): 124 sessions, 1686 sets, 6 skipped rows, 12 customs, name map 57 entries.

### 2.8 Ranks data, ladder migration, exclusions (data layer only)
- `RanksRepository.compute` (`ranks_repository.dart:49-90`): `RankSummary.empty` if no bodyweights; window = last `RankCalculator.windowDays = 90` days (`ranks/domain/ranks.dart:491`) from `dateOnly(now)`; sessions with `startedAt` in `[from, now]`; only `set.isValidForRecords` working sets; each set scored at `bodyweights.at(s.startedAt)`; ranking names = routine display name else library name; `excluded` = exercises not counting toward rank.
- `bodyweightLoadedIds` = standards flagged bodyweight-loaded ids + catalog exercises with `EquipmentKind.bodyweight` + `extraBodyweightExerciseIds`.
- `RankPolicy.sourceOf`: manual (true/false) > in any current routine row > auto (`rank_auto_on`) > off. `autoEnable(id)` is a no-op when a manual choice exists. `RankExclusions.ensureMigrated` (once, `rank_policy_v2`): legacy hidden exercises that are in routines -> manual false; exercises with a completed non-warm-up, `set_type IS NULL`, `reps > 0` set in `source='app'` sessions -> auto.
- `migrateRankLadder` (`ladder_migration.dart`): `rankLadderVersion = 8`; silent rename of stored achievements (`lift_immortal` -> `lift_olympian`, `lift_radiant` -> `lift_immortal`, once via `rank_tier_rename_v8`); unlock newly met, revoke retired keys and rank-based achievements no longer met; stays pending (no revoke) when ranks unknown (no bodyweight).
- Standards parse: `machine_strictness` default 1; `scaling{reference_bodyweight, exponent}` else linear. Tier entry points (file description): Iron 0, Bronze=beginner, Silver=novice, Gold=midpoint(novice,intermediate), Platinum=intermediate, Emerald=midpoint(intermediate,advanced), Diamond=advanced, Master=elite, Grandmaster=elite x1.15, Challenger=elite x1.30 (ladder v6/v8 renamed tiers; `RankCalculator` is another section).
- Body map (`ranks/data/body_map.dart`): `upperChestFraction = 0.45`, `middleDeltFraction = 0.40`; chest path clipped top 45% -> upperChest, rest lowerChest; deltoids: outer 40% -> middleDelt, inner -> frontDelt (front view) / rearDelt (back view); `upper-back`: bounds height > 100 -> lats else upperBack; `gluteal`: height < 70 -> abductors else glutes; other slugs via `bodySlugToMuscle`.

### 2.9 Readiness repository and body weights (data only)
- `ReadinessRepository.sync(source, now, days = 45)`: `from = DateTime(today.year, today.month, today.day - days - 1, 12)`; fetch HRV SDNN, resting HR, active energy, dietary energy and protein (last two with `.catchError -> []`), sleep intervals; aggregate per day with `DailyMetricsAggregator.aggregate`; energy/food/protein summed by `dayKey(sample.to)`; upsert `days+1` rows (`DoUpdate`), `recomputeScores(sinceDays: days)` (writes `readiness_score`, `readiness_band` = null when calibrating else band name, `calibrating`, `explanation`); then body-mass history of the last **365 days** (`_storeBodyMass`: insert `source:'health'` unless a row with the same `(source, measured_at)` exists) plus `latestBodyMass`. Seed generator uses `days: 90`.
- `BodyWeightRepository.latest()` = `ORDER BY measured_at DESC, id DESC LIMIT 1`; `addManual(kg, at ?? now)` source `manual`.

### 2.10 Tutorials / media

#### 2.10.1 ExerciseDB V1 GIF matching (`media_repository.dart`, `media_matcher.dart`, `gif_rule.dart`)
- `ensureMatched(catalog, now)`: `todo` = exercises without a row when stored `media_match_version == 4`, else all exercises whose row source != `manual`; if `todo` empty only bump the version. Per exercise (matching runs in an Isolate): (1) no override for the id AND `catalog[id].edbV1Id` present in V1 data -> **own GIF**: row source `library`, confidence 1, stored only if `gifVerdict == ok` (else null edb fields); (2) override exists (even `null`) -> source `override`, confidence 1, picked V1 entry stored only if it passes `gifVerdict`; (3) else best auto candidate: edb fields stored only when `confidence != none` (score >= 0.5), `confidence = best?.score ?? 0`, source `auto`. Upsert with `DoUpdate`. Manual picks: `setManual(id, edb|null)` -> source `manual`, confidence 1, never overwritten. `exportOverrides` emits rows with source `override|manual` as `{schema_version:1, overrides:{id: edbId}}`.
- GIF cache `CacheManager(Config('exercise_gifs', stalePeriod: const Duration(days: 365), maxNrOfCacheObjects: 2000))`; GIFs download on first view; `prefetch(ids)` downloads those not cached.
```dart
lib/features/tutorials/domain/media_matcher.dart:98-103
  static const double wName = 0.6, wEquipment = 0.25, wMuscle = 0.15;
  static const double highThreshold = 0.72;
  static const double lowThreshold = 0.5;

  static MatchConfidence confidenceFor(double score) =>
      score >= highThreshold ? MatchConfidence.high : (score >= lowThreshold ? MatchConfidence.low : MatchConfidence.none);
```
```dart
lib/features/tutorials/domain/media_matcher.dart:185-201
  double _idf(String t) => math.log((edb.length + 1) / ((_df[t] ?? 0) + 1)) + 1;

  double nameSimilarity(Set<String> a, EdbExercise e) {
    final b = _tokens[e.id]!;
    var common = 0.0, wa = 0.0, wb = 0.0;
    for (final t in a) {
      wa += _idf(t);
      if (b.contains(t)) common += _idf(t);
    }
    for (final t in b) {
      wb += _idf(t);
    }
    final tokenDice = (wa + wb) == 0 ? 0.0 : 2 * common / (wa + wb);
    final ga = _grams(a.join(' ')), gb = _trigrams[e.id]!;
    final triDice = (ga.isEmpty || gb.isEmpty) ? 0.0 : 2 * ga.intersection(gb).length / (ga.length + gb.length);
    return 0.7 * tokenDice + 0.3 * triDice;
  }
```
(`_grams(s)` = set of character trigrams of `' $s '`; only entries with `gifAvailable` are indexed; `edb.length` = number of available entries.) Normalisation (`normalizeTokens` `:164-178`): lowercase; replace phrases longest-key-first; strip `[^a-z0-9 ]` to space; split on whitespace; drop stop-words; map through `_singular`, then generic `length > 4 && endsWith('s') && !endsWith('ss')` -> drop `s`. Tables (condensed; one entry per line in source):
```dart
lib/features/tutorials/domain/media_matcher.dart:107-133,138-162
  static const _phrases = {
    'pull-up': 'pull up', 'pullup': 'pull up', 'pullups': 'pull up', 'chin-up': 'chin up', 'chinup': 'chin up',
    'push-up': 'push up', 'pushup': 'push up', 'pushups': 'push up', 'sit-up': 'sit up', 'situp': 'sit up',
    'e-z': 'ez', 'dumbell': 'dumbbell', 'skullcrusher': 'skull crusher', 'pushdown': 'pushdown',
    'hamstring curl': 'leg curl', 'butterfly': 'machine seated fly', 'pec deck': 'machine seated fly',
    'leverage': 'machine', 'lever': 'machine', 'military press': 'shoulder press', 'overhead press': 'shoulder press',
    'hip thrust': 'hip thrust', 'romanian deadlift': 'romanian deadlift', 'stiff-legged': 'stiff leg', 'stiff legged': 'stiff leg',
  };
  static const _singular = {
    'ups': 'up', 'flyes': 'fly', 'flys': 'fly', 'flies': 'fly', 'raises': 'raise', 'curls': 'curl', 'extensions': 'extension',
    'rows': 'row', 'presses': 'press', 'squats': 'squat', 'lunges': 'lunge', 'deadlifts': 'deadlift', 'crunches': 'crunch',
    'dips': 'dip', 'shrugs': 'shrug', 'kickbacks': 'kickback', 'pulldowns': 'pulldown', 'pushdowns': 'pushdown',
    'calves': 'calf', 'dumbbells': 'dumbbell', 'kettlebells': 'kettlebell',
  };
  static const _stop = {'the', 'a', 'an', 'with', 'on', 'of', 'to', 'and', 'version', 'medium', 'grip', 'v', 'exercise', 'iso'};
```
Equipment compatibility (`equipmentScore(ours, theirs)`: ours unknown/null -> 0.5; no overlap -> 0; every V1 equipment compatible -> 1 else 0.6):
```dart
lib/features/tutorials/domain/media_matcher.dart:205-217
  static const Map<String, Set<String>> _equipment = {
    'barbell': {'barbell', 'olympic barbell', 'trap bar'},
    'dumbbell': {'dumbbell'},
    'cable': {'cable', 'rope'},
    'machine': {'leverage machine', 'smith machine', 'sled machine'},
    'kettlebells': {'kettlebell'},
    'body only': {'bodyweight', 'weighted', 'assisted'},
    'bands': {'resistance band', 'band'},
    'e-z curl bar': {'ez bar'},
    'medicine ball': {'medicine ball'},
    'exercise ball': {'stability ball'},
    'foam roll': {'roller'},
  };
```
Muscle score: our primary dataset muscles mapped to coarse groups (chest, lats->back, middle back->back, lower back->null, shoulders, biceps, triceps, forearms, abdominals->abs, quadriceps->quads, hamstrings, glutes, abductors->glutes, adductors->null, calves, traps, neck->null) vs V1 `targetMuscles` (abdominals->abs, pectorals->chest, glutes, biceps, triceps, deltoids->shoulders, upper back->back, latissimus dorsi->back, calves, quadriceps->quads, forearms, hamstrings, trapezius->traps, levator scapulae->traps, abductors->glutes): intersection -> 1; our secondary intersects -> 0.7; else 0; 0.5 when either side empty; special 1 for lower back<->erector spinae and adductors<->adductors.
`match(ex)`: candidate pool = V1 entries sharing any normalised token (inverted index); skip `nameSimilarity < 0.2`; skip unless `gifVerdict == ok`; score = `0.6*name + 0.25*equipment + 0.15*muscle`; sort score desc, ties = shorter V1 name; keep top 3; best used only if score >= 0.5.
**Strict GIF rule** (`gif_rule.dart`): a GIF is shown only for the same movement on the same equipment.
```dart
lib/features/tutorials/domain/gif_rule.dart:5-28,52-70   (condensed sets; verdict function verbatim)
const _modifiers = {
  'incline', 'decline', 'reverse', 'front', 'sumo', 'romanian', 'stiff', 'hammer', 'preacher', 'concentration', 'unilateral', 'bulgarian',
  'goblet', 'hack', 'pendulum', 'walking', 'jump', 'side',
};
const _synonyms = {
  'straight': 'stiff', 'rear': 'reverse', 'one': 'unilateral', 'single': 'unilateral', 'alternate': 'unilateral',
  'alternating': 'unilateral', 'jumping': 'jump', 'split': 'unilateral', 'lunge': 'unilateral', 'step': 'unilateral',
};
const _coreNouns = {
  'press', 'row', 'curl', 'fly', 'raise', 'extension', 'squat', 'lunge', 'deadlift', 'pulldown', 'pushdown', 'pullover', 'shrug', 'crunch',
  'thrust', 'kickback', 'dip', 'twist', 'chop', 'abduction', 'adduction', 'pull', 'push', 'swing', 'crusher',
};
enum GifVerdict { ok, noGif, wrongEquipment, wrongMovement }
GifVerdict gifVerdict({required String name, required String? equipment, required EdbExercise edb, required MediaMatcher matcher}) {
  if (MediaMatcher.equipmentScore(equipment, edb.equipments) < 1 && equipment != null && equipment.toLowerCase() != 'other') {
    return GifVerdict.wrongEquipment;
  }
  if (_diff(modifierTokens(name), modifierTokens(edb.name)).isNotEmpty) return GifVerdict.wrongMovement;
  final a = coreNouns(name), b = coreNouns(edb.name);
  if (a.isNotEmpty && b.isNotEmpty && a.intersection(b).isEmpty) return GifVerdict.wrongMovement;
  if (matcher.nameSimilarity(MediaMatcher.normalizeTokens(name).toSet(), edb) < 0.45) return GifVerdict.wrongMovement;
  return GifVerdict.ok;
}
```
`modifierTokens(name)`: lowercase name with `side lateral`->`lateral`, `palms-down`/`palms down`->`reverse`, `front lat pulldown`->`lat pulldown`; normalised tokens mapped through `_synonyms`, kept if in `_modifiers`. `coreNouns(name)` first rewrites regex `lying triceps (press|extension)` -> `skull crusher`, then keeps normalised tokens in `_coreNouns`. A GIF that fails to load at runtime falls back to library photos (DECISIONS).
Display rules (DECISIONS Phase A / Fix 4): list thumbnails = static image in order free-exercise-db photo -> wger image -> first frame of the V1 GIF -> placeholder with equipment icon, never YouTube thumbnails. Exercise page: GIF (else photos) + Steps; program exercises also get a "Jeff Nippard demo" video card (autoplay off). In-workout (i) sheet: GIF first, "Watch Jeff's demo" button reveals the video on request.

#### 2.10.2 ExerciseDB V2 client + budget (off by default; debug-only)
```dart
lib/features/tutorials/data/edb_v2/edb_budget.dart:13-15,40-45
  static const int planLimit = 2000;
  static const int softLimit = 1500;
  static const int hardLimit = 1850;
  bool get warn => used >= softLimit;
  bool get stopped => used >= hardLimit;
  bool allows(DateTime now) => !current(now).stopped;
```
Budget rules (`edb_budget.dart`): counted per calendar month `yyyy-MM` (local time), reset when the month changes (`current(now)` -> fresh); `used` = `headerLimit - headerRemaining` when both headers `x-ratelimit-requests-limit` / `x-ratelimit-requests-remaining` have been seen (headers win), else `localCount`; `record(now, headers)` increments `localCount` and keeps latest header values; `resumesOn()` = first day of next month; persisted as setting `edb_budget` JSON `{month, local, hlimit?, hremaining?, last?}`.
Client (`edb_client.dart`): host `edb-with-videos-and-images-by-ascendapi.p.rapidapi.com`; key from compile-time `--dart-define EDB_RAPIDAPI_KEY` (`config/secrets.json`, git-ignored, never logged; key replaced by `***` in network error text); headers `X-RapidAPI-Key`, `X-RapidAPI-Host`; timeout 15 s; endpoints `GET /api/v1/exercises/search?search=<q>` (`data[]` of `{exerciseId,name,imageUrl}`) and `GET /api/v1/exercises/{id}` (`data`). Every call: no key -> `EdbException(0,'NO_KEY')`; load budget; if `!allows(now)` -> log `fallback` and throw `EdbException(0,'BUDGET',...)` with no network; request; network failure -> log + `NETWORK`; record budget and save; log (`call` for 200 else `error`); log one `warn` when this call crosses 1500; non-200 -> parse `error.code/message` else `HTTP_<status>`. `fallsBack` = status in {401,403,429} or code in {DISABLED,BUDGET,NO_KEY,NETWORK}. Log keeps the last `maxLog = 100`. `edbApiProvider` returns `EdbDisabled` (every call fails `DISABLED`, no network) unless setting `edb_v2_enabled == 'true'`. Tests never hit the network (`edb_budget_test`, `edb_mapping_test`).
Mapping (`edb_v2_mapping.dart`, `edb_mapping_repository.dart`):
```dart
lib/features/tutorials/domain/edb_v2_mapping.dart:106-110,128-138
  /// Name 70 %, equipment 30 %; a muscle check (when fetched) moves it by ±0.1.
  double get score {
    final base = 0.7 * nameScore + 0.3 * equipmentScore;
    final m = muscleScore;
    return m == null ? base : (base + (m >= 1 ? 0.1 : -0.1)).clamp(0.0, 1.0);
  }
const double autoAccept = 0.85;
const double autoMargin = 0.08;
bool isConfident(List<EdbCandidate> ranked) {
  if (ranked.isEmpty) return false;
  final top = ranked.first.score;
  final second = ranked.length > 1 ? ranked[1].score : 0.0;
  return top >= autoAccept && top - second >= autoMargin;
}
```
Query = library name minus `\s*\(.*?\)` groups, first part of `split(' - ')`, whitespace collapsed. Equipment score vs the candidate **name** words (`_equipmentWords`: barbell {barbell,bar}, e-z curl bar {ez,barbell,bar}, dumbbell {dumbbell}, cable {cable,rope,pulley}, machine {lever,machine,smith,sled,assisted,leverage}, kettlebells {kettlebell}, bands {band,resistance}): candidate names no equipment -> 1 if ours unknown else 0.5; names equipment but ours unknown -> 0.3; overlap -> 1 else 0. Name score = Dice of normalised tokens minus all equipment words. `mapOne(info, api, detailCalls)`: 1 search call; if not confident and top score >= 0.6 and `detailCalls > 0` -> 1 detail call, `muscleAgreement` (1 on overlap of `muscleForV2(target)` with our prime movers (weights >= 1); 0.5 if either side empty; else 0) shifts top score by +-0.1, re-sort. Status: no candidates `none`; confident `auto` (edbId stored); else `queued` (edbId null). Stored: edbId, status, confidence, query (candidates always `'[]'`). `mapBatch(infos, api, maxCalls = 150)`: skips rows already `confirmed`/`auto`; per item `spare = maxCalls - calls - remainingSearches`, detail call allowed only when `spare > 0`; items beyond `calls >= maxCalls` go to `skipped`. `confirm` -> status `confirmed`, confidence 1; `markNone` -> status `none`. `seedFromAsset` inserts only rows not present and not in the merged-duplicate skip set. `exportJson` = `{schema_version:1, description, mappings{id:{edbId,status,confidence (3 dp),query}}}` (indent 1 space, trailing newline). Initial run (docs): 145 of 150 calls; 24 auto, 84 queued, 3 none (111 exercises). `muscleForV2` (`edb_v2_mapping.dart:50-80`) maps V2 muscle names to the 20 muscles; `targetsFromV2` exists but V2 is not used for muscle data (DECISIONS). AscendAPI policy: IDs permanent, media URLs rotate Mondays 00:00 UTC, never persist API text/media.

#### 2.10.3 YouTube handling and Jeff videos
- `parseYouTubeLink(input)`: bare id `^[A-Za-z0-9_-]{11}$`; hosts `youtu.be`, `youtube.com`, `youtube-nocookie.com` (strip `www.|m.|music.`); paths `/watch?v=`, `/shorts|embed|live|v/<id>`; start from query `t` or `start` via `parseTimestamp` (`90`, `90s`, `1m30s`, `1h2m3s`, `1:30`, `1:02:03`; `formatTimestamp` inverse). `YouTubeRef(videoId, startSeconds)`: `watchUri = https://www.youtube.com/watch?v=<id>[&t=<n>s]`, `thumbnailUri = https://i.ytimg.com/vi/<id>/hqdefault.jpg`.
- Only program videos from the bundled JSON (`video.url`, `substitution_videos`): 73 of 73 program names have one (DECISIONS). User YouTube search/pinning/API key removed; `pinned_videos` unused. Player = embedded iframe, autoplay off.
- `programVideos` matching (`program_videos.dart:39-89`): for each routine row with slots: `relation=='program'` -> slot's own exercise video; otherwise a listed substitution whose normalised key equals the row's display name or library name and that has its own link; or (`relation=='substitution'` with `programExercise`) a substitution resolved to the row's library exercise by `ExerciseNameResolver.resolve(sub, minScore: 0.85)`; `relation=='swap'` without a match -> excluded; finally every non-custom library exercise resolving to any program video name at `minScore: 0.85` and not a swap gets that video (`putIfAbsent`). `_key` = lowercase, non-alnum -> space, trimmed, `reverse wrist curl` -> `wrist extension`.

#### 2.10.4 Exercise audit (debug; summarised)
`ExerciseAuditRepository` + `exercise_audit.dart`: for each exercise used (in routines or with completed working sets) compute `gifVerdict` of its stored GIF and `standardVerdict` of its strength standard (ok / none / variant / mismatch via `coreNouns`, equipment words, `modifierDiff`; per-hand standards ignore `unilateral`); `nameSource` library|merged|custom|imported; routine exercises first then by name. Debug-only.

### 2.11 Seed generator (summary; debug builds, `debug/data/seed_generator.dart`)
`weeks = 12`, `bodyweight = 80.0`, `Random(42)`. Wipes training tables, enables fake Health, syncs 90 days of fake Health data, adds a body weight every 3 days, installs my routines, then simulates each day from the Monday 12 weeks ago to yesterday: skip `Rest` days of `program.weekLayout[day.weekday - 1]`, skip a Red-readiness day when `rng.nextBool()`, start about 18:00, build a `CoachContext`, `ensureQuests`, `SessionRepository.start`, complete each set with reps derived from a hidden e1RM (Epley inverted `30 * (e1rm/load - 1)` clamped 0.5..25, minus fatigue +0.5..0.8 per set, Red day penalty 1 rep, ego-override episodes {week1 and week2: Leverage_Chest_Press, week4 and week5: sp_pendulum_squat} at 110-115% of suggestion, hidden strength +0.4..0.6% per session), then call the real `FinishService.finish`. Test `seed_and_export_test.dart` expects 45 < sessions <= 60, >= 2 ego freezes, >80 readiness days, >500 CSV set rows, 3 CSV files, `schema_version == 1`.

### 2.12 Docs inventory (context)
`docs/PLAN.md` = original plan (architecture, v1 schema, packages, phases; stale: OQ-12). `docs/DECISIONS.md` (2131 lines) = authoritative rule changelog; relevant sections: Liftoff import (:283), ExerciseDB V2 (:888), Phase A library/media (:926), Fix 0 canonical week (:1119), never remove sets (:1340), Fix 4 GIF+video (:1195), plan freeze (:1553), duplicate exercises (:1611). `docs/export_schema.md` = export contract (OQ-5). `docs/program/SCHEMA.md` = old 12-week schema (OQ-6).

---------------------------------------------------------------------------------------------------
## 3. OPEN QUESTIONS
---------------------------------------------------------------------------------------------------

- OQ-1: `onUpgrade` never creates the non-unique indexes (`idx_sessions_started`, `idx_session_ex_*`, `idx_sets_session_ex`, `idx_routine_ex_routine`); only `onCreate` does (`database.dart:41-48` vs `50-110`). An install created at v1 got them at its own create time, unverifiable here. RN port can create all indexes on fresh create.
- OQ-2: Data fixes (`DataFixes`, `ensureRoutineSetCounts`, `ensureSingleArmReverseFly`, `RankExclusions.ensureMigrated`, `ensureCanonicalWeek`) are tied to the owner's legacy data. Unclear whether the RN port must open the existing SQLite file (then all migrations/fixes are needed) or start fresh (they are dead).
- OQ-3: Finish pipeline is NOT atomic: only prune + status/ended_at are in a transaction; XP rows, quest completions, ego freezes, achievement unlocks, `xp_earned`, health sync are separate writes (`finish_service.dart:218-296`). A crash midway leaves a finished session with partial rewards and no retry path. Intended?
- OQ-4: XP counts drop/myo/hold follow-up sets as working sets (10 XP each) because `LoggedSet.isWorking = !isWarmup && completed` and `XpRules.forSet` uses `isWorking`; `session.workingSets` likewise includes them. Docs say follow-ups count for volume but not PRs/ranks; whether XP-per-follow-up is intended is unclear.
- OQ-5: `docs/export_schema.md` vs code: (a) doc's CSV sets column list includes `set_type`, code's `setCsvColumns` does not (`export_schema.dart:59-85`); `partials`/`rest_seconds` are JSON-only; (b) doc's JSON set table omits `partials`; (c) doc says `set_type` is `warmup|working|drop` but code also emits `myo` and `hold`; (d) doc says `xp_events.reason` in (`session`,`weekly_goal`,`quest`) but code only writes `session` and `quest`; (e) export omits `sessions.source`, so Liftoff sessions are indistinguishable; (f) exported routines omit program fields, `display_name`, overrides, supersets, `program_day`; (g) `dietary_kcal`/`protein_g` not exported. Code wins.
- OQ-6: `docs/program/SCHEMA.md` documents `min_max_phase2.json` with per-slot `weeks{...}` and `prescribeSets(..., week)`, `program.weeks: 12`; the bundled file is `min_max_canonical.json` (schema_version 2, `canonical_week: 5`, no `weeks`, no technique per set, plus `video`/`substitution_videos`/`videos_source`). Doc is stale.
- OQ-7: `workout/data/routine_sync.dart` only does session->routine diff/update. No ongoing program<->routine sync exists (program linkage = install/conversion functions in `program_repository.dart`). Confirm nothing else is expected.
- OQ-8: Reinstall of routines when `my_routines.json` `schema_version` increases deletes ALL routines including user-created/edited ones (`program_repository.dart:211-214`); `sessions.routine_id` is not an FK so history keeps dangling ids (achievement `fullProgramWeeks` keys on routine ids). Intended?
- OQ-9: `MediaMatches.source` documented as `auto | override | manual` (`tables.dart:258`) but `ensureMatched` also writes `'library'` (`media_repository.dart:108`); `exportOverrides` filters only `override|manual`.
- OQ-10: `EdbV2Maps.candidates` documented as top candidates JSON (`tables.dart:295`) but `_put` always writes `'[]'` and ignores its `candidates` argument (`edb_mapping_repository.dart:41-42`); queued items cannot show candidates offline. Column is effectively dead.
- OQ-11: Two unrelated classes named `EdbExercise` (V1 in `media_matcher.dart`, V2 in `edb_client.dart`) and two `equipmentScore` functions (V1 static in `MediaMatcher`, V2 top-level in `edb_v2_mapping.dart`). Port carefully.
- OQ-12: `docs/PLAN.md` is stale (schemaVersion 1, 13-table schema, "weekly streak", YouTube url_launcher search which was removed). Not authoritative.
- OQ-13: Count mismatches: `exercises.json` has 876 entries and `extra_exercises.json` 9, DECISIONS says "873 + 11 built-in"; total seeded = 876 + 9 + 1488 = 2373 vs DECISIONS "2,372" / "2,373". The `exerciseDatasetVersion` comment says v5 adds `liftoff_one_arm_machine_reverse_fly` (not an `sp_` id) while the file comment says ids start with `sp_`. Trust the files.
- OQ-14: `liftoff_name_map.json` `exclude_from_ranks` is parsed to `NameMapping.excludeFromRanks` but never read outside `liftoff_mapping.dart` (grep). Exclusion in practice comes from the rank policy (imports never enable an exercise). Flag is redundant/dead.
- OQ-15: `ensureSeeded` writes `source: 'fedb'` for `extra_exercises.json` (`sp_*`, `liftoff_*`) too, so built-ins are indistinguishable from free-exercise-db entries except by id prefix; `liftoff_one_arm_machine_reverse_fly` (in extra_exercises) is not flagged `is_custom`, unlike import-created `liftoff_*` customs (same id prefix, different origin).
- OQ-16: `needsReason` uses `set.targetRepMin ?? exerciseRepMin` while the UI passes `ex.row.repMin` (the exercise-level min, which is the first slot's/override min); sets from later slots with a different range use their own `target_rep_min`. Consistent today; flagged for the port. `completeSet` only enforces the reason when `exerciseRepMin != null`.
- OQ-17: Several `customUpdate` calls in `ExerciseMerger` (exercise_id rewrites on `session_exercises`, `routine_exercises`, `ego_freezes`, media tables) omit `updates:` so drift streams are not notified for those tables; only the display_name update and the final delete notify. Probably harmless (merge runs before UI / is followed by a catalog change) but unverified.
- OQ-18: `HistoryRepository.load` loads every finished session/exercise/set into memory per call; `finish` calls it twice and evaluates `_ranks(before)` twice. Fine for ~124 sessions; performance with RN's SQLite bridge unknown.
- OQ-19: `deleteSession` removes that session's `xp_events` but leaves completed quests, unlocked achievements, ego freezes, `liftoff_imported_at`/streak offset untouched; intent unclear.
- OQ-20: `deleteCustomIfUnused` checks only `session_exercises` and `routine_exercises`; a custom exercise referenced by `ego_freezes`, `media_matches`, `edb_v2_maps` or settings (`rank_manual`, `gym_equipment`, `form_resets`) can be deleted leaving orphans.
- OQ-21: `Sessions.status='active'` uniqueness is not enforced; `activeSession()` uses `getSingleOrNull()` (throws on 2 rows, `session_repository.dart:166-167`) while `watchActive` picks the newest by `started_at`.
- OQ-22: `addSet` warm-up uses negative positions then `_renumber`; `restoreSet` shifts positions `>= set.position` and reinserts with the old id; tie order depends on `id`. Edge behaviour untested.
- OQ-23: Walking-lunge `_half` floors to 2.5 kg steps (37.5 -> 17.5, not 18.75) by design; v2 fix runs v1 implicitly, so the v1 key alone never gates anything after v2 ran.
- OQ-24: `lbPerKg = 2.20462` (not exact 2.20462262): weights arrive as e.g. 20.0000238 kg and are stored at full precision (DECISIONS). The port must replicate the constant AND the rounding noise tolerance (`_eps = 1e-3`, `_clean`, `snapNoise`) or 30 kg of assistance can floor to 32.5.
- OQ-25: `commit` does `mapping[e.name]!` for every exercise of every new session; a `preview` whose `mappings` were built with a different name map/manual picks than its sessions would throw. The UI always re-previews after a manual pick; not enforced by types.
- OQ-26: `streak_offset` is only written on the first import with `sessions > 0` when `liftoff_imported_at` is unset and `streak_offset` is null; `liftoffStreakDays = 177` is a hard-coded owner constant (DECISIONS "section 4"). A second import never changes it.
- OQ-27: `plannedRestWeekdays` returns ISO weekdays `i + 1` of `Rest` entries (layout is Monday-first); the seed generator indexes `weekLayout[day.weekday - 1]`. Users of these are outside this section.
- OQ-28: `EdbBudget.used` prefers server headers even if stale; `warn`/`stopped` then depend on the last response's headers, not the local count. Matches docs ("headers win") but the local counter can disagree.
- OQ-29: Quest XP is only awarded at finish; quests that become complete otherwise (e.g. via imported history) are never rewarded. `retireSuggestionQuests` deletes quests with keys `['followAll','noOverride']` on every `ensureQuests` (`gamification/domain/quests.dart:88`).
- OQ-30: `HistoryRepository.markSavedValuesFixed` / `suspectSetIds` serve a past keypad bug; whether any UI still uses `suspectSetIds` is unverified; likely not needed in the port.
- OQ-31: `ExerciseRepository.ensureSeeded` is skipped entirely when the stored dataset version equals the code constant, so editing `exercises.json` without bumping `exerciseDatasetVersion` never reaches existing installs (by design), but a custom exercise id colliding with a later dataset id would be overwritten (UPSERT by id).

---

# Appendix E. State management, dependencies and platform integrations

> Evidence appendix. Quoted code is verbatim with `path:line`; prose is the analyst's reading. Paths are relative to the Flutter repo root. Section numbers below are this appendix's own (referenced from the spec as `E §n`).

## Section E: State management, dependencies, platform integrations

All paths relative to `/Users/hassan/IdeaProjects/spotter-app`. Riverpod 3.4.3, hand-written providers (no codegen).

### 1. STATE MANAGEMENT

#### 1.1 Bootstrap order and the onboarded flag

`lib/main.dart:11-24`: `ensureInitialized` -> `ErrorLog.instance.init()` (loads `error_log.jsonl`) -> `installGlobalHandlers()` -> portrait-only orientation lock -> `AppDatabase.open()` (`drift_flutter driftDatabase(name:'spotter')`, `lib/core/db/database.dart:34`) -> `bootstrapDatabase(db)` -> `runApp(ProviderScope(overrides:[databaseProvider.overrideWithValue(db)], child: SpotterApp()))`.

`bootstrapDatabase` (`lib/bootstrap.dart:16-32`), all awaited before first frame, in this order:
1. `ExerciseMuscleTable.load(assets/exercise_muscles.json)` (if not loaded)
2. `ExerciseRepository(db).ensureSeeded()`
3. `ExerciseMerger(db).apply()` (merge duplicate library entries, history merged)
4. `ProgramRepository.ensureMyRoutinesInstalled / ensureCanonicalWeek / ensureProgramSupersets / ensureRoutineSetCounts / ensureSingleArmReverseFly`
5. `DataFixes.runAll(db)`
6. `HistoryRepository.markSavedValuesFixed(db, now)`
7. `GymRepository.ensureSmallestPlate(db)`
8. `RankExclusions.ensureMigrated(db)`
9. `EdbMappingRepository(db).seedFromAsset(...)` (skips merger duplicates)

Post-first-frame (`lib/app.dart:58-62`), each in its own try/catch `_step` (failures -> `ErrorLog.recordCaught`, `app.dart:65-72`): `notificationServiceProvider.init()`, `_refreshHealth()`, `rankLadderMigrationProvider.future`.

Listeners installed in `initState` (`app.dart:30-56`), via `ref.listenManual`:
- `settingsProvider` -> copies `onboarded` into a `ValueNotifier<bool>` (`_onboarded`) fed to GoRouter `refreshListenable` (`app.dart:30-33`, `router.dart:65-75`). Redirect: not onboarded and not at `/onboarding` -> `/onboarding`; onboarded at `/onboarding` -> `/home`. Router is built once when settings first load (`app.dart:96-100`); until then a spinner MaterialApp is shown; on stream error a "Failed to open database" screen.
- `mediaBootstrapProvider` (errors logged).
- `streakReminderProvider` (fireImmediately) -> schedule/cancel streak notification.
- `activeSessionProvider` (fireImmediately) and `catalogProvider` -> `workoutActivitySyncProvider.refresh()`.
- `gymEquipmentProvider` -> when `encode()` differs, `equipmentSyncProvider.onGymChanged(b)`.
- `AppLifecycleListener.onResume` -> `dayTickProvider.notifier.bump()`, `restTimerProvider.resync()` (forces Live Activity re-send), `_refreshHealth()`.

The onboarded flag is NOT in shared_preferences: it is a row in the `app_settings` key/value table (`SettingsModel.kOnboarded='onboarded'`, `lib/core/settings/app_settings.dart:41`; written by `SettingsController.setOnboarded`, `lib/core/providers.dart:30`, called from `onboarding_screen.dart:~68` `_finish`). `onboarded = m['onboarded']=='true'` (`app_settings.dart:77`), default false. (PLAN.md:87 says shared_preferences for "pre-DB onboarded flag"; code does not do this; `shared_preferences` is not imported anywhere in `lib/`.)

`_refreshHealth` guard (`app.dart:75-79`): returns without syncing unless `onboarded && (healthPermissionsRequested || useFakeHealth)`.

Theme: forced dark (`themeMode: ThemeMode.dark`, `app.dart:106`); `KeyboardDismisser` wraps all routes (`app.dart:108`). Portrait only (iPhone Info.plist + `SystemChrome`).

#### 1.2 Persistence map

| State | Where | Notes |
|---|---|---|
| All domain data (exercises, routines, sessions, sets, body_weights, daily_metrics, freezes, quests, xp, achievements, media matches, pinned videos, gym equipment ...) | SQLite via drift (`spotter`) | Source of truth; `watch()` streams drive UI |
| Settings | `app_settings` key/value table in same DB (`getSetting/putSetting/deleteSetting/watchSettings`, `database.dart:120-130`) | keys listed in 1.4 |
| Active workout "draft" | DB: `sessions.status='active'` + session exercises + sets. Persisted on every edit; survives kill. `watchActive()` (`session_repository.dart:123`), `loadActive()` = `watchActive().first` (`:164`) | NOT in-memory |
| Rest timer end/total | DB settings `rest_ends_at` (ISO-8601), `rest_total` (seconds) (`providers.dart:42-50`) | Survives app kill; UI ticks via `Timer.periodic(500ms)` + `setState` in `WorkoutClock` and `_RestSheet` (`rest_timer.dart:136,201`); countdown computed from `restEndsAt - clock()` |
| Minimized workout | No state: "minimized" = the `/workout` route is simply popped; `MiniWorkoutBar` shows whenever `activeSessionProvider` has a session (`active_workout_screen.dart:878-889, 984-1010`; hosted in `_Shell` above NavigationBar, `router.dart:205-206`). Tap -> `context.push(Routes.workout)` | |
| Error log | file `Application Support/error_log.jsonl`, max 300 entries (`error_log.dart:33-40`) | in-memory list + broadcast stream + serialized file writes |
| In-memory only (lost on restart) | `RestTimerController._activity` (RestActivity for Live Activity), `_restSetId`, `_skippedAt` (`rest_timer.dart:30,43,94`); `WorkoutActivitySync._last/_ended/_restEnd`; `FrozenCoachNotifier`; `PraiseNotifier`; `LastSummaryNotifier`; `RankTargetModeNotifier`; `HealthSyncNotifier` state; `_SessionHits` (debug); `gifFramesProvider`/`gifFirstFrameProvider` caches | After a cold restart mid-workout `workoutCoachProvider` rebuilds and re-freezes the coach (`app_providers.dart:239-247`); a rest started before the process has unknown set (handled in `cancelIfFor`, `rest_timer.dart:34-39`) |
| shared_preferences | unused in lib | see OQ |

#### 1.3 Data flow

DB (drift tables) -> repository classes (`*Repository(db)`) expose `Stream` (`watch*`) / `Future` (`load`, `all`) -> `StreamProvider` / `FutureProvider` in `lib/app_providers.dart` -> derived sync `Provider`s (pure domain compute) -> `ConsumerWidget`s via `ref.watch`. Writes go straight from UI/controllers into repositories/DB; the DB stream re-emits and providers recompute. Services (HealthKit, notifications, Live Activity) are plain `Provider`s of classes. `clockProvider` (`DateTime Function()`) is the injectable "now" used everywhere (tests override).

`export 'core/providers.dart'` re-exports from `app_providers.dart:49`.

#### 1.4 Provider table (EVERY provider)

Legend: S=StreamProvider (DB stream), F=FutureProvider (async), P=sync Provider, N=Notifier, fam=.family.

##### lib/core/providers.dart
| Name | Type | Owns/derives | Watches | Written by |
|---|---|---|---|---|
| `databaseProvider` :9 | P<AppDatabase> | throws unless overridden | - | `main.dart:21` override |
| `clockProvider` :12 | P<DateTime Function()> | `DateTime.now` | - | tests |
| `settingsProvider` :14 | S<SettingsModel> | `db.watchSettings().map(SettingsModel.fromMap)` | db | `SettingsController` |
| `currentSettingsProvider` :20 | P<SettingsModel> | settings value or defaults while loading | settingsProvider | - |
| `settingsControllerProvider` :24 | P<SettingsController> | writer methods: setOnboarded, setStreakReminder, setIncrement, setCompoundRange, setIsolationRange, setDefaultRir (clamp 0..5), setRestCompound, setRestIsolation, setUseFakeHealth, setHealthRequested, setRestTimer(endsAt,total) | db | UI |

Settings keys (`app_settings.dart:41-52`): `onboarded`, `streak_reminder` (default true: `!= 'false'`), `increments` (JSON {equipmentKindName: kg}), `compound_range`/`isolation_range` ("min-max", validated a>=1,b>=a), `default_rir` (2), `rest_compound` (150 s), `rest_isolation` (90 s), `fake_health`, `health_requested`, `rest_ends_at`, `rest_total`. Others outside the model: `streak_offset` (`StreakOffset.settingKey`), `edb_v2_enabled`, EDB budget key (`EdbBudgetStore.budgetKey`).

##### lib/app_providers.dart
| Name (line) | Type | What | Watches | Writer |
|---|---|---|---|---|
| `notificationServiceProvider` 55 | P | `NotificationService()` | - | - |
| `liveActivityProvider` 58 | P | `defaultLiveActivityService()` (iOS channel, else Noop) | - | - |
| `_healthKitProvider` 60 / `_fakeHealthProvider` 61 | P | source instances | - | - |
| `healthSourceProvider` 64 | P<HealthDataSource> | fake iff `kDebugMode && settings.useFakeHealth` else HealthKit | currentSettingsProvider | debug toggle |
| `exerciseRepositoryProvider` 69, `routineRepositoryProvider` 70, `sessionRepositoryProvider` 71, `historyRepositoryProvider` 72, `readinessRepositoryProvider` 73, `bodyWeightRepositoryProvider` 74, `freezeRepositoryProvider` 75, `gamificationRepositoryProvider` 76, `finishServiceProvider` 77, `gymRepositoryProvider` 149, `programRepositoryProvider` 585 | P | repository wrappers over db | databaseProvider | - |
| `catalogProvider` 83 | S<Map<String,ExerciseInfo>> | exercise catalogue | exerciseRepo.watchCatalog() | exercise edits |
| `_historyVersionProvider` 87 | S<int> | counter that increments on every `historyRepo.watchFinishedChanges()` emission | historyRepo | DB (finished sessions changes) |
| `historyProvider` 96 | F<TrainingHistory> | ALL finished sessions loaded via `historyRepo.load(catalog)`; central hub for ranks, streak, PRs, recovery, load | _historyVersionProvider, catalogProvider.future | - |
| `exerciseAliasesProvider` 103 | F<Map<String,Set<String>>> | search aliases built from routine/session names + assets `programs/my_routines.json`, `programs/min_max_canonical.json`, `liftoff_name_map.json` | routinesProvider, activeSessionProvider | - |
| `routinesProvider` 127 | S<List<RoutineWithExercises>> | routines | routineRepo.watchRoutines() | routine editor |
| `activeSessionProvider` 131 | S<ActiveSession?> | the running workout (DB) | sessionRepo.watchActive() | active workout screen/session repo |
| `dailyMetricsProvider` 139 | S<List<DailyMetric>> | per-day Health metrics + readiness rows (asc by date) | readinessRepo.watchDays() | Health sync |
| `todayReadinessProvider` 143 | P<ReadinessResult?> | `readinessRepo.computeFor(clock(), rows)` | dailyMetricsProvider, clockProvider | - |
| `gymEquipmentProvider` 152 | S<GymEquipment> | gym equipment + per-exercise stack overrides | gymRepo.watch() | settings/workout menu |
| `exerciseGridProvider` 155 | P.family<WeightGrid?,String(exerciseId)> | loads that exist for an exercise | catalog, gymEquipment, history | - |
| `formResetsProvider` 161 | S<Map<String,FormReset>> | form resets | gymRepo.watchResets() | workout |
| `energyProvider` 164 | P<EnergyContext> | bodyweight trend (7-day avg, 2-4 wk slope) + nutrition | _allBodyWeightsProvider, dailyMetricsProvider, clock | - |
| `_allBodyWeightsProvider` 170 | S<List<BodyWeight>> | all weigh-ins | bodyWeightRepo.watchAll() | Health sync / manual |
| `latestBodyWeightProvider` 178 | S<BodyWeight?> | latest weigh-in | bodyWeightRepo.watchLatest() | - |
| `overloadedGroupsProvider` 182 | P<Set<Muscle>> | `TrainingLoad().overloaded(now, groupSetEntries(history))` | history, clock | - |
| `latestFreezesProvider` 188 | S<Map<String,EgoFreeze>> | latest freeze per exercise | freezeRepo.watchAll() | workout |
| `activeFreezesProvider` 193 | P<Map<String,EgoFreeze>> | freezes with `until > now` | latestFreezes, clock | - |
| `coachContextBuilderProvider` 200 | P<Future<CoachContext> Function()> | one-shot snapshot builder (reads, not watches): gym, formResets, energy, recovery, history, readiness, overloaded, freezes, increments, now, bodyweight, bodyweightLoaded | uses `ref.read` | - |
| `frozenCoachProvider` 234 | NotifierProvider<FrozenCoachNotifier, ({sessionId,coach})?> | coach context frozen for the whole workout (no re-plan on Health sync/readiness refresh); in-memory | - | `freeze()` from `workoutCoachProvider` and `EquipmentSync` |
| `workoutCoachProvider` 239 | P<Future<CoachContext> Function(int sessionId)> | returns frozen coach for session else builds fresh and freezes | read frozenCoach, coachContextBuilder | - |
| `standardsProvider` 253 | F<List<StrengthStandard>> | `RanksRepository.loadStandards()` (asset) | - | - |
| `bodyweightLoadedIdsProvider` 255 | F<Set<String>> | exercise ids that are bodyweight-loaded | standards, catalog | - |
| `rankExclusionsProvider` 262 | S<Set<String>> | exercises hidden from ranking | `RankExclusions(db).watch()` | rank toggle |
| `bodyweightTimelineProvider` 265 | S<BodyweightTimeline> | weigh-ins mapped to timeline (per-day interpolation) | bodyWeightRepo.watchAll() | - |
| `ranksProvider` 269 | F<RankSummary> | `RanksRepository.compute(...)` ranks derived from whole history (never stored) | history, standards, catalog, routines, bodyweightTimeline, rankExclusions, clock | - |
| `currentBodyweightProvider` 287 | P<double> | 7-day mean of weigh-ins (0 unknown) | bodyweightTimeline, clock | - |
| `rankTargetModeProvider` 302 | NotifierProvider<RankTargetModeNotifier, RankTargetMode{lift,bodyweight}> | UI toggle, in-memory, default lift | - | `set()` from `rank_toggle.dart` |
| `rankEvolutionProvider` 305 | F<List<RankPoint>> | weekly overall/region/muscle rank series | history, routines, catalog, standards, bodyweightTimeline, rankExclusions, clock | - |
| `totalXpProvider` 324 | S<int> | total XP | gamificationRepo.watchTotalXp() | finish service |
| `levelProvider` 326 | P<LevelInfo> | `levelFor(xp)` | totalXp | - |
| `streakOffsetProvider` 329 | S<StreakOffset?> | Liftoff streak carry-over from settings `streak_offset` | db.watchSettings() | Liftoff import / edit |
| `dayTickProvider` 335-360 | NotifierProvider<DayTickNotifier,int> | counter bumped at each local midnight (+1 s, via `Timer`) and on app resume | clock (read) | Timer; `app.dart:53` |
| `dayStreakProvider` 364 | P<DayStreak?> | `DayStreakCalculator().compute(workoutStarts, now, offset)` | dayTick, history, clock, streakOffset | - |
| `streakMarksProvider` 376 | P<Map<DateTime,StreakDayMark>> | calendar dumbbell/moon marks | dayTick, history, clock, streakOffset | - |
| `streakReminderProvider` 388 | P<({DateTime at,String body})?> | `streakReminderPlan` (18:00 on last-chance day) | dayStreak, clock, settings.streakReminder | - |
| `disciplineProvider` 394 | P<double?> | `disciplineLast30` | history, clock | - |
| `questsProvider` 411 | S<List<QuestProgress>> (async* generator) | ensures this week's quests exist (`repo.ensureQuests`, generated on first access), then streams `repo.watchQuests(now)` mapped to progress via `QuestEngine.progress(def, weekActivity(...))` incl. sleep nights>=420 min; guards `ref.mounted` | clock, gamificationRepo, latestBodyWeight, bodyweightLoadedIds.future, history.future, dailyMetrics (ALL watches taken before first await, DECISIONS.md:1994) | gamification repo |
| `achievementStatsProvider` 458 | F<AchievementStats> | stats for achievements | history, ranks, bodyweightLoadedIds, latestBodyWeight, routines, dayStreak, totalXp, dailyMetrics | - |
| `_unlockedProvider` 475 | S<Map<String,DateTime>> | unlocked achievements | gamificationRepo.watchUnlocked() | finish service |
| `achievementsProvider` 479 | F<List<AchievementState>> | defs (asset) + unlocked + progress via `AchievementEvaluator` | _unlocked, achievementStats | - |
| `praiseProvider` 507 | NotifierProvider<PraiseNotifier, Map<int,PraiseState>> | per-session praise (exercises praised, count) in-memory; survives screen close/reopen not app restart | - | `record(sessionId, exerciseKey)` |
| `lastSummaryProvider` 510 | NotifierProvider<LastSummaryNotifier, SessionSummary?> | result of last finished session for summary screen | - | `set()` after finish |
| `healthSyncProvider` 531 | NotifierProvider<HealthSyncNotifier, HealthSyncState{syncing,lastSync,lastResult,error}> | `sync({days=45})`: no-op if already syncing; calls `readinessRepo.sync(healthSource, now, days)`; errors logged and stored in state | read: clock, readinessRepo, healthSource | app start/resume, pull-to-refresh Home (`home_screen.dart:44`), readiness card, Settings, onboarding |
| `rankLadderMigrationProvider` 552 | F<LadderMigration> | one-shot at startup: `migrateRankLadder(db, stats, defs, now, ranksKnown: !bodyweights.isEmpty)`; silent | read: achievementStats, bodyweightTimeline | `app.dart:61` |
| `groupVolumeProvider` 565 | P<Map<Muscle,GroupVolume>> | working sets per group: last 7 d vs weekly avg of prior 4 weeks | history, clock | - |
| `recoveryProvider` 574 | P<RecoveryState?> | `computeRecovery(history, now, readinessBand)`; band null while calibrating | history, todayReadiness, clock | - |
| `programProvider` 587 | F<Program> | `ProgramRepository.load()` (asset) | - | - |

##### Feature-local providers
| Name (file:line) | Type | What |
|---|---|---|
| `restTimerProvider` (`workout/presentation/rest_timer.dart:23`) | P<RestTimerController> | imperative controller: `start(seconds,{preview,setId})` (no-op for <=0), `adjust(delta)`, `skip()`, `stop()`, `resync()`, `cancelIfFor(setId,{latestDone})`, `takeSkip(since)`, getter `running`; writes DB settings, notification, asks `workoutActivitySyncProvider.refresh()` |
| `workoutActivitySyncProvider` (`workout/data/workout_activity_sync.dart:10`) | P<WorkoutActivitySync> | sole writer of the Live Activity (see 3.2) |
| `equipmentSyncProvider` (`workout/data/equipment_sync.dart:6`) | P<EquipmentSync> | `onGymChanged(next)`: re-snaps not-yet-completed sets of the active workout to new weight grids; completed sets untouched; freezes new coach (with new gym) |
| `mediaRepositoryProvider` (`tutorials/presentation/exercise_demo.dart:15`) | P | MediaRepository(db) |
| `mediaMatchProvider` fam<String> (`:17`) | S.family<MediaMatchRow?,String> | exercise <-> ExerciseDB match row |
| `gifFramesProvider` fam<String url> (`:29`) | F.family<GifFrames,String> | decoded GIF frames cached per URL (via `gifCacheManager`); <=10 ms frame durations -> 100 ms |
| `mediaBootstrapProvider` (`:261`) | F<void> | `repo.ensureMatched(catalog)` then `repo.prefetch(all routine exercise ids)`; re-runs when catalog/routines change |
| `gifFirstFrameProvider` fam<String> (`library/presentation/exercise_thumb.dart:13`) | F.family<ui.Image,String> | first GIF frame as thumbnail |
| `sessionDetailProvider` fam<int> (`history/presentation/session_detail_screen.dart:18`) | F.family<HistSession?,int> | one finished session |
| `suspectSetsProvider` fam<int> (`:26`) | F.family<Set<int>,int> | suspect set ids in a session |
| `programVideosProvider` (`program/presentation/program_video.dart:12`) | F<Map<String,ProgramVideo>> | program YouTube videos |
| `bodyMapProvider` (`ranks/presentation/anatomy_graph.dart:15`) | F<BodyMap> | `BodyMap.load()` (SVG path data parsed with path_parsing) |
| `rankPrescriptionProvider` fam<String> (`ranks/presentation/rank_target_line.dart:11`) | P.family<({repMin,rir}),String> | prescription for rank target |
| `liftoffCsvSourceProvider` (`import/presentation/liftoff_import_screen.dart:19`) | P<Future<String?> Function()> | file picker CSV text (overridable in tests) |
| `liftoffImportServiceProvider` (`:26`) | P | LiftoffImportService(db) |
| `_routineProvider` fam<int> (`workout/presentation/routine_editor_screen.dart:19`) | S.family<RoutineWithExercises?,int> | one routine |
| `edbBudgetStoreProvider`, `edbEnabledProvider` (S<bool> from setting `edb_v2_enabled`), `edbApiProvider` (EdbDisabled unless enabled, else `EdbV2Client` with http.Client), `edbBudgetProvider` (S<EdbBudget> from settings), `edbLogProvider` (F.autoDispose) (`tutorials/data/edb_v2/edb_providers.dart:8-33`) | mixed | ExerciseDB V2 (RapidAPI) client, default OFF; debug/optional |
| `_tableCountsProvider` (`debug/presentation/debug_menu_screen.dart:15`), `_auditProvider` (`debug/.../exercise_audit_screen.dart:15`), `_sessionHitsProvider`/`_SessionHits` (`debug/.../edb_v2_review.dart:23-25`) | debug only | |

#### 1.5 Invalidation / refresh patterns

- No manual `ref.invalidate` in app logic; recomputation is driven by dependency watches.
- Any change to finished sessions -> `watchFinishedChanges()` -> `_historyVersionProvider` increments -> `historyProvider` reloads whole history -> everything derived recomputes: `ranksProvider`, `rankEvolutionProvider`, `recoveryProvider`, `groupVolumeProvider`, `overloadedGroupsProvider`, `dayStreakProvider`, `streakMarksProvider`, `disciplineProvider`, `achievementStatsProvider` -> `achievementsProvider`, `questsProvider`, `exerciseGridProvider`.
- Catalogue change -> `catalogProvider` -> history reload (history depends on `catalogProvider.future`) and ranks.
- Health sync -> upserts `daily_metrics` and `body_weights` rows -> `dailyMetricsProvider` stream -> `todayReadinessProvider`, `energyProvider`, `recoveryProvider` (readiness band scales recovery), quests (sleep). Body weights -> `bodyweightTimelineProvider` -> ranks recompute (each set scored at bodyweight of its day).
- Midnight / resume -> `dayTickProvider.bump()` -> streak providers recompute. NOTE: `todayReadinessProvider`, `recoveryProvider`, `energyProvider`, `levelFor` etc. use `ref.watch(clockProvider)()` (clock provider value never changes) so they refresh only when their data watches change; only streak providers watch `dayTickProvider`.
- Workout start/set tick/exercise add -> `activeSessionProvider` -> `WorkoutActivitySync.refresh()` (Live Activity) and `MiniWorkoutBar`.
- Gym equipment change -> `EquipmentSync.onGymChanged` (running workout only).
- Plan freeze: coach context frozen per session id; Health sync/readiness refresh never re-plans a workout in progress.
- Readiness repository recompute: after each sync `recomputeScores(sinceDays: days)` rewrites `readiness_score/band/calibrating/explanation` for each stored day within window (`readiness_repository.dart:92,117-137`).

### 2. DEPENDENCIES (`pubspec.yaml`)

App: `spotter` 1.0.0+1, `sdk: ^3.12.0`, `publish_to: none`.

| Package | Version | Role in this app | Evidence |
|---|---|---|---|
| flutter_riverpod | 3.4.3 | State/DI; `ConsumerStatefulWidget`, `StreamProvider`, `Notifier`; Riverpod 3 API (`ref.mounted`, `Notifier`) | `lib/main.dart:20`, `app_providers.dart:411-419` |
| drift | 2.35.2 | SQLite ORM, streams, batch/upsert `DoUpdate` | `readiness_repository.dart:1,87-90`; `drift_schemas/` migration dumps |
| drift_flutter | 0.3.1 | `driftDatabase(name:'spotter')` opens native sqlite | `database.dart:2,34` |
| go_router | 18.0.2 | Routing, `StatefulShellRoute` (5 tabs), redirect, `refreshListenable` | `router.dart:65-88` |
| health | 13.3.2 | HealthKit read/write | `healthkit_data_source.dart:4` |
| fl_chart | 1.2.0 | Charts | `exercise_history_screen.dart:3`, `rank_evolution.dart:3` |
| cached_network_image | 4.0.3 | declared; no import found in lib/ (images use `Image.network`, GIFs use flutter_cache_manager) | `exercise_detail_screen.dart:271`; OQ |
| flutter_local_notifications | 22.3.2 | rest-done and streak notifications | `notification_service.dart:2` |
| url_launcher | 6.3.3 | declared; no import found in lib/ | OQ |
| share_plus | 13.3.1 | share sheet for CSV/JSON export | `export_service.dart:9,259` |
| path_provider | 2.1.6 | Application Support dir (error log), temp dir (export) | `error_log.dart:61`, `export_service.dart:256` |
| path | 1.9.1 | file path join in export | `export_service.dart:7` |
| timezone | 0.11.1 | `tz.TZDateTime`, `tz.local` for zonedSchedule | `notification_service.dart:4-5` |
| flutter_timezone | 5.1.1 | device IANA tz id | `notification_service.dart:21` |
| intl | 0.20.2 | date/number formatting | `core/domain/format.dart:1`, `home_screen.dart:4` |
| collection | 1.19.1 | declared; no `package:collection` import found (extension `firstOrNull`/`firstWhere` are in Dart core) | OQ |
| shared_preferences | 2.5.6 | declared; no import found | OQ |
| path_parsing | 1.1.0 | parse SVG path `d` strings for body-map anatomy graph | `ranks/data/body_map.dart:5` |
| flutter_cache_manager | 3.4.5 | `gifCacheManager` (1-year stale) for ExerciseDB GIFs, prefetch | `tutorials/data/media_repository.dart:7`, DECISIONS.md:~173 |
| youtube_player_iframe | 6.0.2 | in-app YouTube player of program videos (`fromVideoId`, `showFullscreenButton`, `strictRelatedVideos`, `playsInline`) | `program/presentation/program_video.dart:43-61` |
| http | 1.6.0 | ExerciseDB V2 (RapidAPI) GET with headers `X-RapidAPI-Key`, `X-RapidAPI-Host`, 15 s timeout | `edb_client.dart:208` |
| file_picker | 13.1.0 | choose Liftoff CSV (`FilePicker.pickFiles(type: custom, allowedExtensions:['csv'])`) | `liftoff_import_screen.dart:20` |
| (docs only) flutter_secure_storage | not in pubspec | DECISIONS.md:178 mentions iOS Keychain for a YouTube API key; not implemented in pubspec | OQ |

Dev: flutter_test, integration_test (sdk), flutter_lints 6.0.0, drift_dev 2.35.1, build_runner 2.15.1, flutter_launcher_icons 0.14.4 (config `flutter_launcher_icons.yaml`).

Assets/fonts (`pubspec.yaml:45-68`): `assets/`, `assets/programs/`; fonts Barlow (400/500/600/700) and Oxanium (600/700/800), `uses-material-design: true`.

Flutter built-ins that matter: Material 3 `NavigationBar` + `NavigationDestination` (5 tabs: Home, Train, Library, Progress, Profile; icons Icons.home/fitness_center/menu_book/insights/person, outlined unselected / rounded selected; `router.dart:207-219`); `showModalBottomSheet` (rest sheet, many sheets); `Hero`, `Dismissible`/swipe rows, `ReorderableListView` (grep counts across workout/library/ranks screens); `CustomPainter` (anatomy_graph, rank_badge, game_ui, fire_streak etc.); `PageView` (onboarding, `onboarding_screen.dart:~38`); `HapticFeedback.heavyImpact` (`rest_timer.dart:157`); `AppLifecycleListener` (`app.dart:52`); `SystemChrome.setPreferredOrientations` (`main.dart:15`); `ValueNotifier`; `Timer`/`Timer.periodic`; `ui.instantiateImageCodec` for GIF; `rootBundle` assets; `ThemeMode.dark` with custom `buildAppTheme()`; `StatefulShellRoute` with `FadeBranches` and `ReduceMotionTransitions` (`core/motion.dart`, respects `MediaQuery.disableAnimations`); `KeyboardDismisser`; custom in-app numeric keypad (`workout/presentation/keypad.dart`).

### 3. PLATFORM INTEGRATIONS

#### 3.1 Apple Health

Abstraction: `HealthDataSource` (`lib/core/health/health_data_source.dart:16-51`): `name`, `isFake`, `isAvailable()`, `requestPermissions()`, `hrvSdnn`, `restingHeartRate`, `asleepIntervals`, `activeEnergy`, `dietaryEnergy`, `dietaryProtein`, `latestBodyMass`, `bodyMassHistory`, `writeStrengthWorkout`. Enum `HealthAccess {unknown, requested, unavailable}` declared (unused in snippets read). iOS never reveals if READ was granted; "missing" is inferred from empty results.

Exact types read/written:

`lib/core/health/healthkit_data_source.dart:16-31`
```dart
  static const _asleepTypes = [
    HealthDataType.SLEEP_ASLEEP, // unspecified
    HealthDataType.SLEEP_LIGHT, // core
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static const _readTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.RESTING_HEART_RATE,
    ..._asleepTypes,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
    HealthDataType.DIETARY_ENERGY_CONSUMED,
    HealthDataType.DIETARY_PROTEIN_CONSUMED,
  ];
```
READ: HRV SDNN, resting HR, sleep (asleep/light=core/deep/REM; in-bed and awake excluded), active energy burned, body weight, dietary energy, dietary protein.
WRITE: `HealthDataType.WORKOUT` (READ_WRITE) only, as `HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING`.

Permission flow, `healthkit_data_source.dart:45-63`:
```dart
  @override
  Future<bool> isAvailable() async => Platform.isIOS;

  @override
  Future<bool> requestPermissions() async {
    if (!Platform.isIOS) return false;
    try {
      await _configure();
      final types = [..._readTypes, HealthDataType.WORKOUT];
      final permissions = [
        for (final _ in _readTypes) HealthDataAccess.READ,
        HealthDataAccess.READ_WRITE,
      ];
      return await _health.requestAuthorization(types, permissions: permissions);
    } catch (e) {
      debugPrint('Health authorization failed: $e');
      return false;
    }
  }
```
`_configure()` calls `Health().configure()` once (`:39-43`). Every read: non-iOS or any exception -> `debugPrint` and empty list (`:65-74`). Values: numeric only (`NumericHealthValue`), times converted `.toLocal()` (`:76-87`, `:108-114`). Units are those the `health` plugin returns for HealthKit (kcal, ms, bpm, kg, g); no conversion in app code. `latestBodyMass`: last 365 days, latest by `dateFrom`, value > 0 (`:117-127`). `bodyMassHistory`: values > 0, sorted ascending (`:129-136`). Sleep: intervals with `dateTo > dateFrom` (`:108-114`). Write: `writeWorkoutData(activityType: TRADITIONAL_STRENGTH_TRAINING, start, end, title)`; non-iOS/exception -> false (`:138-153`).

When requested:
- Onboarding "connect health": `requestPermissions()` -> `setHealthRequested(true)` -> notification `requestPermission()` -> `healthSyncProvider.sync()`; status text: `!ok` -> "Apple Health isn't available. Spotter will work without it and readiness stays neutral."; `days==0` -> "Connected. No recovery data found yet ..."; else "Connected. Found recovery data for N of the last M days."; prefill bodyweight from `lastResult.bodyMass` (`onboarding_screen.dart:40-63`). Manual bodyweight allowed range 30-300 kg; saved as `body_weights(source='manual')` only when no Health weight (`:65-70`, `:30-33`).
- Settings -> "Request permissions again" re-runs the same + sync; snackbar when `!ok`; hint "change it in the Health app under Sharing -> Apps -> Spotter" (`settings_screen.dart:120-130`). "Sync now" tile; title shows `health.name` ("Apple Health" or "Fake data (debug)").
- Write on Finish: `FinishService.finish(... health: ref.read(healthSourceProvider))`; `writeStrengthWorkout(start: session.startedAt, end: now, title: session.name)`; on true sets `sessions.health_synced=true`; exceptions -> `saved=false` (`finish_service.dart:303-317`, caller `active_workout_screen.dart:962-967`).

Sync logic `lib/features/readiness/data/readiness_repository.dart:43-106`:
```dart
    final today = dateOnly(now);
    final from = DateTime(today.year, today.month, today.day - days - 1, 12);
    final to = now;
    final results = await Future.wait([
      source.hrvSdnn(from, to),
      source.restingHeartRate(from, to),
      source.activeEnergy(from, to),
      source.dietaryEnergy(from, to).catchError((_) => <TimedValue>[]),
      source.dietaryProtein(from, to).catchError((_) => <TimedValue>[]),
    ]);
    final sleep = await source.asleepIntervals(from, to);
```
Default window `days=45` (called by `HealthSyncNotifier.sync({days = 45})`). For each day i in [days..0] a `daily_metrics` row is upserted (`onConflict: DoUpdate`): `date` (yyyy-MM-dd key), `hrvMs`, `restingHr`, `sleepMinutes` (from aggregator), `activeEnergyKcal` = SUM of samples by `dayKey(sample.to)`, `dietaryKcal` and `proteinG` = SUM by `dayKey(sample.to)`, `updatedAt`. Then `recomputeScores(sinceDays: days)`. Body mass: `bodyMassHistory(now-365d, now)`; each stored in `body_weights` (`source='health'`) unless an identical `(source='health', measuredAt)` exists; then `latestBodyMass()` stored too; errors swallowed (`:94-106`, `:108-114`). Returns `SyncResult(days: days+1, daysWithData, bodyMass)`.

Aggregation per day D (`lib/features/readiness/domain/metrics_aggregator.dart:19-70`):
- Night window = [D-1 18:00, D 12:00) local (`nightStart/nightEnd`).
- Sleep = union of asleep intervals clipped to the window, overlaps merged (`mergeIntervals`), minutes = total seconds/60; null if none.
- HRV = mean SDNN of samples with `from` within the sleep span `[merged.first.start, merged.last.end]`; if no sleep, mean over [D-1 12:00, D 12:00).
- Resting HR = mean of samples with `from` in [D-1 00:00, D 12:00).
- `TimedValue(from,to,value)` and `TimeInterval(start,end)` defined `metrics_aggregator.dart:4-17`.
- Only HRV, RHR, sleep feed readiness (`dayMetricsFromRow`, `readiness_repository.dart:10-11`); active energy, dietary energy, protein go to `energyProvider`/nutrition; weight to ranks/energy/quests. Quests use `sleepMinutes >= 420` nights.

Denied/unavailable: reads return empty -> metrics null -> readiness "calibrating"/neutral; app works without Health. `_refreshHealth` skips entirely until onboarded and permissions requested (`app.dart:77`). Non-iOS: all methods no-op/false.

Caching: none beyond the DB (`daily_metrics`, `body_weights`); sync runs on launch (post-frame), on resume, pull-to-refresh on Home (`home_screen.dart:44`), readiness-card buttons (`readiness_card.dart:46,158`), Settings, debug menu. Concurrent syncs ignored (`state.syncing`).

Fake source `lib/core/health/fake_health_data_source.dart`: `name 'Fake data (debug)'`, `isFake true`, `isAvailable`/`requestPermissions` always true, `FakeHealthDataSource({baseBodyMass = 80, workouts})`; deterministic per-day `math.Random(y*10000+m*100+d + salt*7919)`; night types: r<0.06 bad (-150 min), r<0.2 rough (-70 min), else normal; bedtime 23:00 +- gaussian*25 min; sleep 445 + gaussian*30 min clamped 200-600 (`:36-64`). Enabled only when `kDebugMode && settings.useFakeHealth` (`app_providers.dart:64-67`). Also used by seed generator/tests.

Entitlements `ios/Runner/Runner.entitlements:5-8`:
```xml
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
```
Info.plist `ios/Runner/Info.plist:5-8`:
```xml
	<key>NSHealthShareUsageDescription</key>
	<string>Spotter reads your heart rate variability, resting heart rate, sleep, active energy and body weight to calculate a daily readiness score and adjust today's training suggestions. This data never leaves your iPhone.</string>
	<key>NSHealthUpdateUsageDescription</key>
	<string>Spotter saves each finished session to Apple Health as a Traditional Strength Training workout with its start and end time.</string>
```
(Note: usage string does not mention dietary energy/protein.)

#### 3.2 Live Activity (ActivityKit)

Targets (ios/ tree, excluding Pods/build/generated): `ios/Runner/{AppDelegate.swift, SceneDelegate.swift, LiveActivityBridge.swift, Runner-Bridging-Header.h, Info.plist, Runner.entitlements, Base.lproj/{LaunchScreen,Main}.storyboard, Assets.xcassets}`; `ios/SpotterLiveActivity/{SpotterLiveActivityBundle.swift, WorkoutLiveActivity.swift, Info.plist}` (WidgetKit extension, bundle id `com.hassan.spotter.LiveActivity`, iOS 17, DECISIONS.md:1539); `ios/Shared/{WorkoutActivityAttributes.swift, WorkoutActivityViews.swift}` (compiled into both app and extension); `ios/RunnerTests/RunnerTests.swift`; `ios/Runner.xcodeproj`. Extension Info.plist: `CFBundleDisplayName "Spotter Rest Timer"`, `NSExtensionPointIdentifier com.apple.widgetkit-extension`. Runner Info.plist: `NSSupportsLiveActivities = true`. Widget entry: `SpotterLiveActivityBundle` containing `WorkoutLiveActivity()` (lock screen + Dynamic Island, layout in `ios/Shared/WorkoutActivityViews.swift`: `ActivityLockScreen`, `activityPanel`; not fully read, see OQ).

AppDelegate registration, `ios/Runner/AppDelegate.swift:5-24`:
```swift
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var liveActivityBridge: LiveActivityBridge?
  override func application(... didFinishLaunchingWithOptions ...) -> Bool {
    // Lets flutter_local_notifications present the rest-timer alert while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      liveActivityBridge = LiveActivityBridge(messenger: registrar.messenger())
    }
  }
}
```
`SceneDelegate.swift:4`: empty `class SceneDelegate: FlutterSceneDelegate {}`. Info.plist uses UIScene manifest (single scene, storyboard Main).

Channel and methods, `ios/Runner/LiveActivityBridge.swift:6-35`:
```swift
/// Flutter ↔ ActivityKit for the workout's Live Activity. Channel `spotter/live_activity`:
/// - `sync {phase, workoutName, exerciseName, nextTarget, setLabel, workoutStartMillis, restStartMillis?, restEndMillis?,
///   warmups: [{text, done}], warmupsMore}`: starts the activity or updates the running one;
/// - `end`: removes it now (workout finished or discarded);
/// - `activeCount`: running activities (integration tests).
...
        channel = FlutterMethodChannel(name: "spotter/live_activity", binaryMessenger: messenger)
...
        case "available":  result(ActivityAuthorizationInfo().areActivitiesEnabled)
        case "activeCount": result(Activity<WorkoutActivityAttributes>.activities.filter { $0.activityState == .active }.count)
        case "sync": ... await self.startOrUpdate(workoutName: (a["workoutName"] as? String) ?? "Workout", state: state); result(self.current != nil)
        case "renderPreview": ... PNG + height (tests; args also width (default 361), restFraction (default 0.4))
        case "end": await self.endAll(); result(nil)
        default: result(FlutterMethodNotImplemented)
```
Native handles also `available` and `renderPreview` (Dart only calls `sync`, `end`, plus test-only `renderPreview`, `activeCount`).

Dart side, `lib/core/live_activity/live_activity_service.dart:104-148`:
```dart
class ChannelLiveActivityService implements LiveActivityService {
  ChannelLiveActivityService([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('spotter/live_activity');
  static Map<String, Object?> _args(WorkoutActivity a) => {
        'phase': a.phase,
        'workoutName': a.workoutName,
        'exerciseName': a.exerciseName,
        'nextTarget': a.nextTarget,
        'setLabel': a.setLabel,
        'workoutStartMillis': a.workoutStart.millisecondsSinceEpoch.toDouble(),
        'restStartMillis': a.restStart?.millisecondsSinceEpoch.toDouble(),
        'restEndMillis': a.restEnd?.millisecondsSinceEpoch.toDouble(),
        'warmups': [for (final w in a.warmups) {'text': w.text, 'done': w.done}],
        'warmupsMore': a.warmupsMore,
      };
```
`MissingPluginException` and `PlatformException` are swallowed (debugPrint) (`:138-147`). `defaultLiveActivityService()` = channel service on iOS else `NoopLiveActivityService` (`:150`).

ContentState (`ios/Shared/WorkoutActivityAttributes.swift:10-33`): `phase` ("warmup"|"working"|"rest"|"done"), `exerciseName`, `nextTarget`, `setLabel`, `workoutStart: Date`, `restStart: Date?`, `restEnd: Date?`, `warmups: [WarmupLine{text,done}]`, `warmupsMore: Int`; static attribute `workoutName`. `Activity.request(... pushType: nil)` (no push). Bridge guard: `ActivityAuthorizationInfo().areActivitiesEnabled` else no-op (`:91`). Update path reuses `current` or the first `.active` activity; `endAll` dismisses all with `.immediate` (`:106-111`). Elapsed time and rest countdown are drawn by the system from dates (`Text(date, style:.timer)`, `Text(timerInterval:)`), so they run while app is suspended (attributes doc comment). Known limit: if app backgrounded when rest ends the activity shows REST 0:00 until return (DECISIONS.md:1935).

Single writer `lib/features/workout/data/workout_activity_sync.dart:16-57`:
- `refresh({force=false})`: reads `activeSessionProvider`, `catalogProvider`, `restTimerProvider.running`. If no session or `status != 'active'`: cancel rest timer, `service.end()` once (guard `_last/_ended/force`). Else `buildWorkoutActivity(session, nameOf: displayName ?? catalog name ?? exerciseId, rest)`; schedules `Timer(rest.endsAt - now + 300ms, refresh)` to flip back to workout view when rest ends; sends only when `next != _last` (value equality incl. warmups list) or `force`; fire-and-forget (`unawaited`).
- `buildWorkoutActivity` (`workout/domain/workout_activity.dart:12-60+`): phase 'rest' (with rest data + next set label + warm-up chips max `_maxWarmupLines = 4`, `warmupsMore`), 'working'/'warmup' for next open set (first exercise with uncompleted set), and when every set done: phase 'working', exerciseName 'Workout', nextTarget 'Last set done. Finish when ready.'. Uses `nextLabel`, `_label`, `_warmups`, `formatKg`.
- Triggers: `activeSessionProvider`/`catalogProvider` change (`app.dart:44-45`), rest timer start/adjust/stop (`rest_timer.dart:61,71,89,115`), app resume with `force:true` (`rest_timer.dart:75`).

#### 3.3 Local notifications

`lib/core/notifications/notification_service.dart:14-15`
```dart
  static const int restTimerId = 1001;
  static const int streakReminderId = 1002;
```
Init (`:17-36`): `tzdata.initializeTimeZones()`; `FlutterTimezone.getLocalTimezone()` -> `tz.setLocalLocation(tz.getLocation(info.identifier))`; failure -> debugPrint, falls back to UTC (tz default). `InitializationSettings`: iOS `DarwinInitializationSettings(requestAlertPermission:false, requestSoundPermission:false, requestBadgePermission:false)` (no permission prompt at init); Android `AndroidInitializationSettings('@mipmap/ic_launcher')`. `_plugin.initialize(settings: settings)`. Init is idempotent (`_ready`), called lazily by every method and post-frame at startup.

Permission (`:38-43`): `IOSFlutterLocalNotificationsPlugin.requestPermissions(alert: true, sound: true, badge: false)`; returns `granted ?? false` (always false on Android: no Android permission request implemented). Asked in onboarding Health step (`onboarding_screen.dart:45`) and Settings "Enable rest-timer alerts" (`settings_screen.dart:140`; message "Notifications are off. Enable them in iOS Settings -> Spotter.").

Rest timer (`:45-65`): `cancel(id: 1001)`, return if `at` not after now, then `zonedSchedule(id:1001, scheduledDate: tz.TZDateTime.from(at, tz.local), title:'Rest done', body: 'Rest is over. Next set!' (default), iOS DarwinNotificationDetails(presentAlert, presentSound, presentBanner: true, interruptionLevel: InterruptionLevel.active), android AndroidNotificationDetails('rest_timer','Rest timer', importance: high, priority: high), androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle)`. One pending at a time; rescheduled on `adjust`; `cancelRest()` cancels 1001. Triggered by `RestTimerController.start/adjust/stop`.

Streak reminder (`:73-88`): same pattern with id 1002, title 'Streak', iOS alert/sound/banner, android channel `'streak'`/'Streak reminder' `Importance.defaultImportance`, body from plan. Schedule time: 18:00 local (`streakReminderHour = 18`, `streaks.dart:235-246`) on `streak.lastChanceDay`, only if enabled, `streak.days>0`, and 18:00 is still in future; body `'Train today to keep your N-day streak.'`. Re-planned whenever `streakReminderProvider` changes (`app.dart:39-42`): plan null -> `cancelStreakReminder()`.

AppDelegate sets `UNUserNotificationCenter.current().delegate = self` so alerts show in foreground. In-app buzz: `HapticFeedback.heavyImpact()` when rest ends in `WorkoutClock` (`rest_timer.dart:154-160`).

#### 3.4 Other plugins / IO

- share_plus: export CSV/JSON (`ExportService.share`, `export_service.dart:254-265`): writes to `getTemporaryDirectory()`, `SharePlus.instance.share(ShareParams(files:[XFile...], subject:'Spotter export <stamp>', sharePositionOrigin: origin))`. CSV writes three files: `sessions`, `sets`, `readiness-days` (`:245-249`); JSON one file (schema doc `docs/export_schema.md`).
- file_picker: Liftoff CSV import (`liftoff_import_screen.dart:19-24`), read bytes, `utf8.decode(allowMalformed:true)`.
- path_provider: `getApplicationSupportDirectory()` for `error_log.jsonl`; temp dir for export.
- http: only `EdbV2Client` (RapidAPI ExerciseDB V2) when setting `edb_v2_enabled=='true'`; key from `--dart-define-from-file=config/secrets.json` (`const edbApiKey = String.fromEnvironment('EDB_RAPIDAPI_KEY')`, `edb_client.dart:12-13`; `config/secrets.example.json` = `{"EDB_RAPIDAPI_KEY": "your RapidAPI key"}`; `config/secrets.json` is git-ignored); `NO_KEY` exception if missing. Monthly budget stored in settings (`EdbBudgetStore`).
- Network otherwise: ExerciseDB V1 GIF downloads via flutter_cache_manager (`gifCacheManager`), library photos via `Image.network` (`exercise_detail_screen.dart:271`), YouTube iframe.
- youtube_player_iframe: `YoutubePlayerController.fromVideoId(... params: YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true, playsInline: true))` (`program_video.dart:43-47`). DECISIONS.md also mentions pinned videos per exercise and optional YouTube Data API key, which is not evidenced in pubspec (see OQ).
- url_launcher: no use found in `lib/`.
- Error log (`lib/core/diagnostics/error_log.dart`): singleton `ErrorLog.instance`; entries `{at, source(flutter|platform|caught), error, stack (first 40 lines), route}`; max 300; JSON Lines file; broadcast stream `changes`; `exportText()` newest first with `---` separators; hooks `FlutterError.onError` and `PlatformDispatcher.instance.onError`; `currentRoute` updated from router delegate (`router.dart:~190`). UI at `/settings/errors` (opened by long-pressing the version label in Settings, DECISIONS.md:260-263), has Copy all and Clear.
- Debug-only routes (`kDebugMode`): `/settings/debug` and children (badges, badge-sheet, media, audit, summary-preview, rank-up-preview) (`router.dart:157-179`).

#### 3.5 Android

`android/app/src/main/AndroidManifest.xml`: only `<uses-permission android.permission.INTERNET/>`; app label `spotter`; icon `@mipmap/ic_launcher`; `MainActivity` exported, `launchMode=singleTop`, `taskAffinity=""`, theme `@style/LaunchTheme`, large `configChanges` list, `hardwareAccelerated`, `windowSoftInputMode=adjustResize`, LAUNCHER intent filter; `flutterEmbedding=2`; `<queries>` PROCESS_TEXT text/plain. NO notification (POST_NOTIFICATIONS), exact-alarm, boot receiver, or Health Connect permissions. Android is effectively a stub: HealthKit class returns false/empty on non-iOS; Live Activity is Noop; Android notification channels exist in code ('rest_timer', 'streak') but permission is never requested.

#### 3.6 iOS Info.plist other keys (`ios/Runner/Info.plist`)
`NSSupportsLiveActivities` true; `ITSAppUsesNonExemptEncryption` false; `CADisableMinimumFrameDurationOnPhone` true (ProMotion); `CFBundleDisplayName Spotter`; `CFBundleName spotter`; `UIApplicationSupportsIndirectInputEvents`; `UILaunchStoryboardName LaunchScreen`; `UIMainStoryboardFile Main`; iPhone orientations: Portrait only; iPad: all four. No camera/photos/location/background modes. No notification entitlement needed (local). No App Groups entitlement (Live Activity is local-update only, no widget data sharing).

#### 3.7 tool/ scripts (build-time data tooling, not runtime)
- `tool/device_shots.sh <sim-id> <folder>`: loops answering integration-test `deviceShot` requests with `xcrun simctl io <sim> screenshot`.
- `tool/library/build_library.py <wger_exerciseinfo.json>`: builds `assets/library_sources.json` merging free-exercise-db and wger (licences/authors kept).
- `tool/program/extract_min_max.py <pdf>`: extracts the owner's Min-Max Phase 2 PDF to `docs/program/min_max_phase2_12weeks.json` (needs pdfplumber; PDF never committed).
- `tool/program/extract_videos.py <pdf>`: adds YouTube demo links from PDF link annotations to the same JSON.
- `tool/program/canonical_week.py`: builds `assets/programs/min_max_canonical.json` (week 5 canonical) from the 12-week JSON.
- `tool/standards/build.py` (+`exercise_data.py`): writes `assets/exercise_muscles.json` and `assets/strength_standards.json`; validates every exercise with muscles has a standard.
- `tool/tier_colors/sample_emblems.py`: samples dominant colours from rank emblem PNGs (design aid for tier colors).
- `config/secrets.json` / `secrets.example.json`: dart-define file for `EDB_RAPIDAPI_KEY`.
- Tests: `integration_test/` (harness with `SHOTS_DIR`, `LIFTOFF_CSV`, `REPORT_DIR` dart-defines; live-activity native tests), `drift_schemas/` migration dumps.

#### 3.8 Decisions that matter for the port (docs)
- PLAN.md:3: on-device, iOS-first, gamified strength app; coach uses lifting history + Apple Health recovery. PLAN.md:42-45: Riverpod, `data` layers translate DB rows/Health samples into pure domain models; Health behind `HealthDataSource` with real + fake.
- DECISIONS.md:257-273: routines install before first frame; startup steps independent and error-logged; ErrorLog persistent.
- DECISIONS.md:1537-1556 and 1919-1940 and 2062+: Live Activity evolved from rest-only (`RestTimerAttributes`) to whole-workout (`WorkoutActivityAttributes`); single writer pattern; redesign layout header row + one warm-up chip row + "Next:" line (`ios/Shared/WorkoutActivityViews.swift`), must fit ~160 pt.
- DECISIONS.md:1901-1904: un-ticking a set cancels the rest it started (timer, notification, live activity).
- DECISIONS.md:1916, 2079: warm-up check starts a rest; single 1:30 rest after last warm-up (`WarmupRest.after`).
- DECISIONS.md:373,413: Health weight sync stores a year of weigh-ins; bodyweight interpolated linearly between weigh-ins.

### 4. OPEN QUESTIONS
- OQ: `shared_preferences`, `url_launcher`, `cached_network_image`, `collection` are in pubspec but I found no import in `lib/`, `integration_test/`, or `tool/` (grep). Confirm they are dead dependencies (PLAN.md:87 says shared_preferences holds a pre-DB onboarded flag; code uses the DB settings row instead).
- OQ: DECISIONS.md:178 mentions `flutter_secure_storage` and an optional YouTube Data API v3 key stored in iOS Keychain, but the package is absent from pubspec and I did not find the code. Is the feature removed?
- OQ: `HealthAccess` enum (health_data_source.dart:10) appears unused; confirm.
- OQ: Exact Live Activity visual layout (`ios/Shared/WorkoutActivityViews.swift`, `ios/SpotterLiveActivity/WorkoutLiveActivity.swift` Dynamic Island compact/expanded/minimal regions, colors: warm-up amber, working green, rest blue per DECISIONS.md:1926) was not read in this section; belongs to a UI section if needed. A React Native port needs a native Swift module + widget extension (no JS equivalent).
- OQ: Entitlements `com.apple.developer.healthkit.access` is empty array (no clinical records); whether `NSHealthShareUsageDescription` should mention nutrition reads is a product choice.
- OQ: Android/Health Connect behaviour for the port is undefined (no Android implementation exists); is Android a target?
- OQ: `healthSourceProvider` fake only in `kDebugMode`; in release `fake_health` setting is ignored but still gates `_refreshHealth` (`useFakeHealth` in guard `app.dart:77`). Minor inconsistency; confirm intended.
- OQ: `todayReadinessProvider`/`recoveryProvider` do not watch `dayTickProvider`, so "today" for readiness/recovery is not refreshed at midnight until data changes (app resume does trigger a Health sync which updates `daily_metrics`). Confirm whether this is intentional.
- OQ: Rank evolution/ladder-migration details and DB schema/table list belong to other sections; the DB `app_settings` helper signatures (`database.dart:120-130`) were only grepped, not read in full.