import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';
import 'package:vinabike_erp/shared/services/supplier_variant_resolution_service.dart';

const _supplierId = '10000000-0000-4000-8000-000000000001';
const _revisionId = '10000000-0000-4000-8000-000000000002';
const _operationId = '10000000-0000-4000-8000-000000000003';
const _applicationId = '10000000-0000-4000-8000-000000000004';
const _productId = '20000000-0000-4000-8000-000000000001';
const _edgeId = '20000000-0000-4000-8000-000000000002';
const _componentId = '20000000-0000-4000-8000-000000000003';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  group('SupplierVariantResolutionService', () {
    test('resolve sends exact option preimage and validates requested evidence',
        () async {
      final harness = _Harness();
      final evidence = _evidence();
      harness.handler = (functionName, params) {
        expect(functionName, 'resolve_supplier_variant_resolution');
        expect(params, <String, dynamic>{
          'p_supplier_id': _supplierId,
          'p_item_id': 'listing-44',
          'p_product_url': '',
          'p_variant_key': 'sku:immutable-variant-77',
          'p_option_evidence_hash': evidence.sha256Hex,
          'p_option_pack_count': 2,
          'p_option_unit_class': 'piece',
          'p_pack_evidence_conflict': false,
        });
        return _resolved(evidence);
      };

      final resolution = await harness.service.resolve(
        supplierId: _supplierId,
        itemId: 'listing-44',
        productUrl: '',
        optionEvidence: evidence,
      );

      expect(resolution.isResolved, isTrue);
      expect(resolution.edges.single.productId, _productId);
    });

    test('conflicting pack evidence stays non-authoritative', () async {
      final harness = _Harness()
        ..handler = (functionName, params) {
          expect(params['p_pack_evidence_conflict'], isTrue);
          return <String, dynamic>{
            'status': 'pack_evidence_conflict',
            'authoritative': false,
            'edges': const <Object>[],
          };
        };
      final result = await harness.service.resolve(
        supplierId: _supplierId,
        itemId: 'listing-44',
        productUrl: '',
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:immutable-variant-77',
          packCount: 2,
          rawUnitToken: 'pcs',
          packEvidenceConflict: true,
        ),
      );

      expect(result.isResolved, isFalse);
      expect(
        result.status,
        SupplierVariantResolutionStatus.packEvidenceConflict,
      );
      expect(harness.calls, hasLength(1));
    });

    test('legacy candidate remains review only with no usable edges', () async {
      final harness = _Harness()
        ..handler = (functionName, params) => <String, dynamic>{
              'status': 'legacy_candidate',
              'authoritative': false,
              'requires_confirmation': true,
              'legacy_alias_id': 'legacy-alias-1',
              'listing_id': 'listing-44',
              'variant_key': 'sku:immutable-variant-77',
              'edges': <Map<String, dynamic>>[
                _edge(),
              ],
            };

      final resolution = await harness.service.resolve(
        supplierId: _supplierId,
        itemId: 'listing-44',
        productUrl: '',
        optionEvidence: _evidence(),
      );

      expect(resolution.requiresConfirmation, isTrue);
      expect(resolution.authoritative, isFalse);
      expect(resolution.edges, isEmpty);
    });

    test('remember validates graph and sends decision provenance', () async {
      final harness = _Harness();
      final evidence = _evidence();
      harness.handler = (functionName, params) {
        expect(functionName, 'remember_supplier_variant_resolution');
        expect(params['p_option_pack_count'], 2);
        expect(params['p_option_unit_class'], 'piece');
        expect(params['p_pack_evidence_conflict'], false);
        expect(params['p_decision_evidence'], _decisionEvidence());
        return <String, dynamic>{
          ..._resolved(evidence),
          'operation_id': _operationId,
          'decision_source': 'operator_confirmed',
          'decision_evidence_hash': _hashB,
          'decision_evidence': _decisionEvidence(),
          'replayed': false,
        }
          ..remove('status')
          ..remove('authoritative');
      };

      final resolution = await harness.service.remember(
        operationId: _operationId,
        supplierId: _supplierId,
        itemId: 'listing-44',
        productUrl: '',
        optionEvidence: evidence,
        action: SupplierVariantResolutionAction.activate,
        kind: SupplierVariantResolutionKind.single,
        edges: const <SupplierVariantResolutionEdge>[
          SupplierVariantResolutionEdge(
            position: 1,
            productId: _productId,
            catalogUnitsPerPurchase: 1,
            allocationRatio: 1,
            componentRole: 'single',
          ),
        ],
        decisionEvidence: _decisionEvidence(),
      );

      expect(resolution.isResolved, isTrue);
    });

    test('malformed remembered receipt is committed-unverified', () async {
      final harness = _Harness()
        ..handler = (functionName, params) => <String, dynamic>{
              'id': _revisionId,
              'state': 'active',
              'resolution_kind': 'single',
              'variant_key': 'sku:immutable-variant-77',
              'option_evidence_hash': _evidence().sha256Hex,
              'revision_number': 1,
              'operation_id': _operationId,
              'edges': const <Object>[],
            };

      expect(
        () => harness.service.remember(
          operationId: _operationId,
          supplierId: _supplierId,
          itemId: 'listing-44',
          productUrl: '',
          optionEvidence: _evidence(),
          action: SupplierVariantResolutionAction.activate,
          kind: SupplierVariantResolutionKind.single,
          edges: const <SupplierVariantResolutionEdge>[
            SupplierVariantResolutionEdge(
              position: 1,
              productId: _productId,
              catalogUnitsPerPurchase: 1,
              allocationRatio: 1,
              componentRole: 'single',
            ),
          ],
          decisionEvidence: _decisionEvidence(),
        ),
        throwsA(isA<SupplierResolutionCommittedUnverifiedException>()),
      );
    });

    test('remember rejects incomplete operator evidence before RPC', () async {
      final harness = _Harness();

      expect(
        () => harness.service.remember(
          operationId: _operationId,
          supplierId: _supplierId,
          itemId: 'listing-44',
          productUrl: '',
          optionEvidence: _evidence(),
          action: SupplierVariantResolutionAction.activate,
          kind: SupplierVariantResolutionKind.single,
          edges: const <SupplierVariantResolutionEdge>[
            SupplierVariantResolutionEdge(
              position: 1,
              productId: _productId,
              catalogUnitsPerPurchase: 1,
              allocationRatio: 1,
              componentRole: 'single',
            ),
          ],
          decisionEvidence: const <String, dynamic>{
            'confirmation_surface': 'purchase_invoice_ocr',
          },
        ),
        throwsArgumentError,
      );
      expect(harness.calls, isEmpty);
    });

    test('prepare sends the full source snapshot and validates exact totals',
        () async {
      final harness = _Harness();
      final evidence = _evidence();
      final resolution = SupplierVariantResolution.fromLookupJson(
        _resolved(evidence),
      );
      final lineKey = SupplierVariantResolutionService.buildSourceLineKey(
        supplierId: _supplierId,
        sourceDate: DateTime(2025, 10, 20),
        sourceOrderNumbers: const <String>['ORDER-2', 'ORDER-1'],
        listingId: 'listing-44',
        variantKey: evidence.variantKey,
      );
      harness.handler = (functionName, params) {
        expect(functionName, 'prepare_purchase_invoice_source_resolution');
        expect(
            params['p_source_order_numbers'], <String>['ORDER-1', 'ORDER-2']);
        expect(params['p_currency_code'], 'CLP');
        expect(params['p_raw_pack_count'], 2);
        expect(params['p_raw_unit_token'], 'pcs');
        expect(params['p_source_snapshot'], <String, dynamic>{
          'source': 'aliexpress_daily_invoice',
          'listing_id': 'listing-44',
          'variant_key': evidence.variantKey.value,
          'option_evidence_hash': evidence.sha256Hex,
          'source_row_index': 4,
          'source_line_key': lineKey,
          'source_document_date': '2025-10-20',
          'source_order_numbers': <String>['ORDER-1', 'ORDER-2'],
          'source_title': 'BUCKLOS Front-Rear brake set',
          'selected_option': 'Front Rear 2PCS',
          'raw_pack_count': 2,
          'raw_unit_code': 'pcs',
          'option_unit_class': 'piece',
          'pack_evidence_conflict': false,
          'source_purchase_quantity': 2.0,
          'source_line_total_minor': 10001,
          'currency_code': 'CLP',
        });
        return _prepared(evidence, lineKey);
      };

      final prepared = await harness.service.prepareInvoiceSource(
        operationId: _operationId,
        resolution: resolution,
        sourceLineKey: lineKey,
        sourceRowIndex: 4,
        sourceDocumentDate: DateTime(2025, 10, 20, 22, 45),
        sourcePurchaseQuantity: 2,
        sourceLineTotalMinor: 10001,
        currencyCode: 'CLP',
        sourceOrderNumbers: const <String>['ORDER-2', 'ORDER-1'],
        sourceTitle: 'BUCKLOS Front-Rear brake set',
        selectedOption: 'Front Rear 2PCS',
        optionEvidence: evidence,
        sourceSnapshot: const <String, dynamic>{
          'source': 'aliexpress_daily_invoice',
        },
      );

      expect(prepared.components.single.allocatedLineTotalMinor, 10001);
      expect(prepared.components.single.resolvedQuantity, 2);
    });

    test('prepare fails closed when committed component receipt drifts',
        () async {
      final harness = _Harness();
      final evidence = _evidence();
      final resolution = SupplierVariantResolution.fromLookupJson(
        _resolved(evidence),
      );
      const lineKey = 'supplier-line-v1:stable';
      harness.handler = (functionName, params) {
        final prepared = _prepared(evidence, lineKey);
        final components = List<Map<String, dynamic>>.from(
          prepared['components'] as List,
        );
        components[0] = <String, dynamic>{
          ...components.single,
          'revision_edge_id': _componentId,
        };
        return <String, dynamic>{
          ...prepared,
          'components': components,
        };
      };

      expect(
        () => harness.service.prepareInvoiceSource(
          operationId: _operationId,
          resolution: resolution,
          sourceLineKey: lineKey,
          sourceRowIndex: 4,
          sourceDocumentDate: DateTime(2025, 10, 20),
          sourcePurchaseQuantity: 2,
          sourceLineTotalMinor: 10001,
          currencyCode: 'CLP',
          sourceOrderNumbers: const <String>['ORDER-1', 'ORDER-2'],
          sourceTitle: 'BUCKLOS Front-Rear brake set',
          selectedOption: 'Front Rear 2PCS',
          optionEvidence: evidence,
          sourceSnapshot: const <String, dynamic>{
            'source': 'aliexpress_daily_invoice',
          },
        ),
        throwsA(
          isA<SupplierSourceResolutionCommittedUnverifiedException>(),
        ),
      );
    });

    test('prepare rejects non-CLP money before calling the RPC', () async {
      final harness = _Harness();
      final evidence = _evidence();
      final resolution = SupplierVariantResolution.fromLookupJson(
        _resolved(evidence),
      );

      expect(
        () => harness.service.prepareInvoiceSource(
          operationId: _operationId,
          resolution: resolution,
          sourceLineKey: 'supplier-line-v1:stable',
          sourceRowIndex: 0,
          sourceDocumentDate: DateTime(2025, 10, 20),
          sourcePurchaseQuantity: 1,
          sourceLineTotalMinor: 100,
          currencyCode: 'USD',
          sourceOrderNumbers: const <String>['ORDER-1'],
          sourceTitle: 'Supplier product',
          optionEvidence: evidence,
        ),
        throwsArgumentError,
      );
      expect(harness.calls, isEmpty);
    });

    test('source key ignores order input order and local display labels', () {
      final variant = SupplierImmutableVariantKey.parse(
        'sku:immutable-variant-77',
      );
      String build(List<String> orders) =>
          SupplierVariantResolutionService.buildSourceLineKey(
            supplierId: _supplierId,
            sourceDate: DateTime(2025, 10, 20, 22, 45),
            sourceOrderNumbers: orders,
            listingId: 'listing-44',
            variantKey: variant,
          );

      expect(build(<String>['ORDER-2', 'ORDER-1']),
          build(<String>['ORDER-1', 'ORDER-2']));
      expect(build(<String>['ORDER-1']), isNot(build(<String>['ORDER-2'])));
    });
  });
}

