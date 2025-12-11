import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import '../../crm/services/customer_service.dart';
import '../../crm/models/crm_models.dart';
import '../../../shared/widgets/branded_loading.dart';

/// Shared calendar widget for displaying mechanic jobs
/// Used by both WorkshopCalendarPage and PegasTablePage calendar tab
class PegasCalendarWidget extends StatefulWidget {
  /// If provided, uses this data instead of loading from service
  final List<MechanicJob>? jobs;
  final Map<String, Customer>? customers;
  final Map<String, Bike>? bikes;
  
  /// Callback when data needs to be refreshed (for external data mode)
  final VoidCallback? onRefreshNeeded;

  const PegasCalendarWidget({
    super.key,
    this.jobs,
    this.customers,
    this.bikes,
    this.onRefreshNeeded,
  });

  @override
  State<PegasCalendarWidget> createState() => _PegasCalendarWidgetState();
}

class _PegasCalendarWidgetState extends State<PegasCalendarWidget> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  
  // Internal data (used when no external data provided)
  List<MechanicJob> _internalJobs = [];
  Map<String, String> _customerNames = {};
  Map<String, String> _bikeNames = {};
  bool _isLoading = true;
  
  // Selected job details
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];
  Map<String, String> _productImages = {};
  String? _customerName;
  String? _bikeBrand;
  String? _bikeModel;
  bool _loadingDetails = false;

  bool get _useExternalData => widget.jobs != null;
  
  List<MechanicJob> get _jobs => _useExternalData ? widget.jobs! : _internalJobs;

  @override
  void initState() {
    super.initState();
    if (!_useExternalData) {
      _loadJobs();
    } else {
      _buildLookupMaps();
      _isLoading = false;
    }
  }

  @override
  void didUpdateWidget(PegasCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useExternalData) {
      _buildLookupMaps();
    }
  }

  void _buildLookupMaps() {
    if (widget.customers != null) {
      _customerNames = {};
      for (final entry in widget.customers!.entries) {
        _customerNames[entry.key] = entry.value.name;
      }
    }
    if (widget.bikes != null) {
      _bikeNames = {};
      for (final entry in widget.bikes!.entries) {
        final bike = entry.value;
        final bikeName = '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
        if (bikeName.isNotEmpty) {
          _bikeNames[entry.key] = bikeName;
        }
      }
    }
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();
      
      final jobs = await bikeshopService.getJobs();
      final customers = await customerService.getCustomers();
      
      final customerNameMap = <String, String>{};
      for (final customer in customers) {
        if (customer.id != null) {
          customerNameMap[customer.id!] = customer.name;
        }
      }
      
      final bikeNameMap = <String, String>{};
      final bikes = await bikeshopService.getBikes();
      for (final bike in bikes) {
        if (bike.id != null) {
          final bikeName = '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
          if (bikeName.isNotEmpty) {
            bikeNameMap[bike.id!] = bikeName;
          }
        }
      }
      
      setState(() {
        _internalJobs = jobs;
        _customerNames = customerNameMap;
        _bikeNames = bikeNameMap;
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
    setState(() => _loadingDetails = true);
    try {
      final bikeshopService = context.read<BikeshopService>();
      
      // Load job items
      final items = await bikeshopService.getJobItems(job.id!);
      
      // Get customer name
      String? customerName;
      if (_useExternalData && widget.customers != null) {
        customerName = widget.customers![job.customerId]?.name ?? 'Cliente no encontrado';
      } else {
        customerName = _customerNames[job.customerId] ?? 'Cliente no encontrado';
      }
      
      // Get bike info
      String? bikeBrand;
      String? bikeModel;
      if (_useExternalData && widget.bikes != null) {
        final bike = widget.bikes![job.bikeId];
        bikeBrand = bike?.brand;
        bikeModel = bike?.model;
      } else {
        try {
          final bike = await bikeshopService.getBikeById(job.bikeId);
          bikeBrand = bike?.brand;
          bikeModel = bike?.model;
        } catch (e) {
          bikeBrand = 'Bici no encontrada';
          bikeModel = '';
        }
      }
      
      // Load product images
      final Map<String, String> productImages = {};
      try {
        final productIds = items
            .where((item) => item.productId != null)
            .map((item) => item.productId!)
            .toSet();
        
        if (productIds.isNotEmpty) {
          final response = await Supabase.instance.client
              .from('products')
              .select('id, image_url')
              .inFilter('id', productIds.toList());
          
          for (final product in response) {
            final id = product['id'] as String;
            final imageUrl = product['image_url'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              productImages[id] = imageUrl;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading product images: $e');
      }
      
      setState(() {
        _selectedJobItems = items;
        _customerName = customerName;
        _bikeBrand = bikeBrand;
        _bikeModel = bikeModel;
        _productImages = productImages;
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

  /// Gets color for a job - prefers custom status color, falls back to legacy
  Color _getJobColor(MechanicJob job) {
    if (job.customStatus != null) {
      return job.customStatus!.colorValue;
    }
    return _getStatusColor(job.status);
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

  /// Gets status text - prefers custom status name, falls back to legacy
  String _getJobStatusText(MechanicJob job) {
    if (job.customStatus != null) {
      return job.customStatus!.name;
    }
    return _getStatusText(job.status);
  }

  String _getStatusText(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return 'Pendiente';
      case JobStatus.diagnostico:
        return 'Diagnóstico';
      case JobStatus.esperandoAprobacion:
        return 'Esperando Aprobación';
      case JobStatus.esperandoRepuestos:
        return 'Esperando Repuestos';
      case JobStatus.enCurso:
        return 'En Curso';
      case JobStatus.finalizado:
        return 'Finalizado';
      case JobStatus.entregado:
        return 'Entregado';
      case JobStatus.cancelado:
        return 'Cancelado';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    return Padding(
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
                    Expanded(child: _buildCalendarGrid()),
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
    );
  }

  Widget _buildMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C), // VinaBike navy blue
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
              });
            },
          ),
          Text(
            DateFormat('MMMM yyyy', 'es').format(_focusedMonth),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday - 1; // Monday = 0

    return Column(
      children: [
        // Weekday headers
        Row(
          children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Calendar days
        Expanded(
          child: Column(
            children: List.generate((daysInMonth + firstWeekday + 6) ~/ 7, (weekIndex) {
              return Expanded(
                child: Row(
                  children: List.generate(7, (dayIndex) {
                    final dayNumber = weekIndex * 7 + dayIndex - firstWeekday + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const Expanded(child: SizedBox());
                    }

                    final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
                    final isSelected = _selectedDate.year == date.year &&
                        _selectedDate.month == date.month &&
                        _selectedDate.day == date.day;
                    final isToday = DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;
                    final jobsOnDay = _getJobsForDate(date);

                    return Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                            _selectedJob = null;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).primaryColor.withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                                : isSelected
                                    ? Border.all(color: Theme.of(context).primaryColor, width: 1)
                                    : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  '$dayNumber',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              // Jobs on this day
                              if (jobsOnDay.isNotEmpty)
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    itemCount: jobsOnDay.length,
                                    itemBuilder: (context, index) {
                                      final job = jobsOnDay[index];
                                      final customerName = _customerNames[job.customerId] ?? 'Cliente';
                                      final statusColor = _getJobColor(job);

                                      return InkWell(
                                        onTap: () async {
                                          setState(() {
                                            _selectedDate = date;
                                            _selectedJob = job;
                                            _loadingDetails = true;
                                          });
                                          await _loadJobDetails(job);
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            customerName,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: statusColor.withOpacity(0.9),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
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
                  setState(() => _selectedJob = null);
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
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay pegas programadas',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
    final statusColor = _getJobColor(job);
    final customerName = _customerNames[job.customerId] ?? 'Cliente';
    final bikeName = _bikeNames[job.bikeId];

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
                      bikeName ?? job.jobNumber ?? 'Sin #',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                customerName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(job.deadline!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
    final statusColor = _getJobColor(job);
    final statusText = _getJobStatusText(job);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Badge & Bike Info
          Row(
            children: [
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
              Text(
                _bikeBrand != null || _bikeModel != null
                    ? '${_bikeBrand ?? ''} ${_bikeModel ?? ''}'.trim()
                    : job.jobNumber ?? 'Sin #',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Customer Name
          if (_customerName != null) ...[
            Row(
              children: [
                Icon(Icons.person, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _customerName!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Bike Info
          if (_bikeBrand != null && _bikeBrand!.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.pedal_bike, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                const SizedBox(width: 8),
                Text(
                  _bikeModel != null && _bikeModel!.isNotEmpty ? '$_bikeBrand $_bikeModel' : _bikeBrand!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Deadline - Editable
          if (job.deadline != null) ...[
            InkWell(
              onTap: () => _editDeadline(job),
              child: Row(
                children: [
                  Icon(Icons.event, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(job.deadline!)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dashed,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: Colors.red.shade700.withAlpha(153)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Items Section
          if (_selectedJobItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.shopping_cart, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Repuestos y Servicios',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._selectedJobItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.productId != null && _productImages.containsKey(item.productId))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _HoverImageWidget(
                            imageUrl: _productImages[item.productId]!,
                            size: 40,
                          ),
                        ),
                      Text('• ', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Cantidad: ${item.quantity.toStringAsFixed(0)} × \$${item.unitPrice.toStringAsFixed(0)} = \$${item.totalPrice.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          // Loading indicator
          if (_loadingDetails) ...[
            const SizedBox(height: 12),
            const Center(child: Padding(padding: EdgeInsets.all(16), child: BrandedLoading())),
          ],

          // Notes section
          if (job.clientRequest != null || job.diagnosis != null || job.workPerformed != null || (job.notes != null && job.notes!.isNotEmpty)) ...[
            const Divider(height: 24),
            if (job.clientRequest != null) ...[
              _buildDetailRow(icon: Icons.description, label: 'Solicitud', value: job.clientRequest!),
              const SizedBox(height: 12),
            ],
            if (job.diagnosis != null) ...[
              _buildDetailRow(icon: Icons.medical_services, label: 'Diagnóstico', value: job.diagnosis!),
              const SizedBox(height: 12),
            ],
            if (job.workPerformed != null) ...[
              _buildDetailRow(icon: Icons.build, label: 'Trabajo Realizado', value: job.workPerformed!),
              const SizedBox(height: 12),
            ],
            if (job.notes != null && job.notes!.isNotEmpty) ...[
              _buildDetailRow(icon: Icons.note, label: 'Notas', value: job.notes!),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _editDeadline(MechanicJob job) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: job.deadline!,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'CL'),
    );
    if (selectedDate == null) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(job.deadline!),
    );
    if (selectedTime == null) return;

    final newDeadline = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    try {
      final bikeshopService = context.read<BikeshopService>();
      final updatedJob = job.copyWith(deadline: newDeadline);
      await bikeshopService.updateJob(updatedJob);

      // Refresh data
      if (_useExternalData) {
        widget.onRefreshNeeded?.call();
      } else {
        await _loadJobs();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fecha de entrega actualizada'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

// ============================================================
// HOVER IMAGE WIDGET - Shows small thumbnail with zoom on hover
// ============================================================
class _HoverImageWidget extends StatefulWidget {
  final String imageUrl;
  final double size;

  const _HoverImageWidget({
    required this.imageUrl,
    this.size = 40,
  });

  @override
  State<_HoverImageWidget> createState() => _HoverImageWidgetState();
}

class _HoverImageWidgetState extends State<_HoverImageWidget> {
  bool _isHovered = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _showZoomedImage(BuildContext context) {
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 300,
        height: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(widget.size + 8, -130),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, size: 50),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideZoomedImage() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
          _showZoomedImage(context);
        },
        onExit: (_) {
          setState(() => _isHovered = false);
          _hideZoomedImage();
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
              width: _isHovered ? 2 : 1,
            ),
            color: Colors.grey[100],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.image, size: 20, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideZoomedImage();
    super.dispose();
  }
}
