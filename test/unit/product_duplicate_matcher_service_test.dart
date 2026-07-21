import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_image_fingerprint_service.dart';

void main() {
  group('ProductDuplicateMatcherService deterministic identities', () {
    test('normalizes RT56, RT-56 and RT 56 to the same model identity', () {
      expect(
        ProductDuplicateMatcherService.extractModelIdentifiers('RT56'),
        contains('rt56'),
      );
      expect(
        ProductDuplicateMatcherService.extractModelIdentifiers('RT-56'),
        contains('rt56'),
      );
      expect(
        ProductDuplicateMatcherService.extractModelIdentifiers('RT 56'),
        contains('rt56'),
      );
    });

    test('ranks an exact normalized model ahead of fuzzy candidates', () async {
      final matcher = _matcher();
      final candidates = await matcher.findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Rotor de freno RT 56 160mm MTB',
          supplierName: 'AliExpress',
        ),
        products: [
          _product(
            id: 'generic',
            sku: 'AE0100',
            name: 'Rotor de freno RT57 160mm MTB',
            model: 'RT57',
          ),
          _product(
            id: 'exact-model',
            sku: 'AE0101',
            name: 'Disco rotor Shimano RT-56 160mm',
            model: 'RT-56',
          ),
        ],
      );

      expect(candidates.first.product.id, 'exact-model');
      expect(candidates.first.hasExactModelMatch, isTrue);
      expect(candidates.first.matchTier, ProductDuplicateMatchTier.strong);
      expect(candidates.first.overallScore, greaterThanOrEqualTo(0.94));
    });

    test('canonical AliExpress image URL variants are exact identity',
        () async {
      const probeUrl =
          'https://ae-pic-a1.aliexpress-media.com/kf/HABC.jpg?width=800';
      const catalogUrl =
          'https://ae01.alicdn.com/kf/HABC.jpg_640x640Q90.jpg_.webp?x=1';
      expect(
        ProductDuplicateMatcherService.canonicalImageIdentity(probeUrl),
        ProductDuplicateMatcherService.canonicalImageIdentity(catalogUrl),
      );

      final candidates =
          await _matcher(imageLoader: (_) async => null).findCandidates(
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
      expect(candidates.single.hasExactImageMatch, isTrue);
      expect(candidates.single.matchTier, ProductDuplicateMatchTier.exact);
      expect(candidates.single.overallScore, 1);
    });

    test('checks every candidate image and detects byte-identical content',
        () async {
      final probeBytes = _imageBytes(20, 40, 60);
      final otherBytes = _imageBytes(200, 180, 160);
      final imageBytesByUrl = <String, Uint8List>{
        'https://example.test/first.png': otherBytes,
        'https://example.test/second.png': probeBytes,
      };
      var aiCalls = 0;
      final candidates = await _matcher(
        imageLoader: (url) async => imageBytesByUrl[url],
        visualComparator: ({
          required probeImageBytes,
          required candidateImageBytes,
          probeName,
          candidateName,
          candidateBrand,
          candidateCategory,
        }) async {
          aiCalls++;
          return const AIProductVisualComparison(
            samePartScore: 0,
            shapeScore: 0,
            colorScore: 0,
            componentTypeMatch: false,
            confidence: 1,
          );
        },
      ).findCandidates(
        probe: ProductDuplicateProbe(
          name: 'Pastillas de freno',
          imageBytes: probeBytes,
        ),
        products: [
          _product(
            id: 'exact-content',
            sku: 'AE0300',
            name: 'Pastillas de freno históricas',
            imageUrl: 'https://example.test/first.png',
            additionalImages: const ['https://example.test/second.png'],
          ),
        ],
      );

      expect(candidates.single.hasExactImageMatch, isTrue);
      expect(candidates.single.matchTier, ProductDuplicateMatchTier.exact);
      expect(candidates.single.overallScore, 1);
      expect(aiCalls, 0, reason: 'exact identity must not enter fuzzy AI pass');
    });

    test('unavailable image is reweighted instead of scored as mismatch',
        () async {
      final candidates =
          await _matcher(imageLoader: (_) async => null).findCandidates(
        probe: ProductDuplicateProbe(
          name: 'Pastillas freno semimetálicas',
          imageBytes: _imageBytes(10, 20, 30),
        ),
        products: [
          _product(
            id: 'unavailable-image',
            sku: 'AE0400',
            name: 'Pastillas freno semimetálicas',
            imageUrl: 'https://example.test/missing.png',
          ),
        ],
      );
      final withoutImage = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno semimetálicas',
        ),
        products: [
          _product(
            id: 'unavailable-image',
            sku: 'AE0400',
            name: 'Pastillas freno semimetálicas',
            imageUrl: 'https://example.test/missing.png',
          ),
        ],
      );

      expect(candidates.single.imageComparisonAvailable, isFalse);
      expect(
        candidates.single.overallScore,
        closeTo(withoutImage.single.overallScore, 0.000001),
      );
      expect(
        candidates.single.signals,
        contains('Imagen no disponible para comparar'),
      );
    });

    test('limits Gemini visual comparison to three ambiguous candidates',
        () async {
      final probeBytes = _imageBytes(1, 2, 3);
      final bytesByUrl = <String, Uint8List>{};
      final products = <Product>[];
      for (var index = 0; index < 5; index++) {
        final url = 'https://example.test/$index.png';
        bytesByUrl[url] = _imageBytes(30 + index, 60 + index, 90 + index);
        products.add(_product(
          id: 'candidate-$index',
          sku: 'AE05$index',
          name: 'Pastillas freno semimetálicas universales',
          imageUrl: url,
        ));
      }
      var aiCalls = 0;
      final candidates = await _matcher(
        imageLoader: (url) async => bytesByUrl[url],
        visualComparator: ({
          required probeImageBytes,
          required candidateImageBytes,
          probeName,
          candidateName,
          candidateBrand,
          candidateCategory,
        }) async {
          aiCalls++;
          return const AIProductVisualComparison(
            samePartScore: 0.75,
            shapeScore: 0.75,
            colorScore: 0.75,
            componentTypeMatch: true,
            confidence: 0.8,
          );
        },
      ).findCandidates(
        probe: ProductDuplicateProbe(
          name: 'Pastillas freno semimetálicas universales',
          supplierName: 'AliExpress',
          imageBytes: probeBytes,
        ),
        products: products,
        limit: 5,
      );

      expect(candidates, hasLength(5));
      expect(aiCalls, 3);
    });

    test('uses stable SKU ordering when all scores tie', () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: [
          _product(id: 'second', sku: 'B', name: 'Pastillas freno'),
          _product(id: 'first', sku: 'A', name: 'Pastillas freno'),
        ],
      );

      expect(candidates.map((candidate) => candidate.product.sku), ['A', 'B']);
    });

    test('does not treat a cross-supplier supplier code as exact identity',
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
      expect(candidates.single.identityScore, 0);
      expect(
        candidates.single.matchTier,
        isNot(ProductDuplicateMatchTier.exact),
      );
    });

    test('keeps AliExpress listing identity across Ali supplier records',
        () async {
      final candidates = await _matcher().findCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno',
          sku: 'AE-LISTING-88',
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
            supplierCode: 'AE-LISTING-88',
          ),
        ],
      );

      expect(candidates.single.identityScore, 1);
      expect(candidates.single.matchTier, ProductDuplicateMatchTier.exact);
    });
  });

  group('ProductImageFingerprintService exact content', () {
    test('uses a full content digest, not perceptual similarity', () {
      final bytes = _imageBytes(12, 34, 56);
      final copy = Uint8List.fromList(bytes);
      final different = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;

      expect(ProductImageFingerprintService.hasExactContent(bytes, copy), true);
      expect(
        ProductImageFingerprintService.hasExactContent(bytes, different),
        false,
      );
    });
  });
}

ProductDuplicateMatcherService _matcher({
  ProductDuplicateImageLoader? imageLoader,
  ProductDuplicateVisualComparator? visualComparator,
}) {
  return ProductDuplicateMatcherService(
    inventoryService: _FakeInventoryService(),
    imageLoader: imageLoader,
    visualComparator: visualComparator,
    enableSemanticSearch: false,
    persistComputedImageFingerprints: false,
  );
}

Product _product({
  required String id,
  required String sku,
  required String name,
  String? model,
  String? imageUrl,
  List<String> additionalImages = const [],
  String? supplierId,
  String? supplierName = 'AliExpress',
  String? supplierCode,
}) {
  return Product(
    id: id,
    tenantId: 'tenant-test',
    sku: sku,
    name: name,
    model: model,
    supplierId: supplierId,
    supplierName: supplierName,
    supplierCode: supplierCode,
    imageUrl: imageUrl,
    additionalImages: additionalImages,
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
  @override
  bool isAliExpressSupplierName(String? supplierName) {
    final normalized = (supplierName ?? '').toLowerCase();
    return normalized.contains('aliexpress') ||
        normalized.contains('ali express');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
