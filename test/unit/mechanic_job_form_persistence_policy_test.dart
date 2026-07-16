import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_form_persistence_policy.dart';

void main() {
  group('linked-invoice commercial snapshot protection', () {
    MechanicJob warrantyJob() => MechanicJob(
          id: 'warranty-1',
          tenantId: 'tenant-1',
          customerId: 'customer-1',
          jobType: JobType.warranty,
          workflowKind: JobWorkflowKind.warranty,
          invoiceId: 'invoice-warranty-1',
        );

    test('locks paid and part-paid warranties', () {
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: warrantyJob(),
          linkedInvoiceHasActivePayments: true,
          linkedInvoicePaymentStateUnknown: false,
        ),
        isTrue,
      );
    });

    test('fails closed when linked payment state cannot be confirmed', () {
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: warrantyJob(),
          linkedInvoiceHasActivePayments: false,
          linkedInvoicePaymentStateUnknown: true,
        ),
        isTrue,
      );
    });

    test('also protects an inconsistent legacy warranty facade', () {
      final legacyWarranty = MechanicJob(
        id: 'legacy-warranty-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobType: JobType.warranty,
        workflowKind: JobWorkflowKind.service,
        invoiceId: 'invoice-legacy-warranty-1',
      );

      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: legacyWarranty,
          linkedInvoiceHasActivePayments: true,
          linkedInvoicePaymentStateUnknown: false,
        ),
        isTrue,
      );
    });

    test('locks a paid normal service with a linked invoice', () {
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: MechanicJob(
            id: 'service-1',
            tenantId: 'tenant-1',
            customerId: 'customer-1',
            invoiceId: 'invoice-service-1',
          ),
          linkedInvoiceHasActivePayments: true,
          linkedInvoicePaymentStateUnknown: false,
        ),
        isTrue,
      );
    });

    test('fails closed for an unreadable linked service invoice', () {
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: MechanicJob(
            id: 'service-unknown',
            tenantId: 'tenant-1',
            customerId: 'customer-1',
            invoiceId: 'invoice-service-unknown',
          ),
          linkedInvoiceHasActivePayments: false,
          linkedInvoicePaymentStateUnknown: true,
        ),
        isTrue,
      );
    });

    test('does not lock an unpaid invoice or a job without a linked invoice',
        () {
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: warrantyJob(),
          linkedInvoiceHasActivePayments: false,
          linkedInvoicePaymentStateUnknown: false,
        ),
        isFalse,
      );
      expect(
        shouldProtectJobCommercialSnapshot(
          existingJob: MechanicJob(
            id: 'service-without-invoice',
            tenantId: 'tenant-1',
            customerId: 'customer-1',
          ),
          linkedInvoiceHasActivePayments: true,
          linkedInvoicePaymentStateUnknown: false,
        ),
        isFalse,
      );
    });

    test('protected update omits trigger and commercial keys, not diagnosis',
        () {
      final result = mechanicJobPaymentProtectedUpdatePayload({
        'status': 'delivered',
        'status_id': 'status-delivered',
        'started_at': '2026-07-16T10:00:00Z',
        'completed_at': '2026-07-16T11:00:00Z',
        'delivered_at': '2026-07-16T12:00:00Z',
        'customer_id': 'customer-2',
        'bike_id': 'bike-2',
        'discount_amount': 9000,
        'invoice_id': 'invoice-1',
        'diagnosis': 'Rodamiento con juego',
        'notes': 'Cliente avisado',
        'priority': 'high',
      });

      expect(result, isNot(contains('status')));
      expect(result, isNot(contains('status_id')));
      expect(result, isNot(contains('started_at')));
      expect(result, isNot(contains('completed_at')));
      expect(result, isNot(contains('delivered_at')));
      expect(result, isNot(contains('customer_id')));
      expect(result, isNot(contains('bike_id')));
      expect(result, isNot(contains('discount_amount')));
      expect(result, isNot(contains('invoice_id')));
      expect(result['diagnosis'], 'Rodamiento con juego');
      expect(result['notes'], 'Cliente avisado');
      expect(result['priority'], 'high');
    });
  });

  group('creation mode draft preservation', () {
    test('requires confirmation only when the target replaces bicycle context',
        () {
      expect(
        mechanicJobModeSwitchRemovesBikeContext(
          from: JobType.service,
          to: JobType.quotation,
          hasPhysicalBikeTabs: true,
        ),
        isTrue,
      );
      expect(
        mechanicJobModeSwitchRemovesBikeContext(
          from: JobType.service,
          to: JobType.itemService,
          hasPhysicalBikeTabs: true,
        ),
        isTrue,
      );
      expect(
        mechanicJobModeSwitchRemovesBikeContext(
          from: JobType.service,
          to: JobType.warranty,
          hasPhysicalBikeTabs: true,
        ),
        isTrue,
      );
      expect(
        mechanicJobModeSwitchRemovesBikeContext(
          from: JobType.quotation,
          to: JobType.service,
          hasPhysicalBikeTabs: false,
        ),
        isFalse,
      );
    });

    test('moves stable lines without duplication or replacing instances', () {
      final first = Object();
      final duplicate = Object();
      final second = Object();
      final ids = <Object, String>{
        first: 'line-1',
        duplicate: 'line-1',
        second: 'line-2',
      };

      final result = preserveMechanicJobModeLines<Object>(
        collections: [
          [first],
          [duplicate, second],
        ],
        stableIdOf: (item) => ids[item]!,
      );

      expect(result, hasLength(2));
      expect(result[0], same(first));
      expect(result[1], same(second));
    });

    test('converted quote narrative fills only an empty bicycle field', () {
      expect(
        mechanicJobConvertedBikeNarrativeValue(
          bikeValue: '',
          jobValue: 'Diagnóstico cotizado por WhatsApp',
        ),
        'Diagnóstico cotizado por WhatsApp',
      );
      expect(
        mechanicJobConvertedBikeNarrativeValue(
          bikeValue: 'Diagnóstico específico al recibir la bicicleta',
          jobValue: 'Diagnóstico anterior del presupuesto',
        ),
        'Diagnóstico específico al recibir la bicicleta',
      );
    });

    test('first service bike inherits standalone narrative without overwrite',
        () {
      expect(
        mechanicJobFirstBikeNarrativeValue(
          bikeValue: '',
          standaloneValue: 'Diagnóstico ingresado como componente',
        ),
        'Diagnóstico ingresado como componente',
      );
      expect(
        mechanicJobFirstBikeNarrativeValue(
          bikeValue: 'Diagnóstico específico de la bicicleta',
          standaloneValue: 'Texto standalone anterior',
        ),
        'Diagnóstico específico de la bicicleta',
      );
    });

    test('warranty source change asks only when scoped draft would be lost',
        () {
      expect(
        mechanicJobWarrantySourceChangeNeedsConfirmation(
          currentSourceJobId: 'source-a',
          nextSourceJobId: 'source-b',
          hasSourceScopedDraft: true,
        ),
        isTrue,
      );
      expect(
        mechanicJobWarrantySourceChangeNeedsConfirmation(
          currentSourceJobId: 'source-a',
          nextSourceJobId: 'source-a',
          hasSourceScopedDraft: true,
        ),
        isFalse,
      );
      expect(
        mechanicJobWarrantySourceChangeNeedsConfirmation(
          currentSourceJobId: 'source-a',
          nextSourceJobId: 'source-b',
          hasSourceScopedDraft: false,
        ),
        isFalse,
      );
    });
  });

  group('standalone job item hydration', () {
    final persistedItem = MechanicJobItem(
      id: '11111111-1111-4111-8111-111111111111',
      tenantId: 'tenant-1',
      jobId: 'job-1',
      productId: 'product-1',
      serviceProductId: 'service-1',
      productName: 'Enrayado de rueda',
      productSku: 'SERV-RUEDA',
      quantity: 2,
      unitPrice: 15000,
      totalPrice: 30000,
      itemType: 'service',
      location: BikeMemoryLocation.rear,
      notes: 'Cruce por tres',
      serviceConfigurationData: const {
        'spokePattern': 'three_cross',
        'tensionTarget': 120,
      },
    );

    test('retains the exact persisted row when there are no bicycle tabs', () {
      final result = mechanicJobStandaloneItemsForForm(
        persistedItems: [persistedItem],
        hasPhysicalBikeTabs: false,
      );

      expect(result, hasLength(1));
      expect(result.single, same(persistedItem));
      expect(result.single.id, '11111111-1111-4111-8111-111111111111');
      expect(result.single.productId, 'product-1');
      expect(result.single.serviceProductId, 'service-1');
      expect(result.single.location, BikeMemoryLocation.rear);
      expect(result.single.serviceConfigurationData, {
        'spokePattern': 'three_cross',
        'tensionTarget': 120,
      });
    });

    test('does not duplicate rows already owned by bicycle tabs', () {
      final result = mechanicJobStandaloneItemsForForm(
        persistedItems: [persistedItem],
        hasPhysicalBikeTabs: true,
      );

      expect(result, isEmpty);
    });
  });

  group('warranty save checkpoint', () {
    test('a recovered row without an explicit claim still requires a source',
        () {
      final checkpoint = MechanicJobWarrantySaveCheckpoint()
        ..hydrate(claim: null, persistedOutcome: WarrantyOutcome.pending);

      expect(checkpoint.hasExplicitPersistedClaim, isFalse);
      expect(checkpoint.requiresSourceSelection, isTrue);
    });

    test('an explicit legacy claim may remain without inventing a source', () {
      const claim = MechanicJobWarrantyClaim(
        warrantyJobId: 'warranty-1',
        outcome: WarrantyOutcome.pending,
      );
      final checkpoint = MechanicJobWarrantySaveCheckpoint()
        ..hydrate(claim: claim, persistedOutcome: WarrantyOutcome.pending);

      expect(checkpoint.hasExplicitPersistedClaim, isTrue);
      expect(checkpoint.requiresSourceSelection, isFalse);
    });

    test('confirmed commands survive a later unrelated save failure', () {
      final checkpoint = MechanicJobWarrantySaveCheckpoint()
        ..hydrate(claim: null, persistedOutcome: WarrantyOutcome.pending);

      expect(checkpoint.needsRegistration('source-1'), isTrue);
      checkpoint.confirmRegistration('source-1');
      checkpoint.confirmDecision(WarrantyOutcome.covered);

      // Simulate retrying Save without rehydrating stale database projections.
      expect(checkpoint.needsRegistration('source-1'), isFalse);
      expect(checkpoint.needsDecision(WarrantyOutcome.covered), isFalse);
      expect(checkpoint.registeredSourceJobId, 'source-1');
      expect(checkpoint.confirmedOutcome, WarrantyOutcome.covered);

      checkpoint.reset();
      expect(checkpoint.requiresSourceSelection, isTrue);
      expect(checkpoint.confirmedOutcome, isNull);
    });

    test('new registration resets an untraced legacy outcome to pending', () {
      final checkpoint = MechanicJobWarrantySaveCheckpoint()
        ..hydrate(claim: null, persistedOutcome: WarrantyOutcome.covered);

      checkpoint.confirmRegistration('source-legacy');

      expect(checkpoint.hasExplicitPersistedClaim, isTrue);
      expect(checkpoint.confirmedOutcome, WarrantyOutcome.pending);
      expect(checkpoint.needsDecision(WarrantyOutcome.covered), isTrue);
    });
  });
}
