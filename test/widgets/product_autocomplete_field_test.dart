import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/widgets/product_autocomplete_field.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'exclusive service filter queries the complete service catalog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final inventory = _RecordingInventoryService();
      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryService>.value(
          value: inventory,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 500,
                  child: ProductAutocompleteField(
                    onProductSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('2 resultados'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Productos'));
      await tester.pumpAndSettle();

      expect(inventory.requests.last.productType, ProductType.service);
      expect(find.text('3 resultados'), findsOneWidget);
      expect(find.text('Enrayado + Centrado'), findsOneWidget);
      expect(find.text('Limpieza de transmisión'), findsOneWidget);
      expect(find.text('Ajuste de frenos'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'frenos');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(inventory.requests.last.query, 'frenos');
      expect(inventory.requests.last.productType, ProductType.service);
    },
  );
}

class _RecordingInventoryService extends InventoryService {
  _RecordingInventoryService() : super(db: null);

  final requests = <_SearchRequest>[];

  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 200,
    ProductType? productType,
  }) async {
    requests.add(_SearchRequest(query, productType));
    if (productType == ProductType.service) {
      return [
        _service1,
        _service2,
        _service3,
      ];
    }
    return [_product, _service1];
  }
}

class _SearchRequest {
  const _SearchRequest(this.query, this.productType);

  final String query;
  final ProductType? productType;
}

final _now = DateTime(2026, 7, 16);

final _product = Product(
  id: 'product-1',
  name: 'Piñón de prueba',
  sku: 'P-1',
  price: 10000,
  cost: 5000,
  stockQuantity: 1,
  category: ProductCategory.other,
  createdAt: _now,
  updatedAt: _now,
);

final _service1 = Product(
  id: 'service-1',
  name: 'Enrayado + Centrado',
  sku: 'S-1',
  price: 22000,
  cost: 0,
  stockQuantity: 0,
  category: ProductCategory.other,
  productType: ProductType.service,
  createdAt: _now,
  updatedAt: _now,
);

final _service2 = Product(
  id: 'service-2',
  name: 'Limpieza de transmisión',
  sku: 'S-2',
  price: 5000,
  cost: 0,
  stockQuantity: 0,
  category: ProductCategory.other,
  productType: ProductType.service,
  createdAt: _now,
  updatedAt: _now,
);

final _service3 = Product(
  id: 'service-3',
  name: 'Ajuste de frenos',
  sku: 'S-3',
  price: 8000,
  cost: 0,
  stockQuantity: 0,
  category: ProductCategory.other,
  productType: ProductType.service,
  createdAt: _now,
  updatedAt: _now,
);
