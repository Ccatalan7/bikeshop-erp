import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/mail/providers/mail_account_manager.dart';
import 'package:vinabike_erp/modules/mail/services/mail_recipient_directory.dart';
import 'package:vinabike_erp/modules/mail/widgets/compose_email_dialog.dart';
import 'package:vinabike_erp/modules/mail/widgets/mail_recipient_field.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/copyable_text_scope.dart';

class _FakeDirectory extends MailRecipientDirectory {
  @override
  Future<Object?> fetchDirectory() async => [
        for (final recipient in _libreta)
          {
            'address': recipient.address,
            'name': recipient.name,
            'org': recipient.org,
            'kind': recipient.kind.name,
          },
      ];
}

/// El dueño (2026-11-16): en Redactar, «por default deberían estar todos los
/// que nosotros tenemos agregados como contacto en nuestra lista de
/// proveedores», además de los que se van usando. El campo sugiere mientras
/// se escribe, con filas en su sitio. Nombres y direcciones son inventados.

const _libreta = [
  MailRecipient(
    address: 'ventas@andina.example',
    kind: MailRecipientKind.supplier,
    name: 'Importadora Andina',
  ),
  MailRecipient(
    address: 'rocio@andina.example',
    kind: MailRecipientKind.supplier,
    name: 'Rocío Pérez',
    org: 'Importadora Andina',
  ),
  MailRecipient(
    address: 'pedro@frenos.example',
    kind: MailRecipientKind.supplier,
    name: 'Pedro Soto',
    org: 'Frenos Norte',
  ),
  MailRecipient(
    address: 'agata.soto@correo.example',
    kind: MailRecipientKind.customer,
    name: 'Ágata Soto',
  ),
];

Future<TextEditingController> _pump(
  WidgetTester tester, {
  Size size = const Size(900, 700),
  Brightness brightness = Brightness.light,
  Set<String> excluded = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            child: Column(
              children: [
                MailRecipientField(
                  label: 'Para:',
                  controller: controller,
                  recipients: _libreta,
                  excluded: excluded,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => isValidMailRecipientList(value ?? '')
                      ? null
                      : 'Revisa las direcciones de correo',
                ),
                const SizedBox(height: 12),
                const TextField(key: Key('asunto')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

Finder _row(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(InkWell),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'al escribir aparecen los proveedores como filas y tocar una la pone',
      (tester) async {
    final controller = await _pump(tester);

    expect(find.text('Importadora Andina'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'andi');
    await tester.pump();

    expect(find.text('Importadora Andina'), findsOneWidget);
    expect(find.text('ventas@andina.example · Proveedor'), findsOneWidget);
    expect(find.text('Rocío Pérez'), findsOneWidget);
    expect(
        find.text('rocio@andina.example · Importadora Andina'), findsOneWidget);
    expect(find.text('Pedro Soto'), findsNothing);
    // Mientras ofrece cómo completar, no reclama la dirección a medias.
    expect(find.text('Revisa las direcciones de correo'), findsNothing);

    await tester.tap(_row('Rocío Pérez'));
    await tester.pump();

    expect(controller.text, 'rocio@andina.example, ');
    expect(find.text('Rocío Pérez'), findsNothing);
    expect(find.text('Revisa las direcciones de correo'), findsNothing);
  });

  testWidgets(
      'en el Mac, hacer clic en una fila no saca el foco antes de elegir',
      (tester) async {
    final controller = await _pump(tester);
    await tester.enterText(find.byType(TextFormField), 'pedro');
    await tester.pump();

    await tester.tap(_row('Pedro Soto'), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(controller.text, 'pedro@frenos.example, ');
    final editable =
        tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.focusNode.hasFocus, isTrue,
        reason: 'el cursor queda listo para el siguiente destinatario');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('flechas, Enter, Tab y Esc', (tester) async {
    final controller = await _pump(tester);

    await tester.enterText(find.byType(TextFormField), 'soto');
    await tester.pump();
    expect(find.text('Pedro Soto'), findsOneWidget);
    expect(find.text('Ágata Soto'), findsOneWidget);

    // Los proveedores van antes que los clientes: Pedro primero, Ágata abajo.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, 'agata.soto@correo.example, ');

    await tester.enterText(
        find.byType(TextFormField), 'agata.soto@correo.example, imp');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        controller.text, 'agata.soto@correo.example, ventas@andina.example, ');

    await tester.enterText(find.byType(TextFormField),
        'agata.soto@correo.example, ventas@andina.example, an');
    await tester.pump();
    expect(find.text('Rocío Pérez'), findsOneWidget);
    expect(find.text('Importadora Andina'), findsNothing,
        reason: 'lo que ya está puesto no se sugiere otra vez');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Rocío Pérez'), findsNothing);
    expect(find.text('Revisa las direcciones de correo'), findsOneWidget,
        reason: 'cerradas las sugerencias, la dirección a medias se reclama');

    await tester.enterText(find.byType(TextFormField),
        'agata.soto@correo.example, ventas@andina.example, and');
    await tester.pump();
    expect(find.text('Rocío Pérez'), findsOneWidget,
        reason: 'escribir de nuevo las trae');
  });

  testWidgets('no sugiere lo que ya va en otro campo ni con el campo sin foco',
      (tester) async {
    await _pump(tester, excluded: {'rocio@andina.example'});
    await tester.enterText(find.byType(TextFormField), 'andi');
    await tester.pump();
    expect(find.text('Importadora Andina'), findsOneWidget);
    expect(find.text('Rocío Pérez'), findsNothing);

    await tester.tap(find.byKey(const Key('asunto')));
    await tester.pump();
    expect(find.text('Importadora Andina'), findsNothing);
  });

  // Como en el ERP: Redactar se abre desde el armazón, cuyo texto se marca con
  // el mouse (CopyableTextScope). Mientras el campo tenía el cursor, las asas
  // invisibles del campo se quedaban con el clic de la sugerencia
  // (2026-11-16, arreglado en copyable_text_scope.dart).
  testWidgets('en Redactar del ERP, con el mouse, la sugerencia se elige',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: CopyableTextScope.host(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ComposeEmailDialog(
                    manager: MailAccountManager(),
                    recipientDirectory: _FakeDirectory(),
                  ),
                ),
                child: const Text('Redactar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Redactar'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    final to = find.byKey(const ValueKey('mail-compose-to'));
    await tester.tap(to, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.enterText(to, 'frenos');
    await tester.pump();
    await tester.tap(
      find.byKey(
          const ValueKey('mail-recipient-suggestion-pedro@frenos.example')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(tester.widget<TextFormField>(to).controller!.text,
        'pedro@frenos.example, ');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final brightness in Brightness.values) {
    testWidgets('en el teléfono (${brightness.name}) las filas caben',
        (tester) async {
      await _pump(tester, size: const Size(320, 640), brightness: brightness);
      await tester.enterText(find.byType(TextFormField), 'a');
      await tester.pump();

      expect(find.text('Importadora Andina'), findsOneWidget);
      expect(find.text('Ágata Soto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final row = tester.getSize(_row('Importadora Andina'));
      expect(row.height, greaterThanOrEqualTo(44),
          reason: 'se toca con el dedo');
    });
  }
}
