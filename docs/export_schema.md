# Spotter export schema (schema_version 1)

Spotter exports everything stored on the device: as one JSON document, or as three CSV files.
Start an export from **Settings → Export**. The files go to the iOS share sheet.

## Conventions

- **Timestamps:** ISO 8601 with the local UTC offset, to the second. Example: `2026-10-12T18:05:00+02:00`.
- **Dates:** `yyyy-MM-dd` in local time. A readiness day is the morning after the night it describes.
- **Units:** weight in kg, sleep in minutes, HRV (SDNN) in ms, heart rate in bpm, energy in kcal.
  The JSON `units` object repeats this.
- **Weights:** `weight_kg` is the **external load**. For bodyweight lifts (pull-ups, dips) it is
  the added load, so 0 means bodyweight only.
- **Missing values:** `null` in JSON, an empty field in CSV.
- **Session scope:** only finished sessions are exported. An in-progress workout is not.
- **Ordering:** sessions by `started_at`, exercises by `position`, sets by `position`,
  readiness days by `date`.

### Versioning policy

`schema_version` is an integer.
- **Additive changes** don't bump it: a new field, a new top-level array, or a new enum value
  in a string field. Consumers must ignore unknown fields.
- **Breaking changes** bump it: a removed or renamed field, a changed type or unit, or a
  changed meaning.

## JSON document

| Field | Type | Notes |
|---|---|---|
| `schema_version` | int | `1` |
| `app` | string | always `"spotter"` |
| `exported_at` | timestamp | |
| `units` | object | `{"weight":"kg","sleep":"minutes","energy":"kcal","hrv":"ms","heart_rate":"bpm"}` |
| `bodyweights` | array | see below |
| `routines` | array | |
| `sessions` | array | finished sessions only |
| `readiness_days` | array | |
| `custom_exercises` | array | user-created exercises |
| `ego_freezes` | array | progression freezes caused by ego flags |
| `xp_events` | array | XP ledger |
| `achievements` | array | unlocked achievements |

### `bodyweights[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `id` | int | no | |
| `measured_at` | timestamp | no | |
| `kg` | number | no | |
| `source` | string | no | `health` or `manual` |

### `routines[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `id` | int | no | |
| `name` | string | no | |
| `position` | int | no | display order |
| `created_at` | timestamp | no | |
| `exercises[]` | array | no | each item has `exercise_id`, `exercise_name`, `position`, `rep_min`, `rep_max`, `target_sets`, `target_rir`, `rest_s` |

### `sessions[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `id` | int | no | |
| `name` | string | no | |
| `routine_id` | int | yes | null for an empty-start workout |
| `started_at` | timestamp | no | |
| `ended_at` | timestamp | yes | always set for finished sessions |
| `duration_s` | int | yes | `ended_at − started_at`, in seconds |
| `notes` | string | no | may be empty |
| `readiness_score` | int 0–100 | yes | null while calibrating or with no Health data |
| `readiness_band` | string | yes | `green`, `yellow` or `red` |
| `xp_earned` | int | no | session XP plus bonuses (weekly goal, quests) |
| `health_synced` | bool | no | the workout was written to Apple Health |
| `exercises[]` | array | no | see below |

### `sessions[].exercises[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `session_exercise_id` | int | no | |
| `exercise_id` | string | no | free-exercise-db id, or `custom_<n>` |
| `exercise_name` | string | no | |
| `position` | int | no | |
| `rep_min`, `rep_max` | int | no | target rep range |
| `target_sets` | int | no | from the routine |
| `target_rir` | int | no | reps in reserve |
| `rest_s` | int | no | rest timer in seconds |
| `suggestion_kind` | string | no | `calibration`, `seeded`, `increase`, `addReps`, `reduce`, `plateauDeload`, `egoFreeze` or `none` |
| `suggested_weight` | number | yes | kg |
| `suggested_reps` | int | yes | |
| `suggested_sets` | int | yes | working sets after readiness modifiers |
| `notes` | string | no | |
| `sets[]` | array | no | see below |

### `sessions[].exercises[].sets[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `set_id` | int | no | |
| `position` | int | no | |
| `is_warmup` | bool | no | warm-ups never count for coaching, ranks, XP or volume |
| `weight_kg` | number | no | external load |
| `reps` | int | no | |
| `rpe` | number | yes | 6–10 in 0.5 steps |
| `rir` | number | yes | `10 − rpe` |
| `completed` | bool | no | always true after finishing (incomplete sets are dropped) |
| `completed_at` | timestamp | yes | |
| `suggested_weight_kg` | number | yes | null for warm-ups and calibration sets |
| `suggested_reps` | int | yes | |
| `is_override` | bool | no | logged more than 5% above the suggestion |
| `override_reason` | string | yes | `feltStrong`, `testingMax` or `justDidIt` |
| `e1rm_kg` | number | yes | Epley on effective reps, `weight × (1 + (reps + RIR)/30)`, with RPE 9 assumed when it's missing. Working sets only. External load only, so bodyweight is not added. |
| `is_ego_set` | bool | no | override at RPE ≥ 9.5. Excluded from ranks and PRs. |

