import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El «Plan borrador» — grupo por proveedor y línea.
///
/// Estas pruebas se montan sobre datos fixture, nunca sobre el plan de
/// producción: crear líneas reales para mirar una pantalla ya costó una
/// limpieza y el dueño lo prohibió expresamente.
///
/// Lo que fijan es lo que se rompió de verdad en la app real:
/// la foto de la ficha, la forma de escribir plata, la separación entre
/// evidencia y subtotal, y que cada control de la línea se pueda alcanzar por
/// identidad y no por su posición.
PurchasePlanLine _line({
  String id = 'line-1',
  String name = 'Neumático 27,5 Maxxis',
  String supplier = 'NMKR',
  String currency = 'CLP',
  double quantity = 2,
  double? cost = 8725,
  double? margin = 0.42,
  ProductMedia media = ProductMedia.empty,
  String unit = 'unit',
  String? candidateId,
  String evidenceState = 'erp_purchase_history',
}) {
  return PurchasePlanLine(
    id: id,
    sourceNeedId: 'need-$id',
    candidateId: candidateId ??
        (evidenceState == 'erp_purchase_history' ? 'candidate-$id' : null),
    productId: 'product-$id',
    productName: name,
    supplierName: supplier,
    quantity: quantity,
    unit: unit,
    currency: currency,
    landedUnitCostNet: cost,
    projectedGrossMarginRatio: margin,
    supplierAvailability: 'unverified',
    evidenceState: evidenceState,
    media: media,
  );
}

PurchasePlanSupplierGroup _group({
  String supplier = 'NMKR',
  String currency = 'CLP',
  int lineCount = 1,
  double? subtotal = 17450,
}) {
  return PurchasePlanSupplierGroup.fromJson({
    'supplier_name': supplier,
    'currency_code': currency,
    'line_count': lineCount,
    'historical_landed_subtotal_net': subtotal,
  });
}

