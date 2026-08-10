import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_visual_reading.dart';
import 'package:vinabike_erp/modules/inventory/services/product_image_fingerprint_service.dart';

/// Contracts carried over from the pre-2026-08-10 matcher.
///
/// The engine underneath was replaced; these are the promises that survived it,
/// migrated to the new API rather than deleted. Where the old assertion was
/// about a score, the migrated one is about the decision that score was
/// standing in for — a deleted contract is a regression nobody notices.
void main() {
  group('identidad determinista', () {
    test('las variantes de una URL de imagen AliExpress son la misma imagen',
        () async {
      const probeUrl =
          'https://ae-pic-a1.aliexpress-media.com/kf/HABC.jpg?width=800';
      const catalogUrl =
          'https://ae01.alicdn.com/kf/HABC.jpg_640x640Q90.jpg_.webp?x=1';
      expect(
        ProductDuplicateMatcherService.canonicalImageIdentity(probeUrl),
        ProductDuplicateMatcherService.canonicalImageIdentity(catalogUrl),
      );

      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Producto nuevo',
          imageUrl: probeUrl,
        ),
        products: [
          _product(
            id: 'same-image-url',
            sku: 'AE0200',
            name: 'Nombre histórico distinto',
            additionalImages: const [catalogUrl],
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.matchTier, ProductDuplicateMatchTier.exact);
      expect(candidates.single.reasons, contains('Misma imagen'));
    });

    test('un código de proveedor de OTRO proveedor no es identidad exacta',
        () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno orgánicas',
          sku: 'LISTING-77',
          supplierId: 'supplier-a',
          supplierName: 'MKR',
        ),
        products: [
          _product(
            id: 'other-supplier',
            sku: 'LOCAL-001',
            name: 'Pastillas freno orgánicas',
            supplierId: 'supplier-b',
            supplierName: 'Andes',
            supplierCode: 'LISTING-77',
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(
        candidates.single.matchTier,
        isNot(ProductDuplicateMatchTier.exact),
      );
    });

    test('la publicación AliExpress sobrevive a dos registros de proveedor',
        () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno',
          sku: 'AE-LISTING-88',
          rawText: 'item id 1005007336672891',
          supplierId: 'ali-record-a',
          supplierName: 'AliExpress Marketplace',
        ),
        products: [
          _product(
            id: 'ali-existing',
            sku: 'AE0888',
            name: 'Pastillas freno históricas',
            supplierId: 'ali-record-b',
            supplierName: 'Ali Express',
            supplierCode: '1005007336672891',
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(
        candidates.single.reasons.join(' '),
        isNot(contains('Mismo SKU')),
        reason: 'una publicación agrupa variantes, no identifica una',
      );
    });

    test('el SKU del catálogo sí es identidad exacta', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno',
          sku: 'AE0888',
          supplierName: 'AliExpress',
        ),
        products: [
          _product(id: 'exact', sku: 'AE0888', name: 'Pastillas freno'),
        ],
      );

      expect(candidates.single.matchTier, ProductDuplicateMatchTier.exact);
      expect(candidates.single.reasons, contains('Mismo SKU del catálogo'));
    });
  });

  group('orden y ranking', () {
    test('el modelo exacto del nombre gana a un candidato difuso', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Rotor de freno Shimano RT 56 160mm',
          description: 'Compatible con Shimano M610 M6000',
          rawText: 'Detalle proveedor: compatibilidad M610/M6000',
          brandName: 'Shimano',
          supplierName: 'AliExpress',
        ),
        products: [
          _product(
            id: 'compatibility-only',
            sku: 'AE0099',
            name: 'Rotor Shimano RX100 160mm',
            description: 'Compatible con Shimano M610/M6000',
            brand: 'Shimano',
            model: 'RX100',
          ),
          _product(
            id: 'exact-model',
            sku: 'AE0101',
            name: 'Disco rotor Shimano RT-56 160mm',
            brand: 'Shimano',
            model: 'RT-56',
          ),
        ],
      );

      expect(candidates.first.product.id, 'exact-model');
      expect(candidates.first.matchTier, ProductDuplicateMatchTier.strong);
      expect(candidates.first.matchedModelCodes, contains('rt56'));

      // La compatibilidad compartida NO es identidad compartida.
      final fuzzy = candidates
          .where((candidate) => candidate.product.id == 'compatibility-only');
      for (final candidate in fuzzy) {
        expect(candidate.matchedModelCodes, isEmpty);
        expect(candidate.matchTier, isNot(ProductDuplicateMatchTier.strong));
      }
    });

    test('«M610» de una frase de compatibilidad no crea evidencia de modelo',
        () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Rotor de freno Shimano RT56 160mm',
          description: 'compatible M610 M6000',
          brandName: 'Shimano',
        ),
        products: [
          _product(
            id: 'rx100',
            sku: 'AE0099',
            name: 'Rotor Shimano RX100 160mm',
            description: 'compatible M610 M6000',
            brand: 'Shimano',
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.matchedModelCodes, isEmpty);
      expect(
        candidates.single.matchTier,
        ProductDuplicateMatchTier.possible,
      );
      expect(
        candidates.single.objections.join(' '),
        contains('Otro modelo'),
      );
    });

    test('orden estable por SKU cuando nada más los separa', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: [
          _product(id: 'second', sku: 'B', name: 'Pastillas freno'),
          _product(id: 'first', sku: 'A', name: 'Pastillas freno'),
        ],
      );

      expect(candidates, hasLength(2));
      expect(
        candidates.map((candidate) => candidate.product.sku),
        <String>['A', 'B'],
      );
    });
  });

  group('marcas contradictorias fallan cerradas', () {
    test('Bucklos B01S no es Zoom B01S', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Horquilla Bucklos B01S 27.5 aire',
          model: 'B01S',
          brandName: 'Bucklos',
          supplierName: 'AliExpress',
        ),
        products: [
          _product(
            id: 'zoom',
            sku: 'AE0501',
            name: 'Horquilla Zoom B01S 27.5',
            brand: 'Zoom',
            model: 'B01S',
          ),
        ],
      );

      expect(
        candidates,
        isEmpty,
        reason: 'dos fabricantes distintos que reutilizan un código no son '
            'el mismo producto',
      );
    });

    test('ZTTO DS01S no es Risk DS01S', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno ZTTO DS01S resina',
          model: 'DS01S',
          brandName: 'ZTTO',
        ),
        products: [
          _product(
            id: 'risk',
            sku: 'AE0502',
            name: 'Pastillas freno Risk DS01S resina',
            brand: 'Risk',
            model: 'DS01S',
          ),
        ],
      );

      expect(candidates, isEmpty);
    });

    test('un fabricante que no contradice nada sigue siendo candidato',
        () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno ZTTO DS01S resina',
          model: 'DS01S',
          brandName: 'ZTTO',
        ),
        products: [
          _product(
            id: 'sin-marca',
            sku: 'AE0503',
            name: 'Pastillas freno DS01S resina',
            model: 'DS01S',
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.matchTier, ProductDuplicateMatchTier.strong);
    });
  });

  group('lectura visual', () {
    test('no se gasta una llamada de visión por candidato', () async {
      final matcher = _matcher();
      await matcher.findCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: [
          for (var index = 0; index < 12; index++)
            _product(
              id: 'p$index',
              sku: 'AE05$index',
              name: 'Pastillas freno modelo $index',
            ),
        ],
      );
      expect(matcher.visualReadingCalls, 0);
    });

    test('la ficha sin familia legible se apoya en la foto, una sola vez',
        () async {
      final matcher = ProductDuplicateMatcherService(
        inventoryService: _FakeInventoryService(),
        imageLoader: (_) async => null,
        visualReadingService: ProductVisualReadingService(
          analyzer: (bytes, {fileName, typedName}) async =>
              const AIProductImageAnalysis(
            primaryType: 'pastillas freno',
            catalogTerms: <String>['pastillas freno', 'brake pad'],
            excludedTerms: <String>[],
            confidence: 0.9,
          ),
        ),
        persistComputedImageFingerprints: false,
      );

      final probe = ProductDuplicateProbe(
        name: 'MS-11C',
        imageBytes: _imageBytes(10, 10, 10),
        imageUrl: 'https://ae01.alicdn.com/kf/HZZZ.jpg',
      );
      final products = [
        _product(id: 'pad', sku: 'AE0600', name: 'Pastillas freno MS-11C'),
      ];

      final first = await matcher.findCandidates(
        probe: probe,
        products: products,
      );
      final second = await matcher.findCandidates(
        probe: probe,
        products: products,
      );

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(
        matcher.visualReadingCalls,
        1,
        reason: 'la lectura se cachea por identidad de imagen',
      );
    });
  });

  group('ProductImageFingerprintService exact content', () {
    test('usa un digest completo, no similitud perceptual', () {
      final bytes = _imageBytes(200, 30, 30);
      final same = Uint8List.fromList(bytes);
      final different = _imageBytes(30, 30, 200);

      expect(ProductImageFingerprintService.hasExactContent(bytes, same), true);
      expect(
        ProductImageFingerprintService.hasExactContent(bytes, different),
        false,
      );
    });
  });
}

