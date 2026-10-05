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

import 'material_icons.dart';
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
    this.styles = '',
    this.overlayHeader = false,
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

  /// The page's own rules after the shared stylesheet: an editor page's
  /// theme colors and its blocks.
  final String styles;

  /// The header floats over the page's first block, clear with a dark veil
  /// until the page scrolls 50 px (`_StickyHeaderScaffold` with
  /// `allowOverlayAtTop`, which the store gives only to its home).
  final bool overlayHeader;
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
          if (meta.styles.isNotEmpty) RawText(meta.styles),
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
      SiteHeader(context, overlay: meta.overlayHeader),
      main_(id: 'contenido', content),
      SiteFooter(context),
      ...afterFooter,
      a(
        classes: 'chat-fab',
        href: '/cuenta/chats',
        attributes: {'aria-label': 'Conversar con ${s.storeName}'},
        [RawText(materialIcon(mdChat))],
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

const _overlayHeaderScript =
    '(function(h){function f(){h.classList.toggle("clear",scrollY<=50)}'
    'f();addEventListener("scroll",f,{passive:true})})'
    '(document.currentScript.parentNode)';

class SiteHeader extends StatelessComponent {
  const SiteHeader(this.page, {this.overlay = false, super.key});

  final PageContext page;

  /// See [PageMeta.overlayHeader].
  final bool overlay;

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
    final items = s.topLevel(MenuLocation.header);
    return header(classes: overlay ? 'top over' : 'top', [
      if (banner.isNotEmpty) p(classes: 'banner', [.text(banner)]),
      // Without JavaScript a checkbox opens the phone menu (a sheet from the
      // bottom, as Flutter's); it comes before the sheet for `~`.
      Component.element(
        tag: 'input',
        id: 'menu-toggle',
        classes: 'menu-toggle',
        attributes: {'type': 'checkbox', 'aria-label': 'Abrir el menú'},
      ),
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
        // The full menu, from 1.080 px (`PublicStoreHeaderGeometry`).
        nav(
          classes: 'menu',
          attributes: {'aria-label': 'Principal'},
          [
            ul([
              for (final item in items) ?_menuItem(item, s.childrenOf(item)),
            ]),
          ],
        ),
        div(classes: 'tools', [
          a(
            href: '/productos#buscar',
            attributes: {'aria-label': 'Buscar productos'},
            [RawText(materialIcon(mdSearch))],
          ),
          a(
            classes: 'cart-link',
            href: '/carrito',
            attributes: {'aria-label': 'Carrito'},
            [
              RawText(materialIcon(mdCartOutlined)),
              span(
                classes: 'cart-count',
                attributes: {'data-cart-count': '', 'hidden': ''},
                [.text('0')],
              ),
            ],
          ),
          a(classes: 'login', href: '/cuenta/login', [
            RawText(materialIcon(mdPersonOutline)),
            .text('Iniciar sesión'),
          ]),
          Component.element(
            tag: 'label',
            classes: 'menu-button',
            attributes: {'for': 'menu-toggle', 'title': 'Menú'},
            children: [RawText(materialIcon(mdMenu))],
          ),
        ]),
      ]),
      Component.element(
        tag: 'label',
        classes: 'sheet-scrim',
        attributes: {'for': 'menu-toggle', 'aria-hidden': 'true'},
      ),
      div(classes: 'menu-sheet', [
        span(classes: 'sheet-handle', []),
        a(classes: 'sheet-item sheet-login', href: '/cuenta/login', [
          RawText(materialIcon(mdLoginRounded)),
          span([.text('Iniciar Sesión')]),
        ]),
        hr(),
        nav(
          attributes: {'aria-label': 'Menú del teléfono'},
          [
            for (final item in items)
              if (item.showOnMobile)
                ?_sheetItem(item, s.childrenOf(item), depth: 0),
          ],
        ),
      ]),
      // Run while the page is parsed, before anything under the header is
      // painted: clear at the top, solid after 50 px of scroll. Without
      // scripts the header stays solid, which is always readable.
      if (overlay) script(content: _overlayHeaderScript),
    ]);
  }

  /// One row of the phone sheet, as `_buildMobileNavigationNode` draws it:
  /// an item with children opens in place with «Ver todo …» first.
  Component? _sheetItem(
    WebsiteNavigation item,
    List<WebsiteNavigation> children, {
    required int depth,
  }) {
    final href = page.shell.hrefFor(item);
    final visible = [
      for (final child in children)
        if (child.showOnMobile) child,
    ];
    final indent = 'padding-left:${24 + depth * 14}px';
    if (visible.isEmpty) {
      if (href == null) return null;
      return a(
        classes: 'sheet-item',
        href: href,
        attributes: {
          'style': indent,
          if (_current(href)) 'aria-current': 'page',
        },
        [
          RawText(
            materialIcon(depth == 0 ? mdArrowForward : mdSubdirectoryRight),
          ),
          span([.text(item.label)]),
          RawText(materialIcon(mdChevronRight, size: 20, classes: 'go')),
        ],
      );
    }
    return details(classes: 'sheet-group', [
      summary(
        classes: 'sheet-item',
        attributes: {'style': indent},
        [
          RawText(materialIcon(mdFolderOutlined)),
          span([.text(item.label)]),
          RawText(materialIcon(mdExpandMore, classes: 'go')),
        ],
      ),
      if (href != null)
        a(
          classes: 'sheet-item sheet-all',
          href: href,
          attributes: {'style': 'padding-left:${24 + (depth + 1) * 14}px'},
          [
            RawText(materialIcon(mdArrowForward)),
            span([.text('Ver todo ${item.label}')]),
            RawText(materialIcon(mdChevronRight, size: 20, classes: 'go')),
          ],
        ),
      for (final child in visible)
        ?_sheetItem(child, page.shell.childrenOf(child), depth: depth + 1),
    ]);
  }

  /// Flutter marks an item only on its own page (`matchedLocation == href`),
  /// never a parent of it: `/productos` is not current on a category.
  bool _current(String href) => Uri.parse(href).path == page.path;

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
    // Font Awesome's brand glyphs, from the font Flutter already serves.
    final socials = <(String, String?, String)>[
      (
        'Facebook',
        normalizeSocialUrl(
          s.setting('facebook', s.setting('facebook_handle')),
          'https://facebook.com/',
        ),
        '\u{f09a}',
      ),
      (
        'Instagram',
        normalizeSocialUrl(
          s.setting('instagram', s.setting('instagram_handle')),
          'https://instagram.com/',
        ),
        '\u{f16d}',
      ),
      (
        'X',
        normalizeSocialUrl(
          s.setting('twitter', s.setting('twitter_handle')),
          'https://twitter.com/',
        ),
        '\u{e61b}',
      ),
      (
        'YouTube',
        normalizeSocialUrl(
          s.setting('youtube', s.setting('youtube_handle')),
          'https://youtube.com/',
          keepAtPrefix: true,
        ),
        '\u{f167}',
      ),
      (
        'WhatsApp',
        s.whatsappDigits.isEmpty
            ? null
            : 'https://wa.me/${s.whatsappDigits}?text='
                  '${Uri.encodeComponent('Hola ${s.storeName}, vengo desde el sitio web')}',
        '\u{f232}',
      ),
    ];
    Component logoLink(int height) => a(href: '/', classes: 'foot-logo', [
      if (logo.isEmpty)
        span(classes: 'foot-name', [.text(s.storeName)])
      else
        img(
          src: logo.startsWith('http') ? logo : '/$logo',
          alt: s.storeName,
          height: height,
          loading: MediaLoading.lazy,
        ),
    ]);
    Component socialLinks({required bool round}) =>
        div(classes: round ? 'foot-social round' : 'foot-social', [
          for (final (label, url, glyph) in socials)
            if (url != null)
              a(
                href: url,
                attributes: {
                  'aria-label': label,
                  'title': label,
                  'rel': 'noopener',
                  'target': '_blank',
                },
                [
                  span(
                    classes: 'fab',
                    attributes: {'aria-hidden': 'true'},
                    [.text(glyph)],
                  ),
                ],
              ),
        ]);
    final hasContact =
        address.isNotEmpty || phone.isNotEmpty || email.isNotEmpty;
    Component contactList() => ul(classes: 'contact', [
      if (address.isNotEmpty)
        li([
          RawText(materialIcon(mdLocationOnOutlined, size: 20)),
          span([.text(address)]),
        ]),
      if (phone.isNotEmpty)
        li([
          RawText(materialIcon(mdPhoneOutlined, size: 20)),
          a(href: 'tel:${phone.replaceAll(' ', '')}', [.text(phone)]),
        ]),
      if (email.isNotEmpty)
        li([
          RawText(materialIcon(mdEmailOutlined, size: 20)),
          a(href: 'mailto:$email', [.text(email)]),
        ]),
    ]);
    final legal = p(classes: 'legal', [
      .text(
        '© ${DateTime.now().year}${s.storeName.isNotEmpty ? ' ${s.storeName}' : ''}. '
        'Todos los derechos reservados.',
      ),
    ]);
    Component collapsible(String title, Component body) =>
        details(classes: 'foot-sec', [
          summary([
            span([.text(title.toUpperCase())]),
            RawText(materialIcon(mdExpandMore)),
          ]),
          body,
        ]);
    final mobileColumns = _footerFor(s, desktop: false);

    // Flutter draws one footer from 800 px up and another below; so does
    // this page, with the same breakpoint.
    return footer(classes: 'foot', [
      div(classes: 'foot-wide', [
        div(classes: 'foot-grid', [
          div(classes: 'foot-brand', [
            logoLink(60),
            if (s.storeDescription.isNotEmpty)
              p(classes: 'foot-about', [.text(s.storeDescription)]),
            socialLinks(round: false),
          ]),
          for (final column in _footerFor(s, desktop: true))
            div(classes: 'foot-col', [
              p(classes: 'foot-title', [.text(column.title)]),
              ul([
                for (final link in column.links)
                  li([
                    // Bold for the page being read, as Flutter's desktop
                    // footer (`matchedLocation == href`).
                    a(
                      href: s.hrefFor(link)!,
                      attributes: {
                        if (s.hrefFor(link) == page.path)
                          'aria-current': 'page',
                      },
                      [.text(link.label)],
                    ),
                  ]),
              ]),
            ]),
          if (hasContact)
            div(classes: 'foot-col', [
              p(classes: 'foot-title', [.text('Contacto')]),
              contactList(),
            ]),
        ]),
        if (s.paymentClaims.isNotEmpty)
          div(
            classes: 'payments',
            attributes: {
              'role': 'group',
              'aria-label': 'Medios de pago aceptados',
            },
            [
              p([.text('Medios de Pago')]),
              ul([
                for (final code in s.paymentClaims) li([_paymentBadge(code)]),
              ]),
            ],
          ),
        hr(classes: 'foot-rule'),
        legal,
      ]),
      div(classes: 'foot-narrow', [
        logoLink(50),
        for (final column in mobileColumns) ...[
          collapsible(
            column.title,
            ul([
              for (final link in column.links)
                li([
                  a(href: s.hrefFor(link)!, [.text(link.label)]),
                ]),
            ]),
          ),
          hr(classes: 'foot-rule'),
        ],
        if (hasContact) ...[
          collapsible('Contacto', contactList()),
          hr(classes: 'foot-rule'),
        ],
        if (socials.any((entry) => entry.$2 != null)) ...[
          p(classes: 'follow', [.text('¡SÍGUENOS!')]),
          socialLinks(round: true),
        ],
        legal,
      ]),
    ]);
  }

  static Component _paymentBadge(PublicCheckoutPaymentCode code) {
    final claim = kPublicStorePaymentClaims[code]!;
    if (claim.imageUrl case final url?) {
      return img(
        classes: 'pay-logo',
        src: url,
        alt: claim.label,
        attributes: {'title': claim.label},
        loading: MediaLoading.lazy,
      );
    }
    return span(classes: 'pay-chip', [
      RawText(materialIcon(mdAccountBalanceOutlined, size: 15)),
      .text(claim.label),
    ]);
  }

  /// The Flutter footer's rule for one audience: among the roots shown to
  /// it, the ones with navigable descendants are columns (a structural item
  /// without a destination passes its published children up); when none
  /// has, every navigable root is a link under «Enlaces».
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
