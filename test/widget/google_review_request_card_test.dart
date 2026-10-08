import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/settings/services/google_review_request_service.dart';
import 'package:vinabike_erp/modules/settings/widgets/google_review_request_card.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

class _FakeService extends GoogleReviewRequestService {
  _FakeService(this.state);

  GoogleReviewRequestState state;
  final List<bool> saved = [];
  int created = 0;

  @override
  Future<GoogleReviewRequestState> load() async => state;

  @override
  Future<void> setEnabled(bool enabled) async {
    saved.add(enabled);
    state = _state(enabled: enabled, status: state.templateStatus);
  }

  @override
  Future<WhatsAppTemplateReviewStatus> createTemplate() async {
    created += 1;
    const pending = WhatsAppTemplateReviewStatus(status: 'PENDING');
    state = _state(enabled: state.enabled, status: pending);
    return pending;
  }
}

GoogleReviewRequestState _state({
  required bool enabled,
  WhatsAppTemplateReviewStatus? status,
}) =>
    GoogleReviewRequestState(
      enabled: enabled,
      templateStatus: status,
      templateCheckFailed: false,
      sent30d: 12,
      skipped30d: 3,
      skippedByReason: const [
        MapEntry('ya se le pidió este año', 2),
        MapEntry('sin celular', 1),
      ],
      lastSentAt: DateTime(2026, 10, 8, 12, 10),
    );

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GoogleReviewRequestCard(service: service),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  testWidgets('the request cannot be turned on before Meta approves it',
      (tester) async {
    final service = _FakeService(_state(enabled: false));
    await _pump(tester, service);

    expect(find.text('Se puede encender cuando Meta apruebe la plantilla.'),
        findsOneWidget);
    final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('google-review-request-switch')));
    expect(tile.onChanged, isNull);

    // Sin la plantilla en Meta, se crea desde aquí.
    await tester.tap(find.byKey(const Key('google-review-request-create')));
    await tester.pumpAndSettle();
    expect(service.created, 1);
    expect(find.textContaining('En revisión de Meta'), findsOneWidget);
    expect(find.byKey(const Key('google-review-request-create')), findsNothing);
  });

  testWidgets('an approved template lets the shop turn the request on',
      (tester) async {
    final service = _FakeService(_state(
      enabled: false,
      status: const WhatsAppTemplateReviewStatus(
        status: 'APPROVED',
        category: 'UTILITY',
      ),
    ));
    await _pump(tester, service);

    expect(find.textContaining('Aprobada por Meta'), findsOneWidget);
    expect(find.textContaining('Meta la cobra como servicio'), findsOneWidget);
    await tester.tap(find.byKey(const Key('google-review-request-switch')));
    await tester.pumpAndSettle();

    expect(service.saved, [true]);
    expect(find.text('Encendido: cada entrega con celular recibe el pedido.'),
        findsOneWidget);
  });

  testWidgets('the card says how many went out and why the rest did not',
      (tester) async {
    await _pump(tester, _FakeService(_state(enabled: true)));

    expect(find.text('12'), findsOneWidget);
    expect(find.text('pedidos enviados en 30 días'), findsOneWidget);
    expect(
      find.text('omitidos: ya se le pidió este año (2), sin celular (1)'),
      findsOneWidget,
    );
  });

  test('every reason the database stores has words for the shop', () {
    for (final reason in [
      'asked_this_year',
      'no_mobile',
      'no_customer',
      'job_not_delivered',
      'no_actor',
      'no_review_link',
      'no_channel',
      'send_not_accepted',
      'send_failed: boom',
    ]) {
      expect(GoogleReviewRequestService.skipReasonLabel(reason),
          isNot('otro motivo'),
          reason: reason);
    }
  });
}
