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
  the reported screenshot it was right: five groups (biceps, forearms, abs, quads, hamstrings,
  calves) were Silver, which averaged to 2.994 = Silver I. The real defect was at boundaries: a
  score exactly on a division threshold, or an average of identical scores that lost a floating-point
  ulp, could floor into the previous division. Tier and division floors now use a 1e-9 epsilon, and a
  test checks every tier/division (including exact boundaries) round-trips: all groups at X Y →
  overall X Y.
- **Volume.** One pure formatter (`lib/core/domain/format.dart`) is used everywhere: whole kg with
  thousands separators below 10,000 kg ("6,763 kg"), then tonnes with one decimal ("15.6 t").
