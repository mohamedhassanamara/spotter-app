import SwiftUI
import WidgetKit

// The workout Live Activity's views. Compiled into the widget extension (which shows them on the lock screen and in the Dynamic Island)
// and into the app (which renders them to PNG for the layout checks in the integration tests: same code, same size).
//
// Budget: the lock screen gives an activity about 160 pt of height, so the layout is three tight rows: header (phase, exercise, set
// | one big timer), one row of warm-up chips, one "Next:" line.

let activityAccent = Color(red: 0.353, green: 0.722, blue: 1.0)      // AppColors.accent  #5AB8FF
let activityGreen = Color(red: 0.486, green: 0.949, blue: 0.612)     // AppColors.primary #7CF29C
let activityWarm = Color(red: 1.0, green: 0.757, blue: 0.271)        // AppColors.warning #FFC145
let activityPanel = Color(red: 0.067, green: 0.086, blue: 0.122)     // AppColors.surface #11161F
let activitySecondary = Color(red: 0.604, green: 0.651, blue: 0.737) // AppColors.textSecondary

typealias ActivityState = WorkoutActivityAttributes.ContentState

func phaseIcon(_ phase: String) -> String {
    switch phase {
    case "warmup": return "flame.fill"
    case "rest": return "timer"
    case "done": return "checkmark.circle.fill"
    default: return "figure.strengthtraining.traditional"
    }
}

func phaseTint(_ phase: String) -> Color {
    switch phase {
    case "warmup": return activityWarm
    case "rest": return activityAccent
    default: return activityGreen
    }
}

func phaseTitle(_ phase: String) -> String {
    switch phase {
    case "warmup": return "WARM-UP"
    case "rest": return "REST"
    case "done": return "DONE"
    default: return "WORKING"
    }
}

/// The one big number: the rest countdown while resting, otherwise the workout's elapsed time. Both are system timers.
struct ActivityTimer: View {
    let state: ActivityState
    var size: CGFloat = 44

    var body: some View {
        Group {
            if state.phase == "rest", let start = state.restStart, let end = state.restEnd {
                Text(timerInterval: start...max(end, start.addingTimeInterval(1)), pauseTime: nil, countsDown: true, showsHours: false)
            } else {
                Text(state.workoutStart, style: .timer)
            }
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(phaseTint(state.phase))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 150, alignment: .trailing)
    }
}

/// One row of compact warm-up chips: "25×6 ✓  40×4  50×3". Never a vertical list.
struct WarmupChips: View {
    let state: ActivityState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.warmups.enumerated()), id: \.offset) { _, w in
                HStack(spacing: 3) {
                    Text(w.text).font(.system(size: 12, weight: .bold, design: .rounded))
                    if w.done { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                }
                .foregroundStyle(w.done ? activityGreen : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(w.done ? activityGreen.opacity(0.16) : Color.white.opacity(0.10)))
                .fixedSize()
            }
            if state.warmupsMore > 0 {
                Text("+\(state.warmupsMore)").font(.system(size: 11, weight: .bold)).foregroundStyle(activitySecondary)
            }
        }
        .lineLimit(1)
    }
}

/// A thin bar for the rest. [staticFraction] draws a fixed fill (used when rendering to PNG, where timer-driven bars do not render).
struct RestBar: View {
    let state: ActivityState
    var staticFraction: Double?

    var body: some View {
        if let f = staticFraction {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(activityAccent).frame(width: g.size.width * f)
                }
            }
            .frame(height: 4)
        } else if let start = state.restStart, let end = state.restEnd {
            ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(activityAccent)
                .frame(height: 4)
        }
    }
}

/// Lock screen content (and the Dynamic Island's expanded view uses the same pieces).
struct ActivityLockScreen: View {
    let workout: String
    let state: ActivityState
    var staticFraction: Double?

    var showChips: Bool { !state.warmups.isEmpty && state.warmups.contains { !$0.done } && state.phase != "done" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(phaseTitle(state.phase), systemImage: phaseIcon(state.phase))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(phaseTint(state.phase))
                    Text(state.exerciseName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(state.setLabel.isEmpty ? workout : state.setLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(activitySecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ActivityTimer(state: state)
            }
            if showChips { WarmupChips(state: state) }
            Text(state.nextTarget)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(state.phase == "rest" || state.phase == "warmup" ? Color.white : activitySecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if state.phase == "rest" { RestBar(state: state, staticFraction: staticFraction) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
