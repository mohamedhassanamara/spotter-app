# Spotter — Build Plan

Personal, on-device, gamified strength-training app for iOS (Flutter) with a coach that
suggests weight × reps × sets from lifting history + Apple Health recovery data and
actively discourages ego lifting.

## 1. Architecture

```
lib/
  main.dart                 app bootstrap (DB, timezone, notifications, ProviderScope)
  app.dart                  MaterialApp.router + theme
  router.dart               go_router config (bottom-nav shell + full-screen routes)
  core/
    db/                     drift database, tables, migrations, DAOs
    health/                 HealthDataSource interface, HealthKit impl, fake impl, sync service
    domain/                 shared PURE models (muscle groups, e1RM, equipment, dates)
    settings/               typed settings stored in the DB key/value table
    notifications/          rest-timer local notifications
    theme/                  dark theme, tier colours, spacing
    widgets/                shared widgets (big buttons, cards, number steppers…)
  features/
    library/      {data, domain, presentation}   exercise catalogue, muscle mapping, custom exercises
    workout/      {data, domain, presentation}   routines, active session, rest timer, summary
    history/      {data, presentation}           calendar, session detail, per-exercise charts
    readiness/    {data, domain, presentation}   daily metrics → readiness score
    coach/        {data, domain}                 suggestion engine, guardrail (override, ego flag, freeze)
    ranks/        {data, domain, presentation}   strength standards, tiers, body graph
    gamification/ {data, domain, presentation}   XP, levels, streaks, achievements, quests
    profile/      {presentation}                 level, achievements, discipline
    settings/     {presentation}                 increments, rep defaults, goal, export, debug menu
    export/       {data, domain}                 JSON + CSV export
    onboarding/   {presentation}
    home/         {presentation}
    debug/        {data, presentation}           seed generator, fake-health toggle (debug builds only)
```

Rules:
- Everything under `features/*/domain` and `core/domain` is **pure Dart**: no `package:flutter`,
  no drift imports. These hold readiness, suggestion engine, guardrail, ranks, XP, streaks,
  achievements and quest logic and are unit-tested with fixed fixtures.
- `data` layers translate DB rows / Health samples into domain models.
- Riverpod (`flutter_riverpod` 3, hand-written providers, no codegen) wires repositories and
  view-models. drift is the single source of truth; UI watches drift streams.
- Health is behind `HealthDataSource` with `HealthKitDataSource` and `FakeHealthDataSource`.
  Debug builds expose a toggle in the hidden debug menu (long-press the version label in Settings).
- A future watchOS app would only need to talk to the same domain layer + DB export schema.

## 2. Database schema (drift, schemaVersion 1)

| Table | Columns |
|---|---|
| `exercises` | `id` TEXT PK (dataset id or `custom_<ts>`), `name`, `primary_muscles` JSON, `secondary_muscles` JSON, `equipment` nullable, `level` nullable, `mechanic` nullable, `category` nullable, `instructions` JSON, `images` JSON, `is_custom`, `is_favorite`, `notes` nullable |
| `routines` | `id` PK, `name`, `position`, `created_at` |
| `routine_exercises` | `id` PK, `routine_id` FK, `exercise_id` FK, `position`, `rep_min`, `rep_max`, `target_sets`, `rest_seconds`, `target_rir` |
| `sessions` | `id` PK, `routine_id` nullable, `name`, `started_at`, `ended_at` nullable, `notes`, `status` (`active`/`finished`), `readiness_score` nullable, `readiness_band` nullable, `health_synced` bool, `xp_earned` |
| `session_exercises` | `id` PK, `session_id` FK, `exercise_id` FK, `position`, `notes`, `rep_min`, `rep_max`, `target_sets`, `rest_seconds`, `target_rir`, `suggestion_kind`, `suggested_weight` nullable, `suggested_reps` nullable, `suggested_sets` nullable, `suggestion_json` (headline + why) |
| `workout_sets` | `id` PK, `session_exercise_id` FK, `position`, `is_warmup`, `weight`, `reps`, `rpe` nullable, `completed`, `completed_at` nullable, `suggested_weight` nullable, `suggested_reps` nullable, `is_override`, `override_reason` nullable |
| `daily_metrics` | `date` TEXT PK (`yyyy-MM-dd`), `hrv_ms`, `resting_hr`, `sleep_minutes`, `active_energy_kcal` (all nullable), `readiness_score` nullable, `readiness_band` nullable, `calibrating`, `explanation`, `updated_at` |
| `body_weights` | `id` PK, `measured_at`, `kg`, `source` (`health`/`manual`) |
| `ego_freezes` | `id` PK, `exercise_id`, `started_at`, `until`, `base_weight`, `reason` |
| `xp_events` | `id` PK, `at`, `amount`, `reason`, `session_id` nullable, `week_start` nullable |
| `achievements_unlocked` | `key` PK, `unlocked_at` |
| `quests` | `id` PK, `week_start`, `key`, `params` JSON, `title`, `completed_at` nullable |
| `app_settings` | `key` PK, `value` |

Migrations: `MigrationStrategy` with `onCreate` (+ indices) and an `onUpgrade` stepper ready for v2+.

## 3. Packages (exact pins)

| Package | Version | Why |
|---|---|---|
| flutter_riverpod | 3.4.3 | state |
| drift / drift_flutter | 2.35.2 / 0.3.1 | SQLite ORM + Flutter setup |
| drift_dev, build_runner (dev) | 2.35.1, 2.15.1 | codegen (build_runner 2.16 needs a newer `meta` than the Flutter SDK pins) |
| go_router | 18.0.2 | navigation |
| health | 13.3.2 | HealthKit read/write |
| fl_chart | 1.2.0 | e1RM / readiness charts |
| cached_network_image | 4.0.3 | exercise images (4.0.4 needs Dart 3.13) |
| flutter_local_notifications | 22.3.2 | rest timer alerts |
| timezone / flutter_timezone | 0.11.1 / 5.1.1 | zoned scheduling for notifications |
| url_launcher | 6.3.3 | YouTube form search |
| share_plus | 13.3.1 | iOS share sheet for export |
| path_provider / path | 2.1.6 / 1.9.1 | export files, DB location |
| intl | 0.20.2 | date formatting (pinned by Flutter SDK) |
| collection | 1.19.1 | helpers |
| shared_preferences | 2.5.6 | only for the pre-DB "onboarded" flag during bootstrap |

## 4. Build phases (one commit each)

1. **Setup & database** — project, pins, HealthKit capability & plist, drift schema, theme, router shell.
2. **Library** — asset import, muscle mapping, search/filter, favorites, detail, custom exercises.
3. **Logging** — routines, active workout, rest timer + notifications, resume, summary, history.
4. **Health & readiness** — data source interface, HealthKit + fake impls, aggregation, readiness, home card.
5. **Suggestion engine & guardrail** — progression, readiness modifiers, calibration, plateau, overrides, ego flag, freeze.
6. **Ranks & body graph** — strength standards asset, tiers/divisions, muscle aggregation, body painter.
7. **Streaks, XP & quests** — weekly streak with smart rest, XP/levels, achievements, weekly quests.
8. **Export, polish & tests** — JSON/CSV export + schema doc, seed generator, debug menu, README.
