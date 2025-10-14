import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/services/payment_method_service.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';

class PurchasePaymentsListPage extends StatefulWidget {
  const PurchasePaymentsListPage({super.key});

  @override
  State<PurchasePaymentsListPage> createState() => _PurchasePaymentsListPageState();
}

class _PurchasePaymentsListPageState extends State<PurchasePaymentsListPage> {
  bool _isLoading = false;
  List<PurchasePayment> _payments = [];
  List<PurchasePayment> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  late PaymentMethodService _paymentMethodService;

  @override
  void initState() {
    super.initState();
    _paymentMethodService = context.read<PaymentMethodService>();
    _loadPayments();
    _searchController.addListener(_filterPayments);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPayments({bool refresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final purchaseService = context.read<PurchaseService>();
      final payments = await purchaseService.getPurchasePayments(forceRefresh: refresh);
      setState(() {
        _payments = payments;
        _filtered = payments;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar pagos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterPayments() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filtered = _payments);
      return;
    }

    final filtered = _payments.where((payment) {
      return (payment.invoiceNumber?.toLowerCase().contains(query) ?? false) ||
          (payment.supplierName?.toLowerCase().contains(query) ?? false) ||
          (payment.reference?.toLowerCase().contains(query) ?? false);
    }).toList();

    setState(() => _filtered = filtered);
  }

  String _getPaymentMethodName(String paymentMethodId) {
    final method = _paymentMethodService.getPaymentMethodById(paymentMethodId);
    return method?.name ?? 'Desconocido';
  }

  Color _getPaymentMethodColor(String paymentMethodId) {
    final method = _paymentMethodService.getPaymentMethodById(paymentMethodId);
    if (method == null) return Colors.grey;
    
    switch (method.code.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'transfer':
        return Colors.purple;
      case 'check':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = _filtered.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos de Compras'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadPayments(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and summary
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por factura, proveedor, referencia...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.background,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total: ${_filtered.length} pagos',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      ChileanUtils.formatCurrency(totalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Payments list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.payment_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _payments.isEmpty
                                  ? 'No hay pagos registrados'
                                  : 'No se encontraron pagos',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadPayments(refresh: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final payment = _filtered[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getPaymentMethodColor(payment.paymentMethodId),
                                  child: const Icon(
                                    Icons.payments,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    if (payment.invoiceNumber != null) ...[
                                      Text(
                                        payment.invoiceNumber!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getPaymentMethodColor(payment.paymentMethodId)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _getPaymentMethodName(payment.paymentMethodId),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _getPaymentMethodColor(payment.paymentMethodId),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (payment.supplierName != null)
                                      Text('Proveedor: ${payment.supplierName}'),
                                    Text(
                                      'Fecha: ${ChileanUtils.formatDate(payment.date)}',
                                    ),
                                    if (payment.reference != null &&
                                        payment.reference!.isNotEmpty)
                                      Text(
                                        'Ref: ${payment.reference}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (payment.notes != null &&
                                        payment.notes!.isNotEmpty)
                                      Text(
                                        payment.notes!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      ChileanUtils.formatCurrency(payment.amount),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      ChileanUtils.formatDate(payment.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
