import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../crm/models/crm_models.dart';
import '../../../shared/models/tax_treatment.dart';
import '../models/bikeshop_models.dart';
import 'job_time_metrics_widget.dart';
import 'tasks_tab_view.dart';

class PegaDetailView extends StatefulWidget {
  final MechanicJob job;
  final Customer? customer;
  final Bike? bike;
  final List<MechanicJobItem> items;
  final Map<String, String> productImages;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final Function(JobStatus) onStatusChange;
  final Function(MechanicJobItem)? onItemAdded;
  final Function(String itemId)? onItemRemoved;
  final VoidCallback? onAddItemPressed; // NEW: Trigger parent's add item dialog
  final VoidCallback? onProposalDocumentPressed;
  final VoidCallback? onProposalStatusPressed;
  final VoidCallback? onProposalConvertPressed;
  final VoidCallback? onStatusPressed;
  final VoidCallback? onProductsAndServicesPressed;
  final VoidCallback? onInvoicePressed;
  final VoidCallback? onPaymentPressed;
  final VoidCallback? onBikePressed;
  final VoidCallback? onCustomerPressed;

  const PegaDetailView({
    super.key,
    required this.job,
    this.customer,
    this.bike,
    this.items = const [],
    this.productImages = const {},
    required this.onClose,
    required this.onEdit,
    required this.onStatusChange,
    this.onItemAdded,
    this.onItemRemoved,
    this.onAddItemPressed, // NEW
    this.onProposalDocumentPressed,
    this.onProposalStatusPressed,
    this.onProposalConvertPressed,
    this.onStatusPressed,
    this.onProductsAndServicesPressed,
    this.onInvoicePressed,
    this.onPaymentPressed,
    this.onBikePressed,
    this.onCustomerPressed,
  });

  @override
  State<PegaDetailView> createState() => _PegaDetailViewState();
}

