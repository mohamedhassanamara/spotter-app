import ActivityKit
import Flutter
import UIKit

/// Flutter ↔ ActivityKit for the workout's Live Activity. Channel `spotter/live_activity`:
/// - `sync {phase, workoutName, exerciseName, nextTarget, setLabel, workoutStartMillis, restStartMillis?, restEndMillis?,
///   warmups: [{text, done}], warmupsMore}`: starts the activity or updates the running one;
/// - `end`: removes it now (workout finished or discarded);
/// - `activeCount`: running activities (integration tests).
/// The elapsed time and the rest countdown are system timer texts drawn from dates, so they keep running with the app suspended.
final class LiveActivityBridge: NSObject {
    private let channel: FlutterMethodChannel
    private var current: Activity<WorkoutActivityAttributes>?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "spotter/live_activity", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "available":
            result(ActivityAuthorizationInfo().areActivitiesEnabled)
        case "activeCount":
            result(Activity<WorkoutActivityAttributes>.activities.filter { $0.activityState == .active }.count)
        case "sync":
            guard let a = call.arguments as? [String: Any],
                  let phase = a["phase"] as? String,
                  let exercise = a["exerciseName"] as? String,
                  let target = a["nextTarget"] as? String,
                  let startMs = a["workoutStartMillis"] as? Double else {
                result(FlutterError(code: "args", message: "bad arguments", details: nil))
                return
            }
            func date(_ key: String) -> Date? {
                (a[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            }
            let warmups = ((a["warmups"] as? [[String: Any]]) ?? []).map {
                WorkoutActivityAttributes.WarmupLine(text: ($0["text"] as? String) ?? "", done: ($0["done"] as? Bool) ?? false)
            }
            let state = WorkoutActivityAttributes.ContentState(
                phase: phase,
                exerciseName: exercise,
                nextTarget: target,
                setLabel: (a["setLabel"] as? String) ?? "",
                workoutStart: Date(timeIntervalSince1970: startMs / 1000),
                restStart: date("restStartMillis"),
                restEnd: date("restEndMillis"),
                warmups: warmups,
                warmupsMore: (a["warmupsMore"] as? Int) ?? 0)
            Task {
                await self.startOrUpdate(workoutName: (a["workoutName"] as? String) ?? "Workout", state: state)
                result(self.current != nil)
            }
        case "end":
            Task {
                await self.endAll()
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startOrUpdate(workoutName: String, state: WorkoutActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let live = current ?? Activity<WorkoutActivityAttributes>.activities.first(where: { $0.activityState == .active }),
           live.activityState == .active {
            current = live
            await live.update(content)
            return
        }
        do {
            current = try Activity.request(attributes: WorkoutActivityAttributes(workoutName: workoutName), content: content, pushType: nil)
        } catch {
            NSLog("Live Activity request failed: \(error)")
        }
    }

    private func endAll() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        current = nil
    }
}
