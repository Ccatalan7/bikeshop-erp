import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/payment_method.dart' as pm;
import '../../../shared/services/payment_method_service.dart';
import '../../sales/models/sales_models.dart';

/// Invoice payment layout for POS
/// Shows invoice details with expandable line items and payment block
class InvoicePaymentLayout extends StatefulWidget {
  final Invoice invoice;
  final VoidCallback onCancel;
  final Function(double amount, pm.PaymentMethod paymentMethod) onPayment;

  const InvoicePaymentLayout({
    super.key,
    required this.invoice,
    required this.onCancel,
    required this.onPayment,
  });

  @override
  State<InvoicePaymentLayout> createState() => _InvoicePaymentLayoutState();
}

class _InvoicePaymentLayoutState extends State<InvoicePaymentLayout> {
  final TextEditingController _amountController = TextEditingController();
  pm.PaymentMethod? _selectedPaymentMethod;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize amount with invoice balance
    _amountController.text = widget.invoice.balance.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _handlePayment() async {
    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un método de pago'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount > widget.invoice.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El monto no puede ser mayor al saldo pendiente (\$${widget.invoice.balance.toStringAsFixed(0)})',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await widget.onPayment(amount, _selectedPaymentMethod!);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Column(
      children: [
        // Header Card
        Card(
          margin: const EdgeInsets.all(16),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FACTURA ${widget.invoice.invoiceNumber}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.invoice.customerName ?? 'Cliente General',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(widget.invoice.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _getStatusColor(widget.invoice.status),
                        ),
                      ),
                      child: Text(
                        _getStatusLabel(widget.invoice.status),
                        style: TextStyle(
                          color: _getStatusColor(widget.invoice.status),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        'Fecha',
                        dateFormat.format(widget.invoice.date),
                        theme,
                      ),
                    ),
                    if (widget.invoice.dueDate != null)
                      Expanded(
                        child: _buildInfoItem(
                          'Vencimiento',
                          dateFormat.format(widget.invoice.dueDate!),
                          theme,
                        ),
                      ),
                    if (widget.invoice.reference != null && widget.invoice.reference!.isNotEmpty)
                      Expanded(
                        child: _buildInfoItem(
                          'Referencia',
                          widget.invoice.reference!,
                          theme,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Expandable Line Items
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    'Ver Detalle (${widget.invoice.items.length} items)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.invoice.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.invoice.items[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                '${item.quantity.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(item.productName ?? 'Sin nombre'),
                            subtitle: Text(
                              '${item.quantity} x ${currencyFormat.format(item.unitPrice)}',
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: Text(
                              currencyFormat.format(item.lineTotal),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Financial Summary
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildFinancialRow('Subtotal', widget.invoice.subtotal, theme),
                        _buildFinancialRow('IVA (19%)', widget.invoice.ivaAmount, theme),
                        const Divider(height: 16),
                        _buildFinancialRow(
                          'Total',
                          widget.invoice.total,
                          theme,
                          isTotal: true,
                        ),
                        _buildFinancialRow('Pagado', widget.invoice.paidAmount, theme,
                            color: Colors.green),
                        const Divider(height: 16, thickness: 2),
                        _buildFinancialRow(
                          'SALDO A PAGAR',
                          widget.invoice.balance,
                          theme,
                          isBalance: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Payment Block
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.payment, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'PROCESAR PAGO',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Payment Method Selector
                        Consumer<PaymentMethodService>(
                          builder: (context, paymentMethodService, child) {
                            final methods = paymentMethodService.paymentMethods;
                            if (methods.isEmpty) {
                              return const Text('No hay métodos de pago disponibles');
                            }

                            return DropdownButtonFormField<pm.PaymentMethod>(
                              value: _selectedPaymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'Método de Pago',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.credit_card),
                              ),
                              items: methods.map((method) {
                                return DropdownMenuItem(
                                  value: method,
                                  child: Text(method.name),
                                );
                              }).toList(),
                              onChanged: _isProcessing
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _selectedPaymentMethod = value;
                                      });
                                    },
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Amount Input
                        TextFormField(
                          controller: _amountController,
                          enabled: !_isProcessing,
                          decoration: InputDecoration(
                            labelText: 'Monto a Pagar',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.attach_money),
                            prefixText: '\$ ',
                            helperText:
                                'Saldo pendiente: ${currencyFormat.format(widget.invoice.balance)}',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Pagar saldo completo',
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      _amountController.text =
                                          widget.invoice.balance.toStringAsFixed(0);
                                    },
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Partial payment hint
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '💡 Pago Parcial: Ingresa un monto menor al saldo para hacer un pago parcial',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Action Buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _handlePayment,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.payment),
                  label: Text(_isProcessing ? 'Procesando...' : '💳 Registrar Pago'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialRow(
    String label,
    double amount,
    ThemeData theme, {
    bool isTotal = false,
    bool isBalance = false,
    Color? color,
  }) {
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isTotal || isBalance ? FontWeight.bold : FontWeight.normal,
              fontSize: isBalance ? 18 : (isTotal ? 16 : 14),
            ),
          ),
          Text(
            currencyFormat.format(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isTotal || isBalance ? FontWeight.bold : FontWeight.w500,
              fontSize: isBalance ? 20 : (isTotal ? 16 : 14),
              color: color ?? (isBalance ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return Colors.grey;
      case InvoiceStatus.sent:
        return Colors.blue;
      case InvoiceStatus.confirmed:
        return Colors.orange;
      case InvoiceStatus.paid:
        return Colors.green;
      case InvoiceStatus.overdue:
        return Colors.red;
      case InvoiceStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Cancelada';
    }
  }
}
