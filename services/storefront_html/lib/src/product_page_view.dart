import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_color_value.dart';
import 'package:vinabike_public_core/public_store/models/public_business_hours.dart';
import 'package:vinabike_public_core/public_store/models/storefront_logo_source.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'product_page_model.dart';
import 'storefront_css.dart';

/// The whole product page as a Jaspr document. Server-only: no component is
/// hydrated, so the page works without JavaScript; the two small scripts
/// (photo switcher, cart note) only add to it.
class ProductPageDocument extends StatelessComponent {
  const ProductPageDocument(this.page, {super.key});

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final c = page.commerce;
    final s = page.shell;
    final images = c.imageUrls;
    final description = page.seo.description;
    return Document(
      lang: 'es-CL',
      // No <base>: it would turn the «#ficha» anchor into a link to the home.
      base: null,
      title: page.seo.title.isNotEmpty ? page.seo.title : c.title,
      meta: {
        'description': description,
        // Phase 0 lives on a hidden route next to the Flutter page it
        // mirrors; only the Flutter page is indexed until phase 1.
        'robots': 'noindex',
      },
      head: [
        link(rel: 'canonical', href: page.productUrl),
        _property('og:type', 'product'),
        _property('og:title', c.title),
        _property('og:description', description),
        if (images.isNotEmpty) _property('og:image', images.first),
        Component.element(
          tag: 'link',
          attributes: {
            'rel': 'preload',
            'href': '/assets/assets/fonts/Oswald-wght.ttf',
            'as': 'font',
            'type': 'font/ttf',
            'crossorigin': '',
          },
        ),
        if (images.isNotEmpty)
          Component.element(
            tag: 'link',
            attributes: {
              'rel': 'preload',
              'as': 'image',
              'href': images.first,
              'fetchpriority': 'high',
            },
          ),
        Component.element(
          tag: 'style',
          children: [
            RawText(
              storefrontCss(
                primary: _hex(s.settings['theme_primary_color'], '#123f68'),
                accent: _hex(s.settings['theme_accent_color'], '#ff7000'),
              ),
            ),
          ],
        ),
        if (page.structuredData case final data?)
          // Escaped by the shared encoder: no «<» can close the script.
          script(
            attributes: {'type': 'application/ld+json'},
            content: encodeStructuredDataForHtml(data),
          ),
      ],
      body: Component.fragment([
        a(classes: 'skip', href: '#contenido', [.text('Ir al contenido')]),
        SiteHeader(page),
        main_(id: 'contenido', [
          _Breadcrumbs(page),
          _ProductSection(page),
          _SpecSheet(page),
          _Related(page),
        ]),
        SiteFooter(page),
        if (c.price > 0) _BuyBar(page),
        script(content: _pageScript),
      ]),
    );
  }
}

class SiteHeader extends StatelessComponent {
  const SiteHeader(this.page, {super.key});

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final s = page.shell;
    final logo = storefrontFirstLogoSource(
      configuredUrl: s.settings['logo_url'] ?? '',
      tenantId: page.tenantId,
    );
    return header(classes: 'top', [
      div(classes: 'wrap bar', [
        a(classes: 'logo', href: '/', [
          // No logo of its own: the store writes its name, as in Flutter.
          if (logo.isEmpty)
            span(classes: 'logo-name', [.text(page.storeName)])
          else
            img(
              src: logo.startsWith('http') ? logo : '/$logo',
              alt: page.storeName,
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
          attributes: {'type': 'checkbox'},
        ),
        Component.element(
          tag: 'label',
          classes: 'menu-button',
          attributes: {'for': 'menu-toggle', 'aria-label': 'Menú'},
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
        ]),
        div(classes: 'tools', [
          a(
            href: '/productos',
            attributes: {'aria-label': 'Buscar'},
            [const RawText(_searchIcon)],
          ),
          a(
            href: '/carrito',
            attributes: {'aria-label': 'Carrito'},
            [const RawText(_cartIcon)],
          ),
          a(classes: 'login', href: '/cuenta/login', [.text('Iniciar sesión')]),
        ]),
      ]),
    ]);
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
            a(href: childHref, [.text(child.label)]),
          ]),
    ];
    if (links.isEmpty) {
      return li(classes: _deviceClasses(item), [
        a(href: href, [.text(item.label)]),
      ]);
    }
    return li(classes: _deviceClasses(item, 'has-sub'), [
      a(href: href, [.text(item.label)]),
      ul(classes: 'sub', links),
    ]);
  }
}

