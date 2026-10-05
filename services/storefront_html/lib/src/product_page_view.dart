import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'product_card.dart';
import 'product_page_model.dart';
import 'site_layout.dart';

/// A product page. Server-only: no component is hydrated, so the page works
/// without JavaScript; the page script adds the cart, the photo switcher and
/// the measurement events.
Component productPageDocument(ProductPageModel page) => sitePage(
  context: page.page,
  meta: page.meta,
  content: [
    _Breadcrumbs(page),
    _ProductSection(page),
    _SpecSheet(page),
    _Related(page),
  ],
  afterFooter: [if (page.commerce.price > 0) _BuyBar(page)],
);

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
    final photos = page.photos;
    final whatsapp = page.shell.whatsappDigits;
    final address = page.shell.setting('contact_address');
    final shipping = page.cheapestShipping;
    final highlights = page.sheet.highlights;
    return section(
      classes: 'product wrap',
      attributes: {
        // What the page script needs for the cart and the events.
        'data-product-id': c.id,
        'data-item-id': c.sku.isNotEmpty ? c.sku : c.id,
        'data-item-name': c.title,
        'data-price': c.price.toStringAsFixed(0),
        'data-max': '${page.cartLimit}',
      },
      [
        div(classes: 'gallery', [
          if (photos.isNotEmpty)
            figure(classes: 'stage', [
              img(
                id: 'foto',
                src: photos.first.src,
                alt: c.title,
                width: 900,
                height: 900,
                attributes: {
                  'fetchpriority': 'high',
                  'decoding': 'async',
                  'srcset': ?photos.first.srcset,
                  'sizes': ?photos.first.sizes,
                },
              ),
            ]),
          if (photos.length > 1)
            ul(
              classes: 'thumbs',
              attributes: {'aria-label': 'Fotos'},
              [
                for (var i = 0; i < photos.length; i++)
                  li([
                    button(
                      attributes: {
                        'type': 'button',
                        'data-src': photos[i].src,
                        'aria-label': 'Foto ${i + 1} de ${photos.length}',
                        if (i == 0) 'aria-current': 'true',
                      },
                      [
                        img(
                          src: photos[i].src,
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
            p(classes: 'price', [.text(publicHeroPrice(c.price))]),
            if (c.price > 0)
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
          // Without JavaScript the form opens the cart; with it the page
          // script adds the product to the cart the Flutter store reads.
          form(
            classes: 'cart',
            action: '/carrito',
            method: FormMethod.get,
            [
              if (page.inStock && c.price > 0) ...[
                label(classes: 'qty', [
                  span(classes: 'sr', [.text('Cantidad')]),
                  Component.element(
                    tag: 'input',
                    attributes: {
                      'type': 'number',
                      'name': 'cantidad',
                      'min': '1',
                      if (page.cartLimit > 0) 'max': '${page.cartLimit}',
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
                  [.text(page.inStock ? 'Consultar precio' : 'Sin stock')],
                ),
            ],
          ),
          div(
            classes: 'cart-note',
            id: 'cart-note',
            attributes: {'hidden': '', 'role': 'status'},
            [
              span(attributes: {'data-note-text': ''}, []),
              a(href: '/carrito', [.text('Ver carrito')]),
            ],
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
                    'Chile continental, desde ${publicPrice(shipping.price)}, '
                    '${shipping.days} días hábiles. ',
                  ),
                  if (page.shell.pagePublication.isPublishedPath('/envios'))
                    a(href: '/envios', [.text('Tarifas')]),
                ]),
              ]),
            // The terms live on the editor's page; here they are only linked.
            if (page.shell.pagePublication.isPublishedPath('/devoluciones'))
              li([
                strong([.text('Cambios y devoluciones')]),
                span([
                  a(href: '/devoluciones', [
                    .text('Política de devoluciones'),
                  ]),
                ]),
              ]),
          ]),
        ]),
      ],
    );
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
      ul(classes: 'cards', [
        for (final item in page.related)
          ProductCard(commerce: item.commerce, path: item.path),
      ]),
    ]);
  }
}

class _BuyBar extends StatelessComponent {
  const _BuyBar(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final canBuy = page.inStock;
    return div(classes: 'buybar', [
      span([.text(publicPrice(page.commerce.price))]),
      button(
        classes: 'primary',
        attributes: {
          'type': 'button',
          if (canBuy) 'data-add-to-cart': '' else 'disabled': '',
        },
        [.text(canBuy ? 'Agregar al carrito' : 'Sin stock')],
      ),
    ]);
  }
}
