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
import '../widgets/public_store_layout.dart';

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
        final verticalMargin = isMobile ? 28.0 : 44.0;

        if (cart.isEmpty) {
          return _buildEmptyCart(
            context,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
          );
        }

        return Container(
          constraints: const BoxConstraints(maxWidth: 1320),
          margin: EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: verticalMargin,
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(context, cart),
                    const SizedBox(height: 28),
                    _buildCartItems(context, cart, isMobile: true),
                    const SizedBox(height: 32),
                    _buildOrderSummary(context, cart, isMobile: true),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeader(context, cart),
                          const SizedBox(height: 34),
                          _buildCartItems(context, cart, isMobile: false),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 4,
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

  Widget _buildPageHeader(BuildContext context, CartProvider cart) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(context, 'Carrito de compras'),
        const SizedBox(height: 12),
        Text(
          '${cart.itemCount} ${cart.itemCount == 1 ? 'unidad' : 'unidades'} en revisión',
          style: storeTheme.text.bodyLarge?.copyWith(
            fontSize: 18,
            color: storeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ajusta cantidades y confirma disponibilidad antes de continuar al pago.',
          style: storeTheme.text.bodyMedium?.copyWith(
            fontSize: 14,
            color: storeTheme.textSecondary,
            height: 1.5,
          ),
        ),
        if (cart.droppedOnRestore > 0) ...[
          const SizedBox(height: 14),
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
      constraints: const BoxConstraints(maxWidth: 1320),
      margin: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  color: storeTheme.softSurface,
                  border: Border.all(color: storeTheme.line),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  size: 62,
                  color: storeTheme.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeading(context, 'Tu carrito está vacío'),
              const SizedBox(height: 16),
              Text(
                'Agrega productos para comenzar tu compra. El carro mantendrá las cantidades y el resumen mientras recorres la tienda.',
                style: storeTheme.text.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: storeTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => PublicStoreLayout.navigateToHref(
                  context,
                  '/productos',
                ),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('EXPLORAR PRODUCTOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: storeTheme.primary,
                  foregroundColor: storeTheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => PublicStoreLayout.navigateToHref(
                  context,
                  '/',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: storeTheme.primary,
                  side: BorderSide(color: storeTheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('VOLVER AL INICIO'),
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

    final imageStage = Container(
      width: isMobile ? 116 : 168,
      height: isMobile ? 108 : 144,
      color: storeTheme.softSurface,
      padding: const EdgeInsets.all(12),
      child: displayImageUrl != null
          ? Image.network(
              displayImageUrl,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 42,
                    color: storeTheme.textMuted,
                  ),
                );
              },
            )
          : Center(
              child: Icon(
                Icons.pedal_bike_outlined,
                size: 42,
                color: storeTheme.textMuted,
              ),
            ),
    );

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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (commerce.categoryPath.isNotEmpty)
                          _buildMetaPill(
                            context,
                            commerce.categoryPath.toUpperCase(),
                          ),
                        if (commerce.brand.isNotEmpty)
                          _buildMetaPill(
                            context,
                            commerce.brand.toUpperCase(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                        commerce.title.toUpperCase(),
                        style: storeTheme.text.headlineSmall?.copyWith(
                          fontSize: isMobile ? 24 : 28,
                          fontWeight: FontWeight.w700,
                          color: storeTheme.textPrimary,
                          height: 1.08,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SKU ${commerce.sku}',
                      style: storeTheme.text.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: storeTheme.textMuted,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _showRemoveDialog(context, cart, item),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Eliminar',
                color: storeTheme.error,
                splashRadius: 20,
              ),
            ],
          ),
          if (isOutOfStock) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: storeTheme.error.withValues(alpha: 0.08),
                border: Border.all(
                  color: storeTheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'Stock insuficiente. Solo ${product.availableStockQuantity} disponibles.',
                style: storeTheme.text.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: storeTheme.error,
                ),
              ),
            ),
          ],
          SizedBox(height: isMobile ? 16 : 22),
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CANTIDAD',
                      style: storeTheme.text.labelSmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: storeTheme.textSecondary,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildQuantitySelector(context, cart, item),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${ChileanUtils.formatCurrency(commerce.price)} c/u',
                          style: storeTheme.text.bodySmall?.copyWith(
                            fontSize: 13,
                            color: storeTheme.textMuted,
                          ),
                        ),
                        _buildSubtotalBlock(context, item.subtotal),
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CANTIDAD',
                          style: storeTheme.text.labelSmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: storeTheme.textSecondary,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildQuantitySelector(context, cart, item),
                      ],
                    ),
                    const Spacer(),
                    _buildSubtotalBlock(
                      context,
                      item.subtotal,
                      unitPrice: commerce.price,
                    ),
                  ],
                ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 18 : 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: showTopBorder ? storeTheme.line : Colors.transparent,
          ),
          bottom: BorderSide(color: storeTheme.line),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    imageStage,
                    const SizedBox(width: 16),
                    infoColumn,
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imageStage,
                const SizedBox(width: 24),
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
    final totalLabel = taxSummary.isValid ? 'TOTAL' : 'TOTAL PRODUCTOS';
    final totalValue = knownGross == null
        ? '—'
        : ChileanUtils.formatCurrency(knownGross.toDouble());
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        color: storeTheme.raisedSurface,
        border: Border(
          top: BorderSide(color: storeTheme.line),
          bottom: BorderSide(color: storeTheme.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESUMEN DEL PEDIDO',
            style: storeTheme.text.headlineMedium?.copyWith(
              fontSize: isMobile ? 28 : 32,
              fontWeight: FontWeight.w700,
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
            const SizedBox(height: 12),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalLabel,
                style: storeTheme.text.labelSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: storeTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                totalValue,
                style: storeTheme.text.displaySmall?.copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: storeTheme.primary,
                  height: 0.95,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
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
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('PROCEDER AL PAGO'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => PublicStoreLayout.navigateToHref(
                context,
                '/productos',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: storeTheme.primary,
                side: BorderSide(color: storeTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('SEGUIR COMPRANDO'),
            ),
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            height: 1,
            color: storeTheme.line,
          ),
          const SizedBox(height: 18),
          _buildBenefitRow(context, 'Envío a Chile continental'),
          _buildBenefitRow(context, 'Retiro en tienda sin costo'),
          _buildBenefitRow(context, 'Compra 100% segura'),
          _buildBenefitRow(
            context,
            'Atención personalizada',
            isLast: true,
          ),
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

    return Container(
      decoration: BoxDecoration(
        color: storeTheme.surface,
        border: Border.all(color: storeTheme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuantityButton(
            context: context,
            icon: Icons.remove,
            enabled: item.quantity > 1,
            onTap: item.quantity > 1
                ? () => cart.decrementQuantity(product.id)
                : null,
          ),
          Container(
            width: 50,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: storeTheme.line),
              ),
            ),
            child: Text(
              '${item.quantity}',
              style: storeTheme.text.labelLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: storeTheme.textPrimary,
              ),
            ),
          ),
          _buildQuantityButton(
            context: context,
            icon: Icons.add,
            enabled: !product.tracksInventory ||
                item.quantity < product.availableStockQuantity,
            onTap: !product.tracksInventory ||
                    item.quantity < product.availableStockQuantity
                ? () => cart.incrementQuantity(product.id)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required BuildContext context,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 40,
        height: 46,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? storeTheme.textPrimary : storeTheme.disabled,
        ),
      ),
    );
  }

  Widget _buildSubtotalBlock(
    BuildContext context,
    double subtotal, {
    double? unitPrice,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          ChileanUtils.formatCurrency(subtotal),
          style: storeTheme.text.headlineMedium?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: storeTheme.primary,
            height: 0.95,
          ),
        ),
        if (unitPrice != null) ...[
          const SizedBox(height: 4),
          Text(
            '${ChileanUtils.formatCurrency(unitPrice)} c/u',
            style: storeTheme.text.bodySmall?.copyWith(
              fontSize: 12,
              color: storeTheme.textMuted,
            ),
          ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            color:
                secondary ? storeTheme.textSecondary : storeTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color:
                secondary ? storeTheme.textSecondary : storeTheme.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: storeTheme.softSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: storeTheme.text.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: storeTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildBenefitRow(
    BuildContext context,
    String text, {
    bool isLast = false,
  }) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : storeTheme.line,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: storeTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: storeTheme.text.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: storeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(BuildContext context, String title) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: storeTheme.text.headlineMedium?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: storeTheme.textPrimary,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: storeTheme.primary,
        ),
      ],
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
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
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
            style: ElevatedButton.styleFrom(
              backgroundColor: PublicStoreSurfaceTheme.of(context).error,
              foregroundColor: PublicStoreSurfaceTheme.of(context).onError,
            ),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
  }
}
