import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_priority_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

PurchasePrioritySuggestion _suggestion({
  String entityId = 'need-a',
  String title = 'Pastillas ZTTO',
  String source = 'workshop',
  ProductMedia media = ProductMedia.empty,
  PurchasePriorityJobContext? jobContext,
  DateTime? signalAt,
}) {
  return PurchasePrioritySuggestion(
    rank: 1,
    source: source,
    entityId: entityId,
    productId: 'product-$entityId',
    title: title,
    suggestedQuantity: 1,
    unit: 'unit',
    reason: 'Un trabajo de taller lo está esperando',
    signalAt: signalAt,
    media: media,
    jobContext: jobContext,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<PurchasePrioritySuggestion> suggestions, {
  double width = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: PurchasePriorityPanel(
          suggestions: suggestions,
          selectedEntityIds: const {},
          onSelectionChanged: (_) {},
          onSearchSelected: () {},
          onTake: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

class _PriorityHarness extends StatefulWidget {
  const _PriorityHarness({required this.suggestions, required this.onSearch});

  final List<PurchasePrioritySuggestion> suggestions;
  final VoidCallback onSearch;

  @override
  State<_PriorityHarness> createState() => _PriorityHarnessState();
}

class _PriorityHarnessState extends State<_PriorityHarness> {
  Set<String> selected = const {};

  @override
  Widget build(BuildContext context) {
    return PurchasePriorityPanel(
      suggestions: widget.suggestions,
      selectedEntityIds: selected,
      onSelectionChanged: (value) => setState(() => selected = value),
      onSearchSelected: widget.onSearch,
      onTake: (_) {},
    );
  }
}

Future<void> _pumpHarness(
  WidgetTester tester,
  List<PurchasePrioritySuggestion> suggestions, {
  required VoidCallback onSearch,
  double width = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: _PriorityHarness(
          suggestions: suggestions,
          onSearch: onSearch,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('cada producto del feed muestra el tile de su ficha',
      (tester) async {
    await _pump(tester, [
      _suggestion(
        media: const ProductMedia(
          imageUrlOptimized: 'https://cdn/pastillas.webp',
        ),
      ),
    ]);

    final tile = tester.widget<ProductMediaTile>(
      find.byKey(const ValueKey('purchase-priority-media-need-a')),
    );
    expect(tile.media.primaryUrl, 'https://cdn/pastillas.webp');
    expect(tile.size, PurchaseSurfaceGeometry.mediaTableRow);
  });

  testWidgets('sin foto queda el monograma canónico, no un hueco',
      (tester) async {
    await _pump(tester, [_suggestion(title: 'Cámara Michelin')]);

    expect(
      find.byKey(const ValueKey('purchase-priority-media-need-a')),
      findsOneWidget,
    );
    expect(find.text(productMonogram('Cámara Michelin')), findsOneWidget);
  });

  testWidgets('la fila con foto no desborda en composición compacta',
      (tester) async {
    await _pump(
      tester,
      [_suggestion(title: 'Pastillas de freno hidráulico metálicas ZTTO')],
      width: 390,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('purchase-priority-media-need-a')),
      findsOneWidget,
    );
  });

  testWidgets('una necesidad de bicicleta muestra trabajo y bicicleta exactos',
      (tester) async {
    await _pump(tester, [
      _suggestion(
        jobContext: const PurchasePriorityJobContext(
          mechanicJobId: 'job-a',
          jobNumber: 'PG-00525',
          scope: 'bike',
          jobBikeId: 'job-bike-a',
          bikeId: 'bike-a',
          bikeBrand: 'Best',
          bikeModel: 'Otis 29',
        ),
      ),
    ]);

    expect(find.text('PG-00525'), findsOneWidget);
    expect(find.text('Best Otis 29'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('purchase-priority-job-need-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('purchase-priority-bike-need-a')),
      findsOneWidget,
    );
  });

  testWidgets('el alcance General se dice Todo el trabajo', (tester) async {
    await _pump(tester, [
      _suggestion(
        jobContext: const PurchasePriorityJobContext(
          mechanicJobId: 'job-a',
          jobNumber: 'PG-00525',
          scope: 'whole_job',
        ),
      ),
    ]);

    expect(find.text('PG-00525'), findsOneWidget);
    expect(find.text('Todo el trabajo'), findsOneWidget);
  });

  testWidgets('la tabla separa producto, trabajo, bicicleta, fecha y cantidad',
      (tester) async {
    await _pump(
        tester,
        [
          _suggestion(
            signalAt: DateTime(2026, 8, 24, 8, 16),
            jobContext: const PurchasePriorityJobContext(
              mechanicJobId: 'job-a',
              jobNumber: 'PG-00525',
              scope: 'bike',
              jobBikeId: 'job-bike-a',
              bikeId: 'bike-a',
              bikeBrand: 'Best',
              bikeModel: 'Otis 29',
            ),
          ),
        ],
        width: 600);

    for (final heading in const [
      'PRODUCTO',
      'TRABAJO',
      'BICICLETA',
      'INGRESADO',
      'CANT.',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.text('24/08/2026\n08:16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una señal automática no inventa trabajo ni fecha de ingreso',
      (tester) async {
    await _pump(tester, [
      _suggestion(
        entityId: 'stock-a',
        source: 'stockout',
        title: 'Neumático Maxxis',
        signalAt: DateTime(2026, 8, 24, 8, 16),
      ),
    ]);

    expect(find.text('Sin trabajo'), findsOneWidget);
    expect(find.text('No aplica'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('24/08/2026\n08:16'), findsNothing);
  });

  testWidgets('los checkbox arman una búsqueda conjunta sin ejecutar al marcar',
      (tester) async {
    var searches = 0;
    await _pumpHarness(
      tester,
      [
        _suggestion(entityId: 'need-a'),
        _suggestion(entityId: 'need-b', title: 'Disco G3'),
      ],
      onSearch: () => searches += 1,
    );

    await tester.tap(
      find.byKey(const ValueKey('purchase-priority-select-need-a')),
    );
    await tester.pump();
    expect(
        find.text(
            'Selecciona una fila más para buscar proveedores en conjunto.'),
        findsOneWidget);
    expect(searches, 0);

    await tester.tap(
      find.byKey(const ValueKey('purchase-priority-select-need-b')),
    );
    await tester.pump();
    expect(find.text('Buscar juntos (2)'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('purchase-priority-search-selected')),
    );
    await tester.pump();
    expect(searches, 1);
  });

  testWidgets('seleccionar visibles marca el lote completo', (tester) async {
    await _pumpHarness(
      tester,
      [
        _suggestion(entityId: 'need-a'),
        _suggestion(entityId: 'need-b'),
        _suggestion(entityId: 'need-c'),
      ],
      onSearch: () {},
    );

    await tester.tap(
      find.byKey(const ValueKey('purchase-priority-select-visible')),
    );
    await tester.pump();

    for (final id in const ['need-a', 'need-b', 'need-c']) {
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(ValueKey('purchase-priority-select-$id')),
            )
            .value,
        isTrue,
      );
    }
    expect(find.text('Buscar juntos (3)'), findsOneWidget);
  });

  testWidgets('la selección sobrevive al pasar de tabla a composición teléfono',
      (tester) async {
    await _pumpHarness(
      tester,
      [_suggestion(entityId: 'need-a')],
      onSearch: () {},
    );
    await tester.tap(
      find.byKey(const ValueKey('purchase-priority-select-need-a')),
    );
    await tester.pump();

    tester.view.physicalSize = const Size(599, 900);
    await tester.pump();

    expect(find.text('PRODUCTO'), findsNothing);
    expect(find.text('TRABAJO'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('purchase-priority-select-need-a')),
          )
          .value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
