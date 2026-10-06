import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'cart_page_model.dart';
import 'checkout_page_css.dart';
import 'checkout_page_script.dart';
import 'checkout_records_script.dart';
import 'material_icons.dart';
import 'site_layout.dart';

/// Where the checkout asks for the visitor's lines
/// (`/checkout/lineas?l=<id>:<q>,…`).
const checkoutLinesPath = '/checkout/lineas';

/// What the checkout needs that only the server knows: the store's pickup
/// point (Flutter's `_pickupPointLabel`), the payment methods it accepts
/// now, and where the browser reaches Supabase with the publishable key —
/// the same public calls the Flutter checkout makes.
class CheckoutPageData {
  const CheckoutPageData({
    required this.page,
    required this.methods,
    required this.methodsKnown,
    required this.supabaseUrl,
    required this.publishableKey,
  });

  final PageContext page;

  /// The available methods in the store's order; empty with [methodsKnown]
  /// false when the read failed (Flutter's «No pudimos verificar…»).
  final List<PublicCheckoutPaymentCode> methods;
  final bool methodsKnown;
  final String supabaseUrl;
  final String publishableKey;

  static List<PublicCheckoutPaymentCode>? methodsOf(Object? raw) {
    if (raw == null) return null;
    try {
      return PublicCheckoutCapabilities.fromRpc(raw).availableMethods;
    } on FormatException {
      return null;
    }
  }

  String get storeName => page.shell.setting('store_name', 'la tienda');
  String get pickupAddress => page.shell.setting('contact_address').trim();
  String get contactPhone => page.shell.setting('contact_phone').trim();

  /// `_pickupPointLabel`.
  String get pickupPoint =>
      pickupAddress.isNotEmpty ? pickupAddress : 'Retiro en $storeName';

  /// `_pickupCustomerAddress`: what an order picked up at the store says
  /// in `customer_address`.
  String get pickupCustomerAddress =>
      pickupPoint.toLowerCase().startsWith('retiro')
      ? pickupPoint
      : 'Retiro en tienda: $pickupPoint';
}

/// `/checkout`, laid out like Flutter's `CheckoutPage`. Like the cart, the
/// basket lives in the browser: the server sends the form (the same for
/// everyone) and the page's script asks [checkoutLinesPath] for the lines,
/// quotes the delivery, and creates the order with the same Supabase calls
/// and the same recovery record (`CheckoutSessionStore`) as Flutter, so its
/// order page and Mercado Pago's return keep working unchanged.
Component checkoutPageDocument(CheckoutPageData data) {
  final page = data.page;
  final theme = WebsiteThemeRoles.resolve(page.shell.setting);
  return sitePage(
    context: page,
    meta: PageMeta(
      title: 'Finalizar compra | ${page.shell.storeName}',
      description: 'Finaliza tu compra en ${page.shell.storeName}.',
      canonicalUrl: '${page.storeUrl}/checkout',
      indexable: false,
      styles: checkoutPageCss(theme),
    ),
    content: [
      div(
        classes: 'co-page',
        attributes: {
          'data-co': '',
          'data-tenant': page.tenantId,
          'data-lines-url': '${page.hidden ? '/_html' : ''}$checkoutLinesPath',
          'data-sb-url': data.supabaseUrl,
          'data-sb-key': data.publishableKey,
          'data-pickup-address': data.pickupCustomerAddress,
          'data-origin': page.storeUrl,
          // Glyphs the script draws into rows it builds.
          'data-receipt-icon': materialIcon(mdReceiptLongOutlined, size: 24),
          'data-place-icon': materialIcon(mdPlaceOutlined, size: 24),
          'data-eye-on': materialIcon(mdVisibilityOutlined, size: 24),
          'data-eye-off': materialIcon(mdVisibilityOffOutlined, size: 24),
        },
        [
          div(classes: 'co-in', [
            _empty(),
            div(
              classes: 'co-full',
              attributes: {'data-co-full': '', 'hidden': ''},
              [
                div(classes: 'co-main', [
                  h1(classes: 'co-title', [.text('Finalizar compra')]),
                  span(classes: 'co-bar', const []),
                  p(classes: 'co-lead', [
                    .text(
                      'Completa tus datos de contacto, elige la forma de '
                      'entrega y selecciona el medio de pago antes de '
                      'confirmar tu pedido.',
                    ),
                  ]),
                  div(
                    classes: 'co-form co-restored',
                    attributes: {'data-co-restored': '', 'hidden': ''},
                    [
                      RawText(materialIcon(mdRestoreRounded, size: 26)),
                      div([
                        b([.text('PEDIDO RECUPERADO')]),
                        p([
                          .text(
                            'Los productos y totales mostrados pertenecen al '
                            'intento guardado. No se reemplazan con el '
                            'carrito actual.',
                          ),
                        ]),
                      ]),
                    ],
                  ),
                  _form(data),
                ]),
                Component.element(
                  tag: 'aside',
                  classes: 'co-sum',
                  attributes: {
                    'data-co-summary': '',
                    'aria-label': 'Resumen del pedido',
                  },
                  children: _summary(),
                ),
              ],
            ),
            p(
              classes: 'co-wait',
              attributes: {'data-co-loading': '', 'hidden': ''},
              [.text('Cargando tu pedido…')],
            ),
            p(
              classes: 'co-failed',
              attributes: {'data-co-failed': '', 'hidden': ''},
              [
                .text(
                  'No pudimos leer tu carrito en este navegador. Escríbenos '
                  'por WhatsApp y te ayudamos.',
                ),
              ],
            ),
            Component.element(
              tag: 'noscript',
              children: [
                p(classes: 'co-failed', [
                  .text(
                    'Tu carrito se guarda en este navegador: activa '
                    'JavaScript para finalizar la compra.',
                  ),
                ]),
              ],
            ),
          ]),
          // Before the first paint: empty or loading, never a blank frame.
          script(content: _firstPaintScript(page.tenantId)),
          p(
            classes: 'co-toast',
            attributes: {'data-co-toast': '', 'role': 'status', 'hidden': ''},
            const [],
          ),
        ],
      ),
    ],
    pageScripts: [
      script(content: checkoutRecordsScript),
      script(content: checkoutPageScript),
    ],
  );
}

