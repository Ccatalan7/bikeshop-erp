import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/public_store/models/public_business_hours.dart';
import 'package:vinabike_public_core/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_public_core/public_store/models/public_payment_claims.dart';
import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_identity.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_structured_data.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/utils/social_url.dart';

import 'storefront_css.dart';
import 'storefront_script.dart';
import 'storefront_shell.dart';

/// What one page says about itself in its `<head>`.
class PageMeta {
  const PageMeta({
    required this.title,
    required this.description,
    required this.canonicalUrl,
    required this.indexable,
    this.ogType = 'website',
    this.imageUrl = '',
    this.preloadImage,
    this.structuredData = const [],
    this.preloadHeadingFont = false,
  });

  final String title;
  final String description;
  final String canonicalUrl;
  final bool indexable;
  final String ogType;
  final String imageUrl;
  final ({String src, String? srcset, String? sizes})? preloadImage;
  final List<Map<String, dynamic>> structuredData;

  /// The heading font (172 KB for Oswald) draws the price of a product page
  /// at first sight; a catalog page uses only the body font, and preloading
  /// the other one took bandwidth from its first photo (2026-10-05).
  final bool preloadHeadingFont;
}

/// Request facts every page needs.
class PageContext {
  const PageContext({
    required this.shell,
    required this.tenantId,
    required this.fallbackOrigin,
    required this.path,
    required this.hidden,
    this.query = '',
  });

  final StorefrontShell shell;
  final String tenantId;
  final String fallbackOrigin;

  /// The public path being served, without the hidden prefix.
  final String path;

  /// The request's query, as sent.
  final String query;

  /// The public URL being served, without the hidden prefix.
  Uri get uri => Uri(path: path, query: query.isEmpty ? null : query);

  /// Served under `/_html` next to the Flutter page it mirrors: never
  /// indexed, never measured.
  final bool hidden;

  String get storeUrl => shell.storeOrigin(fallbackOrigin);
}

/// The whole document around a page's content.
Component sitePage({
  required PageContext context,
  required PageMeta meta,
  required List<Component> content,
  List<Component> afterFooter = const [],
}) {
  final s = context.shell;
  final indexable = meta.indexable && !context.hidden;
  final business = _businessNode(context);
  return Document(
    lang: 'es-CL',
    // No <base>: it would turn in-page anchors into links to the home.
    base: null,
    title: meta.title,
    meta: {
      'description': meta.description,
      'robots': indexable ? 'index,follow' : 'noindex,follow',
      'theme-color': s.primaryColor,
    },
    head: [
      link(rel: 'canonical', href: meta.canonicalUrl),
      _property('og:type', meta.ogType),
      _property('og:url', meta.canonicalUrl),
      _property('og:title', meta.title),
      _property('og:description', meta.description),
      _property('og:site_name', s.storeName),
      _property('og:locale', 'es_CL'),
      if (meta.imageUrl.isNotEmpty) _property('og:image', meta.imageUrl),
      _name('twitter:card', 'summary_large_image'),
      _name('twitter:title', meta.title),
      _name('twitter:description', meta.description),
      if (meta.imageUrl.isNotEmpty) _name('twitter:image', meta.imageUrl),
      if (meta.preloadHeadingFont)
        _preload('/assets/assets/fonts/${_fontFile(s.headingFont)}', 'font'),
      if (meta.preloadImage case final image?)
        Component.element(
          tag: 'link',
          attributes: {
            'rel': 'preload',
            'as': 'image',
            'href': image.src,
            'imagesrcset': ?image.srcset,
            'imagesizes': ?image.sizes,
            'fetchpriority': 'high',
          },
        ),
      Component.element(
        tag: 'style',
        children: [
          RawText(
            storefrontCss(
              primary: s.primaryColor,
              accent: s.accentColor,
              headingFont: s.headingFont,
              bodyFont: s.bodyFont,
            ),
          ),
        ],
      ),
      for (final data in [business, ...meta.structuredData])
        // Escaped by the shared encoder: no «<» can close the script.
        script(
          attributes: {'type': 'application/ld+json'},
          content: encodeStructuredDataForHtml(data),
        ),
      if (!context.hidden && s.googleAnalyticsId != null)
        script(
          content: measurementScript(
            gaId: s.googleAnalyticsId!,
            storeHost: s.canonicalHost(context.fallbackOrigin),
            pixelId: s.setting('seo_fb_pixel_id'),
          ),
        ),
    ],
    body: Component.fragment([
      a(classes: 'skip', href: '#contenido', [.text('Ir al contenido')]),
      SiteHeader(context),
      main_(id: 'contenido', content),
      SiteFooter(context),
      ...afterFooter,
      a(
        classes: 'chat-fab',
        href: '/cuenta/chats',
        attributes: {'aria-label': 'Conversar con ${s.storeName}'},
        [const RawText(_chatIcon)],
      ),
      script(content: _bodyData(context)),
      script(content: storefrontScript),
    ]),
  );
}

