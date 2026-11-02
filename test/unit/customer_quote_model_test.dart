import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/customer_quote.dart';

/// The shape `customer_quote_detail_v1` returns (20261102041700): the quote
/// row, the requested lines, every offer with its lines, the open draft id,
/// supplier tasks and the append-only history.
Map<String, dynamic> _detailPayload() => {
      'quote': {
        'id': 'q-1',
        'quote_number': 'COT-26-00001',
        'status': 'confirming',
        'source': 'web',
        'customer_name': 'Ana Pérez',
        'customer_phone': '+56912345678',
        'preferred_channel': 'whatsapp',
        'customer_notes': 'Para el sábado',
        'current_offer_id': null,
        'requested_at': '2026-11-02T12:00:00Z',
        'version': 3,
      },
      'settings': {'offer_validity_hours': 72, 'on_order_prepay_percent': 100},
      'requested': [
        {
          'line_no': 1,
          'product_name': 'Cámara 29 x 2.10',
          'product_sku': 'TUBE',
          'quantity': 4,
          'kind_at_request': 'on_order',
          'unit_price_reference': 6000,
        },
      ],
      'offers': [
        {
          'id': 'offer-1',
          'offer_no': 1,
          'status': 'draft',
          'lines': [
            {
              'id': 'l-1',
              'line_no': 1,
              'product_name': 'Neumático 29 x 2.25',
              'quantity_requested': 3,
              'availability': 'in_stock',
              'quantity_offered': 3,
              'unit_price': 30000,
              'tax_rate': 19,
              'confirmed_by_system': true,
              'stock_now': 5,
            },
            {
              'id': 'l-2',
              'line_no': 2,
              'product_name': 'Cámara 29 x 2.10',
              'quantity_requested': 4,
              'availability': 'on_order',
              'quantity_offered': 3,
              'unit_price': 6500,
              'tax_rate': 19,
              'unit_cost_net': 3800,
              'lead_days_min': 2,
              'lead_days_max': 4,
              'supplier_name': 'TeknoBike',
            },
            {
              'id': 'l-3',
              'line_no': 3,
              'product_name': 'Válvula',
              'quantity_requested': 1,
              'availability': 'pending',
              'quantity_offered': 0,
            },
          ],
        },
      ],
      'draftOfferId': 'offer-1',
      'tasks': [
        {
          'id': 't-1',
          'status': 'open',
          'due_at': '2026-11-03T12:00:00Z',
          'message_draft': 'Hola, necesito confirmar…',
          'supplier_name': null,
        },
      ],
      'messages': [
        {
          'id': 'm-1',
          'kind': 'offer',
          'channel': 'whatsapp',
          'recipient': '+56912345678',
          'state': 'needs_staff',
          'created_at': '2026-11-02T13:00:00Z',
        },
      ],
      'events': [
        {
          'event_type': 'offer_prepared',
          'actor_kind': 'system',
          'occurred_at': '2026-11-02T12:00:01Z',
          'detail': {'offer_no': 1, 'confirmed': 2, 'pending': 1},
        },
      ],
    };

void main() {
  test('a quote reads its draft, partial lines and supplier work', () {
    final quote = CustomerQuoteDetail.fromJson(_detailPayload());

    expect(quote.number, 'COT-26-00001');
    expect(quote.status, CustomerQuoteStatus.confirming);
    expect(quote.channel, QuoteChannel.whatsapp);
    expect(quote.draft?.number, 1);
    expect(quote.draft?.pendingLines, 1);
    expect(quote.openTasks, hasLength(1));

    final tube = quote.draft!.lines[1];
    expect(tube.isPartial, isTrue, reason: '3 offered of 4 asked');
    expect(tube.lineTotal, 19500);
    expect(tube.leadLabel, '2 a 4 días hábiles');
    // 6.500 with IVA is 5.462 net; against a 3.800 cost that is ~30 %.
    expect(tube.marginPercent!.round(), 30);

    // The draft total only counts what is offered: 3 × 30.000 + 3 × 6.500.
    expect(quote.draft!.draftTotal, 109500);
    expect(quote.events.single.label, 'Borrador 1 armado · 2 confirmadas · 1 por confirmar');
    // A WhatsApp offer waits for the team until a template exists.
    expect(quote.messages.single.needsStaff, isTrue);
    expect(quote.messages.single.stateLabel, 'Por enviar');
  });

  test('the inbox counts by status and keeps the row facts', () {
    final inbox = CustomerQuoteInbox.fromJson({
      'counts': {'confirming': 2, 'offered': 1},
      'quotes': [
        {
          'id': 'q-1',
          'number': 'COT-26-00001',
          'status': 'offered',
          'source': 'web',
          'customerName': 'Ana',
          'preferredChannel': 'email',
          'requestedAt': '2026-11-02T12:00:00Z',
          'updatedAt': '2026-11-02T13:00:00Z',
          'expiresAt': '2026-11-05T13:00:00Z',
          'lines': 3,
          'total': 148000,
          'openTasks': 0,
        },
      ],
    });

    expect(inbox.count(CustomerQuoteStatus.confirming), 2);
    expect(inbox.count(CustomerQuoteStatus.accepted), 0);
    expect(inbox.quotes.single.channel, QuoteChannel.email);
    expect(inbox.quotes.single.total, 148000);
  });
}