ProductDuplicateMatcherService _matcher({
  ProductDuplicateImageLoader? imageLoader,
}) {
  return ProductDuplicateMatcherService(
    inventoryService: _FakeInventoryService(),
    imageLoader: imageLoader ?? (_) async => null,
    knownBrands: const <String>['Shimano', 'ZTTO', 'Risk', 'Zoom', 'Bucklos'],
    enableVisualReading: false,
    persistComputedImageFingerprints: false,
  );
}

Product _product({
  required String id,
  required String sku,
  required String name,
  String? description,
  String? categoryName,
  String? brand,
  String? model,
  String? imageUrl,
  List<String> additionalImages = const [],
  String? supplierId,
  String? supplierName = 'AliExpress',
  String? supplierCode,
  Map<String, dynamic>? imageFingerprint,
}) {
  return Product(
    id: id,
    tenantId: 'tenant-test',
    sku: sku,
    name: name,
    description: description,
    categoryName: categoryName,
    brand: brand,
    model: model,
    supplierId: supplierId,
    supplierName: supplierName,
    supplierCode: supplierCode,
    imageUrl: imageUrl,
    additionalImages: additionalImages,
    imageFingerprint: imageFingerprint,
    price: 1000,
    cost: 500,
  );
}

Uint8List _imageBytes(int red, int green, int blue) {
  final image = img.Image(width: 18, height: 18);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    image,
    x1: 4,
    y1: 3,
    x2: 13,
    y2: 14,
    color: img.ColorRgb8(red, green, blue),
  );
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeInventoryService implements inv_service.InventoryService {
  int fingerprintWrites = 0;

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
  }) async {
    fingerprintWrites++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
