import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';

import 'checkout_records_script.dart';
import 'material_icons.dart';
import 'order_page_css.dart';
import 'order_page_script.dart';
import 'site_layout.dart';

/// Where the order page asks for its summary as a PDF (a POST with the
/// order's access, never in the address).
const orderSummaryPdfPath = '/pedido/resumen.pdf';

/// What the order page needs that only the server knows: where the browser
/// reaches Supabase (the same public calls Flutter's
/// `OrderConfirmationPage` makes) and the store's transfer details from the
/// editor's payment settings.
class OrderPageData {
  const OrderPageData({
    required this.page,
    required this.orderId,
    required this.supabaseUrl,
    required this.publishableKey,
  });

  final PageContext page;
  final String orderId;
  final String supabaseUrl;
  final String publishableKey;

  String _setting(String key, [String fallback = '']) =>
      page.shell.setting(key, fallback).trim();

  String get bankName => _setting('payment_transfer_bank_name');
  String get accountType => _setting('payment_transfer_account_type');
  String get accountNumber => _setting('payment_transfer_account_number');
  String get accountHolder => _setting('payment_transfer_account_holder');
  String get rut => _setting('payment_transfer_rut');

  /// `transferProofInstructions`: the editor's text, or the contact address
  /// to send the receipt to.
  String get proofInstructions {
    final instructions = _setting('payment_transfer_instructions');
    if (instructions.isNotEmpty) return instructions;
    final email = _setting(
      'payment_transfer_contact_email',
      page.shell.setting('contact_email'),
    );
    return email.isEmpty
        ? ''
        : 'Una vez realizada la transferencia, envía el comprobante a '
              '$email con tu número de pedido.';
  }

  bool get hasTransferDestination => [
    bankName,
    accountNumber,
    accountHolder,
    rut,
  ].any((value) => value.isNotEmpty);

  /// `_buildTransferSection`'s rows before the amount, which the script adds.
  List<(String, String)> get transferRows => [
    if (bankName.isNotEmpty) ('Banco', bankName),
    if (accountNumber.isNotEmpty)
      (accountType.isNotEmpty ? accountType : 'Cuenta', accountNumber),
    if (rut.isNotEmpty) ('RUT', rut),
    if (accountHolder.isNotEmpty) ('Nombre', accountHolder),
  ];
}

/// `/pedido/<id>`, laid out like Flutter's `OrderConfirmationPage`. The
/// order's access lives in this browser tab (`CheckoutSessionStore`), so the
/// server sends the frame and the script reads the order with it, settles
/// the cart, verifies Mercado Pago's return and fills the page.
Component orderPageDocument(OrderPageData data) {
  final page = data.page;
  final shell = page.shell;
  final logo = storefrontFirstLogoSource(
    configuredUrl: shell.settings['logo_url'] ?? '',
    tenantId: page.tenantId,
  );
  return sitePage(
    context: page,
    meta: PageMeta(
      title: 'Tu pedido | ${shell.storeName}',
      description: 'El estado de tu pedido en ${shell.storeName}.',
      canonicalUrl: '${page.storeUrl}/pedido/${data.orderId}',
      indexable: false,
      styles: orderPageCss(WebsiteThemeRoles.resolve(shell.setting)),
    ),
    content: [
      div(
        classes: 'od-page',
        attributes: {
          'data-od': '',
          'data-tenant': page.tenantId,
          'data-order': data.orderId,
          'data-sb-url': data.supabaseUrl,
          'data-sb-key': data.publishableKey,
          'data-pdf-url': '${page.hidden ? '/_html' : ''}$orderSummaryPdfPath',
          // Glyphs the script swaps by the order's state.
          'data-icon-check': materialIcon(mdCheck, size: 22),
          'data-icon-close': materialIcon(mdClose, size: 22),
          'data-icon-schedule': materialIcon(mdSchedule, size: 22),
          'data-icon-block': materialIcon(mdBlock, size: 22),
          'data-icon-bank': materialIcon(mdAccountBalance, size: 22),
          'data-icon-info': materialIcon(mdInfoOutline, size: 20),
          'data-icon-error': materialIcon(mdErrorOutline, size: 20),
          'data-icon-ok': materialIcon(mdCheckCircleOutline, size: 20),
          'data-icon-blocked': materialIcon(mdBlockOutlined, size: 20),
          'data-icon-bag': materialIcon(mdShoppingBagOutlined, size: 62),
          'data-icon-failed': materialIcon(mdErrorOutline, size: 62),
        },
        [
          _cartWarning(),
          div(
            classes: 'od-load',
            attributes: {'data-od-loading': '', 'aria-label': 'Cargando'},
            [
              if (logo.isEmpty)
                span(classes: 'od-load-name', [.text(shell.storeName)])
              else
                img(
                  src: logo.startsWith('http') ? logo : '/$logo',
                  alt: '',
                  width: 200,
                  height: 200,
                ),
            ],
          ),
          _stateView(),
          div(
            classes: 'od-in',
            attributes: {'data-od-full': '', 'hidden': ''},
            [
              _hero(),
              div(classes: 'od-grid', [
                div(classes: 'od-main', [
                  _section('Detalle del pedido', [
                    Component.element(
                      tag: 'dl',
                      classes: 'od-rows',
                      attributes: {'data-od-details': ''},
                    ),
                  ]),
                  _section('Productos', [
                    ul(
                      classes: 'od-items',
                      attributes: {'data-od-items': ''},
                      const [],
                    ),
                  ]),
                  _transfer(data),
                  _section('Qué sigue', [
                    ul(
                      classes: 'od-steps',
                      attributes: {'data-od-steps': ''},
                      const [],
                    ),
                  ]),
                ]),
                _summary(),
              ]),
            ],
          ),
          Component.element(
            tag: 'noscript',
            children: [
              p(classes: 'od-noscript', [
                .text(
                  'El acceso a tu pedido se guarda en esta pestaña: activa '
                  'JavaScript para verlo.',
                ),
              ]),
            ],
          ),
          p(
            classes: 'od-toast',
            attributes: {'data-od-toast': '', 'role': 'status', 'hidden': ''},
            const [],
          ),
        ],
      ),
    ],
    pageScripts: [
      script(content: checkoutRecordsScript),
      script(content: orderPageScript),
    ],
  );
}

