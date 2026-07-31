import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/erp_chat_principal_directory_service.dart';

void main() {
  test('parses the exact tenant-scoped principal projection', () async {
    final gateway = _FakeGateway(
      currentUserId: 'current-user',
      response: [
        _row(),
        _row(
          userId: 'owner-without-employee',
          employeeId: null,
          displayName: 'Propietario ERP',
          role: 'admin',
        ),
      ],
    );
    final service = ErpChatPrincipalDirectoryService(gateway: gateway);

    final entries = await service.getEntries(
      authorityTenantId: ' tenant-a ',
    );

    expect(gateway.calls, 1);
    expect(entries, hasLength(2));
    expect(entries.first.userId, 'staff-a');
    expect(entries.first.employeeId, 'employee-a');
    expect(entries.first.initials, 'AL');
    expect(entries.last.employeeId, isNull);
    expect(entries.last.role, 'admin');
  });

  test('requires both Auth identity and tenant authority before the RPC',
      () async {
    final gateway = _FakeGateway(
      currentUserId: null,
      response: [_row()],
    );
    final service = ErpChatPrincipalDirectoryService(gateway: gateway);

    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsStateError,
    );
    await expectLater(
      service.getEntries(authorityTenantId: ' '),
      throwsStateError,
    );
    expect(gateway.calls, 0);
  });

  test('fails closed for cross-tenant, duplicate, or widened rows', () async {
    final gateway = _FakeGateway(
      currentUserId: 'current-user',
      response: [_row(tenantId: 'tenant-b')],
    );
    final service = ErpChatPrincipalDirectoryService(gateway: gateway);

    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );

    gateway.response = [_row(), _row(employeeId: 'employee-b')];
    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );

    gateway.response = [
      {
        ..._row(),
        'email': 'not-part-of-the-contract@example.test',
      },
    ];
    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );
  });

  test('fails closed for unsupported roles and malformed optional values',
      () async {
    final gateway = _FakeGateway(
      currentUserId: 'current-user',
      response: [_row(role: 'customer')],
    );
    final service = ErpChatPrincipalDirectoryService(gateway: gateway);

    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );

    gateway.response = [
      {
        ..._row(),
        'photo_url': 42,
      },
    ];
    await expectLater(
      service.getEntries(authorityTenantId: 'tenant-a'),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _row({
  String tenantId = 'tenant-a',
  String userId = 'staff-a',
  String? employeeId = 'employee-a',
  String displayName = 'Ada Lovelace',
  String role = 'manager',
}) {
  return {
    'tenant_id': tenantId,
    'user_id': userId,
    'employee_id': employeeId,
    'display_name': displayName,
    'role': role,
    'photo_url': null,
  };
}

class _FakeGateway implements ErpChatPrincipalDirectoryGateway {
  _FakeGateway({
    required this.currentUserId,
    required this.response,
  });

  @override
  String? currentUserId;

  Object? response;
  int calls = 0;

  @override
  Future<Object?> getDirectory() async {
    calls++;
    return response;
  }
}
