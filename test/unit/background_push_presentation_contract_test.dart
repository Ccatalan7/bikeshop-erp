import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background FCM handler leaves presentation to the native payload', () {
    final source = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();
    final handler = source.substring(
      source.indexOf('Future<void> _firebaseMessagingBackgroundHandler'),
      source.indexOf('enum NotificationCategory'),
    );

    expect(handler, isNot(contains('handleIncomingMessage(message)')));
    expect(handler, contains('native FCM presentation'));
  });

  test('push payload retains one native mobile presentation owner', () {
    final source = File(
      'supabase/functions/push-notification/index.ts',
    ).readAsStringSync();

    expect(source, contains('android: {'));
    expect(source, contains('notification: {'));
    expect(source, contains('alert: { title: senderName, body }'));
  });
}
