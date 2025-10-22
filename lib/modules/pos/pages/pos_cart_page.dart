import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../services/pos_service.dart';
import '../widgets/cart_item_card.dart';

class POSCartPage extends StatefulWidget {
  const POSCartPage({super.key});

  @override
  State<POSCartPage> createState() => _POSCartPageState();
}

class _POSCartPageState extends State<POSCartPage> {
  void _proceedToPayment() {
    final posService = Provider.of<POSService>(context, listen: false);

    if (posService.hasItemsInCart) {
      context.push('/pos/payment');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header with title and actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Expanded(
                child: Text(
                  'Carrito de Compras',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Consumer<POSService>(
                builder: (context, posService, child) {
                  return IconButton(
                    onPressed: posService.hasItemsInCart
                        ? () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Limpiar Carrito'),
                                content: const Text(
                                    '¿Está seguro que desea limpiar el carrito?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      posService.clearCart();
                                      Navigator.of(context).pop();
                                      context.pop(); // Return to dashboard
                                    },
                                    child: const Text('Limpiar'),
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.clear_all),
                  );
                },
              ),
            ],
          ),
        ),

        // Content area
        Expanded(
          child: Consumer<POSService>(
            builder: (context, posService, child) {
              if (!posService.hasItemsInCart) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 100,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'El carrito está vacío',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agrega productos desde el panel principal',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Volver al Panel'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Cart items
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: posService.cartItems.length,
                      itemBuilder: (context, index) {
                        final item = posService.cartItems[index];
                        return CartItemCard(
                          item: item,
                          onRemove: () => posService.removeFromCart(item.id),
                          onQuantityChanged: (newQuantity) => posService
                              .updateCartItemQuantity(item.id, newQuantity),
                          onDiscountChanged: (discount) => posService
                              .updateCartItemDiscount(item.id, discount),
                          showControls: true,
                        );
                      },
                    ),
                  ),

                  // Cart summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outline,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Subtotal
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal:',
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              '\$${posService.cartNetAmount.toStringAsFixed(0)}',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),

                        // Discount
                        if (posService.cartDiscountAmount > 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Descuento:',
                                style: theme.textTheme.bodyLarge,
                              ),
                              Text(
                                '-\$${posService.cartDiscountAmount.toStringAsFixed(0)}',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),

                        // Tax
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'IVA (19%):',
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              '\$${posService.cartTaxAmount.toStringAsFixed(0)}',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),

                        const Divider(),

                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL:',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '\$${posService.cartTotal.toStringAsFixed(0)}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Checkout button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _proceedToPayment,
                            icon: const Icon(Icons.payment),
                            label: const Text('Proceder al Pago'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
