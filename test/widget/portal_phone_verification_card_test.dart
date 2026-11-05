// «Confirmar teléfono en el portal» (20261105010000): la plantilla del código
// se crea desde la tarjeta, el interruptor no se enciende antes de que Meta la
// apruebe y la tarjeta dice cuántos códigos salieron y se confirmaron.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/settings/services/portal_phone_verification_service.dart';
import 'package:vinabike_erp/modules/settings/widgets/portal_phone_verification_card.dart';
import 'package:vinabike_erp/shared/services/whatsapp_service.dart';

class _FakeService extends PortalPhoneVerificationService {
  _FakeService(this.state);

  PortalPhoneVerificationState state;
  final List<bool> saved = [];
  int created = 0;

  @override
  Future<PortalPhoneVerificationState> load() async => state;

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

PortalPhoneVerificationState _state({
  required bool enabled,
  WhatsAppTemplateReviewStatus? status,
}) =>
    PortalPhoneVerificationState(
      enabled: enabled,
      templateStatus: status,
      templateCheckFailed: false,
      sent30d: 9,
      confirmed30d: 7,
      failed30d: 0,
      lastSentAt: DateTime(2026, 11, 5, 10, 20),
    );

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PortalPhoneVerificationCard(service: service),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  testWidgets('sin plantilla en Meta se crea desde la tarjeta y no se enciende',
      (tester) async {
    final service = _FakeService(_state(enabled: false));
    await _pump(tester, service);

    expect(find.textContaining('Todavía no existe en Meta'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('portal-phone-verification-switch')),
    );
    expect(toggle.onChanged, isNull);
    expect(
      find.text('Se puede encender cuando Meta apruebe la plantilla.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('portal-phone-verification-create')));
    await tester.pumpAndSettle();
    expect(service.created, 1);
    expect(find.textContaining('En revisión de Meta'), findsOneWidget);
  });

  testWidgets('aprobada, se enciende y muestra lo que pasó en 30 días',
      (tester) async {
    final service = _FakeService(_state(
      enabled: false,
      status: const WhatsAppTemplateReviewStatus(status: 'APPROVED'),
    ));
    await _pump(tester, service);

    expect(find.textContaining('Aprobada por Meta'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('códigos enviados en 30 días'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('teléfonos confirmados'), findsOneWidget);
    expect(find.text('no salieron'), findsNothing);

    await tester.tap(find.byKey(const Key('portal-phone-verification-switch')));
    await tester.pumpAndSettle();
    expect(service.saved, [true]);
    expect(
      find.text('Encendido: el portal lo ofrece a quien todavía no ve su ficha '
          'del taller.'),
      findsOneWidget,
    );
  });
}