### `readiness_days[]`
| Field | Type | Null | Notes |
|---|---|---|---|
| `date` | date | no | |
| `hrv_ms` | number | yes | mean SDNN during the night's sleep, or over the last 24 h without sleep data |
| `resting_hr_bpm` | number | yes | |
| `sleep_minutes` | number | yes | asleep stages only. In-bed and awake time are excluded. |
| `active_energy_kcal` | number | yes | total for that calendar day |
| `readiness_score` | int 0–100 | yes | null when no metric is available |
| `readiness_band` | string | yes | `green`, `yellow` or `red`. Null while calibrating. |
| `calibrating` | bool | no | fewer than 14 baseline days |
| `explanation` | string | no | plain-English reason |

### Other arrays
- `custom_exercises[]`: `id`, `name`, `primary_muscles` (string[]), `secondary_muscles`
  (string[]), `equipment` (nullable), `mechanic` (`compound` or `isolation`), `notes` (nullable).
- `ego_freezes[]`: `id`, `exercise_id`, `started_at`, `until`, `base_weight_kg`, `reason`.
- `xp_events[]`: `id`, `at`, `amount`, `reason` (`session`, `weekly_goal` or `quest`),
  `session_id` (nullable), `week_start` (date, nullable).
- `achievements[]`: `key` (see `assets/achievements.json`), `unlocked_at`.

### Example

```json
{
  "schema_version": 1,
  "app": "spotter",
  "exported_at": "2026-10-12T18:05:00+02:00",
  "units": {"weight": "kg", "sleep": "minutes", "energy": "kcal", "hrv": "ms", "heart_rate": "bpm"},
  "sessions": [
    {
      "id": 41, "name": "Push A", "routine_id": 1,
      "started_at": "2026-10-10T18:02:11+02:00", "ended_at": "2026-10-10T19:10:40+02:00",
      "duration_s": 4109, "notes": "", "readiness_score": 63, "readiness_band": "green",
      "xp_earned": 340, "health_synced": true,
      "exercises": [
        {
          "session_exercise_id": 201, "exercise_id": "Barbell_Bench_Press_-_Medium_Grip",
          "exercise_name": "Barbell Bench Press - Medium Grip", "position": 0,
          "rep_min": 6, "rep_max": 10, "target_sets": 3, "target_rir": 2, "rest_s": 150,
          "suggestion_kind": "increase", "suggested_weight": 82.5, "suggested_reps": 6,
          "suggested_sets": 3, "notes": "",
          "sets": [
            {"set_id": 900, "position": 0, "is_warmup": false, "weight_kg": 82.5, "reps": 7,
             "rpe": 8, "rir": 2, "completed": true, "completed_at": "2026-10-10T18:12:00+02:00",
             "suggested_weight_kg": 82.5, "suggested_reps": 6, "is_override": false,
             "override_reason": null, "e1rm_kg": 107.25, "is_ego_set": false}
          ]
        }
      ]
    }
  ],
  "readiness_days": [
    {"date": "2026-10-10", "hrv_ms": 58.2, "resting_hr_bpm": 55, "sleep_minutes": 452,
     "active_energy_kcal": 512, "readiness_score": 63, "readiness_band": "green",
     "calibrating": false, "explanation": "All recovery metrics close to your baseline"}
  ]
}
```

## CSV files

RFC 4180: comma-separated, CRLF line endings, UTF-8, and a header row first. A field that
contains a comma, a quote or a newline is wrapped in double quotes, with inner quotes doubled.
Booleans are `true` or `false`. Nulls are empty fields. Column names match the JSON field names.

- `spotter-sessions-<yyyyMMdd-HHmm>.csv`, one row per finished session:
  `id, name, routine_id, started_at, ended_at, duration_s, notes, readiness_score, readiness_band, xp_earned, health_synced`
- `spotter-sets-<stamp>.csv`, one row per set, denormalised:
  `session_id, session_started_at, session_exercise_id, exercise_id, exercise_name, exercise_position, rep_min, rep_max, target_rir, suggestion_kind, set_id, position, is_warmup, weight_kg, reps, rpe, rir, completed, completed_at, suggested_weight_kg, suggested_reps, is_override, override_reason, e1rm_kg, is_ego_set`
- `spotter-readiness-days-<stamp>.csv`, one row per day:
  `date, hrv_ms, resting_hr_bpm, sleep_minutes, active_energy_kcal, readiness_score, readiness_band, calibrating, explanation`
