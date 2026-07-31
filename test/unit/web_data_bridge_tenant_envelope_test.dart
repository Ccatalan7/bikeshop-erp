import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/web_data_bridge.dart';

const _tenantA = '72000000-0000-4000-8000-000000000001';
const _tenantB = '72000000-0000-4000-8000-000000000002';

void main() {
  group('preloaded public-store tenant envelope', () {
    test('returns only a payload owned by the expected tenant', () {
      final payload = <String, dynamic>{
        'tenant_id': _tenantA,
        'settings': <String, dynamic>{'store_name': 'Tienda A'},
        'blocks': <dynamic>[],
      };

      final result = validatePreloadedStoreEnvelope(
        <String, dynamic>{
          'tenant_id': _tenantA,
          'payload': payload,
        },
        expectedTenantId: _tenantA,
      );

      expect(result, payload);
      expect(result, isNot(same(payload)));
      expect(result, isNot(contains('payload')));
    });

    test('rejects an envelope owned by another tenant', () {
      expect(
        validatePreloadedStoreEnvelope(
          <String, dynamic>{
            'tenant_id': _tenantA,
            'payload': <String, dynamic>{'tenant_id': _tenantA},
          },
          expectedTenantId: _tenantB,
        ),
        isNull,
      );
    });

    test('rejects disagreement between envelope and payload ownership', () {
      expect(
        validatePreloadedStoreEnvelope(
          <String, dynamic>{
            'tenant_id': _tenantA,
            'payload': <String, dynamic>{'tenant_id': _tenantB},
          },
          expectedTenantId: _tenantA,
        ),
        isNull,
      );
    });

    test('rejects malformed and unowned payloads', () {
      final invalidEnvelopes = <Object?>[
        null,
        <dynamic>[],
        <String, dynamic>{},
        <String, dynamic>{
          'tenant_id': _tenantA,
          'payload': <dynamic>[],
        },
        <String, dynamic>{
          'tenant_id': _tenantA,
          'payload': <String, dynamic>{'settings': <String, dynamic>{}},
        },
      ];

      for (final envelope in invalidEnvelopes) {
        expect(
          validatePreloadedStoreEnvelope(
            envelope,
            expectedTenantId: _tenantA,
          ),
          isNull,
          reason: 'Malformed preload data must fail closed: $envelope',
        );
      }
    });

    test('the non-web bridge exposes the required tenant API and returns null',
        () async {
      expect(
        await WebDataBridge.getPreloadedStoreData(
          expectedTenantId: _tenantA,
        ),
        isNull,
      );
    });
  });

  test('generated and source HTML expose only a verified tenant envelope', () {
    final generatedIndex = File('web/index.html').readAsStringSync();
    final generator = File('scripts/sync_seo_index.sh').readAsStringSync();

    for (final source in [generatedIndex, generator]) {
      expect(source, contains("responseData.tenant_id !== tenantId"));
      expect(source, contains('tenant_id: responseData.tenant_id'));
      expect(source, contains('payload: responseData'));
      expect(source, isNot(contains('return await res.json();')));
    }
  });

  test('the edge cache rejects mismatched origin and cached identities', () {
    final worker = File('cloudflare-worker/src/index.js').readAsStringSync();

    expect(
      worker,
      contains('isTenantOwnedStoreData(cachedData, tenantId)'),
    );
    expect(worker, contains('await cache.delete(cacheKey)'));
    expect(worker, contains('isTenantOwnedStoreData(data, tenantId)'));
    expect(worker, contains("status: 502"));
    expect(worker, contains("'X-Tenant-ID': tenantId"));
  });
}
