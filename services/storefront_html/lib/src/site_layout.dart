import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_business_hours.dart';
import 'package:vinabike_public_core/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_public_core/public_store/models/public_payment_claims.dart';
import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_identity.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_structured_data.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/utils/social_url.dart';

import 'material_icons.dart';
import 'mega_menu_view.dart';
import 'storefront_css.dart';
import 'storefront_fonts.dart';
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
    this.supabaseUrl = '',
    this.publishableKey = '',
    this.draft = false,
    this.showsHidden = false,
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

  /// Where the browser reaches Supabase with the publishable key, as the
  /// Flutter store does: the customer's session (header, checkout, order).
  final String supabaseUrl;
  final String publishableKey;

  /// The editor's draft (`POST /editor/borrador`): what a click picks is
  /// named on the page ([pick]).
  final bool draft;

  /// The draft while the operator edits (not «Vista previa»): blocks the
  /// store does not show are drawn veiled, as the canvas edits them.
  final bool showsHidden;

  /// In the editor's draft, the attributes that make an element the part
  /// [selectionId] names (a block's id, `header`, `footer`, a catalog or
  /// product page section), called [label] as on the canvas: a click on it
  /// selects that part in the panel.
  Map<String, String> pick(String selectionId, String label) => draft
      ? {'data-block-id': selectionId, 'data-block-label': label}
      : const {};
}

