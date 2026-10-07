import 'dart:convert';
import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/customer_bike_drawing_geometry.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_forms.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_plans.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_presentation.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_snapshot.dart';
import 'package:vinabike_public_core/public_store/models/online_order.dart';
import 'package:vinabike_public_core/shared/models/customer_address.dart';
import 'package:vinabike_public_core/shared/utils/auth_input_validation.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'css_values.dart';
import 'material_icons.dart';
import 'places_script.dart';
import 'portal_page_css.dart';
import 'portal_page_script.dart';
import 'public_reads.dart';
import 'site_layout.dart';

part 'portal_forms_view.dart';

/// Where the portal page asks for its content, with the customer's session
/// in the `authorization` header (never in the address).
const portalViewPath = '/cuenta/vista';

/// Where the job sheet asks for a fresh link to one of the job's files.
const portalFilePath = '/cuenta/archivo';

/// Where the profile and addresses pages send what the customer saves, with
/// the session in the `authorization` header (`portal_action_route.dart`).
const portalActionPath = '/cuenta/accion';

/// The customer portal's pages the HTML store draws: reading (4a) and the
/// profile and addresses (4b). The chats and the way in are still Flutter's.
enum PortalPage {
  dashboard('/cuenta'),
  orders('/cuenta/pedidos'),
  workshop('/cuenta/servicios'),
  bikes('/cuenta/bicicletas'),
  profile('/cuenta/perfil'),
  addresses('/cuenta/direcciones');

  const PortalPage(this.path);
  final String path;

  static PortalPage? ofPath(String path) {
    for (final page in values) {
      if (page.path == path) return page;
    }
    return null;
  }
}

/// The portal's sections, in the order of Flutter's `_PortalTabs`.
const _tabs = [
  ('Resumen', '/cuenta'),
  ('Pedidos', '/cuenta/pedidos'),
  ('Taller', '/cuenta/servicios'),
  ('Bicicletas', '/cuenta/bicicletas'),
  ('Soporte', '/cuenta/chats'),
  ('Perfil', '/cuenta/perfil'),
  ('Direcciones', '/cuenta/direcciones'),
];

/// `/cuenta/**` as Flutter's `CustomerPortalLayout` draws it, «Sendero».
/// The session lives in the browser, so the server sends the frame with the
/// way in (`_CustomerPortalAuthBoundary`) and the script asks
/// [portalViewPath] for the page with the customer's token; the server reads
/// Supabase as that customer and answers the page drawn here, with the
/// rules of `customer_portal_presentation.dart` and `customer_portal_plans`.
Component portalPageDocument(PageContext page, PortalPage which) {
  final shell = page.shell;
  final roles = WebsiteThemeRoles.resolve(shell.setting);
  final images = PortalImages.of(shell.setting);
  return sitePage(
    context: page,
    meta: PageMeta(
      title: 'Mi cuenta | ${shell.storeName}',
      description:
          'Tus pedidos, tu bici en el taller y tus datos en '
          '${shell.storeName}.',
      canonicalUrl: '${page.storeUrl}${which.path}',
      indexable: false,
      styles: portalPageCss(roles),
    ),
    content: [
      div(
        attributes: {
          'data-portal-root': '',
          'data-view-url': '${page.hidden ? '/_html' : ''}$portalViewPath',
          'data-file-url': '${page.hidden ? '/_html' : ''}$portalFilePath',
          'data-action-url': '${page.hidden ? '/_html' : ''}$portalActionPath',
          if (which == PortalPage.addresses) ...{
            // What the address search draws in its list.
            'data-place-icon': materialIcon(mdPlaceOutlined),
            'data-spinner': '<span class="pt-spin small">$_spinner</span>',
          },
        },
        [
          _portalBoundary(images, _BoundaryState.signedOut),
          _portalBoundary(images, _BoundaryState.loading, hidden: true),
          _portalBoundary(images, _BoundaryState.notCustomer, hidden: true),
          _portalBoundary(images, _BoundaryState.unavailable, hidden: true),
          // Before the first paint: with a session in this browser the
          // frame says it is preparing the account, as Flutter does while it
          // reads the customer.
          script(
            content:
                '(function(r){try{var s=JSON.parse(localStorage.getItem('
                '${jsonEncode(accountSessionKey(page.supabaseUrl))})||"null");'
                'if(s&&s.access_token&&s.user){var b=r.children;'
                'b[0].hidden=true;b[1].hidden=false}'
                '}catch(e){}})(document.currentScript.parentNode);',
          ),
          Component.element(
            tag: 'noscript',
            children: [
              p(classes: 'pt-noscript', [
                .text(
                  'Tu sesión se guarda en este navegador: activa '
                  'JavaScript para ver tu cuenta.',
                ),
              ]),
            ],
          ),
        ],
      ),
    ],
    pageScripts: [
      // The address form's search (4b) shares the checkout's Places client.
      if (which == PortalPage.addresses) script(content: placesScript),
      script(content: portalPageScript),
    ],
    showFooter: false,
  );
}

/// The photos of the portal, from the editor (`theme_customer_portal_image`,
/// `theme_customer_portal_workshop_image`), only when they are http(s).
class PortalImages {
  const PortalImages(this.band, this.workshop);

  factory PortalImages.of(String Function(String, [String]) setting) {
    String url(String key) {
      final value = setting(key).trim();
      final uri = Uri.tryParse(value);
      return uri != null && (uri.isScheme('https') || uri.isScheme('http'))
          ? value
          : '';
    }

    return PortalImages(
      url('theme_customer_portal_image'),
      url('theme_customer_portal_workshop_image'),
    );
  }

  final String band;
  final String workshop;
}

enum _BoundaryState { signedOut, loading, notCustomer, unavailable }

/// What someone sees at `/cuenta/**` without a session (or one that is not
/// a customer of this store): the band and a short column with what is
/// inside and the button to come in.
Component _portalBoundary(
  PortalImages images,
  _BoundaryState state, {
  bool hidden = false,
}) {
  final (title, message) = switch (state) {
    _BoundaryState.loading => (
      'Preparando tu cuenta',
      'Estamos verificando tu acceso a esta tienda.',
    ),
    _BoundaryState.notCustomer => (
      'No pudimos abrir esta cuenta',
      'Tu sesión está abierta, pero no está registrada como cliente '
          'de esta tienda.',
    ),
    // Too many visits at once, or no connection: nothing about the account.
    _BoundaryState.unavailable => (
      'No pudimos abrir tu cuenta ahora',
      'La tienda no respondió a tiempo. Inténtalo de nuevo en unos segundos.',
    ),
    _BoundaryState.signedOut => (
      'Entra a tu cuenta',
      'Aquí ves tus pedidos, tu bici en el taller y tus '
          'conversaciones con la tienda.',
    ),
  };
  return div(
    classes: 'pt',
    attributes: {'data-portal': state.name, if (hidden) 'hidden': ''},
    [
      _band(images, title: title, signOut: false),
      div(classes: 'pt-col', [
        div(classes: 'pt-gate', [
          p(classes: 'pt-gate-msg', [_t(message)]),
          if (state == _BoundaryState.loading)
            span(
              classes: 'pt-spin',
              attributes: {'role': 'progressbar', 'aria-label': 'Cargando'},
              [RawText(_spinner)],
            )
          else if (state == _BoundaryState.unavailable)
            _button(
              'Reintentar',
              expand: true,
              attributes: {'data-act': 'portal-retry'},
            )
          else if (state == _BoundaryState.notCustomer) ...[
            _button(
              'Reintentar',
              expand: true,
              attributes: {'data-act': 'portal-retry'},
            ),
            _button(
              'Cerrar esta sesión',
              kind: 'sec',
              expand: true,
              attributes: {
                'data-act': 'portal-sign-out',
                'data-to': '/cuenta/login',
              },
            ),
          ] else ...[
            _button(
              'Iniciar sesión',
              arrow: true,
              expand: true,
              href: '/cuenta/login',
            ),
            p(classes: 'pt-gate-new', [
              _t('¿Primera vez? Puedes crear tu cuenta ahí mismo.'),
            ]),
          ],
        ]),
      ]),
    ],
  );
}

