import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../crm/models/crm_models.dart';
import '../../../shared/models/tax_treatment.dart';
import '../models/bikeshop_models.dart';
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
                  tooltip: 'Editar',
                  onPressed: widget.onEdit,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status and Priority row
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Estado',
                  widget.job.status.displayName,
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

          // KPI Section
          _buildSectionHeader('Indicadores de Tiempo (KPIs)'),
          const SizedBox(height: 12),
          _buildKPISection(),
          const SizedBox(height: 24),

          // Bike information
          _buildSectionHeader('Información de la Bicicleta'),
          const SizedBox(height: 12),
          if (widget.bike != null)
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
            _buildSectionHeader('Costos'),
            const SizedBox(height: 12),
            _buildInfoCard(
              'Total',
              '\$${_calculateDisplayTotal().toStringAsFixed(0)}',
              Icons.attach_money,
              Colors.green,
            ),
            const SizedBox(height: 24),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar Pega'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showStatusChangeDialog(context),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: labelColor,
                  fontWeight: FontWeight.w500,
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
    // If tax treatment is 'noTax', we should display the sum of parts + labor
    // effectively ignoring any tax calculation that might be in totalCost
    if (widget.job.taxTreatment == TaxTreatment.noTax) {
      return widget.job.partsCost + widget.job.laborCost;
    }
    return widget.job.totalCost;
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
    return TasksTabView(
      jobId: widget.job.id!,
      readOnly: false,
      externalItems: widget.items,
      onItemAdded: widget.onItemAdded,
      onItemRemoved: widget.onItemRemoved,
      onAddItemPressed: widget.onAddItemPressed,
    );
  }

  Widget _buildKPISection() {
    final now = DateTime.now();
    final job = widget.job;

    // 1. Diagnostic Duration (Arrival -> Diagnostic Sent)
    String diagDuration = '-';
    String diagLabel = 'Pendiente';
    Color diagColor = Colors.grey;

    if (job.diagnosticSentAt != null) {
      final d = job.diagnosticSentAt!.difference(job.arrivalDate);
      diagDuration = _formatDuration(d);
      diagLabel = 'Completado';
      diagColor = Colors.blue;
    } else if (job.diagnosticDeadline != null &&
        job.diagnosticDeadline!.isBefore(now)) {
      final d = now.difference(job.arrivalDate);
      diagDuration = _formatDuration(d);
      diagLabel = 'Atrasado';
      diagColor = Colors.red;
    } else {
      final d = now.difference(job.arrivalDate);
      diagDuration = _formatDuration(d);
      diagLabel = 'En curso';
      diagColor = Colors.orange;
    }

    // 2. Workshop Duration (Started -> Completed)
    String shopDuration = '-';
    String shopLabel = 'No iniciado';
    Color shopColor = Colors.grey;

    if (job.startedAt != null) {
      if (job.completedAt != null) {
        final d = job.completedAt!.difference(job.startedAt!);
        shopDuration = _formatDuration(d);
        shopLabel = 'Completado';
        shopColor = Colors.green;
      } else {
        final d = now.difference(job.startedAt!);
        shopDuration = _formatDuration(d);
        shopLabel = 'En curso';
        shopColor = Colors.blue;
      }
    }

    // 3. Total Duration (Arrival -> Delivered)
    String totalDuration = '-';
    String totalLabel = 'En curso';
    Color totalColor = Colors.purple;

    if (job.deliveredAt != null) {
      final d = job.deliveredAt!.difference(job.arrivalDate);
      totalDuration = _formatDuration(d);
      totalLabel = 'Final';
      totalColor = Colors.purple;
    } else {
      final d = now.difference(job.arrivalDate);
      totalDuration = _formatDuration(d);
      totalLabel = 'Actual'; // Running total
      totalColor = Colors.purple.shade300;
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Diagnóstico',
                diagDuration,
                Icons.assignment_turned_in,
                diagColor,
                subtitle: diagLabel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKPICard(
                'Taller',
                shopDuration,
                Icons.build,
                shopColor,
                subtitle: shopLabel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKPICard(
                'Total',
                totalDuration,
                Icons.timer,
                totalColor,
                subtitle: totalLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color,
      {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '0h 0m';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}
