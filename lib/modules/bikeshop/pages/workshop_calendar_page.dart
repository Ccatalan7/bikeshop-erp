import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import '../../crm/services/customer_service.dart';

class WorkshopCalendarPage extends StatefulWidget {
  const WorkshopCalendarPage({super.key});

  @override
  State<WorkshopCalendarPage> createState() => _WorkshopCalendarPageState();
}

class _WorkshopCalendarPageState extends State<WorkshopCalendarPage> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  List<MechanicJob> _jobs = [];
  Map<String, String> _customerNames = {}; // Map of customer_id -> customer_name
  bool _isLoading = true;
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];
  List<MechanicJobLabor> _selectedJobLabor = [];
  String? _customerName;
  String? _bikeBrand;
  String? _bikeModel;
  bool _loadingDetails = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();
      
      final jobs = await bikeshopService.getJobs();
      final customers = await customerService.getCustomers();
      
      // Create customer name lookup map
      final customerNameMap = <String, String>{};
      for (final customer in customers) {
        if (customer.id != null) {
          customerNameMap[customer.id!] = customer.name;
        }
      }
      
      setState(() {
        _jobs = jobs;
        _customerNames = customerNameMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar pegas: $e')),
        );
      }
    }
  }

  Future<void> _loadJobDetails(MechanicJob job) async {
    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();
      
      // Load job items (parts/products)
      final items = await bikeshopService.getJobItems(job.id!);
      
      // Load labor entries
      final labor = await bikeshopService.getJobLabor(job.id!);
      
      // Load customer name
      String? customerName;
      try {
        final customers = await customerService.getCustomers();
        final customer = customers.firstWhere((c) => c.id == job.customerId);
        customerName = customer.name;
      } catch (e) {
        customerName = 'Cliente no encontrado';
      }
      
      // Load bike info
      String? bikeBrand;
      String? bikeModel;
      try {
        final bike = await bikeshopService.getBikeById(job.bikeId);
        bikeBrand = bike?.brand;
        bikeModel = bike?.model;
      } catch (e) {
        bikeBrand = 'Bici no encontrada';
        bikeModel = '';
      }
      
      setState(() {
        _selectedJobItems = items;
        _selectedJobLabor = labor;
        _customerName = customerName;
        _bikeBrand = bikeBrand;
        _bikeModel = bikeModel;
        _loadingDetails = false;
      });
    } catch (e) {
      setState(() => _loadingDetails = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar detalles: $e')),
        );
      }
    }
  }

  List<MechanicJob> _getJobsForDate(DateTime date) {
    return _jobs.where((job) {
      // Use deadline as the scheduled date for calendar display
      if (job.deadline == null) return false;
      final jobDate = job.deadline!;
      return jobDate.year == date.year &&
          jobDate.month == date.month &&
          jobDate.day == date.day;
    }).toList();
  }

  List<MechanicJob> _getJobsForSelectedDate() {
    return _getJobsForDate(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Calendario del Taller',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calendar on the left
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildMonthHeader(),
                            const SizedBox(height: 16),
                            _buildCalendarGrid(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Jobs list on the right
                  Expanded(
                    flex: 1,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildJobsList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month - 1,
              );
            });
          },
        ),
        Text(
          DateFormat('MMMM yyyy', 'es').format(_focusedMonth),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month + 1,
              );
            });
          },
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    return Column(
      children: [
        // Weekday headers
        Row(
          children: ['D', 'L', 'M', 'M', 'J', 'V', 'S']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Calendar days
        ...List.generate((daysInMonth + firstWeekday + 6) ~/ 7, (weekIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber =
                    weekIndex * 7 + dayIndex - firstWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox());
                }

                final date = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month,
                  dayNumber,
                );
                final isSelected = _selectedDate.year == date.year &&
                    _selectedDate.month == date.month &&
                    _selectedDate.day == date.day;
                final isToday = DateTime.now().year == date.year &&
                    DateTime.now().month == date.month &&
                    DateTime.now().day == date.day;
                final jobsOnDay = _getJobsForDate(date);
                final hasJobs = jobsOnDay.isNotEmpty;

                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedDate = date;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color: Theme.of(context).primaryColor,
                                width: 2,
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNumber',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isToday || hasJobs
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (hasJobs) ...[
                            const SizedBox(height: 4),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildJobsList() {
    final jobsForDate = _getJobsForSelectedDate();
    final dateFormat = DateFormat('EEEE, d MMMM yyyy', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_selectedJob != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedJob = null;
                  });
                },
                tooltip: 'Volver a la lista',
              ),
            Expanded(
              child: Text(
                _selectedJob != null ? 'Detalles de la Pega' : dateFormat.format(_selectedDate),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selectedJob != null)
          Expanded(child: _buildJobDetails(_selectedJob!))
        else if (jobsForDate.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay pegas programadas',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: jobsForDate.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final job = jobsForDate[index];
                return _buildJobCard(job);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildJobCard(MechanicJob job) {
    Color statusColor;
    switch (job.status) {
      case JobStatus.pendiente:
        statusColor = Colors.orange;
        break;
      case JobStatus.enCurso:
        statusColor = Colors.blue;
        break;
      case JobStatus.finalizado:
      case JobStatus.entregado:
        statusColor = Colors.green;
        break;
      case JobStatus.cancelado:
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    final customerName = _customerNames[job.customerId] ?? 'Cliente';

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedJob = job;
            _loadingDetails = true;
          });
          await _loadJobDetails(job);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.jobNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                customerName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (job.clientRequest != null) ...[
                const SizedBox(height: 8),
                Text(
                  job.clientRequest!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (job.deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(job.deadline!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobDetails(MechanicJob job) {
    Color statusColor;
    String statusText;
    switch (job.status) {
      case JobStatus.pendiente:
        statusColor = Colors.orange;
        statusText = 'Pendiente';
        break;
      case JobStatus.enCurso:
        statusColor = Colors.blue;
        statusText = 'En Curso';
        break;
      case JobStatus.finalizado:
        statusColor = Colors.green;
        statusText = 'Finalizado';
        break;
      case JobStatus.entregado:
        statusColor = Colors.green;
        statusText = 'Entregado';
        break;
      case JobStatus.cancelado:
        statusColor = Colors.red;
        statusText = 'Cancelado';
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Desconocido';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact header with status and key info
          Row(
            children: [
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Job Number (compact)
              Text(
                job.jobNumber,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Customer Name (prominent)
          if (_customerName != null) ...[
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _customerName!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // Bike Info (compact)
          if (_bikeBrand != null && _bikeBrand!.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.pedal_bike,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  _bikeModel != null && _bikeModel!.isNotEmpty 
                      ? '$_bikeBrand $_bikeModel'
                      : _bikeBrand!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // Deadline (compact and prominent)
          if (job.deadline != null) ...[
            Row(
              children: [
                Icon(
                  Icons.event,
                  size: 18,
                  color: Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(job.deadline!)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          
          // Parts/Products Section
          if (_selectedJobItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.build_circle,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Repuestos y Productos',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._selectedJobItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'Cantidad: ${item.quantity.toStringAsFixed(0)} × \$${item.unitPrice.toStringAsFixed(0)} = \$${item.totalPrice.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
          
          // Labor/Services Section
          if (_selectedJobLabor.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.handyman,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Mano de Obra y Servicios',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._selectedJobLabor.map((labor) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labor.description ?? 'Servicio',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'Horas: ${labor.hoursWorked.toStringAsFixed(1)} × \$${labor.hourlyRate.toStringAsFixed(0)}/hr = \$${labor.totalCost.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
          
          // Show loading indicator while loading details
          if (_loadingDetails) ...[
            const SizedBox(height: 12),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          
          // Client Request, Diagnosis, Work Performed, Notes
          if (job.clientRequest != null || job.diagnosis != null || 
              job.workPerformed != null || (job.notes != null && job.notes!.isNotEmpty)) ...[
            const Divider(height: 24),
            
            if (job.clientRequest != null) ...[
              _buildDetailRow(
                icon: Icons.description,
                label: 'Solicitud',
                value: job.clientRequest!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.diagnosis != null) ...[
              _buildDetailRow(
                icon: Icons.medical_services,
                label: 'Diagnóstico',
                value: job.diagnosis!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.workPerformed != null) ...[
              _buildDetailRow(
                icon: Icons.build,
                label: 'Trabajo Realizado',
                value: job.workPerformed!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.notes != null && job.notes!.isNotEmpty) ...[
              _buildDetailRow(
                icon: Icons.note,
                label: 'Notas',
                value: job.notes!,
                isMultiline: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMultiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: isMultiline ? null : 1,
            overflow: isMultiline ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