/// The material spinner of `CircularProgressIndicator`, drawn in CSS.
const _spinner =
    '<svg viewBox="0 0 28 28" width="28" height="28" aria-hidden="true">'
    '<circle cx="14" cy="14" r="12.75" fill="none" stroke="currentColor" '
    'stroke-width="2.5"/></svg>';

/// Everything a portal page draws once the customer is known.
class PortalViewData {
  PortalViewData._({
    required this.page,
    required this.query,
    required this.images,
    required this.profile,
    required this.orders,
    required this.orderImages,
    required this.bikes,
    required this.jobs,
    required this.addresses,
    required this.jobFiles,
    required this.pendingRevocation,
  });

  /// The rows as read, completed like `CustomerAccountService` completes
  /// them (`customer_portal_snapshot.dart`).
  factory PortalViewData.fromReads(
    PortalPage page,
    String query,
    CustomerPortalReads reads, {
    bool pendingRevocation = false,
  }) {
    final settings = reads.shell['settings'];
    String setting(String key, [String fallback = '']) {
      final value = settings is Map ? settings[key] : null;
      return value == null ? fallback : value.toString();
    }

    final jobs = [
      for (final row in reads.jobs)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
    final bikes = [
      for (final row in reads.bikes)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
    completeCustomerBikes(bikes, jobs);
    completeCustomerJobs(jobs, reads.jobBikes);
    return PortalViewData._(
      page: page,
      query: query,
      images: PortalImages.of(setting),
      profile: reads.profile!,
      orders: customerOrdersFromRows(reads.orders),
      orderImages: customerOrderImages(reads.productImages),
      bikes: bikes,
      jobs: jobs,
      addresses: [for (final row in reads.addresses) ?_address(row)],
      jobFiles: reads.jobFiles,
      pendingRevocation: pendingRevocation,
    );
  }

  final PortalPage page;
  final String query;
  final PortalImages images;
  final Map<String, dynamic> profile;
  final List<OnlineOrder> orders;
  final Map<String, String> orderImages;
  final List<Map<String, dynamic>> bikes;
  final List<Map<String, dynamic>> jobs;
  final List<CustomerAddress> addresses;
  final Map<String, String> jobFiles;

  /// The password changed but closing the other sessions failed, in this
  /// browser (`hasPendingOtherSessionsRevocation`, kept by the page).
  final bool pendingRevocation;

  Map<String, String> get queryParameters =>
      query.isEmpty ? const {} : Uri.splitQueryString(query);
}

/// A portal page with its band, tabs, content, the service band at the foot
/// of the summary and the sheets its rows open.
Component portalView(PortalViewData data) {
  final sheets = _Sheets(data);
  final onDashboard = data.page == PortalPage.dashboard;
  final pending = onDashboard
      ? null
      : CustomerPendingAction.first(orders: data.orders, jobs: data.jobs);

  final String title;
  String? meta;
  Component? action;
  Component body;
  Component? footer;
  switch (data.page) {
    case PortalPage.dashboard:
      final plan = CustomerDashboardPlan.of(
        profile: data.profile,
        orders: data.orders,
        jobs: data.jobs,
      );
      title = plan.title;
      meta = customerDashboardBandMeta(
        profile: data.profile,
        bikes: data.bikes.length,
        orders: data.orders.length,
      );
      body = _dashboard(data, plan, sheets);
      footer = _serviceBand(
        customerServiceBandItems(
          profile: data.profile,
          addressesCount: data.addresses.length,
        ),
      );
    case PortalPage.orders:
      title = 'Pedidos';
      meta = 'Todo lo que compraste en la tienda, con su estado.';
      action = _button(
        'Ir a la tienda',
        kind: 'photo',
        arrow: true,
        href: '/productos',
      );
      body = _orders(data);
    case PortalPage.workshop:
      title = 'Taller';
      meta = 'Tus bicis en el taller y lo que les hicimos.';
      action = _button(
        'Hablar con el taller',
        kind: 'photo',
        arrow: true,
        href: '/cuenta/chats',
      );
      body = _workshop(data, sheets);
    case PortalPage.bikes:
      title = 'Bicicletas';
      meta = 'Las bicis que el taller registró a tu nombre.';
      body = _bikes(data, sheets);
    case PortalPage.profile:
      title = 'Perfil y seguridad';
      meta = 'Los datos con que preparamos tus pedidos y boletas.';
      body = _profile(data, sheets);
    case PortalPage.addresses:
      title = 'Direcciones';
      final none = data.addresses.isEmpty;
      meta = none
          ? 'Dónde te enviamos tus pedidos.'
          : 'La principal aparece primero al pagar un pedido.';
      action = none
          ? null
          : _button(
              'Agregar dirección',
              kind: 'photo',
              icon: mdAdd,
              attributes: {'data-address': 'new'},
            );
      body = _addresses(data, sheets);
  }

  // A section of the tabs has no «Volver»; a filtered view does.
  final showBack = !onDashboard && data.queryParameters.isNotEmpty;
  final pendingStrip = pending == null ? null : _pendingStrip(pending, sheets);
  return div(
    classes: 'pt',
    attributes: {'data-portal': 'ready', 'data-page': data.page.name},
    [
      ?pendingStrip,
      _band(
        data.images,
        title: title,
        meta: meta,
        action: action,
        prominent: onDashboard,
        signOut: true,
      ),
      _tabsNav(data.page.path),
      div(
        classes: footer == null ? 'pt-col pt-main' : 'pt-col pt-main with-foot',
        [
          div(classes: 'pt-content', [
            if (showBack)
              a(
                classes: 'pt-back',
                href: '/cuenta',
                attributes: {'aria-label': 'Volver'},
                [RawText(materialIcon(mdArrowBack, size: 18)), _t('Volver')],
              ),
            body,
          ]),
        ],
      ),
      ?footer,
      ...sheets.built,
    ],
  );
}

// ================================================================ the frame

Component _band(
  PortalImages images, {
  required String title,
  String? meta,
  Component? action,
  bool prominent = false,
  required bool signOut,
}) {
  final photo = images.band.isNotEmpty;
  final metaText = meta == null || meta.trim().isEmpty ? null : meta;
  return section(
    classes: [
      'pt-band',
      if (prominent) 'prom',
      if (photo) 'photo',
      if (signOut) 'out',
    ].join(' '),
    [
      if (photo) ...[
        img(classes: 'pt-band-img', src: images.band, alt: ''),
        div(classes: 'pt-band-veil', const []),
      ],
      div(classes: 'pt-col pt-band-in', [
        div(classes: 'pt-band-row', [
          div(classes: 'pt-band-head', [
            p(classes: 'pt-eyebrow', [_t('Mi cuenta')]),
            h1(classes: prominent ? 'pt-display' : 'pt-title', [_t(title)]),
            if (metaText != null && !prominent)
              p(classes: 'pt-meta', [_lines(metaText)]),
          ]),
          if (metaText != null && prominent)
            p(classes: 'pt-meta', [_lines(metaText)]),
          ?action,
        ]),
      ]),
      if (signOut)
        button(
          classes: 'pt-salir',
          attributes: {
            'type': 'button',
            'data-act': 'portal-sign-out',
            'data-to': '/',
            'aria-label': 'Cerrar sesión',
          },
          [_t('Salir')],
        ),
    ],
  );
}

Component _lines(String text) {
  final parts = text.split('\n');
  return span(classes: 'pt-x', [
    for (var i = 0; i < parts.length; i++) ...[
      if (i > 0) br(),
      .text(parts[i]),
    ],
  ]);
}

Component _tabsNav(String location) => nav(
  classes: 'pt-tabs',
  attributes: {'aria-label': 'Tu cuenta'},
  [
    div(classes: 'pt-col pt-tabs-in', [
      div(classes: 'pt-tabs-scroll', [
        for (final (label, path) in _tabs)
          a(
            classes: path == location ? 'pt-tab on' : 'pt-tab',
            href: path,
            attributes: {if (path == location) 'aria-current': 'page'},
            [_t(label)],
          ),
      ]),
      button(
        classes: 'pt-out',
        attributes: {
          'type': 'button',
          'data-act': 'portal-sign-out',
          'data-to': '/',
          'aria-label': 'Cerrar sesión',
        },
        [_t('Cerrar sesión')],
      ),
    ]),
  ],
);

/// The dark band with the first thing that waits for the customer, on every
/// page but the summary.
Component _pendingStrip(CustomerPendingAction action, _Sheets sheets) {
  final text = '${action.status} · ${action.subject}';
  final children = [
    div(classes: 'pt-col pt-pend-in', [
      span(classes: 'pt-pend-dot', const []),
      span(classes: 'pt-pend-text', [_t(text)]),
      span(classes: 'pt-pend-go', [
        _t(action.actionLabel),
        RawText(materialIcon(mdArrowForward, size: 16)),
      ]),
    ]),
  ];
  final label = '$text. ${action.actionLabel}';
  if (action.job case final job?) {
    return button(
      classes: 'pt-pend',
      attributes: {
        'type': 'button',
        'data-sheet': sheets.job(job),
        'aria-label': label,
      },
      children,
    );
  }
  return a(
    classes: 'pt-pend',
    href: '/pedido/${action.order!.id}',
    attributes: {'aria-label': label},
    children,
  );
}

// ============================================================ the summary

Component _dashboard(
  PortalViewData data,
  CustomerDashboardPlan plan,
  _Sheets sheets,
) {
  Component tile(CustomerCurrentItem item, String layout) {
    final order = item.order;
    if (order != null) {
      return _orderTile(
        order,
        customerOrderImage(order, data.orderImages),
        layout,
      );
    }
    return _jobTile(item.job!, sheets, layout);
  }

  return div(classes: 'pt-sections', [
    if (plan.firstName == null)
      div(classes: 'pt-notice', [
        div(classes: 'pt-notice-main', [
          RawText(materialIcon(mdBadgeOutlined, size: 20)),
          p([
            _t(
              'Agrega tu nombre para que el taller sepa quién eres cuando '
              'escribas o traigas tu bici.',
            ),
          ]),
        ]),
        _link('Completar perfil', href: '/cuenta/perfil'),
      ]),
    if (plan.forYou.isNotEmpty)
      _section(
        'Para ti ahora',
        count: plan.forYou.length,
        child: _tileGrid([
          for (final item in plan.forYou) (l) => tile(item, l),
        ]),
      ),
    if (plan.inProgress.isNotEmpty)
      _section(
        'En curso',
        child: _tileGrid([
          for (final item in plan.inProgress) (l) => tile(item, l),
        ]),
      ),
    if (plan.nothingCurrent)
      _section(
        'En curso',
        child: _empty(
          'No tienes pedidos ni bicis en el taller.',
          message:
              'Cuando compres o dejes tu bici con nosotros, vas a ver aquí '
              'en qué va.',
          actions: [
            _button('Ver productos', arrow: true, href: '/productos'),
            _link('Hablar con el taller', href: '/cuenta/chats'),
          ],
        ),
      ),
    if (data.bikes.isNotEmpty)
      _section(
        'Tus bicicletas',
        actionLabel: data.bikes.length > 2 ? 'Ver todas' : null,
        actionHref: '/cuenta/bicicletas',
        child: _bikesRow(data, sheets),
      ),
    if (plan.previousOrders.isNotEmpty)
      _section(
        'Últimos pedidos',
        actionLabel: 'Ver todos',
        actionHref: '/cuenta/pedidos',
        child: _panel(_orderTableHeader(), [
          for (final order in plan.previousOrders)
            _orderRow(order, customerOrderImage(order, data.orderImages)),
        ]),
      ),
  ]);
}

/// «Tus bicicletas» in the summary: in wide, up to two bikes and the
/// workshop photo (or three bikes); narrower, one compact card or a row that
/// slides.
Component _bikesRow(PortalViewData data, _Sheets sheets) {
  final bikes = data.bikes;
  final (:shown, :showWorkshop) = customerDashboardBikes(bikes);
  return div(classes: 'pt-brow', [
    div(classes: 'pt-brow-wide', [
      for (var i = 0; i < 3; i++)
        if (i < shown.length)
          div(classes: 'pt-brow-cell', [_bikeCard(shown[i], sheets)])
        else if (i == shown.length && showWorkshop)
          _workshopTile(data.images)
        else
          div(classes: 'pt-brow-cell', const []),
    ]),
    if (bikes.length == 1)
      div(classes: 'pt-brow-one', [
        _bikeCard(bikes.first, sheets, compact: true),
      ])
    else
      div(classes: 'pt-brow-slide', [
        for (final bike in bikes)
          div(classes: 'pt-brow-item', [
            _bikeCard(bike, sheets, compact: true),
          ]),
      ]),
  ]);
}

Component _workshopTile(PortalImages images) {
  final photo = images.workshop.isNotEmpty;
  return a(
    classes: photo ? 'pt-wtile photo' : 'pt-wtile',
    href: '/servicios',
    attributes: {'aria-label': 'Servicios y precios del taller'},
    [
      if (photo) ...[
        img(classes: 'pt-wtile-img', src: images.workshop, alt: ''),
        span(classes: 'pt-wtile-veil', const []),
      ],
      span(classes: 'pt-wtile-in', [
        span(classes: 'pt-eyebrow', [_t('Taller')]),
        span(classes: 'pt-wtile-title', [_t('Servicios y precios')]),
        span(classes: 'pt-wtile-msg', [
          _t('Mantenciones y reparaciones para tu próxima visita.'),
        ]),
        _button('Ver servicios', kind: 'photo', arrow: true, inert: true),
      ]),
    ],
  );
}

Component _serviceBand(List<CustomerServiceBandItem> items) {
  const icons = {
    'chat_bubble_outline': mdChatBubbleOutline,
    'verified_user_outlined': mdVerifiedUserOutlined,
    'location_on_outlined': mdLocationOnOutlined,
  };
  return div(classes: 'pt-svc', [
    div(classes: 'pt-col pt-svc-in', [
      for (final item in items)
        div(classes: 'pt-svc-item', [
          div(classes: 'pt-svc-head', [
            RawText(materialIcon(icons[item.icon]!, size: 28)),
            h2(classes: 'pt-svc-title', [_t(item.title)]),
          ]),
          p(classes: 'pt-svc-msg', [_t(item.message)]),
          _link(item.actionLabel, href: item.href),
        ]),
    ]),
  ]);
}

// =============================================================== pedidos

Component _orders(PortalViewData data) {
  final orders = data.orders;
  if (orders.isEmpty) {
    return _empty(
      'Todavía no tienes pedidos.',
      message:
          'Cuando compres en la tienda, cada pedido aparecerá aquí con su '
          'estado.',
      actions: [_link('Ver productos', href: '/productos')],
    );
  }
  // Every tab is drawn; the script shows the one chosen, as Flutter keeps it
  // in the page's state.
  Component view(CustomerOrderGroup? group) {
    final plan = CustomerOrdersPlan.of(orders, group: group);
    return div(
      classes: 'pt-view',
      attributes: {
        'data-view': group?.name ?? 'all',
        if (group != null) 'hidden': '',
      },
      [
        div(classes: 'pt-chips', [
          _chip(
            'Todos',
            count: orders.length,
            selected: plan.group == null,
            view: 'all',
          ),
          for (final g in plan.groups)
            _chip(
              CustomerOrdersPlan.labels[g]!,
              count: plan.counts[g]!,
              selected: plan.group == g,
              view: g.name,
            ),
        ]),
        _panel(_orderTableHeader(), [
          for (final order in plan.visible)
            _orderRow(order, customerOrderImage(order, data.orderImages)),
        ]),
      ],
    );
  }

  final groups = CustomerOrdersPlan.of(orders).groups;
  return div(classes: 'pt-views', [
    view(null),
    for (final g in groups) view(g),
  ]);
}

const _orderNumberColumn = 140;
const _jobNumberColumn = 120;

Component _orderTableHeader() => _tableHeader('Producto', [
  ('Pedido', _orderNumberColumn),
  ('Fecha', 120),
  ('Estado', 200),
]);

Component _jobTableHeader() => _tableHeader('Bicicleta', [
  ('Servicio', _jobNumberColumn),
  ('Ingresó', 120),
  ('Estado', 200),
]);

Component _tableHeader(String first, List<(String, int)> columns) => div(
  classes: 'pt-th',
  attributes: {'aria-hidden': 'true'},
  [
    span(classes: 'pt-th-lead', const []),
    span(classes: 'pt-th-c pt-grow', [_t(first)]),
    for (final (label, width) in columns)
      span(
        classes: 'pt-th-c',
        attributes: {'style': 'width:${width}px'},
        [_t(label)],
      ),
    span(classes: 'pt-th-c pt-th-total', [_t('Total')]),
    span(classes: 'pt-th-tail', const []),
  ],
);

/// An order in a row: in wide the columns of the table, narrower stacked.
Component _orderRow(OnlineOrder order, String? imageUrl) {
  final presentation = CustomerOrderPresentation.of(order);
  final total = ChileanUtils.formatCurrency(order.total);
  Component tag() => _statusTag(
    presentation.label,
    presentation.tone,
    needsCustomer: presentation.needsCustomer,
    active: presentation.group == CustomerOrderGroup.inProgress,
  );
  final summary = CustomerOrderPresentation.itemsSummary(order);
  final date = portalDate(order.createdAt).replaceAll(' ', ' ');
  final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
  Component what() => span(classes: 'pt-what', [
    span(classes: 'pt-row-title', [_t(summary)]),
    if (nextStep != null) span(classes: 'pt-next', [_t(nextStep)]),
  ]);
  Component meta() =>
      span(classes: 'pt-row-meta', [_t('${order.orderNumber} · $date')]);
  Component thumb(int size) =>
      _thumb(imageUrl: imageUrl, fallback: mdShoppingBagOutlined, size: size);
  final arrow = RawText(materialIcon(mdArrowForward, size: 18));
  return a(
    classes: 'pt-row',
    href: '/pedido/${order.id}',
    attributes: {
      'aria-label':
          'Pedido ${order.orderNumber}, ${presentation.label}, '
          '$total',
    },
    [
      span(classes: 'pt-row-table', [
        thumb(72),
        what(),
        span(
          classes: 'pt-row-num',
          attributes: {'style': 'width:${_orderNumberColumn}px'},
          [_t(order.orderNumber)],
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

/// An order that waits for the customer, large: the product's photo on the
/// grey, the state, what to do and the short facts.
Component _orderTile(OnlineOrder order, String? imageUrl, String layout) {
  final presentation = CustomerOrderPresentation.of(order);
  final total = ChileanUtils.formatCurrency(order.total);
  final copy = CustomerOrderPresentation.feature(order, formattedTotal: total);
  final transfer = presentation.awaitsTransfer;
  final url = imageUrl?.trim() ?? '';
  final units = CustomerOrderPresentation.unitCount(order);
  final bag = RawText(
    materialIcon(mdShoppingBagOutlined, size: 56, classes: 'pt-well-icon'),
  );
  return div(classes: 'pt-ftile $layout', [
    _well(
      'Pedido',
      order.orderNumber,
      url.isEmpty ? bag : _productImage(url, bag),
    ),
    div(classes: 'pt-ftile-body', [
      span(classes: 'pt-ftile-state', [
        _statusTag(
          presentation.label,
          presentation.tone,
          needsCustomer: presentation.needsCustomer,
        ),
      ]),
      h3(classes: 'pt-feature', [_t(copy.headline)]),
      if (copy.message != null) p(classes: 'pt-sub', [_t(copy.message!)]),
      div(classes: 'pt-facts-strip', [
        for (final (label, value) in [
          ('Pedido el', portalDate(order.createdAt)),
          ('Productos', '$units'),
          ('Total', total),
        ])
          div([
            span(classes: 'pt-micro', [_t(label)]),
            span(classes: 'pt-fact-v', [_t(value)]),
          ]),
      ]),
      span(classes: 'pt-ftile-gap', const []),
      div(classes: 'pt-actions', [
        _button(
          transfer ? 'Datos de transferencia' : 'Ver pedido',
          kind: presentation.needsCustomer ? 'pri' : 'sec',
          arrow: true,
          expandCompact: true,
          href: '/pedido/${order.id}',
        ),
      ]),
    ]),
  ]);
}

// ================================================================= taller

Component _workshop(PortalViewData data, _Sheets sheets) {
  final jobs = data.jobs;
  if (jobs.isEmpty) {
    return _empty(
      'Todavía no tienes trabajos de taller.',
      message:
          'Cuando dejes tu bici con nosotros vas a ver aquí en qué va, el '
          'presupuesto y cuándo está lista.',
      actions: [
        _link('Ver servicios y precios', href: '/servicios'),
        _link('Hablar con el taller', href: '/cuenta/chats'),
      ],
    );
  }
  final initial = data.queryParameters['bike_id'];
  // Every bike's view is drawn; the script shows the one chosen.
  Component view(String? bikeId, {required bool shown}) {
    final plan = CustomerServiceHistoryPlan.of(jobs, bikeId: bikeId);
    final tiles = [
      for (final job in plan.active) (String l) => _jobTile(job, sheets, l),
    ];
    return div(
      classes: 'pt-view',
      attributes: {'data-view': bikeId ?? 'all', if (!shown) 'hidden': ''},
      [
        if (plan.showsFilter)
          div(classes: 'pt-chips', [
            _chip(
              'Todas',
              count: jobs.length,
              selected: plan.filterId == null,
              view: 'all',
            ),
            for (final entry in plan.bikes.entries)
              _chip(
                entry.value,
                count: plan.counts[entry.key],
                selected: plan.filterId == entry.key,
                view: entry.key,
                narrow: true,
              ),
          ]),
        if (plan.visible.isEmpty)
          _empty(
            'Esta bicicleta no tiene trabajos registrados.',
            actions: [_link('Ver todos los trabajos', view: 'all')],
          ),
        if (plan.active.isNotEmpty)
          _section(
            'En el taller',
            count: plan.waitingCount,
            child: _tileGrid(tiles),
          ),
        if (plan.active.isNotEmpty && plan.history.isNotEmpty)
          span(classes: 'pt-gap72', const []),
        if (plan.history.isNotEmpty)
          _section(
            'Historial',
            child: _panel(_jobTableHeader(), [
              for (final job in plan.history)
                _jobRow(job, sheets, showTotal: true),
            ]),
          ),
      ],
    );
  }

  final bikes = CustomerServiceHistoryPlan.of(jobs).bikes.keys;
  final selected = initial != null && initial.isNotEmpty ? initial : null;
  return div(classes: 'pt-views', [
    view(null, shown: selected == null),
    for (final id in bikes) view(id, shown: selected == id),
    if (selected != null && !bikes.contains(selected))
      view(selected, shown: true),
  ]);
}

Component _bikeThumb(Map<String, dynamic> job, int size) => _thumb(
  fallback: mdPedalBikeOutlined,
  size: size,
  drawing: _drawing(
    customerBikeSilhouette(job['bike_type']),
    size * 0.82,
    availableHeight: size.toDouble(),
  ),
);

/// A workshop job in a row: the bike, what was asked and when it came in,
/// with the state in the customer's words.
Component _jobRow(
  Map<String, dynamic> job,
  _Sheets sheets, {
  bool showTotal = false,
}) {
  final presentation = CustomerWorkshopPresentation.of(job);
  final received = CustomerWorkshopPresentation.receivedAt(job);
  final request = CustomerWorkshopPresentation.requestSummary(job);
  final amount = showTotal ? CustomerWorkshopPresentation.total(job) : null;
  final total = amount == null ? null : ChileanUtils.formatCurrency(amount);
  final number = (job['job_number'] ?? '').toString().trim();
  final bike = CustomerWorkshopPresentation.bikeTitle(job);
  Component tag() => _statusTag(
    presentation.label,
    presentation.tone,
    needsCustomer: presentation.needsCustomer,
    active: presentation.isActive,
  );
  final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
  final date = received == null
      ? null
      : portalDate(received).replaceAll(' ', ' ');
  final what = request.isNotEmpty
      ? request
      : number.isEmpty
      ? null
      : 'Servicio $number';
  Component title() => span(classes: 'pt-what', [
    span(classes: 'pt-row-title one', [_t(bike)]),
    if (what != null) span(classes: 'pt-row-meta two', [_t(what)]),
    if (nextStep != null) span(classes: 'pt-next', [_t(nextStep)]),
  ]);
  final tail = [?date, ?total].join(' · ');
  final arrow = RawText(materialIcon(mdArrowForward, size: 18));
  return button(
    classes: 'pt-row',
    attributes: {
      'type': 'button',
      'data-sheet': sheets.job(job),
      'aria-label': [
        bike,
        if (number.isNotEmpty) 'servicio $number',
        presentation.label,
      ].join(', '),
    },
    [
      span(classes: 'pt-row-table', [
        _bikeThumb(job, 72),
        title(),
        span(
          classes: 'pt-row-num',
          attributes: {'style': 'width:${_jobNumberColumn}px'},
          [_t(number)],
        ),
        span(classes: 'pt-row-date', [_t(date ?? '—')]),
        span(classes: 'pt-row-state', [tag()]),
        span(classes: 'pt-row-total', [_t(total ?? '')]),
        arrow,
      ]),
      span(classes: 'pt-row-mid', [
        _bikeThumb(job, 72),
        title(),
        span(classes: 'pt-row-end', [
          tag(),
          if (tail.isNotEmpty) span(classes: 'pt-row-meta', [_t(tail)]),
        ]),
        arrow,
      ]),
      span(classes: 'pt-row-phone', [
        _bikeThumb(job, 64),
        span(classes: 'pt-what', [
          title(),
          span(classes: 'pt-row-foot job', [
            tag(),
            if (tail.isNotEmpty) span(classes: 'pt-row-meta', [_t(tail)]),
          ]),
        ]),
      ]),
    ],
  );
}

/// A job still in the workshop, large: the bike's drawing on the grey, the
/// state, what was asked, the five steps and what to do.
Component _jobTile(Map<String, dynamic> job, _Sheets sheets, String layout) {
  final presentation = CustomerWorkshopPresentation.of(job);
  final number = (job['job_number'] ?? '').toString().trim();
  final bike = CustomerWorkshopPresentation.bikeTitle(job);
  final step = customerWorkshopStep(job);
  final message = customerJobMessage(job);
  final approval = customerJobAwaitsApproval(job);
  final sheet = sheets.job(job);
  final horizontal = layout == 'solo';
  final silhouette = customerBikeSilhouette(job['bike_type']);

  final actions = <Component>[
    if (approval) ...[
      _button(
        'Responder al taller',
        arrow: true,
        expandCompact: true,
        href: '/cuenta/chats',
      ),
      _button(
        'Ver ficha',
        kind: 'sec',
        expandCompact: true,
        attributes: {'data-sheet': sheet},
      ),
    ] else if (presentation.needsCustomer)
      _button(
        'Ver ficha',
        arrow: true,
        expandCompact: true,
        attributes: {'data-sheet': sheet},
      )
    else ...[
      _button(
        'Ver ficha',
        kind: 'sec',
        expandCompact: true,
        attributes: {'data-sheet': sheet},
      ),
      _link('Preguntar al taller', href: '/cuenta/chats', wideOnly: true),
    ],
  ];

  return div(classes: 'pt-ftile $layout', [
    _well(
      'Taller',
      number.isEmpty ? null : number,
      span(classes: 'pt-well-draw', [
        span(classes: 'pt-draw-wide', [
          _drawing(
            silhouette,
            horizontal ? 330 : 270,
            availableHeight: horizontal ? 240 : 160,
          ),
        ]),
        span(classes: 'pt-draw-compact', [
          _drawing(silhouette, 230, availableHeight: 130),
        ]),
      ]),
    ),
    div(classes: 'pt-ftile-body', [
      span(classes: 'pt-ftile-state', [
        _statusTag(
          presentation.label,
          presentation.tone,
          needsCustomer: presentation.needsCustomer,
          active: presentation.isActive,
        ),
      ]),
      h3(classes: 'pt-feature', [_t(bike)]),
      if (message != null) p(classes: 'pt-sub', [_t(message)]),
      if (step != null && step < customerWorkshopSteps.length)
        _progress(step, needsCustomer: presentation.needsCustomer),
      span(classes: 'pt-ftile-gap', const []),
      div(classes: 'pt-actions job', actions),
    ]),
  ]);
}

/// The workshop's steps in five straight bars. With [labels] `null` the
/// names show where there is room (`showLabels: !compact`); in a sheet they
/// follow the screen (`MediaQuery` from 600).
Component _progress(int step, {required bool needsCustomer, String? scope}) {
  final last = customerWorkshopSteps.length - 1;
  String bar(int index) {
    if (index < step) return 'done';
    if (index > step) return 'todo';
    if (index == last) return 'ok';
    return needsCustomer ? 'wait' : 'now';
  }

  final current = step.clamp(0, last);
  return div(
    classes: scope == null ? 'pt-steps' : 'pt-steps $scope',
    attributes: {
      'role': 'img',
      'aria-label':
          'Paso ${current + 1} de ${last + 1}: ${customerWorkshopSteps[current]}',
    },
    [
      div(classes: 'pt-steps-row', [
        for (var i = 0; i <= last; i++)
          span(classes: 'pt-step', [
            span(classes: 'pt-step-bar ${bar(i)}', const []),
            span(classes: i == step ? 'pt-step-name on' : 'pt-step-name', [
              _t(customerWorkshopSteps[i]),
            ]),
          ]),
      ]),
      p(classes: 'pt-steps-text', [
        _t('Paso ${current + 1} de ${last + 1} · '),
        b([_t(customerWorkshopSteps[current])]),
      ]),
    ],
  );
}

// ============================================================= bicicletas

Component _bikes(PortalViewData data, _Sheets sheets) {
  if (data.bikes.isEmpty) {
    return _empty(
      'Todavía no hay bicicletas en tu cuenta.',
      message:
          'El taller registra tu bici la primera vez que la traes, y desde ahí '
          'vas a ver aquí cada servicio que le hagamos.',
      actions: [_link('Ver servicios y precios', href: '/servicios')],
    );
  }
  return div(classes: 'pt-bgrid', [
    for (final bike in data.bikes)
      div(classes: 'pt-bgrid-cell', [
        _bikeCard(bike, sheets, gridCompact: true),
      ]),
  ]);
}

/// A customer's bike as a catalog shows a product: the drawing of its type
/// on the grey, the type in a tag, the name in capitals and how many times it
/// came to the workshop. [compact] is fixed (the summary's narrow row);
/// [gridCompact] follows the grid's single column.
Component _bikeCard(
  Map<String, dynamic> bike,
  _Sheets sheets, {
  bool compact = false,
  bool gridCompact = false,
}) {
  final title = CustomerWorkshopPresentation.bikeTitle(bike);
  final type = customerBikeTypeLabel(bike['bike_type']);
  final details = customerBikeDetails(
    Map<String, dynamic>.from(bike)..remove('bike_type'),
  );
  final services = customerBikeServiceSummary(bike);
  final image = customerBikeImage(bike);
  final silhouette = customerBikeSilhouette(bike['bike_type']);
  Component drawing() => span(classes: 'pt-well-draw', [
    span(classes: 'pt-draw-wide', [
      _drawing(silhouette, 260, availableHeight: 190),
    ]),
    span(classes: 'pt-draw-compact', [
      _drawing(silhouette, 220, availableHeight: 140),
    ]),
  ]);
  return button(
    classes: [
      'pt-bike',
      if (compact) 'compact',
      if (gridCompact) 'grid',
    ].join(' '),
    attributes: {
      'type': 'button',
      'data-sheet': sheets.bike(bike),
      'aria-label': [title, ?type, services].join(', '),
    },
    [
      _well(
        type,
        null,
        image == null ? drawing() : _productImage(image, drawing()),
        bike: true,
      ),
      span(classes: 'pt-bike-title', [_t(title)]),
      if (details.isNotEmpty) span(classes: 'pt-bike-details', [_t(details)]),
      span(classes: 'pt-bike-foot', [
        span([_t(services)]),
        RawText(materialIcon(mdArrowForward, size: 18)),
      ]),
    ],
  );
}

// ================================================================ sheets

/// The sheets a page's rows open (`showPortalDetail`), each drawn once.
class _Sheets {
  _Sheets(this.data);

  final PortalViewData data;
  final built = <Component>[];
  final _ids = <String, String>{};

  String job(Map<String, dynamic> job) {
    final key = 'job:${job['id']}';
    return _ids[key] ??= _add(_jobSheet(job, data.jobFiles));
  }

  String bike(Map<String, dynamic> bike) {
    final key = 'bike:${bike['id']}';
    return _ids[key] ??= _add(_bikeSheet(bike));
  }

  String _add(Component Function(String id) sheet) {
    final id = 'pt-sheet-${built.length + 1}';
    built.add(sheet(id));
    return id;
  }
}

Component Function(String id) _jobSheet(
  Map<String, dynamic> job,
  Map<String, String> files,
) => (id) {
  final presentation = CustomerWorkshopPresentation.of(job);
  final number = (job['job_number'] ?? '').toString().trim();
  final received = CustomerWorkshopPresentation.receivedAt(job);
  final deadline = portalParseDate(job['deadline']);
  final total = CustomerWorkshopPresentation.total(job);
  final request = CustomerWorkshopPresentation.requestSummary(job);
  final step = customerWorkshopStep(job);
  final references = [
    for (final value in job['image_urls'] as List? ?? const [])
      if (value is String && value.trim().isNotEmpty) value.trim(),
  ];
  String? text(String key) {
    final value = (job[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  return _sheet(
    id,
    title: CustomerWorkshopPresentation.bikeTitle(job),
    subtitle: number.isEmpty ? null : 'Servicio $number',
    status: [
      span(classes: 'pt-sheet-tag', [
        _statusTag(
          presentation.label,
          presentation.tone,
          needsCustomer: presentation.needsCustomer,
          active: presentation.isActive,
        ),
      ]),
      if (step != null && step < customerWorkshopSteps.length)
        _progress(
          step,
          needsCustomer: presentation.needsCustomer,
          scope: 'sheet',
        ),
    ],
    body: [
      _facts([
        ('Lo que pediste', request.isEmpty ? null : request),
        ('Diagnóstico', text('diagnosis')),
        ('Trabajo realizado', text('work_performed')),
        ('Ingresó', received == null ? null : portalDate(received)),
        (
          'Fecha estimada',
          presentation.isActive && deadline != null
              ? portalDate(deadline)
              : null,
        ),
        ('Total', total == null ? null : ChileanUtils.formatCurrency(total)),
      ]),
      if (references.isNotEmpty)
        div(classes: 'pt-files', [
          p(classes: 'pt-files-title', [_t('Archivos del trabajo')]),
          div(classes: 'pt-files-grid', [
            for (var i = 0; i < references.length; i++)
              button(
                classes: 'pt-file',
                attributes: {
                  'type': 'button',
                  'data-file': references[i],
                  'aria-label': 'Abrir archivo ${i + 1} del trabajo',
                },
                [
                  if (Uri.tryParse(
                        references[i],
                      )?.path.toLowerCase().endsWith('.pdf') ==
                      true)
                    RawText(materialIcon(mdPictureAsPdfOutlined, size: 24))
                  else if (files[references[i]] case final url?)
                    img(src: url, alt: '', attributes: {'loading': 'lazy'})
                  else
                    RawText(materialIcon(mdBrokenImageOutlined, size: 24)),
                ],
              ),
          ]),
          p(
            classes: 'pt-files-error',
            attributes: {'hidden': '', 'role': 'status'},
            [_t('Este archivo no está disponible ahora.')],
          ),
        ]),
    ],
    actions: [
      _button(
        presentation.needsCustomer
            ? 'Responder al taller'
            : 'Preguntar al taller',
        arrow: true,
        href: '/cuenta/chats',
      ),
    ],
  );
};

Component Function(String id) _bikeSheet(Map<String, dynamic> bike) => (id) {
  final warranty = customerBikeWarranty(bike);
  final purchased = portalParseDate(bike['purchase_date']);
  final count = (bike['service_count'] as num?)?.toInt() ?? 0;
  String? text(String key) {
    final value = (bike[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  final details = customerBikeDetails(bike);
  return _sheet(
    id,
    title: CustomerWorkshopPresentation.bikeTitle(bike),
    subtitle: details.isEmpty ? null : details,
    status: [
      if (warranty != null)
        span(classes: 'pt-sheet-tag', [
          _tag(
            warranty.active
                ? 'Garantía hasta el ${portalDate(warranty.until)}'
                : 'Garantía vencida el ${portalDate(warranty.until)}',
            warranty.active ? 'success' : 'quiet',
          ),
        ]),
    ],
    body: [
      _facts([
        ('Taller', customerBikeServiceSummary(bike)),
        ('Talla de cuadro', text('frame_size')),
        ('Número de serie', text('serial_number')),
        ('Comprada', purchased == null ? null : portalDate(purchased)),
        ('Notas', text('notes')),
      ]),
    ],
    actions: [
      if (count > 0)
        _button(
          'Ver sus trabajos de taller',
          arrow: true,
          href:
              '/cuenta/servicios?bike_id=${Uri.encodeQueryComponent('${bike['id']}')}',
        ),
    ],
  );
};

Component _sheet(
  String id, {
  required String title,
  String? subtitle,
  List<Component> status = const [],
  required List<Component> body,
  List<Component> actions = const [],
}) => Component.element(
  tag: 'dialog',
  id: id,
  classes: 'pt-dlg',
  attributes: {'aria-labelledby': '$id-t'},
  children: [
    div(classes: 'pt-scrim', attributes: {'data-close': ''}, const []),
    div(classes: 'pt-panel', [
      span(classes: 'pt-panel-bar', const []),
      div(classes: 'pt-panel-head', [
        div(classes: 'pt-panel-headings', [
          h2(
            classes: 'pt-panel-title',
            attributes: {'id': '$id-t'},
            [_t(title)],
          ),
          if (subtitle != null)
            p(classes: 'pt-row-meta pt-panel-sub', [_t(subtitle)]),
          if (status.isNotEmpty) div(classes: 'pt-panel-status', status),
        ]),
        button(
          classes: 'pt-close',
          attributes: {
            'type': 'button',
            'data-close': '',
            'aria-label': 'Cerrar',
            'title': 'Cerrar',
          },
          [RawText(materialIcon(mdClose, size: 24))],
        ),
      ]),
      div(classes: 'pt-panel-body', body),
      if (actions.isNotEmpty) div(classes: 'pt-panel-actions', actions),
    ]),
  ],
);

Component _facts(List<(String, String?)> facts) {
  final visible = [
    for (final (label, value) in facts)
      if (value != null && value.trim().isNotEmpty) (label, value.trim()),
  ];
  return Component.element(
    tag: 'dl',
    classes: 'pt-facts',
    children: [
      for (final (label, value) in visible)
        div([
          Component.element(
            tag: 'dt',
            classes: 'pt-micro',
            children: [_t(label)],
          ),
          Component.element(
            tag: 'dd',
            classes: 'pt-fact',
            children: [_t(value)],
          ),
        ]),
    ],
  );
}

// =============================================================== pieces

/// A text whose glyphs sit where Flutter's do ([portalPageCss] moves each
/// text class by its font's leading).
Component _t(String text) => span(classes: 'pt-x', [.text(text)]);

/// `PortalButton`: square, 44 high at the store's density, the label in
/// spaced capitals; [kind] `pri` (filled with the action color), `sec`
/// (outlined in ink) or `photo` (white, on a photo).
Component _button(
  String label, {
  String kind = 'pri',
  String? icon,
  bool arrow = false,
  bool expand = false,
  bool expandCompact = false,
  bool inert = false,
  String? href,
  Map<String, String> attributes = const {},
}) {
  final classes = [
    'pt-btn',
    kind,
    if (expand) 'full',
    if (expandCompact) 'full-compact',
  ].join(' ');
  final children = <Component>[
    if (icon != null) RawText(materialIcon(icon, size: 18)),
    span(classes: 'pt-btn-label', [_t(label)]),
    if (arrow) RawText(materialIcon(mdArrowForward, size: 18)),
  ];
  if (inert) {
    return span(
      classes: classes,
      attributes: {'aria-hidden': 'true'},
      children,
    );
  }
  if (href != null) {
    return a(classes: classes, href: href, attributes: attributes, children);
  }
  return button(
    classes: classes,
    attributes: {'type': 'button', ...attributes},
    children,
  );
}

/// `PortalLink`: the label in capitals, underlined, with an arrow. [view]
/// switches the page's view instead of leaving it.
Component _link(
  String label, {
  String? href,
  String? view,
  String? act,
  bool wideOnly = false,
}) {
  final children = [
    span(classes: 'pt-link-in', [
      _t(label),
      RawText(materialIcon(mdArrowForward, size: 16)),
    ]),
  ];
  final classes = wideOnly ? 'pt-link wide-only' : 'pt-link';
  if (view != null || act != null) {
    return button(
      classes: classes,
      attributes: {'type': 'button', 'data-view-to': ?view, 'data-act': ?act},
      children,
    );
  }
  return a(classes: classes, href: href!, children);
}

/// `PortalFilterChip`: square, its count after the label; the chosen one
/// filled with ink.
Component _chip(
  String label, {
  int? count,
  required bool selected,
  required String view,
  bool narrow = false,
}) => button(
  classes: ['pt-chip', if (selected) 'on', if (narrow) 'narrow'].join(' '),
  attributes: {
    'type': 'button',
    'data-view-to': view,
    'aria-pressed': selected ? 'true' : 'false',
    'aria-label': [label, if (count != null) '$count'].join(', '),
  },
  [
    span(classes: 'pt-chip-label', [_t(label)]),
    if (count != null) span(classes: 'pt-chip-count', [_t('$count')]),
  ],
);

/// `portalStatusTagKind`: the tag's color says who has to move.
String _statusKind(
  PortalTone tone, {
  required bool needsCustomer,
  required bool active,
}) {
  if (needsCustomer) {
    return switch (tone) {
      PortalTone.success => 'success',
      PortalTone.danger => 'danger',
      _ => 'attention',
    };
  }
  if (active) return 'ink';
  return tone == PortalTone.neutral ? 'quiet' : 'outline';
}

Component _statusTag(
  String label,
  PortalTone tone, {
  bool needsCustomer = false,
  bool active = true,
}) => _tag(
  label,
  _statusKind(tone, needsCustomer: needsCustomer, active: active),
);

Component _tag(String label, String kind) =>
    span(classes: 'pt-tag $kind', [_t(label)]);

Component _section(
  String label, {
  int? count,
  String? actionLabel,
  String? actionHref,
  String? actionAct,
  required Component child,
}) => section(classes: 'pt-section', [
  div(classes: 'pt-sh', [
    div(classes: 'pt-sh-main', [
      span(classes: 'pt-sh-bar', const []),
      div(classes: 'pt-sh-row', [
        h2(classes: 'pt-sh-title', [_t(label)]),
        if (count != null && count > 0)
          span(classes: 'pt-count', [_t('$count')]),
      ]),
    ]),
    if (actionLabel != null && (actionHref != null || actionAct != null))
      _link(actionLabel, href: actionHref, act: actionAct),
  ]),
  child,
]);

Component _panel(Component header, List<Component> rows) =>
    div(classes: 'pt-panel-list', [header, div(classes: 'pt-rows', rows)]);

Component _empty(
  String title, {
  String? message,
  List<Component> actions = const [],
}) => div(classes: 'pt-empty', [
  p(classes: 'pt-empty-title', [_t(title)]),
  if (message != null) p(classes: 'pt-empty-msg', [_t(message)]),
  if (actions.isNotEmpty) div(classes: 'pt-empty-actions', actions),
]);

/// `PortalTileGrid`: two by two in wide, one by one narrower, alone and
/// lying down when it is the only one. Each tile is drawn for its layout.
Component _tileGrid(List<Component Function(String layout)> tiles) {
  if (tiles.length == 1) {
    return div(classes: 'pt-tiles solo', [tiles.first('solo')]);
  }
  return div(classes: 'pt-tiles', [for (final tile in tiles) tile('pair')]);
}

/// `PortalWell`: the product grey with what is shown on it and labels in the
/// corners.
Component _well(
  String? topLeft,
  String? topRight,
  Component child, {
  bool bike = false,
}) => span(classes: bike ? 'pt-well bike' : 'pt-well', [
  span(classes: 'pt-well-in', [child]),
  if (topLeft != null) span(classes: 'pt-well-tl', [_tag(topLeft, 'ink')]),
  if (topRight != null) span(classes: 'pt-well-tr', [_t(topRight)]),
]);

/// `PortalThumb`: a square on the product grey with the whole photo, or a
/// drawing or a quiet icon.
Component _thumb({
  String? imageUrl,
  required String fallback,
  required int size,
  Component? drawing,
}) {
  final url = imageUrl?.trim() ?? '';
  final quiet =
      drawing ?? RawText(materialIcon(fallback, size: (size * 0.38).round()));
  return span(
    classes: 'pt-thumb',
    attributes: {'style': 'width:${size}px;height:${size}px'},
    [
      if (url.isEmpty)
        quiet
      else
        span(
          classes: 'pt-thumb-img',
          attributes: {'style': 'padding:${cssNum(size * 0.08)}px'},
          [_productImage(url, quiet)],
        ),
    ],
  );
}

/// `PortalProductImage`: the photo on the grey, its white melted into it
/// (multiply); [fallback] when it does not load.
Component _productImage(String url, Component fallback) =>
    span(classes: 'pt-pimg', [
      img(
        src: url,
        alt: '',
        attributes: {'loading': 'lazy', 'data-fallback': ''},
      ),
      span(classes: 'pt-pimg-fb', attributes: {'hidden': ''}, [fallback]),
    ]);

/// `CustomerBikeDrawing` as SVG: the strokes of `customerBikeStrokes`, scaled
/// by the width as Flutter's painter scales them. The box is [width] wide
/// and as high as its aspect asks, cut to [availableHeight] like a
/// constrained `SizedBox`; the drawing keeps its scale and overflows it.
Component _drawing(
  CustomerBikeSilhouette silhouette,
  double width, {
  required double availableHeight,
}) {
  final height = width / customerBikeDrawingWidth * customerBikeDrawingHeight;
  final boxHeight = height < availableHeight ? height : availableHeight;
  return RawText(
    '<span class="pt-draw" style="width:${cssNum(width)}px;'
    'height:${cssNum(boxHeight)}px" aria-hidden="true">'
    '${customerBikeSvg(silhouette)}</span>',
  );
}

/// The strokes of [silhouette] as an SVG on the 220×132 canvas.
String customerBikeSvg(CustomerBikeSilhouette silhouette) {
  String n(double value) => cssNum(value);
  String pt(BikePoint point) => '${n(point.$1)} ${n(point.$2)}';
  final paths = StringBuffer();
  for (final stroke in customerBikeStrokes(silhouette)) {
    final d = switch (stroke) {
      BikePolyline(:final points) =>
        'M${pt(points.first)}${points.skip(1).map((point) => 'L${pt(point)}').join()}',
      BikeCircle(:final center, :final radius) =>
        'M${n(center.$1 - radius)} ${n(center.$2)}'
            'a${n(radius)} ${n(radius)} 0 1 0 ${n(radius * 2)} 0'
            'a${n(radius)} ${n(radius)} 0 1 0 ${n(-radius * 2)} 0',
      BikeQuad(:final from, :final control, :final to) =>
        'M${pt(from)}Q${pt(control)} ${pt(to)}',
      BikeCubic(
        :final from,
        :final lineTo,
        :final control1,
        :final control2,
        :final to,
      ) =>
        'M${pt(from)}${lineTo.map((point) => 'L${pt(point)}').join()}'
            'C${pt(control1)} ${pt(control2)} ${pt(to)}',
      BikeArc(:final center, :final radius, :final start, :final sweep) => _arc(
        center,
        radius,
        start,
        sweep,
      ),
    };
    paths.write('<path d="$d" stroke-width="${n(stroke.width)}"/>');
  }
  return '<svg viewBox="0 0 220 132" fill="none" stroke="currentColor" '
      'stroke-linecap="round" stroke-linejoin="round">$paths</svg>';
}

String _arc(BikePoint center, double radius, double start, double sweep) {
  String n(double value) => cssNum(double.parse(value.toStringAsFixed(3)));
  final (cx, cy) = center;
  final x0 = cx + radius * _cos(start), y0 = cy + radius * _sin(start);
  final end = start + sweep;
  final x1 = cx + radius * _cos(end), y1 = cy + radius * _sin(end);
  final large = sweep.abs() > 3.141592653589793 ? 1 : 0;
  final clockwise = sweep > 0 ? 1 : 0;
  return 'M${n(x0)} ${n(y0)}A${n(radius)} ${n(radius)} 0 $large $clockwise '
      '${n(x1)} ${n(y1)}';
}

double _cos(double a) => math.cos(a);
double _sin(double a) => math.sin(a);
