import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';

void main() {
  group('CurrentUserProfile.canManageUsers', () {
    test('matches the canonical owner, admin, and manager authority roles', () {
      for (final role in const ['owner', 'admin', 'manager']) {
        expect(
          _profile(role: role).canManageUsers,
          isTrue,
          reason: '$role must reach the canonical user-management surface',
        );
      }
    });

    test('allows an explicitly delegated permission without widening roles', () {
      expect(
        _profile(
          role: 'employee',
          permissions: const {'manage_users': true},
        ).canManageUsers,
        isTrue,
      );
      expect(_profile(role: 'employee').canManageUsers, isFalse);
    });
  });
}

CurrentUserProfile _profile({
  required String role,
  Map<String, bool> permissions = const {},
}) {
  return CurrentUserProfile(
    userId: 'user-1',
    email: 'user@example.com',
    emailVerified: true,
    displayName: 'Usuario',
    tenantId: 'tenant-1',
    tenantName: 'Taller',
    tenantSubdomain: 'taller',
    role: role,
    permissions: permissions,
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}
