import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../../shared/utils/chilean_utils.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    if (cart.isEmpty) {
      return _buildEmptyCart(context);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cart Items (Left - 65%)
          Expanded(
            flex: 65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Carrito de Compras',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${cart.itemCount} ${cart.itemCount == 1 ? 'producto' : 'productos'}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: PublicStoreTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                _buildCartItems(context, cart),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // Order Summary (Right - 35%)
          Expanded(
            flex: 35,
            child: _buildOrderSummary(context, cart),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: PublicStoreTheme.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: PublicStoreTheme.textMuted,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Tu carrito está vacío',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '¡Agrega productos para comenzar tu compra!',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: PublicStoreTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go('/tienda/productos'),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('EXPLORAR PRODUCTOS'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/tienda'),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItems(BuildContext context, CartProvider cart) {
    return Column(
      children: cart.items.map((item) {
        return _buildCartItem(context, cart, item);
      }).toList(),
    );
  }

  Widget _buildCartItem(BuildContext context, CartProvider cart, CartItem item) {
    final product = item.product;
    final isOutOfStock = product.stockQuantity < item.quantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: PublicStoreTheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: product.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 48,
                              color: PublicStoreTheme.textMuted,
                            ),
                          );
                        },
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.pedal_bike,
                        size: 48,
                        color: PublicStoreTheme.textMuted,
                      ),
                    ),
            ),

            const SizedBox(width: 20),

            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => context.go('/tienda/producto/${product.id}'),
                              child: Text(
                                product.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (product.brand != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                product.brand!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: PublicStoreTheme.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              'SKU: ${product.sku}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: PublicStoreTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Remove Button
                      IconButton(
                        onPressed: () => _showRemoveDialog(context, cart, item),
                        icon: const Icon(Icons.close),
                        tooltip: 'Eliminar',
                        color: PublicStoreTheme.error,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Stock Warning
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: PublicStoreTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PublicStoreTheme.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: PublicStoreTheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Stock insuficiente. Solo ${product.stockQuantity} disponibles.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: PublicStoreTheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Quantity and Price Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Quantity Selector
                      Row(
                        children: [
                          Text(
                            'Cantidad:',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: PublicStoreTheme.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: item.quantity > 1
                                      ? () => cart.decrementQuantity(product.id)
                                      : null,
                                  icon: const Icon(Icons.remove, size: 18),
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                ),
                                Container(
                                  width: 50,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${item.quantity}',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  onPressed: item.quantity < product.stockQuantity
                                      ? () => cart.incrementQuantity(product.id)
                                      : null,
                                  icon: const Icon(Icons.add, size: 18),
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            ChileanUtils.formatCurrency(item.subtotal),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: PublicStoreTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${ChileanUtils.formatCurrency(product.price)} c/u',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PublicStoreTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartProvider cart) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen del Pedido',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Subtotal
            _buildSummaryRow(
              context,
              'Subtotal',
              ChileanUtils.formatCurrency(cart.subtotal),
            ),
            const SizedBox(height: 12),

            // IVA
            _buildSummaryRow(
              context,
              'IVA (19%)',
              ChileanUtils.formatCurrency(cart.ivaAmount),
              isSecondary: true,
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ChileanUtils.formatCurrency(cart.total),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: PublicStoreTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Checkout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/tienda/checkout'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
                child: const Text('PROCEDER AL PAGO'),
              ),
            ),

            const SizedBox(height: 12),

            // Continue Shopping
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/tienda/productos'),
                child: const Text('SEGUIR COMPRANDO'),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // Benefits
            _buildBenefitRow(
              context,
              Icons.local_shipping_outlined,
              'Envío a todo Chile',
            ),
            const SizedBox(height: 16),
            _buildBenefitRow(
              context,
              Icons.store_outlined,
              'Retiro en tienda gratis',
            ),
            const SizedBox(height: 16),
            _buildBenefitRow(
              context,
              Icons.lock_outline,
              'Compra 100% segura',
            ),
            const SizedBox(height: 16),
            _buildBenefitRow(
              context,
              Icons.support_agent_outlined,
              'Atención personalizada',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool isSecondary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: isSecondary
                ? PublicStoreTheme.textSecondary
                : PublicStoreTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: isSecondary
                ? PublicStoreTheme.textSecondary
                : PublicStoreTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: PublicStoreTheme.success,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
