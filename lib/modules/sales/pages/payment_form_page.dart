import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

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
      await salesService.loadPayments(forceRefresh: true);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    final payments = _filterPayments(salesService.payments, _searchTerm);

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
                ? const Center(child: CircularProgressIndicator())
                : payments.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () => context.read<SalesService>().loadPayments(forceRefresh: true),
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
    return payments.where((payment) {
      final reference = payment.reference?.toLowerCase() ?? '';
      final amount = payment.amount.toStringAsFixed(0);
      final method = payment.method.displayName.toLowerCase();
      return reference.contains(query) || amount.contains(query) || method.contains(query);
    }).toList();
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
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green[100],
          child: const Icon(Icons.attach_money, color: Colors.green),
        ),
        title: Text(ChileanUtils.formatCurrency(payment.amount)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${payment.method.displayName} · ${ChileanUtils.formatDate(payment.date)}'),
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
}