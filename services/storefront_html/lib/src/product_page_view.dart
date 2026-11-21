import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';
import 'package:vinabike_public_core/modules/website/models/website_product_page_template.dart';
import 'package:vinabike_public_core/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';

import 'material_icons.dart';
import 'quote_page_model.dart';
import 'quote_page_script.dart';
import 'product_card.dart';
import 'product_page_model.dart';
import 'product_question_view.dart';
import 'site_layout.dart';

/// A product page, laid out like Flutter's `product_detail_page.dart`:
/// the breadcrumb in its own row, then the photo stage edge to edge beside
/// the buy column (as Specialized and Canyon, 2026-10-24), the technical sheet
/// with its help card, and the related products. Server-only: no component
/// is hydrated, so the page works without JavaScript; the page script adds
/// the cart, the quantity buttons, the photo switcher and the measurement
/// events.
Component productPageDocument(ProductPageModel page) => sitePage(
  context: page.page,
  meta: page.meta,
  content: [
    _Breadcrumbs(page),
    div(classes: 'pdp', [_ProductSection(page)]),
    _Fits(page),
    _SpecSheet(page),
    _Related(page),
  ],
  // «Pregunta por este producto»: the buy column's box and the help card
  // open it.
  afterFooter: [if (page.asksQuestions) productQuestionSheet(page)],
  pageScripts: [
    if (page.asksQuestions) script(content: productQuestionScript),
    if (!page.isService) script(content: quoteAddScript),
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
            if (page.isService)
              a(href: '/servicios', [.text('Servicios')])
            else
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
    final template = page.template;
    final highlights = template.showHighlights
        ? page.sheet.highlights
        : const <PublicSpecItem>[];
    // What the supplier brings is bought like what is on the shelf
    // (20261120210000).
    final canBuy = page.purchasable && c.price > 0;
    final lede = page.lede;
    final cap = [
      if (c.sku.trim().isNotEmpty) 'SKU ${c.sku.trim()}',
      if (canBuy && page.cartLimit > 0 && page.cartLimit <= 10)
        'Hasta ${page.cartLimit} por compra',
    ].join(' · ');
    return section(
      classes: template.photoSide == WebsiteProductPhotoSide.right
          ? 'product photos-right'
          : 'product',
      attributes: {
        // What the page script needs for the cart and the events.
        'data-product-id': c.id,
        'data-item-id': c.sku.isNotEmpty ? c.sku : c.id,
        'data-item-name': c.title,
        'data-price': c.price.toStringAsFixed(0),
        'data-max': '${page.cartLimit}',
        ...page.page.pick('product-page:buy', 'Foto y compra'),
      },
      [
        div(classes: 'gallery', [
          figure(classes: 'stage', [
            if (photos.isNotEmpty)
              // Every photo in one row that slides sideways: a finger on the
              // phone, a trackpad, or the thumbnails below, which follow the
              // photo in view (2026-11-20, the owner: «on mobile, give the
              // ability to swipe … across the images of the product»).
              div(
                classes: 'slides',
                attributes: {
                  if (photos.length > 1) ...{
                    'tabindex': '0',
                    'aria-label': 'Fotos de ${c.title}',
                  },
                },
                [
                  for (var i = 0; i < photos.length; i++)
                    div(classes: 'slide', [
                      img(
                        id: i == 0 ? 'foto' : null,
                        src: photos[i].src,
                        alt: i == 0
                            ? c.title
                            : '${c.title}, foto ${i + 1} de ${photos.length}',
                        width: 900,
                        height: 900,
                        // The first is the page's main image; the others
                        // wait for the page, and the script asks for them
                        // once it has loaded.
                        loading: i == 0 ? null : MediaLoading.lazy,
                        attributes: {
                          if (i == 0) 'fetchpriority': 'high',
                          'decoding': 'async',
                          'srcset': ?photos[i].srcset,
                          'sizes': ?photos[i].sizes,
                        },
                      ),
                    ]),
                ],
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
          // On the phone the thumbnails give way to dots under the photo, as
          // in the approved canvas (Ficha con tallas, version 42): they say
          // there is more to swipe and which photo is in view.
          if (photos.length > 1)
            div(classes: 'dots', [
              for (var i = 0; i < photos.length; i++)
                button(
                  attributes: {
                    'type': 'button',
                    'aria-label': 'Foto ${i + 1} de ${photos.length}',
                    if (i == 0) 'aria-current': 'true',
                  },
                  [span([])],
                ),
            ]),
        ]),
        div(classes: 'buy', [
          // The brand above the title, as international brands' pages do
          // (2026-11-20): one quiet line, then the name.
          if (page.brandEyebrow.isNotEmpty)
            p(classes: 'brand-line', [.text(page.brandEyebrow)]),
          h1([.text(page.displayTitle)]),
          if (lede != null && !page.isService)
            p(classes: 'lede', [.text(lede)]),
          p(classes: 'price-row', [
            span(classes: 'price', [
              .text(catalogHeroPriceLabel(c.price, mode: page.priceMode)),
            ]),
            if (template.taxNote.trim().isNotEmpty)
              span(classes: 'tax', [.text(template.taxNote.trim())]),
          ]),
          if (highlights.isNotEmpty) ...[
            _Highlights(highlights),
            a(classes: 'to-sheet', href: '#ficha', [
              RawText(materialIcon(mdSouthRounded, size: 16)),
              .text('Ver ficha técnica completa'),
            ]),
          ],
          hr(),
          if (page.variantAxes.isNotEmpty) _VariantPicker(page),
          if (page.isService)
            _ServiceBooking(page)
          else ...[
            // Stock, dispatch and pickup in one box of three lines
            // (owner, 2026-11-20: «ordenar sin borrar»).
            _Availability(page),
            if (canBuy) ...[
              // Without JavaScript the form opens the cart; with it the page
              // script adds the product to the cart the Flutter store reads.
              form(
                classes: 'cart',
                action: '/carrito',
                method: FormMethod.get,
                [
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
                        [.text(template.resolvedAddToCartLabel)],
                      ),
                    ],
                  ),
                  if (template.showBuyNow)
                    button(
                      classes: 'buy-now',
                      attributes: {'type': 'submit', 'data-buy-now': ''},
                      [.text(template.resolvedBuyNowLabel)],
                    ),
                ],
              ),
              if (template.showStickyBuyBar)
                // On a phone, fixed at the bottom while the form's button is
                // out of sight; its button submits that form.
                div(
                  classes: 'buybar',
                  attributes: {'data-buybar': '', 'hidden': ''},
                  [
                    div(classes: 'buybar-info', [
                      span(classes: 'buybar-name', [.text(c.title)]),
                      span(classes: 'buybar-price', [
                        .text(
                          catalogHeroPriceLabel(c.price, mode: page.priceMode),
                        ),
                      ]),
                    ]),
                    button(
                      classes: 'buybar-add',
                      attributes: {'type': 'button', 'data-buybar-add': ''},
                      [
                        RawText(
                          materialIcon(
                            mdCartOutlined,
                            size: 17,
                            classes: 'idle',
                          ),
                        ),
                        RawText(
                          materialIcon(
                            mdCheckCircleOutline,
                            size: 17,
                            classes: 'done',
                          ),
                        ),
                        span(
                          attributes: {'data-buybar-label': ''},
                          [.text(template.resolvedAddToCartLabel)],
                        ),
                      ],
                    ),
                  ],
                ),
            ] else if (page.quotable && c.price > 0)
              // Sold out is not the end when the shop quotes it: on order,
              // «Se cotiza» on its form or a brand it quotes without stock
              // (20261103070000); the quote page confirms it.
              const _QuoteBox()
            else
              p(classes: 'unavailable', [
                .text(page.inStock ? 'CONSULTAR PRECIO' : 'NO DISPONIBLE'),
              ]),
            // The SKU and how many one purchase takes, one small line under
            // the buttons instead of a row of their own.
            if (cap.isNotEmpty) p(classes: 'buy-cap', [.text(cap)]),
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
            div(
              classes: 'cart-note',
              attributes: {
                'data-quote-note': '',
                'hidden': '',
                'role': 'status',
              },
              [
                RawText(materialIcon(mdShoppingBagOutlined, size: 16)),
                span(attributes: {'data-quote-note-text': ''}, []),
                a(href: quotePagePath, [.text('Ver cotización')]),
              ],
            ),
            // With a button to buy, the question and the quote are two
            // links, not two boxes (owner, 2026-11-20); without one, asking
            // is what the visitor can do, and its box leads.
            if (canBuy)
              div(classes: 'buy-links', [
                if (template.showAsk)
                  productQuestionLink(page, sizes: page.hasSizes),
                button(
                  classes: 'quote-link',
                  attributes: {'type': 'button', 'data-quote-add': ''},
                  [.text('Agregar a una cotización')],
                ),
              ])
            else if (template.showAsk)
              productQuestionBox(page),
            _Trust(page),
          ],
        ]),
      ],
    );
  }
}

