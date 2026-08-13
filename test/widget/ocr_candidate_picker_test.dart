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

    expect(find.text('¿Cuál de estos es?'), findsOneWidget);
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
    expect(find.textContaining('Es tee'), findsWidgets);
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

    expect(find.text('¿Cuál de estos es?'), findsOneWidget);
    expect(find.text('Es este'), findsWidgets);
  });

  testWidgets('elegir uno devuelve ese producto', (tester) async {
    final decision = await _open(tester, candidates: _candidates(2));
    await tester.tap(find.text('Es este').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect((await decision) is OcrCandidateLink, isTrue);
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
    expect(find.text('Es este'), findsNothing);
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
    expect(find.text('Maza ZTTO Boost 32H'), findsOneWidget);
    expect(
      find.textContaining('Revisa la categoría del producto antes de vincular'),
      findsOneWidget,
    );
  });

  testWidgets('muestra la propuesta composite cacheada sin aplicarla',
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

    expect(find.text('Conjunto propuesto por IA'), findsOneWidget);
    expect(
      find.text(
        'La IA propone 2 productos del catálogo. Requiere confirmación.',
      ),
      findsOneWidget,
    );
    expect(find.text('¿Qué productos incluye esta línea?'), findsOneWidget);
    expect(find.text('Es este'), findsNothing);
    expect(find.byKey(const Key('ocr-candidate-create-new')), findsNothing);
    expect(manualQueries, isEmpty,
        reason: 'abrir reutiliza la decisión; no ejecuta otra búsqueda');
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
      onSearch: (_) async => const <Product>[],
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('ocr-candidate-create-new')), findsNothing);
    expect(find.textContaining('La revisión falló'), findsOneWidget);
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
    expect(find.text('1 descartado por una diferencia'), findsOneWidget);
    expect(
      find.text('1 producto del mismo tipo en otra categoría'),
      findsOneWidget,
    );
    expect(find.textContaining('3 opciones'), findsNothing);
    expect(find.textContaining('3 sugerencias'), findsNothing);
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
      'Buscar manualmente en todo el catálogo por nombre, SKU o marca',
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
  bool inspectionOnly = false,
  OcrCandidateSearch? onSearch,
  bool isLoading = false,
  String? lineImageUrl,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late Future<OcrCandidateDecision?> decision;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
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

ProductDuplicateCandidate _categoryConflictCandidate() =>
    ProductDuplicateCandidate(
      product: Product(
        id: 'category-conflict',
        tenantId: 't',
        sku: 'AE0420',
        name: 'Maza ZTTO Boost 32H',
        brand: 'ZTTO',
        categoryName: 'Mazas',
        price: 24000,
        cost: 12000,
      ),
      matchTier: ProductDuplicateMatchTier.possible,
      confidence: 0.72,
      reasons: const ['Misma pieza'],
      objections: const ['Archivada en Mazas'],
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