class _PegaDetailViewState extends State<PegaDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(PegaDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Preserve tab index when widget rebuilds (e.g., after deleting item)
    // This prevents jumping back to Details tab when on Tasks tab
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.job.jobNumber ?? 'Nuevo Trabajo',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.customer != null)
                        Text(
                          widget.customer!.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: widget.job.hasFinalProposalDecision
                      ? 'Reabre ${widget.job.proposalDocumentLabelLower} para editar'
                      : 'Editar',
                  onPressed: widget.job.hasFinalProposalDecision
                      ? null
                      : widget.onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Detalles', icon: Icon(Icons.info_outline, size: 20)),
              Tab(text: 'Tareas', icon: Icon(Icons.checklist, size: 20)),
            ],
          ),
          if (_hasQuickActions) _buildQuickActionsBar(),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDetailsTab(),
                _buildTasksTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    if (widget.job.isSaleWorkflow) return _buildSaleDetailsTab();
    if (widget.job.isStandaloneQuotation) {
      return _buildStandaloneQuotationDetailsTab();
    }
    return SingleChildScrollView(
      padding: _detailPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status and Priority row
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Estado operativo',
                  _operationalStatusSummary(widget.job),
                  Icons.info_outline,
                  _getStatusColor(widget.job.status),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoCard(
                  'Prioridad',
                  widget.job.priority.displayName,
                  Icons.priority_high,
                  _getPriorityColor(widget.job.priority),
                ),
              ),
            ],
          ),
          if (widget.job.isServiceBudget) ...[
            const SizedBox(height: 12),
            _buildInfoCard(
              'Estado comercial',
              widget.job.proposalStatusDisplayName,
              Icons.request_quote_outlined,
              _getProposalStatusColor(widget.job),
            ),
          ],
          const SizedBox(height: 16),

          // Dates row
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Fecha de Ingreso',
                  DateFormat('dd/MM/yyyy').format(widget.job.arrivalDate),
                  Icons.login,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoCard(
                  'Plazo de Entrega',
                  widget.job.deliveryDeadline != null
                      ? DateFormat('dd/MM/yyyy')
                          .format(widget.job.deliveryDeadline!)
                      : 'Sin plazo',
                  widget.job.isOverdue ? Icons.warning : Icons.event,
                  widget.job.isOverdue ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Canonical lifecycle evidence shared with the workshop table.
          _buildSectionHeader('Tiempos del trabajo'),
          const SizedBox(height: 12),
          JobTimeMetricsPanel(job: widget.job),
          const SizedBox(height: 24),

          // Received object information
          _buildSectionHeader(
            widget.job.isComponentIntake
                ? 'Componente recibido'
                : 'Información de la Bicicleta',
          ),
          const SizedBox(height: 12),
          if (widget.job.isComponentIntake)
            _buildInfoCard(
              'Componente',
              widget.job.subjectDisplayName ?? 'Componente recibido',
              Icons.build_outlined,
              Colors.blueGrey,
            )
          else if (widget.bike != null)
            _buildBikeDetails(widget.bike!)
          else
            const Text('Sin bicicleta asignada'),
          const SizedBox(height: 24),

          // Customer information
          _buildSectionHeader('Información del Cliente'),
          const SizedBox(height: 12),
          if (widget.customer != null)
            _buildCustomerDetails(widget.customer!)
          else
            const Text('Sin cliente asignado'),
          const SizedBox(height: 24),

          // Client request (always show)
          _buildSectionHeader('Solicitud del Cliente'),
          const SizedBox(height: 12),
          _buildContentBox(widget.job.clientRequest ?? ''),
          const SizedBox(height: 24),

          // Diagnosis (always show)
          _buildSectionHeader('Diagnóstico'),
          const SizedBox(height: 12),
          _buildContentBox(widget.job.diagnosis ?? ''),
          const SizedBox(height: 24),

          // Work performed summary (always show)
          _buildSectionHeader('Trabajos a Realizar'),
          const SizedBox(height: 12),
          _buildContentBox(widget.job.workPerformed ?? ''),
          const SizedBox(height: 24),

          // Technician notes (always show)
          _buildSectionHeader('Notas del Técnico'),
          const SizedBox(height: 12),
          _buildContentBox(widget.job.notes ?? ''),
          const SizedBox(height: 24),

          // Assigned technician
          if (widget.job.assignedTechnicianName != null) ...[
            _buildSectionHeader('Técnico Asignado'),
            const SizedBox(height: 12),
            _buildInfoCard(
              'Técnico',
              widget.job.assignedTechnicianName!,
              Icons.person,
              Colors.purple,
            ),
            const SizedBox(height: 24),
          ],

          // Products and Services
          if (widget.items.isNotEmpty) ...[
            _buildSectionHeader('Repuestos y Servicios'),
            const SizedBox(height: 12),

            // All items treated uniformly
            ...widget.items.map((item) => _buildProductItem(item)),

            const SizedBox(height: 24),
          ],

          // Cost information - simplified to just show total
          if (widget.job.totalCost > 0) ...[
            _buildSectionHeader(
              widget.job.isServiceBudget ? 'Presupuesto' : 'Costos',
            ),
            const SizedBox(height: 12),
            _buildInfoCard(
              widget.job.isServiceBudget ? 'Total presupuestado' : 'Total',
              '\$${_calculateDisplayTotal().toStringAsFixed(0)}',
              widget.job.isServiceBudget
                  ? Icons.request_quote_outlined
                  : Icons.attach_money,
              widget.job.isServiceBudget ? Colors.orange : Colors.green,
            ),
            const SizedBox(height: 24),
          ],

          // Action buttons
          if (widget.job.isServiceBudget)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProposalActions(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _handleStatusPressed(context),
                  icon: const Icon(Icons.sync),
                  label: const Text('Cambiar estado operativo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar Trabajo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleStatusPressed(context),
                    icon: const Icon(Icons.sync),
                    label: const Text('Cambiar Estado'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStandaloneQuotationDetailsTab() {
    final notes = widget.job.subjectNotes?.trim();
    final request = widget.job.clientRequest?.trim();
    final description = (notes?.isNotEmpty ?? false)
        ? notes!
        : (request?.isNotEmpty ?? false)
            ? request!
            : 'Sin descripción comercial registrada';

    return SingleChildScrollView(
      padding: _detailPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'Tipo',
            'Cotización · Sin objeto recibido',
            Icons.request_quote_outlined,
            Colors.orange,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Estado',
                  widget.job.statusDisplayName,
                  Icons.info_outline,
                  _getProposalStatusColor(widget.job),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoCard(
                  'Válida hasta',
                  widget.job.quotationValidUntil == null
                      ? 'Sin vencimiento'
                      : DateFormat('dd/MM/yyyy')
                          .format(widget.job.quotationValidUntil!),
                  Icons.event_outlined,
                  Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Información del Cliente'),
          const SizedBox(height: 12),
          if (widget.customer != null)
            _buildCustomerDetails(widget.customer!)
          else
            const Text('Sin cliente asignado'),
          const SizedBox(height: 24),
          _buildSectionHeader('Descripción comercial'),
          const SizedBox(height: 12),
          _buildContentBox(description),
          const SizedBox(height: 24),
          _buildSectionHeader('Productos y servicios cotizados'),
          const SizedBox(height: 12),
          if (widget.items.isEmpty)
            const Text('Sin líneas cotizadas')
          else
            ...widget.items.map(_buildProductItem),
          if (widget.job.totalCost > 0) ...[
            const SizedBox(height: 12),
            _buildInfoCard(
              'Total cotizado',
              '\$${_calculateDisplayTotal().toStringAsFixed(0)}',
              Icons.request_quote_outlined,
              Colors.orange,
            ),
          ],
          const SizedBox(height: 24),
          _buildProposalActions(),
        ],
      ),
    );
  }

  Widget _buildProposalActions() {
    final job = widget.job;
    final canConvert =
        job.effectiveQuotationStatus == QuotationStatus.approved &&
            widget.onProposalConvertPressed != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onProposalDocumentPressed,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text('Descargar ${job.proposalDocumentLabelLower}'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onProposalStatusPressed,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Gestionar ${job.proposalDocumentLabelLower}'),
            ),
            OutlinedButton.icon(
              onPressed: job.hasFinalProposalDecision ? null : widget.onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                job.hasFinalProposalDecision
                    ? 'Solo lectura · reabre para editar'
                    : 'Editar ${job.proposalDocumentLabelLower}',
              ),
            ),
          ],
        ),
        if (canConvert) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.onProposalConvertPressed,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
              job.isServiceBudget
                  ? 'Facturar presupuesto'
                  : 'Convertir cotización',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaleDetailsTab() {
    return SingleChildScrollView(
      padding: _detailPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'Tipo',
            'Venta / cobro · Sin objeto recibido',
            Icons.shopping_bag_outlined,
            Colors.blue,
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Información del Cliente'),
          const SizedBox(height: 12),
          if (widget.customer != null)
            _buildCustomerDetails(widget.customer!)
          else
            const Text('Sin cliente asignado'),
          if (widget.job.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 20),
            _buildSectionHeader('Acuerdo de pago / nota interna'),
            const SizedBox(height: 12),
            _buildContentBox(widget.job.notes!.trim()),
          ],
          const SizedBox(height: 20),
          _buildSectionHeader('Productos'),
          const SizedBox(height: 12),
          if (widget.items.isEmpty)
            const Text('Productos no disponibles')
          else
            ...widget.items.map(_buildProductItem),
          if (widget.job.totalCost > 0) ...[
            const SizedBox(height: 20),
            _buildInfoCard(
              'Total',
              '\$${_calculateDisplayTotal().toStringAsFixed(0)}',
              Icons.payments_outlined,
              Colors.green,
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit),
              label: const Text('Editar venta'),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasQuickActions =>
      widget.onStatusPressed != null ||
      widget.onProductsAndServicesPressed != null ||
      widget.onInvoicePressed != null ||
      widget.onPaymentPressed != null ||
      widget.onBikePressed != null ||
      widget.onCustomerPressed != null;

  EdgeInsets _detailPadding(BuildContext context) {
    return EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24);
  }

  Widget _buildQuickActionsBar() {
    final actions = <Widget>[
      if (widget.onStatusPressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-status'),
          icon: Icons.sync_rounded,
          label: 'Estado',
          semanticsLabel: 'Cambiar estado del trabajo',
          onPressed: widget.onStatusPressed!,
        ),
      if (widget.onProductsAndServicesPressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-items'),
          icon: Icons.inventory_2_outlined,
          label: 'Ítems',
          semanticsLabel: 'Abrir productos y servicios del trabajo',
          onPressed: widget.onProductsAndServicesPressed!,
        ),
      if (widget.onInvoicePressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-invoice'),
          icon: Icons.receipt_long_outlined,
          label: 'Factura',
          semanticsLabel: 'Abrir factura vinculada',
          onPressed: widget.onInvoicePressed!,
        ),
      if (widget.onPaymentPressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-payment'),
          icon: Icons.payments_outlined,
          label: 'Abono',
          semanticsLabel: 'Registrar pago de la factura vinculada',
          onPressed: widget.onPaymentPressed!,
        ),
      if (widget.onBikePressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-bike'),
          icon: Icons.pedal_bike_outlined,
          label: 'Bici',
          semanticsLabel: 'Abrir ficha de la bicicleta',
          onPressed: widget.onBikePressed!,
        ),
      if (widget.onCustomerPressed != null)
        _buildQuickAction(
          key: const ValueKey('workshop-detail-action-customer'),
          icon: Icons.person_outline,
          label: 'Cliente',
          semanticsLabel: 'Abrir ficha del cliente',
          onPressed: widget.onCustomerPressed!,
        ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: SingleChildScrollView(
          key: const ValueKey('workshop-detail-quick-actions-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                actions[index],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required Key key,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  void _handleStatusPressed(BuildContext context) {
    final canonicalAction = widget.onStatusPressed;
    if (canonicalAction != null) {
      canonicalAction();
      return;
    }
    _showStatusChangeDialog(context);
  }

  void _showStatusChangeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Estado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: JobStatus.values
              .where((s) => s != widget.job.status)
              .map((status) => ListTile(
                    title: Text(status.displayName),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onStatusChange(status);
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildInfoCard(
      String label, String value, IconData icon, Color color) {
    // Use subtle gray background instead of circus colors
    final isWarning = color == Colors.red && widget.job.isOverdue;
    final bgColor = isWarning ? Colors.red.shade50 : Colors.grey.shade50;
    final borderColor = isWarning ? Colors.red.shade200 : Colors.grey.shade300;
    final iconColor = isWarning ? Colors.red.shade700 : Colors.grey.shade600;
    final labelColor = Colors.grey.shade700;
    final valueColor = isWarning ? Colors.red.shade900 : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBox(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        content,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildBikeDetails(Bike bike) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pedal_bike, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.bike?.displayName ?? 'Sin nombre',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.bike?.serialNumber != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Serie: ${widget.bike?.serialNumber}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (widget.bike?.notes != null && widget.bike!.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notas',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.bike!.notes!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerDetails(Customer customer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customer?.name ?? 'Sin nombre',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.customer?.email != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.email, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            widget.customer?.email ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (widget.customer?.phone != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            widget.customer?.phone ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(MechanicJobItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Product image or icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: item.productId != null &&
                    widget.productImages.containsKey(item.productId)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      widget.productImages[item.productId]!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.inventory_2,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : Icon(Icons.inventory_2, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 12),

          // Product details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (item.notes != null && item.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.notes!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Cantidad: ${item.quantity.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '\$${item.unitPrice.toStringAsFixed(0)} c/u',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Total (calculated from quantity * unitPrice)
          Text(
            '\$${(item.quantity * item.unitPrice).toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDisplayTotal() {
    // Proposal totals are server-derived from authoritative lines after the
    // staged discount. They intentionally use no-tax classification because
    // no invoice exists yet, so the legacy noTax display branch would otherwise
    // add the undiscounted parts/labor subtotal back together.
    if (widget.job.isQuotationWorkflow) {
      return widget.job.totalCost;
    }
    // If tax treatment is 'noTax', we should display the sum of parts + labor
    // effectively ignoring any tax calculation that might be in totalCost
    if (widget.job.taxTreatment == TaxTreatment.noTax) {
      return widget.job.partsCost + widget.job.laborCost;
    }
    return widget.job.totalCost;
  }

  String _operationalStatusSummary(MechanicJob job) {
    final updatedAt = job.statusUpdatedAt;
    if (updatedAt == null) return job.statusDisplayName;
    return '${job.statusDisplayName}\nActualizado '
        '${DateFormat('dd/MM/yyyy HH:mm').format(updatedAt.toLocal())}';
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.grey;
      case JobStatus.diagnostico:
        return Colors.blue;
      case JobStatus.esperandoAprobacion:
        return Colors.amber;
      case JobStatus.esperandoRepuestos:
        return Colors.orange;
      case JobStatus.enCurso:
        return Colors.green;
      case JobStatus.finalizado:
        return Colors.teal;
      case JobStatus.entregado:
        return Colors.purple;
      case JobStatus.cancelado:
        return Colors.red;
    }
  }

  Color _getProposalStatusColor(MechanicJob job) {
    return switch (job.effectiveQuotationStatus) {
      QuotationStatus.pending => Colors.orange,
      QuotationStatus.approved => Colors.green,
      QuotationStatus.rejected => Colors.red,
      QuotationStatus.expired => Colors.grey,
    };
  }

  Color _getPriorityColor(JobPriority priority) {
    switch (priority) {
      case JobPriority.urgente:
        return Colors.red;
      case JobPriority.alta:
        return Colors.orange;
      case JobPriority.normal:
        return Colors.blue;
      case JobPriority.baja:
        return Colors.grey;
    }
  }

  // ============================================================
  // TASKS TAB - Smart To-Do List
  // ============================================================

  Widget _buildTasksTab() {
    // Use new TasksTabView with SmartTaskService
    // We pass externalItems to avoid re-fetching and to ensure immediate updates without destroying state
    final proposalIsFinal = widget.job.hasFinalProposalDecision;
    return TasksTabView(
      jobId: widget.job.id!,
      readOnly: proposalIsFinal,
      externalItems: widget.items,
      onItemAdded: proposalIsFinal ? null : widget.onItemAdded,
      onItemRemoved: proposalIsFinal ? null : widget.onItemRemoved,
      onAddItemPressed: proposalIsFinal ? null : widget.onAddItemPressed,
    );
  }
}