/// Sets the cart identity on the body before the page script reads it: the
/// tenant and `flutter.public_store_cart_v2.<base64url(tenant)>`, the key
/// Flutter's `SharedPreferencesCartStore.storageKeyForTenant` builds.
String _bodyData(PageContext context) {
  final key =
      'flutter.public_store_cart_v2.${base64Url.encode(utf8.encode(context.tenantId))}';
  return 'document.body.dataset.tenant=${jsonEncode(context.tenantId)};'
      'document.body.dataset.cartKey=${jsonEncode(key)};';
}

/// The `BikeStore` node every public page carries, as the Flutter store's
/// `index.html` has it after the build completes it.
Map<String, dynamic> _businessNode(PageContext context) {
  final s = context.shell;
  final logo = storefrontFirstLogoSource(
    configuredUrl: s.settings['logo_url'] ?? '',
    tenantId: context.tenantId,
  );
  final storeUrl = context.storeUrl;
  return completePublicBusinessStructuredData(
    buildPublicBusinessIdentity(s.settings),
    logoUrl: logo.isEmpty || logo.startsWith('https://')
        ? logo
        : '$storeUrl/$logo',
    imageUrl: s.setting('seo_og_image'),
    mapUrl: s.setting(
      'seo_google_maps_url',
      s.setting('business_google_maps_url', s.setting('google_maps_url')),
    ),
    hours: parsePublicBusinessHours(s.setting('business_hours_json')),
    returnPolicyUrl: s.pagePublication.isPublishedPath('/devoluciones')
        ? '$storeUrl/devoluciones'
        : '',
  );
}

class SiteHeader extends StatelessComponent {
  const SiteHeader(this.page, {super.key});

  final PageContext page;

