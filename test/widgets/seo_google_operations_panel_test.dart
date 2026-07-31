import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/services/website_seo_operations_service.dart';
import 'package:vinabike_erp/modules/website/widgets/seo_google_operations_panel.dart';

/// These tests fix the product rules the operations panel exists to protect:
///
/// * an action the backend does not authorize is disabled **and** states why;
/// * a completed operation is a dated fact, never an indexing promise;
/// * no domain, property id, account id, feed URL or secret name is rendered;
///   and
/// * the same actions are available at 390, 834, 1000 and 1400 px without a
///   horizontally scrolling row.
void main() {
  final observedAt = DateTime.utc(2026, 7, 28, 15, 45);

  Widget host(Widget child, {double width = 1400}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 900,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  SeoGoogleOperationsPanel panel({
    WebsiteSeoConnectionStatus? status,
    Map<SeoGoogleOperation, SeoGoogleOperationOutcome> outcomes = const {},
    void Function(SeoGoogleOperation)? onRun,
  }) {
    return SeoGoogleOperationsPanel(
      status: status,
      isBusy: false,
      runningOperation: null,
      outcomes: outcomes,
      onRun: onRun ?? (_) {},
    );
  }

  WebsiteSeoConnectionStatus connected() => WebsiteSeoConnectionStatus(
        connected: true,
        observedAt: observedAt,
        accountEmail: 'owner@example.cl',
        siteUrl: 'sc-domain:example.cl',
      );

  WebsiteSeoConnectionStatus disconnected() => WebsiteSeoConnectionStatus(
        connected: false,
        observedAt: observedAt,
      );

  WebsiteSeoConnectionStatus unauthorized() => WebsiteSeoConnectionStatus(
        connected: false,
        observedAt: observedAt,
        error: 'Insufficient website settings permission',
        blocker: WebsiteSeoOperationBlocker.notAuthorized,
      );

  ButtonStyleButton buttonWithLabel(WidgetTester tester, String label) {
    return tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
  }

  testWidgets('an unavailable action is disabled and states its reason',
      (tester) async {
    await tester.pumpWidget(host(panel(status: disconnected())));

    expect(buttonWithLabel(tester, 'Enviar sitemap').enabled, isFalse);
    expect(
      find.textContaining('Enviar sitemap: no disponible.'),
      findsOneWidget,
    );
    // Connecting is exactly what an unconnected tenant must still be able to do.
    expect(
      buttonWithLabel(tester, 'Conectar Search Console').enabled,
      isTrue,
    );
  });

  testWidgets('a 403 disables every action with the server reason',
      (tester) async {
    await tester.pumpWidget(host(panel(status: unauthorized())));

    for (final label in const [
      'Conectar Search Console',
      'Enviar sitemap',
      'Actualizar Merchant',
    ]) {
      expect(
        buttonWithLabel(tester, label).enabled,
        isFalse,
        reason: '$label must not be offered without authorization',
      );
    }
    expect(find.textContaining('no tiene permiso'), findsWidgets);
  });

  testWidgets('a connected tenant can submit and sees the resolved property',
      (tester) async {
    await tester.pumpWidget(host(panel(status: connected())));

    expect(buttonWithLabel(tester, 'Enviar sitemap').enabled, isTrue);
    expect(find.text('Reconectar Search Console'), findsOneWidget);
    expect(find.textContaining('sc-domain:example.cl'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
  });

  testWidgets('an outcome is dated and never promises indexing',
      (tester) async {
    await tester.pumpWidget(
      host(
        panel(
          status: connected(),
          outcomes: {
            SeoGoogleOperation.submitSitemap: SeoGoogleOperationOutcome(
              succeeded: true,
              observedAt: observedAt,
              message: 'Google aceptó la solicitud. No garantiza rastreo ni '
                  'indexación.',
            ),
          },
        ),
      ),
    );

    expect(find.textContaining('28 jul 2026'), findsOneWidget);
    expect(find.textContaining('No garantiza rastreo'), findsOneWidget);
    expect(find.textContaining('Indexado'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a failed outcome reads as a failure, not a partial success',
      (tester) async {
    await tester.pumpWidget(
      host(
        panel(
          status: connected(),
          outcomes: {
            SeoGoogleOperation.refreshMerchant: SeoGoogleOperationOutcome(
              succeeded: false,
              observedAt: observedAt,
              message: 'Merchant no está autorizado para este tenant.',
            ),
          },
        ),
      ),
    );

    expect(
      find.textContaining('Merchant no está autorizado'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsNothing);
  });

  testWidgets('renders no domain, account id, feed URL or secret name',
      (tester) async {
    await tester.pumpWidget(host(panel(status: connected())));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join(' ');

    for (final forbidden in const [
      'vinabike.cl',
      'merchants.google.com',
      'supabase.co',
      'google-merchant-feed',
      'GOOGLE_SERVICE_ACCOUNT',
      'GOOGLE_MERCHANT_ACCOUNT_ID',
    ]) {
      expect(
        texts.contains(forbidden),
        isFalse,
        reason: 'the panel must not name $forbidden',
      );
    }
  });

  group('action equivalence across widths', () {
    for (final width in const [390.0, 834.0, 1000.0, 1400.0]) {
      testWidgets('offers the same actions at ${width.toInt()} px',
          (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(panel(status: connected()), width: width));

        expect(find.text('Reconectar Search Console'), findsOneWidget);
        expect(find.text('Enviar sitemap'), findsOneWidget);
        expect(find.text('Actualizar Merchant'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('an unreadable status never invents "no estás conectado"',
      (tester) async {
    // A transport failure means we do not know the connection state. Blocking
    // the submit with a fabricated reason is the same class of lie as
    // reporting a fabricated success.
    await tester.pumpWidget(
      host(
        panel(
          status: WebsiteSeoConnectionStatus(
            connected: false,
            observedAt: observedAt,
            error: 'No se pudo contactar el servicio de Google.',
          ),
        ),
      ),
    );

    expect(buttonWithLabel(tester, 'Enviar sitemap').enabled, isTrue);
    expect(
      find.textContaining('Enviar sitemap: no disponible.'),
      findsNothing,
    );
    expect(find.text('Sin consultar'), findsOneWidget);
    expect(
      find.textContaining('No se pudo contactar el servicio de Google.'),
      findsOneWidget,
    );
  });

  testWidgets('the first read shows a loading state, not "no conectado"',
      (tester) async {
    await tester.pumpWidget(host(panel()));

    expect(find.textContaining('Leyendo el estado'), findsOneWidget);
    expect(find.text('No conectado'), findsNothing);
    expect(find.text('Enviar sitemap'), findsNothing);
  });
}
