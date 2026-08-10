import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_product_review_workspace.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';

/// Contracts the owner set on 2026-08-09 for the reconciliation surface, after
/// rejecting both the card wall and the fixed-width `DataTable` that replaced
/// it. They are written as behaviour, not as a snapshot of the widget tree.
void main() {
  group('composición por ancho', () {
    testWidgets('escritorio: una fila por línea, todas del mismo alto',
        (tester) async {
      // Filas ordinarias: sin validación pendiente ni advertencia. Ésas son
      // las que tienen que quedar parejas para poder comparar una columna de
      // un vistazo; una fila que sí tiene un motivo que decir crece, y eso se
      // verifica aparte.
      final lines = <OcrProductReviewLine>[
        _line(id: 'l1', status: OcrProductReviewStatus.ready),
        _line(id: 'l2', status: OcrProductReviewStatus.ready),
        _line(id: 'l3', status: OcrProductReviewStatus.ready),
      ];
      await _pump(tester, size: const Size(1440, 900), lines: lines);

      expect(find.byKey(const Key('ocr-review-table')), findsOneWidget);
      expect(find.byKey(const Key('ocr-review-table-header')), findsOneWidget);

      final heights = <double>[
        for (final line in lines)
          tester
              .getSize(
                  find.byKey(ValueKey<String>('ocr-review-row-${line.id}')))
              .height,
      ];
      expect(heights.toSet(), hasLength(1),
          reason: 'las filas variables son el defecto rechazado');
    });

    testWidgets('escritorio: la tabla llena el ancho, sin scroll horizontal',
        (tester) async {
      await _pump(tester, size: const Size(1440, 900), lines: _threeLines());

      final table = tester.getSize(find.byKey(const Key('ocr-review-table')));
      // El host descuenta su padding lateral; lo que importa es que la tabla no
      // sea una lona fija más ancha que la ventana.
      expect(table.width, lessThanOrEqualTo(1440));
      expect(table.width, greaterThan(1200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet 834: mismas decisiones, columnas reducidas',
        (tester) async {
      await _pump(tester, size: const Size(834, 1112), lines: _threeLines());

      // 834 está bajo el umbral táctil: editor por línea, no tabla encogida.
      expect(find.byKey(const Key('ocr-review-table')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('ocr-review-row-l1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ocr-review-sku-l1')), findsOneWidget);
      expect(find.byKey(const Key('ocr-review-category-l1')), findsOneWidget);
    });

    testWidgets('phone 390: sin scroll horizontal y con objetivos táctiles',
        (tester) async {
      await _pump(tester, size: const Size(390, 844), lines: _threeLines());

      expect(tester.takeException(), isNull);
      final checkbox = tester.getSize(
        find.byKey(const Key('ocr-review-select-l1')),
      );
      expect(checkbox.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    });
  });

  group('categoría y marca', () {
    testWidgets('el selector cerrado dice el nombre corto, no la ruta',
        (tester) async {
      await _pump(tester, size: const Size(1440, 900), lines: _threeLines());

      expect(find.text('Tee'), findsWidgets);
      expect(
        find.textContaining('Componentes / Dirección'),
        findsNothing,
        reason: 'la ruta completa dentro del campo cerrado fue rechazada',
      );
    });

    testWidgets('es el selector canónico buscable, no una variante local',
        (tester) async {
      await _pump(tester, size: const Size(1440, 900), lines: _threeLines());

      expect(
        find.byType(VbSearchableSelect<Category>),
        findsNWidgets(3),
      );
      expect(
        find.byType(VbSearchableSelect<ProductBrand>),
        findsNWidgets(3),
      );
    });

    testWidgets('la ruta aparece dentro de resultados que comparten nombre',
        (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            categories: _ambiguousCategories,
          ),
        ],
        callbacks: OcrProductReviewCallbacks(onCategoryChanged: (_, __) {}),
      );

      await tester.tap(find.byKey(const Key('ocr-review-category-l1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Adaptadores'), findsWidgets);
      expect(find.text('Accesorios / Adaptadores'), findsOneWidget);
      expect(find.text('Componentes / Frenos / Adaptadores'), findsOneWidget);
      // Un nombre único no arrastra su ruta al resultado.
      expect(find.text('Componentes / Dirección / Tee'), findsNothing);
    });

    testWidgets('se puede buscar y elegir con teclado', (tester) async {
      Category? chosen;
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.ready),
        ],
        callbacks: OcrProductReviewCallbacks(
          onCategoryChanged: (_, value) => chosen = value,
        ),
      );

      await tester.tap(find.byKey(const Key('ocr-review-category-l1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextField).last, 'rotor');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(chosen?.name, 'Rotores');
    });
  });

  group('decisión de la fila', () {
    testWidgets('los parecidos no se expanden dentro de la fila',
        (tester) async {
      var opened = <String>[];
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            candidates: _candidates(3),
          ),
        ],
        callbacks: OcrProductReviewCallbacks(
          onOpenCandidates: opened.add,
        ),
      );

      final before = tester
          .getSize(find.byKey(const ValueKey<String>('ocr-review-row-l1')));
      await tester.tap(find.byKey(const Key('ocr-review-alternatives-l1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final after = tester
          .getSize(find.byKey(const ValueKey<String>('ocr-review-row-l1')));

      expect(opened, <String>['l1'], reason: 'abre el overlay centrado');
      expect(after.height, before.height,
          reason: 'la fila no crece: nada se despliega dentro');
    });

    testWidgets('vincular y crear nuevo son decisiones pares en la fila',
        (tester) async {
      Product? linked;
      String? created;
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            candidates: _candidates(2),
          ),
        ],
        callbacks: OcrProductReviewCallbacks(
          onLinkCandidate: (_, product) => linked = product,
          onConfirmNewProduct: (lineId) => created = lineId,
        ),
      );

      await tester.tap(find.byKey(const Key('ocr-review-link-l1')));
      await tester.pump();
      expect(linked?.sku, 'AE0001');

      await tester.tap(find.byKey(const Key('ocr-review-new-l1')));
      await tester.pump();
      expect(created, 'l1');
    });

    testWidgets('sin coincidencia se dice, no se rellena', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.noCandidates),
        ],
      );

      expect(find.text('Sin coincidencia fiable'), findsOneWidget);
      expect(find.byKey(const Key('ocr-review-new-l1')), findsOneWidget);
    });

    testWidgets('ningún porcentaje aparece junto a un producto',
        (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            candidates: _candidates(3),
          ),
        ],
      );

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .toList();
      expect(
        texts.where((value) => RegExp(r'\d+\s*%').hasMatch(value)),
        isEmpty,
      );
    });
  });

  group('pie de página', () {
    testWidgets('dice el siguiente paso exacto', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.ready),
          _line(id: 'l2', status: OcrProductReviewStatus.linked),
        ],
      );

      expect(
        find.textContaining('Decide 1 línea'),
        findsOneWidget,
      );
    });

    testWidgets('todo decidido cambia la frase', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.linked),
          _line(id: 'l2', status: OcrProductReviewStatus.newProductReady),
        ],
      );

      expect(find.textContaining('Todo decidido'), findsOneWidget);
    });
  });

  group('anchos locales sin desbordes', () {
    for (final width in const <double>[
      900,
      950,
      1001,
      1080,
      1179,
      1180,
      1440
    ]) {
      testWidgets('$width px compone sin desbordar', (tester) async {
        await _pump(
          tester,
          size: Size(width, 900),
          lines: _threeLines(),
          callbacks: const OcrProductReviewCallbacks(),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'ningún RenderFlex puede desbordar a $width px',
        );
      });
    }

    testWidgets('la tabla elige columnas según el ancho real que recibe',
        (tester) async {
      await _pump(tester, size: const Size(950, 900), lines: _threeLines());
      // A 950 px no cabe la columna de precio; la decisión y la categoría sí.
      expect(find.byKey(const Key('ocr-review-table')), findsOneWidget);
      expect(find.text('Precio'), findsNothing);
      expect(find.text('Decisión'), findsOneWidget);
      expect(find.text('Categoría'), findsOneWidget);

      await _pump(tester, size: const Size(1440, 900), lines: _threeLines());
      expect(find.text('Precio'), findsOneWidget);
      expect(find.text('Vende'), findsOneWidget);
    });
  });

  group('validaciones visibles', () {
    testWidgets('una fila con categoría faltante crece y muestra el motivo',
        (tester) async {
      final withError = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        categoryValidationMessage: 'Falta elegir la familia correcta.',
        category: null,
      );
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          withError,
          _line(id: 'l2', status: OcrProductReviewStatus.ready),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Falta elegir la familia correcta.'), findsOneWidget);

      final tall = tester
          .getSize(find.byKey(const ValueKey<String>('ocr-review-row-l1')))
          .height;
      final normal = tester
          .getSize(find.byKey(const ValueKey<String>('ocr-review-row-l2')))
          .height;
      expect(
        tall,
        greaterThan(normal),
        reason:
            'el motivo del bloqueo no se recorta para dejar la tabla pareja',
      );
    });

    testWidgets('la advertencia de marca sin evidencia también se lee',
        (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            brandWarning: 'La marca sugerida no tiene evidencia de fabricante.',
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('La marca sugerida no tiene evidencia de fabricante.'),
        findsOneWidget,
      );
    });

    testWidgets('una hoja duplicada dice su rama después de elegirla',
        (tester) async {
      final ambiguous = _ambiguousCategories.firstWhere(
        (category) => category.fullPath == 'Accesorios / Adaptadores',
      );
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            categories: _ambiguousCategories,
            category: ambiguous,
          ),
        ],
      );

      // El campo cerrado sigue diciendo el nombre corto…
      expect(find.text('Adaptadores'), findsOneWidget);
      // …y la rama que lo desambigua se publica al lado, no dentro del valor.
      expect(find.text('en Accesorios'), findsOneWidget);
      expect(find.text('Accesorios / Adaptadores'), findsNothing);
    });

    testWidgets('una hoja única no arrastra su rama', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.ready),
        ],
      );
      expect(find.textContaining('en Componentes'), findsNothing);
    });
  });

  group('el SKU reservado se cuenta en la fila', () {
    testWidgets('mientras reserva, la celda lo dice', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.newProductReady,
            isReservingSku: true,
          ),
        ],
      );

      expect(
        find.byKey(const Key('ocr-review-sku-reserving-l1')),
        findsOneWidget,
      );
      expect(find.text('Reservando…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si falla, lo dice y ofrece reintentar', (tester) async {
      final retried = <String>[];
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.newProductReady,
            skuErrorMessage: 'No se pudo reservar el SKU. Reintenta.',
          ),
        ],
        callbacks: OcrProductReviewCallbacks(
          onRetrySkuReservation: retried.add,
        ),
      );

      expect(
          find.text('No se pudo reservar el SKU. Reintenta.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocr-review-sku-retry-l1')));
      await tester.pump();
      expect(retried, <String>['l1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin reserva pendiente, la celda es editable', (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(id: 'l1', status: OcrProductReviewStatus.ready),
        ],
      );
      expect(find.byKey(const Key('ocr-review-sku-l1')), findsOneWidget);
      expect(
          find.byKey(const Key('ocr-review-sku-reserving-l1')), findsNothing);
    });

    testWidgets('un código que da la base se muestra, no se edita',
        (tester) async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.newProductReady,
            skuIsReadOnly: true,
          ),
        ],
      );

      // No text field: a number the database owns cannot be typed over, and a
      // field that looks editable invites exactly that.
      expect(find.byKey(const Key('ocr-review-sku-l1')), findsNothing);
      expect(
        find.byKey(const Key('ocr-review-sku-readonly-l1')),
        findsOneWidget,
      );
      expect(find.text('AE0137'), findsWidgets);
    });

    testWidgets('mientras reserva, la fila no acepta otra decisión',
        (tester) async {
      final linked = <String>[];
      final created = <String>[];
      await _pump(
        tester,
        size: const Size(1440, 900),
        lines: <OcrProductReviewLine>[
          _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            isReservingSku: true,
          ),
        ],
        callbacks: OcrProductReviewCallbacks(
          onLinkCandidate: (id, _) => linked.add(id),
          onConfirmNewProduct: created.add,
        ),
      );

      for (final key in const <String>[
        'ocr-review-link-l1',
        'ocr-review-new-l1',
      ]) {
        final finder = find.byKey(Key(key));
        if (finder.evaluate().isEmpty) continue;
        await tester.tap(finder, warnIfMissed: false);
        await tester.pump();
      }
      expect(linked, isEmpty);
      expect(created, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('modo oscuro no rompe la composición', (tester) async {
    await _pump(
      tester,
      size: const Size(1440, 900),
      lines: _threeLines(),
      dark: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ocr-review-table')), findsOneWidget);
  });
}

// ── helpers ───────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required List<OcrProductReviewLine> lines,
  OcrProductReviewCallbacks callbacks = const OcrProductReviewCallbacks(),
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Scaffold(
        body: OcrProductReviewWorkspace(
          lines: lines,
          callbacks: callbacks,
          primaryLabel: 'Crear productos',
          pricingPolicyLabel: 'Precio sugerido = costo × 2',
        ),
      ),
    ),
  );
  // `pumpAndSettle` never returns here on purpose: a line that is still
  // searching shows a real indeterminate spinner. Settle a couple of frames
  // instead of waiting for an animation that is not supposed to end.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