  @override
  Component build(BuildContext context) {
    final s = page.shell;
    final logo = storefrontFirstLogoSource(
      configuredUrl: s.settings['logo_url'] ?? '',
      tenantId: page.tenantId,
    );
    final banner = s.setting('header_show_top_banner') == 'true'
        ? s.setting('top_banner_text')
        : '';
    return header(classes: 'top', [
      if (banner.isNotEmpty) p(classes: 'banner', [.text(banner)]),
      div(classes: 'wrap bar', [
        a(classes: 'logo', href: '/', [
          // No logo of its own: the store writes its name, as in Flutter.
          if (logo.isEmpty)
            span(classes: 'logo-name', [.text(s.storeName)])
          else
            img(
              src: logo.startsWith('http') ? logo : '/$logo',
              alt: s.storeName,
              width: 150,
              height: 40,
            ),
        ]),
        // Without JavaScript a checkbox opens the menu on a phone; on a
        // desktop the menu is always visible.
        Component.element(
          tag: 'input',
          id: 'menu-toggle',
          classes: 'menu-toggle',
          attributes: {'type': 'checkbox', 'aria-label': 'Abrir el menú'},
        ),
        Component.element(
          tag: 'label',
          classes: 'menu-button',
          attributes: {'for': 'menu-toggle', 'aria-hidden': 'true'},
          children: [span([]), span([]), span([])],
        ),
        div(classes: 'menu', [
          nav(
            attributes: {'aria-label': 'Principal'},
            [
              ul([
                for (final item in s.topLevel(MenuLocation.header))
                  ?_menuItem(item, s.childrenOf(item)),
              ]),
            ],
          ),
          a(classes: 'menu-login', href: '/cuenta/login', [
            .text('Iniciar sesión'),
          ]),
        ]),
        div(classes: 'tools', [
          a(
            href: '/productos#buscar',
            attributes: {'aria-label': 'Buscar productos'},
            [const RawText(_searchIcon)],
          ),
          a(
            classes: 'cart-link',
            href: '/carrito',
            attributes: {'aria-label': 'Carrito'},
            [
              const RawText(_cartIcon),
              span(
                classes: 'cart-count',
                attributes: {'data-cart-count': '', 'hidden': ''},
                [.text('0')],
              ),
            ],
          ),
          a(classes: 'login', href: '/cuenta/login', [
            const RawText(_personIcon),
            .text('Iniciar sesión'),
          ]),
        ]),
      ]),
    ]);
  }

  bool _current(String href) {
    final path = Uri.parse(href).path;
    if (path == '/') return page.path == '/';
    return page.path == path || page.path.startsWith('$path/');
  }

  Component? _menuItem(
    WebsiteNavigation item,
    List<WebsiteNavigation> children,
  ) {
    final href = page.shell.hrefFor(item);
    if (href == null) return null;
    final links = [
      for (final child in children)
        if (page.shell.hrefFor(child) case final childHref?)
          li(classes: _deviceClasses(child), [
            a(
              href: childHref,
              attributes: {if (_current(childHref)) 'aria-current': 'page'},
              [.text(child.label)],
            ),
          ]),
    ];
    final link = a(
      href: href,
      attributes: {if (_current(href)) 'aria-current': 'page'},
      [.text(item.label)],
    );
    if (links.isEmpty) {
      return li(classes: _deviceClasses(item), [link]);
    }
    return li(classes: _deviceClasses(item, 'has-sub'), [
      link,
      ul(classes: 'sub', links),
    ]);
  }
}

class SiteFooter extends StatelessComponent {
  const SiteFooter(this.page, {super.key});

  final PageContext page;

