import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El inspector de candidato, como superficie.
///
/// Cada prueba muerde un defecto encontrado con la app real delante, no una
/// preferencia: la unidad inventada, el dinero disfrazado de peso, la cifra
/// repetida con dos nombres y el par de métricas con dos tamaños.
PurchaseCandidate _candidate({
  String id = 'cand-1',
  String name = 'Cambio Saiguan HG43A Index Apernado',
  String supplier = 'Comercial Ciclo',
  String currency = 'CLP',
  double? cost = 3490,
  String? gama = 'economica',
  bool gamaIsConfident = true,
  int purchaseCount = 4,
  String? lastPurchaseAt = '2026-03-29T12:00:00Z',
}) {
  return PurchaseCandidate.fromJson({
    'candidateId': id,
    'rank': 1,
    'productId': 'prod-1',
    'productName': name,
    'productSku': 'SAI-HG43A',
    'brand': 'Saiguan',
    'gama': gama,
    'gamaIsConfident': gamaIsConfident,
    'category': 'Componentes / Cambios',
    'supplierId': 'sup-1',
    'supplierName': supplier,
    'supplierWebsite': 'https://comercialciclo.cl',
    'isConfirmedLocal': false,
    'supplierAvailability': 'unverified',
    'currency': currency,
    'latestLandedUnitCostNet': cost,
    'catalogSalePriceGross': 8400,
    'projectedGrossMarginRatio': 0.585,
    'purchaseCount': purchaseCount,
    'lastPurchaseAt': lastPurchaseAt,
    'evidenceAgeDays': 140,
    'evidenceQuality': 'complete',
    'freightEvidence': 'missing',
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required PurchaseCandidate candidate,
  double quantity = 5,
  String unitLabel = 'unidades',
  Brightness brightness = Brightness.light,
  bool alreadyInPlan = false,
  double paneWidth = 420,
  VoidCallback? onClose,
}) async {
  // El viewport de prueba es 800x600 por defecto y el ListView del inspector
  // virtualiza lo que queda fuera: sin agrandarlo, las secciones de más abajo
  // no existen en el árbol y no se pueden abrir.
  tester.view.physicalSize = Size(paneWidth + 40, 1700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        // Alto generoso a propósito: las cuatro secciones plegables caben sin
        // scroll, así una aserción de contenido no depende de desplazar.
        body: SizedBox(
          width: paneWidth,
          height: 1600,
          child: CandidateInspectorPanel(
            candidate: candidate,
            quantity: quantity,
            unitLabel: unitLabel,
            adding: false,
            alreadyInPlan: alreadyInPlan,
            onClose: onClose ?? () {},
            onAddToPlan: () {},
            onOpenSupplier: () {},
          ),
        ),
      ),
    ),
  );
}

/// Abre todas las secciones plegables para poder afirmar sobre su contenido.
Future<void> _expandAll(WidgetTester tester) async {
  for (final title in const [
    'Cumplimiento y compatibilidad',
    'Desglose de costo y flete',
    'Por qué aparece aquí',
    'Historial y evidencia',
  ]) {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }
}

