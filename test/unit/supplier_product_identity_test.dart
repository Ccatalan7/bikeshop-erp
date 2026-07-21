import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/supplier_product_identity.dart';

void main() {
  test('shared product previews retain the supplier scope used by exact lookup',
      () {
    expect(Product.listPreviewSelect, contains('supplier_id'));
    expect(Product.listPreviewSelect, contains('supplier_name'));
    expect(Product.listPreviewSelect, contains('supplier_code'));
  });

  group('SupplierProductAliasRecord', () {
    test('maps the minimal persisted identity evidence', () {
      final imageHash = List.filled(64, 'a').join();
      final record = SupplierProductAliasRecord.fromJson({
        'id': 'alias-1',
        'supplier_id': 'supplier-1',
        'supplier_name': 'AliExpress Marketplace',
        'product_id': 'product-1',
        'listing_id': '1005001234567890',
        'variant_key': 'color:black|ships-from:china',
        'normalized_title': 'ztto brake pad',
        'normalized_model': 'ms-01b',
        'image_content_hash': imageHash,
        'replayed': true,
      });

      expect(record.listingId, '1005001234567890');
      expect(record.productId, 'product-1');
      expect(record.variantKey, 'color:black|ships-from:china');
      expect(record.normalizedTitle, 'ztto brake pad');
      expect(record.imageUrl, isNull);
      expect(record.imageContentHash, imageHash);
      expect(record.replayed, isTrue);
    });
  });

  group('AliExpressSkuReservation', () {
    test('maps a replay-safe contiguous reservation', () {
      final reservation = AliExpressSkuReservation.fromJson({
        'id': 'receipt-1',
        'supplier_id': 'supplier-1',
        'supplier_name': 'AliExpress Marketplace',
        'operation_key': 'ocr-draft-1',
        'requested_count': 2,
        'first_sequence': 10000,
        'last_sequence': 10001,
        'skus': ['AE10000', 'AE10001'],
        'replayed': false,
      });

      expect(reservation.skus, ['AE10000', 'AE10001']);
      expect(reservation.firstSequence, 10000);
      expect(reservation.lastSequence, 10001);
      expect(reservation.replayed, isFalse);
    });

    test('rejects a response whose count does not match its SKU list', () {
      expect(
        () => AliExpressSkuReservation.fromJson({
          'id': 'receipt-1',
          'supplier_id': 'supplier-1',
          'supplier_name': 'AliExpress Marketplace',
          'operation_key': 'ocr-draft-1',
          'requested_count': 2,
          'first_sequence': 10000,
          'last_sequence': 10001,
          'skus': ['AE10000'],
          'replayed': false,
        }),
        throwsFormatException,
      );
    });
  });
}