Future<void> _pump(
  WidgetTester tester,
  List<PurchasePlanLine> lines, {
  PurchasePlanSupplierGroup? group,
  double width = 900,
  Brightness brightness = Brightness.light,
  String? editingLineId,
  void Function(PurchasePlanLine line)? onRemove,
  void Function(PurchasePlanLine line, int quantity)? onStep,
  void Function(PurchasePlanLine line)? onEditQuantity,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: PurchasePlanGroup(
                group: group ??
                    _group(
                      supplier: lines.first.supplierName,
                      currency: lines.first.currency,
                      lineCount: lines.length,
                    ),
                lines: lines,
                removingLineId: null,
                updatingLineId: null,
                editingLineId: editingLineId,
                quantityController: TextEditingController(text: '2'),
                quantityError: null,
                onEditQuantity: onEditQuantity ?? (_) {},
                onCancelQuantity: () {},
                onCommitQuantity: (_) {},
                onStepQuantity: onStep ?? (_, __) {},
                onRemove: onRemove ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // La escala del asistente resuelve sus familias con `google_fonts`; en las
  // pruebas se prohíbe la descarga para que el resultado no dependa de la red.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('foto de la ficha', () {
    testWidgets('cada línea muestra su producto, no sólo su nombre',
        (tester) async {
      await _pump(tester, [
        _line(
          media: const ProductMedia(imageUrlOptimized: 'https://x/opt.webp'),
        ),
        _line(id: 'line-2', name: 'Cámara 27,5'),
      ]);

      expect(
          find.byKey(const ValueKey('plan-line-media-line-1')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('plan-line-media-line-2')), findsOneWidget);
    });

    testWidgets('sin imagen en la ficha queda el monograma, nunca un hueco',
        (tester) async {
      await _pump(tester, [_line(name: 'Cámara Michelin')]);

      final tile = tester.widget<ProductMediaTile>(
        find.byKey(const ValueKey('plan-line-media-line-1')),
      );
      expect(tile.media.hasImage, isFalse);
      // El monograma sale del nombre real: identifica la línea aunque la ficha
      // no tenga foto.
      expect(find.text(productMonogram('Cámara Michelin')), findsOneWidget);
    });

    testWidgets('la foto usa la geometría del contrato de imagen',
        (tester) async {
      await _pump(tester, [_line()]);

      final tile = tester.widget<ProductMediaTile>(
        find.byKey(const ValueKey('plan-line-media-line-1')),
      );
      expect(tile.size, PurchaseSurfaceGeometry.mediaTableRow);
    });
  });

  group('cómo se escribe la plata', () {
    testWidgets('el peso lleva signo y separador de miles', (tester) async {
      await _pump(tester, [_line(quantity: 2, cost: 8725)]);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-line-total-line-1')))
            .data,
        '\$17.450',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-line-unit-line-1')))
            .data,
        '\$8.725 c/u',
      );
      // Nunca la forma vieja, que no separaba miles.
      expect(find.text('CLP 17450'), findsNothing);
    });

    testWidgets('otra moneda se dice con su código y no se convierte',
        (tester) async {
      await _pump(tester, [
        _line(currency: 'USD', quantity: 3, cost: 12.5),
      ]);

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-line-total-line-1')))
            .data,
        'USD 37.50',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-line-unit-line-1')))
            .data,
        'USD 12.50 c/u',
      );
      expect(find.text('Subtotal mercadería USD'), findsOneWidget);
      // Ninguna cifra en dólares toma la forma de un peso.
      expect(find.textContaining('\$'), findsNothing);
    });

    testWidgets('sin costo aterrizado el total es una raya, no un cero',
        (tester) async {
      await _pump(tester, [_line(cost: null, margin: null)]);

      expect(find.text('—'), findsWidgets);
      expect(find.text('\$0'), findsNothing);
      expect(find.textContaining('c/u'), findsNothing);
    });
  });

  group('evidencia y subtotal no se pisan', () {
    testWidgets('la evidencia va con el proveedor y el subtotal en el pie',
        (tester) async {
      await _pump(tester, [_line(), _line(id: 'line-2', name: 'Cámara 27,5')]);

      final evidence = find.text('evidencia completa');
      final subtotal = find.text('Subtotal mercadería CLP');
      expect(evidence, findsWidgets);
      expect(subtotal, findsOneWidget);

      // El defecto real era que ambos compartían fila y salían pegados. Aquí
      // el subtotal vive estrictamente por debajo de la evidencia del grupo.
      final headerEvidence = tester.getRect(evidence.first);
      final footer = tester.getRect(subtotal);
      expect(footer.top, greaterThan(headerEvidence.bottom));
    });

    testWidgets('una línea sin costo deja el grupo en evidencia parcial',
        (tester) async {
      await _pump(tester, [
        _line(),
        _line(id: 'line-2', name: 'Cámara 27,5', cost: null, margin: null),
      ]);

      expect(find.text('evidencia parcial'), findsOneWidget);
      // Y el pie dice por qué el subtotal no cubre todo, en vez de mostrar una
      // cifra que se leería como el precio completo.
      expect(
        find.textContaining('cubre sólo las que sí lo tienen'),
        findsOneWidget,
      );
    });

    testWidgets('el pie conserva la advertencia de disponibilidad',
        (tester) async {
      await _pump(tester, [_line()]);

      // Vivía en la cabecera vieja («N productos · disponibilidad por
      // confirmar»). Al mudarse la composición no puede evaporarse: el
      // historial dice que se compró, nunca que hoy haya.
      expect(
        find.textContaining('disponibilidad del proveedor está por confirmar'),
        findsOneWidget,
      );
      expect(find.textContaining('Flete ya atribuido'), findsOneWidget);
    });

    testWidgets('el subtotal suma sólo las líneas con costo', (tester) async {
      await _pump(tester, [
        _line(quantity: 2, cost: 8725),
        _line(id: 'line-2', name: 'Cámara 27,5', cost: null, margin: null),
      ]);

      expect(find.text('\$17.450'), findsWidgets);
    });

    testWidgets('un grupo mixto cuenta lo que queda fuera del subtotal',
        (tester) async {
      await _pump(tester, [
        _line(quantity: 2, cost: 8725),
        _line(
          id: 'line-2',
          name: 'Cámara 29 Presta 60 mm',
          cost: null,
          margin: null,
          evidenceState: 'catalog_assignment',
        ),
      ]);

      expect(
        find.textContaining('1 línea está por cotizar y queda fuera'),
        findsOneWidget,
      );
      expect(find.textContaining('suma sólo las líneas'), findsOneWidget);
      expect(find.text('\$17.450'), findsWidgets);
    });
  });

  group('cada control de la línea tiene nombre propio', () {
    testWidgets('los cuatro controles se alcanzan por key', (tester) async {
      await _pump(tester, [_line()]);

      expect(find.byKey(const ValueKey('plan-line-line-1-decrease')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('plan-line-line-1-increase')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('plan-line-edit-quantity-line-1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('plan-line-remove-line-1')),
          findsOneWidget);
    });

    testWidgets('el rótulo accesible nombra el producto, no el icono',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_line(name: 'Neumático Maxxis')]);

      expect(
        find.bySemanticsLabel('Quitar Neumático Maxxis del plan'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Escribir la cantidad de Neumático Maxxis'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Agregar una unidad de Neumático Maxxis'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Quitar una unidad de Neumático Maxxis'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Evidencia de Neumático Maxxis'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('con dos líneas los rótulos siguen siendo distinguibles',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _line(name: 'Neumático Maxxis'),
        _line(id: 'line-2', name: 'Cámara Michelin'),
      ]);

      // Éste es el punto: antes las dos filas exponían «Quitar del plan» y no
      // había forma —ni para un lector de pantalla ni para app_control— de
      // decir cuál era cuál.
      expect(find.bySemanticsLabel('Quitar Neumático Maxxis del plan'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Quitar Cámara Michelin del plan'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('los controles hacen lo que dicen', (tester) async {
      final removed = <String>[];
      final stepped = <int>[];
      final edited = <String>[];
      await _pump(
        tester,
        [_line(quantity: 2)],
        onRemove: (line) => removed.add(line.id),
        onStep: (_, quantity) => stepped.add(quantity),
        onEditQuantity: (line) => edited.add(line.id),
      );

      await tester.tap(find.byKey(const ValueKey('plan-line-line-1-increase')));
      await tester.tap(find.byKey(const ValueKey('plan-line-line-1-decrease')));
      await tester
          .tap(find.byKey(const ValueKey('plan-line-edit-quantity-line-1')));
      await tester.tap(find.byKey(const ValueKey('plan-line-remove-line-1')));
      await tester.pump();

      expect(stepped, [3, 1]);
      expect(edited, ['line-1']);
      expect(removed, ['line-1']);
    });

    testWidgets('en el mínimo el botón se apaga y lo dice', (tester) async {
      final stepped = <int>[];
      await _pump(
        tester,
        [_line(quantity: 1)],
        onStep: (_, quantity) => stepped.add(quantity),
      );

      await tester.tap(
        find.byKey(const ValueKey('plan-line-line-1-decrease')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(stepped, isEmpty);
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('plan-line-line-1-decrease')),
      );
      expect(button.onPressed, isNull);
      expect(button.tooltip, 'Ya está en el mínimo');
    });

    testWidgets('la unidad se pluraliza con la cantidad', (tester) async {
      await _pump(tester, [_line(quantity: 1)]);
      expect(find.text('unidad'), findsOneWidget);

      await _pump(tester, [_line(quantity: 4)]);
      expect(find.text('unidades'), findsOneWidget);
    });
  });

  group('la fila reflowa sin romperse', () {
    for (final width in <double>[1200, 900, 700, 560, 430, 360]) {
      testWidgets('${width.toInt()} px compone sin desbordar', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await _pump(
          tester,
          [
            _line(),
            _line(
                id: 'line-2', name: 'Cámara interior 27,5 con válvula Presta'),
          ],
          width: width,
        );

        // Cero excepciones: un overflow no se declara esperado en ninguna talla.
        expect(tester.takeException(), isNull);
        expect(find.text('Subtotal mercadería CLP'), findsOneWidget);
        expect(find.byKey(const ValueKey('plan-line-remove-line-1')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('plan-line-media-line-1')),
            findsOneWidget);
      });
    }

    testWidgets('estrecho, la plata y el stepper caen bajo la identidad',
        (tester) async {
      await _pump(tester, [_line()], width: 380);

      final identity = tester.getRect(find.text('Neumático 27,5 Maxxis'));
      final total =
          tester.getRect(find.byKey(const ValueKey('plan-line-total-line-1')));
      expect(total.top, greaterThan(identity.top));
    });

    testWidgets('ancho, todo cabe en una sola fila', (tester) async {
      await _pump(tester, [_line()], width: 900);

      final identity = tester.getRect(find.text('Neumático 27,5 Maxxis'));
      final total =
          tester.getRect(find.byKey(const ValueKey('plan-line-total-line-1')));
      final remove =
          tester.getRect(find.byKey(const ValueKey('plan-line-remove-line-1')));
      expect(total.left, greaterThan(identity.right));
      expect(remove.left, greaterThan(total.left));
    });
  });

  group('el editor de cantidad ocupa el sitio de su línea', () {
    testWidgets('con la línea en edición, la fila cede el lugar',
        (tester) async {
      await _pump(tester, [_line()], editingLineId: 'line-1');

      expect(find.byKey(const ValueKey('purchase-plan-quantity-field')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('plan-line-remove-line-1')), findsNothing);
      // Y el grupo sigue completo: cabecera y pie no dependen de la fila.
      expect(find.text('Subtotal mercadería CLP'), findsOneWidget);
    });
  });

  group('claro y oscuro', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: la composición no cambia',
          (tester) async {
        await _pump(
          tester,
          [_line(), _line(id: 'line-2', name: 'Cámara 27,5')],
          brightness: brightness,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('\$17.450'), findsWidgets);
        expect(find.text('Subtotal mercadería CLP'), findsOneWidget);
        expect(find.byType(ProductMediaTile), findsNWidgets(2));
      });
    }

    testWidgets('el pie se distingue del cuerpo por su fondo, no por un borde',
        (tester) async {
      await _pump(tester, [_line()]);

      // El pie hundido es lo que separa el subtotal de las líneas. Si alguien
      // lo aplana, evidencia y subtotal vuelven a leerse como una sola cosa.
      final footer = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Subtotal mercadería CLP'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((footer.decoration! as BoxDecoration).color, isNotNull);
    });
  });
}