class _Breadcrumbs extends StatelessComponent {
  const _Breadcrumbs(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    return nav(
      classes: 'crumbs wrap',
      attributes: {'aria-label': 'Estás en'},
      [
        ol([
          li([
            a(href: '/', [.text('Inicio')]),
          ]),
          li([
            a(href: '/productos', [.text('Productos')]),
          ]),
          for (final crumb in page.trail)
            li([
              if (crumb.path case final path?)
                a(href: path, [.text(crumb.name)])
              else
                span([.text(crumb.name)]),
            ]),
          li(
            attributes: {'aria-current': 'page'},
            [
              span([.text(page.commerce.title)]),
            ],
          ),
        ]),
      ],
    );
  }
}

class _ProductSection extends StatelessComponent {
  const _ProductSection(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final c = page.commerce;
    final images = c.imageUrls;
    final settings = page.shell.settings;
    final whatsapp = (settings['whatsapp'] ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final address = settings['contact_address'] ?? '';
    final shipping = page.cheapestShipping;
    final highlights = page.sheet.highlights;
    return section(classes: 'product wrap', [
      div(classes: 'gallery', [
        if (images.isNotEmpty)
          figure(classes: 'stage', [
            img(
              id: 'foto',
              src: images.first,
              alt: c.title,
              width: 900,
              height: 900,
              attributes: {'fetchpriority': 'high', 'decoding': 'async'},
            ),
          ]),
        if (images.length > 1)
          ul(
            classes: 'thumbs',
            attributes: {'aria-label': 'Fotos'},
            [
              for (var i = 0; i < images.length; i++)
                li([
                  button(
                    attributes: {
                      'type': 'button',
                      'data-src': images[i],
                      'aria-label': 'Foto ${i + 1} de ${images.length}',
                      if (i == 0) 'aria-current': 'true',
                    },
                    [
                      img(
                        src: images[i],
                        alt: '',
                        loading: MediaLoading.lazy,
                        width: 96,
                        height: 96,
                      ),
                    ],
                  ),
                ]),
            ],
          ),
      ]),
      div(classes: 'buy', [
        if (c.brand.isNotEmpty) p(classes: 'brand', [.text(c.brand)]),
        h1([.text(c.title)]),
        p(classes: 'ids', [
          if (page.model case final model?) span([.text('Modelo $model')]),
          span([.text('Código ${c.sku}')]),
        ]),
        div(classes: 'price-row', [
          p(classes: 'price', [
            .text(c.price > 0 ? _price(c.price) : 'Consultar'),
          ]),
          p(classes: 'tax', [.text('Precio final con IVA incluido')]),
        ]),
        if (page.inStock)
          p(classes: 'stock ok', [
            span(attributes: {'aria-hidden': 'true'}, []),
            .text('Disponible'),
          ])
        else
          p(classes: 'stock out', [
            span(attributes: {'aria-hidden': 'true'}, []),
            .text('Agotado'),
          ]),
        if (highlights.isNotEmpty) ...[
          dl(classes: 'highlights', [
            for (final item in highlights)
              div([
                dt([.text(item.label)]),
                dd([.text(item.value)]),
              ]),
          ]),
          a(classes: 'to-sheet', href: '#ficha', [
            .text('Ver ficha técnica completa'),
          ]),
        ],
        form(
          classes: 'cart',
          attributes: {'onsubmit': 'return vbCartNote(event)'},
          [
            if (page.inStock) ...[
              label(classes: 'qty', [
                span(classes: 'sr', [.text('Cantidad')]),
                Component.element(
                  tag: 'input',
                  attributes: {
                    'type': 'number',
                    'name': 'cantidad',
                    'min': '1',
                    'value': '1',
                    'inputmode': 'numeric',
                  },
                ),
              ]),
              button(
                classes: 'primary',
                attributes: {'type': 'submit'},
                [.text('Agregar al carrito')],
              ),
            ] else
              button(
                classes: 'primary',
                attributes: {'type': 'button', 'disabled': ''},
                [.text('Sin stock')],
              ),
          ],
        ),
        // Phase 1 writes the same cart the Flutter store reads; until then
        // this hidden-route page says so instead of pretending.
        p(
          classes: 'cart-note',
          id: 'cart-note',
          attributes: {'hidden': ''},
          [.text('El carrito de esta página se conecta en la fase 1.')],
        ),
        if (whatsapp.isNotEmpty)
          a(
            classes: 'secondary',
            href:
                'https://wa.me/$whatsapp?text=${Uri.encodeComponent('Hola, quiero consultar por ${c.title} (${c.sku}): ${page.productUrl}')}',
            attributes: {'rel': 'noopener'},
            [.text('Preguntar por WhatsApp')],
          ),
        ul(classes: 'promises', [
          if (address.isNotEmpty)
            li([
              strong([.text('Retiro gratis en tienda')]),
              span([.text(address)]),
            ]),
          if (shipping != null)
            li([
              strong([.text('Despacho a domicilio')]),
              span([
                .text(
                  'Chile continental, desde ${_price(shipping.price)}, '
                  '${shipping.days} días hábiles. ',
                ),
                a(href: '/envios', [.text('Tarifas')]),
              ]),
            ]),
          // The terms live on the editor's page; here they are only linked.
          li([
            strong([.text('Cambios y devoluciones')]),
            span([
              a(href: '/devoluciones', [.text('Política de devoluciones')]),
            ]),
          ]),
        ]),
      ]),
    ]);
  }
}

class _SpecSheet extends StatelessComponent {
  const _SpecSheet(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final groups = page.sheet.groups;
    final paragraphs = page.descriptionParagraphs;
    if (groups.isEmpty && paragraphs.isEmpty) return const Component.empty();
    return section(classes: 'details wrap', id: 'ficha', [
      h2([
        .text(
          page.sheet.hasTechnicalData
              ? 'Ficha técnica'
              : 'Detalles del producto',
        ),
      ]),
      if (paragraphs.isNotEmpty)
        div(classes: 'description', [
          for (final paragraph in paragraphs) p([.text(paragraph)]),
        ]),
      if (groups.isNotEmpty)
        div(classes: 'sheet', [
          for (final group in groups)
            section(classes: 'group', [
              h3([.text(group.title)]),
              dl([
                for (final item in group.items)
                  div([
                    dt([
                      .text(item.label),
                      if (item.hint case final hint?) small([.text(hint)]),
                    ]),
                    dd([
                      ..._lines(item.value),
                      if (item.detail case final detail?)
                        span(classes: 'detail', [.text(' $detail')]),
                    ]),
                  ]),
              ]),
            ]),
        ]),
    ]);
  }

