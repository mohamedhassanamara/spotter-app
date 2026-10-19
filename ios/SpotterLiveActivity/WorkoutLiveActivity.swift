import ActivityKit
import SwiftUI
import WidgetKit

/// Lock screen and Dynamic Island for the whole workout. The views are in Shared/WorkoutActivityViews.swift.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            ActivityLockScreen(workout: context.attributes.workoutName, state: context.state)
                .activityBackgroundTint(activityPanel)
                .activitySystemActionForegroundColor(activityAccent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                // Expanded: the same three rows as the lock screen.
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(phaseTitle(s.phase), systemImage: phaseIcon(s.phase))
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(phaseTint(s.phase))
                        Text(s.exerciseName).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        if !s.setLabel.isEmpty {
                            Text(s.setLabel).font(.system(size: 12)).foregroundStyle(activitySecondary).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: s, size: 34)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !s.warmups.isEmpty && s.warmups.contains(where: { !$0.done }) && s.phase != "done" { WarmupChips(state: s) }
                        Text(s.nextTarget).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            } compactLeading: {
                Image(systemName: phaseIcon(s.phase)).foregroundStyle(phaseTint(s.phase))
            } compactTrailing: {
                ActivityTimer(state: s, size: 14).frame(maxWidth: 48)
            } minimal: {
                Image(systemName: phaseIcon(s.phase)).foregroundStyle(phaseTint(s.phase))
            }
            .keylineTint(phaseTint(s.phase))
        }
    }
}
