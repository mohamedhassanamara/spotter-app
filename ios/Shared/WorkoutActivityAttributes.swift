import ActivityKit
import Foundation

/// The workout's Live Activity: the whole session on the lock screen and in the Dynamic Island, not only the rest. Compiled into
/// both the app (which starts, updates and ends it) and the widget extension (which draws it).
///
/// Everything that changes second by second is drawn by the system from dates (`Text(date, style: .timer)`,
/// `Text(timerInterval:)`), so the elapsed time and the rest countdown run with the app suspended. The rest is only updated when
/// something happens in the app (a set ticked, a rest skipped).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct WarmupLine: Codable, Hashable {
        var text: String   // "40 kg × 8"
        var done: Bool
    }

    struct ContentState: Codable, Hashable {
        /// "warmup" | "working" | "rest" | "done"
        var phase: String
        var exerciseName: String
        /// The next set's target, e.g. "Set 2 · 80 kg × 8".
        var nextTarget: String
        /// "Warm-up 2 of 3", "Set 2 of 3"; empty when there is nothing to count.
        var setLabel: String
        var workoutStart: Date
        var restStart: Date?
        var restEnd: Date?
        /// The current exercise's warm-up sets (at most 4 shown) and how many more there are.
        var warmups: [WarmupLine]
        var warmupsMore: Int
    }

    var workoutName: String
}
