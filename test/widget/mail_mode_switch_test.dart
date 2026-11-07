import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vinabike_erp/modules/mail/work/mail_mode.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El selector «Inteligente | Normal» del correo (dueño, 2026-11-07).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MailModePreference.instance.resetForTest();
  });

  group('a dónde va cada modo', () {
    test('el inteligente se queda en /mail', () {
      expect(mailModeRedirect(Uri.parse('/mail'), MailMode.smart), isNull);
      expect(
        mailModeRedirect(
            Uri.parse('/mail?providerId=gmail&messageId=abc'), MailMode.smart),
        isNull,
      );
    });

    test('el normal abre la bandeja, con el correo del aviso', () {
      expect(mailModeRedirect(Uri.parse('/mail'), MailMode.normal),
          '/mail/bandeja');
      expect(
        mailModeRedirect(
          Uri.parse('/mail?providerId=zoho&messageId=m1&openRequest=7'),
          MailMode.normal,
        ),
        '/mail/bandeja?providerId=zoho&messageId=m1&openRequest=7',
      );
    });

    test('la historia de un registro se queda en el inteligente', () {
      expect(
        mailModeRedirect(Uri.parse('/mail?mail=1234'), MailMode.normal),
        isNull,
      );
    });

    test('cambiar de modo sigue en el correo abierto', () {
      expect(
        mailModeRoute(MailMode.normal, providerId: 'gmail', messageId: 'x'),
        '/mail/bandeja?providerId=gmail&messageId=x',
      );
      expect(mailModeRoute(MailMode.smart), '/mail');
    });
  });

  group('el modo se recuerda por persona', () {
    test('sin elegir, es el inteligente', () async {
      await MailModePreference.instance.ensureLoaded();
      expect(MailModePreference.instance.mode, MailMode.smart);
    });

    test('elegir el normal lo guarda con la clave de la persona', () async {
      await MailModePreference.instance.set(MailMode.normal);
      expect(MailModePreference.instance.isNormal, isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(MailModePreference.keyFor(null)), 'normal');
      expect(MailModePreference.keyFor('ana'),
          isNot(MailModePreference.keyFor('luis')));
    });
  });

  testWidgets('el selector cambia de vista y deja elegida la otra',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/mail',
      routes: [
        GoRoute(
          path: '/mail',
          redirect: (context, state) =>
              mailModeRedirect(state.uri, MailModePreference.instance.mode),
          builder: (context, state) => const Scaffold(
            body: Column(children: [
              MailModeSwitch(current: MailMode.smart),
              Text('Para hoy'),
            ]),
          ),
        ),
        GoRoute(
          path: '/mail/bandeja',
          builder: (context, state) => const Scaffold(
            body: Column(children: [
              MailModeSwitch(current: MailMode.normal),
              Text('Bandeja Unificada'),
            ]),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Para hoy'), findsOneWidget);
    expect(find.text('Inteligente'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    expect(find.text('Bandeja Unificada'), findsOneWidget);
    expect(MailModePreference.instance.mode, MailMode.normal);

    // «Correo» del menú va a /mail: con el normal elegido, abre la bandeja.
    router.go('/mail');
    await tester.pumpAndSettle();
    expect(find.text('Bandeja Unificada'), findsOneWidget);

    await tester.tap(find.text('Inteligente'));
    await tester.pumpAndSettle();
    expect(find.text('Para hoy'), findsOneWidget);
    expect(MailModePreference.instance.mode, MailMode.smart);
  });

  test('las dos vistas, el menú y la ruta usan el mismo modo', () {
    String read(String path) => File(path).readAsStringSync();
    expect(read('lib/modules/mail/work/mail_work_page.dart'),
        contains('MailModeSwitch('));
    expect(read('lib/modules/mail/pages/mail_inbox_page.dart'),
        contains('current: MailMode.normal'));
    expect(read('lib/shared/routes/app_router.dart'),
        contains('mailModeRedirect('));
    final layout = read('lib/shared/widgets/main_layout.dart');
    expect(layout, contains('MailModePreference.instance.isNormal'));
    expect(layout, contains('MailAccountManager.instance.unreadCount'));
  });
}
