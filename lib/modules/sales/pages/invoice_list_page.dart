import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key});

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInvoices(showErrors: true);
    });
  }

  Future<void> _refreshInvoices({bool showErrors = false}) async {
    final salesService = context.read<SalesService>();
    await salesService.loadInvoices(forceRefresh: true);

    if (!mounted || !showErrors) return;

    final error = salesService.invoiceError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() => _searchTerm = searchTerm);
  }

  // 🗑️ TEMP: Quick delete for testing (no confirmation)
  Future<void> _quickDeleteInvoice(Invoice invoice) async {
    final salesService = context.read<SalesService>();
    
    // Check if invoice has ID
    if (invoice.id == null || invoice.id!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Factura sin ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      // Delete invoice directly
      await salesService.deleteInvoice(invoice.id!);
      
      if (!mounted) return;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Factura ${invoice.invoiceNumber} eliminada'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
      
      // Refresh list
      await _refreshInvoices(showErrors: false);
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    final isLoading = salesService.isLoadingInvoices;
    final invoices = _searchTerm.isEmpty
        ? salesService.invoices
        : salesService.searchInvoices(_searchTerm);

    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Facturas',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nueva Factura',
                  icon: Icons.add,
                  onPressed: () {
                    context.push('/sales/invoices/new').then((_) {
                      _refreshInvoices(showErrors: false);
                    });
                  },
                ),
              ],
            ),
          ),
          
          // Search
          SearchWidget(
            hintText: 'Buscar por cliente o referencia...',
            onSearchChanged: _onSearchChanged,
          ),
          
          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildInvoicesList(invoices),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesList(List<Invoice> invoices) {
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty 
                  ? 'No hay facturas registradas'
                  : 'No se encontraron facturas',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Crear Primera Factura',
                onPressed: () {
                  context.push('/sales/invoices/new').then((_) {
                    _refreshInvoices(showErrors: false);
                  });
                },
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refreshInvoices(showErrors: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: invoices.length,
        itemBuilder: (context, index) {
          final invoice = invoices[index];
          return _buildInvoiceCard(invoice);
        },
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          context.push('/sales/invoices/${invoice.id}').then((_) {
            _refreshInvoices(showErrors: false);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.customerName ?? 'Cliente N/A',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (invoice.reference != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ref: ${invoice.reference}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStatusChip(invoice.status),
                ],
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ChileanUtils.formatDate(invoice.date),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    ChileanUtils.formatCurrency(invoice.total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Pagado: ${ChileanUtils.formatCurrency(invoice.paidAmount)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Saldo: ${ChileanUtils.formatCurrency(invoice.balance)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: invoice.balance <= 0
                          ? Colors.green[700]
                          : Colors.orange[800],
                    ),
                  ),
                  const Spacer(),
                  // 🗑️ TEMP: Quick delete button for testing
                  IconButton(
                    onPressed: () => _quickDeleteInvoice(invoice),
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: 'Eliminar (Testing)',
                    iconSize: 20,
                  ),
                  if (invoice.balance > 0 && invoice.status != InvoiceStatus.cancelled)
                    TextButton.icon(
                      onPressed: () {
                        context.push('/sales/invoices/${invoice.id}', extra: {'openPayment': true}).then((_) {
                          _refreshInvoices(showErrors: false);
                        });
                      },
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Pagar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(InvoiceStatus status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case InvoiceStatus.draft:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        text = 'Borrador';
        break;
      case InvoiceStatus.sent:
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        text = 'Enviada';
        break;
      case InvoiceStatus.confirmed:
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        text = 'Confirmada';
        break;
      case InvoiceStatus.paid:
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        text = 'Pagada';
        break;
      case InvoiceStatus.overdue:
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        text = 'Vencida';
        break;
      case InvoiceStatus.cancelled:
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        text = 'Cancelada';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}