  static List<Component> _lines(String value) {
    final lines = value.split('\n');
    return [
      for (var i = 0; i < lines.length; i++) ...[
        if (i > 0) const Component.element(tag: 'br'),
        .text(lines[i]),
      ],
    ];
  }
}

class _Related extends StatelessComponent {
  const _Related(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    if (page.related.isEmpty) return const Component.empty();
    final last = page.trail.isEmpty ? null : page.trail.last;
    return section(classes: 'related wrap', [
      div(classes: 'related-head', [
        h2([.text('Más en ${last?.name ?? 'esta categoría'}')]),
        if (last?.path case final path?) a(href: path, [.text('Ver todo')]),
      ]),
      ul([
        for (final item in page.related)
          li([
            a(href: item.path, [
              img(
                src: item.commerce.imageUrls.first,
                alt: '',
                loading: MediaLoading.lazy,
                width: 320,
                height: 320,
              ),
              span(classes: 'name', [.text(item.commerce.title)]),
              span(classes: 'p', [.text(_price(item.commerce.price))]),
            ]),
          ]),
      ]),
    ]);
  }
}

class SiteFooter extends StatelessComponent {
  const SiteFooter(this.page, {super.key});

  final ProductPageModel page;

  static const _dayNames = {
    'MONDAY': 'Lunes',
    'TUESDAY': 'Martes',
    'WEDNESDAY': 'Miércoles',
    'THURSDAY': 'Jueves',
    'FRIDAY': 'Viernes',
    'SATURDAY': 'Sábado',
    'SUNDAY': 'Domingo',
  };

