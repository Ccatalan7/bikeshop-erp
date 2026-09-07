import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_candidate_picker.dart';

void main() {
  testWidgets('muestra el contexto de la línea que se está decidiendo',
      (tester) async {
    await _open(tester, candidates: _candidates(2));

    expect(find.text('Comparar productos'), findsOneWidget);
    expect(find.text('Tee WAKE 31.8mm'), findsOneWidget);
    expect(find.textContaining('Código 1005007336672891'), findsOneWidget);

    final shellSize = tester.getSize(
      find.byKey(const Key('ocr-candidate-picker-shell')),
    );
    expect(shellSize.width, greaterThan(1000));
    expect(shellSize.height, greaterThan(800));
  });

  testWidgets('cada opción trae imagen, SKU, marca, categoría y evidencia',
      (tester) async {
    await _open(tester, candidates: _candidates(2));

    expect(find.textContaining('AE0001 · Wake · Tee'), findsOneWidget);
    expect(find.textContaining('Diámetro de abrazadera 31.8mm'), findsWidgets);
    expect(find.textContaining('Otro color'), findsOneWidget);
  });

  testWidgets(
      'amplía la fuente y recorre candidatos sin cerrar ni decidir el picker',
      (tester) async {
    await _open(
      tester,
      candidates: _candidates(2, withImages: true),
      lineImageUrl: 'https://example.com/invoice-source.jpg',
    );

    await tester.tap(
      find.byKey(const Key('ocr-candidate-source-image')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(
      find.byKey(const Key('ocr-comparison-image-viewer')),
      findsOneWidget,
    );
    final imageDialog = tester.widget<Dialog>(
      find.byKey(const Key('ocr-comparison-image-viewer')),
    );
    expect(imageDialog.insetPadding, isNot(EdgeInsets.zero),
        reason: 'la imagen se abre sobre el picker, no como otra página');
    expect(find.text('Imagen de la factura'), findsOneWidget);

    final canvasSize = tester.getSize(
      find.byKey(
        const ValueKey<String>('ocr-comparison-image-canvas-source'),
      ),
    );
    expect(canvasSize.width, greaterThan(1000));
    expect(canvasSize.height, greaterThan(700),
        reason: 'la imagen debe ajustarse al área útil, no a su tamaño nativo');

    await tester.tap(find.byKey(const Key('ocr-comparison-image-next')));
    await tester.pump();

    expect(
      find.text('Tee Aluminio Wake MTB 31.8MM Rojo'),
      findsWidgets,
    );

    await tester.tap(find.byKey(const Key('ocr-comparison-image-close')));
    await tester.pump();

    expect(find.text('Comparar productos'), findsOneWidget);
    expect(find.text('Seleccionar producto'), findsWidgets);
  });

  testWidgets('elegir uno devuelve ese producto', (tester) async {
    final decision = await _open(tester, candidates: _candidates(2));
    await tester.tap(find.text('Seleccionar producto').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect((await decision) is OcrCandidateLink, isTrue);
  });

  testWidgets('identity selection does not start an AI-proposed decomposition',
      (tester) async {
    final decision = await _open(tester,
        candidates: _candidates(2),
        aiCompositeProposal: '1 delantero + 1 trasero',
        allowComposition: false);
    await tester.tap(find.text('Seleccionar producto').first);
    await tester.pumpAndSettle();
    final result = await decision;
    expect(result, isA<OcrCandidateLink>());
    expect((result as OcrCandidateLink).product.id, 'p0');
  });

  testWidgets('«ninguno» pide producto nuevo', (tester) async {
    final decision = await _open(tester, candidates: _candidates(1));
    await tester.tap(find.byKey(const Key('ocr-candidate-create-new')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect((await decision) is OcrCandidateCreateNew, isTrue);
  });

  testWidgets('la X cierra sin decidir', (tester) async {
    final decision = await _open(tester, candidates: _candidates(1));
    await tester.tap(find.byKey(const Key('ocr-candidate-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(await decision, isNull);
  });

  testWidgets('sin candidatos dice la verdad y no rellena', (tester) async {
    await _open(tester, candidates: const []);

    expect(find.text('Sin coincidencia fiable'), findsOneWidget);
    expect(find.text('Seleccionar producto'), findsNothing);
  });

  testWidgets('renderiza por separado los conflictos de categoría cacheados',
      (tester) async {
    final cached = _candidates(1);
    final conflict = _categoryConflictCandidate();

    await _open(
      tester,
      candidates: cached,
      categoryConflicts: [conflict],
    );

    expect(find.textContaining('Tee Aluminio Wake'), findsOneWidget);
    expect(
      find.byKey(const Key('ocr-candidate-category-conflicts-heading')),
      findsOneWidget,
    );
    expect(find.text('Maza ZTTO Boost 32H'), findsNothing);
    await tester
        .tap(find.byKey(const Key('ocr-candidate-category-conflicts-heading')));
    await tester.pump();
    expect(find.text('Maza ZTTO Boost 32H'), findsOneWidget);
    expect(
      find.textContaining('Revisa la categoría del producto antes de vincular'),
      findsOneWidget,
    );
  });

  testWidgets(
      'conserva el orden razonado por IA dentro de los conflictos de categoría',
      (tester) async {
    final hose = _categoryConflictCandidate(
      id: 'hose',
      sku: 'AE0013',
      name: 'Manguera Freno Hidráulico 1M',
      objection: 'Diferencia indicada por IA: misma pieza, pero 1 m ≠ 2,5 m.',
    );
    final oil = _categoryConflictCandidate(
      id: 'oil',
      sku: 'OIL',
      name: 'Aceite Mineral para Freno Hidráulico',
      objection: 'Diferencia indicada por IA: es líquido, no una manguera.',
    );

    await _open(
      tester,
      candidates: const <ProductDuplicateCandidate>[],
      categoryConflicts: <ProductDuplicateCandidate>[hose, oil],
    );

    final hoseFinder = find.text('Manguera Freno Hidráulico 1M');
    final oilFinder = find.text('Aceite Mineral para Freno Hidráulico');
    expect(hoseFinder, findsOneWidget);
    expect(oilFinder, findsOneWidget);
    expect(
      tester.getTopLeft(hoseFinder).dy,
      lessThan(tester.getTopLeft(oilFinder).dy),
    );
    expect(
        find.textContaining('misma pieza, pero 1 m ≠ 2,5 m'), findsOneWidget);
  });

  testWidgets('la propuesta composite no bloquea otras decisiones humanas',
      (tester) async {
    final manualQueries = <String>[];
    await _open(
      tester,
      candidates: _candidates(2),
      aiCompositeProposal:
          'La IA propone 2 productos del catálogo. Requiere confirmación.',
      onSearch: (query) async {
        manualQueries.add(query);
        return const <Product>[];
      },
    );

    expect(find.text('Descomposición propuesta'), findsOneWidget);
    expect(
      find.text(
        'La IA propone 2 productos del catálogo. Requiere confirmación.',
      ),
      findsOneWidget,
    );
    expect(find.text('Definir contenido de la compra'), findsOneWidget);
    expect(find.text('COMPRADO · contenido por definir'), findsOneWidget);
    expect(find.text('Aplicar y guardar regla'), findsNothing,
        reason: 'la regla se guarda una sola vez, en «Confirmar contenido»');
    expect(find.text('Añadir al contenido'), findsWidgets);
    expect(find.byKey(const Key('ocr-candidate-create-new')), findsOneWidget);
    expect(manualQueries, isEmpty,
        reason: 'abrir reutiliza la decisión; no ejecuta otra búsqueda');
  });

  testWidgets('un componente no vincula toda la línea: revisa unidades primero',
      (tester) async {
    final decision = await _open(
      tester,
      candidates: _candidates(2),
      aiCompositeProposal: 'La IA propone un conjunto; el operador decide.',
    );

    await tester.tap(find.text('Añadir al contenido').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
        find.byKey(const Key('ocr-candidate-picker-dialog')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('ocr-content-units-0')), '2');
    await tester.tap(find.byKey(const Key('ocr-candidate-review-content')));
    await tester.pumpAndSettle();
    final result = await decision;
    expect(result, isA<OcrCandidateDefineComposition>());
    final content = result as OcrCandidateDefineComposition;
    expect(content.items.single.catalogUnitsPerPurchase, 2);
    expect(content.items.single.product.id, _candidates(2).first.product.id);
  });

  testWidgets('confirma la descomposición sólo cuando el host la habilita',
      (tester) async {
    final decision = await _open(
      tester,
      candidates: _candidates(2),
      aiCompositeProposal:
          '3 compras → 3 × AE0145 · delantero + 3 × AE0144 · trasero',
      canConfirmCompositeProposal: true,
    );

    await tester.tap(
      find.byKey(const Key('ocr-candidate-confirm-composite')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(await decision, isA<OcrCandidateConfirmComposition>());
  });

  testWidgets('auditoría nunca permite confirmar una descomposición',
      (tester) async {
    await _open(
      tester,
      candidates: _candidates(2),
      aiCompositeProposal: '1 compra → 10 × OL03',
      canConfirmCompositeProposal: true,
      inspectionOnly: true,
    );

    expect(
      find.byKey(const Key('ocr-candidate-confirm-composite')),
      findsNothing,
    );
  });

  testWidgets('un fallo de identidad permite buscar pero no implica crear',
      (tester) async {
    await _open(
      tester,
      candidates: const <ProductDuplicateCandidate>[],
      allowCreateNew: false,
      errorMessage: 'La revisión falló. Reintenta o busca en inventario.',
      onSearch: (_) async => const <Product>[],
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('ocr-candidate-create-new')), findsNothing);
    expect(find.text('La revisión falló'), findsOneWidget);
  });

  testWidgets('nombra viables y descartados sin convertirlos en sugerencias',
      (tester) async {
    await _open(
      tester,
      candidates: <ProductDuplicateCandidate>[
        _candidates(1).single,
        _ruledOutCandidate(),
      ],
      categoryConflicts: [_categoryConflictCandidate()],
    );

    expect(find.text('1 viable'), findsOneWidget);
    expect(find.text('Ver 1 descartado y sus diferencias'), findsOneWidget);
    expect(
      find.text('1 producto en otra categoría'),
      findsOneWidget,
    );
    expect(find.textContaining('3 opciones'), findsNothing);
    expect(find.textContaining('3 sugerencias'), findsNothing);
  });

  testWidgets(
      'descartados requieren abrir sus diferencias y una elección explícita',
      (tester) async {
    final decision = await _open(tester,
        candidates: [_candidates(1).single, _ruledOutCandidate()]);
    final rejected = _ruledOutCandidate().product;
    expect(find.text(rejected.name), findsNothing);
    await tester.tap(find.byKey(const Key('ocr-candidate-ruled-out-heading')));
    await tester.pump();
    expect(find.text(rejected.name), findsOneWidget);
    expect(find.text('Seleccionar con diferencias'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(ValueKey('ocr-candidate-select-${rejected.id}')));
    await tester
        .tap(find.byKey(ValueKey('ocr-candidate-select-${rejected.id}')));
    await tester.pumpAndSettle();
    expect((await decision as OcrCandidateLink).product.id, rejected.id);
  });

  for (final size in [const Size(390, 844), const Size(834, 1112)]) {
    for (final dark in [false, true]) {
      testWidgets(
          'comparación $size dark=$dark con teclado conserva salida y búsqueda',
          (tester) async {
        await _open(tester,
            candidates: _candidates(3),
            size: size,
            dark: dark,
            onSearch: (_) async =>
                _candidates(1).map((candidate) => candidate.product).toList());
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), 'Tee');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final close =
            tester.getRect(find.byKey(const Key('ocr-candidate-close')));
        expect(close.right, lessThanOrEqualTo(size.width));
        await tester.tap(find.byKey(const Key('ocr-candidate-close')));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const Key('ocr-candidate-picker-dialog')), findsNothing);
      });
    }
  }

  test('fila y picker comparten una sola prioridad de candidatos', () {
    final ruledOut = _ruledOutCandidate();
    final viable = _candidates(1).single;

    final ordered = orderOcrCandidateChoices(<ProductDuplicateCandidate>[
      ruledOut,
      viable,
    ]);

    expect(ordered.first.product.id, viable.product.id);
    expect(ordered.last.product.id, ruledOut.product.id);
  });

  testWidgets('abrir conserva la lista cacheada y no dispara búsqueda manual',
      (tester) async {
    final queries = <String>[];

    await _open(
      tester,
      candidates: _candidates(1),
      onSearch: (query) async {
        queries.add(query);
        return const <Product>[];
      },
    );

    expect(queries, isEmpty);
    expect(find.textContaining('Tee Aluminio Wake'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.decoration?.hintText,
      'Buscar nombre, SKU o marca',
    );
  });

  testWidgets('la búsqueda manual en todo el catálogo reemplaza la lista',
      (tester) async {
    await _open(
      tester,
      candidates: _candidates(1),
      onSearch: (query) async => <Product>[
        Product(
          id: 'manual',
          tenantId: 't',
          sku: 'AE0999',
          name: 'Tee buscado a mano',
          price: 1,
          cost: 1,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField).first, 'tee');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Tee buscado a mano'), findsOneWidget);
  });

  testWidgets('un fallo de búsqueda se dice, no se traga', (tester) async {
    await _open(
      tester,
      candidates: _candidates(1),
      onSearch: (query) async => throw StateError('sin red'),
    );

    await tester.enterText(find.byType(TextField).first, 'tee');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('La búsqueda falló'), findsOneWidget);
  });

  testWidgets('mientras busca muestra su estado de carga', (tester) async {
    await _open(tester, candidates: const [], isLoading: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  group('la búsqueda manual es dueña de su generación', () {
    testWidgets('una respuesta vieja no pisa a una nueva', (tester) async {
      final completers = <String, Completer<List<Product>>>{};
      await _open(
        tester,
        candidates: _candidates(1),
        onSearch: (query) {
          final completer = Completer<List<Product>>();
          completers[query] = completer;
          return completer.future;
        },
      );

      await tester.enterText(find.byType(TextField).first, 'rot');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'rotor 160');
      await tester.pump(const Duration(milliseconds: 400));

      // La nueva contesta primero, la vieja después.
      completers['rotor 160']!.complete(<Product>[_named('Resultado nuevo')]);
      await tester.pump();
      completers['rot']!.complete(<Product>[_named('Resultado viejo')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Resultado nuevo'), findsOneWidget);
      expect(find.text('Resultado viejo'), findsNothing);
    });

    testWidgets('borrar la caja invalida lo que venía en camino',
        (tester) async {
      final completers = <String, Completer<List<Product>>>{};
      await _open(
        tester,
        candidates: _candidates(1),
        onSearch: (query) {
          final completer = Completer<List<Product>>();
          completers[query] = completer;
          return completer.future;
        },
      );

      await tester.enterText(find.byType(TextField).first, 'rotor');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      completers['rotor']!.complete(<Product>[_named('Llegó tarde')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Llegó tarde'), findsNothing);
      // Vuelve a lo que el matcher propuso, no a una lista vacía inventada.
      expect(find.textContaining('Tee Aluminio Wake'), findsOneWidget);
    });

    testWidgets('un fallo viejo no borra un resultado nuevo', (tester) async {
      final completers = <String, Completer<List<Product>>>{};
      await _open(
        tester,
        candidates: _candidates(1),
        onSearch: (query) {
          final completer = Completer<List<Product>>();
          completers[query] = completer;
          return completer.future;
        },
      );

      await tester.enterText(find.byType(TextField).first, 'ro');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'rotor');
      await tester.pump(const Duration(milliseconds: 400));

      completers['rotor']!.complete(<Product>[_named('Sigue vigente')]);
      await tester.pump();
      completers['ro']!.completeError(StateError('sin red'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Sigue vigente'), findsOneWidget);
      expect(find.text('La búsqueda falló'), findsNothing);
    });

    testWidgets('cerrar mientras busca no explota', (tester) async {
      final completers = <String, Completer<List<Product>>>{};
      final decision = await _open(
        tester,
        candidates: _candidates(1),
        onSearch: (query) {
          final completer = Completer<List<Product>>();
          completers[query] = completer;
          return completer.future;
        },
      );

      await tester.enterText(find.byType(TextField).first, 'rotor');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('ocr-candidate-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      completers['rotor']!.complete(<Product>[_named('Nadie lo espera')]);
      await tester.pump();

      expect(await decision, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ningún porcentaje aparece en el overlay', (tester) async {
    await _open(tester, candidates: _candidates(3));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '');
    expect(
      texts.where((value) => RegExp(r'\d+\s*%').hasMatch(value)),
      isEmpty,
    );
  });
}

Future<Future<OcrCandidateDecision?>> _open(
  WidgetTester tester, {
  required List<ProductDuplicateCandidate> candidates,
  List<ProductDuplicateCandidate> categoryConflicts = const [],
  String? aiCompositeProposal,
  bool canConfirmCompositeProposal = false,
  bool allowCreateNew = true,
  bool allowComposition = true,
  String? errorMessage,
  bool inspectionOnly = false,
  OcrCandidateSearch? onSearch,
  bool isLoading = false,
  String? lineImageUrl,
  Size size = const Size(1440, 900),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late Future<OcrCandidateDecision?> decision;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                decision = OcrCandidatePicker.show(
                  context,
                  line: OcrCandidateLineContext(
                    title: 'Tee WAKE 31.8mm',
                    supplierCode: '1005007336672891',
                    imageUrl: lineImageUrl,
                    quantity: 1,
                    unitCost: 7172,
                  ),
                  candidates: candidates,
                  categoryConflicts: categoryConflicts,
                  aiCompositeProposal: aiCompositeProposal,
                  canConfirmCompositeProposal: canConfirmCompositeProposal,
                  allowCreateNew: allowCreateNew,
                  allowComposition: allowComposition,
                  errorMessage: errorMessage,
                  inspectionOnly: inspectionOnly,
                  onSearch: onSearch,
                  isLoading: isLoading,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return decision;
}

List<ProductDuplicateCandidate> _candidates(
  int count, {
  bool withImages = false,
}) {
  return <ProductDuplicateCandidate>[
    for (var index = 0; index < count; index++)
      ProductDuplicateCandidate(
        product: Product(
          id: 'p$index',
          tenantId: 't',
          sku: 'AE000${index + 1}',
          name: 'Tee Aluminio Wake MTB 31.8MM ${index == 0 ? 'Rojo' : 'Negro'}',
          brand: 'Wake',
          categoryName: 'Tee',
          imageUrl:
              withImages ? 'https://example.com/candidate-$index.jpg' : null,
          price: 14300,
          cost: 7172,
        ),
        matchTier: index == 0
            ? ProductDuplicateMatchTier.strong
            : ProductDuplicateMatchTier.possible,
        confidence: 0.9 - index * 0.1,
        reasons: const ['Es tee', 'Diámetro de abrazadera 31.8mm'],
        objections: index == 0 ? const [] : const ['Otro color: negro'],
        gates: const [],
        variantMismatch: index != 0,
        hasProductImage: false,
      ),
  ];
}

Product _named(String name) => Product(
      id: name,
      tenantId: 't',
      sku: 'AE9999',
      name: name,
      price: 1,
      cost: 1,
    );

ProductDuplicateCandidate _categoryConflictCandidate({
  String id = 'category-conflict',
  String sku = 'AE0420',
  String name = 'Maza ZTTO Boost 32H',
  String objection = 'Archivada en Mazas',
}) =>
    ProductDuplicateCandidate(
      product: Product(
        id: id,
        tenantId: 't',
        sku: sku,
        name: name,
        brand: 'ZTTO',
        categoryName: 'Mazas',
        price: 24000,
        cost: 12000,
      ),
      matchTier: ProductDuplicateMatchTier.possible,
      confidence: 0.72,
      reasons: const ['Misma pieza'],
      objections: <String>[objection],
      gates: const [],
      variantMismatch: false,
      hasProductImage: false,
    );

ProductDuplicateCandidate _ruledOutCandidate() => ProductDuplicateCandidate(
      product: Product(
        id: 'ruled-out',
        tenantId: 't',
        sku: 'AE0700',
        name: 'Tee ZTTO 35mm',
        brand: 'ZTTO',
        categoryName: 'Tee',
        price: 18000,
        cost: 9000,
      ),
      matchTier: ProductDuplicateMatchTier.ruledOut,
      confidence: 0.4,
      reasons: const ['Es tee'],
      objections: const ['Diámetro distinto: 31.8 ≠ 35'],
      gates: const [],
      variantMismatch: false,
      hasProductImage: false,
    );
