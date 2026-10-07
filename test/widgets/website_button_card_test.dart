import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';

/// The button card of the editor's «Vista HTML»: the canvas's action fields
/// under the button the operator pressed in the page.
void main() {
  const action = WebsiteActionValue(
    label: 'Escríbenos',
    href: '/contacto',
  );

  Future<Future<WebsiteActionValue?>> open(
    WidgetTester tester, {
    Rect? anchor,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = showWebsiteButtonCard(
      host,
      action: action,
      anchor: anchor,
      destinationHelp: 'Vacío, abre el WhatsApp de la tienda.',
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('under the button, with its label, destination and look',
      (tester) async {
    final result = await open(
      tester,
      anchor: const Rect.fromLTWH(500, 200, 160, 48),
    );
    final card = tester.getRect(find.byKey(WebsiteInlineActionEditor.cardKey));
    expect(card.top, 256);
    expect(card.center.dx, closeTo(580, 0.5));
    expect(find.text('Botón'), findsOneWidget);
    expect(find.text('Vacío, abre el WhatsApp de la tienda.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Texto del botón'),
      'Agendar',
    );
    await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetApplyKey));
    await tester.pumpAndSettle();
    final written = await result;
    expect(written?.label, 'Agendar');
    expect(written?.href, '/contacto');
  });

  testWidgets('over the button when there is no room under it', (tester) async {
    final result = await open(
      tester,
      anchor: const Rect.fromLTWH(1180, 740, 90, 40),
    );
    final card = tester.getRect(find.byKey(WebsiteInlineActionEditor.cardKey));
    expect(card.bottom, lessThanOrEqualTo(732));
    expect(card.right, lessThanOrEqualTo(1268));
    await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetCancelKey));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('a press outside applies what is on screen, as on the canvas',
      (tester) async {
    final result = await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Texto del botón'),
      'Agendar hoy',
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect((await result)?.label, 'Agendar hoy');
  });
}
