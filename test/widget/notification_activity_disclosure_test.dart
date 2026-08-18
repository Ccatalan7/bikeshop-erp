import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:vinabike_erp/modules/hr/models/hr_models.dart';
import 'package:vinabike_erp/modules/hr/services/hr_service.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/shared/services/notification_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/widgets/notifications_panel.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  tearDown(() {
    NotificationService().notificationsFeed.value = const [];
  });

  group('collapsed second line', () {
    testWidgets('a job merges number, customer and bicycle', (tester) async {
      await _pumpBriefing(tester, rows: [_jobRow()]);

      expect(
        find.text('PG-00492 · Claudia Arcos · Oxford Orion 4 · Negro'),
        findsOneWidget,
      );
    });

    testWidgets('a payment always names the method', (tester) async {
      await _pumpBriefing(tester, rows: [_paymentRow()]);

      expect(find.text('FV-00917 · \$30.000 · Transferencia'), findsOneWidget);
    });

    testWidgets('a voided payment remains truthful historical activity', (
      tester,
    ) async {
      await _pumpBriefing(tester, rows: [_voidedPaymentRow()]);

      expect(find.text('Pago anulado'), findsOneWidget);
      expect(find.text('FV-00917 · \$30.000 · Transferencia'), findsOneWidget);
    });

    testWidgets('a payment without a method leaves no dangling separator', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [
          _paymentRow(
            id: 'payment-bare',
            data: const {'payment_id': 'payment-bare'},
          ),
        ],
      );

      expect(find.text('FV-00917 · \$30.000'), findsOneWidget);
      expect(find.textContaining(' · ·'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data ?? '').trimRight().endsWith('·'),
        ),
        findsNothing,
      );
    });

    testWidgets('an expense names the method and an order names the delivery', (
      tester,
    ) async {
      await _pumpBriefing(tester, rows: [_expenseRow(), _orderRow()]);

      expect(
        find.text('GTO-00140 · Bicicletas del Sur · \$45.000 · Efectivo'),
        findsOneWidget,
      );
      expect(
        find.text('PED-014 · Ana Ríos · \$58.000 · Retiro en tienda'),
        findsOneWidget,
      );
    });

    testWidgets('a catalog row names the product and its SKU', (tester) async {
      await _pumpBriefing(tester, rows: [_catalogRow()]);

      expect(
        find.text('Cassette Shimano · SKU CS-M771'),
        findsOneWidget,
      );
    });

    testWidgets('a partial payload degrades to the server body', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [
          _jobRow(id: 'job-bare', data: const {'job_id': 'job-bare'}),
        ],
      );

      expect(find.text('PG-00492 · Claudia Arcos'), findsOneWidget);
    });

    testWidgets(
        'a backdated payment stays in recent activity and names its date',
        (tester) async {
      final row = _paymentRow(body: 'FV-00918 · \$72.000');
      final recorded = _fixtureCreatedAt();
      final occurred = recorded.subtract(const Duration(days: 4));
      row
        ..['created_at'] = recorded.toUtc().toIso8601String()
        ..['occurred_at'] = occurred.toUtc().toIso8601String();

      await _pumpBriefing(tester, rows: [row]);

      final occurredChile = _chileDayOf(occurred);
      expect(find.text('Nuevo pago recibido'), findsOneWidget);
      expect(
        find.textContaining(
          'Registrado hoy · pago del ${occurredChile.day}',
        ),
        findsOneWidget,
      );
      final movementTotal = tester
          .element(find.text('movimientos'))
          .findAncestorWidgetOfExactType<Column>();
      expect((movementTotal!.children.first as Text).data, '0');
    });
  });

  group('disclosure', () {
    testWidgets('a job with a client request opens and closes in place', (
      tester,
    ) async {
      await _pumpBriefing(tester, rows: [_jobRow()]);

      expect(find.text('Detalles'), findsOneWidget);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);

      final collapsed = _headerSemanticsOf(tester, 'Detalles');
      expect(
          collapsed.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(collapsed.flagsCollection.isButton, isTrue);
      expect(collapsed.flagsCollection.isExpanded, Tristate.isFalse);
      expect(collapsed.label, contains('Ver el detalle del trabajo'));
      expect(collapsed.label, isNot(contains('Ocultar')));

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);
      expect(
          find.text('Revisión de frenos y cambio de cadena'), findsOneWidget);
      expect(find.text('REGISTRÓ'), findsOneWidget);
      expect(find.text('Guille'), findsOneWidget);
      expect(find.text('Abrir trabajo'), findsOneWidget);
      expect(find.text('Ocultar'), findsOneWidget);
      expect(find.text('Detalles'), findsNothing);

      final expanded = _headerSemanticsOf(tester, 'Ocultar');
      expect(expanded.flagsCollection.isButton, isTrue);
      expect(expanded.flagsCollection.isExpanded, Tristate.isTrue);
      expect(expanded.label, contains('Ocultar el detalle del trabajo'));

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);
      expect(find.text('Abrir trabajo'), findsNothing);
      expect(find.text('Detalles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a job can disclose its registrant without a client request', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [
          _jobRow(
            id: 'job-actor-only',
            data: const {
              'job_id': 'job-actor-only',
              'recorded_by_name': 'Tania Soto',
            },
          ),
        ],
      );

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);
      expect(find.text('REGISTRÓ'), findsOneWidget);
      expect(find.text('Tania Soto'), findsOneWidget);
      expect(find.text('Abrir trabajo'), findsOneWidget);
    });

    testWidgets('only one row stays open', (tester) async {
      await _pumpBriefing(
        tester,
        rows: [
          _jobRow(id: 'job-1', body: 'PG-00001 · Ana'),
          _jobRow(
            id: 'job-2',
            body: 'PG-00002 · Beto',
            data: {
              'job_id': 'job-2',
              'client_request': 'Cambio de piñón y cadena',
            },
          ),
        ],
      );

      await tester.tap(find.text('PG-00001 · Ana · Oxford Orion 4 · Negro'));
      await _settle(tester);
      expect(
          find.text('Revisión de frenos y cambio de cadena'), findsOneWidget);

      await tester.tap(find.text('PG-00002 · Beto'));
      await _settle(tester);

      expect(find.text('Cambio de piñón y cadena'), findsOneWidget);
      expect(find.text('Revisión de frenos y cambio de cadena'), findsNothing);
      expect(find.text('Ocultar'), findsOneWidget);
      expect(find.text('Detalles'), findsOneWidget);
    });

    testWidgets(
        'a job without a client request has no disclosure and the '
        'whole row still navigates', (tester) async {
      final workspace = _RecordingWorkspaceManager();
      addTearDown(workspace.dispose);

      await _pumpBriefing(
        tester,
        rows: [
          _jobRow(id: 'job-bare', data: const {'job_id': 'job-bare'}),
        ],
        workspace: workspace,
      );

      expect(find.text('Detalles'), findsNothing);

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(workspace.routes, hasLength(1));
      expect(workspace.routes.single, startsWith('/taller/pegas/job-bare'));
    });

    testWidgets(
        'the explicit action opens the record through the existing '
        'workspace route', (tester) async {
      final workspace = _RecordingWorkspaceManager();
      addTearDown(workspace.dispose);

      await _pumpBriefing(tester, rows: [_jobRow()], workspace: workspace);

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);
      expect(workspace.routes, isEmpty);

      await tester.tap(find.text('Abrir trabajo'));
      await _settle(tester);

      expect(workspace.routes, hasLength(1));
      expect(workspace.routes.single, startsWith('/taller/pegas/job-1'));
      expect(workspace.routes.single, contains('openRequest='));
    });

    testWidgets('Abrir pago and Abrir gasto use their existing routes', (
      tester,
    ) async {
      final workspace = _RecordingWorkspaceManager();
      addTearDown(workspace.dispose);

      await _pumpBriefing(
        tester,
        rows: [_paymentRow(), _expenseRow()],
        workspace: workspace,
      );

      await tester.tap(find.text('Nuevo pago recibido'));
      await _settle(tester);
      await tester.tap(find.text('Abrir pago'));
      await _settle(tester);

      expect(workspace.routes, hasLength(1));
      final paymentRoute = Uri.parse(workspace.routes.single);
      expect(paymentRoute.path, '/sales/payments');
      expect(paymentRoute.queryParameters['paymentId'], 'payment-1');
      expect(paymentRoute.queryParameters['openRequest'], isNotEmpty);

      await tester.tap(find.text('Nuevo gasto registrado'));
      await _settle(tester);
      await tester.tap(find.text('Abrir gasto'));
      await _settle(tester);

      expect(workspace.routes, hasLength(2));
      final expenseRoute = Uri.parse(workspace.routes.last);
      expect(expenseRoute.path, '/accounting/expenses/expense-1');
      expect(expenseRoute.queryParameters['openRequest'], isNotEmpty);
    });

    testWidgets('a voided payment opens its invoice and names both actors', (
      tester,
    ) async {
      final workspace = _RecordingWorkspaceManager();
      addTearDown(workspace.dispose);

      await _pumpBriefing(
        tester,
        rows: [_voidedPaymentRow()],
        workspace: workspace,
      );

      await tester.tap(find.text('Pago anulado'));
      await _settle(tester);

      expect(find.text('REGISTRÓ'), findsOneWidget);
      expect(find.text('Guille'), findsOneWidget);
      expect(find.text('ANULÓ'), findsOneWidget);
      expect(find.text('Vicente Díaz'), findsOneWidget);
      expect(find.text('Abrir factura'), findsOneWidget);
      expect(find.text('Abrir pago'), findsNothing);

      await tester.tap(find.text('Abrir factura'));
      await _settle(tester);

      expect(workspace.routes, hasLength(1));
      final invoiceRoute = Uri.parse(workspace.routes.single);
      expect(invoiceRoute.path, '/sales/invoices/invoice-1');
      expect(invoiceRoute.queryParameters['openRequest'], isNotEmpty);
    });

    testWidgets('a payment disclosure omits every field the payload lacks', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [
          _paymentRow(
            id: 'payment-partial',
            data: const {
              'payment_id': 'payment-partial',
              'payment_method': 'Efectivo',
              'customer_name': 'Lorena Guzmán',
            },
          ),
        ],
      );

      await tester.tap(find.text('Nuevo pago recibido'));
      await _settle(tester);

      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('Lorena Guzmán'), findsOneWidget);
      expect(find.text('REGISTRÓ'), findsNothing);
      expect(find.text('REFERENCIA'), findsNothing);
      expect(find.text('FECHA DEL PAGO'), findsNothing);
      expect(find.text('Abrir pago'), findsOneWidget);
    });

    testWidgets(
        'a payment dated before its registration says so, and one '
        'dated the same day does not', (tester) async {
      // The comparison is against the Chilean civil day of the row, so the
      // fixtures are derived from that same calendar rather than from the
      // machine's local date, which can be a day apart near midnight.
      final rowDay = _chileDayOf(_fixtureCreatedAt());
      final sameDay = _isoDay(rowDay);
      final earlier = rowDay.subtract(const Duration(days: 40));
      final earlierIso = _isoDay(earlier);
      final earlierLabel = '${_pad(earlier.day)}/${_pad(earlier.month)}/'
          '${earlier.year}';

      await _pumpBriefing(
        tester,
        rows: [
          _paymentRow(
            id: 'payment-divergent',
            body: 'FV-00100 · \$1.000',
            data: {
              'payment_id': 'payment-divergent',
              // Serialised as midnight UTC, exactly like `issue_date` in
              // production: a timezone conversion here would move the day.
              'payment_date': '${earlierIso}T00:00:00+00:00',
            },
          ),
          _paymentRow(
            id: 'payment-sameday',
            body: 'FV-00200 · \$2.000',
            data: {
              'payment_id': 'payment-sameday',
              'customer_name': 'Ana',
              'payment_date': sameDay,
            },
          ),
        ],
      );

      await tester.tap(find.text('FV-00100 · \$1.000'));
      await _settle(tester);
      expect(find.text('FECHA DEL PAGO'), findsOneWidget);
      expect(find.text(earlierLabel), findsOneWidget);

      await tester.tap(find.text('FV-00200 · \$2.000'));
      await _settle(tester);
      expect(find.text('FECHA DEL PAGO'), findsNothing);
      expect(find.text('CLIENTE'), findsOneWidget);
    });

    testWidgets('an expense disclosure carries category, document and author', (
      tester,
    ) async {
      await _pumpBriefing(tester, rows: [_expenseRow()]);

      await tester.tap(find.text('Nuevo gasto registrado'));
      await _settle(tester);

      expect(find.text('CATEGORÍA'), findsOneWidget);
      expect(find.text('Suministros de Oficina'), findsOneWidget);
      expect(find.text('N° DE DOCUMENTO'), findsOneWidget);
      expect(find.text('549'), findsOneWidget);
      expect(find.text('REGISTRÓ'), findsOneWidget);
      expect(find.text('Abrir gasto'), findsOneWidget);
    });

    testWidgets('orders, catalog rows and Meta interactions stay direct', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [_orderRow(), _catalogRow(), _metaRow()],
      );

      expect(find.text('Detalles'), findsNothing);
      expect(find.text('Responder'), findsNothing);
      expect(find.text('Nuevo comentario de Instagram'), findsOneWidget);
    });

    testWidgets('keyboard arrows open and close the focused row', (
      tester,
    ) async {
      await _pumpBriefing(tester, rows: [_jobRow()]);

      Focus.of(tester.element(find.text('Detalles'))).requestFocus();
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);

      // Right on an open row is a no-op, not a toggle.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);

      // Left on a closed row is a no-op too.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);
    });

    testWidgets('Enter and Space toggle the focused row', (tester) async {
      await _pumpBriefing(tester, rows: [_jobRow()]);

      Focus.of(tester.element(find.text('Detalles'))).requestFocus();
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);
      expect(find.text('SOLICITUD DEL CLIENTE'), findsNothing);
    });

    testWidgets('the disclosure action is reachable with Tab', (tester) async {
      await _pumpBriefing(tester, rows: [_jobRow()]);

      Focus.of(tester.element(find.text('Detalles'))).requestFocus();
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final action = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Abrir trabajo'),
          matching: find.byType(TextButton),
        ),
      );
      expect(action.onPressed, isNotNull);
      expect(
        Focus.of(tester.element(find.text('Abrir trabajo'))).hasFocus,
        isTrue,
      );
    });
  });

  group('read state', () {
    testWidgets('opening the disclosure settles unread once; closing does not',
        (tester) async {
      NotificationService().activateNotificationScope(
        userId: 'user-test',
        tenantId: 'tenant-test',
      );
      addTearDown(NotificationService().clearNotificationScope);

      await _pumpBriefing(tester, rows: [_jobRow()]);

      expect(find.text('1 nuevas'), findsOneWidget);
      expect(_unreadDotCount(tester), 1);

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);
      expect(_unreadDotCount(tester), 0);
      expect(find.textContaining('nuevas'), findsNothing);
      final readAt = _feedReadAt('job-1');
      expect(readAt, isNotNull);

      // Collapsing writes nothing, and reopening does not rewrite the stamp.
      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);
      expect(_feedReadAt('job-1'), readAt);

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);
      expect(_feedReadAt('job-1'), readAt);
      expect(_unreadDotCount(tester), 0);
    });

    testWidgets('opening one row leaves its unread neighbour untouched',
        (tester) async {
      NotificationService().activateNotificationScope(
        userId: 'user-test',
        tenantId: 'tenant-test',
      );
      addTearDown(NotificationService().clearNotificationScope);

      await _pumpBriefing(tester, rows: [_jobRow(), _paymentRow()]);
      expect(_unreadDotCount(tester), 2);

      await tester.tap(find.text('Nuevo pago recibido'));
      await _settle(tester);

      // Only the opened row settles; its neighbour is untouched.
      expect(_unreadDotCount(tester), 1);
      expect(_feedReadAt('payment-1'), isNotNull);
      expect(_feedReadAt('job-1'), isNull);
    });
  });

  group('conversations', () {
    testWidgets(
        'an incoming WhatsApp thread names its channel and unread '
        'count', (tester) async {
      await _pumpBriefing(
        tester,
        rows: const [],
        conversations: [
          _conversation(
            id: 'conv-in',
            title: 'Rosita',
            content: '¿A qué hora abren?',
            unreadCount: 3,
            direction: 'inbound',
          ),
        ],
      );

      expect(
        find.text('WhatsApp · 3 nuevos · ¿A qué hora abren?'),
        findsOneWidget,
      );
    });

    testWidgets('an outgoing WhatsApp thread never claims a new message', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: const [],
        conversations: [
          _conversation(
            id: 'conv-out',
            title: 'Rosita',
            content: 'Ya está lista tu bicicleta',
            unreadCount: 4,
            direction: 'outbound',
            isMine: true,
          ),
        ],
      );

      expect(
        find.text('WhatsApp · Tú: Ya está lista tu bicicleta'),
        findsOneWidget,
      );
      // The row itself must never claim an unread incoming message when the
      // shop sent last; the module-level attention counter is a separate owner.
      expect(
        find.text('WhatsApp · 4 nuevos · Ya está lista tu bicicleta'),
        findsNothing,
      );
    });

    testWidgets('a single unread incoming message needs no count', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: const [],
        conversations: [
          _conversation(
            id: 'conv-one',
            title: 'Rosita',
            content: 'Gracias',
            unreadCount: 1,
            direction: 'inbound',
          ),
        ],
      );

      expect(find.text('WhatsApp · Gracias'), findsOneWidget);
    });
  });

  group('layout matrix', () {
    for (final size in const [
      Size(384, 824),
      Size(599, 900),
      Size(600, 900),
      Size(899, 900),
      Size(900, 900),
      Size(1440, 900),
    ]) {
      testWidgets('renders open and closed at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _pumpBriefing(
          tester,
          rows: [_jobRow(), _paymentRow()],
          surfaceSize: size,
        );

        expect(tester.takeException(), isNull);
        await _revealRow(tester, 'Nuevo pago recibido');
        await _revealRow(tester, 'Nuevo trabajo');
        expect(
          _activityRowHeight(tester, 'Nuevo trabajo'),
          greaterThanOrEqualTo(48),
        );
        expect(
          _activityRowHeight(tester, 'Nuevo pago recibido'),
          greaterThanOrEqualTo(48),
        );
        // `A-02`: the hit target grows, the glyph does not.
        expect(
          tester.widget<Icon>(find.byIcon(Icons.expand_more).first).size,
          16,
        );

        await tester.tap(find.text('Nuevo trabajo'));
        await _settle(tester);

        expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the panel survives its narrowest real width of 272px', (
      tester,
    ) async {
      // The toolbar panel itself is 272 wide on a 320px phone once the 48px
      // rail is gone. The viewport stays 320 — panel width and viewport class
      // are two different inputs and must not be conflated.
      final payment = _paymentRow();
      final recorded = _fixtureCreatedAt();
      final occurred = recorded.subtract(const Duration(days: 4));
      payment
        ..['created_at'] = recorded.toUtc().toIso8601String()
        ..['occurred_at'] = occurred.toUtc().toIso8601String();

      await _pumpBriefing(
        tester,
        rows: [payment, _jobRow()],
        surfaceSize: const Size(320, 900),
        panelWidth: 272,
      );

      expect(tester.takeException(), isNull);

      await _revealRow(tester, 'Nuevo pago recibido');
      final subtitle = tester.widget<Text>(
        find.text('FV-00917 · \$30.000 · Transferencia'),
      );
      // The widget-test font is not the shipped one and measures far wider, so
      // whether this line wraps here says nothing about the real app. What is
      // assertable is that the method survived composition and that the line
      // degrades through ellipsis rather than through an overflow.
      expect(subtitle.data, endsWith(' · Transferencia'));
      expect(subtitle.maxLines, 2);
      expect(subtitle.overflow, TextOverflow.ellipsis);
      final occurredChile = _chileDayOf(occurred);
      final dateHint = tester.widget<Text>(
        find.textContaining(
          'Registrado hoy · pago del ${occurredChile.day}',
        ),
      );
      expect(dateHint.maxLines, 2);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.textContaining(
                'Registrado hoy · pago del ${occurredChile.day}',
              ),
            )
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);

      await _revealRow(tester, 'Nuevo trabajo');
      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // A 420px panel inside an 899px viewport is still a compact host: the
    // action must reach 48. The same panel at 900 is pointer density. Each
    // viewport gets its own test, because a second `pumpWidget` in the same
    // one reuses the element tree and would carry the open row over.
    for (final probe in const [
      (viewport: 899.0, expected: 48.0),
      (viewport: 900.0, expected: 32.0),
    ]) {
      testWidgets(
          'the action is ${probe.expected.toInt()}px tall at viewport '
          '${probe.viewport.toInt()} with a 420px panel', (tester) async {
        await _pumpBriefing(
          tester,
          rows: [_jobRow()],
          surfaceSize: Size(probe.viewport, 1400),
          panelWidth: 420,
        );

        await _revealRow(tester, 'Nuevo trabajo');
        await tester.tap(find.text('Nuevo trabajo'));
        await _settle(tester);

        final actionFinder = find.ancestor(
          of: find.text('Abrir trabajo'),
          matching: find.byType(TextButton),
        );
        final action = tester.widget<TextButton>(actionFinder);
        final minimumSize = action.style!.minimumSize!.resolve({});
        expect(minimumSize!.height, probe.expected);
        expect(
          tester.getSize(actionFinder).height,
          greaterThanOrEqualTo(probe.expected),
        );
      });
    }

    testWidgets('384x824 at text scale 1.3 raises nothing, open or closed', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [_jobRow()],
        surfaceSize: const Size(384, 824),
        textScale: 1.3,
      );

      // `_BriefingToolbar` used to overflow here: its compact threshold was a
      // fixed 360 px while the `n nuevas` label grows with the text scale, and
      // a 384 panel lands on exactly 360.0.
      expect(tester.takeException(), isNull);
      // The scaled threshold abbreviates the alert label instead of spilling.
      expect(find.text('1 nuevas'), findsNothing);

      await _revealRow(tester, 'Nuevo trabajo');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Nuevo trabajo'));
      await _settle(tester);

      expect(find.text('SOLICITUD DEL CLIENTE'), findsOneWidget);
      expect(find.text('Abrir trabajo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the long alert label still renders at scale 1.0', (
      tester,
    ) async {
      await _pumpBriefing(
        tester,
        rows: [_jobRow()],
        surfaceSize: const Size(384, 824),
      );

      // The scaled threshold must not silently abbreviate the default host.
      expect(find.text('1 nuevas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('appearance', () {
    for (final brightness in Brightness.values) {
      testWidgets(
          'the disclosure sits on the sunken layer in ${brightness.name}',
          (tester) async {
        await _pumpBriefing(
          tester,
          rows: [_jobRow()],
          brightness: brightness,
        );

        await tester.tap(find.text('Nuevo trabajo'));
        await _settle(tester);

        final body = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('SOLICITUD DEL CLIENTE'),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = body.decoration! as BoxDecoration;
        final context = tester.element(find.text('SOLICITUD DEL CLIENTE'));
        expect(
          decoration.color,
          Theme.of(context).colorScheme.surfaceContainerLow,
        );
        // `T-03`: the row disclosure has no shadow and no selection bar.
        expect(decoration.boxShadow, anyOf(isNull, isEmpty));
        expect(decoration.border, isNull);
      });
    }

    testWidgets('the sunken layer is a designed role in each brightness', (
      tester,
    ) async {
      final light = ThemeData(brightness: Brightness.light).colorScheme;
      final dark = ThemeData(brightness: Brightness.dark).colorScheme;

      expect(light.surfaceContainerLow, isNot(dark.surfaceContainerLow));
      // A collapsed role would make the disclosure invisible against the row.
      expect(light.surfaceContainerLow, isNot(light.surface));
      expect(dark.surfaceContainerLow, isNot(dark.surface));
    });
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpBriefing(
  WidgetTester tester, {
  required List<Map<String, dynamic>> rows,
  List<Conversation> conversations = const [],
  WorkspaceManager? workspace,
  Size surfaceSize = const Size(500, 1400),
  double? panelWidth,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  NotificationService().notificationsFeed.value = rows;

  final hr = _EmptyHRService();
  addTearDown(hr.dispose);
  final chat = _StubChatProvider(conversations);
  addTearDown(chat.dispose);
  final toolbar = RightToolbarService();
  addTearDown(toolbar.dispose);
  final manager = workspace ?? _RecordingWorkspaceManager();
  if (workspace == null) addTearDown(manager.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<HRService>.value(value: hr),
        ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
        ChangeNotifierProvider<WorkspaceManager>.value(value: manager),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Builder(
          builder: (context) => MediaQuery(
            // `setSurfaceSize` changes the render surface but leaves
            // `MediaQuery.size` at the harness default of 800, so the two must
            // be set together — otherwise a test claiming a 900px viewport is
            // really only asserting a `SizedBox` width.
            data: MediaQuery.of(context).copyWith(
              size: surfaceSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SizedBox(
                width: panelWidth ?? surfaceSize.width,
                height: surfaceSize.height,
                child: const NotificationsToolbarPanel(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// The briefing keeps a live clock and a progress indicator mounted, so it
/// never reaches a quiescent frame. Settle a bounded number of frames instead
/// of waiting for one that cannot arrive.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump(const Duration(milliseconds: 320));
}

/// Counts the 6x6 unread markers currently rendered in activity rows.
int _unreadDotCount(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final constraints = widget.constraints;
        if (constraints == null) return false;
        return constraints.minWidth == 6 && constraints.minHeight == 6;
      })
      .evaluate()
      .length;
}

String? _feedReadAt(String notificationId) {
  for (final row in NotificationService().notificationsFeed.value) {
    if (row['id']?.toString() == notificationId) {
      return row['read_at']?.toString();
    }
  }
  return null;
}

/// Semantics node of the row header that currently shows [indicatorLabel].
SemanticsNode _headerSemanticsOf(WidgetTester tester, String indicatorLabel) {
  return tester.getSemantics(
    find
        .ancestor(
          of: find.text(indicatorLabel),
          matching: find.byType(InkWell),
        )
        .first,
  );
}

/// Brings an activity row into view.
///
/// The briefing list is lazy, so at a narrow width or an increased text scale
/// the timeline can sit beyond the built cache extent entirely; scrolling is
/// what materialises it, not just what makes it visible.
Future<void> _revealRow(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    240,
    scrollable: find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first,
  );
  await _settle(tester);
}

/// Height of the activity header that owns [title] — the single tap target of
/// that row, which must reach the 48 px touch minimum at every width.
double _activityRowHeight(WidgetTester tester, String title) {
  final header =
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;
  return tester.getSize(header).height;
}

// ---------------------------------------------------------------------------
// Row builders (shapes mirror the production `erp_notifications` payloads)
// ---------------------------------------------------------------------------

/// One deterministic instant inside the current Chilean business day.
///
/// `now - 2 minutes` crosses midnight in Santiago during a real release gate
/// and turns every activity fixture into "yesterday" at once. Midnight at the
/// start of the already-current Chilean day is always inside `Hoy` and never
/// lies after the digest's live upper bound.
DateTime _fixtureCreatedAt() {
  tzdata.initializeTimeZones();
  final location = tz.getLocation('America/Santiago');
  final now = tz.TZDateTime.now(location);
  return tz.TZDateTime(location, now.year, now.month, now.day).toUtc();
}

tz.TZDateTime _chileDayOf(DateTime instant) {
  tzdata.initializeTimeZones();
  return tz.TZDateTime.from(
    instant.toUtc(),
    tz.getLocation('America/Santiago'),
  );
}

String _pad(int value) => value.toString().padLeft(2, '0');

String _isoDay(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${_pad(value.month)}-${_pad(value.day)}';

Map<String, dynamic> _row({
  required String id,
  required String type,
  required String title,
  required String body,
  required Map<String, dynamic> data,
  String? entityId,
}) {
  return <String, dynamic>{
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'route': '',
    'entity_id': entityId,
    'severity': 'info',
    'data': data,
    'read_at': null,
    'created_at': _fixtureCreatedAt().toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _jobRow({
  String id = 'job-1',
  String body = 'PG-00492 · Claudia Arcos',
  Map<String, dynamic>? data,
}) {
  return _row(
    id: id,
    type: 'mechanic_job_created',
    title: 'Nuevo trabajo',
    body: body,
    entityId: id,
    data: data ??
        {
          'job_id': id,
          'job_number': 'PG-00492',
          'customer_name': 'Claudia Arcos',
          'bike_label': 'Oxford Orion 4 · Negro',
          'client_request': 'Revisión de frenos y cambio de cadena',
          'recorded_by_name': 'Guille',
          'priority': 'NORMAL',
          'status': 'PENDIENTE',
        },
  );
}

Map<String, dynamic> _paymentRow({
  String id = 'payment-1',
  String body = 'FV-00917 · \$30.000',
  Map<String, dynamic>? data,
}) {
  return _row(
    id: id,
    type: 'sales_payment_received',
    title: 'Nuevo pago recibido',
    body: body,
    entityId: id,
    data: data ??
        {
          'payment_id': id,
          'invoice_reference': 'FV-00917',
          'payment_method': 'Transferencia',
          'customer_name': 'Claudia Arcos',
          'recorded_by_name': 'Guille',
        },
  );
}

Map<String, dynamic> _voidedPaymentRow({String id = 'payment-voided-1'}) {
  return _row(
    id: id,
    type: 'sales_payment_voided',
    title: 'Pago anulado',
    body: 'FV-00917 · \$30.000',
    entityId: id,
    data: {
      'payment_id': id,
      'invoice_id': 'invoice-1',
      'invoice_reference': 'FV-00917',
      'payment_method': 'Transferencia',
      'customer_name': 'Claudia Arcos',
      'recorded_by_name': 'Guille',
      'voided_by_name': 'Vicente Díaz',
      'is_voided': true,
    },
  );
}

Map<String, dynamic> _expenseRow({String id = 'expense-1'}) {
  return _row(
    id: id,
    type: 'expense_recorded',
    title: 'Nuevo gasto registrado',
    body: 'GTO-00140 · Bicicletas del Sur · \$45.000',
    entityId: id,
    data: {
      'expense_id': id,
      'category_name': 'Suministros de Oficina',
      'document_type': 'invoice',
      'document_number': '549',
      'payment_method': 'Efectivo',
      'payment_status': 'paid',
      'posting_status': 'posted',
      'supplier_rut': '76.123.456-7',
      'recorded_by_name': 'Guille',
    },
  );
}

Map<String, dynamic> _orderRow({String id = 'order-1'}) {
  return _row(
    id: id,
    type: 'online_order_created',
    title: 'Nueva venta online',
    body: 'PED-014 · Ana Ríos · \$58.000',
    entityId: id,
    data: {
      'order_id': id,
      'order_number': 'PED-014',
      'customer_name': 'Ana Ríos',
      'delivery_type': 'pickup',
      'payment_status': 'pending',
    },
  );
}

Map<String, dynamic> _catalogRow({String id = 'product-1'}) {
  return _row(
    id: id,
    type: 'whatsapp_catalog_approved',
    title: 'Producto aprobado en WhatsApp',
    body: 'Cassette Shimano ya es visible en el catálogo de WhatsApp',
    entityId: id,
    data: {
      'product_id': id,
      'product_name': 'Cassette Shimano',
      'sku': 'CS-M771',
    },
  );
}

Map<String, dynamic> _metaRow({String id = 'meta-1'}) {
  return _row(
    id: id,
    type: 'meta_instagram_comment',
    title: 'Nuevo comentario de Instagram',
    body: 'Rosita: ¿Tienen esta talla?',
    entityId: id,
    data: {
      'provider': 'instagram',
      'interaction_type': 'comment',
      'actor_name': 'Rosita',
      'preview': '¿Tienen esta talla?',
    },
  );
}

Conversation _conversation({
  required String id,
  required String title,
  required String content,
  required int unreadCount,
  required String direction,
  bool isMine = false,
}) {
  return Conversation(
    id: id,
    type: 'support',
    channel: 'whatsapp',
    title: title,
    updatedAt: DateTime.now(),
    lastMessageAt: DateTime.now().subtract(const Duration(minutes: 1)),
    lastMessageContent: content,
    lastMessageIsMine: isMine,
    lastMessageDirection: direction,
    unreadCount: unreadCount,
    participantIds: const [],
  );
}

// ---------------------------------------------------------------------------
// Doubles
// ---------------------------------------------------------------------------

class _RecordingWorkspaceManager extends WorkspaceManager {
  final List<String> routes = <String>[];

  @override
  void navigateActiveWorkspaceFromSharedLink(String route) {
    routes.add(route);
  }
}

class _StubChatProvider extends ChatProvider {
  _StubChatProvider(this._conversations);

  final List<Conversation> _conversations;

  @override
  List<Conversation> get conversations => _conversations;
}

class _EmptyHRService extends HRService {
  _EmptyHRService()
      : super(
          TenantService.testing(
            currentUserId: () => 'user-test',
            profileLookup: (_) async => const [
              {'tenant_id': 'tenant-test'},
            ],
          ),
        );

  @override
  Future<List<DailyAttendanceBriefingEntry>> getDailyAttendanceBriefing({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async =>
      const [];
}
