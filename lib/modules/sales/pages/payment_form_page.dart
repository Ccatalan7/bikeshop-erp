import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/payment_method_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key, this.highlightPaymentId});

  final String? highlightPaymentId;

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  String _searchTerm = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final salesService = context.read<SalesService>();
      final paymentMethodService = context.read<PaymentMethodService>();

      // Load both payments and payment methods in parallel
      await Future.wait([
        salesService.loadPayments(forceRefresh: true),
        paymentMethodService.loadPaymentMethods(),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    // Watch payment methods to trigger rebuild when loaded
    context.watch<PaymentMethodService>();
    final payments = _prioritizeHighlightedPayment(
      _filterPayments(salesService.payments, _searchTerm),
    );

    return MainLayout(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pagos',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => context.push('/sales/invoices'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  tooltip: 'Ver facturas',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchWidget(
              hintText: 'Buscar por cliente, referencia o monto...',
              onSearchChanged: (value) => setState(() => _searchTerm = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : payments.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () => context
                            .read<SalesService>()
                            .loadPayments(forceRefresh: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: payments.length,
                          itemBuilder: (context, index) {
                            final payment = payments[index];
                            return _buildPaymentTile(payment);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  List<Payment> _filterPayments(List<Payment> payments, String term) {
    if (term.isEmpty) return payments;
    final query = term.toLowerCase();
    final paymentMethodService = context.read<PaymentMethodService>();

    return payments.where((payment) {
      final paymentNumber = _paymentNumber(payment)?.toLowerCase() ?? '';
      final reference = payment.reference?.toLowerCase() ?? '';
      final invoiceReference = payment.invoiceReference?.toLowerCase() ?? '';
      final amount = payment.amount.toStringAsFixed(0);
      final paymentMethod =
          paymentMethodService.getPaymentMethodById(payment.paymentMethodId);
      final method = paymentMethod?.name.toLowerCase() ?? '';
      return paymentNumber.contains(query) ||
          invoiceReference.contains(query) ||
          reference.contains(query) ||
          amount.contains(query) ||
          method.contains(query);
    }).toList();
  }

  List<Payment> _prioritizeHighlightedPayment(List<Payment> payments) {
    final highlightId = widget.highlightPaymentId;
    if (highlightId == null || highlightId.isEmpty) return payments;

    final index = payments.indexWhere((payment) => payment.id == highlightId);
    if (index <= 0) return payments;

    return [
      payments[index],
      ...payments.take(index),
      ...payments.skip(index + 1),
    ];
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payments_outlined, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Aún no hay pagos registrados',
            style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Los pagos ingresados desde las facturas aparecerán aquí automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTile(Payment payment) {
    final paymentMethodService = context.read<PaymentMethodService>();
    final paymentMethod =
        paymentMethodService.getPaymentMethodById(payment.paymentMethodId);
    final methodName = paymentMethod?.name ?? 'Desconocido';
    final theme = Theme.of(context);
    final isHighlighted = payment.id == widget.highlightPaymentId;
    final paymentNumber = _paymentNumber(payment);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isHighlighted
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isHighlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.65)
              : Colors.transparent,
          width: isHighlighted ? 1.2 : 0,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green[100],
          child: const Icon(Icons.attach_money, color: Colors.green),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (paymentNumber != null) _buildPaymentCodeChip(paymentNumber),
            Text(
              ChileanUtils.formatCurrency(payment.amount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (payment.invoiceReference != null &&
                payment.invoiceReference!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  payment.invoiceReference!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$methodName · ${ChileanUtils.formatDate(payment.date)}'),
            if (payment.reference != null && payment.reference!.isNotEmpty)
              Text('Ref: ${payment.reference}'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.push('/sales/invoices/${payment.invoiceId}');
        },
      ),
    );
  }

  Widget _buildPaymentCodeChip(String value) {
    return Text(
      value,
      style: const TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        fontFamily: 'monospace',
      ),
    );
  }

  String? _paymentNumber(Payment payment) {
    final id = payment.id;
    if (id == null || id.isEmpty) return null;

    final compact = id.replaceAll('-', '').toUpperCase();
    final suffix = compact.length <= 6
        ? compact.padLeft(6, '0')
        : compact.substring(compact.length - 6);
    return 'COB-$suffix';
  }
}
