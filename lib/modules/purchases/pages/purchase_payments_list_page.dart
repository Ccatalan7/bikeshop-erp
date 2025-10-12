import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/themes/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
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

  Color _getMethodColor(String method) {
    switch (method.toLowerCase()) {
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

  String _getMethodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'check':
        return 'Cheque';
      default:
        return 'Otro';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    final totalAmount = _filtered.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos de Compras', maxLines: 1, overflow: TextOverflow.ellipsis),
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
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: isMobile ? 'Buscar...' : 'Buscar por factura, proveedor, referencia...',
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
                SizedBox(height: isMobile ? 8 : 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Total: ${_filtered.length} pagos',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        ChileanUtils.formatCurrency(totalAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                                  backgroundColor: _getMethodColor(payment.method),
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
                                        color: _getMethodColor(payment.method)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _getMethodLabel(payment.method),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _getMethodColor(payment.method),
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
