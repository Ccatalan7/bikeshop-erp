import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/utils/chilean_utils.dart';

/// Customer service history page - view mechanic jobs (pegas) for their bikes
class CustomerServiceHistoryPage extends StatefulWidget {
  final String? bikeId; // Optional filter by bike

  const CustomerServiceHistoryPage({super.key, this.bikeId});

  @override
  State<CustomerServiceHistoryPage> createState() =>
      _CustomerServiceHistoryPageState();
}

class _CustomerServiceHistoryPageState extends State<CustomerServiceHistoryPage>
    with AutomaticKeepAliveClientMixin {
  String? _selectedBikeId;
  String _selectedStatus = 'all';

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedBikeId = widget.bikeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<CustomerAccountService>();
      service.loadServiceHistory();
      service.loadBikes(); // For filter dropdown
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return _buildUnauthenticatedState(context);
    }

    // Filter services
    var services = accountService.serviceHistory;
    debugPrint('🔍 [ServiceHistoryPage] Total services: ${services.length}');
    debugPrint(
        '🔍 [ServiceHistoryPage] Selected bike: $_selectedBikeId, status: $_selectedStatus');

    if (_selectedBikeId != null && _selectedBikeId!.isNotEmpty) {
      services =
          services.where((s) => s['bike_id'] == _selectedBikeId).toList();
      debugPrint(
          '🔍 [ServiceHistoryPage] After bike filter: ${services.length}');
    }
    if (_selectedStatus != 'all') {
      services = services.where((s) => s['status'] == _selectedStatus).toList();
      debugPrint(
          '🔍 [ServiceHistoryPage] After status filter: ${services.length}');
    }

    debugPrint(
        '🔍 [ServiceHistoryPage] Final services to display: ${services.length}');

    // Build content without Scaffold (PublicStoreLayout provides the chrome)
    return _buildPageContent(context, accountService, services);
  }

  Widget _buildUnauthenticatedState(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 400),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_outlined, size: 64),
            const SizedBox(height: 16),
            const Text('Debes iniciar sesión para ver tu historial'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/cuenta/login'),
              child: const Text('INICIAR SESIÓN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent(
      BuildContext context,
      CustomerAccountService accountService,
      List<Map<String, dynamic>> services) {
    return Container(
      constraints: const BoxConstraints(minHeight: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header with back button
          _buildPageHeader(context),

          // Filters
          _buildFilters(accountService),

          // Content - no Expanded needed since we're in SingleChildScrollView
          if (accountService.isLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (services.isEmpty)
            _buildEmptyState()
          else
            _buildServicesContent(services),
        ],
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/cuenta'),
            tooltip: 'Volver a mi cuenta',
          ),
          const SizedBox(width: 8),
          const Text(
            'Historial de Servicios',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(CustomerAccountService accountService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Bike filter
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedBikeId,
              decoration: const InputDecoration(
                labelText: 'Bicicleta',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Todas las bicicletas'),
                ),
                ...accountService.bikes.map((bike) {
                  final brand = bike['brand'] ?? bike['brand_name'] ?? '';
                  final model = bike['model'] ?? bike['model_name'] ?? '';
                  return DropdownMenuItem(
                    value: bike['id'] as String,
                    child: Text('$brand $model'),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedBikeId = value;
                });
              },
            ),
          ),
          const SizedBox(width: 12),

          // Status filter
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Estado',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
                DropdownMenuItem(value: 'EN_CURSO', child: Text('En curso')),
                DropdownMenuItem(
                    value: 'ESPERANDO_REPUESTOS',
                    child: Text('Esperando repuestos')),
                DropdownMenuItem(
                    value: 'FINALIZADO', child: Text('Finalizado')),
                DropdownMenuItem(value: 'ENTREGADO', child: Text('Entregado')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedStatus = value ?? 'all';
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.build_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              _selectedBikeId != null
                  ? 'Esta bicicleta no tiene servicios'
                  : 'No tienes servicios registrados',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Cuando lleves tu bicicleta a servicio técnico, los trabajos aparecerán aquí.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => context.go('/contacto'),
              icon: const Icon(Icons.calendar_today_outlined),
              label: const Text('AGENDAR SERVICIO'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesList(List<Map<String, dynamic>> services) {
    // Debug: log all service statuses
    for (final s in services) {
      debugPrint(
          '🔍 [ServicesList] Service ${s['job_number']}: status="${s['status']}", status_id=${s['status_id']}');
    }

    // Group by status: active first, then completed
    final activeServices = services
        .where((s) => !['ENTREGADO', 'CANCELADO'].contains(s['status']))
        .toList();
    final completedServices = services
        .where((s) => ['ENTREGADO', 'CANCELADO'].contains(s['status']))
        .toList();

    debugPrint(
        '🔍 [ServicesList] activeServices: ${activeServices.length}, completedServices: ${completedServices.length}');

    // Build content directly (no ListView since we're in SingleChildScrollView)
    final children = <Widget>[];
    if (activeServices.isNotEmpty) {
      debugPrint('🔍 [ServicesList] Adding active services section');
      children
          .add(_buildSectionHeader('Servicios Activos', Icons.pending_actions));
      for (final service in activeServices) {
        debugPrint(
            '🔍 [ServicesList] Adding card for: ${service['job_number']}');
        children.add(_ServiceCard(
          service: service,
          onTap: () => _showServiceDetails(service),
        ));
      }
      children.add(const SizedBox(height: 24));
    }
    if (completedServices.isNotEmpty) {
      debugPrint('🔍 [ServicesList] Adding completed services section');
      children.add(_buildSectionHeader('Historial', Icons.history));
      for (final service in completedServices) {
        children.add(_ServiceCard(
          service: service,
          onTap: () => _showServiceDetails(service),
        ));
      }
    }

    debugPrint(
        '🔍 [ServicesList] Total children in ListView: ${children.length}');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Build services content without RefreshIndicator (not needed in SingleChildScrollView)
  Widget _buildServicesContent(List<Map<String, dynamic>> services) {
    return _buildServicesList(services);
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PublicStoreTheme.primaryBlue),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: PublicStoreTheme.primaryBlue,
                ),
          ),
        ],
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ServiceDetailSheet(service: service),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.service,
    required this.onTap,
  });

  /// Calculate display total based on tax treatment (same logic as ERP)
  double _getDisplayTotal() {
    final taxTreatment = service['tax_treatment'] ?? 'no_tax';
    final partsCost = (service['parts_cost'] ?? 0).toDouble();
    final laborCost = (service['labor_cost'] ?? 0).toDouble();
    final totalCost = (service['total_cost'] ?? 0).toDouble();

    debugPrint(
        '💰 [ServiceCard] ${service['job_number']}: tax_treatment=$taxTreatment, parts=$partsCost, labor=$laborCost, total=$totalCost');

    // If no_tax, show parts + labor (net amount)
    // Otherwise show total_cost (which may include tax)
    if (taxTreatment == 'no_tax') {
      return partsCost + laborCost;
    }
    return totalCost;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎴 [ServiceCard] Building card for job: ${service['job_number']}');
    final jobNumber = service['job_number'] ?? 'Sin número';
    final status = service['status'] ?? 'PENDIENTE';
    final bikeBrand = service['bike_brand'] ?? service['bikes']?['brand'] ?? '';
    final bikeModel = service['bike_model'] ?? service['bikes']?['model'] ?? '';
    final clientRequest = service['client_request'];
    final diagnosis = service['diagnosis'];
    final arrivalDate = service['arrival_date'];
    final deadline = service['deadline'];
    final displayTotal = _getDisplayTotal();
    final isInvoiced = service['is_invoiced'] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Job number
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      jobNumber,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Status badge
                  _StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 12),

              // Bike info
              if (bikeBrand.isNotEmpty || bikeModel.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.pedal_bike, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      '$bikeBrand $bikeModel'.trim(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),

              // Client request
              if (clientRequest != null && clientRequest.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  clientRequest,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Diagnosis preview (if available)
              if (diagnosis != null && diagnosis.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.medical_information,
                          size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          diagnosis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[900],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Footer: dates and cost
              Row(
                children: [
                  // Dates
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (arrivalDate != null)
                          _buildDateRow(
                            'Ingreso:',
                            ChileanUtils.formatDate(
                                DateTime.parse(arrivalDate)),
                          ),
                        if (deadline != null)
                          _buildDateRow(
                            'Fecha límite:',
                            ChileanUtils.formatDate(DateTime.parse(deadline)),
                            isOverdue: DateTime.parse(deadline)
                                    .isBefore(DateTime.now()) &&
                                !['ENTREGADO', 'CANCELADO'].contains(status),
                          ),
                      ],
                    ),
                  ),

                  // Cost
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (displayTotal > 0)
                        Text(
                          ChileanUtils.formatCurrency(displayTotal),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: PublicStoreTheme.primaryBlue,
                                  ),
                        ),
                      if (isInvoiced)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'FACTURADO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateRow(String label, String value, {bool isOverdue = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isOverdue ? Colors.red : Colors.grey[800],
            ),
          ),
          if (isOverdue) ...[
            const SizedBox(width: 4),
            const Icon(Icons.warning_amber, size: 14, color: Colors.red),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 14, color: config.textColor),
          const SizedBox(width: 4),
          Text(
            config.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: config.textColor,
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case 'PENDIENTE':
        return _StatusConfig(
          label: 'Pendiente',
          icon: Icons.schedule,
          backgroundColor: Colors.grey[200]!,
          textColor: Colors.grey[700]!,
        );
      case 'DIAGNOSTICO':
        return _StatusConfig(
          label: 'En diagnóstico',
          icon: Icons.search,
          backgroundColor: Colors.purple[100]!,
          textColor: Colors.purple[800]!,
        );
      case 'ESPERANDO_APROBACION':
        return _StatusConfig(
          label: 'Esperando aprobación',
          icon: Icons.pending_actions,
          backgroundColor: Colors.amber[100]!,
          textColor: Colors.amber[900]!,
        );
      case 'ESPERANDO_REPUESTOS':
        return _StatusConfig(
          label: 'Esperando repuestos',
          icon: Icons.inventory_2,
          backgroundColor: Colors.orange[100]!,
          textColor: Colors.orange[900]!,
        );
      case 'EN_CURSO':
        return _StatusConfig(
          label: 'En trabajo',
          icon: Icons.build,
          backgroundColor: Colors.blue[100]!,
          textColor: Colors.blue[800]!,
        );
      case 'FINALIZADO':
        return _StatusConfig(
          label: 'Listo para retiro',
          icon: Icons.check_circle,
          backgroundColor: Colors.green[100]!,
          textColor: Colors.green[800]!,
        );
      case 'ENTREGADO':
        return _StatusConfig(
          label: 'Entregado',
          icon: Icons.done_all,
          backgroundColor: Colors.teal[100]!,
          textColor: Colors.teal[800]!,
        );
      case 'CANCELADO':
        return _StatusConfig(
          label: 'Cancelado',
          icon: Icons.cancel,
          backgroundColor: Colors.red[100]!,
          textColor: Colors.red[800]!,
        );
      default:
        return _StatusConfig(
          label: status,
          icon: Icons.help_outline,
          backgroundColor: Colors.grey[200]!,
          textColor: Colors.grey[700]!,
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;

  _StatusConfig({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
  });
}

class _ServiceDetailSheet extends StatelessWidget {
  final Map<String, dynamic> service;

  const _ServiceDetailSheet({required this.service});

  /// Calculate display total based on tax treatment (same logic as ERP)
  double _getDisplayTotal() {
    final taxTreatment = service['tax_treatment'] ?? 'no_tax';
    final partsCost = (service['parts_cost'] ?? 0).toDouble();
    final laborCost = (service['labor_cost'] ?? 0).toDouble();
    final totalCost = (service['total_cost'] ?? 0).toDouble();

    if (taxTreatment == 'no_tax') {
      return partsCost + laborCost;
    }
    return totalCost;
  }

  @override
  Widget build(BuildContext context) {
    final jobNumber = service['job_number'] ?? 'Sin número';
    final status = service['status'] ?? 'PENDIENTE';
    final bikeBrand = service['bike_brand'] ?? service['bikes']?['brand'] ?? '';
    final bikeModel = service['bike_model'] ?? service['bikes']?['model'] ?? '';
    final clientRequest = service['client_request'];
    final diagnosis = service['diagnosis'];
    final workPerformed = service['work_performed'];
    final arrivalDate = service['arrival_date'];
    final deadline = service['deadline'];
    final completedAt = service['completed_at'];
    final deliveredAt = service['delivered_at'];
    final partsCost = (service['parts_cost'] ?? 0).toDouble();
    final laborCost = (service['labor_cost'] ?? 0).toDouble();
    final discountAmount = (service['discount_amount'] ?? 0).toDouble();
    final displayTotal = _getDisplayTotal();
    final isWarrantyJob = service['is_warranty_job'] ?? false;
    final warrantyNotes = service['warranty_notes'];
    final technicianName = service['assigned_technician_name'];

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: PublicStoreTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      jobNumber,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _StatusBadge(status: status),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bike info
                  if (bikeBrand.isNotEmpty || bikeModel.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.pedal_bike, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          '$bikeBrand $bikeModel'.trim(),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Warranty badge
                  if (isWarrantyJob) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified, color: Colors.purple[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trabajo en Garantía',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[900],
                                  ),
                                ),
                                if (warrantyNotes != null &&
                                    warrantyNotes.isNotEmpty)
                                  Text(
                                    warrantyNotes,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.purple[800],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Client request
                  if (clientRequest != null && clientRequest.isNotEmpty) ...[
                    _buildSection(
                      'Lo que reportaste',
                      Icons.chat_bubble_outline,
                      clientRequest,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Diagnosis
                  if (diagnosis != null && diagnosis.isNotEmpty) ...[
                    _buildSection(
                      'Diagnóstico',
                      Icons.medical_information,
                      diagnosis,
                      backgroundColor: Colors.blue[50],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Work performed
                  if (workPerformed != null && workPerformed.isNotEmpty) ...[
                    _buildSection(
                      'Trabajo realizado',
                      Icons.build_circle,
                      workPerformed,
                      backgroundColor: Colors.green[50],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Timeline
                  _buildTimelineSection(
                    arrivalDate: arrivalDate,
                    deadline: deadline,
                    completedAt: completedAt,
                    deliveredAt: deliveredAt,
                    status: status,
                  ),

                  const SizedBox(height: 16),

                  // Cost breakdown
                  if (displayTotal > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalle de Costos',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (partsCost > 0)
                            _buildCostRow('Repuestos', partsCost),
                          if (laborCost > 0)
                            _buildCostRow('Mano de obra', laborCost),
                          if (discountAmount > 0)
                            _buildCostRow('Descuento', -discountAmount,
                                isDiscount: true),
                          const Divider(height: 16),
                          _buildCostRow('Total', displayTotal, isTotal: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Technician
                  if (technicianName != null && technicianName.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.engineering,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Técnico: $technicianName',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
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

  Widget _buildSection(
    String title,
    IconData icon,
    String content, {
    Color? backgroundColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection({
    String? arrivalDate,
    String? deadline,
    String? completedAt,
    String? deliveredAt,
    required String status,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seguimiento',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          if (arrivalDate != null)
            _buildTimelineItem(
              'Ingreso',
              ChileanUtils.formatDate(DateTime.parse(arrivalDate)),
              Icons.login,
              isCompleted: true,
            ),
          if (deadline != null)
            _buildTimelineItem(
              'Fecha límite',
              ChileanUtils.formatDate(DateTime.parse(deadline)),
              Icons.event,
              isCompleted: completedAt != null,
              isOverdue: DateTime.parse(deadline).isBefore(DateTime.now()) &&
                  completedAt == null &&
                  !['ENTREGADO', 'CANCELADO'].contains(status),
            ),
          if (completedAt != null)
            _buildTimelineItem(
              'Completado',
              ChileanUtils.formatDate(DateTime.parse(completedAt)),
              Icons.check_circle,
              isCompleted: true,
            ),
          if (deliveredAt != null)
            _buildTimelineItem(
              'Entregado',
              ChileanUtils.formatDate(DateTime.parse(deliveredAt)),
              Icons.done_all,
              isCompleted: true,
              isLast: true,
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    String label,
    String date,
    IconData icon, {
    bool isCompleted = false,
    bool isOverdue = false,
    bool isLast = false,
  }) {
    final color = isOverdue
        ? Colors.red
        : isCompleted
            ? Colors.green
            : Colors.grey;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isOverdue ? Colors.red : null,
                  ),
                ),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 13,
                    color: isOverdue ? Colors.red : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCostRow(String label, double amount,
      {bool isDiscount = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
          Text(
            isDiscount
                ? '-${ChileanUtils.formatCurrency(amount.abs())}'
                : ChileanUtils.formatCurrency(amount),
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
              color: isDiscount
                  ? Colors.green
                  : (isTotal ? PublicStoreTheme.primaryBlue : null),
            ),
          ),
        ],
      ),
    );
  }
}
