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

/// Etapa 3 de Correo que trabaja: el aviso de una transferencia propone a
/// qué cobro corresponde y «Registrar aquí» abre el cobro de esa factura con
/// lo que trae el aviso. Nombres, montos y números son inventados.
/// Creado fuera de cada prueba: sus temporizadores no son de la prueba.
late final SupabaseClient _client;

class _FakeService extends MailWorkService {
  _FakeService(this.candidates) : super(client: _client);

  final List<MailPaymentCandidate> candidates;

  @override
  Future<List<MailPaymentCandidate>> paymentCandidates(
          String messageId) async =>
      candidates;
}

MailItem _transfer() => MailItem.fromJson({
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
      'body_text': 'Camila Prueba le ha transferido \$45.990.\n'
          'Numero de operacion635938240135',
      'state': {
        'actionable': true,
        'done': false,
        'action': 'register_payment',
      },
    });

Future<void> _pump(
  WidgetTester tester, {
  required List<MailPaymentCandidate> candidates,
  required List<String> visited,
}) async {
  final controller =
      MailWorkController(service: _FakeService(candidates), followsList: false);
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
          go: (route) async => visited.add(route),
          child: MailWorkDetail(item: _transfer(), controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
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

  testWidgets('a named transfer proposes her invoice and opens its payment',
      (tester) async {
    final visited = <String>[];
    await _pump(
      tester,
      visited: visited,
      candidates: [
        MailPaymentCandidate(
          type: 'sales_invoice',
          id: 'inv-1',
          label: 'V-123',
          who: 'Camila Prueba',
          balance: 45990,
          exact: true,
          named: true,
          at: DateTime(2026, 11, 2),
        ),
        const MailPaymentCandidate(
          type: 'online_order',
          id: 'ord-1',
          label: 'WEB-26-00099',
          who: 'Camila Prueba',
          balance: 45990,
          exact: true,
          named: true,
        ),
      ],
    );

    expect(find.text('¿A qué cobro de Camila Prueba corresponde?'),
        findsOneWidget);
    expect(find.text('Factura V-123'), findsOneWidget);
    expect(find.text('Pedido WEB-26-00099'), findsOneWidget);

    await tester.tap(find.text('Registrar aquí'));
    await tester.pump();

    expect(visited, hasLength(1));
    final route = Uri.parse(visited.single);
    expect(route.path, '/sales/invoices/inv-1/payment');
    expect(route.queryParameters['amount'], '45990');
    expect(route.queryParameters['method'], 'transfer');
    expect(route.queryParameters['reference'], '635938240135');
    expect(route.queryParameters['date'], isNotEmpty);
    expect(route.queryParameters['note'], contains('Camila Prueba'));

    await tester.tap(find.text('Abrir pedido'));
    await tester.pump();
    expect(visited.last, '/website/orders?order=ord-1');
  });

  testWidgets('without a pending charge it says so and keeps the search',
      (tester) async {
    final visited = <String>[];
    await _pump(tester, visited: visited, candidates: const []);

    expect(find.text('No hay un cobro pendiente de Camila Prueba.'),
        findsOneWidget);
    expect(find.text('Buscar el cobro'), findsOneWidget);
    expect(find.text('Hecho'), findsOneWidget);
  });
}