/// The model's selector (20261120230000): the colors as photo tiles and the
/// sizes as buttons, each a link to its own page; a size this color does not
/// come in, or that cannot be bought now, is crossed out.
class _VariantPicker extends StatelessComponent {
  const _VariantPicker(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    return div(classes: 'variant-picker', [
      for (final axis in page.variantAxes)
        div(
          classes: 'pick',
          attributes: {'role': 'group', 'aria-label': axis.name},
          [
            p(classes: 'pick-head', [
              .text('${axis.name}: '),
              strong([.text(axis.current)]),
            ]),
            ul(classes: axis.swatches ? 'swatch-list' : 'size-list', [
              for (final choice in axis.choices) li([_choice(axis, choice)]),
            ]),
          ],
        ),
    ]);
  }

  Component _choice(VariantAxis axis, VariantChoice choice) {
    final classes = [
      axis.swatches ? 'swatch-opt' : 'size-opt',
      if (choice.current) 'on',
      if (choice.soldOut && !choice.current) 'off',
    ].join(' ');
    final label = [
      '${axis.name} ${choice.label}',
      if (choice.current) 'elegido',
      if (choice.soldOut && choice.path == null && !choice.current)
        'no viene en esta combinación'
      else if (choice.soldOut && !choice.current)
        'agotado',
    ].join(', ');
    final content = axis.swatches
        ? [
            img(
              src: choice.image!,
              alt: '',
              width: 58,
              height: 58,
              loading: MediaLoading.lazy,
            ),
          ]
        : [Component.text(choice.label)];
    if (choice.current) {
      return span(
        classes: classes,
        attributes: {
          'aria-current': 'true',
          'aria-label': label,
          'title': choice.label,
        },
        content,
      );
    }
    final path = choice.path;
    if (path == null) {
      return span(
        classes: classes,
        attributes: {
          'aria-disabled': 'true',
          'aria-label': label,
          'title': choice.label,
        },
        content,
      );
    }
    return a(
      classes: classes,
      href: path,
      attributes: {'aria-label': label, 'title': choice.label},
      content,
    );
  }
}

