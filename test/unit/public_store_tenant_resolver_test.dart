import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/utils/public_store_tenant_resolver.dart';

void main() {
  group('choosePublicStoreTenantId', () {
    test('prefers the detected storefront tenant', () {
      expect(
        choosePublicStoreTenantId(
          detectedTenantId: ' public-tenant ',
          authenticatedTenantId: 'erp-tenant',
          allowAuthenticatedFallback: true,
        ),
        'public-tenant',
      );
    });

    test('uses the authenticated tenant only when explicitly allowed', () {
      expect(
        choosePublicStoreTenantId(
          detectedTenantId: null,
          authenticatedTenantId: 'erp-tenant',
          allowAuthenticatedFallback: false,
        ),
        isNull,
      );
      expect(
        choosePublicStoreTenantId(
          detectedTenantId: null,
          authenticatedTenantId: ' erp-tenant ',
          allowAuthenticatedFallback: true,
        ),
        'erp-tenant',
      );
    });

    test('rejects blank tenant identifiers', () {
      expect(
        choosePublicStoreTenantId(
          detectedTenantId: ' ',
          authenticatedTenantId: '',
          allowAuthenticatedFallback: true,
        ),
        isNull,
      );
    });
  });

  group('allowsAuthenticatedStoreTenantFallback', () {
    test('accepts the route query before the editor provider synchronizes', () {
      expect(
        allowsAuthenticatedStoreTenantFallback(
          explicitlyAllowed: false,
          isEditorContext: false,
          previewQuery: 'true',
          editQuery: null,
        ),
        isTrue,
      );
    });

    test('rejects authenticated fallback in a plain public storefront', () {
      expect(
        allowsAuthenticatedStoreTenantFallback(
          explicitlyAllowed: false,
          isEditorContext: false,
          previewQuery: null,
          editQuery: null,
        ),
        isFalse,
      );
    });
  });

  group('chooseErpMountedStoreTenantId', () {
    test('authenticated ERP authority wins over a storefront scope', () {
      expect(
        chooseErpMountedStoreTenantId(
          authenticatedTenantId: ' erp-tenant ',
          focusedHostScopeTenantId: 'detected-tenant',
          hasAuthenticatedTenantOwner: true,
        ),
        'erp-tenant',
      );
    });

    test('fails closed when the authenticated owner has no tenant', () {
      expect(
        chooseErpMountedStoreTenantId(
          authenticatedTenantId: null,
          focusedHostScopeTenantId: 'detected-tenant',
          hasAuthenticatedTenantOwner: true,
        ),
        isNull,
      );
    });

    test('focused hosts may supply the provider scope without TenantService',
        () {
      expect(
        chooseErpMountedStoreTenantId(
          authenticatedTenantId: null,
          focusedHostScopeTenantId: ' focused-tenant ',
          hasAuthenticatedTenantOwner: false,
        ),
        'focused-tenant',
      );
    });
  });
}