Component _el(
  String tag, {
  String? classes,
  Map<String, String> attributes = const {},
  List<Component> children = const [],
}) => Component.element(
  tag: tag,
  classes: classes,
  attributes: attributes,
  children: children,
);

Component _empty() => div(
  classes: 'co-empty',
  attributes: {'data-co-empty': '', 'hidden': ''},
  [
    span(classes: 'co-empty-box', [
      RawText(materialIcon(mdCartOutlined, size: 62)),
    ]),
    div(classes: 'co-empty-head', [
      h2(classes: 'co-title', [.text('No hay productos para finalizar')]),
      span(classes: 'co-bar', const []),
    ]),
    p([
      .text(
        'Vuelve al catálogo, revisa productos y agrega artículos antes de '
        'continuar al checkout.',
      ),
    ]),
    a(classes: 'co-go', href: '/productos', [
      RawText(materialIcon(mdShoppingBagOutlined, size: 18)),
      .text('Explorar productos'),
    ]),
  ],
);

/// One Material outlined field. [name] is the key the script reads.
Component _field({
  required String name,
  required String label,
  required String icon,
  String type = 'text',
  String? hint,
  String? autocomplete,
  String? inputmode,
  String? helper,
  bool textarea = false,
  bool password = false,
  String? classes,
}) {
  final id = 'co-$name';
  final control = textarea
      ? _el(
          'textarea',
          attributes: {
            'id': id,
            'name': name,
            'rows': '4',
            'placeholder': hint ?? ' ',
            'aria-describedby': '$id-msg',
          },
        )
      : _el(
          'input',
          attributes: {
            'id': id,
            'name': name,
            'type': type,
            'placeholder': hint ?? ' ',
            'autocomplete': ?autocomplete,
            'inputmode': ?inputmode,
            'aria-describedby': '$id-msg',
            if (type == 'email' || type == 'tel') 'spellcheck': 'false',
          },
        );
  return div(
    classes: [
      'co-f',
      if (textarea) 'ta',
      if (password) 'pw',
      ?classes,
    ].join(' '),
    attributes: {'data-f': name},
    [
      div(classes: 'co-f-box', [
        span(classes: 'co-f-ic', [RawText(materialIcon(icon, size: 20))]),
        control,
        _el('label', attributes: {'for': id}, children: [.text(label)]),
        _el(
          'fieldset',
          attributes: {'aria-hidden': 'true'},
          children: [
            _el(
              'legend',
              children: [
                span([.text(label)]),
              ],
            ),
          ],
        ),
        if (password)
          button(
            classes: 'co-f-eye',
            attributes: {
              'type': 'button',
              'data-act': 'eye',
              'aria-label': 'Mostrar contraseña',
            },
            [RawText(materialIcon(mdVisibilityOutlined, size: 24))],
          ),
      ]),
      p(
        classes: 'co-f-msg',
        attributes: {
          'id': '$id-msg',
          'data-msg': '',
          'data-helper': ?helper,
          'aria-live': 'polite',
        },
        [if (helper != null) .text(helper)],
      ),
    ],
  );
}

