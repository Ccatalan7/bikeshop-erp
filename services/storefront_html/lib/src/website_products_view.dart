import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'block_composition.dart';
import 'block_product_picks.dart';
import 'material_icons.dart';
import 'product_card.dart';
import 'website_blocks_view.dart';

/// Whether the block shows only the workshop's services: then it draws them
/// as rows of a price list, as `/servicios` does, since a service has no
/// photo for a card (2026-10-09). `_ProductsBlockWidget` follows the same
/// rule.
bool productsBlockShowsServices(List<Product> items) =>
    items.isNotEmpty && items.every((product) => product.isService);

/// Whether the block lays its products in a carousel ([productsCarouselScript]
/// plays it).
bool productsBlockIsCarousel(Map<String, dynamic> data) =>
    WebsiteProductsBlockContract.fromData(data).layout == 'carousel';

/// The products the block shows, at most `maxProducts`, public and in stock:
/// the picked ones in the author's order, or its list as the store reads it
/// ([BlockProductList]; none for a category it does not name, as Flutter).
List<Product> productsBlockItems(
  Map<String, dynamic> data,
  BlockRenderContext context,
) {
  final contract = WebsiteProductsBlockContract.fromData(data);
  final items = contract.productSource == 'manual'
      ? [for (final id in contract.productIds) ?context.products[id]]
      : switch (BlockProductList.of(contract)) {
          final list? => context.productLists[list.key] ?? const <Product>[],
          null => const <Product>[],
        };
  return items.take(contract.maxProducts).toList(growable: false);
}

