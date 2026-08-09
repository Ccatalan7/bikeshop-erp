import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/pages/supplier_form_page.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';

void main() {
  test('lost acknowledgement reuses the operation id until success', () {
    var sequence = 0;
    final ledger = SupplierCommandRetryLedger(
      newOperationId: () => 'operation-${++sequence}',
    );

    final firstAttempt = ledger.retain('same-request');
    final retryAfterLostAck = ledger.retain('same-request');
    final changedDraft = ledger.retain('changed-request');
    ledger.complete('same-request', 'not-the-owner');
    final retryAfterUnrelatedCompletion = ledger.retain('same-request');
    ledger.complete('same-request', firstAttempt);
    final nextIntent = ledger.retain('same-request');

    expect(firstAttempt, 'operation-1');
    expect(retryAfterLostAck, firstAttempt);
    expect(changedDraft, 'operation-2');
    expect(retryAfterUnrelatedCompletion, firstAttempt);
    expect(nextIntent, 'operation-3');
  });

  test('ambiguous credential command retries the exact same operation',
      () async {
    const operationId = 'operation-stays-stable';
    final seenOperationIds = <String>[];

    final result = await replayAmbiguousSupplierCredentialCommand(() async {
      seenOperationIds.add(operationId);
      if (seenOperationIds.length == 1) {
        throw StateError('lost acknowledgement');
      }
      return 'receipt';
    });

    expect(result, 'receipt');
    expect(seenOperationIds, [operationId, operationId]);
  });

  test('two ambiguous credential failures never claim a negative result',
      () async {
    var attempts = 0;

    await expectLater(
      replayAmbiguousSupplierCredentialCommand<void>(() async {
        attempts++;
        throw StateError('transport unavailable');
      }),
      throwsA(isA<SupplierCredentialCommandOutcomeUnknown>()),
    );

    expect(attempts, 2);
  });

  test('supplier quick-create delegates to the canonical profile command', () {
    final source = File(
      'lib/modules/purchases/services/purchase_service.dart',
    ).readAsStringSync();

    expect(source, contains('_supplierRelationshipService.saveProfile('));
    expect(source, contains('SaveSupplierRelationshipProfileCommand('));
    expect(source, contains('_supplierCreateRetries.retain(retryKey)'));
    expect(source, contains('operationId: operationId'));
    expect(source, contains('defaultTaxTreatment: TaxTreatment.noTax'));
    expect(source, isNot(contains("_db.insert(\n        'suppliers'")));
    expect(source, isNot(contains("_db.update(\n          'suppliers'")));
    expect(source, isNot(contains("_db.delete('suppliers'")));
    expect(source, isNot(contains('Future<void> deleteSupplier(')));
    expect(source,
        isNot(contains('Future<shared_supplier.Supplier> saveSupplier(')));
  });

  test('OCR template uses its narrow optimistic command', () {
    final purchaseService = File(
      'lib/modules/purchases/services/purchase_service.dart',
    ).readAsStringSync();
    final ocrSurface = File(
      'lib/shared/widgets/ocr_upload_widget.dart',
    ).readAsStringSync();

    expect(
      purchaseService,
      contains('_supplierRelationshipService.updateOcrTemplate('),
    );
    expect(
      purchaseService,
      contains('_supplierOcrRetries.retain(retryKey)'),
    );
    expect(purchaseService, contains('expectedUpdatedAt: supplier.updatedAt'));
    expect(ocrSurface, contains('updateSupplierOcrTemplate('));
    expect(ocrSurface, isNot(contains('saveSupplier(')));
  });

  test('application shares one relationship command owner with purchases', () {
    final main = File('lib/main.dart').readAsStringSync();

    final relationshipProvider = main.indexOf(
      'create: (context) => SupplierRelationshipService(',
    );
    final purchaseProvider = main.indexOf(
      'create: (context) => PurchaseService(',
    );
    expect(relationshipProvider, greaterThanOrEqualTo(0));
    expect(purchaseProvider, greaterThan(relationshipProvider));
    expect(
      main,
      contains(
        'supplierRelationshipService:\n'
        '                      context.read<SupplierRelationshipService>()',
      ),
    );
  });

  test('product import delegates missing suppliers to canonical quick-create',
      () {
    final service = File(
      'lib/modules/inventory/services/product_import_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/modules/inventory/pages/product_import_page.dart',
    ).readAsStringSync();

    expect(service, contains('_createMissingSupplier(supplierName.trim())'));
    expect(service, isNot(contains("_db.insert(\n      'suppliers'")));
    expect(page, contains('purchaseService.createSupplier(name)'));
  });
}
