import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

/// The gate every shared source the assistant reads must pass.
///
/// The session boundary already refuses jobs a page published for another
/// tenant. These are the other six: customers, suppliers, workshop jobs (cache
/// fallback included), sales invoices, purchase invoices and inventory. They
/// come out of caches keyed by their own lifecycle, so a stale one can outlive
/// a tenant switch, and all six funnel through this one object.
void main() {
  // An unresolved authority is not constructable: the scope is non-nullable,
  // so there is no "turn without an authority" case to test — there is no way
  // to build one.
  final authority = AIAssistantTurnAuthority(
    ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: 'tenant-a')!,
  );

  Map<String, dynamic> row(String? tenantId) =>
      <String, dynamic>{'tenant_id': tenantId};

  String? tenantOf(Map<String, dynamic> r) => r['tenant_id'] as String?;

  group('row verification', () {
    test('passes rows that all belong to the authority', () {
      final verified = authority.verifyRows(
        'clientes',
        [row('tenant-a'), row('tenant-a')],
        tenantOf,
      );
      expect(verified, hasLength(2));
    });

    test('one foreign row invalidates the whole source', () {
      // Never a silent filter: dropping the foreign row and answering with the
      // rest would let another taller's cache decide what this one is told.
      expect(
        () => authority.verifyRows(
            'clientes', [row('tenant-a'), row('tenant-b')], tenantOf),
        throwsA(isA<AIAssistantSourceUnavailable>()),
      );
    });

    test('a row without a tenant invalidates the whole source', () {
      expect(
        () => authority.verifyRows('facturas de venta', [row(null)], tenantOf),
        throwsA(isA<AIAssistantSourceUnavailable>()),
      );
      expect(
        () => authority.verifyRows('facturas de venta', [row('  ')], tenantOf),
        throwsA(isA<AIAssistantSourceUnavailable>()),
      );
    });

    test('an empty source is not an error', () {
      // "Zero rows" and "cannot be verified" must stay distinguishable: the
      // first is an answer, the second is a refusal to answer.
      expect(
        authority.verifyRows(
            'taller', const <Map<String, dynamic>>[], tenantOf),
        isEmpty,
      );
    });

    test('the failure names the source it came from', () {
      for (final source in const [
        'clientes',
        'proveedores',
        'taller',
        'facturas de venta',
        'facturas de compra',
        'inventario',
      ]) {
        try {
          authority.verifyRows(source, [row('tenant-b')], tenantOf);
          fail('$source did not fail closed');
        } on AIAssistantSourceUnavailable catch (e) {
          expect(e.source, source);
        }
      }
    });
  });

  group('service scope', () {
    final sameScope =
        ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: 'tenant-a');
    final otherTenant =
        ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: 'tenant-b');
    final otherUser =
        ErpAuthorityScopeKey.from(userId: 'user-b', tenantId: 'tenant-a');

    test('accepts a service bound to exactly this authority', () {
      expect(
        () => authority.requireServiceScope('taller', sameScope),
        returnsNormally,
      );
    });

    test('rejects another tenant, another user, and no scope at all', () {
      for (final scope in [otherTenant, otherUser, null]) {
        expect(
          () => authority.requireServiceScope('taller', scope),
          throwsA(isA<AIAssistantSourceUnavailable>()),
          reason: 'accepted $scope',
        );
      }
    });
  });
}
