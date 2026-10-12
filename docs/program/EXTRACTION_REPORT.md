# Min-Max Phase 2 (5x): extraction report

**Source:** your copy of *The Min-Max Program Phase 2 5x (Jeff Nippard).pdf*, 91 pages. It's read
from its own folder and is never committed (`private/` and `*.pdf` are git-ignored).
**Output:** `assets/programs/min_max_phase2.json`, as documented in `SCHEMA.md`.
**Generator:** `tool/program/extract_min_max.py "<path to pdf>"`. You can re-run it if the PDF is
updated.

## What I read

| Pages | Content | Where it went |
|---|---|---|
| 2–3 | Disclaimer, contents | — |
| 4–6 | Intro: Phase 2 takes the **first** working set to failure on most exercises; Upper/Lower/Push/Pull/Arms split; extra higher-rep sets | `method.effort.first_set_to_failure`, `program.split` |
| 7–8 | Who it's for | — (context only) |
| 9–11 | How it works: low volume, 4–12 sets per muscle per week | — (context only) |
| 12–13 | RIR definition; the **RIR 0 safety exception** for Hack Squat and Smith Machine Bench Press | `method.effort`, slot `rir0_attempt_failure` |
| 14–15 | Structure: two 6-week blocks, an intro or deload week at the start of each, techniques in Block 2, 2 substitutions per exercise | `method.blocks`, `method.substitutions` |
| 16–17 | **Warm-up:** general warm-up plus the exercise-specific pyramid for 1, 2, 3 or 4 warm-up sets | `method.warmup` |
| 18 | **Last-set intensity techniques:** drop sets, lengthened partials, myo-reps, weighted static hold | `method.techniques` |
| 19 | **Progression** rule and fallback; tracking; rest (working, warm-up, between exercises); substitutions; notes; **supersets** | `method.progression`, `method.rest`, `method.supersets` |
| 20–23 | Weekly sets per muscle and the exercises behind them | used to sanity-check the tables (sums match) |
| 25 | Important notes: separate warm-up and working columns, RIR, the safety exception again, warm-up protocol | consistent with the above |
| **26–85** | **60 tables: 12 weeks × 5 days** | `days[].slots[]` |
| 86–89 | FAQ: rest timing optional, exercise order flexible, substitutions, loop after week 12, 4×/week option | `method.rest.faq`, `method.exercise_order`, `method.looping`, `method.four_day_option` |
| 90–91 | Final thoughts | — |

## What the PDF actually contains (vs. your description)

- **Effort is prescribed as RIR per set, not "failure on the last set".**
  - Most first sets are RIR 0; second and third sets are RIR 0–1.
  - Week 1 (intro) and week 7 (deload) are 1–2 RIR easier.
  - **Hack Squat never goes to failure:** RIR 2/3 → 1/2 → 0/2 across the block. **Stiff-Leg Deadlift
    never goes below RIR 1.**
  - The app shows RIR 0 as "FAILURE".
- **Last-set techniques appear only in weeks 8–12, and only these three:**
  - **Myo-reps:** Pec Deck, Chest-Supported T-Bar Row, Chest-Supported Machine Row, Preacher Hammer
    Curl, Triceps Pressdown.
  - **Two drop sets (~25% each):** Seated Leg Curl, Machine Shoulder Press, Cable Flye, Cable Crunch.
  - **Weighted static hold (30 s):** Standing Calf Raise.
  - **Lengthened partials** are described on page 18 but **no exercise uses them** in this 5x version.
    The definition is kept with `used_in_this_version: false`.
- **"Higher-rep sets" are separate rows of the same exercise.** For example, Machine Chest Press is
  2×4–6 followed by a separate 1×20. Your "Chest Press: 3" is exactly those 3 sets. The app gives each
  row its own suggested weight.
- **Rep ranges, warm-up counts, rest, substitutions and notes never change** over the 12 weeks. Only
  RIR and techniques vary. The generator asserts this on every page.
- **Warm-up counts are ranges** (e.g. `2-3`, `0-1`), with the % pyramid on page 17.
- **Supersets exist only on Arms:** S1 curl + skull crusher, S2 hammer curl + pressdown, S3 wrist curl
  + extension. The first exercise has no rest ("-"), and the listed rest comes after the second one.
- **The week layout has two rest days:** Upper, Lower, **Rest**, Push, Pull, Arms, **Rest**.

## Verification

1. **Coordinate extraction.** Every table cell was rebuilt from word coordinates (pdfplumber). The
   generator asserts that each slot's exercise, warm-ups, working sets, reps, rest, substitutions and
   notes are identical in all 12 weeks.
2. **Independent re-read.** I parsed the same 60 pages again from the plain text layer with pypdf,
   which goes column by column and shares no code with step 1. I compared warm-ups, working sets, rep
   range, rest, technique and RIR for every slot and week. **Result: 444 slot-weeks checked, 0
   mismatches.** The first pass showed apparent mismatches, but all of them came from my checker:
   text-layer kerning ("3 0-60 sec"), cells that wrap ("10 per / leg"), and the word "Rest" in the
   "Rest Day" banner.
