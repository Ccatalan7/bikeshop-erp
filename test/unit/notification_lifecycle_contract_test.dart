import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the stable workspace shell owns ERP notification transport', () {
    final shell = File('lib/main.dart').readAsStringSync();
    final routedLayout =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();

    expect(shell, contains("table: 'erp_notifications'"));
    expect(shell, contains('ErpNotificationGate.shared.rememberBaseline'));
    expect(shell, contains('_notificationLifecycleEpoch'));
    expect(shell, contains('_authStateSubscription?.cancel()'));
    expect(shell, contains('_erpNotificationsRefreshTimer?.cancel()'));
    expect(shell, contains('_erpNotificationsChannel?.unsubscribe()'));
    expect(shell, contains('_notificationLifecycleEpoch++'));
    expect(shell, contains('MailAccountManager.instance.reset()'));
    expect(shell, contains('ErpNotificationGate.shared.clearScope()'));

    expect(routedLayout, isNot(contains("table: 'erp_notifications'")));
    expect(routedLayout, isNot(contains('Timer.periodic')));
    expect(routedLayout, isNot(contains('RealtimeChannel')));
    expect(routedLayout, isNot(contains('_showTopNotification')));
  });

  test('mail reset preserves the shared stream and invalidates stale work', () {
    final manager = File(
      'lib/modules/mail/providers/mail_account_manager.dart',
    ).readAsStringSync();

    expect(manager, contains('_lifecycleEpoch++'));
    expect(manager, contains('_isSessionScopeReady = false'));
    expect(manager, contains('MailSessionTransition.run('));
    expect(manager, contains('_invalidateCacheForSession(nextUserId)'));
    expect(manager, contains('_cache.isAvailableForSessionIsolation'));
    expect(manager, contains('_refreshDebounceTimer?.cancel()'));
    expect(manager, contains('channel.unsubscribe().timeout('));
    expect(manager, contains('_isCurrentLifecycle(epoch, expectedUserId)'));
    expect(manager, isNot(contains('_sessionUserId = nextUserId;')));
    expect(manager, isNot(contains('_newEmailController.close()')));
    expect(manager, isNot(contains('_instance = null')));
  });

  test('notification loads use generation read-back before publishing', () {
    final service = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();

    expect(service, contains('_notificationScopeGeneration++'));
    expect(service, contains('generation != _notificationScopeGeneration'));
    expect(service, contains('_initializingFuture'));
    expect(service, contains('_desktopMessagesAuthUserId'));
  });

  test('online-order routes preserve exact durable read semantics', () {
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    final ordersPage = File(
      'lib/modules/website/pages/online_orders_page.dart',
    ).readAsStringSync();
    final layout =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();

    expect(router, contains("state.uri.queryParameters['order']"));
    expect(router, contains('initialOrderId: initialOrderId'));
    expect(ordersPage, contains('this.initialOrderId'));
    expect(ordersPage, contains('didUpdateWidget'));
    expect(ordersPage, contains('markOnlineOrderAlertReadForOrder'));
    expect(ordersPage, contains('_openInitialOrderWhenAvailable'));
    expect(layout, contains('_resolveWebsiteMenuRoute'));
  });
}