SupplierOptionEvidence _evidence() => SupplierOptionEvidence(
      variantKey: 'sku:immutable-variant-77',
      packCount: 2,
      rawUnitToken: 'pcs',
    );

Map<String, dynamic> _decisionEvidence() => <String, dynamic>{
      'source_line_key': 'supplier-line-v1:abc',
      'source_document_date': '2025-10-20',
      'supplier_order_numbers': <String>['ORDER-1'],
      'source_purchase_quantity': 2,
      'persisted_quantity': 2,
      'source_total_minor': 10001,
      'persisted_total_minor': 10001,
      'currency_code': 'CLP',
      'confirmation_surface': 'purchase_invoice_ocr',
    };

Map<String, dynamic> _resolved(SupplierOptionEvidence evidence) =>
    <String, dynamic>{
      'status': 'resolved',
      'authoritative': true,
      'id': _revisionId,
      'tenant_id': '30000000-0000-4000-8000-000000000001',
      'supplier_id': _supplierId,
      'listing_id': 'listing-44',
      'variant_key': evidence.variantKey.value,
      'revision_number': 1,
      'state': 'active',
      'resolution_kind': 'single',
      'option_evidence_hash': evidence.sha256Hex,
      'option_pack_count': evidence.packCount,
      'option_unit_class': evidence.unitClass,
      'pack_evidence_conflict': evidence.packEvidenceConflict,
      'edge_set_hash': _hashB,
      'operation_id': _operationId,
      'request_fingerprint': _hashB,
      'decision_source': 'operator_confirmed',
      'decision_evidence_hash': _hashB,
      'decision_evidence': const <String, dynamic>{
        'confirmation_surface': 'purchase_invoice_ocr',
      },
      'edges': <Map<String, dynamic>>[
        _edge(),
      ],
    };

