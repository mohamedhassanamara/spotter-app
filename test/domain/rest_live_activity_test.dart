import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/live_activity/live_activity_service.dart';
import 'package:spotter/core/notifications/notification_service.dart';
import 'package:spotter/features/workout/data/session_repository.dart';
import 'package:spotter/features/workout/domain/rest_preview.dart';
import 'package:spotter/features/workout/presentation/rest_timer.dart';

class _Notifications extends NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<void> scheduleRestDone(DateTime at, {String body = ''}) async {}
  int cancels = 0;
  @override
  Future<void> cancelRest() async => cancels++;
}

class _FakeActivity implements LiveActivityService {
  final calls = <String>[];
  RestActivity? last;
  @override
  Future<void> startRest(RestActivity a) async {
    calls.add('start');
    last = a;
  }

  @override
  Future<void> end() async => calls.add('end');
}

SessionExercise _ex(int id, {int? group}) => SessionExercise(
      id: id,
      sessionId: 1,
      exerciseId: 'x$id',
      position: id,
      notes: '',
      repMin: 6,
      repMax: 8,
      targetSets: 3,
      restSeconds: 90,
      targetRir: 0,
      suggestionKind: 'none',
      restEnabled: true,
      supersetGroup: group,
      targetsEdited: false,
    );

WorkoutSet _set(int id, int ex, int pos, {double kg = 80, int reps = 8, bool done = false, bool warmup = false, String? type}) => WorkoutSet(
      id: id,
      sessionExerciseId: ex,
      position: pos,
      isWarmup: warmup,
      weight: kg,
      reps: reps,
      completed: done,
      isOverride: false,
      partials: false,
      setType: type,
    );