/// Stock, dispatch and pickup in one box of three lines with their icons:
/// what used to be a stock row, a «Precio y disponibilidad actualizados»
/// line and two promise tiles (owner, 2026-11-20).
class _Availability extends StatelessComponent {
  const _Availability(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final shell = page.shell;
    final lines = <(String, String, String?)>[
      (
        page.purchasable ? mdCheckCircleOutline : mdInfoOutline,
        page.stockWord,
        page.purchasable ? 'avail-ok' : 'avail-out',
      ),
    ];
    if (page.template.showPromises) {
      final shippingTitle = shell.setting('shipping_promise_title');
      final shippingDetail = shell.setting('shipping_promise_detail');
      final shipping = page.shippingPromise;
      // The owner's own pickup text when there is one; otherwise the shop's
      // address as «Tienda física» says it, without the country
      // (2026-11-20: «Viña del Mar, Chile» under «En Chile»).
      final pickupText = shell.setting('pickup_promise_detail');
      final pickup = pickupText.isNotEmpty
          ? pickupText.replaceAll('\n', ', ')
          : shell.localAddress;
      if (shippingTitle.isNotEmpty || shippingDetail.isNotEmpty) {
        lines.add((
          mdLocalShippingOutlined,
          [shippingTitle, shippingDetail].where((t) => t.isNotEmpty).join('. '),
          null,
        ));
      } else if (shipping != null) {
        lines.add((mdLocalShippingOutlined, shipping.buyBoxDetail, null));
      }
      if (pickup.isNotEmpty) {
        lines.add((mdStorefrontOutlined, 'Retiro en tienda: $pickup', null));
      }
    }
    return div(classes: 'avail', [
      for (final (icon, text, state) in lines)
        p(classes: state, [
          RawText(materialIcon(icon, size: 18)),
          span([.text(text)]),
        ]),
    ]);
  }
}