3. **Visual check** of the rendered pages against the JSON:
   - Page 26 (Week 1 Upper) matched cell for cell.
   - Page 62 (Week 8 Lower: drop sets, static hold, Hack Squat RIR 1/2) matched cell for cell.

## Uncertain or decided by me (please check)

1. **Back Extension (you asked me to confirm).** The program's Lower day has no back extension. I
   mapped it to the **Glute Kickback** slot (`lower_07`) because its first substitution is **"45°
   Hyperextension"**, which is a back extension. The prescription is 1 set × **30 reps**, RIR 1 in
   week 1 and RIR 0 (failure) otherwise, 0–1 warm-up sets and 1–2 min rest. The slot's note says
   the 45° Hyperextension option is for focusing "more on your lower back and hamstrings", and the
   kickback is for glutes. **Is 1 × 30 to failure what you want?**
2. **Face Pull is not in the program.** It has no free slot on Pull: your Machine Reverse Fly already
   fills both 1-Arm Reverse Pec Deck rows (1×20 + 1×10). I gave it the reverse pec deck's **1×20,
   failure** prescription (same day, same muscle). **Keep that, or give me a prescription?**
3. **Current program week.** I set it to week 1. **Which week are you in?** You can also change it in
   Settings → Program.
4. **Warm-up count ranges** (e.g. "2-3", "0-1"). I default to the **upper bound** (3 and 1). For
   isolation work that adds one light set. You can delete warm-up sets in a workout. **Prefer the lower
   bound?**
5. **Rest timer.** It uses the **upper** bound of the printed range (2-3 min → 3:00). The FAQ says
   timing is optional.
6. **Pendulum Squat** is your swap for **Hack Squat** and inherits its prescription. That includes the
   **RIR 0 safety rule**: no attempting a failed rep, and the program never prescribes RIR 0 on set 2.
7. **EZ Bar Curl** stands in for **EZ-Bar Cheat Curl**: same slot, 4–6 reps. The program intends a bit
   of momentum; I kept your strict curl.
8. **Machine Reverse Fly** (two-arm) for **1-Arm Reverse Pec Deck**, and **Cable Lateral Raise** for
   **Single-Arm Machine Lateral Raise** via its "High-Cable Lateral Raise" substitution. Both are
   treated as the program's exercise or its substitution.
9. **Assisted Pull-Ups** use the **Pull-Up (Wide Grip)** prescription: 3 × 4–6, RIR 0/1/1. Assistance
   is logged as negative weight, so 25 kg of help is −25. The app uses bodyweight − assistance as the
   load everywhere: e1RM, suggestions and the −5% / −10% rules. More assistance is never mistaken for
   "heavier".
10. **Decline Crunch and Back Extension** are bodyweight lifts with optional added load. 0 means
    bodyweight.
11. **PDF typo:** the table header says "BLOCK 1" on weeks 8–12. Those weeks belong to Block 2 per
    pages 14–15. I treated them as Block 2.

## Your routines: every exercise and where its prescription comes from

Sets are your counts. "Prescription" lists the program slot(s) in order.

