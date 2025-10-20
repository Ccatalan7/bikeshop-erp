import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';

class OrderConfirmationPage extends StatefulWidget {
  final String orderId;

  const OrderConfirmationPage({super.key, required this.orderId});

  @override
  State<OrderConfirmationPage> createState() => _OrderConfirmationPageState();
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage> {
  OnlineOrder? _order;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websiteService = Provider.of<WebsiteService>(context, listen: false);
      final order = await websiteService.getOrderById(widget.orderId);

      setState(() {
        _order = order;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar el pedido: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _order == null
                  ? _buildNotFound()
                  : _buildConfirmation(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(fontSize: 16, color: PublicStoreTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/tienda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PublicStoreTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Volver al Inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 64, color: PublicStoreTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Pedido no encontrado',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'No pudimos encontrar este pedido.',
              style: TextStyle(fontSize: 16, color: PublicStoreTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/tienda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PublicStoreTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Volver al Inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    final order = _order!;

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Success Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 24),

              // Thank You Message
              const Text(
                '¡Pedido Recibido!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: PublicStoreTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Gracias por tu compra. Hemos recibido tu pedido y lo procesaremos pronto.',
                style: TextStyle(
                  fontSize: 16,
                  color: PublicStoreTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Order Details Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Número de Pedido',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            order.orderNumber,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: PublicStoreTheme.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),

                      // Customer Info
                      _buildInfoRow('Nombre', order.customerName),
                      _buildInfoRow('Email', order.customerEmail),
                      if (order.customerPhone != null)
                        _buildInfoRow('Teléfono', order.customerPhone!),
                      if (order.customerAddress != null)
                        _buildInfoRow('Dirección', order.customerAddress!),
                      const Divider(height: 32),

                      // Order Items
                      const Text(
                        'Productos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...order.items.map((item) => _buildOrderItem(item)),
                      const Divider(height: 32),

                      // Totals
                      _buildTotalRow('Subtotal', order.subtotal),
                      _buildTotalRow('IVA (19%)', order.taxAmount),
                      if (order.shippingCost > 0)
                        _buildTotalRow('Envío', order.shippingCost),
                      if (order.discountAmount > 0)
                        _buildTotalRow('Descuento', -order.discountAmount),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PublicStoreTheme.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              ChileanUtils.formatCurrency(order.total),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: PublicStoreTheme.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Payment Instructions (if payment method is transfer)
              if (order.paymentMethod == 'transfer')
                Card(
                  elevation: 2,
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
                            SizedBox(width: 8),
                            Text(
                              'Instrucciones de Pago',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Para completar tu pedido, realiza una transferencia bancaria a:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentInfo('Banco', 'Banco de Chile'),
                        _buildPaymentInfo('Cuenta Corriente', '1234567890'),
                        _buildPaymentInfo('RUT', '12.345.678-9'),
                        _buildPaymentInfo('Nombre', 'Vinabike SpA'),
                        _buildPaymentInfo('Monto', ChileanUtils.formatCurrency(order.total)),
                        const SizedBox(height: 12),
                        const Text(
                          'Una vez realizada la transferencia, envía el comprobante a ventas@vinabike.cl con tu número de pedido.',
                          style: TextStyle(
                            fontSize: 12,
                            color: PublicStoreTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // What's Next
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¿Qué sigue?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildNextStep(
                        Icons.email_outlined,
                        'Te enviaremos un email de confirmación con los detalles de tu pedido.',
                      ),
                      _buildNextStep(
                        Icons.local_shipping_outlined,
                        'Procesaremos tu pedido en 1-2 días hábiles.',
                      ),
                      _buildNextStep(
                        Icons.phone_outlined,
                        'Te contactaremos si necesitamos más información.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go('/tienda/productos'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: PublicStoreTheme.primaryBlue),
                      ),
                      child: const Text('Seguir Comprando'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.go('/tienda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PublicStoreTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Volver al Inicio'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: PublicStoreTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OnlineOrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.productSku != null)
                  Text(
                    'SKU: ${item.productSku}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: PublicStoreTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'x${item.quantity}',
            style: const TextStyle(
              fontSize: 14,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          Text(
            ChileanUtils.formatCurrency(amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: PublicStoreTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
