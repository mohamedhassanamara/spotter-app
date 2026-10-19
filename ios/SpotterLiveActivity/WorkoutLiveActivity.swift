import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.353, green: 0.722, blue: 1.0)      // AppColors.accent  #5AB8FF
private let green = Color(red: 0.486, green: 0.949, blue: 0.612)     // AppColors.primary #7CF29C
private let warm = Color(red: 1.0, green: 0.757, blue: 0.271)        // AppColors.warning #FFC145
private let panel = Color(red: 0.067, green: 0.086, blue: 0.122)     // AppColors.surface #11161F
private let secondary = Color(red: 0.604, green: 0.651, blue: 0.737) // AppColors.textSecondary

private typealias State = WorkoutActivityAttributes.ContentState

private func phaseIcon(_ phase: String) -> String {
    switch phase {
    case "warmup": return "flame.fill"
    case "rest": return "timer"
    case "done": return "checkmark.circle.fill"
    default: return "figure.strengthtraining.traditional"
    }
}

private func phaseTint(_ phase: String) -> Color {
    switch phase {
    case "warmup": return warm
    case "rest": return accent
    default: return green
    }
}

private func phaseTitle(_ phase: String) -> String {
    switch phase {
    case "warmup": return "WARM-UP"
    case "rest": return "REST"
    case "done": return "DONE"
    default: return "WORKING SET"
    }
}

/// Lock screen and Dynamic Island for the whole workout.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(workout: context.attributes.workoutName, state: context.state)
                .activityBackgroundTint(panel)
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(phaseTitle(s.phase), systemImage: phaseIcon(s.phase))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(phaseTint(s.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigTime(state: s)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(phaseTint(s.phase))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.exerciseName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Details(state: s)
                }
            } compactLeading: {
                Image(systemName: phaseIcon(s.phase)).foregroundStyle(phaseTint(s.phase))
            } compactTrailing: {
                BigTime(state: s)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(phaseTint(s.phase))
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: phaseIcon(s.phase)).foregroundStyle(phaseTint(s.phase))
            }
            .keylineTint(phaseTint(s.phase))
        }
    }
}

/// The big number: the rest countdown while resting, otherwise the workout's elapsed time. Both are system timers.
private struct BigTime: View {
    let state: State

    var body: some View {
        if state.phase == "rest", let start = state.restStart, let end = state.restEnd {
            Text(timerInterval: start...max(end, start.addingTimeInterval(1)), pauseTime: nil, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(state.workoutStart, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// What comes next: the warm-ups checked off, or the next set's target (and the rest bar).
private struct Details: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.warmups.isEmpty && state.phase != "working" && state.phase != "done" {
                ForEach(Array(state.warmups.enumerated()), id: \.offset) { _, w in
                    HStack(spacing: 6) {
                        Image(systemName: w.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(w.done ? green : secondary)
                        Text(w.text)
                            .font(.subheadline)
                            .strikethrough(w.done, color: secondary)
                            .foregroundStyle(w.done ? secondary : Color.white)
                    }
                }
                if state.warmupsMore > 0 {
                    Text("+\(state.warmupsMore) more").font(.caption).foregroundStyle(secondary)
                }
            }
            if state.phase != "done" || state.warmups.isEmpty {
                Text(state.nextTarget)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.phase == "working" ? Color.white : secondary)
                    .lineLimit(1)
            }
            if !state.setLabel.isEmpty {
                Text(state.setLabel).font(.caption).foregroundStyle(secondary)
            }
            if state.phase == "rest", let start = state.restStart, let end = state.restEnd {
                ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(accent)
            }
        }
    }
}

private struct LockScreenView: View {
    let workout: String
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(phaseTitle(state.phase), systemImage: phaseIcon(state.phase))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(phaseTint(state.phase))
                    Text(state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    BigTime(state: state)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(phaseTint(state.phase))
                    if state.phase == "rest" {
                        HStack(spacing: 4) {
                            Text(workout).lineLimit(1)
                            Text(state.workoutStart, style: .timer).monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(secondary)
                    } else {
                        Text(workout).font(.caption2).foregroundStyle(secondary).lineLimit(1)
                    }
                }
            }
            Details(state: state)
        }
        .padding(16)
    }
}