Component _cartWarning() => div(
  classes: 'od-warn',
  attributes: {'data-od-warn': '', 'role': 'status', 'hidden': ''},
  [
    RawText(materialIcon(mdInfoOutline, size: 20)),
    div([
      p([
        .text(
          'Tu pedido se completó. Revisa tu carrito: puede que aún contenga '
          'artículos comprados.',
        ),
      ]),
      div(classes: 'od-warn-acts', [
        a(classes: 'od-warn-cart', href: '/carrito', [.text('VER CARRITO')]),
        button(
          classes: 'od-warn-ok',
          attributes: {'type': 'button', 'data-act': 'ack'},
          [
            span(classes: 'od-spin', attributes: {'hidden': ''}, const []),
            span([.text('ENTENDIDO')]),
          ],
        ),
      ]),
    ]),
  ],
);

/// `_buildStateView`: the error and the order that is not there.
Component _stateView() => div(
  classes: 'od-state',
  attributes: {'data-od-state': '', 'hidden': ''},
  [
    span(classes: 'od-state-box', attributes: {'data-od-state-icon': ''}, []),
    h1(classes: 'od-state-title', attributes: {'data-od-state-title': ''}, []),
    span(classes: 'od-state-bar', const []),
    p(attributes: {'data-od-state-text': ''}, const []),
    a(classes: 'od-go', href: '/', [.text('VOLVER AL INICIO')]),
  ],
);

Component _hero() => Component.element(
  tag: 'section',
  classes: 'od-hero',
  attributes: {'data-od-hero': ''},
  children: [
    div(classes: 'od-hero-top', [
      div(classes: 'od-hero-text', [
        div(classes: 'od-kick', [
          span(
            classes: 'od-kick-ic',
            attributes: {'data-od-kick-icon': ''},
            [],
          ),
          span(attributes: {'data-od-kicker': ''}, const []),
        ]),
        h1(classes: 'od-title', attributes: {'data-od-title': ''}, const []),
        p(classes: 'od-sub', attributes: {'data-od-sub': ''}, const []),
      ]),
      div(classes: 'od-card', [
        span(classes: 'od-card-store', attributes: {'data-od-store': ''}, []),
        span(classes: 'od-card-label', [.text('PEDIDO')]),
        b(classes: 'od-card-number', attributes: {'data-od-number': ''}, []),
        span(classes: 'od-card-rule', const []),
        div(classes: 'od-fact', [
          span([.text('TOTAL')]),
          b(attributes: {'data-od-total': ''}, const []),
        ]),
        div(classes: 'od-fact', [
          span([.text('PAGO')]),
          b(attributes: {'data-od-method': ''}, const []),
        ]),
      ]),
    ]),
    p(
      classes: 'od-status',
      attributes: {'data-od-status': '', 'hidden': ''},
      [
        span(
          classes: 'od-status-ic',
          attributes: {'data-od-status-icon': ''},
          [],
        ),
        span(attributes: {'data-od-status-text': ''}, const []),
      ],
    ),
  ],
);