  @override
  Component build(BuildContext context) {
    final s = page.shell;
    final phone = s.setting('contact_phone');
    final email = s.setting('contact_email');
    final address = s.setting('contact_address');
    final logo = storefrontFirstLogoSource(
      configuredUrl: s.settings['logo_url'] ?? '',
      tenantId: page.tenantId,
    );
    final socials = <(String, String?, String)>[
      (
        'Facebook',
        normalizeSocialUrl(
          s.setting('facebook', s.setting('facebook_handle')),
          'https://facebook.com/',
        ),
        _facebookIcon,
      ),
      (
        'Instagram',
        normalizeSocialUrl(
          s.setting('instagram', s.setting('instagram_handle')),
          'https://instagram.com/',
        ),
        _instagramIcon,
      ),
      (
        'X',
        normalizeSocialUrl(
          s.setting('twitter', s.setting('twitter_handle')),
          'https://twitter.com/',
        ),
        _xIcon,
      ),
      (
        'YouTube',
        normalizeSocialUrl(
          s.setting('youtube', s.setting('youtube_handle')),
          'https://youtube.com/',
          keepAtPrefix: true,
        ),
        _youtubeIcon,
      ),
      (
        'WhatsApp',
        s.whatsappDigits.isEmpty ? null : 'https://wa.me/${s.whatsappDigits}',
        _whatsappIcon,
      ),
    ];
    return footer(classes: 'foot', [
      div(classes: 'wrap foot-grid', [
        div(classes: 'foot-brand', [
          a(href: '/', classes: 'foot-logo', [
            if (logo.isEmpty)
              span(classes: 'foot-name', [.text(s.storeName)])
            else
              img(
                src: logo.startsWith('http') ? logo : '/$logo',
                alt: s.storeName,
                width: 180,
                height: 48,
                loading: MediaLoading.lazy,
              ),
          ]),
          if (s.storeDescription.isNotEmpty) p([.text(s.storeDescription)]),
          ul(classes: 'socials', [
            for (final (label, url, icon) in socials)
              if (url != null)
                li([
                  a(
                    href: url,
                    attributes: {
                      'aria-label': label,
                      'rel': 'noopener',
                      'target': '_blank',
                    },
                    [RawText(icon)],
                  ),
                ]),
          ]),
        ]),
        ..._footerColumns(s),
        if (address.isNotEmpty || phone.isNotEmpty || email.isNotEmpty)
          div([
            p(classes: 'foot-title', [.text('Contacto')]),
            ul(classes: 'contact', [
              if (address.isNotEmpty)
                li([const RawText(_pinIcon), span([.text(address)])]),
              if (phone.isNotEmpty)
                li([
                  const RawText(_phoneIcon),
                  a(href: 'tel:${phone.replaceAll(' ', '')}', [.text(phone)]),
                ]),
              if (email.isNotEmpty)
                li([
                  const RawText(_mailIcon),
                  a(href: 'mailto:$email', [.text(email)]),
                ]),
            ]),
          ]),
      ]),
      if (s.paymentClaims.isNotEmpty)
        div(
          classes: 'wrap payments',
          attributes: {'role': 'group', 'aria-label': 'Medios de pago aceptados'},
          [
            p([.text('Medios de Pago')]),
            ul([
              for (final code in s.paymentClaims)
                li([_paymentBadge(code)]),
            ]),
          ],
        ),
      p(classes: 'wrap legal', [
        .text(
          '© ${DateTime.now().year}${s.storeName.isNotEmpty ? ' ${s.storeName}' : ''}. '
          'Todos los derechos reservados.',
        ),
      ]),
    ]);
  }

  static Component _paymentBadge(PublicCheckoutPaymentCode code) {
    final claim = kPublicStorePaymentClaims[code]!;
    if (claim.imageUrl case final url?) {
      return span(classes: 'pay-badge', [
        img(
          src: url,
          alt: claim.label,
          width: 72,
          height: 24,
          loading: MediaLoading.lazy,
        ),
      ]);
    }
    return span(classes: 'pay-chip', [
      const RawText(_bankIcon),
      .text(claim.label),
    ]);
  }

  /// The Flutter footer's rule, worked out once per audience like its
  /// desktop and mobile footers: among the roots shown to that audience, the
  /// ones with navigable descendants are columns (a structural item without a
  /// destination passes its published children up); when none has, every
  /// navigable root is a link under «Enlaces». When both audiences get the
  /// same footer it is drawn once, otherwise each with its device class.
  static List<Component> _footerColumns(StorefrontShell shell) {
    final desktop = _footerFor(shell, desktop: true);
    final mobile = _footerFor(shell, desktop: false);
    String key(List<_FooterColumn> columns) => [
      for (final column in columns)
        '${column.title}:${column.links.map((l) => l.id).join(',')}',
    ].join('|');
    if (key(desktop) == key(mobile)) return _renderFooter(shell, desktop);
    return [
      ..._renderFooter(shell, desktop, classes: 'nav-no-mobile'),
      ..._renderFooter(shell, mobile, classes: 'nav-no-desktop'),
    ];
  }

