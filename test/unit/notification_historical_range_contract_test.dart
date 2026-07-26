import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('historical notifications use a tenant-safe paginated half-open range',
      () {
    final service = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();
    final method = _between(
      service,
      'loadNotificationsForRange({',
      '/// Insert/refresh a single notification row',
    );

    expect(method, contains('final tenantId = _notificationScopeTenantId'));
    expect(method, contains('final generation = _notificationScopeGeneration'));
    expect(method, contains(".eq('tenant_id', tenantId)"));
    expect(method, contains(".gte('created_at', startUtc.toIso8601String())"));
    expect(method, contains(".lt('created_at', endUtc.toIso8601String())"));
    expect(method, contains('.range('));
    expect(method, contains('_historicalNotificationPageSize'));
    expect(method, contains('generation != _notificationScopeGeneration'));
    expect(method, isNot(contains('notificationsFeed.value =')));
  });

  test('historical files use a tenant-safe paginated half-open range', () {
    final service = File(
      'lib/modules/storage/services/app_file_storage_service.dart',
    ).readAsStringSync();
    final method = _between(
      service,
      'listFilesForRange({',
      'Future<AppStoredFile?> getFileById',
    );

    expect(method, contains('final tenantId = await _requireTenantId()'));
    expect(method, contains(".eq('tenant_id', tenantId)"));
    expect(method, contains(".isFilter('deleted_at', null)"));
    expect(method, contains(".gte('created_at', startUtc.toIso8601String())"));
    expect(method, contains(".lt('created_at', endUtc.toIso8601String())"));
    expect(method, contains('.range('));
    expect(method, contains('_historicalFilePageSize'));
  });

  test('historical read actions update the database and reconcile local rows',
      () {
    final service = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();
    final exactRead = _between(
      service,
      'Future<void> markNotificationRead(',
      'Future<void> markNotificationsReadForRange({',
    );
    final rangeRead = _between(
      service,
      'Future<void> markNotificationsReadForRange({',
      '/// Mark every unread notification as read',
    );

    expect(exactRead, contains('if (index != -1'));
    expect(exactRead, isNot(contains('if (index == -1) return')));
    expect(exactRead, contains(".eq('tenant_id', tenantId)"));
    expect(exactRead, contains(".eq('id', id)"));

    expect(rangeRead, contains(".eq('tenant_id', tenantId)"));
    expect(
      rangeRead,
      contains(".gte('created_at', startUtc.toIso8601String())"),
    );
    expect(
      rangeRead,
      contains(".lt('created_at', endUtc.toIso8601String())"),
    );
    expect(rangeRead, contains(".isFilter('read_at', null)"));
    expect(rangeRead, contains('createdAt.isBefore(startUtc)'));
    expect(rangeRead, contains('!createdAt.isBefore(endUtc)'));
    expect(rangeRead, contains('notificationsFeed.value = current'));
  });
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNot(-1), reason: 'Missing marker: $startMarker');
  expect(end, greaterThan(start), reason: 'Missing marker: $endMarker');
  return source.substring(start, end);
}
