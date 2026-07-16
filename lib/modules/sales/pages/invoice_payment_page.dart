import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';
import '../widgets/payment_form.dart' show PaymentForm;

class InvoicePaymentPage extends StatefulWidget {
  const InvoicePaymentPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<InvoicePaymentPage> createState() => _InvoicePaymentPageState();
}

class _InvoicePaymentPageState extends State<InvoicePaymentPage> {
  bool _isLoading = true;
  Invoice? _invoice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInvoice());
  }

  Future<void> _loadInvoice() async {
    final salesService = context.read<SalesService>();
    final invoice =
        await salesService.fetchInvoice(widget.invoiceId, refresh: true);
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _isLoading = false;
    });
  }

  void _returnToInvoice({bool refresh = false}) {
    if (refresh) {
      GoRouter.of(context).pop(true);
    } else {
      GoRouter.of(context).pop();
    }
  }

  double _effectiveBalance(Invoice invoice) {
    final calculated =
        (invoice.total - invoice.paidAmount).clamp(0.0, invoice.total);
    return calculated.abs() < 1 ? 0 : calculated;
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _isLoading
          ? const Center(child: BrandedLoading())
          : _invoice == null
              ? _buildNotFound()
              : _buildContent(context, _invoice!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long, size: 64),
          const SizedBox(height: 16),
          const Text('Factura no encontrada'),
          const SizedBox(height: 16),
          AppButton(
            text: 'Volver',
            onPressed: _returnToInvoice,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, Invoice invoice) {
    final theme = Theme.of(context);
    final effectiveBalance = _effectiveBalance(invoice);
    final isSettled = effectiveBalance <= 0.01;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final padding =
            isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

        return SingleChildScrollView(
          padding: padding,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 560,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _returnToInvoice,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Volver',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.invoiceNumber.isNotEmpty
                                  ? 'Factura ${invoice.invoiceNumber}'
                                  : 'Factura',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              invoice.customerName ?? 'Cliente',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: padding, // Use same padding logic
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saldo pendiente: ${ChileanUtils.formatCurrency(effectiveBalance)}',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total factura: ${ChileanUtils.formatCurrency(invoice.total)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (invoice.dueDate != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Vence el ${ChileanUtils.formatDate(invoice.dueDate!)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isSettled)
                    Card(
                      color: theme.colorScheme.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Colors.green.shade600.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Padding(
                        padding: padding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 48,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Factura pagada',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'No hay saldo pendiente. El documento tributario y sus pagos ya están registrados.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 20),
                            AppButton(
                              text: 'Volver a la factura',
                              onPressed: _returnToInvoice,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    PaymentForm(
                      invoice: invoice,
                      dismissOnSubmit: false,
                      onCompleted: () => _returnToInvoice(refresh: true),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
