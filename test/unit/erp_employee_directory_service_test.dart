import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/erp_employee_directory_service.dart';

void main() {
  test('parses and caches the exact projection per Auth-user/tenant scope',
      () async {
    final gateway = _FakeDirectoryGateway(
      currentUserId: 'user-a',
      handler: () async => [_directoryRow()],
    );
    final service = ErpEmployeeDirectoryService.forTesting(gateway: gateway);

    final first = await service.getEntries(authorityTenantId: 'tenant-a');
    final second = await service.getEntries(authorityTenantId: 'tenant-a');

    expect(gateway.calls, 1);
    expect(second, same(first));
    expect(first.single.employeeId, 'employee-a');
    expect(first.single.userId, 'staff-a');
    expect(first.single.fullName, 'Ada Lovelace');
    expect(first.single.initials, 'AL');
    expect(first.single.jobTitle, 'Administradora');
    expect(first.single.status, 'active');
  });

  test('clears cache and discards a late response after tenant scope change',
      () async {
    final firstResponse = Completer<Object?>();
    final secondResponse = Completer<Object?>();
    var request = 0;
    final gateway = _FakeDirectoryGateway(
      currentUserId: 'user-a',
      handler: () =>
          request++ == 0 ? firstResponse.future : secondResponse.future,
    );
    final service = ErpEmployeeDirectoryService.forTesting(gateway: gateway);

    final staleLoad = service.getEntries(authorityTenantId: 'tenant-a');
    final currentLoad = service.getEntries(authorityTenantId: 'tenant-b');
    secondResponse.complete([
      _directoryRow(
        employeeId: 'employee-b',
        userId: 'staff-b',
        firstName: 'Grace',
        lastName: 'Hopper',
      ),
    ]);
    expect((await currentLoad).single.employeeId, 'employee-b');

    firstResponse.complete([_directoryRow()]);
    await expectLater(staleLoad, throwsStateError);
    expect(
      (await service.getEntries(authorityTenantId: 'tenant-b'))
          .single
          .employeeId,
      'employee-b',
    );
    expect(gateway.calls, 2);
  });

  test('fails closed for malformed or ambiguous directory evidence', () async {
    final gateway = _FakeDirectoryGateway(
      currentUserId: 'user-a',
      handler: () async => [
        _directoryRow(),
        _directoryRow(employeeId: 'employee-b'),
      ],
    );
    final service = ErpEmployeeDirectoryService.forTesting(gateway: gateway);

    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );

    gateway.handler = () async => [
          {
            ..._directoryRow(),
            'rut': '12.345.678-5',
          },
        ];
    await expectLater(
      service.getEntries(
        authorityTenantId: 'tenant-a',
        forceRefresh: true,
      ),
      throwsFormatException,
    );
  });

  test('a failed forced refresh cannot republish the previous cache', () async {
    final gateway = _FakeDirectoryGateway(
      currentUserId: 'user-a',
      handler: () async => [_directoryRow()],
    );
    final service = ErpEmployeeDirectoryService.forTesting(gateway: gateway);
    await service.getEntries(authorityTenantId: 'tenant-a');

    gateway.handler = () async => throw StateError('offline');
    await expectLater(
      service.getEntries(
        authorityTenantId: 'tenant-a',
        forceRefresh: true,
      ),
      throwsStateError,
    );
    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsStateError,
    );
    expect(gateway.calls, 3);
  });

  test('a clock rollback invalidates the cache and refetches', () async {
    var now = DateTime.utc(2026, 7, 28, 12);
    final gateway = _FakeDirectoryGateway(
      currentUserId: 'user-a',
      handler: () async => [_directoryRow()],
    );
    final service = ErpEmployeeDirectoryService.forTesting(
      gateway: gateway,
      now: () => now,
    );
    await service.getEntries(authorityTenantId: 'tenant-a');

    now = now.subtract(const Duration(seconds: 1));
    gateway.handler = () async => [
          _directoryRow(
            employeeId: 'employee-b',
            userId: 'staff-b',
            firstName: 'Grace',
            lastName: 'Hopper',
          ),
        ];

    final refreshed = await service.getEntries(authorityTenantId: 'tenant-a');

    expect(gateway.calls, 2);
    expect(refreshed.single.employeeId, 'employee-b');
  });

  test('requires an active Auth identity before invoking the RPC', () async {
    final gateway = _FakeDirectoryGateway(
      currentUserId: null,
      handler: () async => [_directoryRow()],
    );
    final service = ErpEmployeeDirectoryService.forTesting(gateway: gateway);

    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsStateError,
    );
    expect(gateway.calls, 0);
  });
}

Map<String, dynamic> _directoryRow({
  String employeeId = 'employee-a',
  String? userId = 'staff-a',
  String firstName = 'Ada',
  String lastName = 'Lovelace',
}) {
  return {
    'employee_id': employeeId,
    'user_id': userId,
    'first_name': firstName,
    'last_name': lastName,
    'job_title': 'Administradora',
    'system_role': 'manager',
    'status': 'active',
    'photo_url': null,
    'department_id': 'department-a',
  };
}

class _FakeDirectoryGateway implements ErpEmployeeDirectoryGateway {
  _FakeDirectoryGateway({
    required this.currentUserId,
    required this.handler,
  });

  @override
  String? currentUserId;

  Future<Object?> Function() handler;
  int calls = 0;

  @override
  Future<Object?> getDirectory() {
    calls++;
    return handler();
  }
}
