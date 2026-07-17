import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/browser_supplier_credential_resolver.dart';

void main() {
  test('supplier website credentials resolve for the same HTTPS host', () {
    final credential = resolveSupplierCredentialForOrigin(
      suppliers: [
        _supplier(
          id: 'supplier-a',
          website: 'comercialciclo.cl/portal',
          username: 'buyer',
          password: 'secret',
        ),
      ],
      origin: 'https://www.comercialciclo.cl/Home',
    );

    expect(credential?.supplierId, 'supplier-a');
    expect(credential?.origin, 'https://www.comercialciclo.cl');
    expect(credential?.username, 'buyer');
    expect(credential?.password, 'secret');
  });

  test('resolver never leaks credentials to a sibling subdomain', () {
    final credential = resolveSupplierCredentialForOrigin(
      suppliers: [
        _supplier(
          id: 'supplier-a',
          website: 'portal.supplier.example',
          username: 'buyer',
          password: 'secret',
        ),
      ],
      origin: 'https://malicious.supplier.example',
    );

    expect(credential, isNull);
  });

  test('supplier credentials can fill a legacy HTTP page on the exact host',
      () {
    final credential = resolveSupplierCredentialForOrigin(
      suppliers: [
        _supplier(
          id: 'legacy-supplier',
          website: 'https://portal.supplier.example',
          username: 'buyer',
          password: 'secret',
        ),
      ],
      origin: 'http://portal.supplier.example/login',
    );

    expect(credential?.supplierId, 'legacy-supplier');
    expect(credential?.origin, 'http://portal.supplier.example');
  });

  test('resolver never sends a default-site credential to another port', () {
    final credential = resolveSupplierCredentialForOrigin(
      suppliers: [
        _supplier(
          id: 'supplier-a',
          website: 'supplier.example',
          username: 'buyer',
          password: 'secret',
        ),
      ],
      origin: 'https://supplier.example:8443',
    );

    expect(credential, isNull);
  });

  test('resolver refuses inactive, incomplete, or ambiguous suppliers', () {
    expect(
      resolveSupplierCredentialForOrigin(
        suppliers: [
          _supplier(
            id: 'inactive',
            website: 'supplier.example',
            username: 'buyer',
            password: 'secret',
            isActive: false,
          ),
        ],
        origin: 'https://supplier.example',
      ),
      isNull,
    );
    expect(
      resolveSupplierCredentialForOrigin(
        suppliers: [
          _supplier(
            id: 'missing-password',
            website: 'supplier.example',
            username: 'buyer',
            password: '',
          ),
        ],
        origin: 'https://supplier.example',
      ),
      isNull,
    );
    expect(
      resolveSupplierCredentialForOrigin(
        suppliers: [
          _supplier(
            id: 'one',
            website: 'supplier.example',
            username: 'buyer-one',
            password: 'secret-one',
          ),
          _supplier(
            id: 'two',
            website: 'www.supplier.example',
            username: 'buyer-two',
            password: 'secret-two',
          ),
        ],
        origin: 'https://supplier.example',
      ),
      isNull,
    );
  });
}

Supplier _supplier({
  required String id,
  required String website,
  required String username,
  required String password,
  bool isActive = true,
}) {
  final timestamp = DateTime.utc(2026, 7, 17);
  return Supplier(
    id: id,
    tenantId: 'tenant-a',
    name: id,
    website: website,
    portalUsername: username,
    portalPassword: password,
    isActive: isActive,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