Component _section(String title, List<Component> children, {String? id}) => _el(
  'section',
  classes: 'co-sec',
  attributes: {'data-sec': ?id},
  children: [
    h2(classes: 'co-sec-title', [.text(title.toUpperCase())]),
    ...children,
  ],
);

Component _option({
  required String group,
  required String value,
  required String title,
  required String subtitle,
  String? icon,
  String? badge,
  bool checked = false,
}) => _el(
  'label',
  classes: 'co-opt',
  children: [
    _el(
      'input',
      attributes: {
        'type': 'radio',
        'name': group,
        'value': value,
        if (checked) 'checked': '',
      },
    ),
    span(classes: 'co-radio', const []),
    if (icon != null)
      span(classes: 'co-opt-ic', [RawText(materialIcon(icon, size: 22))]),
    span(classes: icon == null ? 'co-opt-body no-ic' : 'co-opt-body', [
      span(classes: 'co-opt-title', [
        span([.text(title)]),
        if (badge != null) span(classes: 'co-pill', [.text(badge)]),
      ]),
      span(classes: 'co-opt-sub', [.text(subtitle)]),
    ]),
  ],
);

Component _form(CheckoutPageData data) => _el(
  'form',
  classes: 'co-form',
  attributes: {'data-co-form': '', 'novalidate': ''},
  children: [
    _section('1. Información de contacto', [
      div(classes: 'co-stack', [
        _field(
          name: 'name',
          label: 'Nombre completo *',
          icon: mdPersonOutline,
          autocomplete: 'name',
        ),
        _field(
          name: 'email',
          label: 'Correo electrónico *',
          icon: mdEmailOutlined,
          type: 'email',
          autocomplete: 'email',
        ),
        _field(
          name: 'phone',
          label: 'Teléfono *',
          icon: mdPhoneOutlined,
          type: 'tel',
          hint: '+56 9 1234 5678',
          autocomplete: 'tel',
        ),
        div(
          classes: 'co-box',
          attributes: {'data-co-account': ''},
          [
            _el(
              'label',
              classes: 'co-check',
              children: [
                _el(
                  'input',
                  attributes: {'type': 'checkbox', 'name': 'create_account'},
                ),
                span(classes: 'co-check-mark', const []),
                span(classes: 'co-check-text', [
                  b([.text('Crear una cuenta con estos datos')]),
                  span([
                    .text(
                      'Te enviaremos una confirmación por correo para '
                      'activar el acceso a pedidos, direcciones y servicios.',
                    ),
                  ]),
                ]),
              ],
            ),
            div(
              classes: 'co-stack',
              attributes: {'data-co-password': '', 'hidden': ''},
              [
                _field(
                  name: 'password',
                  label: 'Contraseña para tu cuenta *',
                  icon: mdLockOutline,
                  type: 'password',
                  autocomplete: 'new-password',
                  helper:
                      'Mínimo 8 caracteres, con al menos una letra y un '
                      'número',
                  password: true,
                ),
                _field(
                  name: 'password_confirm',
                  label: 'Confirmar contraseña *',
                  icon: mdLockResetOutlined,
                  type: 'password',
                  autocomplete: 'new-password',
                ),
              ],
            ),
          ],
        ),
      ]),
    ]),
    _section('2. Entrega', [
      _el(
        'fieldset',
        classes: 'co-opts',
        attributes: {'data-co-delivery': ''},
        children: [
          _el('legend', classes: 'sr', children: [.text('Forma de entrega')]),
          _option(
            group: 'delivery',
            value: 'shipping',
            title: 'Despacho a domicilio',
            subtitle:
                'Chile continental, 3 a 12 días hábiles. Verás el costo '
                'exacto antes de realizar el pedido.',
            icon: mdLocalShippingOutlined,
            checked: true,
          ),
          _option(
            group: 'delivery',
            value: 'pickup',
            title: 'Retiro en tienda',
            subtitle:
                'Compra online y retira cuando recibas la confirmación '
                'de que tu pedido está listo.',
            icon: mdStorefrontOutlined,
          ),
        ],
      ),
      div(
        classes: 'co-ship',
        attributes: {'data-co-shipping': ''},
        [
          div(
            classes: 'co-f',
            attributes: {'data-co-saved': '', 'data-f': 'saved', 'hidden': ''},
            [
              div(classes: 'co-f-box', [
                span(classes: 'co-f-ic', [
                  RawText(materialIcon(mdBookmarkOutline, size: 20)),
                ]),
                _el('select', attributes: {'id': 'co-saved', 'name': 'saved'}),
                _el(
                  'label',
                  attributes: {'for': 'co-saved'},
                  children: [.text('Usar dirección guardada')],
                ),
                _el(
                  'fieldset',
                  attributes: {'aria-hidden': 'true'},
                  children: [
                    _el(
                      'legend',
                      children: [
                        span([.text('Usar dirección guardada')]),
                      ],
                    ),
                  ],
                ),
                span(classes: 'co-f-caret', [
                  RawText(materialIcon(mdKeyboardArrowDown, size: 24)),
                ]),
              ]),
            ],
          ),
          div(
            classes: 'co-search',
            attributes: {'data-co-search': '', 'hidden': ''},
            [
              _field(
                name: 'address',
                label: 'Buscar dirección',
                icon: mdSearch,
                hint: 'Ej: Álvarez 32, Viña del Mar',
                autocomplete: 'off',
              ),
              _el(
                'ul',
                classes: 'co-sugs',
                attributes: {
                  'id': 'co-sugs',
                  'role': 'listbox',
                  'data-co-sugs': '',
                  'hidden': '',
                },
              ),
              p(classes: 'co-hint', [
                .text(
                  'Selecciona una sugerencia y revisa los datos antes de '
                  'confirmar.',
                ),
              ]),
            ],
          ),
          p(
            classes: 'co-hint solo',
            attributes: {'data-co-manual': '', 'hidden': ''},
            [
              .text(
                'Puedes escribir tu dirección manualmente. Separarla nos ayuda '
                'a guardarla mejor en tu cuenta.',
              ),
            ],
          ),
          div(classes: 'co-addr', [
            _field(
              name: 'street',
              label: 'Calle *',
              icon: mdSignpostOutlined,
              hint: 'Ej: Álvarez',
              autocomplete: 'address-line1',
            ),
            _field(
              name: 'street_number',
              label: 'Número',
              icon: mdPinOutlined,
              hint: 'Ej: 32',
            ),
            _field(
              name: 'apartment',
              label: 'Depto / oficina / local',
              icon: mdApartmentOutlined,
              hint: 'Opcional',
              autocomplete: 'address-line2',
            ),
            _field(
              name: 'comuna',
              label: 'Comuna *',
              icon: mdLocationCityOutlined,
              hint: 'Ej: Viña del Mar',
              autocomplete: 'address-level3',
            ),
            _field(
              name: 'city',
              label: 'Ciudad',
              icon: mdDomainOutlined,
              hint: 'Ej: Viña del Mar',
              autocomplete: 'address-level2',
            ),
            _field(
              name: 'region',
              label: 'Región *',
              icon: mdMapOutlined,
              hint: 'Ej: Valparaíso',
              autocomplete: 'address-level1',
            ),
            _field(
              name: 'postal_code',
              label: 'Código postal',
              icon: mdMarkunreadMailboxOutlined,
              hint: 'Opcional',
              autocomplete: 'postal-code',
              classes: 'half',
            ),
          ]),
          div(
            attributes: {'data-co-label': '', 'hidden': ''},
            [
              div(classes: 'co-label-row', [
                _field(
                  name: 'address_label',
                  label: 'Etiqueta (ej: Casa, Trabajo)',
                  icon: mdLabelOutline,
                ),
              ]),
              _el(
                'label',
                classes: 'co-check co-save',
                children: [
                  _el(
                    'input',
                    attributes: {
                      'type': 'checkbox',
                      'name': 'save_address',
                      'checked': '',
                    },
                  ),
                  span(classes: 'co-check-mark', const []),
                  span(classes: 'co-check-text', [
                    b([.text('Guardar esta dirección en mi cuenta')]),
                  ]),
                ],
              ),
            ],
          ),
          a(
            classes: 'co-manage',
            href: '/cuenta/direcciones',
            attributes: {'data-co-manage': '', 'hidden': ''},
            [
              RawText(materialIcon(mdOpenInNew, size: 16)),
              .text('Gestionar mis direcciones guardadas'),
            ],
          ),
        ],
      ),
      div(
        classes: 'co-ship co-box',
        attributes: {'data-co-pickup': '', 'hidden': ''},
        [
          div(classes: 'co-pick-head', [
            RawText(materialIcon(mdStorefrontOutlined, size: 22)),
            div([
              b([.text('Retiro en ${data.storeName}')]),
              span([
                .text(
                  'La tienda preparará tu pedido y te avisará antes de que '
                  'pases a buscarlo.',
                ),
              ]),
            ]),
          ]),
          _el(
            'dl',
            classes: 'co-pick-rows',
            children: [
              for (final (label, value) in [
                if (data.pickupAddress.isNotEmpty)
                  ('Punto de retiro', data.pickupAddress),
                (
                  'Cuándo retirar',
                  'Espera la confirmación de que el pedido está listo.',
                ),
                ('Qué llevar', 'Número de pedido y nombre de quien compra.'),
                (
                  'Retira otra persona',
                  'Indícalo en notas para coordinar sin fricción.',
                ),
                if (data.contactPhone.isNotEmpty)
                  ('Contacto tienda', data.contactPhone),
              ])
                div([
                  _el('dt', children: [.text(label)]),
                  _el('dd', children: [.text(value)]),
                ]),
            ],
          ),
        ],
      ),
    ], id: 'delivery'),
    _section('3. Método de pago', [_payment(data)], id: 'payment'),
    _section('Notas adicionales (opcional)', [
      _field(
        name: 'notes',
        label: 'Instrucciones especiales para tu pedido',
        icon: mdNoteAltOutlined,
        textarea: true,
      ),
    ]),
  ],
);

