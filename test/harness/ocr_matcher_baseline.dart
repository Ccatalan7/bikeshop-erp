// Measurement harness for the shipped matcher over a production-derived
// catalog dump: it prints what each invoice line resolves to and how long that
// took. Not part of the automatic suite (no `_test` suffix).
//
//   fvm flutter test test/harness/ocr_matcher_baseline.dart
//
// Reads .tmp/ocr-redesign-evidence/catalog.json (see the redesign notes for how
// it is produced with scripts/db/query.sh, read-only).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';

void main() {
  test('baseline: current matcher over the production catalog', () async {
    final file = File('.tmp/ocr-redesign-evidence/catalog.json');
    final rows = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final products = rows.map(_product).toList(growable: false);
    stdout.writeln('catalog: ${products.length} products');

    final matcher = ProductDuplicateMatcherService(
      inventoryService: _FakeInventoryService(),
      imageLoader: (_) async => null,
      enableVisualReading: false,
      persistComputedImageFingerprints: false,
    );

    for (final probe in _probes) {
      final watch = Stopwatch()..start();
      final candidates = await matcher.findCandidates(
        probe: probe.probe,
        products: products,
      );
      watch.stop();
      stdout.writeln('');
      stdout.writeln('── ${probe.label}  (esperado: ${probe.expectedSku})');
      stdout.writeln('   ${watch.elapsedMilliseconds} ms · '
          '${candidates.length} candidatos');
      for (final candidate in candidates) {
        stdout.writeln(
          '   ${candidate.product.sku.padRight(14)} '
          '${candidate.matchTier.name.padRight(8)} '
          '${candidate.product.name}\n'
          '        ${candidate.reasons.join(' · ')}'
          '${candidate.objections.isEmpty ? '' : '\n        ⚠ '
              '${candidate.objections.join(' · ')}'}',
        );
      }
      final rank =
          candidates.indexWhere((c) => c.product.sku == probe.expectedSku);
      stdout.writeln('   >> rank del esperado: '
          '${rank < 0 ? "NO APARECE" : "#${rank + 1}"}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _Probe {
  const _Probe({
    required this.label,
    required this.expectedSku,
    required this.probe,
  });

  final String label;
  final String expectedSku;
  final ProductDuplicateProbe probe;
}

const _probes = <_Probe>[
  _Probe(
    label: 'Tee WAKE 31.8mm rojo',
    expectedSku: 'AE0137',
    probe: ProductDuplicateProbe(
      name: 'Tee WAKE 31.8mm',
      description:
          'WAKE-vástago ligero de aleación de aluminio para bicicleta de '
          'montaña, pieza de manillar corto para bici de carretera, BMX, DH, '
          '31,8mm (Red)',
      rawText: 'item id 1005007336672891',
      categoryName: 'Tee',
      brandName: 'Wake',
      supplierName: 'AliExpress',
      cost: 7172,
      price: 14300,
    ),
  ),
  _Probe(
    label: 'Tee WAKE 31.8mm morado',
    expectedSku: 'AE0138',
    probe: ProductDuplicateProbe(
      name: 'Potencia WAKE 31.8mm morada',
      description:
          'WAKE-vástago ligero de aleación de aluminio para bicicleta de '
          'montaña, pieza de manillar corto para bici de carretera, BMX, DH, '
          '31,8mm (Purple)',
      rawText: 'item id 1005007336672891',
      brandName: 'Wake',
      supplierName: 'AliExpress',
      cost: 7172,
      price: 14300,
    ),
  ),
  _Probe(
    label: 'Volante IXF 104BCD 170mm 36T',
    expectedSku: 'AE0093',
    probe: ProductDuplicateProbe(
      name: 'IXF-platos y bielas para bicicleta 104BCD 170mm 36T compatible '
          'con SHIMANO/SRAM',
      description:
          'IXF-platos y bielas para bicicleta 104BCD, 170mm, manivela ancha y '
          'estrecha, rueda de cadena de disco ovalada/redonda, Compatible con '
          'SHIMANO/SRAM (Black crank BB 36T, 170mm)',
      model: '104BCD',
      rawText: 'item id 10050084658370',
      categoryName: 'Volantes',
      brandName: 'Shimano',
      supplierName: 'AliExpress',
      cost: 36684,
    ),
  ),
  _Probe(
    label: 'Rotor Shimano RT56 160mm',
    expectedSku: 'AE0155',
    probe: ProductDuplicateProbe(
      name: 'Rotor de freno Shimano RT56 160mm 6 pernos',
      description:
          'Rotor de freno de disco de bicicleta RT56 MTB, disco de montaña de '
          '6 pernos M610 M6000, 160MM 180MM (160mm 1pcs)',
      model: 'RT56',
      rawText: 'item id 10050037769267',
      categoryName: 'Rotores',
      brandName: 'Shimano',
      supplierName: 'AliExpress',
      cost: 6859,
    ),
  ),
  _Probe(
    label: 'Adaptador Presta a Schrader',
    expectedSku: 'AE0001',
    probe: ProductDuplicateProbe(
      name: 'Adaptador Presta a Schrader',
      description:
          'Adaptador Presta a Schrader para bicicleta, adaptador de válvula de '
          'neumático, conectores de válvula de bomba, dorados de cobre, '
          'convertidor F/V a A/V (10 pcs)',
      rawText: 'item id 10050094669679',
      categoryName: 'Válvula Tubeless',
      supplierName: 'AliExpress',
      cost: 2365,
    ),
  ),
  _Probe(
    label: 'Maza trasera Novatec D042SB 32H',
    expectedSku: 'AE0062',
    probe: ProductDuplicateProbe(
      name: 'Maza trasera Novatec D042SB 32H HG',
      description:
          'Novatec bujes de bicicleta D041SB D042SB buje libre de acero MTB '
          'buje de bicicleta freno de disco buje de Cassette 28/32/36 agujeros '
          'HG SX 8-12 velocidades (Black rear 32H)',
      model: 'D042SB',
      rawText: 'item id 10050084210422',
      categoryName: 'Mazas',
      brandName: 'Novatec',
      supplierName: 'AliExpress',
      cost: 32527,
    ),
  ),
  _Probe(
    label: 'Cortacadena RIDERACE',
    expectedSku: 'AE0147',
    probe: ProductDuplicateProbe(
      name: 'Cortacadena RIDERACE',
      description: 'Herramienta cortacadena de bicicleta RIDERACE',
      rawText: 'item id 10050082146375',
      categoryName: 'Herramientas',
      brandName: 'RideRace',
      supplierName: 'AliExpress',
      cost: 6543,
    ),
  ),
];

Product _product(Map<String, dynamic> json) {
  return Product(
    id: json['id'] as String?,
    tenantId: 'tenant',
    sku: (json['sku'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    description: json['description'] as String?,
    categoryId: json['category_id'] as String?,
    categoryName: json['category_name'] as String?,
    supplierId: json['supplier_id'] as String?,
    supplierName: json['supplier_name'] as String?,
    supplierCode: json['supplier_code'] as String?,
    brand: json['brand'] as String?,
    model: json['model'] as String?,
    manufacturer: json['manufacturer'] as String?,
    manufacturerSku: json['manufacturer_sku'] as String?,
    imageUrl: json['image_url'] as String?,
    tags: ((json['tags'] as List?) ?? const []).cast<String>(),
    price: ((json['price'] as num?) ?? 0).toDouble(),
    cost: ((json['cost'] as num?) ?? 0).toDouble(),
    inventoryQty: ((json['inventory_qty'] as num?) ?? 0).toInt(),
    isActive: (json['is_active'] as bool?) ?? true,
  );
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  bool isAliExpressSupplierName(String? supplierName) {
    final normalized = (supplierName ?? '').toLowerCase();
    return normalized.contains('aliexpress') ||
        normalized.contains('ali express');
  }

  @override
  Future<void> storeProductImageFingerprint({
    required String productId,
    required Map<String, dynamic> imageFingerprint,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
