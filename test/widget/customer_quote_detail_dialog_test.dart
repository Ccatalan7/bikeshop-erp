import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/sales/models/customer_quote.dart';
import 'package:vinabike_erp/modules/sales/services/customer_quote_service.dart';
import 'package:vinabike_erp/modules/sales/widgets/customer_quote_detail_view.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Answers like `customer_quote_detail_v1` and `customer_quote_cancel_v1`,
/// without a database.
class _FakeQuotes implements CustomerQuoteService {
  Map<String, dynamic> quote = {
    'id': 'q-1',
    'quote_number': 'COT-26-00001',
    'status': 'confirming',
    'source': 'web',
    'customer_name': 'Ana Pérez',
    'customer_phone': '+56912345678',
    'preferred_channel': 'whatsapp',
    'notify_email': false,
    'notify_whatsapp': true,
    'requested_at': '2026-11-02T12:00:00Z',
    'version': 1,
  };
  String? cancelReason;

  Map<String, dynamic> get _payload => {
        'quote': quote,
        'settings': {
          'offer_validity_hours': 72,
          'on_order_prepay_percent': 100
        },
        'requested': const [],
        'offers': const [],
        'tasks': const [],
        'messages': const [],
        'events': const [],
      };

  @override
  Future<CustomerQuoteDetail> fetchDetail(String quoteId) async =>
      CustomerQuoteDetail.fromJson(_payload);

  @override
  Future<CustomerQuoteDetail> cancel(
    String quoteId, {
    required String operationKey,
    required String reason,
  }) async {
    cancelReason = reason;
    quote = {...quote, 'status': 'cancelled'};
    return CustomerQuoteDetail.fromJson(_payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  // 2026-11-02: «Enviar oferta» crashed the app with `_dependents.isEmpty`.
  // The field's controller was disposed when `showDialog` resolved, which
  // happens as `pop` starts, while the exit transition still shows the field.
  // The dialog owns its controller now (GUI_DESIGN_PRINCIPLES: a routed sheet
  // owns its listenables).
  testWidgets(
      'a reason typed in the dialog cancels the quote and closing it does '
      'not throw', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quotes = _FakeQuotes();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: CustomerQuoteDetailView(quoteId: 'q-1', service: quotes),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anular'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('customer-quote-dialog-text'));
    await tester.enterText(field, 'Prueba interna del sistema');
    await tester.pump();
    await tester.tap(find.text('Anular cotización'));
    // Frame by frame through the exit transition, which still has the field.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(quotes.cancelReason, 'Prueba interna del sistema');
    expect(field, findsNothing);
    expect(find.text('Anular'), findsNothing,
        reason: 'a cancelled quote has nothing left to cancel');
  });
}
