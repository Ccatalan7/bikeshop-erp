import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/timezone.dart';

import 'details.dart';

export 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
export 'package:timezone/timezone.dart';

/// A stub Windows implementation that does nothing.
/// Used to avoid ATL build dependency issues.
class FlutterLocalNotificationsWindows
    extends FlutterLocalNotificationsPlatform {
  /// Registers this class as the default instance of [FlutterLocalNotificationsPlatform].
  static void registerWith() {
    FlutterLocalNotificationsPlatform.instance =
        FlutterLocalNotificationsWindows();
  }

  /// Initializes the plugin (stub - always returns true).
  Future<bool> initialize(
    WindowsInitializationSettings settings, {
    DidReceiveNotificationResponseCallback? onNotificationReceived,
  }) async {
    return true;
  }

  /// Releases any resources (stub - does nothing).
  void dispose() {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> show(int id, String? title, String? body,
      {String? payload, WindowsNotificationDetails? details}) async {}

  @override
  Future<List<PendingNotificationRequest>>
      pendingNotificationRequests() async => <PendingNotificationRequest>[];

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async =>
      <ActiveNotification>[];

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async => null;

  @override
  Future<void> periodicallyShow(int id, String? title, String? body,
      RepeatInterval repeatInterval) async {}

  @override
  Future<void> periodicallyShowWithDuration(int id, String? title, String? body,
      Duration repeatDurationInterval) async {}

  /// Schedules a notification (stub - does nothing).
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    TZDateTime scheduledDate,
    WindowsNotificationDetails? details, {
    String? payload,
  }) async {}

  /// Shows raw XML notification (stub - does nothing).
  Future<void> showRawXml({
    required int id,
    required String xml,
    Map<String, String> bindings = const <String, String>{},
  }) async {}

  /// Schedules XML notification (stub - does nothing).
  Future<void> zonedScheduleRawXml(
    int id,
    String xml,
    TZDateTime scheduledDate,
    WindowsNotificationDetails? details,
  ) async {}

  /// Updates bindings (stub - returns success).
  Future<NotificationUpdateResult> updateBindings({
    required int id,
    required Map<String, String> bindings,
  }) async =>
      NotificationUpdateResult.success;

  /// Validates XML (stub - returns false).
  bool isValidXml(String xml) => false;
}