  @override
  Component build(BuildContext context) {
    final shell = page.shell;
    final s = shell.settings;
    final hours = parsePublicBusinessHours(s['business_hours_json'] ?? '');
    final spans = <String, List<String>>{};
    for (final day in publicBusinessDays) {
      final span = hours
          .where((h) => h.day == day)
          .map((h) => '${h.opens}–${h.closes}')
          .join(' / ');
      spans.putIfAbsent(span.isEmpty ? 'Cerrado' : span, () => []).add(day);
    }
    final phone = s['contact_phone'] ?? '';
    final email = s['contact_email'] ?? '';
    return footer(classes: 'foot', [
      div(classes: 'wrap cols', [
        div([
          p(classes: 'foot-name', [.text(page.storeName)]),
          p([.text(s['contact_address'] ?? '')]),
          if (phone.isNotEmpty)
            p([
              a(href: 'tel:${phone.replaceAll(' ', '')}', [.text(phone)]),
            ]),
          if (email.isNotEmpty)
            p([
              a(href: 'mailto:$email', [.text(email)]),
            ]),
        ]),
        div([
          p(classes: 'foot-title', [.text('Horario')]),
          dl(classes: 'hours', [
            for (final entry in spans.entries)
              div([
                dt([.text(_daysLabel(entry.value))]),
                dd([.text(entry.key)]),
              ]),
          ]),
        ]),
        ..._footerColumns(shell),
      ]),
      p(classes: 'wrap legal', [.text(s['business_legal_name'] ?? '')]),
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

  static String _daysLabel(List<String> days) {
    final names = [for (final day in days) _dayNames[day]!];
    return names.length > 2
        ? '${names.first} a ${names.last}'
        : names.join(' y ');
  }
}

class _FooterColumn {
  const _FooterColumn(this.title, this.links);
  final String title;
  final List<WebsiteNavigation> links;
}

class _BuyBar extends StatelessComponent {
  const _BuyBar(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    return div(classes: 'buybar', [
      span([.text(_price(page.commerce.price))]),
      button(
        classes: 'primary',
        attributes: {
          'type': 'button',
          if (page.inStock) 'onclick': 'vbCartNote(event)' else 'disabled': '',
        },
        [.text(page.inStock ? 'Agregar al carrito' : 'Sin stock')],
      ),
    ]);
  }
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

String _hex(String? raw, String fallback) {
  final argb = parseWebsiteThemeColorValue(raw ?? '');
  if (argb == null) return fallback;
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

String _price(double value) =>
    ChileanUtils.formatCurrency(value).replaceFirst(r'$ ', r'$');

const _pageScript = '''
function vbCartNote(e){e.preventDefault();var n=document.getElementById('cart-note');if(n)n.hidden=false;return false}
document.querySelectorAll('.thumbs button').forEach(function(t){t.addEventListener('click',function(){
var f=document.getElementById('foto');f.src=t.dataset.src;
document.querySelectorAll('.thumbs button').forEach(function(o){o.removeAttribute('aria-current')});
t.setAttribute('aria-current','true')})});
''';

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