  static List<_FooterColumn> _footerFor(
    StorefrontShell shell, {
    required bool desktop,
  }) {
    bool shown(WebsiteNavigation item) =>
        item.isVisible && (desktop ? item.showOnDesktop : item.showOnMobile);
    bool navigable(WebsiteNavigation item) => shell.hrefFor(item) != null;
    List<WebsiteNavigation> descendants(Iterable<WebsiteNavigation> nodes) {
      final result = <WebsiteNavigation>[];
      void visit(Iterable<WebsiteNavigation> current) {
        for (final node in current) {
          if (!shown(node)) continue;
          if (navigable(node)) {
            result.add(node);
          } else {
            visit(shell.childrenOf(node));
          }
        }
      }

      visit(nodes);
      return result;
    }

    final roots = [
      for (final root in shell.topLevel(MenuLocation.footer))
        if (shown(root)) root,
    ];
    final sections = [
      for (final root in roots)
        if (descendants(shell.childrenOf(root)) case final links
            when links.isNotEmpty)
          _FooterColumn(root.label, links),
    ];
    if (sections.isNotEmpty) return sections;
    final flat = [
      for (final root in roots)
        if (navigable(root)) root,
    ];
    return flat.isEmpty ? const [] : [_FooterColumn('Enlaces', flat)];
  }

  static List<Component> _renderFooter(
    StorefrontShell shell,
    List<_FooterColumn> columns, {
    String? classes,
  }) => [
    for (final column in columns)
      div(classes: classes, [
        p(classes: 'foot-title', [.text(column.title)]),
        ul([
          for (final link in column.links)
            li([
              a(href: shell.hrefFor(link)!, [.text(link.label)]),
            ]),
        ]),
      ]),
  ];
}

class _FooterColumn {
  const _FooterColumn(this.title, this.links);
  final String title;
  final List<WebsiteNavigation> links;
}

/// The page shown when the editor unpublished the site, as Flutter shows it.
Component unpublishedPage(PageContext context) {
  final s = context.shell;
  final label = s.storeName.isNotEmpty ? s.storeName : 'Mi Tienda';
  return Document(
    lang: 'es-CL',
    base: null,
    title: '$label no está publicado',
    meta: {'robots': 'noindex,nofollow'},
    head: [
      Component.element(
        tag: 'style',
        children: [
          RawText(
            storefrontCss(
              primary: s.primaryColor,
              accent: s.accentColor,
              headingFont: s.headingFont,
              bodyFont: s.bodyFont,
            ),
          ),
        ],
      ),
    ],
    body: main_(classes: 'holding', [
      h1([.text('$label no está publicado')]),
      p([.text('Este sitio está en construcción. Vuelve pronto.')]),
    ]),
  );
}

