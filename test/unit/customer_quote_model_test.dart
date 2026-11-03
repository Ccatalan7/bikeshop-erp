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
        'notify_email': false,
        'notify_whatsapp': true,
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
    expect(quote.notices, [QuoteChannel.whatsapp]);
    expect(quote.notifiesByEmail, isFalse);
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
    expect(quote.events.single.label,
        'Borrador 1 armado · 2 confirmadas · 1 por confirmar');
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
          'notifyEmail': true,
          'notifyWhatsapp': false,
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
    expect(inbox.quotes.single.notices, [QuoteChannel.email]);
    expect(inbox.quotes.single.total, 148000);
    expect(inbox.quotes.single.isWorkshop, isFalse);
  });

  // 20261102100000: a shop «Cotización» (a workshop job without a received
  // bicycle) is listed beside the site's, and opens in Trabajos.
  test('a shop quotation has no channel and says when it was converted', () {
    final inbox = CustomerQuoteInbox.fromJson({
      'counts': {'offered': 1, 'accepted': 1},
      'quotes': [
        {
          'id': 'job-1',
          'number': 'PG-00654',
          'status': 'offered',
          'source': 'workshop',
          'customerName': 'Cliente Taller',
          'notifyEmail': null,
          'notifyWhatsapp': null,
          'requestedAt': '2026-10-30T21:56:49Z',
          'updatedAt': '2026-10-30T21:56:50Z',
          'expiresAt': '2026-11-29T21:55:50Z',
          'lines': 4,
          'total': 160000,
          'openTasks': 0,
          'converted': false,
        },
        {
          'id': 'job-2',
          'number': 'PG-00470',
          'status': 'accepted',
          'source': 'workshop',
          'customerName': 'Otro cliente',
          'requestedAt': '2026-07-16T12:00:00Z',
          'updatedAt': '2026-07-16T13:00:00Z',
          'lines': 2,
          'total': 31000,
          'converted': true,
        },
      ],
    });

    final pending = inbox.quotes.first;
    expect(pending.isWorkshop, isTrue);
    expect(pending.notices, isEmpty, reason: 'the shop does not say a channel');
    expect(pending.status, CustomerQuoteStatus.offered);
    expect(pending.converted, isFalse);
    expect(inbox.quotes.last.converted, isTrue);
    expect(inbox.count(CustomerQuoteStatus.accepted), 1);
  });

  // 20261102175500: the customer picks email, WhatsApp or both, and the
  // quote follows the account's data.
  test('the notices read as the customer chose them, in the shop\'s words', () {
    expect(
        QuoteChannel.labelOf(QuoteChannel.chosen(email: true, whatsapp: true)),
        'Correo y WhatsApp');
    expect(
        QuoteChannel.inSentence(
            QuoteChannel.chosen(email: true, whatsapp: true)),
        'correo y WhatsApp');
    expect(
        QuoteChannel.inSentence(
            QuoteChannel.chosen(email: false, whatsapp: true)),
        'WhatsApp');

    CustomerQuoteEvent event(String type, Map<String, dynamic> detail) =>
        CustomerQuoteEvent.fromJson({
          'event_type': type,
          'actor_kind': type == 'notify_changed' ? 'customer' : 'system',
          'occurred_at': '2026-11-02T18:00:00Z',
          'detail': detail,
        });
    expect(
      event('notify_changed', {'notify_email': true, 'notify_whatsapp': true})
          .label,
      'El cliente cambió sus avisos: correo y WhatsApp',
    );
    expect(
      event('contact_updated', {'phone': true, 'whatsapp_dropped': true}).label,
      'Su cuenta quedó sin teléfono: ahora avisa por correo',
    );
    expect(
      event('contact_updated', {'phone': true, 'whatsapp_dropped': false})
          .label,
      'Tomó los datos nuevos de su cuenta',
    );

    final quote = CustomerQuoteDetail.fromJson({
      'quote': {
        'id': 'q-2',
        'quote_number': 'COT-26-00002',
        'status': 'offered',
        'source': 'web',
        'customer_id': 'c-1',
        'customer_name': 'Ana',
        'customer_email': 'ana@example.invalid',
        'customer_phone': '+56912345678',
        'notify_email': true,
        'notify_whatsapp': true,
        'requested_at': '2026-11-02T12:00:00Z',
        'version': 2,
      },
    });
    expect(quote.notices, [QuoteChannel.email, QuoteChannel.whatsapp]);
    expect(quote.fromAccount, isTrue);
  });

  // 20261103010000: accepting makes a web order. The detail carries it with
  // where each line comes from and the supplier orders drafted on payment.
  test('the accepted quote reads its order, lines and supplier orders', () {
    final quote = CustomerQuoteDetail.fromJson({
      'quote': {
        'id': 'q-3',
        'quote_number': 'COT-26-00003',
        'status': 'accepted',
        'source': 'web',
        'customer_name': 'Ana',
        'notify_email': true,
        'notify_whatsapp': false,
        'requested_at': '2026-11-02T12:00:00Z',
        'version': 5,
      },
      'order': {
        'id': 'o-1',
        'number': 'WEB-26-00010',
        'status': 'confirmed',
        'payment_status': 'paid',
        'payment_method': 'mercadopago',
        'delivery_type': 'pickup',
        'total': 126000,
        'shipping_cost': 0,
        'paid_at': '2026-11-03T13:00:00Z',
        'waiting': true,
        'items': [
          {
            'id': 'i-1',
            'product_name': 'Neumático 29 x 2.25',
            'quantity': 1,
            'fulfillment': 'stock',
          },
          {
            'id': 'i-2',
            'product_name': 'Neumático 29 x 2.40',
            'quantity': 2,
            'fulfillment': 'on_order',
            'supplier_id': 's-1',
            'supplier_name': 'Proveedor de neumáticos',
            'lead_days_min': 3,
            'lead_days_max': 5,
          },
          {
            'id': 'i-3',
            'product_name': 'Válvula',
            'quantity': 1,
            'fulfillment': 'on_order',
          },
        ],
        'purchases': [
          {
            'id': 'p-1',
            'supplier_id': 's-1',
            'supplier_name': 'Proveedor de neumáticos',
            'purchase_invoice_id': 'ped-1',
            'number': 'PED-202611-00042',
            'status': 'draft',
            'total': 63070,
          },
        ],
      },
    });
    final order = quote.order!;
    expect(order.number, 'WEB-26-00010');
    expect(order.stateLabel, 'Pagado · falta que llegue');
    expect(order.items[1].leadLabel, '3 a 5 días hábiles');
    expect(order.items[1].waiting, isTrue);
    expect(order.items.first.onOrder, isFalse);
    expect(order.missingSupplier, 1, reason: 'the valve has no supplier');
    expect(order.purchases.single.statusLabel, 'Por enviar');
    expect(order.purchases.single.isDraft, isTrue);

    CustomerQuoteEvent event(String type, Map<String, dynamic> detail) =>
        CustomerQuoteEvent.fromJson({
          'event_type': type,
          'actor_kind': 'system',
          'occurred_at': '2026-11-03T13:00:00Z',
          'detail': detail,
        });
    expect(
      event('order_waiting', {'purchases': 1, 'without_supplier': 1}).label,
      'Pagado: el pedido al proveedor quedó en borrador · un producto sin '
      'proveedor',
    );
    expect(
      event('order_waiting', {'purchases': 0, 'without_supplier': 2}).label,
      'Pagado: falta armar el pedido al proveedor · 2 productos sin proveedor',
    );
    expect(event('order_line_arrived', {'product': 'Válvula'}).label,
        'Llegó Válvula');
    expect(event('order_sale_issued', {'invoice_number': 'B-120'}).label,
        'Llegó todo: venta B-120 emitida');
    expect(
      event('order_refunded', {'amount': 58000, 'reference': 'DEV-1'}).label,
      'Se devolvió el pago · \$58.000 · ref. DEV-1',
    );
    expect(order.canCancelAndRefund, isTrue,
        reason: 'paid and without a sale: cancelled by returning the money');
    expect(
      CustomerQuoteOrder.fromJson({
        'id': 'o-3',
        'number': 'WEB-26-00012',
        'status': 'cancelled',
        'payment_status': 'refunded',
      }).stateLabel,
      'Anulado · devuelto',
    );

    final waitingTransfer = CustomerQuoteOrder.fromJson({
      'id': 'o-2',
      'number': 'WEB-26-00011',
      'status': 'pending',
      'payment_status': 'pending',
      'payment_method': 'transfer',
      'waiting': true,
    });
    expect(waitingTransfer.stateLabel, 'Esperando la transferencia');
    expect(
      CustomerQuoteSummary.fromJson({
        'id': 'q-3',
        'number': 'COT-26-00003',
        'status': 'accepted',
        'source': 'web',
        'customerName': 'Ana',
        'requestedAt': '2026-11-02T12:00:00Z',
        'orderNumber': 'WEB-26-00010',
        'orderWaiting': true,
      }).orderWaiting,
      isTrue,
    );
  });
}
