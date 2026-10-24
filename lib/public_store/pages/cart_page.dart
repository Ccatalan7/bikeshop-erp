import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/public_store_surface_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import '../utils/product_url.dart';
import '../widgets/cart_restore_notice.dart';
import '../widgets/cart_suggestions.dart';
import '../widgets/public_store_layout.dart';

/// The cart (2026-10-24), as the HTML `/carrito` draws it: titles as
/// written, each photo on the products' tile, the summary in its own card and
/// «Te puede faltar» under the lines ([CartSuggestions]).
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    // Get edit mode for key to prevent element reactivation conflicts

    return MediaQueryLayoutBuilder(
      key: const ValueKey('cart_layout'),
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 980;
        final horizontalMargin = constraints.maxWidth < 760 ? 16.0 : 24.0;

        if (cart.isEmpty) {
          return _buildEmptyCart(
            context,
            horizontalMargin: horizontalMargin,
            verticalMargin: isMobile ? 24 : 40,
          );
        }

        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(context, cart, isMobile: isMobile),
            SizedBox(height: isMobile ? 22 : 28),
            _buildCartItems(context, cart, isMobile: isMobile),
            CartSuggestions(isMobile: isMobile),
          ],
        );

        return Container(
          constraints: const BoxConstraints(maxWidth: 1240),
          margin: EdgeInsets.fromLTRB(
            horizontalMargin,
            isMobile ? 24 : 40,
            horizontalMargin,
            isMobile ? 48 : 72,
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    main,
                    const SizedBox(height: 28),
                    _buildOrderSummary(context, cart, isMobile: true),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 48),
                    SizedBox(
                      width: 380,
                      child: _buildOrderSummary(
                        context,
                        cart,
                        isMobile: false,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPageHeader(
    BuildContext context,
    CartProvider cart, {
    required bool isMobile,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          context,
          'Carrito de compras',
          size: isMobile ? 30 : 36,
        ),
        const SizedBox(height: 8),
        Text(
          '${cart.itemCount} ${cart.itemCount == 1 ? 'unidad' : 'unidades'} en revisión',
          style: storeTheme.text.bodyLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: storeTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ajusta cantidades y confirma disponibilidad antes de continuar al pago.',
          style: storeTheme.text.bodyMedium?.copyWith(
            fontSize: 14,
            color: storeTheme.textMuted,
            height: 1.5,
          ),
        ),
        if (cart.droppedOnRestore > 0) ...[
          const SizedBox(height: 16),
          CartRestoreNotice(
            dropped: cart.droppedOnRestore,
            onAcknowledged: cart.acknowledgeDroppedLines,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyCart(
    BuildContext context, {
    required double horizontalMargin,
    required double verticalMargin,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 1240),
      margin: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: storeTheme.photoTile,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  size: 62,
                  color: storeTheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              _buildSectionHeading(
                context,
                'Tu carrito está vacío',
                size: 30,
                center: true,
              ),
              const SizedBox(height: 12),
              Text(
                'Agrega productos para comenzar tu compra. El carro mantendrá las cantidades y el resumen mientras recorres la tienda.',
                style: storeTheme.text.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: storeTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => PublicStoreLayout.navigateToHref(
                  context,
                  '/productos',
                ),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text('Explorar productos'),
                style: FilledButton.styleFrom(
                  backgroundColor: storeTheme.primary,
                  foregroundColor: storeTheme.onPrimary,
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => PublicStoreLayout.navigateToHref(
                  context,
                  '/',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: storeTheme.textSecondary,
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItems(
    BuildContext context,
    CartProvider cart, {
    required bool isMobile,
  }) {
    return Column(
      children: [
        for (var index = 0; index < cart.items.length; index++)
          _buildCartItem(
            context,
            cart,
            cart.items[index],
            isMobile: isMobile,
            showTopBorder: index == 0,
          ),
      ],
    );
  }

  Widget _buildCartItem(
    BuildContext context,
    CartProvider cart,
    CartItem item, {
    required bool isMobile,
    required bool showTopBorder,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    final product = item.product;
    final commerce = item.commerce;
    final isOutOfStock =
        commerce.availability.merchantValue == 'out_of_stock' ||
            product.availableStockQuantity < item.quantity;
    final displayImageUrl =
        commerce.imageUrls.isNotEmpty ? commerce.imageUrls.first : null;
    final tile = storeTheme.photoTile;
    final placeholder = Center(
      child: Icon(
        Icons.pedal_bike_outlined,
        size: 42,
        color: storeTheme.textMuted,
      ),
    );

    final imageStage = ClipRRect(
      borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
      child: Container(
        width: isMobile ? 96 : 132,
        height: isMobile ? 96 : 132,
        color: tile,
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        child: displayImageUrl != null
            // Multiplied by the tile, as the HTML's `mix-blend-mode`.
            ? ColorFiltered(
                colorFilter: ColorFilter.mode(tile, BlendMode.multiply),
                child: Image.network(
                  displayImageUrl,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                ),
              )
            : placeholder,
      ),
    );

    final pills = [
      if (commerce.brand.isNotEmpty) commerce.brand,
      if (commerce.categoryPath.isNotEmpty) commerce.categoryPath,
    ];

    final infoColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pills.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final pill in pills)
                            _buildMetaPill(context, pill),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    InkWell(
                      onTap: () {
                        final tenantId = context
                                .read<PublicStoreTenantProvider>()
                                .tenantId
                                ?.trim() ??
                            '';
                        if (tenantId.isNotEmpty) {
                          context
                              .read<PublicInventoryService>()
                              .primeProductSnapshotForNavigation(
                                tenantId: tenantId,
                                product: product,
                              );
                        }
                        PublicStoreLayout.navigateToHref(
                          context,
                          publicProductPath(product),
                        );
                      },
                      child: Text(
                        commerce.title,
                        style: storeTheme.text.titleMedium?.copyWith(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: storeTheme.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU ${commerce.sku}',
                      style: storeTheme.text.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: storeTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Transform.translate(
                offset: const Offset(8, -6),
                child: IconButton(
                  onPressed: () => _showRemoveDialog(context, cart, item),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Eliminar',
                  color: storeTheme.textMuted,
                  hoverColor: storeTheme.error.withValues(alpha: 0.08),
                  splashRadius: 20,
                ),
              ),
            ],
          ),
          if (isOutOfStock) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: storeTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Stock insuficiente. Solo ${product.availableStockQuantity} disponibles.',
                style: storeTheme.text.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: storeTheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                container: true,
                label: 'Cantidad',
                child: _buildQuantitySelector(context, cart, item),
              ),
              const SizedBox(width: 12),
              // A large amount on a narrow phone shrinks, never overflows.
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _buildSubtotalBlock(
                      context,
                      item.subtotal,
                      unitPrice: commerce.price,
                      unitFirst: isMobile,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 16 : 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: showTopBorder ? storeTheme.line : Colors.transparent,
          ),
          bottom: BorderSide(color: storeTheme.line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imageStage,
          SizedBox(width: isMobile ? 14 : 20),
          infoColumn,
        ],
      ),
    );
  }

  Widget _buildOrderSummary(
    BuildContext context,
    CartProvider cart, {
    required bool isMobile,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    final taxSummary = cart.taxSummary;
    final knownGross = cart.grossMerchandiseAmountClp;
    final totalLabel = taxSummary.isValid ? 'Total' : 'Total productos';
    final totalValue = knownGross == null
        ? '—'
        : ChileanUtils.formatCurrency(knownGross.toDouble());
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 22 : 28),
      decoration: BoxDecoration(
        color: storeTheme.surface,
        border: Border.all(color: storeTheme.line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.10),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen del pedido',
            style: storeTheme.text.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: storeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          if (taxSummary.isValid) ...[
            _buildSummaryMetric(
              context,
              taxSummary.netLabel,
              ChileanUtils.formatCurrency(taxSummary.netAmount.toDouble()),
            ),
            const SizedBox(height: 8),
            _buildSummaryMetric(
              context,
              taxSummary.ivaLabel,
              ChileanUtils.formatCurrency(taxSummary.taxAmount.toDouble()),
              secondary: true,
            ),
          ] else ...[
            _buildTaxConfigurationWarning(
              context,
              taxSummary.checkoutBlockMessage ??
                  'No podemos validar los impuestos de este carrito.',
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1,
            color: storeTheme.line,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                totalLabel,
                style: storeTheme.text.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: storeTheme.textPrimary,
                ),
              ),
              Flexible(
                child: Text(
                  totalValue,
                  textAlign: TextAlign.right,
                  style: storeTheme.text.headlineMedium?.copyWith(
                    fontFamily: storeTheme.text.bodyMedium?.fontFamily,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: storeTheme.textPrimary,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: MouseRegion(
              onEnter: taxSummary.isValid
                  ? (_) => PublicStoreLayout.prepareHref(context, '/checkout')
                  : null,
              child: FilledButton(
                onPressed: taxSummary.isValid
                    ? () => PublicStoreLayout.navigateToHref(
                          context,
                          '/checkout',
                        )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: storeTheme.primary,
                  foregroundColor: storeTheme.onPrimary,
                  minimumSize: const Size.fromHeight(54),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Proceder al pago'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => PublicStoreLayout.navigateToHref(
                context,
                '/productos',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: storeTheme.textPrimary,
                side: BorderSide(color: storeTheme.line),
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Seguir comprando'),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 1,
            color: storeTheme.line,
          ),
          const SizedBox(height: 18),
          for (final (index, perk) in const [
            'Envío a Chile continental',
            'Retiro en tienda sin costo',
            'Compra 100% segura',
            'Atención personalizada',
          ].indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            _buildBenefitRow(context, perk),
          ],
        ],
      ),
    );
  }

  Widget _buildQuantitySelector(
    BuildContext context,
    CartProvider cart,
    CartItem item,
  ) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    final product = item.product;
    final canIncrement = !product.tracksInventory ||
        item.quantity < product.availableStockQuantity;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: storeTheme.surface,
        border: Border.all(color: storeTheme.line),
        borderRadius: BorderRadius.circular(999),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuantityButton(
            context: context,
            icon: Icons.remove,
            tooltip: 'Quitar una unidad',
            enabled: item.quantity > 1,
            onTap: item.quantity > 1
                ? () => cart.decrementQuantity(product.id)
                : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 32),
            child: Text(
              '${item.quantity}',
              textAlign: TextAlign.center,
              style: storeTheme.text.labelLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: storeTheme.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _buildQuantityButton(
            context: context,
            icon: Icons.add,
            tooltip: 'Agregar una unidad',
            enabled: canIncrement,
            onTap:
                canIncrement ? () => cart.incrementQuantity(product.id) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? storeTheme.textPrimary : storeTheme.disabled,
          ),
        ),
      ),
    );
  }

  Widget _buildSubtotalBlock(
    BuildContext context,
    double subtotal, {
    required double unitPrice,
    required bool unitFirst,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    final each = Text(
      '${ChileanUtils.formatCurrency(unitPrice)} c/u',
      style: storeTheme.text.bodySmall?.copyWith(
        fontSize: 12,
        color: storeTheme.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (unitFirst) each,
        Text(
          ChileanUtils.formatCurrency(subtotal),
          style: storeTheme.text.titleLarge?.copyWith(
            fontFamily: storeTheme.text.bodyMedium?.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: storeTheme.textPrimary,
            height: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (!unitFirst) ...[
          const SizedBox(height: 2),
          each,
        ],
      ],
    );
  }

  Widget _buildSummaryMetric(
    BuildContext context,
    String label,
    String value, {
    bool secondary = false,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    final color = secondary ? storeTheme.textSecondary : storeTheme.textPrimary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontFamily: null, fontSize: 15, color: color),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildTaxConfigurationWarning(
    BuildContext context,
    String message,
  ) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: storeTheme.warningSurface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        border: Border(
          left: BorderSide(color: storeTheme.warning, width: 3),
        ),
      ),
      child: Text(
        message,
        style: storeTheme.text.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: storeTheme.onWarningSurface,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildMetaPill(BuildContext context, String label) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: storeTheme.softSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: storeTheme.text.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.5,
          color: storeTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildBenefitRow(BuildContext context, String text) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Row(
      children: [
        Icon(Icons.check, size: 16, color: storeTheme.success),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: storeTheme.text.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: storeTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeading(
    BuildContext context,
    String title, {
    required double size,
    bool center = false,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Text(
      title,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: storeTheme.text.headlineMedium?.copyWith(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * size,
        color: storeTheme.textPrimary,
        height: 1.15,
      ),
    );
  }

  void _showRemoveDialog(
    BuildContext context,
    CartProvider cart,
    CartItem item,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Estás seguro que deseas eliminar "${item.commerce.title}" del carrito?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              cart.removeProduct(item.product.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Producto eliminado del carrito'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: PublicStoreSurfaceTheme.of(context).error,
              foregroundColor: PublicStoreSurfaceTheme.of(context).onError,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
