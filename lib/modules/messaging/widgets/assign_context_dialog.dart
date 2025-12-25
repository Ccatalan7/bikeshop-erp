import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/services/sales_service.dart';
import '../services/messaging_service.dart';

/// Dialog to assign/link a conversation to a Job or Invoice
class AssignContextDialog extends StatefulWidget {
  final String conversationId;
  final String? currentContextType;
  final String? currentContextId;

  const AssignContextDialog({
    super.key,
    required this.conversationId,
    this.currentContextType,
    this.currentContextId,
  });

  @override
  State<AssignContextDialog> createState() => _AssignContextDialogState();
}

class _AssignContextDialogState extends State<AssignContextDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _jobs = [];
  List<dynamic> _invoices = [];
  bool _isLoading = true;
  String? _selectedType;
  String? _selectedId;
  String? _selectedLabel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedType = widget.currentContextType;
    _selectedId = widget.currentContextId;
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
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final salesService = Provider.of<SalesService>(context, listen: false);

      // Load recent jobs (last 50)
      final jobs = await bikeshopService.getJobs();
      final recentJobs = jobs.take(50).toList();

      // Load recent invoices (last 50)
      await salesService.loadInvoices();
      final recentInvoices = salesService.cachedInvoices.take(50).toList();

      if (mounted) {
        setState(() {
          _jobs = recentJobs;
          _invoices = recentInvoices;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading entities: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveContext() async {
    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);

      await messagingService.updateConversationContext(
        conversationId: widget.conversationId,
        contextType: _selectedType,
        contextId: _selectedId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedType != null
                ? 'Chat vinculado a $_selectedLabel'
                : 'Vínculo removido'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.toLowerCase();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
                    'Vincular Chat',
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
                  hintText: 'Buscar...',
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
                  text: 'Trabajos (${_jobs.length})',
                ),
                Tab(
                  icon: const Icon(Icons.receipt),
                  text: 'Facturas (${_invoices.length})',
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
                        _buildInvoicesList(query),
                      ],
                    ),
            ),

            // Current selection
            if (_selectedType != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedType == 'job' ? Icons.build : Icons.receipt,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seleccionado: $_selectedLabel',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _selectedType = null;
                        _selectedId = null;
                        _selectedLabel = null;
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
                    onPressed: _saveContext,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Guardar'),
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
          query.isEmpty ? 'No hay trabajos' : 'Sin resultados',
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
        final isSelected = _selectedType == 'job' && _selectedId == job.id;
        final jobNumber =
            job.jobNumber ?? job.id?.substring(0, 8) ?? 'Sin número';

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
          title: Text('Trabajo #$jobNumber'),
          subtitle: Text('ID: ${job.id?.substring(0, 8) ?? ""}'),
          trailing: isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: isSelected,
          onTap: () => setState(() {
            _selectedType = 'job';
            _selectedId = job.id;
            _selectedLabel = 'Trabajo #$jobNumber';
          }),
        );
      },
    );
  }

  Widget _buildInvoicesList(String query) {
    final filtered = _invoices.where((invoice) {
      final invoiceNumber = (invoice.invoiceNumber ?? '').toLowerCase();
      final customerName = (invoice.customerName ?? '').toLowerCase();
      return invoiceNumber.contains(query) || customerName.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'No hay facturas' : 'Sin resultados',
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
        final isSelected =
            _selectedType == 'invoice' && _selectedId == invoice.id;
        final invoiceNumber = invoice.invoiceNumber ?? 'Sin número';
        final customerName = invoice.customerName ?? 'Sin cliente';

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
          title: Text('Factura #$invoiceNumber'),
          subtitle: Text(customerName),
          trailing: isSelected
              ? Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary)
              : null,
          selected: isSelected,
          onTap: () => setState(() {
            _selectedType = 'invoice';
            _selectedId = invoice.id;
            _selectedLabel = 'Factura #$invoiceNumber';
          }),
        );
      },
    );
  }
}