final _categories = <Category>[
  _category('Tee', 'Componentes / Dirección / Tee'),
  _category('Rotores', 'Componentes / Frenos / Rotores'),
  _category('Maza', 'Componentes / Ruedas / Mazas / Maza'),
];

final _ambiguousCategories = <Category>[
  ..._categories,
  _category('Adaptadores', 'Accesorios / Adaptadores'),
  _category('Adaptadores', 'Componentes / Frenos / Adaptadores'),
];

Category _category(String name, String fullPath) => Category(
      id: fullPath,
      tenantId: 'tenant-test',
      name: name,
      fullPath: fullPath,
    );

final _brands = <ProductBrand>[
  ProductBrand(id: 'b1', tenantId: 'tenant-test', name: 'Wake'),
  ProductBrand(id: 'b2', tenantId: 'tenant-test', name: 'Shimano'),
];

List<OcrProductReviewLine> _threeLines() => <OcrProductReviewLine>[
      _line(id: 'l1', status: OcrProductReviewStatus.ready),
      _line(id: 'l2', status: OcrProductReviewStatus.searching),
      _line(id: 'l3', status: OcrProductReviewStatus.linked),
    ];

OcrProductReviewLine _line({
  required String id,
  required OcrProductReviewStatus status,
  List<ProductDuplicateCandidate> candidates = const [],
  List<Category>? categories,
  Category? category,
  String? categoryValidationMessage,
  String? brandWarning,
  bool isReservingSku = false,
  bool skuIsReadOnly = false,
  String? skuErrorMessage,
}) {
  return OcrProductReviewLine(
    id: id,
    sku: 'AE0${id.hashCode.abs() % 900 + 100}',
    originalTitle: 'WAKE-vástago ligero de aluminio 31,8mm',
    supplierCode: '1005007336672891',
    sourceQuantity: 1,
    controllers: OcrProductDraftControllers(
      sku: TextEditingController(text: 'AE0137'),
      name: TextEditingController(text: 'Tee WAKE 31.8mm'),
      cost: TextEditingController(text: '7172'),
      price: TextEditingController(text: '14300'),
    ),
    status: status,
    candidates: candidates.isEmpty && status == OcrProductReviewStatus.ready
        ? _candidates(1)
        : candidates,
    categories: categories ?? _categories,
    brands: _brands,
    category: categoryValidationMessage != null
        ? category
        : (category ?? (categories ?? _categories).first),
    brand: _brands.first,
    categoryValidationMessage: categoryValidationMessage,
    brandWarning: brandWarning,
    isReservingSku: isReservingSku,
    skuIsReadOnly: skuIsReadOnly,
    skuErrorMessage: skuErrorMessage,
    resolvedProductName: 'Tee Aluminio Wake MTB 31.8MM Rojo',
    resolvedProductSku: 'AE0137',
  );
}

List<ProductDuplicateCandidate> _candidates(int count) {
  return <ProductDuplicateCandidate>[
    for (var index = 0; index < count; index++)
      ProductDuplicateCandidate(
        product: Product(
          id: 'p$index',
          tenantId: 'tenant-test',
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