void main() {
  // La escala del asistente resuelve sus familias con `google_fonts`. En las
  // pruebas se prohíbe la descarga en tiempo de ejecución: sin esto el
  // resultado dependería de la red y del caché de la máquina, que es
  // exactamente lo contrario de una regresión.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('el total usa la unidad real de la necesidad, no «u.»',
      (tester) async {
    await _pump(tester,
        candidate: _candidate(), quantity: 2, unitLabel: 'pares');

    expect(find.text('TOTAL POR 2 PARES'), findsOneWidget);
    expect(find.textContaining('U.'), findsNothing);
  });

  testWidgets('un juego en singular tampoco se pluraliza acá', (tester) async {
    await _pump(tester,
        candidate: _candidate(), quantity: 1, unitLabel: 'juego');

    expect(find.text('TOTAL POR 1 JUEGO'), findsOneWidget);
  });

  testWidgets('el total en CLP multiplica y se escribe como peso',
      (tester) async {
    await _pump(tester, candidate: _candidate(cost: 3490), quantity: 5);

    // 3.490 × 5 = 17.450, con el formato canónico del ERP.
    expect(find.text('\$17.450'), findsOneWidget);
  });

  testWidgets('una moneda distinta se dice, nunca se disfraza de peso',
      (tester) async {
    await _pump(
      tester,
      candidate: _candidate(currency: 'USD', cost: 12.5),
      quantity: 2,
    );
    await _expandAll(tester);

    // Métrica grande, costo unitario y total: los tres con el código visible.
    expect(find.text('USD 12.50'), findsNWidgets(2));
    expect(find.text('USD 25.00'), findsOneWidget);
    // Ni un solo signo de peso para un candidato que no está en pesos.
    expect(find.textContaining('\$'), findsNothing);
    expect(find.text('sin convertir'), findsOneWidget);
  });

  testWidgets('sin costo aterrizado no se inventa un total', (tester) async {
    await _pump(tester, candidate: _candidate(cost: null));

    expect(find.text('sin evaluar'), findsWidgets);
    expect(find.textContaining('\$'), findsNothing);
  });

  testWidgets(
      'el conteo de compras aparece una sola vez, donde explica el orden',
      (tester) async {
    await _pump(tester, candidate: _candidate(purchaseCount: 4));
    await _expandAll(tester);

    expect(find.text('Compras observadas'), findsOneWidget);
    expect(
      find.text('Veces compradas'),
      findsNothing,
      reason: 'la misma cifra con dos nombres es ruido',
    );
    // Historial conserva la fecha exacta: «hace 140 días» es relativo.
    expect(find.text('Última compra'), findsOneWidget);
    expect(find.text('29 mar 2026'), findsOneWidget);
  });

  testWidgets('sin fecha de compra se dice, no se deja en blanco',
      (tester) async {
    await _pump(tester, candidate: _candidate(lastPurchaseAt: null));
    await _expandAll(tester);

    expect(find.text('sin registro'), findsOneWidget);
  });

  testWidgets('la marca no se repite entre secciones', (tester) async {
    await _pump(tester, candidate: _candidate());
    await _expandAll(tester);

    expect(find.text('Marca'), findsOneWidget);
  });

  testWidgets('la banda de gama poco firme se matiza con palabras',
      (tester) async {
    await _pump(
      tester,
      candidate: _candidate(gama: 'economica', gamaIsConfident: false),
    );
    await _expandAll(tester);

    expect(find.text('Económica · pocas compras de la marca'), findsOneWidget);
  });

  testWidgets('una banda firme se muestra sin reservas', (tester) async {
    await _pump(tester, candidate: _candidate(gamaIsConfident: true));
    await _expandAll(tester);

    expect(find.text('Económica'), findsOneWidget);
  });

  testWidgets('sin banda derivada lo dice en vez de fingir una',
      (tester) async {
    await _pump(tester, candidate: _candidate(gama: null));
    await _expandAll(tester);

    expect(find.text('Sin banda aún'), findsOneWidget);
  });

  testWidgets('las dos métricas grandes comparten tamaño', (tester) async {
    await _pump(tester, candidate: _candidate(cost: 3490));

    final costo = tester.widget<Text>(find.text('\$3.490'));
    final margen = tester.widget<Text>(find.text('58.5%'));

    expect(
      costo.style?.fontSize,
      margen.style?.fontSize,
      reason: 'un par de cifras comparables no puede tener dos tamaños',
    );
    expect(costo.style?.fontSize, 21, reason: 'metric_lg del handoff');
  });

  testWidgets('cerrar entrega el control a quien montó el panel',
      (tester) async {
    var closed = 0;
    await _pump(tester, candidate: _candidate(), onClose: () => closed++);

    await tester.tap(find.byKey(const ValueKey('close-candidate-inspector')));
    await tester.pump();

    expect(closed, 1);
  });

  testWidgets('un candidato ya en el plan se rotula corto y no se re-agrega',
      (tester) async {
    // El rótulo de estado era «Ya está en el plan» y estiraba el botón hasta
    // desbordar la fila del pie. Un estado se rotula corto; el layout no se
    // reorganiza para acomodar una frase larga.
    await _pump(
      tester,
      candidate: _candidate(),
      alreadyInPlan: true,
      paneWidth: 600,
    );

    expect(find.text('En el plan'), findsOneWidget);
    expect(find.text('Ya está en el plan'), findsNothing);
    expect(find.text('Agregar al plan'), findsNothing);
  });

  /// El pie es una fila: alternativa a la izquierda, acción principal a la
  /// derecha, ambas en la misma línea.
  ///
  /// Se afirma la **relación**, que es cierta en cualquier fuente. No se afirma
  /// que quepa en un ancho concreto, y **no se acepta ningún desborde**: medir
  /// anchos aquí no dice nada del resultado real, porque `PurchaseType` pide
  /// Poppins / IBM Plex por nombre y el proyecto sólo declara Oswald y Barlow,
  /// así que la familia cae a un fallback distinto en cada entorno. Que la fila
  /// entre en 330–420 se verifica en la app, con su frame.
  void expectFooterRow(WidgetTester tester) {
    final secondary = tester.getRect(find.text('Abrir proveedor'));
    final primary = tester.getRect(
      find.byKey(const ValueKey('add-candidate-to-plan')),
    );

    expect(tester.takeException(), isNull);
    expect(
      secondary.center.dy,
      moreOrLessEquals(primary.center.dy, epsilon: 1),
      reason: 'las dos acciones comparten línea',
    );
    expect(
      secondary.right <= primary.left,
      isTrue,
      reason: 'la alternativa queda a la izquierda de la principal',
    );
  }

  testWidgets('el pie mantiene su composición horizontal', (tester) async {
    await _pump(tester, candidate: _candidate(), paneWidth: 600);

    expectFooterRow(tester);
    final primary = tester.getRect(
      find.byKey(const ValueKey('add-candidate-to-plan')),
    );
    expect(primary.right <= 600, isTrue, reason: 'sin desborde');
  });

  testWidgets('el pie conserva la fila con el candidato ya agregado',
      (tester) async {
    await _pump(
      tester,
      candidate: _candidate(),
      alreadyInPlan: true,
      paneWidth: 600,
    );

    expectFooterRow(tester);
  });

  testWidgets('cambiar de candidato reemplaza todo el contenido del panel',
      (tester) async {
    // Con los datos reales de producción esta necesidad tiene UN solo
    // candidato, así que cambiar de candidato no es ejercitable contra la app.
    // La fixture cubre el contrato: el panel es del candidato que recibe y no
    // arrastra nada del anterior.
    await _pump(
      tester,
      candidate: _candidate(cost: 3490),
      paneWidth: 600,
    );
    await _expandAll(tester);
    expect(find.text('Cambio Saiguan HG43A Index Apernado'), findsOneWidget);
    expect(find.text('\$17.450'), findsOneWidget);

    await _pump(
      tester,
      candidate: _candidate(
        id: 'cand-2',
        name: 'Maza Trasera Novatec 32H',
        supplier: 'NMKR',
        cost: 9000,
        gama: 'alta',
      ),
      paneWidth: 600,
    );
    await tester.pumpAndSettle();

    expect(find.text('Maza Trasera Novatec 32H'), findsOneWidget);
    expect(find.text('NMKR'), findsOneWidget);
    expect(find.text('\$45.000'), findsOneWidget);
    expect(
      find.text('Cambio Saiguan HG43A Index Apernado'),
      findsNothing,
      reason: 'el panel no arrastra el candidato anterior',
    );
  });

  testWidgets('el panel se compone igual en oscuro', (tester) async {
    await _pump(
      tester,
      candidate: _candidate(),
      brightness: Brightness.dark,
    );
    await _expandAll(tester);

    expect(find.text('TOTAL POR 5 UNIDADES'), findsOneWidget);
    expect(find.text('\$17.450'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
