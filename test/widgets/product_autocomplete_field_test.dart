import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/widgets/product_autocomplete_field.dart';
import 'package:vinabike_erp/shared/widgets/smart_product_field.dart';

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

  testWidgets('deferred catalog stays idle until the field is opened',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final inventory = _RecordingInventoryService();
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryService>.value(
        value: inventory,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: ProductAutocompleteField(
                preloadCatalog: false,
                onProductSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(inventory.requests, isEmpty);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(inventory.requests, hasLength(1));
    expect(inventory.requests.single.query, isEmpty);
  });

  testWidgets(
    'compact deferred search stays closed until the query is useful',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final inventory = _RecordingInventoryService();
      await tester.pumpWidget(
        ChangeNotifierProvider<InventoryService>.value(
          value: inventory,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  child: ProductAutocompleteField(
                    autoFocus: true,
                    preloadCatalog: false,
                    minimumSearchCharacters: 2,
                    compactSuggestions: true,
                    onProductSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(inventory.requests, isEmpty);
      expect(find.text('Filtros:'), findsNothing);

      await tester.enterText(find.byType(TextField), 'p');
      await tester.pump(const Duration(milliseconds: 350));
      expect(inventory.requests, isEmpty);

      await tester.enterText(find.byType(TextField), 'pi');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(inventory.requests.single.query, 'pi');
      expect(find.text('Piñón de prueba'), findsOneWidget);
      expect(find.text('Filtros:'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    },
  );

  testWidgets('sale picker labels but allows child products from a set',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final inventory = _SetInventoryService();
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryService>.value(
        value: inventory,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: ProductAutocompleteField(
                onProductSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('Juego de frenos'), findsOneWidget);
    expect(find.text('Freno delantero'), findsOneWidget);
    expect(find.text('Pieza de juego'), findsOneWidget);
    expect(find.text('2 resultados'), findsOneWidget);
  });

  testWidgets('selected component keeps its piece-of-set label',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final inventory = _SetInventoryService();
    await tester.pumpWidget(
      ChangeNotifierProvider<InventoryService>.value(
        value: inventory,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: SmartProductField(
                onProductChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Freno delantero'));
    await tester.pumpAndSettle();

    expect(find.text('Pieza de juego'), findsOneWidget);
  });

  testWidgets('locked catalog identity keeps the normal description editor',
      (tester) async {
    final description = TextEditingController();
    addTearDown(description.dispose);
    final changes = <ProductFieldSelection?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: SmartProductField(
              initialData: ProductFieldData(
                product: _setComponent,
                productName: _setComponent.name,
                productSku: _setComponent.sku,
                isCatalogProduct: true,
              ),
              descriptionController: description,
              canChangeProduct: false,
              onProductChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Freno delantero'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Componente delantero');
    await tester.pump();

    expect(description.text, 'Componente delantero');
    expect(changes.single?.description, 'Componente delantero');
    expect(changes.single?.product?.id, _setComponent.id);
  });
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

class _SetInventoryService extends InventoryService {
  _SetInventoryService() : super(db: null);

  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 200,
    ProductType? productType,
  }) async {
    return [_setParent, _setComponent];
  }
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

final _setParent = Product(
  id: 'set-1',
  name: 'Juego de frenos',
  sku: 'SET-1',
  price: 30000,
  cost: 15000,
  stockQuantity: 1,
  category: ProductCategory.other,
  isSet: true,
  createdAt: _now,
  updatedAt: _now,
);

final _setComponent = Product(
  id: 'component-1',
  name: 'Freno delantero',
  sku: 'SET-1-FRONT',
  price: 15000,
  cost: 7500,
  stockQuantity: 1,
  category: ProductCategory.other,
  parentSetId: 'set-1',
  createdAt: _now,
  updatedAt: _now,
);