| Day | Your exercise | Library id | Program exercise | Relation | Prescription (week 2 example) |
|---|---|---|---|---|---|
| Upper | Chest Press (3) | Leverage_Chest_Press | Machine Chest Press | program | `upper_01` 2×4–6 F/F, then `upper_02` 1×20 F; warm-up 2–3; rest 2–3 min |
| Upper | Straight Arm Pulldown (2) | Straight-Arm_Pulldown | Machine Lat Pullover | **swap** (same day, lats, same slot) | `upper_03` 1×8–10 F, then `upper_04` 1×20 F; warm-up 1–2 |
| Upper | Machine Chest Fly (2) | Butterfly | Pec Deck | program (same machine) | `upper_05` 2×10–12 F/F; myo-reps wk 8–12 |
| Upper | Chest Supported T-Bar Row (2) | Lying_T-Bar_Row | Chest-Supported T-Bar Row | program | `upper_06` 2×6–8 F/F; myo-reps wk 8–12 |
| Upper | Dumbbell Incline Y Raise (3) | sp_db_incline_y_raise | Incline DB Y-Raise | program | `upper_07` 3×10–12 F/F/F |
| Lower | Lying Leg Curl (3) | Lying_Leg_Curls | Seated Leg Curl | substitution 1 | `lower_01` 3×6–8 F/F/F; drop sets wk 8–12 |
| Lower | Pendulum Squat (2) | sp_pendulum_squat | Hack Squat | **swap** (same day, quads, same slot) | `lower_02` 2×4–6 RIR 1/2; warm-up 2–3; rest 2–4 min; no failed-rep attempts |
| Lower | Leg Extension (3) | Leg_Extensions | Leg Extension | program | `lower_03` 2×6–8 F/F, then `lower_04` 1×20 F |
| Lower | Walking Lunge (1) | sp_db_walking_lunge | DB Walking Lunge | program | `lower_05` 1×10 per leg F |
| Lower | Sled Press Calf Raise (3) | Calf_Press_On_The_Leg_Press_Machine | Standing Calf Raise | substitution 2 ("Leg Press Calf Press") | `lower_06` 3×10–12 F/F/F; static hold wk 8–12 |
| Lower | Back Extension (1) **(confirm)** | Hyperextensions_Back_Extensions | Glute Kickback | substitution 1 ("45° Hyperextension") | `lower_07` 1×30 F |
| Push | High-to-Low Cable Fly (2) | Cable_Crossover | Cable Flye | program | `push_07` 2×10–12 F/F; drop sets wk 8–12 |
| Push | Seated Smith Machine Shoulder Press (2) | Smith_Machine_Overhead_Shoulder_Press | Machine Shoulder Press | substitution 2 | `push_01` 2×4–6 F/RIR 1; drop sets wk 8–12 |
| Push | Smith Machine Bench Press (2) | Smith_Machine_Bench_Press | DB Bench Press | substitution 1 | `push_02` 1×10 F, then `push_03` 1×20 F; no failed-rep attempts |
| Push | Single Leg Extension (1) | Single-Leg_Leg_Extension | Single-Leg Leg Extension | program | `push_04` 1×20 F |
| Push | Standing Machine Lateral Raise (2) | sp_standing_machine_lateral_raise | Machine Lateral Raise | program | `push_05` 1×10 F, then `push_06` 1×20 F |
| Pull | Assisted Pull-Ups (3) | sp_assisted_pull_up_machine | Pull-Up (Wide Grip) | program (assisted) | `pull_01` 3×4–6 F/RIR 1/RIR 1 |
| Pull | Stiff-Leg Deadlift (2) | Stiff-Legged_Barbell_Deadlift | Stiff-Leg Deadlift | program | `pull_02` 2×6–8 RIR 1/2; warm-up 2–3 |
| Pull | Close-Grip Lat Pulldown (2) | Close-Grip_Front_Lat_Pulldown | Close-Grip Lat Pulldown | program | `pull_03` 1×10 F, then `pull_04` 1×20 F |
| Pull | Dumbbell Row (2) | One-Arm_Dumbbell_Row | Chest-Supported Machine Row | substitution 2 ("DB Row") | `pull_05` 2×4–6 F/F; myo-reps wk 8–12 |
| Pull | Machine Reverse Fly (2) | Reverse_Machine_Flyes | 1-Arm Reverse Pec Deck | program (two-arm machine) | `pull_06` 1×20 F, then `pull_07` 1×10 F |
| Pull | Face Pull (1) **(confirm)** | Face_Pull | — | **extra** | inherits `pull_06` 1×20 F |
| Pull | Decline Crunch (2) | Decline_Crunch | Cable Crunch | **swap** (same day, abs, same slot) | `pull_08` 2×6–8 F/F; drop sets wk 8–12 |
| Arms | EZ Bar Curl (2) | EZ-Bar_Curl | EZ-Bar Cheat Curl | program (strict variant) | `arms_01` 2×4–6 F/F; superset S1 |
| Arms | Cable Overhead Triceps Extension (2) | Cable_Rope_Overhead_Triceps_Extension | EZ-Bar Skull Crusher | substitution 2 | `arms_02` 2×6–8 F/F; S1; rest 30–60 s |
| Arms | Preacher Hammer Curl (2) | Preacher_Hammer_Dumbbell_Curl | Preacher Hammer Curl | program | `arms_03` 2×6–8 F/F; S2; myo-reps wk 8–12 |
| Arms | Triceps Pushdown (2) | Triceps_Pushdown | Triceps Pressdown | program | `arms_04` 2×4–6 F/F; S2; myo-reps wk 8–12 |
| Arms | Cable Wrist Curl (2) | Cable_Wrist_Curl | DB Wrist Curl | substitution 1 | `arms_05` 2×10–12 F/F; S3 |
| Arms | Cable Reverse Wrist Curl (2) | sp_cable_reverse_wrist_curl | DB Wrist Extension | substitution 1 ("Cable Wrist Extension") | `arms_06` 2×10–12 F/F; S3 |
| Arms | Cable Lateral Raise (2) | sp_cable_lateral_raise | Single-Arm Machine Lateral Raise | substitution 1 ("High-Cable Lateral Raise") | `arms_07` 1×20 F, then `arms_08` 1×10 F |

**Your swaps and what they inherit:**
- Straight Arm Pulldown ← Machine Lat Pullover (`upper_03` + `upper_04`)
- Pendulum Squat ← Hack Squat (`lower_02`)
- Decline Crunch ← Cable Crunch (`pull_08`)
- Face Pull (extra) ← 1-Arm Reverse Pec Deck 1×20 (`pull_06`)

Every other exercise is the program's exercise (some under your name) or one of its listed
substitutions.

**Library additions** (free-exercise-db has none of these): Pendulum Squat, Dumbbell Incline Y Raise,
Standing Machine Lateral Raise, Assisted Pull-Up (Machine), Cable Reverse Wrist Curl, Cable Lateral
Raise, Dumbbell Walking Lunge. They're in `assets/extra_exercises.json`.

Your working-set counts equal the program's total for every exercise. Face Pull is the exception: it
adds 1 set.
