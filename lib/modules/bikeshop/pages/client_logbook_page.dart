import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import 'bike_form_dialog.dart';

class ClientLogbookPage extends StatefulWidget {
  final String customerId;

  const ClientLogbookPage({
    super.key,
    required this.customerId,
  });

  @override
  State<ClientLogbookPage> createState() => _ClientLogbookPageState();
}

class _ClientLogbookPageState extends State<ClientLogbookPage> {
  Customer? _customer;
  List<Bike> _bikes = [];
  List<MechanicJob> _jobs = [];
  List<MechanicJobTimeline> _timeline = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customerService = Provider.of<CustomerService>(context, listen: false);
      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);

      // Load customer data
      final customer = await customerService.getCustomerById(widget.customerId);
      
      if (customer == null) {
        setState(() {
          _error = 'Cliente no encontrado';
          _isLoading = false;
        });
        return;
      }

      // Load bikes for this customer
      final bikes = await bikeshopService.getBikes(customerId: widget.customerId);

      // Load all jobs for this customer
      final jobs = await bikeshopService.getJobs(
        customerId: widget.customerId,
        includeCompleted: true,
      );

      // Load combined timeline from all jobs
      final allTimeline = <MechanicJobTimeline>[];
      for (final job in jobs) {
        final jobTimeline = await bikeshopService.getJobTimeline(job.id!);
        allTimeline.addAll(jobTimeline);
      }

      // Sort timeline by date descending (most recent first)
      allTimeline.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _customer = customer;
        _bikes = bikes;
        _jobs = jobs;
        _timeline = allTimeline;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar datos: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: _customer?.name ?? 'Historial del Cliente',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _customer == null
                  ? const Center(child: Text('Cliente no encontrado'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCustomerHeader(),
          const SizedBox(height: 32),
          _buildStatistics(),
          const SizedBox(height: 32),
          _buildBikesSection(),
          const SizedBox(height: 32),
          _buildJobsSection(),
          const SizedBox(height: 32),
          _buildTimelineSection(),
        ],
      ),
    );
  }

  Widget _buildCustomerHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                _customer!.name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 32,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 24),
            // Customer Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customer!.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_customer!.phone != null)
                    Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _customer!.phone!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  if (_customer!.email != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.email, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _customer!.email!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ],
                  if (_customer!.rut != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'RUT: ${_customer!.rut}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => context.push('/bikeshop/jobs/new?customer_id=${_customer!.id}'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Pega'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/crm/customers/${_customer!.id}'),
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar Cliente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    final totalJobs = _jobs.length;
    final activeJobs = _jobs.where((j) => 
      j.status != JobStatus.entregado && j.status != JobStatus.cancelado
    ).length;
    final completedJobs = _jobs.where((j) => j.status == JobStatus.entregado).length;
    final totalSpent = _jobs
        .where((j) => j.status == JobStatus.entregado)
        .fold(0.0, (sum, j) => sum + j.totalCost);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.two_wheeler,
            label: 'Bicicletas',
            value: _bikes.length.toString(),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.build,
            label: 'Total Pegas',
            value: totalJobs.toString(),
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.pending_actions,
            label: 'Activas',
            value: activeJobs.toString(),
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            label: 'Completadas',
            value: completedJobs.toString(),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.attach_money,
            label: 'Total Gastado',
            value: NumberFormat.currency(
              symbol: '\$',
              decimalDigits: 0,
            ).format(totalSpent),
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBikesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bicicletas Registradas',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) => BikeFormDialog(
                    customerId: widget.customerId,
                  ),
                );
                
                if (result == true) {
                  // Reload data after adding bike
                  _loadData();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar Bicicleta'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_bikes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_bike, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No hay bicicletas registradas',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _bikes.length,
            itemBuilder: (context, index) => _buildBikeCard(_bikes[index]),
          ),
      ],
    );
  }

  Widget _buildBikeCard(Bike bike) {
    final jobsForBike = _jobs.where((j) => j.bikeId == bike.id).length;
    final activeJobsForBike = _jobs.where((j) => 
      j.bikeId == bike.id && 
      j.status != JobStatus.entregado && 
      j.status != JobStatus.cancelado
    ).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pedal_bike, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bike.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editBike(bike);
                    } else if (value == 'delete') {
                      _confirmDeleteBike(bike);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (bike.serialNumber != null) ...[
              Text(
                'S/N: ${bike.serialNumber}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              bike.bikeType?.displayName ?? 'N/A',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeJobsForBike > 0 ? Colors.orange[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$jobsForBike pegas',
                    style: TextStyle(
                      fontSize: 12,
                      color: activeJobsForBike > 0 ? Colors.orange[900] : Colors.grey[700],
                    ),
                  ),
                ),
                if (bike.isUnderWarranty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user, size: 12, color: Colors.green[900]),
                        const SizedBox(width: 4),
                        Text(
                          'Garantía',
                          style: TextStyle(fontSize: 12, color: Colors.green[900]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsSection() {
    final activeJobs = _jobs.where((j) => 
      j.status != JobStatus.entregado && j.status != JobStatus.cancelado
    ).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pegas Activas',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        if (activeJobs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No hay pegas activas',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeJobs.length,
            itemBuilder: (context, index) => _buildJobCard(activeJobs[index]),
          ),
      ],
    );
  }

  Widget _buildJobCard(MechanicJob job) {
    final bike = _bikes.firstWhere(
      (b) => b.id == job.bikeId,
      orElse: () => Bike(
        id: '',
        customerId: '',
        brand: 'N/A',
        model: 'N/A',
        bikeType: BikeType.other,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/bikeshop/jobs/${job.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Job number
                  Text(
                    job.jobNumber ?? 'Sin número',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Priority badge
                  _buildPriorityBadge(job.priority),
                  const SizedBox(width: 12),
                  // Status badge
                  _buildStatusBadge(job.status),
                  const Spacer(),
                  // Cost
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Text(
                      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(job.totalCost),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Bike info
              Row(
                children: [
                  Icon(Icons.pedal_bike, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    bike.displayName,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              if (job.clientRequest != null) ...[
                const SizedBox(height: 8),
                Text(
                  job.clientRequest!,
                  style: TextStyle(color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Dates
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Ingreso: ${DateFormat('dd/MM/yyyy').format(job.arrivalDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (job.deadline != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.event,
                      size: 14,
                      color: job.isOverdue ? Colors.red : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Entrega: ${DateFormat('dd/MM/yyyy').format(job.deadline!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: job.isOverdue ? Colors.red : Colors.grey[600],
                        fontWeight: job.isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                  if (job.assignedTechnicianName != null) ...[
                    const Spacer(),
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      job.assignedTechnicianName!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(JobPriority priority) {
    Color color;
    IconData icon;
    
    switch (priority) {
      case JobPriority.urgente:
        color = Colors.red;
        icon = Icons.warning;
        break;
      case JobPriority.alta:
        color = Colors.orange;
        icon = Icons.priority_high;
        break;
      case JobPriority.normal:
        color = Colors.blue;
        icon = Icons.circle;
        break;
      case JobPriority.baja:
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            priority.displayName,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(JobStatus status) {
    Color color;
    
    switch (status) {
      case JobStatus.pendiente:
        color = Colors.grey;
        break;
      case JobStatus.diagnostico:
        color = Colors.blue;
        break;
      case JobStatus.esperandoAprobacion:
        color = Colors.amber;
        break;
      case JobStatus.esperandoRepuestos:
        color = Colors.orange;
        break;
      case JobStatus.enCurso:
        color = Colors.green;
        break;
      case JobStatus.finalizado:
        color = Colors.teal;
        break;
      case JobStatus.entregado:
        color = Colors.purple;
        break;
      case JobStatus.cancelado:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial Completo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        if (_timeline.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.timeline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No hay eventos registrados',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _timeline.length,
            itemBuilder: (context, index) => _buildTimelineItem(_timeline[index]),
          ),
      ],
    );
  }

  Widget _buildTimelineItem(MechanicJobTimeline event) {
    IconData icon;
    Color color;

    switch (event.eventType) {
      case 'created':
        icon = Icons.add_circle;
        color = Colors.blue;
        break;
      case 'status_changed':
        icon = Icons.swap_horiz;
        color = Colors.purple;
        break;
      case 'assigned':
        icon = Icons.person_add;
        color = Colors.teal;
        break;
      case 'diagnosis_added':
        icon = Icons.description;
        color = Colors.orange;
        break;
      case 'parts_added':
        icon = Icons.build_circle;
        color = Colors.amber;
        break;
      case 'labor_added':
        icon = Icons.work;
        color = Colors.indigo;
        break;
      case 'photo_added':
        icon = Icons.photo_camera;
        color = Colors.pink;
        break;
      case 'note_added':
        icon = Icons.note;
        color = Colors.cyan;
        break;
      case 'approved':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'invoiced':
        icon = Icons.receipt;
        color = Colors.deepPurple;
        break;
      case 'paid':
        icon = Icons.attach_money;
        color = Colors.green;
        break;
      case 'completed':
        icon = Icons.done_all;
        color = Colors.teal;
        break;
      case 'delivered':
        icon = Icons.local_shipping;
        color = Colors.blue;
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.description ?? _getDefaultDescription(event.eventType.dbValue),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(event.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (event.createdByName != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${event.createdByName}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                  if (event.oldValue != null || event.newValue != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${event.oldValue ?? ''} → ${event.newValue ?? ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDefaultDescription(String eventType) {
    switch (eventType) {
      case 'created':
        return 'Pega creada';
      case 'status_changed':
        return 'Estado cambiado';
      case 'assigned':
        return 'Técnico asignado';
      case 'diagnosis_added':
        return 'Diagnóstico agregado';
      case 'parts_added':
        return 'Repuestos agregados';
      case 'labor_added':
        return 'Mano de obra registrada';
      case 'photo_added':
        return 'Foto agregada';
      case 'note_added':
        return 'Nota agregada';
      case 'approved':
        return 'Trabajo aprobado';
      case 'invoiced':
        return 'Factura generada';
      case 'paid':
        return 'Pago recibido';
      case 'completed':
        return 'Trabajo completado';
      case 'delivered':
        return 'Bicicleta entregada';
      default:
        return 'Evento';
    }
  }

  // ============================================================
  // BIKE MANAGEMENT
  // ============================================================

  void _editBike(Bike bike) async {
    final result = await showDialog<Bike?>(
      context: context,
      builder: (context) => BikeFormDialog(
        customerId: widget.customerId,
        bike: bike,
      ),
    );
    
    if (result != null) {
      // Reload data after editing bike
      _loadData();
    }
  }

  Future<void> _confirmDeleteBike(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Está seguro de eliminar esta bicicleta?'),
            const SizedBox(height: 16),
            Text(
              bike.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty)
              Text('N° Serie: ${bike.serialNumber}'),
            if (bike.bikeType != null)
              Text('Tipo: ${bike.bikeType!.displayName}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && bike.id != null) {
      try {
        final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bicicleta eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh the bike list automatically
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