Component _payment(CheckoutPageData data) {
  if (!data.methodsKnown || data.methods.isEmpty) {
    return div(
      classes: 'co-pay-warn',
      attributes: {'data-co-no-pay': ''},
      [
        .text(
          data.methodsKnown
              ? 'Esta tienda todavía no tiene un medio de pago disponible.'
              : 'No pudimos verificar los medios de pago disponibles. Reintenta '
                    'antes de crear el pedido.',
        ),
      ],
    );
  }
  final recommended = data.methods.length > 1;
  return _el(
    'fieldset',
    classes: 'co-opts',
    attributes: {'data-co-payment': ''},
    children: [
      _el('legend', classes: 'sr', children: [.text('Método de pago')]),
      for (final (index, code) in data.methods.indexed)
        switch (code) {
          PublicCheckoutPaymentCode.mercadopago => _option(
            group: 'payment',
            value: code.wireValue,
            title: 'MercadoPago',
            subtitle:
                'Pago seguro con tarjeta de crédito, débito o saldo de '
                'Mercado Pago.',
            badge: recommended && index == 0 ? 'RECOMENDADO' : null,
            checked: index == 0,
          ),
          PublicCheckoutPaymentCode.transfer => _option(
            group: 'payment',
            value: code.wireValue,
            title: 'Transferencia bancaria',
            subtitle: 'Recibirás los datos para completar la transferencia.',
            badge: recommended && index == 0 ? 'RECOMENDADO' : null,
            checked: index == 0,
          ),
        },
    ],
  );
}

