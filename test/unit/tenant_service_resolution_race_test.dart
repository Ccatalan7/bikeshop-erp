import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/services/tenant_service.dart';

void main() {
  test(
    'a user B lookup never reuses or accepts user A pending work',
    () async {
      var currentUserId = 'user-a';
      final lookups = <String, Completer<List<Map<String, dynamic>>>>{};
      final service = TenantService.testing(
        currentUserId: () => currentUserId,
        profileLookup: (userId) {
          final lookup = Completer<List<Map<String, dynamic>>>();
          lookups[userId] = lookup;
          return lookup.future;
        },
      );
      addTearDown(service.dispose);

      final userAResult = service.getTenantId();
      currentUserId = 'user-b';
      final userBResult = service.getTenantId();

      expect(lookups.keys, containsAll(<String>['user-a', 'user-b']));

      lookups['user-b']!.complete([
        _profile(tenantId: 'tenant-b', role: 'manager'),
      ]);
      expect(await userBResult, 'tenant-b');
      expect(service.currentTenantId, 'tenant-b');
      expect(service.currentUserRole, 'manager');

      lookups['user-a']!.complete([
        _profile(tenantId: 'tenant-a', role: 'cashier'),
      ]);
      expect(await userAResult, isNull);
      expect(service.currentTenantId, 'tenant-b');
      expect(service.currentUserRole, 'manager');
    },
  );

  test(
    'clearCache invalidates a slow lookup even for the same user id',
    () async {
      const currentUserId = 'user-a';
      final lookups = <Completer<List<Map<String, dynamic>>>>[];
      final service = TenantService.testing(
        currentUserId: () => currentUserId,
        profileLookup: (_) {
          final lookup = Completer<List<Map<String, dynamic>>>();
          lookups.add(lookup);
          return lookup.future;
        },
      );
      addTearDown(service.dispose);

      final staleResult = service.getTenantId();
      service.clearCache();
      final currentResult = service.getTenantId();

      expect(lookups, hasLength(2));
      lookups[1].complete([
        _profile(tenantId: 'tenant-current', role: 'manager'),
      ]);
      expect(await currentResult, 'tenant-current');

      lookups[0].complete([
        _profile(tenantId: 'tenant-stale', role: 'cashier'),
      ]);
      expect(await staleResult, isNull);
      expect(service.currentTenantId, 'tenant-current');
      expect(service.currentUserRole, 'manager');
    },
  );
}

Map<String, dynamic> _profile({
  required String tenantId,
  required String role,
}) {
  return {
    'tenant_id': tenantId,
    'role': role,
    'permissions': const <String, dynamic>{'view_dashboard': true},
  };
}