Map<String, dynamic> _edge() => const <String, dynamic>{
      'edge_id': _edgeId,
      'edge_ordinal': 1,
      'product_id': _productId,
      'catalog_units_per_purchase': 1,
      'allocation_ratio': 1.0,
      'component_role': 'single',
    };

Map<String, dynamic> _prepared(
  SupplierOptionEvidence evidence,
  String lineKey,
) =>
    <String, dynamic>{
      'id': _applicationId,
      'source_line_key': lineKey,
      'source_row_index': 4,
      'supplier_resolution_revision_id': _revisionId,
      'supplier_listing_id': 'listing-44',
      'supplier_variant_key': evidence.variantKey.value,
      'option_evidence_hash': evidence.sha256Hex,
      'source_order_numbers': <String>['ORDER-1', 'ORDER-2'],
      'source_title': 'BUCKLOS Front-Rear brake set',
      'selected_option': 'Front Rear 2PCS',
      'raw_pack_count': 2,
      'raw_unit_token': 'pcs',
      'option_unit_class': 'piece',
      'pack_evidence_conflict': false,
      'source_snapshot': <String, dynamic>{
        'source': 'aliexpress_daily_invoice',
        'listing_id': 'listing-44',
        'variant_key': evidence.variantKey.value,
        'option_evidence_hash': evidence.sha256Hex,
        'source_row_index': 4,
        'source_line_key': lineKey,
        'source_document_date': '2025-10-20',
        'source_order_numbers': <String>['ORDER-1', 'ORDER-2'],
        'source_title': 'BUCKLOS Front-Rear brake set',
        'selected_option': 'Front Rear 2PCS',
        'raw_pack_count': 2,
        'raw_unit_code': 'pcs',
        'option_unit_class': 'piece',
        'pack_evidence_conflict': false,
        'source_purchase_quantity': 2,
        'source_line_total_minor': 10001,
        'currency_code': 'CLP',
      },
      'source_snapshot_hash': _hashB,
      'source_purchase_quantity': 2,
      'source_line_total_minor': 10001,
      'currency_code': 'CLP',
      'operation_id': _operationId,
      'replayed': false,
      'components': const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _componentId,
          'revision_edge_id': _edgeId,
          'edge_ordinal': 1,
          'product_id': _productId,
          'catalog_units_per_purchase': 1,
          'resolved_quantity': 2,
          'allocation_ratio': 1.0,
          'allocated_line_total_minor': 10001,
          'component_role': 'single',
        },
      ],
    };

final class _Harness {
  _Harness() : service = SupplierVariantResolutionService(rpc: _unwired) {
    service = SupplierVariantResolutionService(rpc: _call);
  }

  late SupplierVariantResolutionService service;
  FutureOr<dynamic> Function(String, Map<String, dynamic>)? handler;
  final List<({String functionName, Map<String, dynamic> params})> calls = [];

  Future<dynamic> _call(
      String functionName, Map<String, dynamic> params) async {
    calls.add((functionName: functionName, params: params));
    final callback = handler;
    if (callback == null) throw StateError('Unexpected RPC call.');
    return callback(functionName, params);
  }

  static Future<dynamic> _unwired(
    String functionName,
    Map<String, dynamic> params,
  ) =>
      throw StateError('Harness is not wired.');
}
