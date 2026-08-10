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
  });

  testWidgets('cada opción trae imagen, SKU, marca, categoría y evidencia',
      (tester) async {
    await _open(tester, candidates: _candidates(2));

    expect(find.textContaining('AE0001 · Wake · Tee'), findsOneWidget);
    expect(find.textContaining('Es tee'), findsWidgets);
    expect(find.textContaining('Otro color'), findsOneWidget);
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

  testWidgets('la búsqueda manual reemplaza la lista', (tester) async {
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
  OcrCandidateSearch? onSearch,
  bool isLoading = false,
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
                  line: const OcrCandidateLineContext(
                    title: 'Tee WAKE 31.8mm',
                    supplierCode: '1005007336672891',
                    quantity: 1,
                    unitCost: 7172,
                  ),
                  candidates: candidates,
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

List<ProductDuplicateCandidate> _candidates(int count) {
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
