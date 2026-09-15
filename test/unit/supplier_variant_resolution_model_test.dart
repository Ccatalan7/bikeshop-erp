import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _revisionId = '10000000-0000-4000-8000-000000000001';
const _applicationId = '10000000-0000-4000-8000-000000000002';
const _operationId = '10000000-0000-4000-8000-000000000003';
const _productOneId = '20000000-0000-4000-8000-000000000001';
const _productTwoId = '20000000-0000-4000-8000-000000000002';

void main() {
  group('SupplierOptionEvidence', () {
    test('normalizes immutable property order and localized unit synonyms', () {
      final evidence = SupplierOptionEvidence(
        variantKey: 'props:9002:BLACK|9001:2PCS',
        packCount: 2,
        rawUnitToken: 'Piezas',
      );
      final localized = SupplierOptionEvidence(
        variantKey: 'props:9001:2pcs|9002:black',
        packCount: 2,
        rawUnitToken: 'pcs',
      );

      expect(evidence.variantKey.value, 'props:9001:2pcs|9002:black');
      expect(evidence.unitClass, 'piece');
      expect(evidence.sha256Hex, localized.sha256Hex);
      expect(
        evidence.sha256Hex,
        'c586e106311cfdeee7694173e3a0cc0a53d3de9a19a1c43982649ddf10c26010',
        reason: 'must match supplier_option_evidence_v1_hash in PostgreSQL',
      );
      expect(
        evidence.canonicalJson,
        '{"schema":"supplier_option_evidence_v1",'
        '"variant_key":"props:9001:2pcs|9002:black",'
        '"pack_count":2,"unit_class":"piece",'
        '"pack_evidence_conflict":false}',
      );
    });

    test('ignores translated labels but changes hash for 2PCS versus 1PCS', () {
      SupplierOptionEvidence evidence({required int packCount}) =>
          SupplierOptionEvidence(
            variantKey: 'sku:immutable-variant-77',
            packCount: packCount,
            rawUnitToken: 'pcs',
          );

      final black = evidence(packCount: 2);
      final negro = evidence(packCount: 2);
      final onePiece = evidence(packCount: 1);

      expect(black.sha256Hex, negro.sha256Hex,
          reason: 'Black/Negro display labels are not hash input');
      expect(black.sha256Hex, isNot(onePiece.sha256Hex));
      expect(black.sha256Hex, hasLength(64));
    });

    test('refuses labels/default and contradictory unit-only evidence', () {
      expect(
        () => SupplierOptionEvidence(variantKey: 'label:Black'),
        throwsFormatException,
      );
      expect(
        () => SupplierOptionEvidence(
          variantKey: 'sku:immutable-variant-77',
          rawUnitToken: 'pcs',
        ),
        throwsArgumentError,
      );
    });

    test('requires a graph for pair or set semantics even when count is one',
        () {
      SupplierOptionEvidence evidence(String unit) => SupplierOptionEvidence(
            variantKey: 'sku:immutable-variant-77',
            packCount: 1,
            rawUnitToken: unit,
          );

      expect(evidence('pair').requiresExplicitComposition, isTrue);
      expect(evidence('set').requiresExplicitComposition, isTrue);
      expect(evidence('piece').requiresExplicitComposition, isFalse);
      expect(evidence('unit').requiresExplicitComposition, isFalse);
    });
  });

  group('SupplierVariantResolution', () {
    test('parses a complete active composite in edge order', () {
      final resolution = SupplierVariantResolution.fromLookupJson(
        _resolvedJson(
          edges: <Map<String, dynamic>>[
            _edge(2, _productTwoId, 1, 0.4, 'rear'),
            _edge(1, _productOneId, 1, 0.6, 'front'),
          ],
        ),
      );

      expect(resolution.isResolved, isTrue);
      expect(resolution.kind, SupplierVariantResolutionKind.composite);
      expect(
        resolution.edges.map((edge) => edge.position),
        <int>[1, 2],
      );
      expect(resolution.optionEvidenceHash, _optionEvidence().sha256Hex);
      expect(resolution.optionPackCount, 2);
      expect(resolution.optionUnitClass, 'piece');
      expect(resolution.packEvidenceConflict, isFalse);
      expect(resolution.toJson()['edges'], hasLength(2));
    });

    test('fails closed on gaps and ratio drift', () {
      for (final edges in <List<Map<String, dynamic>>>[
        <Map<String, dynamic>>[
          _edge(1, _productOneId, 1, 0.5, 'front'),
          _edge(3, _productTwoId, 1, 0.5, 'rear'),
        ],
        <Map<String, dynamic>>[
          _edge(1, _productOneId, 1, 0.4, 'front'),
          _edge(2, _productTwoId, 1, 0.5, 'rear'),
        ],
      ]) {
        final resolution = SupplierVariantResolution.fromLookupJson(
          _resolvedJson(edges: edges),
        );
        expect(resolution.isResolved, isFalse);
        expect(
          resolution.status,
          SupplierVariantResolutionStatus.invalidResponse,
        );
        expect(resolution.edges, isEmpty);
      }
    });

    test('preserves repeated catalog product under distinct physical roles',
        () {
      final resolution = SupplierVariantResolution.fromLookupJson(
        _resolvedJson(
          edges: <Map<String, dynamic>>[
            _edge(1, _productOneId, 1, 0.5, 'left'),
            _edge(2, _productOneId, 1, 0.5, 'right'),
          ],
        ),
      );

      expect(resolution.isResolved, isTrue);
      expect(resolution.edges, hasLength(2));
      expect(
        resolution.edges.map((edge) => edge.componentRole),
        <String>['left', 'right'],
      );
    });

    test('fails closed when option preimage or decision provenance drifts', () {
      final wrongPack = _resolvedJson(
        edges: <Map<String, dynamic>>[
          _edge(1, _productOneId, 1, 0.5, 'front'),
          _edge(2, _productTwoId, 1, 0.5, 'rear'),
        ],
      )..['option_pack_count'] = 1;
      final missingDecisionHash = _resolvedJson(
        edges: <Map<String, dynamic>>[
          _edge(1, _productOneId, 1, 0.5, 'front'),
          _edge(2, _productTwoId, 1, 0.5, 'rear'),
        ],
      )..remove('decision_evidence_hash');

      for (final json in <Map<String, dynamic>>[
        wrongPack,
        missingDecisionHash,
      ]) {
        final resolution = SupplierVariantResolution.fromLookupJson(json);
        expect(resolution.isResolved, isFalse);
        expect(
          resolution.status,
          SupplierVariantResolutionStatus.invalidResponse,
        );
        expect(resolution.edges, isEmpty);
      }
    });

    test('never exposes legacy review candidate edges as authority', () {
      final resolution = SupplierVariantResolution.fromLookupJson(
        <String, dynamic>{
          'status': 'legacy_candidate',
          'authoritative': false,
          'requires_confirmation': true,
          'legacy_alias_id': 'legacy-1',
          'variant_key': 'sku:immutable-variant-77',
          'edges': <Map<String, dynamic>>[
            _edge(1, _productOneId, 1, 1, 'legacy_candidate'),
          ],
        },
      );

      expect(resolution.isResolved, isFalse);
      expect(resolution.requiresConfirmation, isTrue);
      expect(resolution.edges, isEmpty);
    });
  });

  group('PurchaseInvoiceItem supplier provenance', () {
    test('exact JSON and copyWith preserve every source field', () {
      final source = <String, dynamic>{
        'line_id': 'line-stable-1',
        'product_id': _productOneId,
        'product_name': 'Caliper delantero',
        'product_sku': 'AE0144',
        'description': 'BUCKLOS Front-Rear',
        'purchase_treatment': 'inventory',
        'quantity': 2.0,
        'unit_cost': 3050.5,
        'discount': 0.0,
        'iva_rate': 0.19,
        'created_at': '2026-08-12T10:00:00.000Z',
        'supplier_resolution_application_id': _applicationId,
        'supplier_resolution_revision_id': _revisionId,
        'source_line_key': 'supplier-line-v1:abc',
        'supplier_resolution_edge_ordinal': 1,
        'supplier_resolution_component_role': 'front',
        'source_purchase_quantity': 2.0,
        'catalog_units_per_purchase': 1,
        'source_line_total_minor': 12202,
        'allocated_line_total_minor': 6101,
        'allocation_ratio': 0.5,
        'source_row_index': 4,
        'source_order_numbers': <String>['ORDER-1', 'ORDER-2'],
        'supplier_listing_id': 'listing-44',
        'supplier_variant_key': 'sku:immutable-variant-77',
        'option_evidence_hash': _hashA,
        'source_title': 'BUCKLOS Front-Rear brake set',
        'selected_option': 'Front Rear 2PCS',
        'raw_pack_count': 2,
        'raw_unit_code': 'pcs',
        'pack_evidence_conflict': false,
        'source_snapshot': <String, dynamic>{
          'listing_id': 'listing-44',
          'variant_key': 'sku:immutable-variant-77',
          'option_evidence_hash': _hashA,
        },
      };

      final item = PurchaseInvoiceItem.fromJson(source);
      final encoded = item.toJson();

      expect(encoded, source);
      expect(item.hasCompleteSupplierResolutionProvenance, isTrue);
      expect(
          item.copyWith(description: 'Display edit').toJson(),
          <String, dynamic>{
            ...source,
            'description': 'Display edit',
          });
    });

    test('legacy JSON remains valid and omits every new key', () {
      final legacy = <String, dynamic>{
        'product_id': _productOneId,
        'product_name': 'Legacy product',
        'product_sku': 'LEGACY-1',
        'description': 'Old row',
        'purchase_treatment': 'inventory',
        'quantity': 3.0,
        'unit_cost': 1000.0,
        'discount': 0.0,
        'iva_rate': 0.19,
        'created_at': '2026-08-12T10:00:00.000Z',
      };

      final item = PurchaseInvoiceItem.fromJson(legacy);

      expect(item.toJson(), legacy);
      expect(item.hasSupplierResolutionProvenance, isFalse);
      expect(item.hasSupplierSourceEvidence, isFalse);
    });

    test('rejects fractional integer provenance instead of truncating', () {
      expect(
        () => PurchaseInvoiceItem.fromJson(<String, dynamic>{
          'product_id': _productOneId,
          'unit_cost': 1,
          'supplier_resolution_edge_ordinal': 1.5,
        }),
        throwsFormatException,
      );
    });
  });

  test('prepared source receipt validates exact quantity and allocation', () {
    final receipt = SupplierInvoiceSourceResolution.fromJson(
      <String, dynamic>{
        'id': _applicationId,
        'source_line_key': 'supplier-line-v1:abc',
        'source_row_index': 2,
        'supplier_resolution_revision_id': _revisionId,
        'supplier_listing_id': 'listing-44',
        'supplier_variant_key': 'sku:immutable-variant-77',
        'option_evidence_hash': _optionEvidence().sha256Hex,
        'source_order_numbers': <String>['ORDER-1'],
        'source_title': 'Brake set',
        'selected_option': 'Front Rear 2PCS',
        'raw_pack_count': 2,
        'raw_unit_token': 'pcs',
        'option_unit_class': 'piece',
        'pack_evidence_conflict': false,
        'source_snapshot': <String, dynamic>{
          'listing_id': 'listing-44',
          'variant_key': 'sku:immutable-variant-77',
          'option_evidence_hash': _optionEvidence().sha256Hex,
          'source_row_index': 2,
          'source_line_key': 'supplier-line-v1:abc',
          'source_document_date': '2025-10-20',
          'source_order_numbers': <String>['ORDER-1'],
          'source_title': 'Brake set',
          'selected_option': 'Front Rear 2PCS',
          'raw_pack_count': 2,
          'raw_unit_code': 'pcs',
          'option_unit_class': 'piece',
          'pack_evidence_conflict': false,
          'source_purchase_quantity': 2.0,
          'source_line_total_minor': 12203,
          'currency_code': 'CLP',
        },
        'source_snapshot_hash': _hashB,
        'source_purchase_quantity': 2.0,
        'source_line_total_minor': 12203,
        'currency_code': 'CLP',
        'operation_id': '30000000-0000-4000-8000-000000000001',
        'replayed': false,
        'components': <Map<String, dynamic>>[
          _component(1, _productOneId, 2, 4, 0.5, 6102, 'front'),
          _component(2, _productTwoId, 1, 2, 0.5, 6101, 'rear'),
        ],
      },
    );

    expect(receipt.components, hasLength(2));
    expect(
      receipt.components.fold<int>(
        0,
        (sum, component) => sum + component.allocatedLineTotalMinor,
      ),
      receipt.sourceLineTotalMinor,
    );
  });

  test('prepared source preserves one product in two physical roles', () {
    final json = _preparedSourceJson(
      components: <Map<String, dynamic>>[
        _component(1, _productOneId, 1, 2, 0.5, 6102, 'left'),
        _component(2, _productOneId, 1, 2, 0.5, 6101, 'right'),
      ],
    );

    final receipt = SupplierInvoiceSourceResolution.fromJson(json);
    expect(receipt.components, hasLength(2));
    expect(receipt.components.map((item) => item.productId).toSet(),
        <String>{_productOneId});
  });

  test('prepared source requires canonical date and raw unit code', () {
    final invalidDate = _preparedSourceJson(
      components: <Map<String, dynamic>>[
        _component(1, _productOneId, 1, 2, 1, 12203, 'single'),
      ],
    );
    invalidDate['source_snapshot'] = <String, dynamic>{
      ...(invalidDate['source_snapshot'] as Map<String, dynamic>),
      'source_document_date': '2025-02-30',
    };
    expect(
      () => SupplierInvoiceSourceResolution.fromJson(invalidDate),
      throwsFormatException,
    );

    final legacyUnitKey = _preparedSourceJson(
      components: <Map<String, dynamic>>[
        _component(1, _productOneId, 1, 2, 1, 12203, 'single'),
      ],
    );
    final legacySnapshot = Map<String, dynamic>.from(
      legacyUnitKey['source_snapshot'] as Map<String, dynamic>,
    );
    legacySnapshot['raw_unit_token'] = 'pcs';
    legacyUnitKey['source_snapshot'] = legacySnapshot;
    expect(
      () => SupplierInvoiceSourceResolution.fromJson(legacyUnitKey),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _resolvedJson({
  required List<Map<String, dynamic>> edges,
}) =>
    <String, dynamic>{
      'status': 'resolved',
      'authoritative': true,
      'id': _revisionId,
      'tenant_id': '30000000-0000-4000-8000-000000000001',
      'supplier_id': '30000000-0000-4000-8000-000000000002',
      'listing_id': 'listing-44',
      'variant_key': 'sku:immutable-variant-77',
      'revision_number': 3,
      'state': 'active',
      'resolution_kind': 'composite',
      'option_evidence_hash': _optionEvidence().sha256Hex,
      'option_pack_count': 2,
      'option_unit_class': 'piece',
      'pack_evidence_conflict': false,
      'edge_set_hash': _hashA,
      'operation_id': _operationId,
      'request_fingerprint': _hashB,
      'decision_source': 'operator_confirmed',
      'decision_evidence_hash': _hashB,
      'decision_evidence': const <String, dynamic>{
        'confirmation_surface': 'purchase_invoice_ocr',
      },
      'edges': edges,
    };

SupplierOptionEvidence _optionEvidence() => SupplierOptionEvidence(
      variantKey: 'sku:immutable-variant-77',
      packCount: 2,
      rawUnitToken: 'pcs',
    );

Map<String, dynamic> _edge(
  int position,
  String productId,
  int units,
  double ratio,
  String role,
) =>
    <String, dynamic>{
      'edge_id':
          '40000000-0000-4000-8000-${position.toString().padLeft(12, '0')}',
      'edge_ordinal': position,
      'product_id': productId,
      'catalog_units_per_purchase': units,
      'allocation_ratio': ratio,
      'component_role': role,
    };

Map<String, dynamic> _component(
  int position,
  String productId,
  int units,
  double resolvedQuantity,
  double ratio,
  int allocatedTotal,
  String role,
) =>
    <String, dynamic>{
      'id': '50000000-0000-4000-8000-${position.toString().padLeft(12, '0')}',
      'revision_edge_id':
          '40000000-0000-4000-8000-${position.toString().padLeft(12, '0')}',
      'edge_ordinal': position,
      'product_id': productId,
      'catalog_units_per_purchase': units,
      'resolved_quantity': resolvedQuantity,
      'allocation_ratio': ratio,
      'allocated_line_total_minor': allocatedTotal,
      'component_role': role,
    };

Map<String, dynamic> _preparedSourceJson({
  required List<Map<String, dynamic>> components,
}) =>
    <String, dynamic>{
      'id': _applicationId,
      'source_line_key': 'supplier-line-v1:abc',
      'source_row_index': 2,
      'supplier_resolution_revision_id': _revisionId,
      'supplier_listing_id': 'listing-44',
      'supplier_variant_key': 'sku:immutable-variant-77',
      'option_evidence_hash': _optionEvidence().sha256Hex,
      'source_order_numbers': <String>['ORDER-1'],
      'source_title': 'Brake set',
      'selected_option': 'Front Rear 2PCS',
      'raw_pack_count': 2,
      'raw_unit_token': 'pcs',
      'option_unit_class': 'piece',
      'pack_evidence_conflict': false,
      'source_snapshot': <String, dynamic>{
        'listing_id': 'listing-44',
        'variant_key': 'sku:immutable-variant-77',
        'option_evidence_hash': _optionEvidence().sha256Hex,
        'source_row_index': 2,
        'source_line_key': 'supplier-line-v1:abc',
        'source_document_date': '2025-10-20',
        'source_order_numbers': <String>['ORDER-1'],
        'source_title': 'Brake set',
        'selected_option': 'Front Rear 2PCS',
        'raw_pack_count': 2,
        'raw_unit_code': 'pcs',
        'option_unit_class': 'piece',
        'pack_evidence_conflict': false,
        'source_purchase_quantity': 2.0,
        'source_line_total_minor': 12203,
        'currency_code': 'CLP',
      },
      'source_snapshot_hash': _hashB,
      'source_purchase_quantity': 2.0,
      'source_line_total_minor': 12203,
      'currency_code': 'CLP',
      'operation_id': '30000000-0000-4000-8000-000000000001',
      'replayed': false,
      'components': components,
    };
