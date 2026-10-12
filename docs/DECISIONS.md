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
