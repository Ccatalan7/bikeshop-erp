import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/widgets/keyboard_scroll_scope.dart';

/// El dueño, 2026-11-14: «no puedo mover filas con los arrows o moverme hacia
/// el lado con las flechas».
///
/// Igual que `AppScrollBehavior`: cada desplazable deja su marca.
class _MarkedBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      KeyboardScrollScope.markScrollable(
        context,
        super.buildScrollbar(context, child, details),
      );
}

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late ScrollController rows;
  late ScrollController columns;
  late ScrollController locked;

  setUp(() {
    rows = ScrollController();
    columns = ScrollController();
    locked = ScrollController();
  });

  tearDown(() {
    rows.dispose();
    columns.dispose();
    locked.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, {int menuItems = 3}) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: _MarkedBehavior(),
      builder: (context, child) => KeyboardScrollScope(child: child!),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: TextField(key: ValueKey('search')),
                ),
                PopupMenuButton<int>(
                  key: const ValueKey('menu'),
                  itemBuilder: (_) => [
                    for (var item = 0; item < menuItems; item++)
                      PopupMenuItem(value: item, child: Text('Opción $item')),
                  ],
                ),
              ],
            ),
            // Una tabla más ancha que la ventana.
            SingleChildScrollView(
              key: const ValueKey('wide-table'),
              controller: columns,
              scrollDirection: Axis.horizontal,
              child: const SizedBox(
                width: 2400,
                height: 80,
                child: Text('Código · Producto · Marca · Stock · Precio'),
              ),
            ),
            SizedBox(
              height: 60,
              child: ListView(
                key: const ValueKey('locked'),
                controller: locked,
                physics: const NeverScrollableScrollPhysics(),
                children: const [SizedBox(height: 400)],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('rows'),
                controller: rows,
                children: [
                  for (var row = 0; row < 80; row++)
                    SizedBox(height: 36, child: Text('Trabajo $row')),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Future<void> pointAt(WidgetTester tester, Finder finder) async {
    final mouse = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(finder)));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('the down and up arrows move the list under the cursor',
      (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(rows.offset, KeyboardScrollScope.lineStep);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(rows.offset, KeyboardScrollScope.lineStep * 2);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(rows.offset, KeyboardScrollScope.lineStep);
    expect(columns.offset, 0);
  }, variant: _mac);

  testWidgets('left and right move a wide table sideways', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('wide-table')));

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(columns.offset, KeyboardScrollScope.lineStep * 2);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(columns.offset, KeyboardScrollScope.lineStep);
    expect(rows.offset, 0);
  }, variant: _mac);

  testWidgets('two quick taps move two steps', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    // La segunda llega antes de que la primera termine de moverse.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(rows.offset, KeyboardScrollScope.lineStep * 2);
  }, variant: _mac);

  testWidgets('a key held down keeps moving', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    // El sistema espera un momento antes de empezar a repetir la tecla.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(rows.offset, KeyboardScrollScope.lineStep * 3);
  }, variant: _mac);

  testWidgets('Page Down, End and Home', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));
    final viewport = rows.position.viewportDimension;

    await press(tester, LogicalKeyboardKey.pageDown);
    expect(rows.offset, closeTo(viewport * 0.85, 0.01));
    await press(tester, LogicalKeyboardKey.end);
    expect(rows.offset, rows.position.maxScrollExtent);
    await press(tester, LogicalKeyboardKey.pageUp);
    expect(
      rows.offset,
      closeTo(rows.position.maxScrollExtent - viewport * 0.85, 0.01),
    );
    await press(tester, LogicalKeyboardKey.home);
    expect(rows.offset, 0);
  }, variant: _mac);

  testWidgets('a text field keeps its arrow keys', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('search')));
    await tester.enterText(find.byKey(const ValueKey('search')), 'corona');
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.end);

    expect(rows.offset, 0);
  }, variant: _mac);

  testWidgets('an open menu keeps its arrow keys', (tester) async {
    // Tantas opciones que el menú mismo se desplaza: sin la excepción, la
    // flecha movería el menú en vez de pasar al primer ítem.
    await pumpPage(tester, menuItems: 40);
    await tester.tap(find.byKey(const ValueKey('menu')));
    await tester.pumpAndSettle();
    await pointAt(tester, find.text('Opción 3'));
    final menu = Scrollable.of(tester.element(find.text('Opción 3'))).position;

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(menu.pixels, 0);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<PopupMenuItem<int>>(),
      isNotNull,
    );
  }, variant: _mac);

  testWidgets('with Shift, Ctrl, Alt or Cmd the key is left alone',
      (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    for (final modifier in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    expect(rows.offset, 0);
  }, variant: _mac);

  testWidgets('a list locked on purpose does not move', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('locked')));

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.end);

    expect(locked.offset, 0);
    expect(rows.offset, 0);
  }, variant: _mac);

  testWidgets('at its end, the inner one passes the key to what holds it',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: _MarkedBehavior(),
      builder: (context, child) => KeyboardScrollScope(child: child!),
      home: Scaffold(
        body: ListView(
          controller: outer,
          children: [
            SizedBox(
              height: 200,
              child: ListView(
                key: const ValueKey('inner'),
                controller: inner,
                children: const [SizedBox(height: 240)],
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    ));
    await pointAt(tester, find.byKey(const ValueKey('inner')));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(inner.offset, 40, reason: 'sólo le quedaban 40 px');
    expect(outer.offset, 0);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(inner.offset, 40);
    expect(outer.offset, KeyboardScrollScope.lineStep);
  }, variant: _mac);

  testWidgets('a pager is not turned by the arrows', (tester) async {
    final inner = ScrollController();
    addTearDown(inner.dispose);
    late TabController tabs;
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: _MarkedBehavior(),
      builder: (context, child) => KeyboardScrollScope(child: child!),
      home: DefaultTabController(
        length: 2,
        child: Builder(builder: (context) {
          tabs = DefaultTabController.of(context);
          return Scaffold(
            body: TabBarView(
              children: [
                ListView(
                  key: const ValueKey('tab-list'),
                  controller: inner,
                  children: const [SizedBox(height: 3000)],
                ),
                const Text('Pagos'),
              ],
            ),
          );
        }),
      ),
    ));
    await pointAt(tester, find.byKey(const ValueKey('tab-list')));

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(tabs.index, 0);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(inner.offset, KeyboardScrollScope.lineStep);
  }, variant: _mac);

  testWidgets('on a phone the arrows are left alone', (tester) async {
    await pumpPage(tester);
    await pointAt(tester, find.byKey(const ValueKey('rows')));

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(rows.offset, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('before the pointer has been anywhere the key is left alone',
      (tester) async {
    await pumpPage(tester);

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(rows.offset, 0);
  });
}
