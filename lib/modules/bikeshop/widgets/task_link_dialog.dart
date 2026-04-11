import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../models/bikeshop_models.dart';
import '../../sales/models/sales_models.dart';
import '../../purchases/models/purchase_invoice.dart';

class TaskLinkResult {
  final String type; // 'job', 'sales_invoice', 'purchase_invoice'
  final String id;
  final String displayId;
  final String? displayName;

  TaskLinkResult({
    required this.type,
    required this.id,
    required this.displayId,
    this.displayName,
  });
}

class TaskLinkDialog extends StatefulWidget {
  const TaskLinkDialog({super.key});

  @override
  State<TaskLinkDialog> createState() => _TaskLinkDialogState();
}

class _TaskLinkDialogState extends State<TaskLinkDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<MechanicJob> _jobs = [];
  List<Invoice> _salesInvoices = [];
  List<PurchaseInvoice> _purchaseInvoices = [];
  bool _isLoading = true;

  TaskLinkResult? _selectedResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEntities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntities() async {
    try {
      final bikeshopService = context.read<BikeshopService>();
      final salesService = context.read<SalesService>();
      final purchaseService = context.read<PurchaseService>();

      // Load recent jobs
      final jobs = await bikeshopService.getJobs();
      final recentJobs = jobs.take(50).toList();

      // Load recent sales invoices
      await salesService.loadInvoices();
      final recentSalesInvoices = salesService.cachedInvoices.take(50).toList();

      // Load recent purchase invoices
      final purchaseInvoicesReq = await purchaseService.getPurchaseInvoices();
      final recentPurchaseInvoices = purchaseInvoicesReq.take(50).toList();

      if (mounted) {
        setState(() {
          _jobs = recentJobs;
          _salesInvoices = recentSalesInvoices;
          _purchaseInvoices = recentPurchaseInvoices;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading entities for task link: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.toLowerCase();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Vincular a Tarea',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por número o nombre...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  icon: const Icon(Icons.build),
                  text: 'Pegas (${_jobs.length})',
                ),
                Tab(
                  icon: const Icon(Icons.point_of_sale),
                  text: 'Ventas (${_salesInvoices.length})',
                ),
                Tab(
                  icon: const Icon(Icons.receipt),
                  text: 'Compras (${_purchaseInvoices.length})',
                ),
              ],
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildJobsList(query),
                        _buildSalesInvoicesList(query),
                        _buildPurchaseInvoicesList(query),
                      ],
                    ),
            ),

            // Current selection
            if (_selectedResult != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedResult!.type == 'job'
                          ? Icons.build
                          : _selectedResult!.type == 'sales_invoice'
                              ? Icons.point_of_sale
                              : Icons.receipt,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seleccionado: #${_selectedResult!.displayId} ${_selectedResult!.displayName != null ? "- ${_selectedResult!.displayName}" : ""}',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedResult = null;
                      }),
                      child: const Text('Quitar'),
                    ),
                  ],
                ),
              ),

            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _selectedResult == null
                        ? null
                        : () => Navigator.of(context).pop(_selectedResult),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Vincular'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsList(String query) {
    final filtered = _jobs.where((job) {
      final jobNumber = (job.jobNumber ?? job.id ?? '').toLowerCase();
      return jobNumber.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'No hay pegas recientes' : 'Sin resultados',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final job = filtered[index];
        final isSelected =
            _selectedResult?.type == 'job' && _selectedResult?.id == job.id;
        final jobNumber = job.jobNumber ?? job.id?.substring(0, 8) ?? '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.build,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text('Pega #$jobNumber'),
          subtitle: Text('ID del Trabajo: ${job.id?.substring(0, 8) ?? ""}'),
          trailing: isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: isSelected,
          onTap: () => setState(() {
            _selectedResult = TaskLinkResult(
              type: 'job',
              id: job.id!,
              displayId: jobNumber,
              displayName: null,
            );
          }),
        );
      },
    );
  }

  Widget _buildSalesInvoicesList(String query) {
    final filtered = _salesInvoices.where((invoice) {
      final invoiceNumber = invoice.invoiceNumber.toLowerCase();
      final customerName = (invoice.customerName ?? '').toLowerCase();
      return invoiceNumber.contains(query) || customerName.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'No hay facturas de venta' : 'Sin resultados',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final invoice = filtered[index];
        final isSelected = _selectedResult?.type == 'sales_invoice' &&
            _selectedResult?.id == invoice.id;
        final invoiceNumber = invoice.invoiceNumber;
        final customerName = invoice.customerName ?? 'Sin nombre cliente';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.point_of_sale,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text('Venta #$invoiceNumber'),
          subtitle: Text(customerName),
          trailing: isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: isSelected,
          onTap: () => setState(() {
            _selectedResult = TaskLinkResult(
              type: 'sales_invoice',
              id: invoice.id!,
              displayId: invoiceNumber,
              displayName: customerName,
            );
          }),
        );
      },
    );
  }

  Widget _buildPurchaseInvoicesList(String query) {
    final filtered = _purchaseInvoices.where((invoice) {
      final invoiceNumber = invoice.invoiceNumber.toLowerCase();
      final supplierName = (invoice.supplierName ?? '').toLowerCase();
      return invoiceNumber.contains(query) || supplierName.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'No hay facturas de compra' : 'Sin resultados',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final invoice = filtered[index];
        final isSelected = _selectedResult?.type == 'purchase_invoice' &&
            _selectedResult?.id == invoice.id;
        final invoiceNumber = invoice.invoiceNumber;
        final supplierName = invoice.supplierName ?? 'Sin proveedor';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.receipt,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text('Compra #$invoiceNumber'),
          subtitle: Text(supplierName),
          trailing: isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: isSelected,
          onTap: () => setState(() {
            _selectedResult = TaskLinkResult(
              type: 'purchase_invoice',
              id: invoice.id!,
              displayId: invoiceNumber,
              displayName: supplierName,
            );
          }),
        );
      },
    );
  }
}
