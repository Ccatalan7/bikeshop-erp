import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';

import 'material_icons.dart';
import 'product_card.dart';
import 'product_page_model.dart';
import 'site_layout.dart';

/// A product page, laid out like Flutter's `product_detail_page.dart`:
/// breadcrumb, the photo stage beside the buy column, the technical sheet
/// with its help card, and the related products. Server-only: no component
/// is hydrated, so the page works without JavaScript; the page script adds
/// the cart, the quantity buttons, the photo switcher and the measurement
/// events.
Component productPageDocument(ProductPageModel page) => sitePage(
  context: page.page,
  meta: page.meta,
  content: [
    div(classes: 'pdp', [_Breadcrumbs(page), _ProductSection(page)]),
    _SpecSheet(page),
    _Related(page),
  ],
);

class _Breadcrumbs extends StatelessComponent {
  const _Breadcrumbs(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    return nav(
      classes: 'crumbs',
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
                span(classes: 'plain', [.text(crumb.name)]),
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
    final highlights = page.sheet.highlights;
    final canBuy = page.inStock && c.price > 0;
    return section(
      classes: 'product',
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
          figure(classes: 'stage', [
            if (photos.isNotEmpty)
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
              )
            else
              RawText(materialIcon(mdPedalBikeOutlined, size: 100)),
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
                          width: 92,
                          height: 92,
                        ),
                      ],
                    ),
                  ]),
              ],
            ),
        ]),
        div(classes: 'buy', [
          h1([.text(c.title)]),
          hr(),
          p(classes: 'price', [.text(publicHeroPrice(c.price))]),
          p(classes: 'tax', [.text('Precio final con IVA incluido')]),
          if (highlights.isNotEmpty) ...[
            _Highlights(highlights),
            a(classes: 'to-sheet', href: '#ficha', [
              RawText(materialIcon(mdSouthRounded, size: 16)),
              .text('Ver ficha técnica completa'),
            ]),
          ],
          hr(),
          div(classes: 'stock-row', [
            p(classes: page.inStock ? 'stock ok' : 'stock out', [
              span(attributes: {'aria-hidden': 'true'}, []),
              .text(page.inStock ? 'En stock' : 'Agotado'),
            ]),
            if (c.sku.trim().isNotEmpty)
              p(classes: 'sku', [.text('SKU: ${c.sku.trim()}')]),
          ]),
          p(classes: 'checked', [
            RawText(materialIcon(mdCheckCircleOutline, size: 15)),
            .text('Precio y disponibilidad actualizados.'),
          ]),
          if (canBuy)
            // Without JavaScript the form opens the cart; with it the page
            // script adds the product to the cart the Flutter store reads.
            form(classes: 'cart', action: '/carrito', method: FormMethod.get, [
              div(classes: 'qty', [
                button(
                  classes: 'qty-step',
                  attributes: {
                    'type': 'button',
                    'data-step': '-1',
                    'aria-label': 'Quitar una unidad',
                  },
                  [RawText(materialIcon(mdRemove, size: 16))],
                ),
                label([
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
                  classes: 'qty-step',
                  attributes: {
                    'type': 'button',
                    'data-step': '1',
                    'aria-label': 'Agregar una unidad',
                  },
                  [RawText(materialIcon(mdAdd, size: 16))],
                ),
              ]),
              button(
                classes: 'add',
                attributes: {'type': 'submit'},
                [
                  RawText(
                      materialIcon(mdCartOutlined, size: 17, classes: 'idle'),
                    ),
                    RawText(
                      materialIcon(
                        mdCheckCircleOutline,
                        size: 17,
                        classes: 'done',
                      ),
                    ),
                  span(
                    attributes: {'data-add-label': ''},
                    [.text('Agregar al carrito')],
                  ),
                ],
              ),
              button(
                classes: 'buy-now',
                attributes: {'type': 'submit', 'data-buy-now': ''},
                [.text('Comprar ahora')],
              ),
            ])
          else
            p(classes: 'unavailable', [
              .text(page.inStock ? 'CONSULTAR PRECIO' : 'NO DISPONIBLE'),
            ]),
          div(
            classes: 'cart-note',
            id: 'cart-note',
            attributes: {'hidden': '', 'role': 'status'},
            [
              RawText(materialIcon(mdShoppingBagOutlined, size: 16)),
              span(attributes: {'data-note-text': ''}, []),
              a(href: '/carrito', [.text('Ver carrito')]),
            ],
          ),
          _Promises(page),
        ]),
      ],
    );
  }
}

/// What decides the purchase, next to the price: one object with up to four
/// cells, value first; an odd last cell takes the whole row.
class _Highlights extends StatelessComponent {
  const _Highlights(this.items);

  final List<PublicSpecItem> items;