/// `_ProductsBlockWidget` (2026-10-24): the title as written and the
/// subtitle, the «view all» link at their right, and the grid of
/// `PremiumProductCard`s (two columns on a phone and a tablet, the author's
/// count on a desktop).
class ProductsBlockView extends StatelessComponent {
  const ProductsBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final contract = WebsiteProductsBlockContract.fromData(data);
    final rawTitle = contract.title.trim();
    final title = rawTitle.isEmpty ? 'Destacados' : rawTitle;
    final subtitle = contract.subtitle.trim();
    final items = productsBlockItems(data, context);
    final viewAll = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const ['viewAllText'],
      hrefKeys: const ['viewAllLink'],
      defaultLabel: 'Ver todos los productos',
      defaultHref: '/productos',
      defaultVariant: WebsiteActionVariant.outline,
      enabled: contract.showViewAll,
    );
    final viewAllHref = viewAll == null
        ? null
        : context.publicHref(viewAll.href);
    // The phone and tablet bands of the block's own document (legacy 640 and
    // 1024, canonical 600 and 900), by the window: the home's canvas.
    final canonical = WebsiteResponsiveDataCodec.usesCanonicalSchema(data);
    final band = canonical ? 'cn' : 'lg';
    if (items.isEmpty) {
      return section(classes: 'prod-blk empty $band', [
        div(classes: 'prod-head', [
          div(classes: 'prod-ht', [
            h2([.text(title)]),
            if (subtitle.isNotEmpty) p(classes: 'prod-sub', [.text(subtitle)]),
          ]),
        ]),
        RawText(materialIcon(mdInventory, size: 48)),
        p(classes: 'prod-none', [.text('No hay productos disponibles')]),
      ]);
    }
    return section(classes: 'prod-blk $band', [
      div(classes: 'prod-in', [
        div(classes: 'prod-head', [
          div(classes: 'prod-ht', [
            h2([.text(title)]),
            if (subtitle.isNotEmpty) p(classes: 'prod-sub', [.text(subtitle)]),
          ]),
          if (viewAll != null && viewAllHref != null)
            a(classes: 'prod-all', href: viewAllHref, [
              .text(viewAll.label),
              RawText(materialIcon(mdArrowForward, size: 18)),
            ]),
        ]),
        if (productsBlockShowsServices(items))
          _serviceRows(items, contract, title: title)
        else if (contract.layout == 'carousel')
          _carousel(items, contract, canonical: canonical, title: title)
        else
          ul(
            classes: 'prod-grid',
            attributes: {
              'style': '--cols:${contract.itemsPerRow.clamp(2, 4)}',
              ...measuredList('bloque-${composed.block.id}', title),
            },
            [
              for (final product in items)
                li([_card(product, contract, canonical: canonical)]),
            ],
          ),
      ]),
    ]);
  }

  /// The workshop's services as the price list of `/servicios`: a row
  /// each, its name and its price, two columns from a tablet up.
  Component _serviceRows(
    List<Product> items,
    WebsiteProductsBlockContract contract, {
    required String title,
  }) => ul(
    classes: items.length == 1 ? 'prod-rows one' : 'prod-rows',
    attributes: measuredList('bloque-${composed.block.id}', title),
    [
      for (final product in items)
        li([
          a(
            href: publicProductPath(product),
            attributes: {
              // For Google Analytics, as a card names its product.
              'data-item-id': product.sku.trim().isNotEmpty
                  ? product.sku.trim()
                  : product.id,
              'data-item-name': product.name,
              'data-price': '${product.price.round()}',
            },
            [
              span(classes: 'prod-rname', [.text(product.name)]),
              if (contract.showPrice)
                span(classes: 'prod-rprice', [
                  .text(ChileanUtils.formatCurrency(product.price)),
                ]),
            ],
          ),
        ]),
    ],
  );

  /// The carousel layout: on a phone one card a page, 520 tall, turning
  /// every 3 s with its dots (`_MobileProductAutoCarousel`); wider, a row 480
  /// tall that scrolls sideways, its cards 350, 300 or 260 wide by the
  /// author's count a row.
  Component _carousel(
    List<Product> items,
    WebsiteProductsBlockContract contract, {
    required bool canonical,
    required String title,
  }) {
    final width = switch (contract.itemsPerRow) {
      <= 2 => 350,
      3 => 300,
      _ => 260,
    };
    final phone = canonical ? 599 : 639;
    return div(
      classes: 'prod-car',
      attributes: {'data-pcar': '', 'style': '--card:${width}px'},
      [
        ul(
          classes: 'prod-row',
          attributes: measuredList('bloque-${composed.block.id}', title),
          [
            for (final product in items)
              li([
                _card(
                  product,
                  contract,
                  canonical: canonical,
                  // The photo is its card less 16 px each side: a phone's page
                  // (the window less 16 + 8 a side), or the row's card.
                  sizes:
                      '(max-width: ${phone}px) calc(100vw - 80px), '
                      '${width - 32}px',
                ),
              ]),
          ],
        ),
        if (items.length > 1)
          div(
            classes: 'prod-dots',
            attributes: {'aria-hidden': 'true'},
            [
              for (var index = 0; index < items.length; index++)
                span(classes: index == 0 ? 'on' : null, const []),
            ],
          ),
      ],
    );
  }

  Component _card(
    Product product,
    WebsiteProductsBlockContract contract, {
    required bool canonical,
    String? sizes,
  }) {
    final (phone, tablet) = canonical ? (599, 899) : (639, 1023);
    return productCard(
      product,
      context,
      showBrand: contract.showBrand,
      showSku: contract.showSku,
      showPrice: contract.showPrice,
      showStock: contract.showStock,
      quickAdd: true,
      // The photo is the card less 16 px each side: a phone's single column,
      // a tablet's two, a desktop's four of at most 1.200 px.
      sizes:
          sizes ??
          '(max-width: ${phone}px) calc(100vw - 112px), '
              '(max-width: ${tablet}px) calc(50vw - 90px), '
              '(max-width: 1295px) calc(25vw - 71px), 253px',
    );
  }
}

