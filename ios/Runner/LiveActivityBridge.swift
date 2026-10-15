import ActivityKit
import Flutter
import UIKit

/// Flutter ↔ ActivityKit for the rest timer. Channel `spotter/live_activity`:
/// - `start {workoutName, exerciseName, nextTarget, startMillis, endMillis}`: starts or replaces the rest activity;
/// - `end`: removes it now.
/// When the app goes to the background with a rest running, the activity is *ended with a dismissal date at
/// the rest's end*: it stays on the lock screen counting down (system timer text) and removes itself at 0:00,
/// with no app update needed. Coming back, Dart restarts it if the rest is still running.
final class LiveActivityBridge: NSObject {
    private let channel: FlutterMethodChannel
    private var current: Activity<RestTimerAttributes>?
    private var observers: [NSObjectProtocol] = []

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "spotter/live_activity", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.finalizeForBackground()
        })
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "available":
            result(ActivityAuthorizationInfo().areActivitiesEnabled)
        case "activeCount":
            // Running rest activities (used by the integration tests).
            result(Activity<RestTimerAttributes>.activities.filter { $0.activityState == .active }.count)
        case "start":
            guard let a = call.arguments as? [String: Any],
                  let exercise = a["exerciseName"] as? String,
                  let target = a["nextTarget"] as? String,
                  let startMs = a["startMillis"] as? Double,
                  let endMs = a["endMillis"] as? Double else {
                result(FlutterError(code: "args", message: "bad arguments", details: nil))
                return
            }
            let state = RestTimerAttributes.ContentState(
                exerciseName: exercise,
                nextTarget: target,
                startDate: Date(timeIntervalSince1970: startMs / 1000),
                endDate: Date(timeIntervalSince1970: endMs / 1000))
            Task {
                await self.startOrUpdate(workoutName: (a["workoutName"] as? String) ?? "Workout", state: state)
                result(self.current != nil)
            }
        case "end":
            Task {
                await self.endAll(policy: .immediate)
                result(nil)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startOrUpdate(workoutName: String, state: RestTimerAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: state.endDate)
        if let live = current, live.activityState == .active {
            await live.update(content)
            return
        }
        await endAll(policy: .immediate) // anything left over from an earlier run
        do {
            current = try Activity.request(attributes: RestTimerAttributes(workoutName: workoutName), content: content, pushType: nil)
        } catch {
            NSLog("Live Activity request failed: \(error)")
        }
    }

    private func endAll(policy: ActivityUIDismissalPolicy) async {
        for activity in Activity<RestTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: policy)
        }
        current = nil
    }

    /// Backgrounded mid-rest: end the activity now but keep it visible until the rest's end.
    private func finalizeForBackground() {
        guard let live = current, live.activityState == .active else { return }
        let state = live.content.state
        guard state.endDate > Date() else {
            Task { await self.endAll(policy: .immediate) }
            return
        }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg) }
        Task {
            await live.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(state.endDate))
            self.current = nil
            UIApplication.shared.endBackgroundTask(bg)
        }
    }
}