/// Why it is safe to buy here, in one quiet row: how the store takes the
/// payment (its checkout's methods), where its return policy is, and where
/// the shop is. Each item comes from the store's own settings; without them
/// the row is not drawn.
class _Trust extends StatelessComponent {
  const _Trust(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final shell = page.shell;
    final methods = [
      for (final code in shell.paymentClaims)
        switch (code) {
          PublicCheckoutPaymentCode.mercadopago => 'Mercado Pago',
          PublicCheckoutPaymentCode.transfer => 'transferencia',
        },
    ];
    // Where the shop is, as a customer reads it to come, and a tap opens it
    // on Google Maps. Until 2026-11-20 this kept only the address's last
    // part, the country: the owner read «Tienda física · En Chile» as
    // robotic and asked for the real address («por la dirección de
    // verdad»).
    final address = shell.localAddress;
    final mapsUrl = shell.mapsUrl;
    final items = <(String, String, String, String?)>[
      if (methods.isNotEmpty)
        (
          mdLockOutline,
          'Pago seguro',
          methods.length == 1
              ? methods.single
              : '${methods.sublist(0, methods.length - 1).join(', ')} o ${methods.last}',
          null,
        ),
      if (shell.pagePublication.isPublishedPath('/devoluciones'))
        (
          mdAssignmentReturnOutlined,
          'Cambios y devoluciones',
          'Lee cómo funcionan',
          '/devoluciones',
        ),
      // «Tienda y taller», as the approved canvas names it (version 42).
      if (address.isNotEmpty)
        (
          mdBuildOutlined,
          'Tienda y taller',
          address,
          mapsUrl.isEmpty ? null : mapsUrl,
        ),
    ];
    if (items.isEmpty) return const Component.empty();
    return ul(classes: 'trust', [
      for (final (icon, title, detail, href) in items)
        li([
          RawText(materialIcon(icon, size: 20)),
          if (href != null)
            a(
              href: href,
              attributes: {
                if (href.startsWith('http')) ...{
                  'target': '_blank',
                  'rel': 'noopener',
                },
              },
              [
                strong([.text(title)]),
                span([.text(detail)]),
              ],
            )
          else
            div([
              strong([.text(title)]),
              span([.text(detail)]),
            ]),
        ]),
    ]);
  }
}

/// A sold-out product's buy column: its quantity goes into the quote the
/// visitor puts together; the quote page says whether it is ordered and in
/// how many working days, and the offer confirms it.
class _QuoteBox extends StatelessComponent {
  const _QuoteBox();

  @override
  Component build(BuildContext context) {
    return div(classes: 'quote-box', [
      p(classes: 'quote-box-title', [.text('Te lo conseguimos')]),
      p(classes: 'quote-box-text', [
        .text(
          'Agrégalo a tu cotización y te respondemos con el precio, '
          'el plazo y la disponibilidad confirmados.',
        ),
      ]),
      div(classes: 'quote-box-row', [
        div(classes: 'qty', [
          button(
            classes: 'qty-step',
            attributes: {
              'type': 'button',
              'data-quote-step': '-1',
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
                'min': '1',
                'max': '99',
                'value': '1',
                'inputmode': 'numeric',
                'data-quote-qty': '',
              },
            ),
          ]),
          button(
            classes: 'qty-step',
            attributes: {
              'type': 'button',
              'data-quote-step': '1',
              'aria-label': 'Agregar una unidad',
            },
            [RawText(materialIcon(mdAdd, size: 16))],
          ),
        ]),
        button(
          classes: 'add quote-add',
          attributes: {'type': 'button', 'data-quote-add': ''},
          [.text('Agregar a la cotización')],
        ),
      ]),
    ]);
  }
}

