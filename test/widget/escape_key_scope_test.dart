import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/widgets/escape_key_scope.dart';

/// El dueño, 2026-11-14: «ESC doesn't unfocus a search bar».
///
/// En el Mac la prueba hace lo mismo que el sistema: con un campo enfocado la
/// tecla vuelve como `cancelOperation:` (`MacOSTestTextInputKeyHandler`).
final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  late FocusNode search;

  setUp(() => search = FocusNode());
  tearDown(() => search.dispose());

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> focusField(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(search.hasFocus, isTrue);
  }

  testWidgets('Esc takes the cursor out of a search field on a page',
      (tester) async {
    final text = TextEditingController(text: 'corona 38');
    addTearDown(text.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscapeKeyScope(
          child: TextField(focusNode: search, controller: text),
        ),
      ),
    ));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isFalse);
    expect(text.text, 'corona 38', reason: 'lo escrito queda');
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('without the scope the cursor stayed in the field',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(focusNode: search)),
    ));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isTrue);
  }, variant: _mac);

  testWidgets('in a dialog Esc still closes the dialog', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EscapeKeyScope(
                child: AlertDialog(
                  content: TextField(focusNode: search, autofocus: true),
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(search.hasFocus, isTrue);

    await pressEscape(tester);

    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('Autocomplete: Esc first closes the options, then the field',
      (tester) async {
    const brands = ['Shimano', 'SRAM', 'Sunrace'];
    final text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscapeKeyScope(
          child: RawAutocomplete<String>(
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
        ),
      ),
    ));
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscapeKeyScope(
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => cancelled++,
              ),
            },
            child: TextField(focusNode: search),
          ),
        ),
      ),
    ));
    await focusField(tester);

    await pressEscape(tester);

    expect(cancelled, 1);
    expect(search.hasFocus, isTrue);
  }, variant: _mac);

  testWidgets('on a phone nothing changes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EscapeKeyScope(child: TextField(focusNode: search)),
      ),
    ));
    await focusField(tester);

    await pressEscape(tester);

    expect(search.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
