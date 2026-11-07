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

/// Etapa 4 de Correo que trabaja: lo que mandamos y espera respuesta muestra
/// desde cuándo y el recordatorio ya escrito; un desconocido que dice ser un
/// banco se advierte antes que nada. Todo es inventado.
late final SupabaseClient _client;

MailItem _sent({required bool overdue}) {
  final at = DateTime.now().subtract(Duration(days: overdue ? 4 : 1));
  return MailItem.fromJson({
    'id': 'out-1',
    'mailbox': 'taller@ejemplo.invalid',
    'provider': 'gmail',
    'provider_message_id': 'p-out-1',
    'direction': 'out',
    'from_address': 'taller@ejemplo.invalid',
    'to': ['ventas@proveedor.invalid'],
    'subject': 'Pastillas de freno',
    'received_at': at.toIso8601String(),
    'kind': 'own',
    'facts': {
      'to_party': {
        'address': 'ventas@proveedor.invalid',
        'type': 'supplier',
        'label': 'Repuestos Inventados',
      },
    },
    'body_text': '¿Tienen pastillas B01S?',
    'state': {
      'actionable': true,
      'action': 'remind',
      'done': false,
      'waiting_since': at.toIso8601String(),
      'overdue': overdue,
      'remind_to': 'ventas@proveedor.invalid',
    },
  });
}

Future<void> _pump(WidgetTester tester, MailItem item) async {
  final controller = MailWorkController(
      service: MailWorkService(client: _client), followsList: false);
  addTearDown(controller.dispose);
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: MailNavigation(
          go: (route) async {},
          child: MailWorkDetail(item: item, controller: controller),
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

  testWidgets('an overdue mail of ours carries its written reminder',
      (tester) async {
    await _pump(tester, _sent(overdue: true));

    expect(find.text('Para Repuestos Inventados'), findsOneWidget);
    expect(find.textContaining('no ha respondido'), findsOneWidget);
    expect(find.text('LISTO PARA MANDAR'), findsOneWidget);
    expect(find.textContaining('¿pudieron revisar mi correo'), findsOneWidget);
    expect(find.text('Para ventas@proveedor.invalid'), findsOneWidget);
    expect(find.text('Mandar recordatorio'), findsOneWidget);
    expect(find.text('Hecho'), findsOneWidget);
  });

  testWidgets('before it is due, it says when it comes back', (tester) async {
    await _pump(tester, _sent(overdue: false));
    expect(find.textContaining('Si en 3 días no responde'), findsOneWidget);
    expect(find.text('Mandar recordatorio'), findsOneWidget);
  });

  testWidgets('a stranger posing as a bank is warned first', (tester) async {
    await _pump(
      tester,
      MailItem.fromJson(const {
        'id': 'f-1',
        'mailbox': 'taller@ejemplo.invalid',
        'provider': 'gmail',
        'provider_message_id': 'p-f-1',
        'from_address': 'alertas@otro.invalid',
        'from_name': 'Banco de Chile',
        'subject': 'Su cuenta fue bloqueada',
        'received_at': '2026-11-06T12:00:00Z',
        'kind': 'security',
        'facts': {'fake_bank': true, 'bank_name': 'Banco de Chile'},
        'state': {'actionable': true, 'action': 'review', 'done': false},
      }),
    );
    expect(
        find.text('Dice ser de Banco de Chile, pero no viene de su dirección.'),
        findsOneWidget);
    expect(find.textContaining('No abras sus enlaces'), findsOneWidget);
    expect(find.text('Ya lo revisé'), findsOneWidget);
  });
}