/// GA4 and the Meta Pixel, behind the same two gates as the Flutter store's
/// `index.html` (`scripts/sync_seo_index.sh`): only on the store's own host,
/// and never in a browser marked with `?sin_medir` (cookie `vb_sin_medir` or
/// its localStorage copy). The browser decides it: Firebase Hosting strips
/// every cookie but `__session` before a request reaches Cloud Run, so the
/// server never sees the mark.
String measurementScript({
  required String gaId,
  required String storeHost,
  required String pixelId,
}) {
  final pixel = RegExp(r'^\d+$').hasMatch(pixelId) ? pixelId : '';
  return '''
window.dataLayer = window.dataLayer || [];
function gtag() { dataLayer.push(arguments); }
(function () {
  var storeHost = ${jsonEncode(storeHost)};
  var host = (window.location.host || '').toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  window.vinabikeMeasurementAllowed = false;
  if (host !== storeHost) return;
  var markName = 'vb_sin_medir';
  function readMark() {
    if (('; ' + document.cookie + ';').indexOf('; ' + markName + '=1;') !== -1) return true;
    try { return window.localStorage.getItem(markName) === '1'; } catch (e) { return false; }
  }
  function writeMark(on) {
    document.cookie = markName + '=' + (on ? '1' : '') + '; Domain=' + storeHost +
      '; Path=/; Max-Age=' + (on ? 34560000 : 0) + '; SameSite=Lax; Secure';
    try {
      if (on) { window.localStorage.setItem(markName, '1'); }
      else { window.localStorage.removeItem(markName); }
    } catch (e) { /* the cookie alone still works */ }
  }
  function showNote(text) {
    function place() {
      var note = document.createElement('div');
      note.setAttribute('role', 'status');
      note.className = 'mark-note';
      note.textContent = text;
      document.body.appendChild(note);
      window.setTimeout(function () { note.remove(); }, 7000);
    }
    if (document.body) { place(); } else {
      document.addEventListener('DOMContentLoaded', place, { once: true });
    }
  }
  try {
    var params = new URLSearchParams(window.location.search || '');
    var asked = params.has('sin_medir') ? true : params.has('medir') ? false : null;
    if (asked !== null) {
      writeMark(asked);
      params.delete('sin_medir');
      params.delete('medir');
      var query = params.toString();
      window.history.replaceState(window.history.state, '',
        window.location.pathname + (query ? '?' + query : '') + window.location.hash);
      showNote(asked
        ? 'Listo: las visitas de este navegador ya no se cuentan en Google Analytics.'
        : 'Listo: las visitas de este navegador vuelven a contarse en Google Analytics.');
    }
  } catch (e) { /* an old browser keeps whatever mark it had */ }
  if (readMark()) { writeMark(true); return; }
  window.vinabikeMeasurementAllowed = true;

  gtag('js', new Date());
  gtag('config', ${jsonEncode(gaId)});
  var pixelId = ${jsonEncode(pixel)};
  if (pixelId) {
    var fbq = window.fbq = function () {
      fbq.callMethod ? fbq.callMethod.apply(fbq, arguments) : fbq.queue.push(arguments);
    };
    if (!window._fbq) window._fbq = fbq;
    fbq.push = fbq; fbq.loaded = true; fbq.version = '2.0'; fbq.queue = [];
    fbq('init', pixelId);
    fbq('track', 'PageView');
  }
  function load() {
    var tag = document.createElement('script');
    tag.async = true;
    tag.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(${jsonEncode(gaId)});
    document.head.appendChild(tag);
    if (pixelId) {
      var px = document.createElement('script');
      px.async = true;
      px.src = 'https://connect.facebook.net/en_US/fbevents.js';
      document.head.appendChild(px);
    }
  }
  function schedule() {
    if ('requestIdleCallback' in window) {
      window.requestIdleCallback(load, { timeout: 2500 });
    } else {
      window.setTimeout(load, 0);
    }
  }
  if (document.readyState === 'complete') { schedule(); }
  else { window.addEventListener('load', schedule, { once: true }); }
})();
''';
}

/// `show_on_desktop` / `show_on_mobile` as classes the stylesheet hides at
/// the phone breakpoint, so one HTML serves both like Flutter's two menus.
String? _deviceClasses(WebsiteNavigation item, [String? base]) {
  final classes = [
    ?base,
    if (!item.showOnMobile) 'nav-no-mobile',
    if (!item.showOnDesktop) 'nav-no-desktop',
  ];
  return classes.isEmpty ? null : classes.join(' ');
}

Component _property(String property, String content) => Component.element(
  tag: 'meta',
  attributes: {'property': property, 'content': content},
);

Component _name(String name, String content) => Component.element(
  tag: 'meta',
  attributes: {'name': name, 'content': content},
);

Component _preload(String href, String as) => Component.element(
  tag: 'link',
  attributes: {
    'rel': 'preload',
    'href': href,
    'as': as,
    'type': 'font/ttf',
    'crossorigin': '',
  },
);

/// The bundled font file Firebase serves for a family.
String _fontFile(String family) =>
    family == 'Oswald' ? 'Oswald-wght.ttf' : 'Barlow-SemiBold.ttf';

const _searchIcon =
    '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
    '<circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<path d="M20 20l-4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

