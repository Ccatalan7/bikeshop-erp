import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_model_draft.dart';
import 'package:vinabike_erp/modules/inventory/services/product_model_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_model_section.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Modelo y variantes» en la ficha del producto (20261120230000): se lee y
/// se arma en la misma sección, sin diálogos; al agrupar, los nombres
/// sugieren el modelo, el color y la talla.
class _FakeService implements ProductModelService {
  _FakeService({this.model, this.candidateList = const []});

  ProductModel? model;
  List<ProductModelCandidate> candidateList;
  ProductModelDraft? saved;
  Object? failSave;
  String? deleted;

  @override
  Future<ProductModel?> fetchForProduct(String productId) async => model;

  @override
  Future<List<ProductModelCandidate>> candidates(
    String productId, {
    String? query,
    int limit = 12,
  }) async =>
      [
        for (final candidate in candidateList)
          if ((query ?? '').isEmpty ||
              candidate.name.toLowerCase().contains(query!.toLowerCase()))
            candidate,
      ];

  @override
  Future<ProductModel?> save(ProductModelDraft draft) async {
    final failure = failSave;
    if (failure != null) throw failure;
    saved = draft;
    return ProductModel(
      id: draft.id ?? 'm-new',
      name: draft.name,
      axes: draft.axes,
      members: draft.members,
      updatedAt: '2026-11-20T23:30:00+00:00',
    );
  }

  @override
  Future<void> delete(String modelId) async => deleted = modelId;
}

const _self = ProductModelMember(
  productId: 'b',
  name: 'Rodillera Leatt 3DF 5.0 Blanco/Negro S/M',
  sku: '6009699059461',
  price: 65990,
  stock: 0,
  onWebsite: true,
  options: {},
);

ProductModelCandidate _candidate(String id, String name, {String? taken}) =>
    ProductModelCandidate(
      productId: id,
      name: name,
      sku: 'SKU-$id',
      price: 65990,
      modelId: taken == null ? null : 'other',
      modelName: taken,
    );

Future<void> _pump(
  WidgetTester tester,
  _FakeService service, {
  List<String>? opened,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ProductModelSection(
            product: _self,
            service: service,
            onOpenProduct: (id) => opened?.add(id),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a loose product offers to group its sizes and colors', (
    tester,
  ) async {
    final service = _FakeService(
      candidateList: [
        _candidate('a', 'Rodillera Leatt 3DF 5.0 Blanco/Negro L/XL'),
        _candidate('c', 'Rodillera Leatt 3DF 5.0 Blanco/Negro XXL'),
        _candidate('d', 'Rodillera Leatt 3DF 5.0 Negra XXL'),
        _candidate('x', 'Rodillera Leatt AirFlex Pro Negra XL',
            taken: 'Rodillera Leatt AirFlex Pro Negra'),
      ],
    );
    await _pump(tester, service);

    expect(find.text('Agrupar tallas y colores'), findsOneWidget);
    await tester.tap(find.text('Agrupar tallas y colores'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Parecidos por nombre'), findsOneWidget);
    expect(
        find.textContaining('Ya está en «Rodillera Leatt AirFlex Pro Negra»'),
        findsOneWidget);
    expect(find.text('Crear modelo'), findsOneWidget);

    for (final name in const [
      'Rodillera Leatt 3DF 5.0 Blanco/Negro L/XL',
      'Rodillera Leatt 3DF 5.0 Blanco/Negro XXL',
      'Rodillera Leatt 3DF 5.0 Negra XXL',
    ]) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Row),
      );
      await tester
          .tap(find.descendant(of: row.first, matching: find.text('Agregar')));
      await tester.pumpAndSettle();
    }

    // Los nombres armaron el modelo solos.
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('product-model-name')),
    );
    expect(name.controller!.text, 'Rodillera Leatt 3DF 5.0');
    expect(find.text('Color'), findsWidgets);
    expect(find.text('Talla'), findsWidgets);

    await tester.tap(find.text('Crear modelo'));
    await tester.pumpAndSettle();

    final saved = service.saved!;
    expect(saved.name, 'Rodillera Leatt 3DF 5.0');
    expect([for (final m in saved.members) m.productId], ['b', 'a', 'c', 'd']);
    expect(
        saved.members.first.options, {'Color': 'Blanco/Negro', 'Talla': 'S/M'});
    // Guardado, la sección vuelve a leerse con sus variantes.
    expect(find.text('Rodillera Leatt 3DF 5.0'), findsOneWidget);
    expect(find.text('Esta ficha'), findsOneWidget);
    expect(find.textContaining('2 colores · 3 tallas'), findsOneWidget);
  });

  testWidgets('a grouped product lists its variants and opens the others', (
    tester,
  ) async {
    final opened = <String>[];
    final service = _FakeService(
      model: const ProductModel(
        id: 'm1',
        name: 'Rodillera Leatt 3DF 5.0',
        updatedAt: '2026-11-20T23:10:00+00:00',
        axes: [
          ProductModelAxis(name: 'Color', values: ['Blanco/Negro', 'Negra']),
          ProductModelAxis(name: 'Talla', values: ['S/M', 'XXL']),
        ],
        members: [
          ProductModelMember(
            productId: 'b',
            name: 'Rodillera Leatt 3DF 5.0 Blanco/Negro S/M',
            options: {'Color': 'Blanco/Negro', 'Talla': 'S/M'},
            onWebsite: true,
          ),
          ProductModelMember(
            productId: 'd',
            name: 'Rodillera Leatt 3DF 5.0 Negra XXL',
            options: {'Color': 'Negra', 'Talla': 'XXL'},
            stock: 2,
          ),
        ],
      ),
    );
    await _pump(tester, service, opened: opened);

    expect(find.text('Blanco/Negro · S/M'), findsOneWidget);
    expect(find.text('Esta ficha'), findsOneWidget);
    expect(find.textContaining('Fuera de la tienda'), findsOneWidget);
    await tester.tap(find.text('Negra · XXL'));
    expect(opened, ['d']);

    // Editar pone la misma sección en edición; un error se dice en palabras
    // del taller y no se pierde lo editado.
    await tester.tap(find.text('Editar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    service.failSave = const ProductModelException(
      'product_model_stale',
      'Otra persona cambió este modelo mientras lo editabas. Vuelve a '
          'abrirlo para ver lo último.',
    );
    await tester.tap(find.text('Guardar modelo'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Otra persona cambió este modelo'), findsOneWidget);
    expect(find.text('Guardar modelo'), findsOneWidget);

    // Desarmar pide confirmación en el mismo lugar.
    await tester.tap(find.text('Desarmar modelo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('quedan sueltos'), findsOneWidget);
    await tester.tap(find.text('Desarmar'));
    await tester.pumpAndSettle();
    expect(service.deleted, 'm1');
    expect(find.text('Agrupar tallas y colores'), findsOneWidget);
  });

  testWidgets('the section reads in dark too', (tester) async {
    final service = _FakeService();
    await _pump(tester, service, brightness: Brightness.dark);
    expect(find.text('Agrupar tallas y colores'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
