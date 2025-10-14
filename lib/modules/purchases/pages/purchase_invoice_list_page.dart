import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_model_selection_dialog.dart';

class PurchaseInvoiceListPage extends StatefulWidget {
  const PurchaseInvoiceListPage({super.key});

  @override
  State<PurchaseInvoiceListPage> createState() => _PurchaseInvoiceListPageState();
}

class _PurchaseInvoiceListPageState extends State<PurchaseInvoiceListPage> {
  final TextEditingController _searchController = TextEditingController();

  late PurchaseService _purchaseService;
  List<PurchaseInvoice> _invoices = const [];
  List<PurchaseInvoice> _filtered = const [];
  bool _isLoading = true;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _purchaseService = context.read<PurchaseService>();
      _loadInvoices();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-refresh when returning to this page
    if (!_isLoading && mounted) {
      _loadInvoices(refresh: true);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices({bool refresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final invoices = await _purchaseService.getPurchaseInvoices(forceRefresh: refresh);
      setState(() {
        _invoices = invoices;
        _filtered = invoices;
        _isLoading = false;
      });
      _filterInvoices(_searchController.text);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar facturas de compra: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _filterInvoices(String query) {
    final filtered = _invoices.where((invoice) {
      final matchesSearch = query.isEmpty ||
          invoice.invoiceNumber.toLowerCase().contains(query.toLowerCase()) ||
          (invoice.supplierName?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
          (invoice.supplierRut?.toLowerCase().contains(query.toLowerCase()) ?? false);

      final matchesStatus = _selectedStatus == 'all' || invoice.status.name == _selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();

    setState(() => _filtered = filtered);
  }

  Color _statusColor(PurchaseInvoiceStatus status) {
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        return Colors.grey;
      case PurchaseInvoiceStatus.sent:
        return Colors.blue;
      case PurchaseInvoiceStatus.confirmed:
        return Colors.purple;
      case PurchaseInvoiceStatus.received:
        return Colors.green;
      case PurchaseInvoiceStatus.paid:
        return Colors.blue;
      case PurchaseInvoiceStatus.cancelled:
        return Colors.red;
    }
  }

  String _statusLabel(PurchaseInvoiceStatus status) {
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        return 'Borrador';
      case PurchaseInvoiceStatus.sent:
        return 'Enviada';
      case PurchaseInvoiceStatus.confirmed:
        return 'Confirmada';
      case PurchaseInvoiceStatus.received:
        return 'Recibida';
      case PurchaseInvoiceStatus.paid:
        return 'Pagada';
      case PurchaseInvoiceStatus.cancelled:
        return 'Anulada';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Facturas de compra',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nueva factura',
                  icon: Icons.add,
                  onPressed: () async {
                    // Show model selection dialog
                    final isPrepayment = await showPurchaseModelSelectionDialog(context);
                    
                    if (isPrepayment != null && mounted) {
                      // Navigate to form with model selection
                      final created = await context.push<bool>(
                        '/purchases/new?prepayment=$isPrepayment',
                      );
                      if (created == true) {
                        _loadInvoices(refresh: true);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                SearchBarWidget(
                  controller: _searchController,
                  hintText: 'Buscar por número, proveedor o RUT...',
                  onChanged: _filterInvoices,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Estado:'),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _selectedStatus,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedStatus = value);
                        _filterInvoices(_searchController.text);
                      },
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                        DropdownMenuItem(value: 'sent', child: Text('Enviada')),
                        DropdownMenuItem(value: 'confirmed', child: Text('Confirmada')),
                        DropdownMenuItem(value: 'received', child: Text('Recibida')),
                        DropdownMenuItem(value: 'paid', child: Text('Pagada')),
                        DropdownMenuItem(value: 'cancelled', child: Text('Anulada')),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Actualizar',
                      onPressed: () => _loadInvoices(refresh: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _EmptyState(
                        onCreate: () async {
                          // Show model selection dialog
                          final isPrepayment = await showPurchaseModelSelectionDialog(context);
                          
                          if (isPrepayment != null && mounted) {
                            // Navigate to form with model selection
                            final created = await context.push<bool>(
                              '/purchases/new?prepayment=$isPrepayment',
                            );
                            if (created == true) {
                              _loadInvoices(refresh: true);
                            }
                          }
                        },
                      )
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: () => _loadInvoices(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filtered.length,
        itemBuilder: (context, index) {
          final invoice = _filtered[index];
          final isDraft = invoice.status == PurchaseInvoiceStatus.draft;
          
          return Dismissible(
            key: Key(invoice.id ?? invoice.invoiceNumber),
            direction: isDraft ? DismissDirection.endToStart : DismissDirection.none,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              if (!isDraft) return false;
              
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Eliminar factura'),
                    ],
                  ),
                  content: Text(
                    '¿Eliminar la factura ${invoice.invoiceNumber}?\n\n'
                    'Esta acción no se puede deshacer.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Eliminar'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (direction) async {
              try {
                await _purchaseService.deletePurchaseInvoice(invoice.id!);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Factura ${invoice.invoiceNumber} eliminada'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadInvoices(refresh: true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al eliminar: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
                _loadInvoices(refresh: true);
              }
            },
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _statusColor(invoice.status),
                  child: const Icon(Icons.receipt_long, color: Colors.white),
                ),
                title: Text(
                  invoice.invoiceNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (invoice.supplierName != null && invoice.supplierName!.isNotEmpty)
                      Text(invoice.supplierName!),
                    Text('Fecha: ${ChileanUtils.formatDate(invoice.date)}'),
                    Text('Total: ${ChileanUtils.formatCurrency(invoice.total)}'),
                    // Show model indicator
                    if (invoice.prepaymentModel)
                      Row(
                        children: [
                          Icon(Icons.payment, size: 12, color: Colors.orange[700]),
                          const SizedBox(width: 4),
                          Text(
                            'Prepago',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    if (isDraft)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.swipe_left, size: 14, color: Colors.grey),
                            SizedBox(width: 4),
                            Text(
                              'Desliza para eliminar',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(invoice.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusLabel(invoice.status),
                        style: TextStyle(
                          color: _statusColor(invoice.status),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  final refreshed = await context.push<bool>('/purchases/${invoice.id}/detail');
                  if (refreshed == true) {
                    _loadInvoices(refresh: true);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay facturas de compra registradas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comienza registrando tus compras y ajustando inventario e IVA automáticamente.',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Crear factura',
            icon: Icons.add,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}
