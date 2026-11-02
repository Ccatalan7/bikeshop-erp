part of 'portal_page_view.dart';

// «Cotizaciones» (`/cuenta/cotizaciones`, 2026-11-02): the account's quotes,
// newest first, each opening its page (`/cotizacion#q=<id>`, where the page
// asks for a fresh link with the session). A quote belongs to an account
// since 20261102175500.

/// A quote of the account as `list_my_customer_quotes_v1` reads it: no
/// contact data and no link.
class PortalQuote {
  const PortalQuote({
    required this.id,
    required this.number,
    required this.status,
    required this.requestedAt,
    required this.lines,
    this.expiresAt,
    this.total,
  });

  final String id;
  final String number;
  final String status;
  final DateTime requestedAt;
  final int lines;

  /// Until when the offer is valid, only while it waits for the customer.
  final DateTime? expiresAt;

  /// The total of the offer sent, IVA included.
  final num? total;

  static PortalQuote? fromJson(Object? row) {
    if (row is! Map) return null;
    final id = row['id']?.toString() ?? '';
    final requestedAt = DateTime.tryParse(row['requestedAt']?.toString() ?? '');
    if (id.isEmpty || requestedAt == null) return null;
    final lines = row['lines'];
    final total = row['total'];
    return PortalQuote(
      id: id,
      number: row['number']?.toString() ?? '',
      status: row['status']?.toString() ?? 'confirming',
      requestedAt: requestedAt,
      lines: lines is num ? lines.toInt() : int.tryParse('$lines') ?? 0,
      expiresAt: DateTime.tryParse(row['expiresAt']?.toString() ?? ''),
      total: total is num ? total : num.tryParse('${total ?? ''}'),
    );
  }

  static List<PortalQuote> fromRows(List<Object?> rows) => [
    for (final row in rows) ?fromJson(row),
  ];

  /// The quote page's words for its state.
  String get label => switch (status) {
    'confirming' => 'Confirmando',
    'offered' => 'Oferta lista',
    'accepted' => 'Aceptada',
    'rejected' => 'Rechazada',
    'expired' => 'Vencida',
    _ => 'Anulada',
  };

  PortalTone get tone => switch (status) {
    'offered' => PortalTone.warning,
    'accepted' => PortalTone.success,
    'confirming' => PortalTone.info,
    _ => PortalTone.neutral,
  };

  /// An offer is the one moment the customer has to answer.
  bool get needsCustomer => status == 'offered';

  String get summary => lines == 1 ? '1 producto' : '$lines productos';

  String? get nextStep => switch (status) {
    'offered' when expiresAt != null =>
      'Respóndela antes del ${portalDate(expiresAt!)}',
    'confirming' => 'Estamos confirmando precio y plazo',
    _ => null,
  };
}

Component _quotes(PortalViewData data) {
  final quotes = data.quotes;
  if (quotes.isEmpty) {
    return _empty(
      'Todavía no tienes cotizaciones.',
      message:
          'Agrega productos desde su ficha con «Agregar a la cotización» y '
          'te respondemos con el precio y el plazo confirmados.',
      actions: [_link('Ver productos', href: '/productos')],
    );
  }
  return _panel(
    _tableHeader('Cotización', [
      ('Número', _orderNumberColumn),
      ('Fecha', 120),
      ('Estado', 200),
    ]),
    [for (final quote in quotes) _quoteRow(quote)],
  );
}

/// A quote in a row, like an order's: in wide the columns of the table,
/// narrower stacked.
Component _quoteRow(PortalQuote quote) {
  final total = quote.total == null
      ? '—'
      : ChileanUtils.formatCurrency(quote.total!.toDouble());
  Component tag() => _statusTag(
    quote.label,
    quote.tone,
    needsCustomer: quote.needsCustomer,
    active: quote.status == 'confirming',
  );
  final date = portalDate(quote.requestedAt).replaceAll(' ', ' ');
  final nextStep = quote.nextStep;
  Component what() => span(classes: 'pt-what', [
    span(classes: 'pt-row-title', [_t(quote.summary)]),
    if (nextStep != null) span(classes: 'pt-next', [_t(nextStep)]),
  ]);
  Component meta() =>
      span(classes: 'pt-row-meta', [_t('${quote.number} · $date')]);
  Component thumb(int size) =>
      _thumb(fallback: mdDescriptionOutlined, size: size);
  final arrow = RawText(materialIcon(mdArrowForward, size: 18));
  return a(
    classes: 'pt-row',
    href: '/cotizacion#q=${Uri.encodeComponent(quote.id)}',
    attributes: {
      'aria-label': 'Cotización ${quote.number}, ${quote.label}, $total',
    },
    [
      span(classes: 'pt-row-table', [
        thumb(72),
        what(),
        span(
          classes: 'pt-row-num',
          attributes: {'style': 'width:${_orderNumberColumn}px'},
          [_t(quote.number)],
        ),
        span(classes: 'pt-row-date', [_t(date)]),
        span(classes: 'pt-row-state', [tag()]),
        span(classes: 'pt-row-total', [_t(total)]),
        arrow,
      ]),
      span(classes: 'pt-row-mid', [
        thumb(72),
        span(classes: 'pt-what', [what(), meta()]),
        span(classes: 'pt-row-end', [
          span(classes: 'pt-fig', [_t(total)]),
          tag(),
        ]),
        arrow,
      ]),
      span(classes: 'pt-row-phone', [
        thumb(64),
        span(classes: 'pt-what', [
          what(),
          meta(),
          span(classes: 'pt-row-foot', [
            tag(),
            span(classes: 'pt-fig small', [_t(total)]),
          ]),
        ]),
      ]),
    ],
  );
}