/// A service's buy column after the price: the services page's booking
/// button, with a message that names the service, and where it is done.
class _ServiceBooking extends StatelessComponent {
  const _ServiceBooking(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final shell = page.shell;
    final c = page.commerce;
    final action = page.serviceAction;
    final whatsapp = shell.whatsappDigits;
    final label = (action?.label.trim().isNotEmpty ?? false)
        ? action!.label.trim()
        : WebsiteProductPageTemplate.serviceBookLabel;
    final href = whatsapp.isNotEmpty
        ? 'https://wa.me/$whatsapp?text=${Uri.encodeComponent('Hola, quiero agendar ${c.title} (${catalogPriceLabel(c.price, mode: page.priceMode)}): ${page.productUrl}')}'
        : action?.href.trim() ?? '';
    final where = shell
        .setting('pickup_promise_detail', shell.setting('contact_address'))
        .replaceAll('\n', ', ');
    return div(classes: 'service-booking', [
      if (href.isNotEmpty)
        a(
          classes: 'add book',
          href: href,
          attributes: {'rel': 'noopener', 'target': '_blank'},
          [
            RawText(materialIcon(mdChatBubbleOutlineRounded, size: 17)),
            span([.text(label)]),
          ],
        ),
      if (where.isNotEmpty)
        ul(classes: 'promises', [
          li([
            span(classes: 'dot', attributes: {'aria-hidden': 'true'}, []),
            div([
              strong([.text(WebsiteProductPageTemplate.serviceWhereTitle)]),
              span([.text(where)]),
            ]),
            RawText(materialIcon(mdStorefrontOutlined, size: 18)),
          ]),
        ]),
    ]);
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

class _SpecSheet extends StatelessComponent {
  const _SpecSheet(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final groups = page.sheet.groups;
    final paragraphs = page.descriptionParagraphs;
    final technical = page.sheet.hasTechnicalData;
    final service = page.isService;
    final whatsapp = page.shell.whatsappDigits;
    final c = page.commerce;
    final template = page.template;
    final help = aside(classes: 'help', [
      RawText(
        materialIcon(
          technical ? mdPedalBikeOutlined : mdChatBubbleOutlineRounded,
          size: 26,
        ),
      ),
      p(classes: 'help-title', [
        .text(
          service
              ? WebsiteProductPageTemplate.serviceHelpTitle
              : template.resolvedHelpTitle(technical: technical),
        ),
      ]),
      p([
        .text(
          service
              ? WebsiteProductPageTemplate.serviceHelpText
              : template.resolvedHelpText(technical: technical),
        ),
      ]),
      // The same question as the buy column's box, with the help card's own
      // («¿Le sirve a mi bicicleta?») already marked; without JavaScript,
      // WhatsApp with the product.
      if (service && whatsapp.isNotEmpty)
        a(
          classes: 'ask',
          href:
              'https://wa.me/$whatsapp?text=${Uri.encodeComponent('Hola, quiero consultar por ${c.title} (${c.sku}): ${page.productUrl}')}',
          attributes: {'rel': 'noopener', 'target': '_blank'},
          [
            RawText(materialIcon(mdChatBubbleOutlineRounded, size: 17)),
            .text('Preguntar por WhatsApp'),
          ],
        )
      else if (!service)
        a(
          classes: 'ask',
          href: whatsapp.isNotEmpty
              ? productQuestionWhatsAppHref(page)
              : '/cuenta/chats',
          attributes: {
            if (whatsapp.isNotEmpty) ...{'rel': 'noopener', 'target': '_blank'},
            'data-question-open': '',
            if (technical) 'data-question-sug': '¿Le sirve a mi bicicleta?',
          },
          [
            RawText(materialIcon(mdChatBubbleOutlineRounded, size: 17)),
            .text('Preguntar por este producto'),
          ],
        ),
    ]);
    final hasContent = groups.isNotEmpty || paragraphs.isNotEmpty;
    final rowClass = !template.showHelp
        ? 'sheet-row no-help'
        : hasContent
        ? 'sheet-row'
        : 'sheet-row only-help';
    final sheetTitle = service
        ? WebsiteProductPageTemplate.serviceSheetTitle
        : template.resolvedSheetTitle(technical: technical);
    // Folded, with the description open (owner, 2026-11-20: «bloque →
    // plegable»); a `details` reads and opens without JavaScript, and its
    // text stays in the page for Google.
    Component fold({
      required String title,
      required bool open,
      required List<Component> body,
      String? classes,
    }) => Component.element(
      tag: 'details',
      classes: ['pd-fold', ?classes].join(' '),
      attributes: {if (open) 'open': ''},
      children: [
        Component.element(
          tag: 'summary',
          children: [
            h2([.text(title)]),
            RawText(materialIcon(mdExpandMore, size: 24, classes: 'fold-chev')),
          ],
        ),
        div(classes: 'pd-fold-body', body),
      ],
    );
    return section(
      classes: 'details',
      id: 'ficha',
      attributes: page.page.pick('product-page:sheet', 'Ficha técnica'),
      [
        div(classes: 'details-in', [
          div(classes: rowClass, [
            if (hasContent)
              div(classes: 'sheet', [
                if (paragraphs.isNotEmpty)
                  fold(
                    title: 'Descripción',
                    open: true,
                    body: [
                      div(classes: 'description', [
                        for (final paragraph in paragraphs)
                          p([
                            for (final (index, line)
                                in paragraph.split('\n').indexed) ...[
                              if (index > 0) const br(),
                              .text(line),
                            ],
                          ]),
                      ]),
                    ],
                  ),
                if (groups.isNotEmpty)
                  fold(
                    title: sheetTitle,
                    open: paragraphs.isEmpty,
                    classes: 'pd-fold-sheet',
                    body: [
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
                      if (technical && template.showOriginNote)
                        p(classes: 'origin', [
                          .text(WebsiteProductPageTemplate.originNote),
                        ]),
                    ],
                  ),
              ]),
            if (template.showHelp) help,
          ]),
        ]),
      ],
    );
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

/// What goes with the product, by its technical sheet (2026-10-23): the
/// tubes that fit a tyre, the tyres a tube fits, each one added to the cart
/// from here.
class _Fits extends StatelessComponent {
  const _Fits(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final template = page.template;
    if (page.fits.isEmpty || !template.showFits || page.isService) {
      return const Component.empty();
    }
    final kind = page.fitsKind;
    final title = template.resolvedFitsTitle(kind);
    return section(
      classes: 'fits',
      attributes: page.page.pick('product-page:fits', 'Lo que va con esto'),
      [
        div(classes: 'fits-in', [
          p(classes: 'fits-eyebrow', [
            .text(WebsiteProductPageTemplate.fitsEyebrow(kind)),
          ]),
          h2(classes: 'fits-title', [.text(title)]),
          p(classes: 'fits-note', [
            .text(WebsiteProductPageTemplate.fitsNote(kind)),
          ]),
          ul(classes: 'fits-list', attributes: measuredList('calzan', title), [
            for (final item in page.fits)
              li(classes: 'fit', [
                a(
                  classes: 'fit-card',
                  href: item.path,
                  attributes: {
                    'data-item-id': item.commerce.sku.isNotEmpty
                        ? item.commerce.sku
                        : item.commerce.id,
                    'data-item-name': item.commerce.title,
                    'data-price': item.commerce.price.toStringAsFixed(0),
                  },
                  [
                    span(classes: 'fit-shot', [
                      if (item.commerce.imageUrls.isNotEmpty)
                        img(
                          src: item.commerce.imageUrls.first,
                          alt: item.commerce.title,
                          attributes: {
                            'loading': 'lazy',
                            'decoding': 'async',
                            'width': '96',
                            'height': '96',
                          },
                        ),
                    ]),
                    span(classes: 'fit-text', [
                      span(classes: 'fit-name', [.text(item.commerce.title)]),
                      span(classes: 'fit-price', [
                        .text(publicPrice(item.commerce.price)),
                      ]),
                    ]),
                  ],
                ),
                button(
                  classes: 'fit-add',
                  attributes: {
                    'type': 'button',
                    'data-quick-add': '',
                    'data-product-id': item.commerce.id,
                    'data-max': '${item.max}',
                    'data-item-id': item.commerce.sku.isNotEmpty
                        ? item.commerce.sku
                        : item.commerce.id,
                    'data-item-name': item.commerce.title,
                    'data-price': item.commerce.price.toStringAsFixed(0),
                    'aria-label': 'Agregar ${item.commerce.title} al carrito',
                  },
                  [
                    span(
                      attributes: {'data-quick-label': ''},
                      [.text('Agregar')],
                    ),
                  ],
                ),
              ]),
          ]),
        ]),
      ],
    );
  }
}

class _Related extends StatelessComponent {
  const _Related(this.page);

  final ProductPageModel page;

  @override
  Component build(BuildContext context) {
    final template = page.template;
    if (page.related.isEmpty || !template.showRelated) {
      return const Component.empty();
    }
    final title = page.isService
        ? WebsiteProductPageTemplate.serviceRelatedTitle
        : template.resolvedRelatedTitle;
    return section(
      classes: 'related',
      attributes: page.page.pick('product-page:related', 'Relacionados'),
      [
        h2(classes: 'section-title', [.text(title)]),
        div(classes: 'related-box', [
          ul(
            classes: 'related-cards',
            attributes: measuredList('relacionados', title),
            [
              for (final item in page.related)
                ProductCard(
                  commerce: item.commerce,
                  path: item.path,
                  service: page.isService,
                  model: item.model,
                ),
            ],
          ),
        ]),
      ],
    );
  }
}
