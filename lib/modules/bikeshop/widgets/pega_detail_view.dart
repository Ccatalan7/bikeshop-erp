import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../crm/models/crm_models.dart';
import '../models/bikeshop_models.dart';

class PegaDetailView extends StatelessWidget {
  final MechanicJob job;
  final Customer? customer;
  final Bike? bike;
  final List<MechanicJobItem> items;
  final List<MechanicJobLabor> labor;
  final Map<String, String> productImages;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final Function(JobStatus) onStatusChange;

  const PegaDetailView({
    super.key,
    required this.job,
    this.customer,
    this.bike,
    this.items = const [],
    this.labor = const [],
    this.productImages = const {},
    required this.onClose,
    required this.onEdit,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border(bottom: BorderSide(color: Colors.blue[200]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.jobNumber,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (customer != null)
                        Text(
                          customer!.name,
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
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Detail content (scrollable)
          Expanded(
            child: SingleChildScrollView(
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
                          job.status.displayName,
                          Icons.info_outline,
                          _getStatusColor(job.status),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildInfoCard(
                          'Prioridad',
                          job.priority.displayName,
                          Icons.priority_high,
                          _getPriorityColor(job.priority),
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
                          DateFormat('dd/MM/yyyy').format(job.arrivalDate),
                          Icons.login,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildInfoCard(
                          'Plazo de Entrega',
                          job.deadline != null
                              ? DateFormat('dd/MM/yyyy').format(job.deadline!)
                              : 'Sin plazo',
                          job.isOverdue ? Icons.warning : Icons.event,
                          job.isOverdue ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bike information
                  _buildSectionHeader('Información de la Bicicleta'),
                  const SizedBox(height: 12),
                  if (bike != null) _buildBikeDetails(bike!) else const Text('Sin bicicleta asignada'),
                  const SizedBox(height: 24),

                  // Customer information
                  _buildSectionHeader('Información del Cliente'),
                  const SizedBox(height: 12),
                  if (customer != null) _buildCustomerDetails(customer!) else const Text('Sin cliente asignado'),
                  const SizedBox(height: 24),

                  // Client request (always show)
                  _buildSectionHeader('Solicitud del Cliente'),
                  const SizedBox(height: 12),
                  _buildContentBox(job.clientRequest ?? ''),
                  const SizedBox(height: 24),

                  // Diagnosis (always show)
                  _buildSectionHeader('Diagnóstico'),
                  const SizedBox(height: 12),
                  _buildContentBox(job.diagnosis ?? ''),
                  const SizedBox(height: 24),

                  // Technician notes (always show)
                  _buildSectionHeader('Notas del Técnico'),
                  const SizedBox(height: 12),
                  _buildContentBox(job.notes ?? ''),
                  const SizedBox(height: 24),

                  // Assigned technician
                  if (job.assignedTechnicianName != null) ...[
                    _buildSectionHeader('Técnico Asignado'),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      'Técnico',
                      job.assignedTechnicianName!,
                      Icons.person,
                      Colors.purple,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Products and Services
                  if (items.isNotEmpty || labor.isNotEmpty) ...[
                    _buildSectionHeader('Repuestos y Servicios'),
                    const SizedBox(height: 12),
                    
                    // Products/Parts
                    if (items.isNotEmpty) ...[
                      ...items.map((item) => _buildProductItem(item)),
                    ],
                    
                    // Labor/Services
                    if (labor.isNotEmpty) ...[
                      ...labor.map((laborItem) => _buildLaborItem(laborItem)),
                    ],
                    
                    const SizedBox(height: 24),
                  ],

                  // Cost information
                  if (job.totalCost > 0) ...[
                    _buildSectionHeader('Costos'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (job.partsCost > 0)
                          Expanded(
                            child: _buildInfoCard(
                              'Repuestos',
                              '\$${job.partsCost.toStringAsFixed(0)}',
                              Icons.build_circle,
                              Colors.orange,
                            ),
                          ),
                        if (job.partsCost > 0 && job.laborCost > 0)
                          const SizedBox(width: 16),
                        if (job.laborCost > 0)
                          Expanded(
                            child: _buildInfoCard(
                              'Mano de Obra',
                              '\$${job.laborCost.toStringAsFixed(0)}',
                              Icons.handyman,
                              Colors.blue,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      'Total',
                      '\$${job.totalCost.toStringAsFixed(0)}',
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
                          onPressed: onEdit,
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
            ),
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
              .where((s) => s != job.status)
              .map((status) => ListTile(
                    title: Text(status.displayName),
                    onTap: () {
                      Navigator.pop(context);
                      onStatusChange(status);
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

  Widget _buildInfoCard(String label, String value, IconData icon, Color color) {
    // Use subtle gray background instead of circus colors
    final isWarning = color == Colors.red && job.isOverdue;
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
                      bike.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (bike.serialNumber != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Serie: ${bike.serialNumber}',
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
                      customer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (customer.email != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.email, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            customer.email!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (customer.phone != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone!,
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
            child: item.productId != null && productImages.containsKey(item.productId)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      productImages[item.productId]!,
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

  Widget _buildLaborItem(MechanicJobLabor laborItem) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          // Labor icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.handyman, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 12),
          
          // Labor details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  laborItem.description ?? 'Mano de obra',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${laborItem.hoursWorked.toStringAsFixed(1)} hrs',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (laborItem.hourlyRate > 0) ...[
                      const SizedBox(width: 16),
                      Text(
                        '\$${laborItem.hourlyRate.toStringAsFixed(0)}/hr',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Cost
          Text(
            '\$${laborItem.totalCost.toStringAsFixed(0)}',
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
}