/// The summary's frame; the script fills the rows and amounts.
List<Component> _summary() => [
  h2(classes: 'co-sum-title', [.text('RESUMEN DEL PEDIDO')]),
  p(
    classes: 'co-frozen',
    attributes: {'data-co-frozen': '', 'hidden': ''},
    [.text('RESUMEN CONGELADO DEL PEDIDO RECUPERADO')],
  ),
  ul(classes: 'co-rows', attributes: {'data-co-rows': ''}, const []),
  hr(classes: 'co-rule'),
  div(attributes: {'data-co-amounts': ''}, const []),
  p(
    classes: 'co-metric sec',
    attributes: {'data-co-ship-row': ''},
    [
      span(attributes: {'data-co-ship-label': ''}, [.text('Envío')]),
      b(attributes: {'data-co-ship-value': ''}, [.text('—')]),
    ],
  ),
  p(
    classes: 'co-ship-note',
    attributes: {'data-co-ship-note': '', 'hidden': ''},
    const [],
  ),
  div(
    classes: 'co-progress',
    attributes: {'data-co-ship-wait': '', 'hidden': '', 'role': 'progressbar'},
    const [],
  ),
  div(
    classes: 'co-ship-err',
    attributes: {'data-co-ship-err': '', 'hidden': ''},
    [
      RawText(materialIcon(mdErrorOutline, size: 18)),
      p(attributes: {'data-co-ship-err-text': ''}, const []),
      button(
        attributes: {'type': 'button', 'data-act': 'requote'},
        [.text('REINTENTAR')],
      ),
    ],
  ),
  hr(classes: 'co-rule'),
  p(classes: 'co-total', [
    span([.text('TOTAL')]),
    b(attributes: {'data-co-total': ''}, [.text('—')]),
  ]),
  p(
    classes: 'co-recovery',
    attributes: {'data-co-recovery': '', 'hidden': '', 'role': 'status'},
    const [],
  ),
  button(
    classes: 'co-pay',
    attributes: {'type': 'button', 'data-act': 'place', 'disabled': ''},
    [
      span(attributes: {'data-co-pay-label': ''}, [.text('REALIZAR PEDIDO')]),
    ],
  ),
  a(
    classes: 'co-back',
    href: '/carrito',
    attributes: {'data-co-back': ''},
    [.text('VOLVER AL CARRITO')],
  ),
  hr(classes: 'co-rule b'),
  p(classes: 'co-safe', [
    .text(
      'Tus datos están protegidos y serán utilizados únicamente para '
      'procesar tu pedido.',
    ),
  ]),
];

