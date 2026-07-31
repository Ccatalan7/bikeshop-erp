import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/storefront_tax_summary.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  group('StorefrontTaxSummary', () {
    test('calculates mixed exempt/affected lines exactly like the backend', () {
      final summary = StorefrontTaxSummary.calculate(const [
        StorefrontTaxLineInput(
          label: 'Afecto',
          grossUnitPrice: 1190,
          quantity: 1,
          taxRate: 19,
        ),
        StorefrontTaxLineInput(
          label: 'Exento',
          grossUnitPrice: 500,
          quantity: 2,
          taxRate: 0,
        ),
      ]);

      expect(summary.isValid, isTrue);
      expect(summary.grossAmount, 2190);
      expect(summary.netAmount, 2000);
      expect(summary.taxAmount, 190);
      expect(summary.isMixed, isTrue);
      expect(summary.netLabel, 'Neto + exento');
      expect(summary.ivaLabel, 'IVA incluido (ítems afectos)');
    });

    test('rounds once per gross line in whole CLP', () {
      final summary = StorefrontTaxSummary.calculate(const [
        StorefrontTaxLineInput(
          label: 'Línea',
          grossUnitPrice: 100,
          quantity: 3,
          taxRate: 19,
        ),
      ]);

      expect(summary.netAmount, 252);
      expect(summary.taxAmount, 48);
      expect(summary.grossAmount, summary.netAmount + summary.taxAmount);
    });

    test('normalizes the known legacy 0.19 fraction to canonical 19', () {
      final summary = StorefrontTaxSummary.calculate(const [
        StorefrontTaxLineInput(
          label: 'Legado',
          grossUnitPrice: 1190,
          quantity: 1,
          taxRate: 0.19,
        ),
      ]);

      expect(summary.isValid, isTrue);
      expect(summary.lines.single.taxRate, 19);
      expect(summary.netAmount, 1000);
      expect(summary.taxAmount, 190);
    });

    test('fails closed on missing, unsupported, or fractional product data',
        () {
      final summary = StorefrontTaxSummary.calculate(const [
        StorefrontTaxLineInput(
          label: 'Sin tasa',
          grossUnitPrice: 1000,
          quantity: 1,
          taxRate: null,
        ),
        StorefrontTaxLineInput(
          label: 'Tasa inválida',
          grossUnitPrice: 1000,
          quantity: 1,
          taxRate: 10,
        ),
        StorefrontTaxLineInput(
          label: 'Precio inválido',
          grossUnitPrice: 1000.5,
          quantity: 1,
          taxRate: 19,
        ),
      ]);

      expect(summary.isValid, isFalse);
      expect(
        summary.issues.map((issue) => issue.code),
        [
          StorefrontTaxIssueCode.missingTaxRate,
          StorefrontTaxIssueCode.unsupportedTaxRate,
          StorefrontTaxIssueCode.invalidUnitPrice,
        ],
      );
      expect(summary.checkoutBlockMessage, contains('Sin tasa'));
    });

    test('keeps known gross separate from an invalid fiscal breakdown', () {
      const inputs = [
        StorefrontTaxLineInput(
          label: 'Sin tasa',
          grossUnitPrice: 1000,
          quantity: 2,
          taxRate: null,
        ),
        StorefrontTaxLineInput(
          label: 'Afecto',
          grossUnitPrice: 1190,
          quantity: 1,
          taxRate: 19,
        ),
      ];

      final summary = StorefrontTaxSummary.calculate(inputs);

      expect(summary.isValid, isFalse);
      expect(StorefrontTaxSummary.calculateGrossAmount(inputs), 3190);
    });

    test('does not invent a gross amount from unsafe monetary input', () {
      expect(
        StorefrontTaxSummary.calculateGrossAmount(const [
          StorefrontTaxLineInput(
            label: 'Precio fraccional',
            grossUnitPrice: 1000.5,
            quantity: 1,
            taxRate: null,
          ),
        ]),
        isNull,
      );
    });
  });

  test('CartProvider totals come from each product tax classification', () {
    final cart = CartProvider();
    cart.addProduct(_product(
      id: 'taxed',
      name: 'Producto afecto',
      price: 1190,
      taxRate: 19,
    ));
    cart.addProduct(
      _product(
        id: 'exempt',
        name: 'Producto exento',
        price: 500,
        taxRate: 0,
      ),
      quantity: 2,
    );

    expect(cart.hasValidTaxClassification, isTrue);
    expect(cart.total, 2190);
    expect(cart.subtotal, 2000);
    expect(cart.ivaAmount, 190);
  });

  test('CartProvider blocks an unclassified product without inventing IVA', () {
    final cart = CartProvider()
      ..addProduct(_product(
        id: 'missing',
        name: 'Producto sin tasa',
        price: 1000,
        taxRate: null,
      ));

    expect(cart.hasValidTaxClassification, isFalse);
    expect(cart.grossMerchandiseAmountClp, 1000);
    expect(cart.total, isNull);
    expect(cart.subtotal, isNull);
    expect(cart.ivaAmount, isNull);
    expect(cart.taxCheckoutBlockMessage, contains('Producto sin tasa'));
  });
}

Product _product({
  required String id,
  required String name,
  required double price,
  required double? taxRate,
}) {
  return Product(
    id: id,
    name: name,
    sku: id.toUpperCase(),
    price: price,
    cost: 0,
    stockQuantity: 20,
    category: ProductCategory.other,
    taxRate: taxRate,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );
}
