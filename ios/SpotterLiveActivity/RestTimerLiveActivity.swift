import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.353, green: 0.722, blue: 1.0)      // AppColors.accent  #5AB8FF
private let panel = Color(red: 0.067, green: 0.086, blue: 0.122)     // AppColors.surface #11161F
private let secondary = Color(red: 0.604, green: 0.651, blue: 0.737) // AppColors.textSecondary

/// Lock screen and Dynamic Island for the rest timer. The countdown is `Text(timerInterval:)` and the bar a
/// timer-driven `ProgressView`, both drawn by the system, so they run with the app suspended.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(panel)
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("REST", systemImage: "timer")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.nextTarget)
                            .font(.subheadline)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                        ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(accent)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(accent)
            } compactTrailing: {
                Countdown(state: context.state)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

/// "1:26", counting down on its own.
private struct Countdown: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.startDate...state.endDate, pauseTime: nil, countsDown: true, showsHours: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

private struct LockScreenView: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("REST", systemImage: "timer")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(accent)
                    Text(state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Countdown(state: state)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
            }
            Text(state.nextTarget)
                .font(.subheadline)
                .foregroundStyle(secondary)
                .lineLimit(1)
            ProgressView(timerInterval: state.startDate...state.endDate, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
        }
        .padding(16)
    }
}