const _cartIcon =
    '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
    '<path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.5L21 8H6.2" '
    'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round"/><circle cx="10" cy="20" r="1.4" fill="currentColor"/>'
    '<circle cx="17" cy="20" r="1.4" fill="currentColor"/></svg>';

const _personIcon =
    '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">'
    '<circle cx="12" cy="8" r="4" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<path d="M4 21c1.6-4 4.5-6 8-6s6.4 2 8 6" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round"/></svg>';

const _chatIcon =
    '<svg viewBox="0 0 24 24" width="26" height="26" aria-hidden="true">'
    '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8a2.5 2.5 0 0 1-2.5 2.5H9l-5 4z" '
    'fill="currentColor"/><path d="M8 8h8M8 11.5h5" stroke="#1e293b" stroke-width="1.8" '
    'stroke-linecap="round"/></svg>';

const _pinIcon =
    '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">'
    '<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0C18.5 15 12 21 12 21z" fill="none" '
    'stroke="currentColor" stroke-width="1.8"/><circle cx="12" cy="10" r="2.3" fill="none" '
    'stroke="currentColor" stroke-width="1.8"/></svg>';

const _phoneIcon =
    '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">'
    '<path d="M6.6 3.5l3 3.2-1.8 2.1a12 12 0 0 0 7.4 7.4l2.1-1.8 3.2 3-1.6 2.6c-.6.9-1.7 1.2-2.7.9'
    'C9.6 19 5 14.4 3.1 7.8c-.3-1 0-2.1.9-2.7z" fill="none" stroke="currentColor" '
    'stroke-width="1.8" stroke-linejoin="round"/></svg>';

const _mailIcon =
    '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">'
    '<rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" '
    'stroke-width="1.8"/><path d="M4 7l8 6 8-6" fill="none" stroke="currentColor" '
    'stroke-width="1.8" stroke-linejoin="round"/></svg>';

const _bankIcon =
    '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">'
    '<path d="M3 9.5L12 4l9 5.5M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18" fill="none" '
    'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" '
    'stroke-linejoin="round"/></svg>';

const _instagramIcon =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">'
    '<rect x="3.5" y="3.5" width="17" height="17" rx="5" fill="none" stroke="currentColor" '
    'stroke-width="1.8"/><circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" '
    'stroke-width="1.8"/><circle cx="17.2" cy="6.8" r="1.2" fill="currentColor"/></svg>';

const _facebookIcon =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">'
    '<path d="M13.5 21v-7.5h2.6l.4-3h-3V8.7c0-.9.3-1.5 1.6-1.5h1.6V4.5a20 20 0 0 0-2.4-.1'
    'c-2.4 0-4 1.4-4 4.1v2h-2.6v3h2.6V21z" fill="currentColor"/></svg>';

const _xIcon =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">'
    '<path d="M4 4l16 16M20 4L4 20" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round"/></svg>';

const _youtubeIcon =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">'
    '<rect x="2.5" y="5.5" width="19" height="13" rx="4" fill="none" stroke="currentColor" '
    'stroke-width="1.8"/><path d="M10 9v6l5-3z" fill="currentColor"/></svg>';

const _whatsappIcon =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">'
    '<path d="M12 3.5a8.5 8.5 0 0 0-7.3 12.8L3.5 20.5l4.3-1.1A8.5 8.5 0 1 0 12 3.5z" '
    'fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>'
    '<path d="M9 8.2c.3-.4.7-.4 1-.1l.9 1.6c.2.3.1.6-.1.9l-.5.5a5.5 5.5 0 0 0 2.6 2.6l.5-.5'
    'c.3-.2.6-.3.9-.1l1.6.9c.3.3.3.7-.1 1-.9.9-2 1.2-3.3.6a8.6 8.6 0 0 1-3.9-3.9'
    'c-.6-1.3-.3-2.4.6-3.3z" fill="currentColor"/></svg>';
