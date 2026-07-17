import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/browser_supplier_portal_catalog.dart';
import 'package:vinabike_erp/shared/utils/browser_omnibox.dart';

void main() {
  test('active supplier domains are shared even without portal credentials',
      () {
    final entries = buildBrowserSupplierPortalCatalog([
      _supplier(
        id: 'commercial-cycle',
        name: 'Comercial Ciclo',
        website: 'comercialciclo.cl',
      ),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.supplierName, 'Comercial Ciclo');
    expect(entries.single.host, 'comercialciclo.cl');
    expect(entries.single.url, 'https://comercialciclo.cl');
  });

  test('fresh machines can inline-complete a centrally configured supplier',
      () {
    final entries = buildBrowserSupplierPortalCatalog([
      _supplier(
        id: 'commercial-cycle',
        name: 'Comercial Ciclo',
        website: 'https://www.comercialciclo.cl/',
      ),
    ]);

    final completion = browserInlineHostCompletion(
      query: 'com',
      rankedHosts: entries.map((entry) => entry.host),
    );

    expect(completion?.value, 'comercialciclo.cl');
    expect(completion?.selectionStart, 3);
  });

  test('catalog preserves a portal path but drops URL secrets', () {
    final entries = buildBrowserSupplierPortalCatalog([
      _supplier(
        id: 'supplier-a',
        name: 'Supplier A',
        website:
            'https://buyer:secret@portal.example/login?token=private#account',
      ),
    ]);

    expect(entries.single.url, 'https://portal.example/login');
    expect(entries.single.url, isNot(contains('secret')));
    expect(entries.single.url, isNot(contains('token')));
  });

  test('inactive and invalid supplier sites are not suggested', () {
    final entries = buildBrowserSupplierPortalCatalog([
      _supplier(
        id: 'inactive',
        name: 'Inactive',
        website: 'inactive.example',
        isActive: false,
      ),
      _supplier(
        id: 'invalid',
        name: 'Invalid',
        website: 'file:///tmp/login.html',
      ),
      _supplier(
        id: 'missing',
        name: 'Missing',
        website: '',
      ),
    ]);

    expect(entries, isEmpty);
  });

  test('www aliases deduplicate and HTTPS is preferred', () {
    final entries = buildBrowserSupplierPortalCatalog([
      _supplier(
        id: 'http-copy',
        name: 'HTTP copy',
        website: 'http://portal.example',
      ),
      _supplier(
        id: 'secure-copy',
        name: 'Secure copy',
        website: 'https://www.portal.example/login',
      ),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.supplierId, 'secure-copy');
    expect(entries.single.url, 'https://www.portal.example/login');
  });
}

Supplier _supplier({
  required String id,
  required String name,
  required String website,
  bool isActive = true,
}) {
  final timestamp = DateTime.utc(2026, 7, 17);
  return Supplier(
    id: id,
    tenantId: 'tenant-a',
    name: name,
    website: website,
    isActive: isActive,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