/// The whole document around a page's content.
Component sitePage({
  required PageContext context,
  required PageMeta meta,
  required List<Component> content,
  List<Component> afterFooter = const [],

  /// Scripts that use what the page script sets up (`window.vinabikeCart`),
  /// so they run after it.
  List<Component> pageScripts = const [],

  /// Flutter's pages that scroll on their own (`_buildPageNoScroll`: the
  /// customer portal) show no store footer.
  bool showFooter = true,
}) {
  final s = context.shell;
  final roles = WebsiteThemeRoles.resolve(s.setting);
  final indexable = meta.indexable && !context.hidden;
  final menuColors = HeaderMenuColors.of(s, roles);
  final menus = s
      .menuFor(MenuLocation.header, mobile: false, storeUrl: context.storeUrl)
      .any((item) => item.children.any((c) => c.isVisible && c.showOnDesktop));
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
        _preload(storefrontLatinFontUrl(_fontFile(s.headingFont)), 'font'),
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
              onSurface: roles.onSurface.css,
              onSurfaceVariant: roles.onSurfaceVariant.css,
              outlineVariant: roles.outlineVariant.css,
              lightMenuSurface: menuColors.surfaceLight,
            ),
          ),
          if (menus) RawText(headerMenuCss(menuColors)),
          RawText(SiteFooter.wrapCss(s)),
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
      if (showFooter) SiteFooter(context),
      ...afterFooter,
      a(
        classes: 'chat-fab',
        href: '/cuenta/chats',
        attributes: {'aria-label': 'Conversar con ${s.storeName}'},
        [RawText(materialIcon(mdChat))],
      ),
      script(content: _bodyData(context)),
      script(content: storefrontScript),
      if (menus) script(content: headerMenuScript),
      ...pageScripts,
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
      'document.body.dataset.cartKey=${jsonEncode(key)};'
      'document.body.dataset.sbUrl=${jsonEncode(context.supabaseUrl)};'
      'document.body.dataset.sbKey=${jsonEncode(context.publishableKey)};';
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
    // The desktop menu as Flutter's header gets it (`forDesktop`); the
    // phone's sheet reads its own projection below.
    final items = s.menuFor(
      MenuLocation.header,
      mobile: false,
      storeUrl: page.storeUrl,
    );
    return header(
      classes: overlay ? 'top over' : 'top',
      attributes: page.pick('header', 'Encabezado'),
      [
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
              ul([for (final item in items) ?_menuItem(item)]),
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
            _accountMenu(),
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
            RawText(materialIcon(mdChevronRight, size: 20, classes: 'go')),
          ]),
          a(
            classes: 'sheet-item sheet-account',
            href: '/cuenta',
            attributes: {'hidden': ''},
            [
              RawText(materialIcon(mdPersonRounded)),
              span([.text('Mi Cuenta')]),
              RawText(materialIcon(mdChevronRight, size: 20, classes: 'go')),
            ],
          ),
          hr(),
          nav(
            attributes: {'aria-label': 'Menú del teléfono'},
            [
              for (final item in s.menuFor(
                MenuLocation.header,
                mobile: true,
                storeUrl: page.storeUrl,
              ))
                ?_sheetItem(item, depth: 0),
            ],
          ),
          hr(classes: 'sheet-account', attributes: {'hidden': ''}),
          button(
            classes: 'sheet-item sheet-out sheet-account',
            attributes: {
              'type': 'button',
              'data-act': 'sign-out',
              'hidden': '',
            },
            [
              RawText(materialIcon(mdLogoutRounded)),
              span([.text('Cerrar Sesión')]),
              RawText(materialIcon(mdChevronRight, size: 20, classes: 'go')),
            ],
          ),
        ]),
        // Run while the page is parsed, before anything under the header is
        // painted: clear at the top, solid after 50 px of scroll. Without
        // scripts the header stays solid, which is always readable.
        if (overlay) script(content: _overlayHeaderScript),
        // A customer seen on an earlier page shows as signed in from the first
        // paint; the page script confirms it (or reverts) with the base.
        script(content: _accountFirstPaintScript(page)),
      ],
    );
  }

  /// `CustomerAccountMenu` signed in: the initial, the first name over «Mi
  /// cuenta» and the portal's sections; the page script fills and opens it.
  Component _accountMenu() => div(
    classes: 'acct',
    attributes: {'data-acct': '', 'hidden': ''},
    [
      button(
        classes: 'acct-btn',
        attributes: {
          'type': 'button',
          'title': 'Mi cuenta',
          'aria-haspopup': 'menu',
          'aria-expanded': 'false',
        },
        [
          span(classes: 'acct-av', attributes: {'data-acct-initial': ''}, []),
          span(classes: 'acct-text', [
            b(attributes: {'data-acct-name': ''}, [.text('Mi cuenta')]),
            Component.element(
              tag: 'small',
              attributes: {'data-acct-sub': '', 'hidden': ''},
              children: [.text('Mi cuenta')],
            ),
          ]),
          RawText(materialIcon(mdArrowDropDown)),
        ],
      ),
      div(
        classes: 'acct-menu',
        attributes: {'role': 'menu', 'hidden': ''},
        [
          for (final (icon, label, href) in _accountItems) ...[
            a(
              classes: 'acct-item',
              href: href,
              attributes: {'role': 'menuitem'},
              [
                RawText(materialIcon(icon, size: 18)),
                span([.text(label)]),
              ],
            ),
            if (href == '/cuenta') hr(),
          ],
          hr(),
          button(
            classes: 'acct-item',
            attributes: {
              'type': 'button',
              'role': 'menuitem',
              'data-act': 'sign-out',
            },
            [
              RawText(materialIcon(mdLogout, size: 18)),
              span([.text('Cerrar sesión')]),
            ],
          ),
        ],
      ),
    ],
  );

  /// `CustomerAccountMenu._items`: the portal's sections, same words.
  static const _accountItems = [
    (mdHomeOutlined, 'Resumen', '/cuenta'),
    (mdReceiptLongOutlined, 'Pedidos', '/cuenta/pedidos'),
    (mdBuildOutlined, 'Taller', '/cuenta/servicios'),
    (mdPedalBikeOutlined, 'Bicicletas', '/cuenta/bicicletas'),
    (mdChatBubbleOutline, 'Soporte', '/cuenta/chats'),
    (mdPersonOutline, 'Perfil y seguridad', '/cuenta/perfil'),
    (mdLocationOnOutlined, 'Direcciones', '/cuenta/direcciones'),
  ];

  /// One row of the phone sheet, as `_buildMobileNavigationNode` draws it
  /// over the projected menu (`StorefrontShell.menuFor`): a leaf links, with
  /// «Solo esta categoría» under a category's own products; an item with
  /// children opens in place with «Ver todo …» first when it leads somewhere.
  Component? _sheetItem(WebsiteNavigation item, {required int depth}) {
    final href = page.shell.hrefFor(item);
    final indent = 'padding-left:${24 + depth * 14}px';
    if (item.children.isEmpty) {
      if (href == null) return null;
      final raw = Uri.tryParse(item.href?.trim() ?? '');
      final direct =
          raw != null &&
          WebsiteCatalogQuery.tryParse(raw)?.categoryScope ==
              WebsiteCatalogCategoryScope.direct;
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
          span([
            .text(item.label),
            if (direct) small([.text('Solo esta categoría')]),
          ]),
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
      for (final child in item.children) ?_sheetItem(child, depth: depth + 1),
    ]);
  }

  /// Flutter marks an item only on its own page (`matchedLocation == href`),
  /// never a parent of it: `/productos` is not current on a category.
  bool _current(String href) => Uri.parse(href).path == page.path;

  /// A desktop item: its link, or the wide panel or compact list of its
  /// children (`headerMenuItem`).
  Component? _menuItem(WebsiteNavigation item) {
    if (item.children.any((c) => c.isVisible && c.showOnDesktop)) {
      return headerMenuItem(page.shell, item);
    }
    final href = page.shell.hrefFor(item);
    if (href == null) return null;
    return li([
      a(
        href: href,
        attributes: {if (_current(href)) 'aria-current': 'page'},
        [.text(item.label)],
      ),
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
    final hasContact = _hasContact(s);
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
        li(classes: 'mail', [
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
    return footer(
      classes: 'foot',
      attributes: page.pick('footer', 'Pie de página'),
      [
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
      ],
    );
  }

  static bool _hasContact(StorefrontShell shell) =>
      shell.setting('contact_address').isNotEmpty ||
      shell.setting('contact_phone').isNotEmpty ||
      shell.setting('contact_email').isNotEmpty;

  /// Flutter lays the wide footer's columns out in a `Wrap` as wide as its
  /// widest run, centered, each run starting at its left edge: between 800
  /// and about 1000 px the «Contacto» column drops under the logo, not under
  /// the middle. A wrapping flex line cannot shrink to its widest run, so
  /// the width the `Wrap` takes is worked out here for every width the
  /// footer's inside can have (the 250 px brand, 200 px columns, 32 px
  /// apart, as Flutter wraps them) and set with container queries.
  static String wrapCss(StorefrontShell shell) {
    final widths = [
      250,
      for (final _ in _footerFor(shell, desktop: true)) 200,
      if (_hasContact(shell)) 200,
    ];
    const spacing = 32;
    int widest(int available) {
      var widest = 0;
      var run = 0;
      var count = 0;
      for (final width in widths) {
        if (count > 0 && run + spacing + width > available) {
          if (run > widest) widest = run;
          run = width;
          count = 1;
        } else {
          run = count == 0 ? width : run + spacing + width;
          count++;
        }
      }
      return run > widest ? run : widest;
    }

    // The footer's inside is at most 1200 px; each rule below holds until
    // the next narrower one takes over.
    final rules = StringBuffer(
      '.foot-wide{container:foot/inline-size}'
      '.foot-grid{justify-content:flex-start;width:${widest(1200)}px;'
      'max-width:100%;margin:0 auto}',
    );
    var current = widest(1200);
    for (var available = 1199; available >= 250; available--) {
      final width = widest(available);
      if (width == current) continue;
      rules.write(
        '@container foot (width<${available + 1}px){'
        '.foot-grid{width:${width}px}}',
      );
      current = width;
    }
    return rules.toString();
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
    'type': 'font/woff2',
    'crossorigin': '',
  },
);

/// The face of a heading family the page preloads (its Latin subset).
String _fontFile(String family) =>
    family == 'Oswald' ? 'Oswald-wght' : 'Barlow-SemiBold';

/// Where the store keeps a customer's session (`sb-<ref>-auth-token`, the
/// key `supabase_flutter` uses) and, per tab, the profile the header last
/// showed for it.
String accountSessionKey(String supabaseUrl) {
  final host = Uri.tryParse(supabaseUrl)?.host ?? '';
  return 'sb-${host.split('.').first}-auth-token';
}

String accountProfileKey(String tenantId) =>
    'vinabike.account-profile.v1.$tenantId';

/// Before the first paint: a session in this browser whose customer this tab
/// already read shows as signed in; the page script (`paintAccount`) draws
/// the same thing and confirms it with the base, or reverts it.
String _accountFirstPaintScript(PageContext page) =>
    '(function(h){try{'
    'var s=JSON.parse(localStorage.getItem(${jsonEncode(accountSessionKey(page.supabaseUrl))})||"null");'
    'var p=JSON.parse(sessionStorage.getItem(${jsonEncode(accountProfileKey(page.tenantId))})||"null");'
    'if(!(s&&s.user&&p&&p.uid===s.user.id))return;'
    'h.querySelector("[data-acct-initial]").textContent=p.initial;'
    'h.querySelector("[data-acct-name]").textContent=p.first||"Mi cuenta";'
    'h.querySelector("[data-acct-sub]").hidden=!p.first;'
    'h.querySelector("[data-acct]").hidden=false;'
    'h.querySelectorAll(".login,.sheet-login").forEach(function(e){e.hidden=true});'
    'h.querySelectorAll(".sheet-account").forEach(function(e){e.hidden=false})'
    '}catch(e){}})(document.currentScript.parentNode);';