Component _section(
  String title,
  List<Component> children, {
  Map<String, String> attributes = const {},
}) => Component.element(
  tag: 'section',
  classes: 'od-sec',
  attributes: attributes,
  children: [
    h2(classes: 'od-sec-title', [.text(title.toUpperCase())]),
    ...children,
  ],
);

/// `_buildTransferSection`: shown only while a transfer waits for its
/// receipt; the amount row is the order's.
Component _transfer(OrderPageData data) => _section(
  'Instrucciones de pago',
  attributes: {'data-od-transfer': '', 'hidden': ''},
  [
    p(classes: 'od-lead', [
      .text('Para completar tu pedido, realiza una transferencia bancaria a:'),
    ]),
    Component.element(
      tag: 'dl',
      classes: 'od-rows pay',
      children: [
        for (final (label, value) in data.transferRows) _row(label, value),
        div(classes: 'od-row', [
          Component.element(tag: 'dt', children: [.text('MONTO')]),
          Component.element(
            tag: 'dd',
            attributes: {'data-od-amount': ''},
            children: const [],
          ),
        ]),
      ],
    ),
    if (!data.hasTransferDestination)
      p(classes: 'od-note', [
        .text(
          'Nuestro equipo te compartirá los datos de transferencia para '
          'completar el pago.',
        ),
      ]),
    if (data.proofInstructions.isNotEmpty)
      p(classes: 'od-note', [.text(data.proofInstructions)]),
  ],
);

Component _row(String label, String value) => div(classes: 'od-row', [
  Component.element(tag: 'dt', children: [.text(label.toUpperCase())]),
  Component.element(tag: 'dd', children: [.text(value)]),
]);

/// `_buildSummaryRail`.
Component _summary() => Component.element(
  tag: 'aside',
  classes: 'od-sum',
  attributes: {'aria-label': 'Resumen del pedido'},
  children: [
    h2(classes: 'od-sum-title', attributes: {'data-od-sum-title': ''}, []),
    b(classes: 'od-sum-number', attributes: {'data-od-sum-number': ''}, []),
    div(classes: 'od-pills', [
      span(classes: 'od-pill', attributes: {'data-od-pill-method': ''}, []),
      span(classes: 'od-pill', attributes: {'data-od-pill-state': ''}, []),
    ]),
    div(classes: 'od-metrics', attributes: {'data-od-metrics': ''}, const []),
    span(classes: 'od-rule', const []),
    div(classes: 'od-total', [
      span([.text('TOTAL')]),
      b(attributes: {'data-od-sum-total': ''}, const []),
    ]),
    div(classes: 'od-acts', [
      button(
        classes: 'od-btn fill',
        attributes: {'type': 'button', 'data-act': 'retry', 'hidden': ''},
        [
          span(classes: 'od-btn-ic', [
            RawText(materialIcon(mdPayment, size: 18)),
          ]),
          span(classes: 'od-spin', attributes: {'hidden': ''}, const []),
          span(attributes: {'data-od-retry-label': ''}, const []),
        ],
      ),
      button(
        classes: 'od-btn line',
        attributes: {'type': 'button', 'data-act': 'pdf'},
        [
          span(classes: 'od-btn-ic', [
            RawText(materialIcon(mdDownload, size: 18)),
          ]),
          span(classes: 'od-spin', attributes: {'hidden': ''}, const []),
          span([.text('DESCARGAR RESUMEN DEL PEDIDO')]),
        ],
      ),
      p(classes: 'od-doc', [
        .text(
          'Documento informativo: no acredita pago ni reemplaza una boleta o '
          'voucher oficial.',
        ),
      ]),
      a(classes: 'od-btn line', href: '/productos', [
        span([.text('SEGUIR COMPRANDO')]),
      ]),
      a(classes: 'od-btn fill', href: '/', [
        span([.text('VOLVER AL INICIO')]),
      ]),
    ]),
    span(classes: 'od-rule b', const []),
    p(classes: 'od-foot', attributes: {'data-od-foot': ''}, const []),
  ],
);