String _firstPaintScript(String tenant) {
  final key =
      'flutter.public_store_cart_v2.${base64Url.encode(utf8.encode(tenant))}';
  final session = 'vinabike.public-checkout.v1.$tenant';
  return '(function(r){try{var s=sessionStorage.getItem(${jsonEncode(session)});'
      'var raw=localStorage.getItem(${jsonEncode(key)});'
      'var d=raw&&JSON.parse(JSON.parse(raw));'
      'var some=!!s||(d&&Array.isArray(d.lines)&&d.lines.length>0);'
      'r.querySelector(some?"[data-co-loading]":"[data-co-empty]").hidden=false'
      '}catch(e){}'
      '})(document.currentScript.previousElementSibling);';
}

const _escape = HtmlEscape();
String _e(String value) => _escape.convert(value);
String _money(num amount) => _e(ChileanUtils.formatCurrency(amount.toDouble()));

/// The answer to [checkoutLinesPath]: the lines as the cart restores them,
/// drawn as the summary's rows, with what the order needs of each one
/// (Flutter's `orderItems`) and the amounts the order states.
Map<String, Object?> checkoutLinesJson(CartLinesModel model) {
  final tax = model.taxSummary;
  final outOfStock = model.lines.any(
    (each) => each.commerce.availability.merchantValue == 'out_of_stock',
  );
  return {
    'adjusted': model.adjusted,
    'gone': model.gone,
    'lines': [
      for (final line in model.lines)
        {'id': line.product.id, 'q': line.quantity, 'limit': line.limit},
    ],
    'valid': tax.isValid,
    'outOfStock': outOfStock,
    'block': tax.isValid ? null : tax.checkoutBlockMessage,
    'gross': tax.isValid ? tax.grossAmount : null,
    'knownGross': model.grossAmount,
    'net': tax.isValid ? tax.netAmount : null,
    'tax': tax.isValid ? tax.taxAmount : null,
    'netLabel': tax.netLabel,
    'ivaLabel': tax.ivaLabel,
    'items': [
      for (final line in model.lines)
        {
          'product_id': line.commerce.id,
          'product_name': line.commerce.title,
          'product_sku': line.commerce.sku,
          'quantity': line.quantity,
          'unit_price': line.commerce.price,
          'subtotal': line.commerce.price * line.quantity,
        },
    ],
    'rows': [for (final line in model.lines) _rowHtml(line)].join(),
  };
}

String _rowHtml(CartLine line) {
  final commerce = line.commerce;
  final photo = commerce.imageUrls.isEmpty ? '' : commerce.imageUrls.first;
  final copies = line.thumbnail;
  final image = photo.isEmpty
      ? materialIcon(mdPedalBikeOutlined, size: 22)
      : '<img src="${_e(copies?.smallestUrl ?? photo)}" alt="" '
            'loading="lazy" decoding="async">';
  return '<li class="co-row"><div class="co-row-shot">$image</div>'
      '<div class="co-row-body"><p class="co-row-name">${_e(commerce.title)}</p>'
      '<p class="co-row-q">Cantidad: ${line.quantity}</p></div>'
      '<p class="co-row-sub">${_money(line.subtotal)}</p></li>';
}
