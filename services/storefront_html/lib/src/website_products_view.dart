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
import 'material_icons.dart';
import 'website_blocks_view.dart';

/// What the HTML products block draws: a grid of hand-picked products on the
/// block's own white. A carousel layout, another source (the featured,
/// newest or a category's products, which the page does not read yet) or a
/// surface the author styled are not drawn yet.
bool productsBlockIsCovered(Map<String, dynamic> data) {
  final contract = WebsiteProductsBlockContract.fromData(data);
  final style = data['style'];
  return contract.layout == 'grid' &&
      contract.productSource == 'manual' &&
      (style is! Map || style.isEmpty);
}

/// The products the block shows: the picked ones that are public and in
/// stock, in the author's order, at most `maxProducts`.
List<Product> productsBlockItems(
  Map<String, dynamic> data,
  Map<String, Product> products,
) {
  final contract = WebsiteProductsBlockContract.fromData(data);
  return [
    for (final id in contract.productIds) ?products[id],
  ].take(contract.maxProducts).toList(growable: false);
}

/// `_ProductsBlockWidget`: the title after a black bar, the subtitle, the
/// grid of `PremiumProductCard`s (one column on a phone, two on a tablet,
/// the author's count on a desktop) and the «view all» button.
class ProductsBlockView extends StatelessComponent {
  const ProductsBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final contract = WebsiteProductsBlockContract.fromData(data);
    final rawTitle = contract.title.trim();
    final title = rawTitle.isEmpty ? 'DESTACADOS' : rawTitle.toUpperCase();
    final subtitle = contract.subtitle.trim();
    final items = productsBlockItems(data, context.products);
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
          span(classes: 'prod-bar', const []),
          h2([.text(title)]),
        ]),
        if (subtitle.isNotEmpty) p(classes: 'prod-sub', [.text(subtitle)]),
        RawText(materialIcon(mdInventory, size: 48)),
        p(classes: 'prod-none', [.text('No hay productos disponibles')]),
      ]);
    }
    return section(classes: 'prod-blk $band', [
      div(classes: 'prod-in', [
        div(classes: 'prod-head', [
          span(classes: 'prod-bar', const []),
          h2([.text(title)]),
        ]),
        if (subtitle.isNotEmpty) p(classes: 'prod-sub', [.text(subtitle)]),
        ul(
          classes: 'prod-grid',
          attributes: {'style': '--cols:${contract.itemsPerRow.clamp(2, 4)}'},
          [
            for (final product in items)
              li([_card(product, contract, canonical: canonical)]),
          ],
        ),
        if (viewAll != null && viewAllHref != null)
          div(classes: 'prod-all', [
            a(classes: 'w-btn ink outline', href: viewAllHref, [
              .text(viewAll.label.toUpperCase()),
            ]),
          ]),
      ]),
    ]);
  }

  Component _card(
    Product product,
    WebsiteProductsBlockContract contract, {
    required bool canonical,
  }) {
    final image = publicProductPrimaryImageUrl(product) ?? '';
    final copies = image.isEmpty ? null : context.thumbnails[image];
    final brand = product.brand?.trim() ?? '';
    final sku = product.sku.trim();
    final name = product.name.isEmpty ? 'Producto' : product.name;
    final label = [
      name.trim().isEmpty ? 'Producto' : name.trim(),
      if (contract.showBrand && brand.isNotEmpty) 'Marca $brand',
      if (contract.showSku && sku.isNotEmpty) 'SKU $sku',
      if (contract.showPrice) ChileanUtils.formatCurrency(product.price),
    ].join('. ');
    final (phone, tablet) = canonical ? (599, 899) : (639, 1023);
    return a(
      classes: 'pcard',
      href: publicProductPath(product),
      attributes: {'aria-label': label},
      [
        span(classes: 'pcard-shot', [
          if (image.isNotEmpty)
            img(
              src: copies?.smallestUrl ?? image,
              alt: '',
              loading: MediaLoading.lazy,
              attributes: {
                if (copies != null && copies.variants.isNotEmpty) ...{
                  'srcset': copies.srcset,
                  // The photo is the card less 16 px each side: a phone's
                  // single column, a tablet's two, a desktop's four of at
                  // most 1.200 px.
                  'sizes':
                      '(max-width: ${phone}px) calc(100vw - 112px), '
                      '(max-width: ${tablet}px) calc(50vw - 90px), '
                      '(max-width: 1295px) calc(25vw - 71px), 253px',
                },
                'decoding': 'async',
              },
            )
          else
            RawText(materialIcon(mdPedalBikeOutlined, size: 56)),
          span(
            classes: 'pcard-cta',
            attributes: {'aria-hidden': 'true'},
            [.text('VER DETALLES')],
          ),
        ]),
        span(classes: 'pcard-info', [
          if (contract.showBrand && brand.isNotEmpty)
            span(classes: 'pcard-brand', [.text(brand.toUpperCase())]),
          span(classes: 'pcard-name', [.text(name.toUpperCase())]),
          if (contract.showSku && sku.isNotEmpty)
            span(classes: 'pcard-sku', [.text('SKU: $sku')]),
          if (contract.showPrice)
            span(classes: 'pcard-price', [
              .text(ChileanUtils.formatCurrency(product.price)),
            ]),
        ]),
      ],
    );
  }
}
