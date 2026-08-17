import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';

void main() {
  test('job status carries the semantic supply-capture capability', () {
    final status = JobStatusCustom.fromJson({
      'id': 'status-parts',
      'tenant_id': 'tenant-a',
      'name': 'REPUESTOS',
      'code': 'ESPERANDO_REPUESTOS',
      'phase': 'in_progress',
      'prompts_supply_need_capture': true,
      'created_at': '2026-08-16T12:00:00Z',
      'updated_at': '2026-08-16T12:00:00Z',
    });

    expect(status.promptsSupplyNeedCapture, isTrue);
    expect(status.toJson()['prompts_supply_need_capture'], isTrue);
    expect(
      status.copyWith(promptsSupplyNeedCapture: false).promptsSupplyNeedCapture,
      isFalse,
    );
  });

  test('old status rows default safely without name heuristics', () {
    final status = JobStatusCustom.fromJson({
      'tenant_id': 'tenant-a',
      'name': 'REPUESTOS',
      'code': 'ESPERANDO_REPUESTOS',
    });

    expect(status.promptsSupplyNeedCapture, isFalse);
  });

  test('job attention is derived independently from the editable status name',
      () {
    final attention = JobSupplyAttention.fromJson({
      'mechanic_job_id': 'job-a',
      'prompts_supply_need_capture': true,
      'active_need_count': 0,
      'unresolved_identity_count': 0,
      'requires_supply_capture': true,
    });

    expect(attention.jobId, 'job-a');
    expect(attention.promptsSupplyNeedCapture, isTrue);
    expect(attention.requiresCapture, isTrue);
    expect(attention.activeNeedCount, 0);
  });

  test('supply need keeps identity, workflow and optimistic version separate',
      () {
    final need = SupplyNeed.fromJson({
      'id': 'need-a',
      'origin_kind': 'mechanic_job',
      'mechanic_job_id': 'job-a',
      'job_bike_id': null,
      'original_description': 'motor sellado BSA 73 x 125',
      'product_id': 'product-a',
      'quantity': '2.000',
      'unit': 'unit',
      'identity_state': 'confirmed',
      'supply_state': 'open',
      'version': 4,
      'created_at': '2026-08-16T12:00:00Z',
    });

    expect(need.hasConfirmedProduct, isTrue);
    expect(need.quantity, 2);
    expect(need.version, 4);
    expect(need.mechanicJobId, 'job-a');
    expect(need.jobBikeId, isNull);
  });

  test('inventory snapshot exposes common ATP rather than physical stock only',
      () {
    final snapshot = SupplyInventorySnapshot.fromJson({
      'need_id': 'need-a',
      'need_version': 4,
      'source_product_id': 'product-a',
      'requested_quantity': 2,
      'available_to_promise': 1,
      'assignable': false,
      'components': [
        {
          'product_id': 'product-a',
          'name': 'Motor sellado',
          'required_quantity': 2,
          'on_hand': 4,
          'online_committed': 2,
          'workshop_committed': 1,
          'atp': 1,
        },
      ],
    });

    expect(snapshot.assignable, isFalse);
    expect(snapshot.availableToPromise, 1);
    expect(snapshot.components.single.onHand, 4);
    expect(snapshot.components.single.availableToPromise, 1);
  });

  test('purchase candidate preserves explainable economic evidence', () {
    final ranking = PurchaseRanking.fromJson({
      'status': 'success',
      'hasMore': false,
      'supplierAvailabilitySemantics': 'historical_only_unverified',
      'items': [
        {
          'candidateId': 'candidate-a',
          'rank': 1,
          'productId': 'product-a',
          'productName': 'Piñón Shimano',
          'supplierId': 'supplier-a',
          'supplierName': 'Andes Industrial',
          'supplierAvailability': 'unverified',
          'latestLandedUnitCostNet': 10100,
          'catalogSalePriceGross': 22000,
          'projectedGrossMarginRatio': 0.541,
          'purchaseCount': 12,
          'evidenceAgeDays': 18,
          'evidenceQuality': 'complete',
          'freightEvidence': 'complete',
        },
      ],
    });

    final candidate = ranking.items.single;
    expect(candidate.latestLandedUnitCostNet, 10100);
    expect(candidate.projectedGrossMarginRatio, closeTo(0.541, 0.0001));
    expect(candidate.purchaseCount, 12);
    expect(candidate.supplierId, 'supplier-a');
    expect(candidate.supplierAvailability, 'unverified');
    expect(ranking.supplierAvailabilitySemantics, 'historical_only_unverified');
  });

  test('basket scenario keeps internal, external and uncovered lines explicit',
      () {
    final result = PurchaseScenarioResult.fromJson({
      'status': 'partial',
      'profile': 'balanced',
      'inputCount': 3,
      'internalLineCount': 1,
      'externalLineCount': 2,
      'boundedSupplierCount': 2,
      'hasMore': false,
      'supplierAvailabilitySemantics': 'historical_only_unverified',
      'scenarios': [
        {
          'scenarioKey': 'recommended:a',
          'kind': 'recommended',
          'label': 'Mejor equilibrio',
          'coverageLineCount': 2,
          'externalCoverageLineCount': 1,
          'totalLineCount': 3,
          'externalLineCount': 2,
          'complete': false,
          'supplierCount': 1,
          'historicalSubtotals': [
            {'currency': 'CLP', 'historicalLandedSubtotalNet': 10100},
          ],
          'supplierAvailability': 'historical_only_unverified',
          'freightAssumption':
              'sum_historical_landed_line_costs_no_consolidation_saving',
          'lines': [
            {
              'lineRef': 'need-stock',
              'productId': 'product-stock',
              'productName': 'Cadena disponible',
              'requestedQuantity': 1,
              'availableToPromise': 2,
              'sourcing': 'internal',
              'covered': true,
            },
            {
              'lineRef': 'need-buy',
              'productId': 'product-buy',
              'productName': 'Piñón Shimano',
              'requestedQuantity': 1,
              'availableToPromise': 0,
              'sourcing': 'external',
              'covered': true,
              'candidateId': 'candidate-a',
              'supplierName': 'Andes Industrial',
              'currency': 'CLP',
              'latestLandedUnitCostNet': 10100,
              'projectedGrossMarginRatio': 0.541,
              'purchaseCount': 12,
              'evidenceAgeDays': 18,
              'evidenceQuality': 'complete',
            },
            {
              'lineRef': 'need-missing',
              'productId': 'product-missing',
              'productName': 'Producto nuevo',
              'requestedQuantity': 1,
              'availableToPromise': 0,
              'sourcing': 'uncovered',
              'covered': false,
            },
          ],
          'explanationCodes': [
            'stock_first',
            'partial_external_coverage',
          ],
        },
      ],
    });

    final scenario = result.scenarios.single;
    expect(result.status, 'partial');
    expect(scenario.complete, isFalse);
    expect(scenario.lines.map((line) => line.sourcing),
        <String>['internal', 'external', 'uncovered']);
    expect(scenario.externalCandidates, hasLength(1));
    expect(
      scenario.externalCandidates.single.toCandidate(rank: 1).supplierName,
      'Andes Industrial',
    );
    expect(scenario.historicalSubtotals.single.amount, 10100);
  });

  test('purchase draft keeps line economics and supplier groups separate', () {
    final line = PurchasePlanLine.fromJson({
      'id': 'line-a',
      'source_need_id': 'need-a',
      'candidate_id': 'candidate-a',
      'product_id': 'product-a',
      'supplier_name': 'Andes Industrial',
      'quantity': 2,
      'unit': 'unit',
      'currency_code': 'CLP',
      'landed_unit_cost_net': 10100,
      'projected_gross_margin_ratio': 0.541,
      'supplier_availability': 'unverified',
    });
    final group = PurchasePlanSupplierGroup.fromJson({
      'supplier_id': 'supplier-a',
      'supplier_name': 'Andes Industrial',
      'currency_code': 'CLP',
      'line_count': 1,
      'total_units': 2,
      'historical_landed_subtotal_net': 20200,
      'supplier_availability': 'unverified',
      'freight_assumption':
          'sum_frozen_line_landed_costs_no_consolidation_saving',
    });
    final plan = PurchasePlanDraft.fromParts(
      plan: {
        'id': 'plan-a',
        'title': 'Plan de compra',
        'state': 'draft',
        'objective_profile': 'balanced',
        'version': 3,
      },
      lines: [line.withProductName('Kenda Kwick')],
      supplierGroups: [group],
    );

    expect(plan.version, 3);
    expect(plan.lines.single.productName, 'Kenda Kwick');
    expect(plan.supplierGroups.single.historicalLandedSubtotalNet, 20200);
    expect(plan.supplierGroups.single.supplierAvailability, 'unverified');
  });

  group('contrato de imagen del producto', () {
    test('resuelve optimizada, cruda y galería en ese orden, sin duplicar', () {
      const media = ProductMedia(
        imageUrlOptimized: ' https://cdn/opt.webp ',
        imageUrl: 'https://cdn/raw.jpg',
        imageUrls: ['https://cdn/raw.jpg', '', 'https://cdn/extra.jpg'],
      );

      expect(media.primaryUrl, 'https://cdn/opt.webp');
      expect(media.resolutionChain, [
        'https://cdn/opt.webp',
        'https://cdn/raw.jpg',
        'https://cdn/extra.jpg',
      ]);
      expect(media.hasImage, isTrue);
    });

    test('una ficha sin imagen cae al monograma, no a una caja rota', () {
      const media = ProductMedia(imageUrlOptimized: '   ', imageUrls: ['']);

      expect(media.primaryUrl, isNull);
      expect(media.hasImage, isFalse);
      expect(media.resolutionChain, isEmpty);
      expect(productMonogram('Maxxis Minion DHF'), 'MM');
      expect(productMonogram('Kenda'), 'KE');
      expect(productMonogram('   '), '—');
    });

    test('el candidato transporta la terna de imagen del read model', () {
      final candidate = PurchaseCandidate.fromJson({
        'candidateId': 'c1',
        'productId': 'p1',
        'productName': 'Kenda Kwick 27,5 × 2,10',
        'supplierName': 'Andes Industrial',
        'imageUrlOptimized': 'https://cdn/kenda-opt.webp',
        'imageUrls': ['https://cdn/kenda-a.jpg'],
      });

      expect(candidate.media.primaryUrl, 'https://cdn/kenda-opt.webp');
      expect(candidate.media.resolutionChain.length, 2);
    });

    test('el componente de bodega también trae su identidad visual', () {
      final component = SupplyInventoryComponent.fromJson({
        'product_id': 'p1',
        'name': 'Cámara 27,5',
        'required_quantity': 10,
        'on_hand': 4,
        'online_committed': 1,
        'workshop_committed': 0,
        'atp': 3,
        'image_url': 'https://cdn/camara.jpg',
      });

      expect(component.media.primaryUrl, 'https://cdn/camara.jpg');
      // La bodega cubre 3 de 10: el resto es faltante externo explícito.
      expect(component.coverable, 3);
      expect(component.shortfall, 7);
    });

    test('sin existencias no se inventa cobertura', () {
      final component = SupplyInventoryComponent.fromJson({
        'product_id': 'p2',
        'name': 'Rayo 264 mm',
        'required_quantity': 32,
        'atp': 0,
      });

      expect(component.coverable, 0);
      expect(component.shortfall, 32);
      expect(component.media.hasImage, isFalse);
    });
  });
}
