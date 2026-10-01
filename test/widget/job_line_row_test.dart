import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_line_row.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, child: child),
      ),
    );

JobLineRow _row({
  required bool mobile,
  required List<String> selected,
}) =>
    JobLineRow(
      mobileLayout: mobile,
      menuKey: const ValueKey('menu'),
      thumb: const SizedBox(),
      body: const Text('Enrayado + Centrado'),
      quantity: const Text('1'),
      price: const Text('22000'),
      total: const Text(r'$22,000'),
      semanticLabel: 'Línea 4, Enrayado + Centrado',
      actions: [
        JobLineAction(
          icon: Icons.tune,
          label: 'Configurar servicio',
          onSelected: () => selected.add('configure'),
        ),
        const JobLineAction(
          icon: Icons.arrow_downward,
          label: 'Bajar',
          onSelected: null,
          startsGroup: true,
        ),
      ],
    );

void main() {
  testWidgets('el menú de la línea se anuncia con su nombre y se abre',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    await tester.pumpWidget(_host(_row(mobile: true, selected: selected)));

    final menu =
        find.bySemanticsLabel('Acciones de Línea 4, Enrayado + Centrado');
    expect(menu, findsOneWidget,
        reason: 'el tooltip de PopupMenuButton no nombra el botón');
    expect(
        tester.getSize(find.byKey(const ValueKey('menu'))), const Size(48, 48));

    // La acción semántica abre el menú igual que el toque.
    tester.semantics.tap(
      find.semantics.byLabel('Acciones de Línea 4, Enrayado + Centrado'),
    );
    await tester.pumpAndSettle();
    final configure = find.text('Configurar servicio');
    expect(configure, findsOneWidget);
    expect(
      tester
          .getSize(find.ancestor(
            of: configure,
            matching: find.byType(PopupMenuItem<int>),
          ))
          .height,
      greaterThanOrEqualTo(48),
    );
    final moveDown = tester.widget<PopupMenuItem<int>>(find.ancestor(
      of: find.text('Bajar'),
      matching: find.byType(PopupMenuItem<int>),
    ));
    expect(moveDown.enabled, isFalse,
        reason: 'la última línea no baja, pero la opción se sigue viendo');

    await tester.tap(configure);
    await tester.pumpAndSettle();
    expect(selected, ['configure']);
    semantics.dispose();
  });

  testWidgets('en escritorio el menú mide 36 y la fila no desborda',
      (tester) async {
    tester.view.physicalSize = const Size(
      (JobLineRow.fixedWidth + 200) * 2,
      400,
    );
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _row(mobile: false, selected: [])),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('menu'))).width,
        greaterThanOrEqualTo(36),
        reason: 'con la tabla en su ancho mínimo el menú no se recorta');
  });

  // Barrido con el mouse (dueño, 2026-10-01): las filas que se soltaban
  // dejaban cajas grises porque el recuadro se apagaba hacia
  // `Colors.transparent` (negro). A mitad de camino, entrando y saliendo,
  // todo color pintado es el de su rol, sólo con menos alfa.
  testWidgets('al pasar el mouse la fila se anima sin pasar por gris',
      (tester) async {
    tester.view.physicalSize = const Size(
      (JobLineRow.fixedWidth + 300) * 2,
      600,
    );
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final theme = ThemeData(useMaterial3: true);
    final scheme = theme.colorScheme;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(body: _row(mobile: false, selected: [])),
    ));
    final allowed = {
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.outlineVariant,
    }.map((color) => color.withValues(alpha: 1).toARGB32()).toSet();

    void expectNoGrey(String moment) {
      final painted = <Color>[];
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(JobLineRow),
        matching: find.byType(DecoratedBox),
      ))) {
        final decoration = box.decoration;
        if (decoration is! BoxDecoration) continue;
        if (decoration.color case final color?) painted.add(color);
        final border = decoration.border;
        if (border is Border) painted.add(border.top.color);
      }
      for (final color in painted.where((color) => color.a > 0)) {
        expect(allowed, contains(color.withValues(alpha: 1).toARGB32()),
            reason: '$moment: $color no es un color del tema');
      }
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Enrayado + Centrado')));
    await tester.pump();
    await tester.pump(JobLineRow.hoverFade ~/ 2);
    expectNoGrey('entrando');
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(1, 590));
    await tester.pump();
    await tester.pump(JobLineRow.hoverFade ~/ 2);
    expectNoGrey('saliendo');
    await tester.pumpAndSettle();
  });

  testWidgets('una línea protegida no ofrece acciones ni un menú vacío',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const JobLineRow(
      mobileLayout: true,
      menuKey: ValueKey('menu'),
      thumb: SizedBox(),
      body: Text('Regulación de frenos'),
      quantity: Text('2'),
      price: Text('5000'),
      total: Text(r'$10,000'),
      semanticLabel: 'Línea 5, Regulación de frenos',
      actions: [],
    )));
    expect(find.byType(PopupMenuButton<int>), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Acciones de')), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final mobile in [false, true]) {
    testWidgets(
        'el grupo se anuncia como encabezado con su subtotal (móvil: $mobile)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(JobLineGroupHeader(
        label: 'Rueda trasera',
        lineCount: 2,
        subtotal: r'$45,000',
        mobileLayout: mobile,
      )));
      final node = tester.getSemantics(find.byType(JobLineGroupHeader));
      expect(node.label, r'Rueda trasera, 2 líneas, subtotal $45,000');
      expect(node.flagsCollection.isHeader, isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