  @override
  Component build(BuildContext context) => dl(classes: 'highlights', [
    for (var i = 0; i < items.length; i++)
      div(
        classes: i == items.length - 1 && items.length.isOdd ? 'wide' : null,
        [
          // Value first on screen, label first in the markup.
          dt([.text(items[i].label)]),
          dd([.text(items[i].value)]),
        ],
      ),
  ]);
}

/// Pickup and delivery, as Flutter's `_buildFulfilmentPromises` says them:
/// the owner's own promises, the store's address, and the cheapest shipping
/// rate the checkout would charge.
class _Promises extends StatelessComponent {
  const _Promises(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final shell = page.shell;
    final shippingTitle = shell.setting('shipping_promise_title');
    final shippingDetail = shell.setting('shipping_promise_detail');
    final pickup = shell
        .setting('pickup_promise_detail', shell.setting('contact_address'))
        .replaceAll('\n', ', ');
    final shipping = page.cheapestShipping;
    final tiles = <(String, String, String)>[
      if (shippingTitle.isNotEmpty || shippingDetail.isNotEmpty)
        (
          shippingTitle.isEmpty ? 'Despacho' : shippingTitle,
          shippingDetail,
          mdLocalShippingOutlined,
        )
      else if (shipping != null)
        (
          'Despacho a domicilio',
          'Chile continental, desde ${publicPrice(shipping.price)}, '
              '${shipping.days} días hábiles.',
          mdLocalShippingOutlined,
        ),
      if (pickup.isNotEmpty) ('Retiro en tienda', pickup, mdStorefrontOutlined),
    ];
    if (tiles.isEmpty) return const Component.empty();
    return ul(classes: 'promises', [
      for (final (title, detail, icon) in tiles)
        li([
          span(classes: 'dot', attributes: {'aria-hidden': 'true'}, []),
          div([
            strong([.text(title)]),
            if (detail.isNotEmpty) span([.text(detail)]),
          ]),
          RawText(materialIcon(icon, size: 18)),
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
    final technical = page.sheet.hasTechnicalData;
    final whatsapp = page.shell.whatsappDigits;
    final c = page.commerce;
    final help = aside(classes: 'help', [
      RawText(
        materialIcon(
          technical ? mdPedalBikeOutlined : mdChatBubbleOutlineRounded,
          size: 26,
        ),
      ),
      p(classes: 'help-title', [
        .text(technical ? '¿Le sirve a tu bicicleta?' : '¿Tienes una duda?'),
      ]),
      p([
        .text(
          technical
              ? 'Cuéntanos qué bicicleta tienes y te ayudamos a elegir la '
                    'medida correcta antes de comprar.'
              : 'Escríbenos y te ayudamos con lo que necesites saber de este '
                    'producto antes de comprar.',
        ),
      ]),
      if (whatsapp.isNotEmpty)
        a(
          classes: 'ask',
          href:
              'https://wa.me/$whatsapp?text=${Uri.encodeComponent('Hola, quiero consultar por ${c.title} (${c.sku}): ${page.productUrl}')}',
          attributes: {'rel': 'noopener', 'target': '_blank'},
          [
            RawText(materialIcon(mdChatBubbleOutlineRounded, size: 17)),
            .text('Preguntar por WhatsApp'),
          ],
        ),
    ]);
    final hasContent = groups.isNotEmpty || paragraphs.isNotEmpty;
    return section(classes: 'details', id: 'ficha', [
      div(classes: 'details-in', [
        h2(classes: 'section-title accent', [
          .text(technical ? 'Ficha técnica' : 'Detalles del producto'),
        ]),
        div(classes: hasContent ? 'sheet-row' : 'sheet-row only-help', [
          if (hasContent)
            div(classes: 'sheet', [
              if (paragraphs.isNotEmpty) ...[
                h3([.text('Descripción')]),
                div(classes: 'description', [
                  for (final paragraph in paragraphs) p([.text(paragraph)]),
                ]),
              ],
              for (final group in groups)
                section(classes: 'group', [
                  h3([.text(group.title)]),
                  dl([
                    for (final item in group.items)
                      div([
                        dt([.text(item.label)]),
                        dd([
                          span(classes: 'value', _lines(item.value)),
                          if (item.detail case final detail?)
                            span(classes: 'detail', [.text(detail)]),
                        ]),
                        if (item.hint case final hint?)
                          p(classes: 'hint', [.text(hint)]),
                      ]),
                  ]),
                ]),
              if (technical)
                p(classes: 'origin', [
                  .text(
                    'Ficha preparada por nuestro equipo con información del '
                    'fabricante y del proveedor.',
                  ),
                ]),
            ]),
          help,
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
    return section(classes: 'related', [
      h2(classes: 'section-title', [.text('Productos relacionados')]),
      div(classes: 'related-box', [
        ul(classes: 'related-cards', [
          for (final item in page.related)
            ProductCard(commerce: item.commerce, path: item.path),
        ]),
      ]),
    ]);
  }
}
