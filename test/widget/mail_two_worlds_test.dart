import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/mail/work/mail_navigation.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_controller.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_detail.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_models.dart';
import 'package:vinabike_erp/modules/mail/work/mail_work_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El dueño (2026-11-08): «que separe ambos mundos, pero que dé fácil acceso e
/// intuitivo a ambas áreas». Lo que propone el ERP y el correo original van
/// cada uno en su superficie: lado a lado con espacio, con un selector que no
/// se corta en el teléfono, y un correo sin propuesta abre en el original.
/// Nombres y montos son inventados.
late final SupabaseClient _client;

class _FakeService extends MailWorkService {
  _FakeService() : super(client: _client);

  @override
  Future<List<MailPaymentCandidate>> paymentCandidates(
          String messageId) async =>
      const [];

  @override
  Future<({String? html, String? text})> original(String messageId) async =>
      (html: null, text: null);
}

MailItem _transfer() => MailItem.fromJson(const {
      'id': 'mail-1',
      'mailbox': 'caja@ejemplo.invalid',
      'provider': 'gmail',
      'provider_message_id': 'p-1',
      'from_address': 'aviso@banco.invalid',
      'party_label': 'Banco Inventado',
      'subject': 'Aviso de transferencia de fondos',
      'received_at': '2026-11-04T22:08:00Z',
      'kind': 'transfer',
      'facts': {'amount': 45990, 'payer': 'Camila Prueba'},
      'attachments': [
        {
          'filename': 'comprobante.pdf',
          'mime_type': 'application/pdf',
          'size': 48211,
          'inline': false,
          'attachment_id': 'a1',
        },
      ],
      'body_text': 'Camila Prueba le ha transferido \$45.990.',
      'state': {
        'actionable': true,
        'done': false,
        'action': 'register_payment',
      },
    });

MailItem _notice() => MailItem.fromJson(const {
      'id': 'mail-2',
      'mailbox': 'contacto@ejemplo.invalid',
      'provider': 'zoho',
      'provider_message_id': 'p-2',
      'from_address': 'avisos@plataforma.invalid',
      'subject': 'Tu resumen semanal',
      'received_at': '2026-11-04T22:08:00Z',
      'kind': 'notification',
      'body_text': 'Esta semana no hubo novedades.',
      'state': {'actionable': false, 'done': false},
    });

Future<void> _pump(
  WidgetTester tester,
  MailItem item, {
  required Size size,
  bool compact = false,
  Brightness brightness = Brightness.light,
}) async {
  final controller =
      MailWorkController(service: _FakeService(), followsList: false);
  addTearDown(controller.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: MailNavigation(
          go: (route) async {},
          child: MailWorkDetail(
              item: item, controller: controller, compact: compact),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}

void main() {
  setUpAll(() async {
    _client = SupabaseClient(
      'http://localhost:54321',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es');
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'en el teléfono (${brightness.name}) el selector cabe y cambia de mundo',
        (tester) async {
      await _pump(tester, _transfer(),
          size: const Size(390, 844), compact: true, brightness: brightness);

      expect(find.text('Propuesta'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Viñabike ERP'), findsOneWidget);
      expect(find.text('Lo que propone'), findsOneWidget);
      expect(find.text('comprobante.pdf'), findsNothing);

      await tester.tap(find.text('Original'));
      await tester.pump();
      expect(find.text('comprobante.pdf'), findsOneWidget);
      expect(find.text('Lo que propone'), findsNothing);
      // El original ya ocupa la pantalla: no se ofrece abrirlo aparte.
      expect(find.text('Abrir aparte'), findsNothing);
    });
  }

  testWidgets('con espacio, la propuesta y el original van lado a lado',
      (tester) async {
    await _pump(tester, _transfer(), size: const Size(1500, 900));

    expect(find.text('Lo que propone'), findsOneWidget);
    expect(find.text('comprobante.pdf'), findsOneWidget);
    expect(find.text('Abrir aparte'), findsOneWidget);
    expect(find.text('Propuesta del ERP'), findsNothing);
  });

  testWidgets('más angosto, el selector nombra los dos mundos completos',
      (tester) async {
    await _pump(tester, _transfer(), size: const Size(1200, 900));

    expect(find.text('Propuesta del ERP'), findsOneWidget);
    expect(find.text('Correo original'), findsWidgets);
  });

  testWidgets('un correo sin nada que proponer abre en el original',
      (tester) async {
    await _pump(tester, _notice(), size: const Size(1200, 900));

    expect(find.text('Lo que propone'), findsNothing);
    expect(find.textContaining('no hubo novedades'), findsOneWidget);
  });
}