/// `PremiumProductCard` (2026-10-24): the photo on a soft tile of the site's
/// color, where a white supplier photo melts in; under it the brand, the
/// name as the catalog writes it and the price, with «En stock» when the
/// block asks. The name is the link and its hit area covers the card; with
/// [quickAdd], a product that can go straight to the cart (not a service,
/// a set or without stock) gets a «+» on its photo that adds one.
/// [sizes] says how wide its photo is drawn.
Component productCard(
  Product product,
  BlockRenderContext context, {
  required bool showBrand,
  required bool showSku,
  required bool showPrice,
  required String sizes,
  bool showStock = false,
  bool quickAdd = false,
}) {
  final image = publicProductPrimaryImageUrl(product) ?? '';
  final copies = image.isEmpty ? null : context.thumbnails[image];
  final brand = product.brand?.trim() ?? '';
  final sku = product.sku.trim();
  final rawName = product.name.trim();
  final name = rawName.isEmpty ? 'Producto' : rawName;
  final itemId = sku.isNotEmpty ? sku : product.id;
  final stock = product.trackStock ? product.stockQuantity : 0;
  final canAdd =
      quickAdd &&
      !product.isService &&
      !product.isSet &&
      product.price > 0 &&
      (!product.trackStock || stock > 0);
  final label = [
    name,
    if (showBrand && brand.isNotEmpty) 'Marca $brand',
    if (showSku && sku.isNotEmpty) 'SKU $sku',
    if (showPrice) ChileanUtils.formatCurrency(product.price),
  ].join('. ');
  return div(classes: 'pcard', [
    span(classes: 'pcard-shot', [
      if (image.isNotEmpty)
        img(
          src: copies?.smallestUrl ?? image,
          alt: '',
          loading: MediaLoading.lazy,
          attributes: {
            if (copies != null && copies.variants.isNotEmpty) ...{
              'srcset': copies.srcset,
              'sizes': sizes,
            },
            'decoding': 'async',
          },
        )
      else
        RawText(materialIcon(mdPedalBikeOutlined, size: 56)),
      if (canAdd)
        button(
          classes: 'pcard-add',
          attributes: {
            'type': 'button',
            'aria-label': 'Agregar $name al carrito',
            'data-quick-add': '',
            'data-product-id': product.id,
            'data-max': '$stock',
            'data-item-id': itemId,
            'data-item-name': product.name,
            'data-price': '${product.price.round()}',
          },
          [
            RawText(materialIcon(mdAdd, size: 20, classes: 'pcard-plus')),
            RawText(materialIcon(mdCheck, size: 20, classes: 'pcard-ok')),
          ],
        ),
    ]),
    span(classes: 'pcard-info', [
      // Its line is kept without a brand, so a row of cards lines up.
      if (showBrand) span(classes: 'pcard-brand', [.text(brand)]),
      a(
        classes: 'pcard-name',
        href: publicProductPath(product),
        attributes: {
          'aria-label': label,
          // For Google Analytics, as `measuredItem` names a catalog card.
          'data-item-id': itemId,
          'data-item-name': product.name,
          'data-price': '${product.price.round()}',
        },
        [.text(name)],
      ),
      if (showSku && sku.isNotEmpty)
        span(classes: 'pcard-sku', [.text('SKU: $sku')]),
      if (showPrice || showStock)
        span(classes: 'pcard-row', [
          if (showPrice)
            span(classes: 'pcard-price', [
              .text(ChileanUtils.formatCurrency(product.price)),
            ]),
          if (showStock &&
              !product.isService &&
              (!product.trackStock || stock > 0))
            span(classes: 'pcard-stock', [.text('En stock')]),
        ]),
    ]),
  ]);
}

/// Plays the products carousels on a phone as `_MobileProductAutoCarousel`:
/// the next page every 3 s (back to the first after the last; none for a
/// visitor who asks for less motion), the dots following the page shown,
/// also when the visitor swipes. Wider, the row only scrolls.
const productsCarouselScript = r'''
document.querySelectorAll("[data-pcar]").forEach(function(c){
var row=c.querySelector(".prod-row"),dots=[].slice.call(c.querySelectorAll(".prod-dots span")),n=row.children.length,timer=0;
var still=matchMedia("(prefers-reduced-motion: reduce)").matches;
function paged(){return getComputedStyle(row).scrollSnapType.indexOf("x")>=0}
function at(){return row.clientWidth?Math.round(row.scrollLeft/row.clientWidth):0}
function mark(){var i=at();dots.forEach(function(d,k){d.className=k===i?"on":""})}
function restart(){clearInterval(timer);if(!still&&n>1)timer=setInterval(function(){if(!paged())return;var i=at()+1;row.scrollTo({left:(i>=n?0:i)*row.clientWidth,behavior:"smooth"})},3000)}
var wait=0;row.addEventListener("scroll",function(){clearTimeout(wait);wait=setTimeout(mark,60)},{passive:true});
row.addEventListener("touchstart",restart,{passive:true});
restart();
});
''';
