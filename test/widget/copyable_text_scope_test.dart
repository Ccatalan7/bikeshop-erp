import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/widgets/copyable_text_scope.dart';

/// El dueño, 2026-11-14: «no puedo hacer highlight de texto para copiar y
/// pegar». El ERP arrastra con el mouse para desplazar (así está configurado
/// en `AppScrollBehavior`), y eso le gana a marcar texto.
class _MouseDragsToScroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late List<String> copied;

  setUp(() {
    copied = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ScrollController> pumpList(
    WidgetTester tester, {
    bool scoped = true,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final list = ListView(
      controller: controller,
      children: [
        for (var row = 0; row < 60; row++)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Seguimiento 7700029326$row'),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: _MouseDragsToScroll(),
      home: Scaffold(
        body: scoped ? CopyableTextScope(child: list) : list,
      ),
    ));
    return controller;
  }

  /// Un arrastre de mano: en diagonal y con un cuadro entre cada movimiento,
  /// como en la app (la selección dentro de una lista se resuelve por cuadro).
  Future<void> dragMouse(WidgetTester tester, Offset from, Offset by) async {
    final mouse =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await mouse.moveBy(Offset(by.dx * 0.2, by.dy * 0.5));
    await tester.pump();
    await mouse.moveBy(Offset(by.dx * 0.8, by.dy * 0.5));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
  }

  Future<void> clickMouse(WidgetTester tester, Offset at) async {
    final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
  }

  Offset textStart(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)) + const Offset(2, 8);

  Future<void> pressCopy(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
  }

  testWidgets('the mouse marks text in a list and Cmd+C copies it',
      (tester) async {
    final controller = await pumpList(tester);

    await dragMouse(
      tester,
      textStart(tester, 'Seguimiento 77000293262'),
      const Offset(200, 10),
    );
    expect(controller.offset, 0, reason: 'el arrastre no desplaza la lista');

    await pressCopy(tester);
    expect(copied, hasLength(1));
    expect(copied.single, contains('Seguimiento 7700029326'));

    // Esc desmarca: después ya no hay nada que copiar.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await pressCopy(tester);
    expect(copied, hasLength(1));
  }, variant: _mac);

  testWidgets('without the zone the same drag scrolls and nothing is copied',
      (tester) async {
    final controller = await pumpList(tester, scoped: false);

    await dragMouse(
      tester,
      textStart(tester, 'Seguimiento 77000293265'),
      const Offset(8, -60),
    );
    expect(controller.offset, greaterThan(0));

    await pressCopy(tester);
    expect(copied, isEmpty);
  }, variant: _mac);

  testWidgets('the wheel still scrolls a list whose text can be marked',
      (tester) async {
    final controller = await pumpList(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();

    expect(controller.offset, 120);
  }, variant: _mac);

  testWidgets('on a phone nothing changes', (tester) async {
    await pumpList(tester);

    expect(find.byType(SelectionArea), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('one zone is enough: a second one inside adds nothing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CopyableTextScope(
          child: CopyableTextScope(child: Text('Corona 38T')),
        ),
      ),
    ));

    expect(find.byType(SelectionArea), findsOneWidget);
  }, variant: _mac);

  // El visor de fotos de un producto cambia de foto con ← →, escuchándolas
  // desde su propio Focus. Un clic sobre la foto no puede quitárselas.
  testWidgets(
      'a click leaves the keys where they were, and marking text takes '
      'them only while something is marked', (tester) async {
    var arrows = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CopyableTextScope(
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                arrows++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Foto 1 de 3'),
                SizedBox(height: 40),
                Text('Marca: Shimano · Modelo MF-TZ500'),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    await clickMouse(tester, textStart(tester, 'Foto 1 de 3'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(arrows, 1, reason: 'el clic no movió el foco');

    await dragMouse(
      tester,
      textStart(tester, 'Marca: Shimano · Modelo MF-TZ500'),
      const Offset(140, 0),
    );
    await pressCopy(tester);
    expect(copied.single, startsWith('Marca'));

    // Un clic sin arrastrar desmarca y devuelve las teclas.
    await clickMouse(tester, textStart(tester, 'Foto 1 de 3'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(arrows, 2);

    // Esc también: desmarca y las teclas vuelven a quien las tenía.
    await dragMouse(
      tester,
      textStart(tester, 'Marca: Shimano · Modelo MF-TZ500'),
      const Offset(140, 0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await pressCopy(tester);
    expect(copied, hasLength(1),
        reason: 'después de Esc no queda nada marcado');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(arrows, 3);
  }, variant: _mac);

  Widget pageWithDialog({required bool hostOnly}) {
    final button = Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            content: Text('No se pudo guardar: código 40001'),
          ),
        ),
        child: const Text('abrir'),
      ),
    );
    return MaterialApp(
      home: Scaffold(
        body: hostOnly
            ? CopyableTextScope.host(child: button)
            : CopyableTextScope(child: button),
      ),
    );
  }

  for (final hostOnly in [false, true]) {
    testWidgets(
        'a dialog opened from ${hostOnly ? 'the shell' : 'a page'} '
        'is its own zone', (tester) async {
      await tester.pumpWidget(pageWithDialog(hostOnly: hostOnly));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final dialogText = find.text('No se pudo guardar: código 40001');
      expect(
        find.ancestor(of: dialogText, matching: find.byType(SelectionArea)),
        findsOneWidget,
      );
      // La zona del diálogo no es la de la página: lo tapado no se mezcla.
      expect(
        find.ancestor(
          of: find.text('abrir'),
          matching: find.byType(SelectionArea),
        ),
        hostOnly ? findsNothing : findsOneWidget,
      );

      await dragMouse(
        tester,
        tester.getTopLeft(dialogText) + const Offset(1, 8),
        const Offset(120, 0),
      );
      await pressCopy(tester);
      // Lo marcado es un tramo del texto del diálogo, y nada más.
      expect(copied.single, isNotEmpty);
      expect('No se pudo guardar: código 40001', startsWith(copied.single));
    }, variant: _mac);
  }

  // 2026-11-16: las asas de un campo también capturan los temas, y nacían con
  // una zona del tamaño de la pantalla encima de todo. Mientras el campo tenía
  // el cursor, el clic siguiente en cualquier botón se perdía, y la fila de un
  // destinatario sugerido en el correo no se podía elegir nunca.
  Widget fieldAndButton(VoidCallback onSave) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TextField(key: Key('campo')),
          TextButton(onPressed: onSave, child: const Text('Guardar')),
        ],
      );

  Future<void> clickFieldThenSave(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('campo')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('campo')), 'Cassette 11-50');
    await tester.pump();
    await tester.tap(find.text('Guardar'), kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  for (final where in ['the shell', 'a page', 'a workspace navigator']) {
    testWidgets(
        'with the cursor in a field of $where, the next click on a button '
        'arrives', (tester) async {
      var saved = 0;
      final content = Scaffold(body: fieldAndButton(() => saved++));
      await tester.pumpWidget(MaterialApp(
        home: switch (where) {
          'the shell' => CopyableTextScope.host(child: content),
          'a page' => CopyableTextScope(child: content),
          _ => CopyableTextScope.host(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => CopyableTextScope(child: content),
                ),
              ),
            ),
        },
      ));

      await clickFieldThenSave(tester);

      expect(saved, 1);
      expect(
        find.byType(SelectionArea),
        where == 'the shell' ? findsNothing : findsOneWidget,
        reason: 'sólo la zona de la página: las asas del campo no traen '
            'la suya',
      );
    }, variant: _mac);
  }

  testWidgets(
      'in a dialog opened from the shell, the next click after a field '
      'arrives too', (tester) async {
    var saved = 0;
    await tester.pumpWidget(MaterialApp(
      home: CopyableTextScope.host(
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(child: fieldAndButton(() => saved++)),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    await clickFieldThenSave(tester);

    expect(saved, 1);
    expect(
      find.ancestor(
        of: find.byKey(const Key('campo')),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
      reason: 'el diálogo sigue siendo su propia zona',
    );
  }, variant: _mac);

  testWidgets('an open menu still takes the arrow keys on its items',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CopyableTextScope(
          child: PopupMenuButton<String>(
            onSelected: (value) => chosen = value,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'efectivo', child: Text('Efectivo')),
              PopupMenuItem(value: 'tarjeta', child: Text('Tarjeta')),
            ],
            child: const Text('Medio de pago'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Medio de pago'));
    await tester.pumpAndSettle();

    // El menú también nace con su zona; ésta no puede quedarse con el foco
    // antes que el primer ítem.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(chosen, 'efectivo');
  }, variant: _mac);
}