ActiveSession _session(List<ActiveExercise> e) => ActiveSession(
    session: Session(id: 1, name: 'Upper', startedAt: DateTime(2026, 10, 12), notes: '', status: 'active', healthSynced: false, xpEarned: 0, source: 'app'), exercises: e);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('what the lock screen shows next', () {
    test('the next set of the same exercise, numbered among the working sets', () {
      final e = ActiveExercise(row: _ex(1), sets: [_set(1, 1, 0, warmup: true, kg: 40), _set(2, 1, 1, done: true), _set(3, 1, 2), _set(4, 1, 3)], suggestion: null);
      final s = _session([e]);
      final next = nextSetAfter(s, e, e.sets[1])!;
      expect(next.set.id, 3);
      expect(setTarget(e, next.set), 'Set 2 · 80 kg × 8');
      expect(setTarget(e, e.sets[0]), 'Warm-up · 40 kg × 8');
    });

    test('the last set of an exercise points at the next exercise', () {
      final a = ActiveExercise(row: _ex(1), sets: [_set(1, 1, 0, done: true)], suggestion: null);
      final b = ActiveExercise(row: _ex(2), sets: [_set(2, 2, 0, kg: 55.5, reps: 12)], suggestion: null);
      final next = nextSetAfter(_session([a, b]), a, a.sets.first)!;
      expect(next.exercise.row.id, 2);
      expect(setTarget(next.exercise, next.set), 'Set 1 · 55.5 kg × 12');
    });

    test('a superset round comes back to the first partner; nothing left → null', () {
      final a = ActiveExercise(row: _ex(1, group: 1), sets: [_set(1, 1, 0, done: true), _set(2, 1, 1)], suggestion: null);
      final b = ActiveExercise(row: _ex(2, group: 1), sets: [_set(3, 2, 0), _set(4, 2, 1)], suggestion: null);
      final afterB = nextSetAfter(_session([a, b]), b, b.sets.first)!;
      expect(afterB.exercise.row.id, 1, reason: 'round done: A2 is next');
      final last = ActiveExercise(row: _ex(1), sets: [_set(1, 1, 0, done: true)], suggestion: null);
      expect(nextSetAfter(_session([last]), last, last.sets.first), isNull);
    });

    test('drop sets and assisted loads read naturally', () {
      final e = ActiveExercise(row: _ex(1), sets: [_set(1, 1, 0), _set(2, 1, 1, kg: 60, type: 'drop'), _set(3, 1, 2, kg: -25)], suggestion: null);
      expect(setTarget(e, e.sets[1]), 'Drop set · 60 kg × 8');
      expect(setTarget(e, e.sets[2]), 'Set 2 · 25 kg assist × 8');
    });
  });

  group('the rest timer drives the Live Activity', () {
    late AppDatabase db;
    late _FakeActivity activity;
    late ProviderContainer c;
    late _Notifications notes;
    final now = DateTime(2026, 10, 12, 18);
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      activity = _FakeActivity();
      notes = _Notifications();
      c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        liveActivityProvider.overrideWithValue(activity),
        notificationServiceProvider.overrideWithValue(notes),
        clockProvider.overrideWithValue(() => now),
      ]);
      c.listen(settingsProvider, (_, _) {});
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    const preview = RestPreview(workoutName: 'Upper', exerciseName: 'Chest Press', nextTarget: 'Set 2 · 80 kg × 8');

    test('start: the activity carries the exercise, the target and the end time (a system timer shows the countdown)', () async {
      await c.read(restTimerProvider).start(90, preview: preview);
      expect(activity.calls, ['start']);
      expect(activity.last!.exerciseName, 'Chest Press');
      expect(activity.last!.nextTarget, 'Set 2 · 80 kg × 8');
      expect(activity.last!.endsAt, now.add(const Duration(seconds: 90)));
      expect(activity.last!.startsAt, now);
    });

    test('±15 s updates the end; skip, the next set, finishing or the end of the rest end it', () async {
      final timer = c.read(restTimerProvider);
      await timer.start(90, preview: preview);
      await c.read(settingsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await timer.adjust(15);
      expect(activity.last!.endsAt, now.add(const Duration(seconds: 105)));
      expect(activity.calls, ['start', 'start']);
      await timer.stop();
      expect(activity.calls.last, 'end');
      expect(activity.last!.endsAt, now.add(const Duration(seconds: 105)));
    });

    test('a rest without a preview shows nothing; 0 s is a no-op', () async {
      await c.read(restTimerProvider).start(0, preview: preview);
      expect(activity.calls, isEmpty);
      await c.read(restTimerProvider).start(60);
      expect(activity.calls, ['end']);
    });

    test('un-ticking the set whose rest is running cancels it: timer, notification and Live Activity', () async {
      final timer = c.read(restTimerProvider);
      await timer.start(90, preview: preview, setId: 7);
      await c.read(settingsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(currentSettingsProvider).restEndsAt, isNotNull);
      activity.calls.clear();
      final before = notes.cancels;
      expect(await timer.cancelIfFor(7), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(currentSettingsProvider).restEndsAt, isNull, reason: 'the in-app timer is gone');
      expect(activity.calls, ['end'], reason: 'the Live Activity ends');
      expect(notes.cancels, before + 1, reason: 'the pending "rest done" notification is cancelled');
    });

    test('un-ticking some other set leaves the running rest alone; nothing running → nothing to cancel', () async {
      final timer = c.read(restTimerProvider);
      expect(await timer.cancelIfFor(7), isFalse, reason: 'no rest running');
      await timer.start(90, preview: preview, setId: 7);
      await c.read(settingsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      activity.calls.clear();
      expect(await timer.cancelIfFor(3), isFalse);
      expect(activity.calls, isEmpty);
      expect(c.read(currentSettingsProvider).restEndsAt, isNotNull);
    });

    test('a rest from before this process (set unknown) is cancelled when the latest set done is un-ticked', () async {
      final timer = c.read(restTimerProvider);
      await timer.start(90, preview: preview);
      await c.read(settingsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await timer.cancelIfFor(9, latestDone: false), isFalse);
      expect(await timer.cancelIfFor(9, latestDone: true), isTrue);
    });

    test('back in the foreground mid-rest: the activity is shown again with the same end', () async {
      final timer = c.read(restTimerProvider);
      await timer.start(90, preview: preview);
      await c.read(settingsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      activity.calls.clear();
      await timer.resync();
      expect(activity.calls, ['start']);
      expect(activity.last!.endsAt, now.add(const Duration(seconds: 90)));
    });
  });

  test('the platform channel: start arguments reach native; a missing plugin is harmless', () async {
    final seen = <MethodCall>[];
    const channel = MethodChannel('spotter/live_activity');
    TestWidgetsFlutterBinding.ensureInitialized();
    final svc = ChannelLiveActivityService(channel);
    await svc.end(); // no handler yet → MissingPluginException swallowed
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      seen.add(call);
      return true;
    });
    await svc.startRest(RestActivity(
        workoutName: 'Upper', exerciseName: 'Chest Press', nextTarget: 'Set 2', startsAt: DateTime.fromMillisecondsSinceEpoch(1000), endsAt: DateTime.fromMillisecondsSinceEpoch(91000)));
    await svc.end();
    expect(seen.map((c) => c.method), ['start', 'end']);
    expect((seen.first.arguments as Map)['endMillis'], 91000.0);
    expect((seen.first.arguments as Map)['exerciseName'], 'Chest Press');
  });
}
