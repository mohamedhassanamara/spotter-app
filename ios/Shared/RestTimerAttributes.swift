import ActivityKit
import Foundation

/// The rest timer's Live Activity. Compiled into both the app (which starts / updates / ends it) and the
/// widget extension (which draws it), so the two always agree on the shape of the data.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The exercise coming up (or the one being rested after).
        var exerciseName: String
        /// The next set's target, e.g. "Set 3 · 80 kg × 8".
        var nextTarget: String
        var startDate: Date
        /// When the rest ends. The countdown is a system timer text, so nothing has to update it.
        var endDate: Date
    }

    var workoutName: String
}
