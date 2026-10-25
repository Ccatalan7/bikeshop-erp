import 'package:flutter/material.dart';

import '../../../public_store/utils/product_url.dart';
import '../../../public_store/widgets/public_link_semantics.dart';
import '../../../shared/utils/chilean_utils.dart';

/// The product card of the website (2026-10-24), as the HTML storefront's
/// `productCard` draws it. It takes Canyon's grid idea in Viñabike's voice:
/// the photo on a flat grey tile with square corners, which a white supplier
/// photo melts into. Under it go the brand, the name as the catalog writes it
/// and the price in the heading font and the site's color, as on the product
/// page, with «En stock» when asked. The «+» is a square in the tile's corner.
///
/// - [interactionsEnabled] is an EXPLICIT interaction flag: visitor surfaces
///   (public AND Preview) enable it; editors (Edit blocks, editable Canvas)
///   disable it. It carries no preview-data semantics.
/// - When interactive, tapping navigates to the product's public URL.
/// - [showAdd] puts a «+» on the photo; [onAdd] adds one to the cart (inert
///   while editing).
class PremiumProductCard extends StatefulWidget {
  final String productId;
  final String? productSku;
  final String? productBrand;
  final String name;
  final double price;
  final String? imageUrl;

  /// The price's font, the site's heading font (the theme's headline font
  /// when null).
  final String? headingFont;
  final String? bodyFont;
  final bool showPrice;
  final bool showSku;
  final bool showBrand;
  final bool showStock;
  final bool showAdd;
  final VoidCallback? onAdd;
  final bool interactionsEnabled;
  final void Function(String route)? onNavigate;

  const PremiumProductCard({
    super.key,
    required this.productId,
    this.productSku,
    this.productBrand,
    required this.name,
    required this.price,
    this.imageUrl,
    this.headingFont,
    this.bodyFont,
    this.showPrice = true,
    this.showSku = false,
    this.showBrand = false,
    this.showStock = false,
    this.showAdd = false,
    this.onAdd,
    required this.interactionsEnabled,
    this.onNavigate,
  });

  /// The «+» on the photo.
  static const addKey = ValueKey<String>('premium-product-card-add');

  /// How tall the words under the photo are for a [width]: a grid gives each
  /// card its square photo plus this ([PremiumProductCard.heightFor]).
  static double infoHeight({required bool brand, required bool sku}) =>
      12 + (brand ? 20 : 0) + 41 + (sku ? 21 : 0) + 30;

  /// The card's height for [width]: a square photo and its words.
  static double heightFor(
    double width, {
    required bool brand,
    required bool sku,
  }) =>
      width + infoHeight(brand: brand, sku: sku);

  @override
  State<PremiumProductCard> createState() => _PremiumProductCardState();
}

class _PremiumProductCardState extends State<PremiumProductCard> {
  bool _isHovered = false;

  bool get _isInteractive =>
      widget.interactionsEnabled && widget.onNavigate != null;

  String get _semanticLabel {
    final parts = <String>[
      widget.name.trim().isEmpty ? 'Producto' : widget.name.trim(),
      if (widget.showBrand && (widget.productBrand?.trim().isNotEmpty ?? false))
        'Marca ${widget.productBrand!.trim()}',
      if (widget.showSku && (widget.productSku?.trim().isNotEmpty ?? false))
        'SKU ${widget.productSku!.trim()}',
      if (widget.showPrice) ChileanUtils.formatCurrency(widget.price),
    ];
    return parts.join('. ');
  }

  String get _productPath => buildPublicProductPath(
        name: widget.name,
        sku: widget.productSku ?? '',
        fallbackProductId: widget.productId,
      );

  bool get _declaresLink =>
      _isInteractive && PublicLinkSemantics.publicStoreRuntime;

  void _openProduct() {
    widget.onNavigate?.call(_productPath);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final hovered = _isInteractive && _isHovered;
    // The flat grey tile: the page's ink at 6 % over the page (9 % under the
    // pointer), as the HTML's `color-mix(in srgb, var(--w-on) 6%, var(--w-bg))`.
    final tile = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: hovered ? 0.09 : 0.06),
      scheme.surface,
    );
    final brand = widget.productBrand?.trim() ?? '';
    final sku = widget.productSku?.trim() ?? '';
    final name = widget.name.trim().isEmpty ? 'Producto' : widget.name.trim();
    TextStyle text(double size, FontWeight weight, Color color) => TextStyle(
          fontFamily: widget.bodyFont,
          fontSize: size,
          fontWeight: weight,
          height: 1.35,
          color: color,
        );
    final placeholder = Center(
      child: Icon(
        Icons.pedal_bike_outlined,
        size: 48,
        color: Colors.grey.shade400,
      ),
    );

    final photo = ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: tile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: FractionallySizedBox(
                widthFactor: 0.76,
                heightFactor: 0.76,
                child: hasImage
                    // Multiplied by the tile, as the HTML's `mix-blend-mode`:
                    // a white background takes the tile's color.
                    ? ColorFiltered(
                        colorFilter: ColorFilter.mode(tile, BlendMode.multiply),
                        child: AnimatedScale(
                          scale: hovered ? 1.04 : 1,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          child: Image.network(
                            widget.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                placeholder,
                          ),
                        ),
                      )
                    : placeholder,
              ),
            ),
            if (widget.showAdd)
              Positioned(
                right: 0,
                bottom: 0,
                child: Semantics(
                  button: true,
                  label: 'Agregar $name al carrito',
                  child: ExcludeSemantics(
                    child: Material(
                      key: PremiumProductCard.addKey,
                      color: scheme.primary,
                      child: InkWell(
                        onTap:
                            widget.interactionsEnabled ? widget.onAdd : () {},
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.add,
                            size: 20,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final info = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Its line is kept without a brand, so a row of cards lines up.
          if (widget.showBrand) ...[
            Text(
              brand.toUpperCase(),
              style: text(11, FontWeight.w700, scheme.onSurfaceVariant)
                  .copyWith(letterSpacing: 1.3, height: 1.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
          ],
          SizedBox(
            height: 41,
            child: Text(
              name,
              style: text(15, FontWeight.w500, scheme.onSurface).copyWith(
                decoration: hovered ? TextDecoration.underline : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.showSku && sku.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'SKU: $sku',
              style: text(12, FontWeight.w500, scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (widget.showPrice || widget.showStock) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (widget.showPrice)
                  Expanded(
                    child: Text(
                      ChileanUtils.formatCurrency(widget.price),
                      style: text(22, FontWeight.w500, scheme.primary).copyWith(
                        fontFamily: widget.headingFont ??
                            Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.fontFamily,
                        height: 1.15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (widget.showStock)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: _inStock,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'En stock',
                        style: text(13, FontWeight.w600, _inStock),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: _isInteractive,
      // En la tienda pública, con la semántica activa (rastreadores), sale
      // como `<a href>`; en Edit/Preview del ERP sigue siendo un botón.
      link: _declaresLink,
      linkUrl: _declaresLink ? publicLinkUri(_productPath) : null,
      enabled: _isInteractive ? true : null,
      label: _semanticLabel,
      child: MouseRegion(
        onEnter:
            _isInteractive ? (_) => setState(() => _isHovered = true) : null,
        onExit:
            _isInteractive ? (_) => setState(() => _isHovered = false) : null,
        cursor: _isInteractive ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isInteractive ? _openProduct : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: photo),
              ExcludeSemantics(child: info),
            ],
          ),
        ),
      ),
    );
  }
}

/// «En stock», the green the HTML card writes (#1F7A46).
const _inStock = Color(0xFF1F7A46);
