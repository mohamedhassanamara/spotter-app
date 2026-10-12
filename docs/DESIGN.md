# Spotter design system

Goal: a polished game, not a generic dark Material app. Dark only. One-handed, so the actions you
use mid-set sit in the lower two-thirds of the screen and tap targets are large. Rank tiers are the
main accent system.

Code: tokens live in `lib/core/theme/app_theme.dart` (`AppColors`, `AppType`, `Space`, `Radii`,
`Motion`). Components live in `lib/core/widgets/game_ui.dart`.

## Tokens

### Colour

| Token | Value | Use |
|---|---|---|
| `background` | `#090C12` | Scaffold |
| `surface` (s1) | `#11161F` | Cards, sheets |
| `surfaceHigh` (s2) | `#18202D` | Raised elements: inputs, set rows, chips |
| `surfaceTop` (s3) | `#212B3B` | Pressed or selected surfaces, stepper buttons |
| `outline` | `#263043` | 1 px borders on every layer |
| `outlineBright` | `#34405A` | Focused borders, dividers on s2 |
| `textPrimary` / `textSecondary` / `textTertiary` | `#F2F5FA` / `#9AA6BC` / `#667189` | |
| `primary` (success, readiness Green) | `#7CF29C` | Primary buttons, completed sets |
| `xp` | `#B98CFF` | XP, levels |
| `warning` | `#FFC145` | Overrides, Yellow readiness |
| `danger` | `#FF5D6C` | Ego flags, Red readiness, destructive |
| `accent` | `#5AB8FF` | Info, rest timer |
| Tier colours | Iron `#8B8580` → Challenger `#FFE27A` (`tierColors`) | Badges, LP bars, body map, hero card glow |

**Layering.** Every card is a gradient from s1 at the top-left to a slightly darker s1 at the
bottom-right, with a 1 px `outline` border. Cards that carry a rank or a state add a coloured border
at 45% alpha and a soft glow (a 24 px blurred shadow at 18% alpha). There are no flat boxes and no
Material elevation tint.

### Type

| Role | Font | Size / weight | Notes |
|---|---|---|---|
| Display XL | Oxanium | 44 / 800 | Hero numbers: score, XP count-up |
| Display | Oxanium | 32 / 800 | Screen-level numbers, rank names |
| Title L | Oxanium | 24 / 700 | Screen titles (app bar) |
| Title | Oxanium | 18 / 700 | Card titles, exercise names |
| Number | Oxanium | 22 / 800 | Weights, reps, timers |
| Body | Barlow | 16 / 500 | Text |
| Body S | Barlow | 14 / 500 | Secondary text |
| Label | Barlow | 12 / 700, +1.2 tracking, UPPERCASE | Section headers, field labels |

- Oxanium's digits all share one advance width (578 units), so any number set in Oxanium is
  tabular by construction. Barlow numbers use `FontFeature.tabularFigures()` wherever they can change.
- Both fonts are bundled (SIL OFL, `docs/licenses/`).

### Spacing, radii, targets

- **Spacing:** 4 · 8 · 12 · 16 · 20 · 24 · 32. Screen padding is 16, the gap between cards 12, and
  card padding 16–18.
- **Radii:** 10 (chips) · 14 (inputs, rows, buttons) · 20 (cards) · 28 (sheets).
- **Tap targets:** at least 48 × 48; 56 high for primary actions; 64 for steppers and set-completion
  buttons.

### Motion

- **Durations:** fast 150 ms (presses), base 250 ms (state changes), slow 450 ms (reveals), and
  celebration up to 2.6 s (rank-up).
- **Curves:** `easeOutCubic` for entering, `easeInOutCubic` for flips, `easeOutBack` for badges and
  celebratory pops.
- **Page transitions:** iOS-style slide with swipe-back, for one-handed navigation back. Celebration
  routes (rank-up, summary) fade in.
- **Loading:** skeleton shimmer blocks shaped like the content, never a spinner in content areas.
  Spinners only appear inside buttons.

### Haptics

| Moment | Feedback |
|---|---|
| Set completed (swipe or tap) | `mediumImpact` |
| PR on the summary | `heavyImpact` × 2 |
| Rank-up impact | `heavyImpact` |
| Muscle selected, segment changed | `selectionClick` |
| Rest over | `heavyImpact` |

## Components (`game_ui.dart`)

- **GameCard:** the layered surface above. Takes an optional `accent` colour (border plus glow) and
  `onTap`.
- **LpBar:** tier-coloured progress bar with a rounded track and an "LP" readout.
- **ProgressRing:** circular progress used by the rest timer and level ring, with the label centred.
- **DayDots:** 7 dots, Monday → Sunday. Filled in the success colour when trained, a ring for today,
  a moon for smart rest.
- **Skeleton / SkeletonList:** shimmering placeholder blocks.
- **CountUp:** integer that animates from 0 (or a start value) to its target.
- **SectionLabel:** uppercase label with optional trailing action.
- **PillButton** (rounded secondary action) and **BigButton** (56 px primary, with an optional
  leading icon and a busy state).
- **StepperBox:** − value + with 56 px buttons. Long-press repeats. Tap the value to type it.
- **GuardrailBanner:** amber (override) or red (ego flag) left stripe with an icon, a one-line
  message and an expandable detail. It's firm, not modal. It never blocks the flow except where the
  spec requires RPE and a reason.

## Screen patterns

- **Home**, top to bottom:
  1. Hero card: overall rank badge, LP bar, level.
  2. Readiness card.
  3. One primary button: Resume, or Start <next routine>.
  4. Quests with progress bars.
  5. Streak: day dots plus the week count.
- **Active workout:** each exercise is a card.
  - Card header: name, a form-check (i) button, menu.
  - Coach strip: today's target, expandable "why".
  - Set rows: a large card each. The top line is the target (muted, prefixed "TARGET"). Below it the
    actual weight and reps steppers (equipment increment / ±1), and an RPE chip.
  - Completing a set: swipe right, or tap the check.
  - Completed rows tint green and compact. Override rows get the amber stripe.
  - The rest timer is a pinned bottom bar with a progress ring.
- **Summary:** a celebration. XP counts up, then PRs (trophy cards), rank changes (badges), the
  session's discipline %, and guardrail notes.
- **Ranks:** group rows sorted weakest → strongest (unranked first), each with badge, division and
  LP bar.
- **Profile:** achievements as badge tiles. Locked ones are dark silhouettes with a lock and a
  progress ring.
