import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications for the rest timer. Scheduled with the OS, so they fire with the phone locked.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const int restTimerId = 1001;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Timezone setup failed, using UTC: $e');
    }
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final granted = await ios?.requestPermissions(alert: true, sound: true, badge: false);
    return granted ?? false;
  }

  Future<void> scheduleRestDone(DateTime at, {String body = 'Rest is over. Next set!'}) async {
    await init();
    await _plugin.cancel(id: restTimerId);
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: restTimerId,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBanner: true,
          interruptionLevel: InterruptionLevel.active,
        ),
        android: AndroidNotificationDetails('rest_timer', 'Rest timer', importance: Importance.high, priority: Priority.high),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Rest done',
      body: body,
    );
  }

  Future<void> cancelRest() async {
    await init();
    await _plugin.cancel(id: restTimerId);
  }
}
