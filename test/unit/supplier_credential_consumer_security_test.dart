import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary supplier cache reads use the explicit secret-free projection',
      () {
    final supplierModel = File(
      'lib/shared/models/supplier.dart',
    ).readAsStringSync();
    final purchaseService = _normalizedSource(
      'lib/modules/purchases/services/purchase_service.dart',
    );

    expect(supplierModel, contains('static const String secretFreeSelect'));
    expect(supplierModel, isNot(contains('portal_username')));
    expect(supplierModel, isNot(contains('portal_password')));
    expect(supplierModel, isNot(contains('portalUsername')));
    expect(supplierModel, isNot(contains('portalPassword')));
    expect(
      purchaseService,
      contains(
        "_db.select( 'suppliers', selectColumns: "
        'shared_supplier.Supplier.secretFreeSelect',
      ),
    );
  });

  test('OCR supplier selection declares the same secret-free projection', () {
    final ocr = _normalizedSource(
      'lib/shared/widgets/ocr_upload_widget.dart',
    );

    expect(
      ocr,
      contains(
        "dbService.select( 'suppliers', selectColumns: "
        "shared_supplier.Supplier.secretFreeSelect, orderBy: 'id', "
        'fetchAll: true',
      ),
    );
    expect(ocr, contains('a.id.compareTo(b.id)'));
    expect(
      RegExp(r"\.select\(\s*'suppliers'\s*\)").hasMatch(ocr),
      isFalse,
    );
  });

  test('product import supplier lookups always declare a projection', () {
    final importer = _normalizedSource(
      'lib/modules/inventory/services/product_import_service.dart',
    );

    expect(
      RegExp(r"_db\.select\( 'suppliers', selectColumns:")
          .allMatches(importer)
          .length,
      3,
    );
    expect(
      RegExp(r"_db\.select\( 'suppliers', (?!selectColumns:)")
          .hasMatch(importer),
      isFalse,
    );
  });

  test(
      'WebView requests supplier secrets on demand and never enables HTTP fill',
      () {
    final browser = _normalizedSource(
      'lib/shared/widgets/webview_module_page.dart',
    );
    final resolver = _normalizedSource(
      'lib/shared/services/browser_supplier_credential_resolver.dart',
    );

    expect(browser, contains('SupplierCredentialService('));
    expect(browser, contains('resolveBrowserSupplierCredentialLookup('));
    expect(browser, contains('resolveSupplierCredentialReferenceForOrigin('));
    expect(browser, contains('service.revealPortalCredentialForOrigin('));
    expect(resolver, contains('SupplierCredentialKind.portalPassword'));
    expect(
      browser,
      contains('BrowserSupplierCredentialLookupStatus.unavailable'),
    );
    expect(browser, contains('supplierLookup.isMatched'));
    expect(browser, contains('_deleteLocalCredential(origin)'));
    expect(browser, contains('supplierNoMatchConfirmed: true'));
    expect(browser, contains('allowInsecureSupplierOrigin: false'));
    expect(browser, isNot(contains('filled-insecure')));
    expect(browser, isNot(contains(r'credential save skipped: $error')));
    expect(browser, isNot(contains(r'credential autofill skipped: $error')));
  });

  test('supplier writes use the command owner and safe read projections', () {
    final database = _normalizedSource(
      'lib/shared/services/database_service.dart',
    );
    final purchases = _normalizedSource(
      'lib/modules/purchases/services/purchase_service.dart',
    );
    final importer = _normalizedSource(
      'lib/modules/inventory/services/product_import_service.dart',
    );

    expect(database, contains('String? selectColumns'));
    expect(purchases, contains('_supplierRelationshipService.saveProfile('));
    expect(
      purchases,
      contains('_supplierRelationshipService.updateOcrTemplate('),
    );
    expect(importer, contains('_createMissingSupplier('));
    expect(importer, contains("selectColumns: 'id,name'"));
    expect(
      RegExp(r"_db\.(?:insert|update|delete)\( 'suppliers'")
          .hasMatch(purchases),
      isFalse,
    );
    expect(
      RegExp(r"_db\.(?:insert|update|delete)\( 'suppliers'").hasMatch(importer),
      isFalse,
    );
  });

  test('supplier editor is metadata-first and writes exact-origin credentials',
      () {
    final form = _normalizedSource(
      'lib/modules/purchases/pages/supplier_form_page.dart',
    );

    expect(form, contains('SupplierCredentialService('));
    expect(form, contains('_credentialService.getStatus('));
    expect(form, contains('_credentialService.upsert(input)'));
    expect(form, contains('_credentialService.delete('));
    expect(form, contains('canonicalSupplierCredentialOrigin('));
    expect(form, contains('credentialKey: draft.credentialKey'));
    expect(form, contains('originUrl: draft.origin'));
    expect(form, contains('expectedUpdatedAt: existing?.updatedAt'));
    expect(form, contains('operationId: draft.operationId'));
    expect(form, isNot(contains('_credentialService.get(')));
    expect(form, isNot(contains('SupplierCredentialRevealController')));
    expect(form, isNot(contains('_portalPasswordController')));
    expect(form, isNot(contains('_portalSecretRevealTimer')));
    expect(form, isNot(contains('PurchaseService')));
    expect(form, isNot(contains('saveSupplier(')));
    expect(form, isNot(contains('SupplierType')));
    expect(form, isNot(contains('supplier.portalUsername')));
    expect(form, isNot(contains('supplier.portalPassword')));
    expect(form, isNot(contains('portalUsername:')));
    expect(form, isNot(contains('portalPassword:')));
  });
}

String _normalizedSource(String path) {
  return File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
}
