// Measurement harness for the typed identity engine against a
// production-derived catalog dump. Not part of the automatic suite.
//
//   fvm flutter test test/harness/ocr_identity_engine_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_catalog_identity_index.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';

void main() {
  test('typed identity engine over the production catalog', () async {
    final rows = (jsonDecode(File('.tmp/ocr-redesign-evidence/catalog.json')
            .readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final products = rows.map(_product).toList(growable: false);
    final ancestry = _categoryAncestry();

    final buildWatch = Stopwatch()..start();
    final index = ProductCatalogIdentityIndex(
      knownBrands: _knownBrands,
      categoryAncestry: ancestry,
    )..sync(products);
    buildWatch.stop();
    stdout.writeln('índice: ${index.length} productos en '
        '${buildWatch.elapsedMilliseconds} ms');

    final matcher = ProductIdentityMatcher(categoryAncestry: ancestry);
    final durations = <int>[];

    for (final probe in _probes) {
      final watch = Stopwatch()..start();
      final profile = ProductIdentityExtractor.extract(probe.input);
      final shortlist = index.retrieve(profile);
      final results = <({Product product, ProductIdentityMatch match})>[];
      for (final product in shortlist) {
        final match = matcher.evaluate(
          probe: profile,
          candidate: index.profileOfProduct(product),
        );
        if (match.isRejected) continue;
        results.add((product: product, match: match));
      }
      final shown =
          const IdentityShortlistPolicy().apply(results, (row) => row.match);
      results
        ..clear()
        ..addAll(shown);
      watch.stop();
      durations.add(watch.elapsedMicroseconds);

      stdout.writeln('');
      stdout.writeln('── ${probe.label}   (esperado ${probe.expectedSku})');
      stdout.writeln('   ${profile}');
      stdout.writeln('   shortlist ${shortlist.length} · '
          'aceptados ${results.length} · '
          '${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms');
      for (final result in results.take(8)) {
        stdout.writeln(
          '   ${result.product.sku.padRight(14)} '
          '${result.match.verdict.name.padRight(8)} '
          '${result.match.score.toStringAsFixed(2)} '
          '${result.product.name}',
        );
        stdout.writeln('        ${result.match.reasons.join(' · ')}');
        if (result.match.objections.isNotEmpty) {
          stdout.writeln('        ⚠ ${result.match.objections.join(' · ')}');
        }
      }
      final rank =
          results.indexWhere((r) => r.product.sku == probe.expectedSku);
      stdout.writeln(
        '   >> ${rank < 0 ? "NO APARECE" : "#${rank + 1}"}',
      );
    }

    durations.sort();
    stdout.writeln('');
    stdout.writeln(
        'p50 ${(durations[durations.length ~/ 2] / 1000).toStringAsFixed(1)} ms · '
        'p95 ${(durations[(durations.length * 0.95).floor().clamp(0, durations.length - 1)] / 1000).toStringAsFixed(1)} ms');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

const _knownBrands = <String>[
  'Shimano',
  'Novatec',
  'Wake',
  'RideRace',
  'Deemount',
  'MUQZI',
  'Meroca',
  'ZTTO',
  'Toopre',
  'Mana',
  'KENDA',
  'Maxxis',
  'Chaoyang',
  'Arisun',
  'Ralco',
  'Duro',
  'CST',
  'Giyo',
  'West Biking',
  '10Ten',
  'Le Tour',
  'RideXC',
  'RBX',
  'Weinmann',
  'Velocek',
  'Vuelta USA',
  'Wistio',
  'Genérico',
  'Arisun',
  'RISK',
  'Bucklos',
  'ODI',
  'LUNJE',
];

Map<String, List<String>> _categoryAncestry() => <String, List<String>>{
      'adaptadores': ['accesorios', 'adaptadores'],
      'tee': ['componentes', 'direccion', 'tee'],
      'rotores': ['componentes', 'frenos', 'rotores'],
      'rotor bmx': ['componentes', 'frenos', 'rotor bmx'],
      'mazas': ['componentes', 'ruedas', 'mazas'],
      'maza': ['componentes', 'ruedas', 'mazas', 'maza'],
      'valvula tubeless': [
        'componentes',
        'ruedas',
        'tubeless',
        'valvula tubeless',
      ],
      'volantes': ['componentes', 'transmision', 'volantes'],
      'volante': ['componentes', 'transmision', 'volantes', 'volante'],
      'herramientas': ['herramientas'],
      'corta cadena': ['herramientas', 'corta cadena'],
    };

class _Probe {
  const _Probe({
    required this.label,
    required this.expectedSku,
    required this.input,
  });

  final String label;
  final String expectedSku;
  final ProductIdentityInput input;
}

/// Two real AliExpress days, measured against the same production catalog.
///
/// The seven lines of AE160326 are the invoice that exposed the original
/// engine. The fourteen of AE100326 were run afterwards, on 2026-08-10, so the
/// rebuilt engine would be judged on products it had never been tuned against
/// — and they immediately found two: `Missinglink` and `Sticker protector`
/// were families the taxonomy did not have, so nothing eliminated a chain
/// sticker from a master-link purchase.
final _probes = <_Probe>[
  _Probe(
    label: 'Missinglink RISK 9v (AE100326 · 2026-03-10)',
    expectedSku: 'AE0097',
    input: const ProductIdentityInput(
      name: 'Eslabón rápido RISK 9 velocidades',
      // The real listing sells every speed from one page, so its body offers
      // all of them. Only the variant the shop bought says nine.
      description:
          '5 pares de juntas de conector de enlace rápido para cadena de '
          'bicicleta, 6 7 8 9 10 11 12 velocidades, RISK',
      brandHint: 'RISK',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Missinglink RISK 10v (AE100326 · 2026-03-10)',
    expectedSku: 'AE0098',
    input: const ProductIdentityInput(
      name: 'Eslabón rápido RISK 10v',
      description:
          '5 pares de juntas de conector de enlace rápido para cadena de '
          'bicicleta, 6 7 8 9 10 11 12 velocidades, RISK',
      brandHint: 'RISK',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Tee WAKE 31.8mm rojo',
    expectedSku: 'AE0137',
    input: const ProductIdentityInput(
      name: 'Tee WAKE 31.8mm',
      description:
          'WAKE-vástago ligero de aleación de aluminio para bicicleta de '
          'montaña, pieza de manillar corto para bici de carretera, BMX, DH, '
          '31,8mm (Red)',
      categoryPath: 'Componentes / Dirección / Tee',
      brandHint: 'Wake',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Tee WAKE 31.8mm morado',
    expectedSku: 'AE0138',
    input: const ProductIdentityInput(
      name: 'Potencia WAKE 31.8mm morada',
      description:
          'WAKE-vástago ligero de aleación de aluminio para bicicleta de '
          'montaña, pieza de manillar corto, 31,8mm (Purple)',
      brandHint: 'Wake',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Volante IXF 104BCD 170mm 36T',
    expectedSku: 'AE0093',
    input: const ProductIdentityInput(
      name: 'IXF-platos y bielas para bicicleta 104BCD 170mm 36T compatible '
          'con SHIMANO/SRAM',
      description:
          'IXF-platos y bielas para bicicleta 104BCD, 170mm, manivela ancha y '
          'estrecha, rueda de cadena de disco ovalada/redonda, Compatible con '
          'SHIMANO/SRAM (Black crank BB 36T, 170mm)',
      modelHint: '104BCD',
      categoryPath: 'Volantes',
      brandHint: 'Shimano',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Rotor Shimano RT56 160mm',
    expectedSku: 'AE0155',
    input: const ProductIdentityInput(
      name: 'Rotor de freno Shimano RT56 160mm 6 pernos',
      description:
          'Rotor de freno de disco de bicicleta RT56 MTB, disco de montaña de '
          '6 pernos M610 M6000, 160MM (160mm 1pcs)',
      modelHint: 'RT56',
      categoryPath: 'Rotores',
      brandHint: 'Shimano',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Adaptador Presta a Schrader',
    expectedSku: 'AE0001',
    input: const ProductIdentityInput(
      name: 'Adaptador Presta a Schrader',
      description:
          'Adaptador Presta a Schrader para bicicleta, adaptador de válvula de '
          'neumático de bicicleta, conectores de válvula de bomba, dorados de '
          'cobre, convertidor F/V a A/V (10 pcs)',
      categoryPath: 'Válvula Tubeless',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Maza trasera Novatec D042SB 32H',
    expectedSku: 'AE0062',
    input: const ProductIdentityInput(
      name: 'Maza trasera Novatec D042SB 32H HG',
      description:
          'Novatec bujes de bicicleta D041SB D042SB buje libre de acero MTB '
          'buje de bicicleta freno de disco buje de Cassette 28/32/36 agujeros '
          'HG SX 8-12 velocidades (Black rear 32H)',
      modelHint: 'D042SB',
      categoryPath: 'Mazas',
      brandHint: 'Novatec',
      knownBrands: _knownBrands,
    ),
  ),
  _Probe(
    label: 'Cortacadena RIDERACE',
    expectedSku: 'AE0147',
    input: const ProductIdentityInput(
      name: 'Cortacadena RIDERACE',
      description: 'Herramienta cortacadena de bicicleta RIDERACE',
      categoryPath: 'Herramientas',
      brandHint: 'RideRace',
      knownBrands: _knownBrands,
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
