import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/widgets/copyable_text_scope.dart';
import 'package:vinabike_erp/shared/widgets/escape_key_scope.dart';

/// El dueño, 2026-11-14: «ESC doesn't unfocus a search bar».
///
/// Con la forma del ERP: la zona de la página afuera y el `Scaffold` de la
/// página adentro, entre la zona y el campo. Ese `Scaffold` trae su propia
/// acción de cancelar (cerrar el cajón), apagada, y ahí moría la tecla.
///
/// En el Mac la prueba hace lo mismo que el sistema: con un campo enfocado la
/// tecla vuelve como `cancelOperation:` (`MacOSTestTextInputKeyHandler`).
final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late FocusNode search;

  setUp(() => search = FocusNode());
  tearDown(() => search.dispose());

  Widget erp(Widget page, {bool scoped = true}) => MaterialApp(
        builder: (context, child) =>
            scoped ? EscapeKeyScope(child: child!) : child!,
        home: CopyableTextScope(child: page),
      );

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> focusField(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(search.hasFocus, isTrue);
  }

  testWidgets('Esc takes the cursor out of a search field on a page',
      (tester) async {
    final text = TextEditingController(text: 'corona 38');
    addTearDown(text.dispose);
    await tester.pumpWidget(erp(Scaffold(
      body: TextField(focusNode: search, controller: text),
    )));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isFalse);
    expect(text.text, 'corona 38', reason: 'lo escrito queda');
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('without the scope the page Scaffold kept the cursor there',
      (tester) async {
    await tester.pumpWidget(erp(
      Scaffold(body: TextField(focusNode: search)),
      scoped: false,
    ));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isTrue);
  }, variant: _mac);

  testWidgets('in a dialog Esc still closes the dialog', (tester) async {
    await tester.pumpWidget(erp(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              content: TextField(focusNode: search, autofocus: true),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(search.hasFocus, isTrue);

    await pressEscape(tester);

    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('an open drawer closes first', (tester) async {
    final scaffold = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(erp(Scaffold(
      key: scaffold,
      drawer: Drawer(child: TextField(focusNode: search)),
      body: const Text('Productos'),
    )));
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await focusField(tester);

    await pressEscape(tester);

    expect(scaffold.currentState!.isDrawerOpen, isFalse);
  }, variant: _mac);

  testWidgets('Autocomplete: Esc first closes the options, then the field',
      (tester) async {
    const brands = ['Shimano', 'SRAM', 'Sunrace'];
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(erp(Scaffold(
      body: RawAutocomplete<String>(
        focusNode: search,
        textEditingController: text,
        optionsBuilder: (value) => brands.where(
          (brand) => brand.toLowerCase().startsWith(value.text),
        ),
        fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
            TextField(controller: controller, focusNode: focusNode),
        optionsViewBuilder: (context, onSelected, options) => Material(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final option in options) Text(option)],
          ),
        ),
      ),
    )));
    await focusField(tester);
    await tester.enterText(find.byType(TextField), 's');
    await tester.pumpAndSettle();
    expect(find.text('Shimano'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('Shimano'), findsNothing);
    expect(search.hasFocus, isTrue, reason: 'el primer Esc es de las opciones');

    await pressEscape(tester);
    expect(search.hasFocus, isFalse);
  }, variant: _mac);

  testWidgets('an edit that cancels with Esc keeps it', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(erp(Scaffold(
      body: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => cancelled++,
          ),
        },
        child: TextField(focusNode: search),
      ),
    )));
    await focusField(tester);

    await pressEscape(tester);

    expect(cancelled, 1);
    expect(search.hasFocus, isTrue);
  }, variant: _mac);

  testWidgets('with a modifier the key is left alone', (tester) async {
    await tester.pumpWidget(erp(Scaffold(body: TextField(focusNode: search))));
    await focusField(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(search.hasFocus, isTrue);
  }, variant: _mac);

  testWidgets('on a phone nothing changes', (tester) async {
    await tester.pumpWidget(erp(Scaffold(body: TextField(focusNode: search))));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
