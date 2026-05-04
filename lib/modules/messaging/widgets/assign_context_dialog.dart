import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
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

  List<MechanicJob> _jobs = [];
  List<Invoice> _invoices = [];
  Map<String, Customer> _customersById = {};
  Map<String, Bike> _bikesById = {};
  Map<String, List<MechanicJobBike>> _jobBikesByJobId = {};
  Map<String, Invoice> _invoicesById = {};
  bool _isLoading = true;
  String? _selectedType;
  String? _selectedId;
  String? _selectedLabel;
  String _jobStatusFilter = 'active';
  bool _showOnlyOverdueJobs = false;
  bool _showOnlyUnpaidJobs = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedType = widget.currentContextType;
    _selectedId = widget.currentContextId;
    if (_selectedType == 'invoice') {
      _tabController.index = 1;
    }
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
      final customerService =
          Provider.of<CustomerService>(context, listen: false);

      var jobs = <MechanicJob>[];
      var jobBikes = <String, List<MechanicJobBike>>{};
      var bikes = <Bike>[];
      var customers = <Customer>[];

      await Future.wait<void>([
        () async {
          jobs = await bikeshopService.getJobs();
        }(),
        () async {
          jobBikes = await bikeshopService.getAllJobBikes();
        }(),
        () async {
          bikes = await bikeshopService.getBikes();
        }(),
        () async {
          customers = await customerService.getCustomersForList();
        }(),
        () async {
          await salesService.loadInvoices();
        }(),
      ]);

      final customersById = <String, Customer>{
        for (final customer in customers)
          if (customer.id != null) customer.id!: customer,
      };
      final bikesById = <String, Bike>{
        for (final bike in bikes)
          if (bike.id != null) bike.id!: bike,
      };
      final invoicesById = <String, Invoice>{
        for (final invoice in salesService.cachedInvoices)
          if (invoice.id != null) invoice.id!: invoice,
      };

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _invoices = salesService.cachedInvoices;
          _customersById = customersById;
          _bikesById = bikesById;
          _jobBikesByJobId = jobBikes;
          _invoicesById = invoicesById;
          _resolveSelectedLabel();
          _syncJobFilterToSelectedJob();
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

      final label = _selectedLabel ?? _fallbackSelectedLabel();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_selectedType != null
                ? 'Chat vinculado a $label'
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
    final query = _searchController.text.trim().toLowerCase();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.link, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vincular chat',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Asocia esta conversación al trabajo o factura que corresponde.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Buscar por cliente, bicicleta, trabajo o factura',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar búsqueda',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                }),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loadEntities,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.build_outlined),
                      text: 'Trabajos (${_jobs.length})',
                    ),
                    Tab(
                      icon: const Icon(Icons.receipt_long_outlined),
                      text: 'Facturas (${_invoices.length})',
                    ),
                  ],
                ),
              ),
            ),
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
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildSelectionSummary(context)),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: _saveContext,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Guardar vínculo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSummary(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = _selectedType != null && _selectedId != null;
    final label = _selectedLabel ?? _fallbackSelectedLabel();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasSelection
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasSelection
              ? theme.colorScheme.primary.withValues(alpha: 0.22)
              : theme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasSelection ? _contextIcon(_selectedType) : Icons.link_off,
            size: 18,
            color: hasSelection
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasSelection ? label : 'Sin vínculo seleccionado',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
                color: hasSelection
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasSelection) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                _selectedType = null;
                _selectedId = null;
                _selectedLabel = null;
              }),
              child: const Text('Quitar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobsList(String query) {
    final filtered = _filterJobs(query);

    return Column(
      children: [
        _buildJobFilterBar(query, filtered.length),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(
                  icon: Icons.build_outlined,
                  title: query.isEmpty
                      ? 'No hay trabajos en este filtro'
                      : 'Sin trabajos',
                  message: query.isEmpty
                      ? 'Cambia el filtro de estado para revisar otros trabajos.'
                      : 'Prueba buscar por cliente, bicicleta, número de trabajo o solicitud.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final job = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildJobCard(job),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildJobFilterBar(String query, int filteredCount) {
    final theme = Theme.of(context);
    final hasExtraFilters = _jobStatusFilter != 'active' ||
        _showOnlyOverdueJobs ||
        _showOnlyUnpaidJobs ||
        query.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: _buildJobStatusSegments(query),
              selected: <String>{_jobStatusFilter},
              onSelectionChanged: (selected) {
                if (selected.isEmpty) return;
                setState(() => _jobStatusFilter = selected.first);
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildResultCountChip(filteredCount),
              FilterChip(
                label: const Text('Vencidos'),
                selected: _showOnlyOverdueJobs,
                avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                onSelected: (selected) => setState(() {
                  _showOnlyOverdueJobs = selected;
                }),
              ),
              FilterChip(
                label: const Text('Sin pagar'),
                selected: _showOnlyUnpaidJobs,
                avatar: const Icon(Icons.payments_outlined, size: 16),
                onSelected: (selected) => setState(() {
                  _showOnlyUnpaidJobs = selected;
                }),
              ),
              if (hasExtraFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _jobStatusFilter = 'active';
                    _showOnlyOverdueJobs = false;
                    _showOnlyUnpaidJobs = false;
                    _searchController.clear();
                  }),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Limpiar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<ButtonSegment<String>> _buildJobStatusSegments(String query) {
    const labels = <String, String>{
      'active': 'Activos',
      'completed': 'Completados',
      'delivered': 'Entregados',
      'warranty_completed': 'Garantías',
      'unpaid': 'Sin pagar',
      'all': 'Todos',
    };

    return labels.entries.map((entry) {
      final count = _jobCountForStatus(entry.key, query);
      return ButtonSegment<String>(
        value: entry.key,
        label: Text(
          '${entry.value} ($count)',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }).toList();
  }

  Widget _buildResultCountChip(int count) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count de ${_jobs.length} trabajos',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInvoicesList(String query) {
    final filtered = _filterInvoices(query);

    if (filtered.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long_outlined,
        title: query.isEmpty ? 'No hay facturas cargadas' : 'Sin facturas',
        message: query.isEmpty
            ? 'No encontramos facturas para vincular.'
            : 'Prueba buscar por cliente, número de factura, estado o monto.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final invoice = filtered[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildInvoiceCard(invoice),
        );
      },
    );
  }

  Widget _buildJobCard(MechanicJob job) {
    final theme = Theme.of(context);
    final isSelected = _selectedType == 'job' && _selectedId == job.id;
    final statusColor = job.colorValue;
    final jobNumber = _jobNumber(job);
    final customerName = _customerNameForJob(job);
    final bikeTitle = _bikeTitleForJob(job);
    final bikeMeta = _bikeMetaForJob(job);
    final request =
        _firstNonEmpty([job.clientRequest, job.diagnosis, job.notes]);
    final isInvoiced = _isJobInvoicedEffective(job);
    final isPaid = _isJobPaidEffective(job);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.55)
              : theme.dividerColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _selectedType = 'job';
          _selectedId = job.id;
          _selectedLabel = _jobSelectionLabel(job);
        }),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEntityIcon(
                icon: Icons.build_outlined,
                selected: isSelected,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            customerName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildStatusPill(job.statusDisplayName, statusColor),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bikeTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildMetaPill(Icons.tag, 'Trabajo #$jobNumber'),
                        _buildMetaPill(
                          Icons.event_available_outlined,
                          'Ingreso ${ChileanUtils.formatDate(job.arrivalDate)}',
                        ),
                        if (job.totalCost > 0)
                          _buildMetaPill(
                            Icons.payments_outlined,
                            ChileanUtils.formatCurrency(job.totalCost),
                          ),
                        if (isInvoiced)
                          _buildMetaPill(
                            Icons.receipt_long_outlined,
                            isPaid ? 'Pagado' : 'Sin pagar',
                          ),
                        if (job.isOverdue)
                          _buildMetaPill(
                            Icons.warning_amber_rounded,
                            'Vencido',
                          ),
                        ...bikeMeta.map(
                          (meta) => _buildMetaPill(Icons.pedal_bike, meta),
                        ),
                      ],
                    ),
                    if (request != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        request,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildSelectionIndicator(isSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    final theme = Theme.of(context);
    final isSelected = _selectedType == 'invoice' && _selectedId == invoice.id;
    final statusColor = _invoiceStatusColor(invoice.status);
    final invoiceNumber = _invoiceNumber(invoice);
    final customerName = _invoiceCustomerName(invoice);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.55)
              : theme.dividerColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _selectedType = 'invoice';
          _selectedId = invoice.id;
          _selectedLabel = _invoiceSelectionLabel(invoice);
        }),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEntityIcon(
                icon: Icons.receipt_long_outlined,
                selected: isSelected,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            customerName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildStatusPill(
                          _invoiceStatusLabel(invoice.status),
                          statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Factura #$invoiceNumber',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildMetaPill(
                          Icons.event_outlined,
                          ChileanUtils.formatDate(invoice.date),
                        ),
                        _buildMetaPill(
                          Icons.payments_outlined,
                          ChileanUtils.formatCurrency(invoice.total),
                        ),
                        if (invoice.balance > 0)
                          _buildMetaPill(
                            Icons.account_balance_wallet_outlined,
                            'Saldo ${ChileanUtils.formatCurrency(invoice.balance)}',
                          ),
                        if (invoice.jobNumber != null &&
                            invoice.jobNumber!.trim().isNotEmpty)
                          _buildMetaPill(
                            Icons.build_outlined,
                            'Trabajo #${invoice.jobNumber!.trim()}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildSelectionIndicator(isSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntityIcon({required IconData icon, required bool selected}) {
    final theme = Theme.of(context);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 20,
        color: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSelectionIndicator(bool isSelected) {
    final theme = Theme.of(context);
    return Icon(
      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
      color: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.outline.withValues(alpha: 0.55),
      size: 22,
    );
  }

  Widget _buildStatusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<MechanicJob> _filterJobs(String query) {
    return _jobs.where((job) {
      if (!_jobMatchesStatusFilter(job, _jobStatusFilter)) return false;
      if (_showOnlyOverdueJobs && !job.isOverdue) return false;
      if (_showOnlyUnpaidJobs &&
          (_isJobPaidEffective(job) || !_isJobInvoicedEffective(job))) {
        return false;
      }
      if (query.isNotEmpty && !_jobSearchText(job).contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  int _jobCountForStatus(String statusFilter, String query) {
    return _jobs.where((job) {
      if (!_jobMatchesStatusFilter(job, statusFilter)) return false;
      if (query.isNotEmpty && !_jobSearchText(job).contains(query)) {
        return false;
      }
      return true;
    }).length;
  }

  bool _jobMatchesStatusFilter(MechanicJob job, String statusFilter) {
    final isInvoiced = _isJobInvoicedEffective(job);
    final isPaid = _isJobPaidEffective(job);
    final isDelivered = _isJobDelivered(job);
    final isFinishedWarranty = _isFinishedWarrantyJob(job);
    final jobPhase = _jobPhase(job);

    switch (statusFilter) {
      case 'active':
        if (job.status == JobStatus.cancelado) return false;
        if (isDelivered && isInvoiced && isPaid) return false;
        if (isFinishedWarranty) return false;
        return true;
      case 'completed':
        return jobPhase == StatusPhase.complete &&
            !isDelivered &&
            job.status != JobStatus.cancelado;
      case 'delivered':
        return isDelivered;
      case 'warranty_completed':
        return isFinishedWarranty;
      case 'unpaid':
        return isInvoiced && !isPaid;
      case 'all':
      default:
        return true;
    }
  }

  void _syncJobFilterToSelectedJob() {
    if (_selectedType != 'job' || _selectedId == null) return;
    for (final job in _jobs) {
      if (job.id != _selectedId) continue;
      if (_jobMatchesStatusFilter(job, _jobStatusFilter)) return;

      const filters = <String>[
        'active',
        'unpaid',
        'delivered',
        'warranty_completed',
        'completed',
        'all',
      ];
      for (final filter in filters) {
        if (_jobMatchesStatusFilter(job, filter)) {
          _jobStatusFilter = filter;
          return;
        }
      }
    }
  }

  Invoice? _invoiceForJob(MechanicJob job) {
    final invoiceId = job.invoiceId;
    if (invoiceId == null) return null;
    return _invoicesById[invoiceId];
  }

  bool _isJobInvoicedEffective(MechanicJob job) {
    return job.invoiceId != null || job.isInvoiced;
  }

  bool _isJobPaidEffective(MechanicJob job) {
    final invoice = _invoiceForJob(job);
    if (invoice != null) return invoice.status == InvoiceStatus.paid;
    return job.isPaid;
  }

  bool _isJobDelivered(MechanicJob job) {
    return job.deliveredAt != null ||
        job.status == JobStatus.entregado ||
        job.customStatus?.code.toLowerCase() == 'entregado';
  }

  bool _isFinishedWarrantyJob(MechanicJob job) {
    return job.isWarrantyJob &&
        _isJobDelivered(job) &&
        (job.totalCost <= 0 ||
            (_isJobInvoicedEffective(job) && _isJobPaidEffective(job)));
  }

  StatusPhase _jobPhase(MechanicJob job) {
    return job.customStatus?.phase ?? _inferPhaseFromLegacyStatus(job.status);
  }

  StatusPhase _inferPhaseFromLegacyStatus(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return StatusPhase.todo;
      case JobStatus.diagnostico:
      case JobStatus.esperandoAprobacion:
      case JobStatus.esperandoRepuestos:
      case JobStatus.enCurso:
        return StatusPhase.inProgress;
      case JobStatus.finalizado:
      case JobStatus.entregado:
      case JobStatus.cancelado:
        return StatusPhase.complete;
    }
  }

  List<Invoice> _filterInvoices(String query) {
    if (query.isEmpty) return _invoices;
    return _invoices
        .where((invoice) => _invoiceSearchText(invoice).contains(query))
        .toList();
  }

  String _jobSearchText(MechanicJob job) {
    final bikes = _bikesForJob(job);
    final parts = <String>[
      _jobNumber(job),
      _customerNameForJob(job),
      _bikeTitleForJob(job),
      job.statusDisplayName,
      job.clientRequest ?? '',
      job.diagnosis ?? '',
      job.notes ?? '',
      job.subjectDisplayName ?? '',
      job.id ?? '',
      for (final bike in bikes) ...[
        bike.brand ?? '',
        bike.model ?? '',
        bike.serialNumber ?? '',
        bike.color ?? '',
        bike.frameSize ?? '',
        bike.wheelSize ?? '',
      ],
    ];
    return parts.join(' ').toLowerCase();
  }

  String _invoiceSearchText(Invoice invoice) {
    return [
      _invoiceNumber(invoice),
      _invoiceCustomerName(invoice),
      _invoiceStatusLabel(invoice.status),
      invoice.reference ?? '',
      invoice.jobNumber ?? '',
      invoice.id ?? '',
      ChileanUtils.formatCurrency(invoice.total),
    ].join(' ').toLowerCase();
  }

  void _resolveSelectedLabel() {
    if (_selectedType == null || _selectedId == null) {
      _selectedLabel = null;
      return;
    }

    if (_selectedType == 'job') {
      for (final job in _jobs) {
        if (job.id == _selectedId) {
          _selectedLabel = _jobSelectionLabel(job);
          return;
        }
      }
    }

    if (_selectedType == 'invoice') {
      for (final invoice in _invoices) {
        if (invoice.id == _selectedId) {
          _selectedLabel = _invoiceSelectionLabel(invoice);
          return;
        }
      }
    }

    _selectedLabel = _fallbackSelectedLabel();
  }

  String _fallbackSelectedLabel() {
    if (_selectedType == null || _selectedId == null) return '';
    final typeLabel = _selectedType == 'invoice' ? 'Factura' : 'Trabajo';
    return '$typeLabel ${_shortId(_selectedId)}';
  }

  IconData _contextIcon(String? type) {
    if (type == 'invoice') return Icons.receipt_long_outlined;
    return Icons.build_outlined;
  }

  String _jobNumber(MechanicJob job) {
    final value = job.jobNumber?.trim();
    if (value != null && value.isNotEmpty) return value;
    return _shortId(job.id);
  }

  String _jobSelectionLabel(MechanicJob job) {
    final customer = _customerNameForJob(job);
    final bike = _bikeTitleForJob(job);
    return 'Trabajo #${_jobNumber(job)} · $customer · $bike';
  }

  String _customerNameForJob(MechanicJob job) {
    final customer = _customersById[job.customerId];
    final name = customer?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Cliente sin nombre';
  }

  List<MechanicJobBike> _jobBikesForJob(MechanicJob job) {
    final jobId = job.id;
    if (jobId == null) return const [];
    return _jobBikesByJobId[jobId] ?? const [];
  }

  List<Bike> _bikesForJob(MechanicJob job) {
    final hydrated = _jobBikesForJob(job)
        .map((jobBike) => jobBike.bike)
        .whereType<Bike>()
        .toList();
    if (hydrated.isNotEmpty) return hydrated;

    final bikeId = job.bikeId;
    final fallbackBike = bikeId != null ? _bikesById[bikeId] : null;
    if (fallbackBike != null) return [fallbackBike];

    return const [];
  }

  String _bikeTitleForJob(MechanicJob job) {
    final bikes = _bikesForJob(job);
    if (bikes.length > 1) {
      final first = bikes.first.displayName;
      return '$first + ${bikes.length - 1} bicicleta(s) más';
    }
    if (bikes.length == 1) return bikes.first.displayName;
    final subject = job.subjectDisplayName;
    if (subject != null && subject.trim().isNotEmpty) return subject.trim();
    return 'Sin bicicleta asociada';
  }

  List<String> _bikeMetaForJob(MechanicJob job) {
    final bikes = _bikesForJob(job);
    if (bikes.isEmpty) return const [];
    final first = bikes.first;
    final meta = <String>[];
    if (first.serialNumber != null && first.serialNumber!.trim().isNotEmpty) {
      meta.add('S/N ${first.serialNumber!.trim()}');
    }
    if (first.color != null && first.color!.trim().isNotEmpty) {
      meta.add(first.color!.trim());
    }
    if (first.frameSize != null && first.frameSize!.trim().isNotEmpty) {
      meta.add('Talla ${first.frameSize!.trim()}');
    }
    if (first.wheelSize != null && first.wheelSize!.trim().isNotEmpty) {
      meta.add('Aro ${first.wheelSize!.trim()}');
    }
    if (bikes.length > 1) {
      meta.add('${bikes.length} bicicletas');
    }
    return meta.take(4).toList();
  }

  String _invoiceNumber(Invoice invoice) {
    final value = invoice.invoiceNumber.trim();
    if (value.isNotEmpty) return value;
    return _shortId(invoice.id);
  }

  String _invoiceCustomerName(Invoice invoice) {
    final name = invoice.customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Cliente sin nombre';
  }

  String _invoiceSelectionLabel(Invoice invoice) {
    return 'Factura #${_invoiceNumber(invoice)} · ${_invoiceCustomerName(invoice)}';
  }

  String _invoiceStatusLabel(InvoiceStatus status) {
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
        return 'Anulada';
    }
  }

  Color _invoiceStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return const Color(0xFF6B7280);
      case InvoiceStatus.sent:
        return const Color(0xFF2563EB);
      case InvoiceStatus.confirmed:
        return const Color(0xFFD97706);
      case InvoiceStatus.paid:
        return const Color(0xFF059669);
      case InvoiceStatus.overdue:
        return const Color(0xFFDC2626);
      case InvoiceStatus.cancelled:
        return const Color(0xFF4B5563);
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String _shortId(String? id) {
    if (id == null || id.isEmpty) return 'sin número';
    return id.length <= 8 ? id : id.substring(0, 8);
  }
}
