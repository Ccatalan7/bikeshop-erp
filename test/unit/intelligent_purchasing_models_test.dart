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
      lines: [
        line.withProduct(
          name: 'Kenda Kwick',
          media: const ProductMedia(imageUrlOptimized: 'https://cdn/opt.webp'),
        ),
      ],
      supplierGroups: [group],
    );

    expect(plan.version, 3);
    expect(plan.lines.single.productName, 'Kenda Kwick');
    // La ficha del producto viaja con la línea: el plan muestra la foto sin
    // volver a consultar `products` por cada fila.
    expect(plan.lines.single.media.primaryUrl, 'https://cdn/opt.webp');
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

  group('Fase B1/B2 — carril familia y candidatos externos', () {
    test('la resolución de stock trae versión y revisión, no supply_needs', () {
      final resolution = SupplyStockResolution.fromJson({
        'needId': 'need-1',
        'needVersion': 7,
        'revisionNo': 3,
        'quantity': 2,
        'unit': 'unit',
        'lane': 'family',
        'status': 'ok',
        'coverage': 'full',
        'blocksExternal': true,
        'internalStockRejectionReason': null,
        'items': [
          {
            'productId': 'p-1',
            'name': 'Cadena X10',
            'atp': 5,
            'coverage': 'full',
            'matchState': 'strong',
            'blocksExternal': true,
          },
          {
            'productId': 'p-2',
            'name': 'Cadena genérica',
            'atp': 0,
            'coverage': 'none',
            'matchState': 'unverified',
            'blocksExternal': false,
          },
        ],
        'counts': {'eligible': 2, 'full': 1, 'unverified': 1},
        'page': {
          'limit': 12,
          'offset': 0,
          'total': 2,
          'returned': 2,
          'hasMore': false,
        },
      });

      // Los dos números que los comandos de esta fase exigen, y que
      // `SupplyNeed` no puede tener porque su tabla no guarda la revisión.
      expect(resolution.needVersion, 7);
      expect(resolution.revisionNo, 3);
      expect(resolution.isFamilyLane, isTrue);
      expect(resolution.items.first.matchState, 'strong');
      expect(resolution.items.last.isUnverified, isTrue);
      // Bloquea y nadie lo rechazó: el paso externo está cerrado.
      expect(resolution.externalAllowed, isFalse);
    });

    test('un rechazo registrado abre el paso externo', () {
      final resolution = SupplyStockResolution.fromJson({
        'needId': 'need-1',
        'needVersion': 8,
        'revisionNo': 3,
        'lane': 'family',
        'status': 'ok',
        'blocksExternal': true,
        'internalStockRejectionReason': 'Reservado para otro trabajo',
        'items': const [],
        'counts': const {},
      });

      expect(resolution.externalAllowed, isTrue);
    });

    test('un motivo en blanco no cuenta como rechazo', () {
      final resolution = SupplyStockResolution.fromJson({
        'needId': 'need-1',
        'needVersion': 8,
        'revisionNo': 3,
        'status': 'ok',
        'blocksExternal': true,
        'internalStockRejectionReason': '   ',
        'items': const [],
        'counts': const {},
      });

      expect(resolution.externalAllowed, isFalse);
    });

    test('una señal desconocida no vale cero y dice su causa', () {
      final signal = SupplySignalEvaluation.fromJson({
        'status': 'unknown',
        'reason': 'currency_mismatch_no_fx',
        'score': null,
      });

      expect(signal.score, isNull);
      expect(signal.isKnown, isFalse);
      expect(signal.isUnknown, isTrue);
      expect(supplySignalVerdict(signal), 'No verificable');
      expect(
        supplySignalReasonLabel(signal.reason),
        'Están en monedas distintas y el sistema no convierte.',
      );
    });

    test('un fallo conocido sí vale cero, y se distingue del desconocido', () {
      final missed = SupplySignalEvaluation.fromJson({
        'status': 'missed',
        'reason': 'cost_above_ceiling',
        'score': 0,
      });

      expect(missed.score, 0);
      expect(missed.isKnown, isTrue);
      expect(missed.isUnknown, isFalse);
      expect(supplySignalVerdict(missed), 'No cumple');
    });

    test('el flete incompleto es desconocido, no un costo comparable', () {
      final signal = SupplySignalEvaluation.fromJson({
        'status': 'unknown',
        'reason': 'incomplete_landed_cost',
        'score': null,
      });

      expect(signal.isUnknown, isTrue);
      expect(
        supplySignalReasonLabel(signal.reason),
        contains('no es comparable'),
      );
    });

    test('sólo se muestran las señales que el operador pidió', () {
      final match = SupplyRequestMatch.fromJson({
        'state': 'strong',
        'group': 'actionable',
        'knownSignalCount': 1,
        'knownSignalAverage': 1,
        'blendApplied': true,
        'signals': {
          'preferredBrandId': {
            'status': 'met',
            'reason': 'brand_identity_match',
            'score': 1,
          },
          'maxLandedUnitCostNet': {
            'status': 'not_requested',
            'reason': 'not_requested',
            'score': null,
          },
          'gama': {
            'status': 'delegated',
            'reason': 'scored_by_kernel',
            'score': null,
          },
        },
      });

      final keys = match.requestedSignals.map((entry) => entry.key).toList();
      expect(keys, containsAll(<String>['preferredBrandId', 'gama']));
      expect(keys, isNot(contains('maxLandedUnitCostNet')));
      // La gama viaja rotulada y sin puntaje: ya pesa dentro del ranking.
      expect(match.signals['gama']!.isDelegated, isTrue);
      expect(match.signals['gama']!.score, isNull);
    });

    test('el candidato externo conserva el puesto del kernel', () {
      final candidate = SupplyExternalCandidate.fromJson({
        'candidateId': 'cand-1',
        'rank': 1,
        'baseRank': 4,
        'baseRankingScore': 0.784864,
        'overallRank': 1,
        'rankingScore': 0.838648,
        'group': 'actionable',
        'matchState': 'strong',
        'productId': 'p-1',
        'productName': 'Cadena HG54',
        'supplierName': 'Andes',
        'supplierAvailability': 'unverified',
        'evidenceQuality': 'complete',
        'purchaseCount': 4,
        'evidenceAgeDays': 30,
        'currency': 'USD',
        'catalogSalePriceCurrency': 'CLP',
        'requestMatch': {
          'state': 'strong',
          'group': 'actionable',
          'knownSignalCount': 1,
          'blendApplied': true,
          'signals': {
            'preferredBrandId': {
              'status': 'met',
              'reason': 'brand_identity_match',
              'score': 1,
            },
          },
        },
      });

      // Sin baseRank nadie puede ver cuánto movió el objetivo comercial.
      expect(candidate.baseRank, 4);
      expect(candidate.overallRank, 1);
      expect(candidate.movedByTarget, isTrue);
      expect(candidate.isUnverified, isFalse);
      // Las dos monedas viajan: el margen queda auditable en el cliente.
      expect(candidate.currency, 'USD');
      expect(candidate.catalogSalePriceCurrency, 'CLP');
    });

    test('los dos grupos y sus dos páginas no se mezclan', () {
      final result = SupplyExternalCandidates.fromJson({
        'needId': 'need-1',
        'needVersion': 4,
        'revisionNo': 2,
        'needSupplyState': 'open',
        'status': 'success',
        'lane': 'family',
        'rankingProfile': 'profitability',
        'rankingProfileSource': 'revision',
        'items': [
          {
            'candidateId': 'a',
            'rank': 1,
            'group': 'actionable',
            'matchState': 'strong',
            'productId': 'p-a',
            'productName': 'A',
            'supplierName': 'S',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'complete',
            'purchaseCount': 1,
            'evidenceAgeDays': 1,
          },
        ],
        'unverifiedItems': [
          {
            'candidateId': 'b',
            'rank': 1,
            'group': 'unverified',
            'matchState': 'unverified',
            'productId': 'p-b',
            'productName': 'B',
            'supplierName': 'S',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'weak',
            'purchaseCount': 1,
            'evidenceAgeDays': 1,
          },
        ],
        'counts': {'actionable': 1, 'unverified': 1, 'candidates': 2},
        'page': {
          'limit': 1,
          'offset': 0,
          'total': 3,
          'returned': 1,
          'hasMore': true,
          'nextOffset': 1,
        },
        'unverifiedPage': {
          'limit': 5,
          'offset': 0,
          'total': 1,
          'returned': 1,
          'hasMore': false,
        },
        'targetRevisionNo': 0,
        'target': const <String, dynamic>{},
        'targetCurrencyCode': 'CLP',
        'tenantCurrencyCode': 'CLP',
      });

      expect(result.items.single.candidateId, 'a');
      expect(result.unverifiedItems.single.isUnverified, isTrue);
      // La vista compatible sólo lleva el grupo accionable: los no
      // verificados tienen su propio bloque rotulado.
      expect(result.asRanking.items.length, 1);
      // Paginación honesta: el total es del conjunto, no de la página.
      expect(result.page.total, 3);
      expect(result.page.hasMore, isTrue);
      expect(result.page.nextOffset, 1);
      expect(result.unverifiedPage.hasMore, isFalse);
      expect(result.unverifiedPage.nextOffset, isNull);
    });

    test('cada estado vacío dice su causa y su acción, y no se colapsan', () {
      Map<String, dynamic> envelope(String status, [Map<String, dynamic>? more]) =>
          <String, dynamic>{
            'needId': 'n',
            'status': status,
            'items': const [],
            'unverifiedItems': const [],
            'counts': const {},
            'page': const {},
            'unverifiedPage': const {},
            'target': const <String, dynamic>{},
            ...?more,
          };

      final titles = <String>{};
      for (final status in <String>[
        'supply_closed',
        'identity_unresolved',
        'needs_refinement',
        'technical_conflict',
        'analysis_too_broad',
        'no_eligible_products',
        'no_historical_candidates',
      ]) {
        final copy = supplyExternalStatusCopy(
          SupplyExternalCandidates.fromJson(envelope(status)),
        );
        titles.add(copy.title);
      }
      // Siete causas distintas, siete títulos distintos: colapsarlos en «sin
      // resultados» borraría la acción siguiente, que es distinta en cada uno.
      expect(titles.length, 7);

      final broad = supplyExternalStatusCopy(
        SupplyExternalCandidates.fromJson(envelope('analysis_too_broad', {
          'candidateUniverseSize': 900,
          'candidateSafeLimit': 600,
        })),
      );
      expect(broad.body, contains('900'));
      expect(broad.body, contains('600'));

      final refine = supplyExternalStatusCopy(
        SupplyExternalCandidates.fromJson(envelope('needs_refinement', {
          'universeSize': 700,
          'safeLimit': 400,
          'availableFields': ['chain_speeds'],
        })),
      );
      expect(refine.body, contains('chain_speeds'));

      // Un conjunto sin historial no es lo mismo que uno sin productos.
      expect(
        supplyExternalStatusCopy(
          SupplyExternalCandidates.fromJson(envelope('no_historical_candidates')),
        ).actionLabel,
        'Registrar una compra local',
      );
      expect(
        supplyExternalStatusCopy(
          SupplyExternalCandidates.fromJson(envelope('supply_closed')),
        ).actionLabel,
        isNull,
      );
    });

    test('el objetivo se denomina en la moneda de su revisión', () {
      final target = SupplyCommercialTarget.fromJson({
        'needId': 'need-1',
        'needVersion': 3,
        'needSupplyState': 'open',
        'currencyCode': 'CLP',
        'tenantCurrencyCode': 'USD',
        'targetRevisionNo': 2,
        'target': {'maxLandedUnitCostNet': 12000, 'gama': 'media'},
        'preferredBrandAvailable': null,
        'legacyPreferenceNote': {'text': 'algo barato', 'drivesRanking': false},
      });

      expect(target.hasTarget, isTrue);
      // El taller cambió de moneda: el tope guardado no se reinterpreta solo.
      expect(target.currencyRebased, isTrue);
      expect(target.target.maxLandedUnitCostNet, 12000);
      expect(target.legacyPreferenceNote, 'algo barato');
    });

    test('sin revisión de objetivo no hay objetivo, aunque haya nota', () {
      final target = SupplyCommercialTarget.fromJson({
        'needId': 'need-1',
        'needVersion': 1,
        'needSupplyState': 'open',
        'currencyCode': 'CLP',
        'tenantCurrencyCode': 'CLP',
        'targetRevisionNo': 0,
        'target': const <String, dynamic>{},
        'legacyPreferenceNote': {'text': 'gama alta', 'drivesRanking': false},
      });

      expect(target.hasTarget, isFalse);
      expect(target.target.isEmpty, isTrue);
      expect(target.legacyPreferenceNote, 'gama alta');
    });

    test('el servidor distingue paso pendiente de lectura vencida', () {
      // `stock_first_required` es un estado del flujo con su acción, no una
      // caída: tratarlo como error genérico dejaba al operador con «reintenta»
      // delante de un paso que nadie había dado.
      expect(
        supplyCommandFailure(
          'need-1',
          code: 'P0001',
          message: 'stock_first_required',
        ),
        isA<SupplyStockFirstRequired>(),
      );
      // Un choque de concurrencia se recupera releyendo.
      expect(
        supplyCommandFailure('need-1', code: '40001', message: 'serialization'),
        isA<SupplyConcurrencyConflict>(),
      );
      // Otro P0001 no es éste: no se le inventa significado.
      expect(
        supplyCommandFailure('need-1', code: 'P0001', message: 'otra cosa'),
        isNull,
      );
      // Y cualquier otro código sube tal cual.
      expect(
        supplyCommandFailure('need-1', code: '23514', message: 'check'),
        isNull,
      );
      expect(
        supplyCommandFailure('need-1', code: null, message: 'sin código'),
        isNull,
      );
    });
  });
}
