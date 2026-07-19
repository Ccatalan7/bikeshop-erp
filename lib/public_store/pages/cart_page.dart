import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import '../utils/product_url.dart';

class CartPage extends StatelessWidget {
  static const Color _logoBlue = Color(0xFF093357);
  static const Color _warmLine = Color(0xFFE8E2D8);
  static const Color _warmSurface = Color(0xFFF7F4EE);
  static const Color _softSurface = Color(0xFFFCFBF8);

  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    // Get edit mode for key to prevent element reactivation conflicts
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');

    return MediaQueryLayoutBuilder(
      key: ValueKey('cart_layout_$modeKey'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Carrito de compras'),
        const SizedBox(height: 12),
        Text(
          '${cart.itemCount} ${cart.itemCount == 1 ? 'producto' : 'productos'} en revisión',
          style: const TextStyle(
            fontFamily: null,
            fontSize: 18,
            color: PublicStoreTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ajusta cantidades y confirma disponibilidad antes de continuar al pago.',
          style: TextStyle(
            fontFamily: null,
            fontSize: 14,
            color: PublicStoreTheme.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCart(
    BuildContext context, {
    required double horizontalMargin,
    required double verticalMargin,
  }) {
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
                  color: _softSurface,
                  border: Border.all(color: _warmLine),
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  size: 62,
                  color: PublicStoreTheme.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeading('Tu carrito está vacío'),
              const SizedBox(height: 16),
              const Text(
                'Agrega productos para comenzar tu compra. El carro mantendrá las cantidades y el resumen mientras recorres la tienda.',
                style: TextStyle(
                  fontFamily: null,
                  fontSize: 15,
                  color: PublicStoreTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/productos'),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('EXPLORAR PRODUCTOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: _logoBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => context.go('/tienda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _logoBlue,
                  side: const BorderSide(color: _logoBlue),
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
    final product = item.product;
    final isOutOfStock = product.stockQuantity < item.quantity;
    final displayImageUrl = product.imageUrlOptimized ?? product.imageUrl;

    final imageStage = Container(
      width: isMobile ? 116 : 168,
      height: isMobile ? 108 : 144,
      color: _softSurface,
      padding: const EdgeInsets.all(12),
      child: displayImageUrl != null
          ? Image.network(
              displayImageUrl,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 42,
                    color: PublicStoreTheme.textMuted,
                  ),
                );
              },
            )
          : const Center(
              child: Icon(
                Icons.pedal_bike_outlined,
                size: 42,
                color: PublicStoreTheme.textMuted,
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
                        if (product.categoryName?.trim().isNotEmpty ?? false)
                          _buildMetaPill(
                            product.categoryName!.trim().toUpperCase(),
                          ),
                        if (product.brand?.trim().isNotEmpty ?? false)
                          _buildMetaPill(product.brand!.trim().toUpperCase()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => context.go(publicProductPath(product)),
                      child: Text(
                        product.name.toUpperCase(),
                        style: TextStyle(
                          fontFamily: null,
                          fontSize: isMobile ? 24 : 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                          height: 1.08,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SKU ${product.sku}',
                      style: const TextStyle(
                        fontFamily: null,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: PublicStoreTheme.textMuted,
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
                color: PublicStoreTheme.error,
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
                color: PublicStoreTheme.error.withValues(alpha: 0.08),
                border: Border.all(
                  color: PublicStoreTheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'Stock insuficiente. Solo ${product.stockQuantity} disponibles.',
                style: const TextStyle(
                  fontFamily: null,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PublicStoreTheme.error,
                ),
              ),
            ),
          ],
          SizedBox(height: isMobile ? 16 : 22),
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CANTIDAD',
                      style: TextStyle(
                        fontFamily: null,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: PublicStoreTheme.textSecondary,
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
                          '${ChileanUtils.formatCurrency(product.price)} c/u',
                          style: const TextStyle(
                            fontFamily: null,
                            fontSize: 13,
                            color: PublicStoreTheme.textMuted,
                          ),
                        ),
                        _buildSubtotalBlock(item.subtotal),
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
                        const Text(
                          'CANTIDAD',
                          style: TextStyle(
                            fontFamily: null,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: PublicStoreTheme.textSecondary,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildQuantitySelector(context, cart, item),
                      ],
                    ),
                    const Spacer(),
                    _buildSubtotalBlock(
                      item.subtotal,
                      unitPrice: product.price,
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
            color: showTopBorder ? _warmLine : Colors.transparent,
          ),
          bottom: const BorderSide(color: _warmLine),
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
    final taxSummary = cart.taxSummary;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        color: _warmSurface.withValues(alpha: 0.56),
        border: const Border(
          top: BorderSide(color: _warmLine),
          bottom: BorderSide(color: _warmLine),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESUMEN DEL PEDIDO',
            style: TextStyle(
              fontFamily: null,
              fontSize: isMobile ? 28 : 32,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 18),
          if (taxSummary.isValid) ...[
            _buildSummaryMetric(
              taxSummary.netLabel,
              ChileanUtils.formatCurrency(taxSummary.netAmount.toDouble()),
            ),
            const SizedBox(height: 12),
            _buildSummaryMetric(
              taxSummary.ivaLabel,
              ChileanUtils.formatCurrency(taxSummary.taxAmount.toDouble()),
              secondary: true,
            ),
          ] else ...[
            _buildTaxConfigurationWarning(
              taxSummary.checkoutBlockMessage ??
                  'No podemos validar los impuestos de este carrito.',
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1,
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontFamily: null,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PublicStoreTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                ChileanUtils.formatCurrency(cart.total),
                style: const TextStyle(
                  fontFamily: null,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: _logoBlue,
                  height: 0.95,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: taxSummary.isValid
                  ? () => context.go('/tienda/checkout')
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _logoBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('PROCEDER AL PAGO'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/productos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _logoBlue,
                side: const BorderSide(color: _logoBlue),
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
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          _buildBenefitRow('Envío a todo Chile'),
          _buildBenefitRow('Retiro en tienda sin costo'),
          _buildBenefitRow('Compra 100% segura'),
          _buildBenefitRow('Atención personalizada', isLast: true),
        ],
      ),
    );
  }

  Widget _buildQuantitySelector(
    BuildContext context,
    CartProvider cart,
    CartItem item,
  ) {
    final product = item.product;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _warmLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuantityButton(
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
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: _warmLine),
              ),
            ),
            child: Text(
              '${item.quantity}',
              style: const TextStyle(
                fontFamily: null,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          _buildQuantityButton(
            icon: Icons.add,
            enabled: item.quantity < product.stockQuantity,
            onTap: item.quantity < product.stockQuantity
                ? () => cart.incrementQuantity(product.id)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 40,
        height: 46,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.black87 : PublicStoreTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildSubtotalBlock(
    double subtotal, {
    double? unitPrice,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          ChileanUtils.formatCurrency(subtotal),
          style: const TextStyle(
            fontFamily: null,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: _logoBlue,
            height: 0.95,
          ),
        ),
        if (unitPrice != null) ...[
          const SizedBox(height: 4),
          Text(
            '${ChileanUtils.formatCurrency(unitPrice)} c/u',
            style: const TextStyle(
              fontFamily: null,
              fontSize: 12,
              color: PublicStoreTheme.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryMetric(
    String label,
    String value, {
    bool secondary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            color: secondary
                ? PublicStoreTheme.textSecondary
                : PublicStoreTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: secondary ? PublicStoreTheme.textSecondary : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildTaxConfigurationWarning(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8E8),
        border: Border(
          left: BorderSide(color: Color(0xFFB7791F), width: 3),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: null,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B4F19),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildMetaPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _softSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: null,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: PublicStoreTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildBenefitRow(String text, {bool isLast = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
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
            decoration: const BoxDecoration(
              color: _logoBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: null,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontFamily: null,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: Colors.black,
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
          '¿Estás seguro que deseas eliminar "${item.product.name}" del carrito?',
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
              backgroundColor: PublicStoreTheme.error,
            ),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
  }
}
