import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/utils/chilean_utils.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/public_store_layout.dart';

class CustomerServiceHistoryPage extends StatefulWidget {
  final String? bikeId;

  const CustomerServiceHistoryPage({super.key, this.bikeId});

  @override
  State<CustomerServiceHistoryPage> createState() =>
      _CustomerServiceHistoryPageState();
}

class _CustomerServiceHistoryPageState extends State<CustomerServiceHistoryPage>
    with AutomaticKeepAliveClientMixin {
  String? _selectedBikeId;
  String _selectedStatus = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedBikeId = widget.bikeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<CustomerAccountService>();
      service.loadServiceHistory();
      service.loadBikes();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return CustomerPortalLayout(
        title: 'Servicios de taller',
        child: _UnauthenticatedState(
          onLogin: () => PublicStoreLayout.navigateToHref(
            context,
            '/cuenta/login',
          ),
        ),
      );
    }

    var services = accountService.serviceHistory;
    if (_selectedBikeId != null && _selectedBikeId!.isNotEmpty) {
      services = services
          .where((service) => service['bike_id'] == _selectedBikeId)
          .toList();
    }
    if (_selectedStatus != 'all') {
      services = services
          .where((service) => service['status'] == _selectedStatus)
          .toList();
    }

    return CustomerPortalLayout(
      title: 'Servicios de taller',
      headerAction: FilledButton.icon(
        onPressed: () => PublicStoreLayout.navigateToHref(context, '/contacto'),
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: const Text('Agendar'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF102A43),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ServiceSummary(total: accountService.serviceHistory.length),
          const SizedBox(height: 18),
          _ServiceFilters(
            selectedBikeId: _selectedBikeId,
            selectedStatus: _selectedStatus,
            bikes: accountService.bikes,
            onBikeChanged: (value) => setState(() => _selectedBikeId = value),
            onStatusChanged: (value) {
              setState(() => _selectedStatus = value ?? 'all');
            },
          ),
          const SizedBox(height: 18),
          if (accountService.isLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (services.isEmpty)
            _EmptyServicesState(
              hasBikeFilter: _selectedBikeId != null,
              onContact: () => PublicStoreLayout.navigateToHref(
                context,
                '/contacto',
              ),
            )
          else
            _ServicesList(
              services: services,
              onTap: _showServiceDetails,
            ),
        ],
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> service) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Servicio #${service['job_number'] ?? 'N/A'}',
                        style: const TextStyle(
                          color: Color(0xFF18212F),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StatusBadge(status: (service['status'] ?? '').toString()),
                const SizedBox(height: 18),
                _DetailLine(
                  label: 'Bicicleta',
                  value: _bikeTitle(service),
                ),
                if ((service['description'] ?? '').toString().isNotEmpty)
                  _DetailLine(
                    label: 'Trabajo',
                    value: service['description'].toString(),
                  ),
                if ((service['diagnosis'] ?? '').toString().isNotEmpty)
                  _DetailLine(
                    label: 'Diagnostico',
                    value: service['diagnosis'].toString(),
                  ),
                if (service['arrival_date'] != null)
                  _DetailLine(
                    label: 'Ingreso',
                    value: _formatDate(service['arrival_date']),
                  ),
                if (service['deadline'] != null)
                  _DetailLine(
                    label: 'Fecha estimada',
                    value: _formatDate(service['deadline']),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF102A43),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnauthenticatedState extends StatelessWidget {
  final VoidCallback onLogin;

  const _UnauthenticatedState({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 360),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_outlined, size: 64),
            const SizedBox(height: 16),
            const Text('Debes iniciar sesion para ver tu historial'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onLogin,
              child: const Text('Iniciar sesion'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceSummary extends StatelessWidget {
  final int total;

  const _ServiceSummary({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.build_outlined, color: Color(0xFF102A43), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 1
                      ? '1 servicio registrado'
                      : '$total servicios registrados',
                  style: const TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consulta el estado de tus trabajos de taller y el historial asociado a tus bicicletas.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceFilters extends StatelessWidget {
  final String? selectedBikeId;
  final String selectedStatus;
  final List<Map<String, dynamic>> bikes;
  final ValueChanged<String?> onBikeChanged;
  final ValueChanged<String?> onStatusChanged;

  const _ServiceFilters({
    required this.selectedBikeId,
    required this.selectedStatus,
    required this.bikes,
    required this.onBikeChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final bikeField = DropdownButtonFormField<String>(
            initialValue: selectedBikeId,
            decoration: const InputDecoration(
              labelText: 'Bicicleta',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Todas las bicicletas'),
              ),
              ...bikes.map((bike) => DropdownMenuItem(
                    value: bike['id'] as String,
                    child: Text(_bikeTitle(bike)),
                  )),
            ],
            onChanged: onBikeChanged,
          );
          final statusField = DropdownButtonFormField<String>(
            initialValue: selectedStatus,
            decoration: const InputDecoration(
              labelText: 'Estado',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Todos')),
              DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
              DropdownMenuItem(value: 'EN_CURSO', child: Text('En curso')),
              DropdownMenuItem(
                value: 'ESPERANDO_REPUESTOS',
                child: Text('Esperando repuestos'),
              ),
              DropdownMenuItem(value: 'FINALIZADO', child: Text('Finalizado')),
              DropdownMenuItem(value: 'ENTREGADO', child: Text('Entregado')),
            ],
            onChanged: onStatusChanged,
          );

          if (compact) {
            return Column(
              children: [
                bikeField,
                const SizedBox(height: 12),
                statusField,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: bikeField),
              const SizedBox(width: 12),
              Expanded(child: statusField),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyServicesState extends StatelessWidget {
  final bool hasBikeFilter;
  final VoidCallback onContact;

  const _EmptyServicesState({
    required this.hasBikeFilter,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        children: [
          Icon(Icons.build_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 18),
          Text(
            hasBikeFilter
                ? 'Esta bicicleta no tiene servicios'
                : 'No tienes servicios registrados',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF18212F),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cuando lleves tu bicicleta a servicio tecnico, los trabajos apareceran aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF667085), height: 1.35),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onContact,
            icon: const Icon(Icons.calendar_today_outlined),
            label: const Text('Agendar servicio'),
          ),
        ],
      ),
    );
  }
}

class _ServicesList extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _ServicesList({required this.services, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeServices = services
        .where((service) =>
            !['ENTREGADO', 'CANCELADO'].contains(service['status']))
        .toList();
    final completedServices = services
        .where(
            (service) => ['ENTREGADO', 'CANCELADO'].contains(service['status']))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (activeServices.isNotEmpty) ...[
          const _SectionHeader(icon: Icons.pending_actions, title: 'Activos'),
          const SizedBox(height: 10),
          ...activeServices.map((service) => _ServiceCard(
                service: service,
                onTap: () => onTap(service),
              )),
          const SizedBox(height: 18),
        ],
        if (completedServices.isNotEmpty) ...[
          const _SectionHeader(icon: Icons.history, title: 'Historial'),
          const SizedBox(height: 10),
          ...completedServices.map((service) => _ServiceCard(
                service: service,
                onTap: () => onTap(service),
              )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF102A43), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF18212F),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (service['status'] ?? '').toString();
    final displayTotal = _numeric(service['total_amount']) ??
        _numeric(service['total_cost']) ??
        _numeric(service['estimated_total']) ??
        0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E4EA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _bikeTitle(service),
                            style: const TextStyle(
                              color: Color(0xFF18212F),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Servicio #${service['job_number'] ?? 'N/A'}',
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusBadge(status: status),
                  ],
                ),
                if ((service['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    service['description'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          if (service['arrival_date'] != null)
                            _DatePill(
                              label: 'Ingreso',
                              value: _formatDate(service['arrival_date']),
                            ),
                          if (service['deadline'] != null)
                            _DatePill(
                              label: 'Estimado',
                              value: _formatDate(service['deadline']),
                            ),
                        ],
                      ),
                    ),
                    if (displayTotal > 0)
                      Text(
                        ChileanUtils.formatCurrency(displayTotal),
                        style: const TextStyle(
                          color: Color(0xFF102A43),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  final String label;
  final String value;

  const _DatePill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: Color(0xFF18212F))),
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
    final config = _statusConfig(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 13, color: config.textColor),
          const SizedBox(width: 4),
          Text(
            config.label,
            style: TextStyle(
              color: config.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusConfig {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color textColor;

  const _StatusConfig({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.textColor,
  });
}

_StatusConfig _statusConfig(String status) {
  switch (status) {
    case 'PENDIENTE':
      return _StatusConfig(
        label: 'Pendiente',
        icon: Icons.schedule,
        backgroundColor: Colors.grey.shade200,
        textColor: Colors.grey.shade700,
      );
    case 'DIAGNOSTICO':
      return _StatusConfig(
        label: 'Diagnostico',
        icon: Icons.search,
        backgroundColor: Colors.purple.shade50,
        textColor: Colors.purple.shade700,
      );
    case 'ESPERANDO_APROBACION':
      return _StatusConfig(
        label: 'Aprobacion',
        icon: Icons.pending_actions,
        backgroundColor: Colors.amber.shade50,
        textColor: Colors.amber.shade900,
      );
    case 'ESPERANDO_REPUESTOS':
      return _StatusConfig(
        label: 'Repuestos',
        icon: Icons.inventory_2_outlined,
        backgroundColor: Colors.orange.shade50,
        textColor: Colors.orange.shade800,
      );
    case 'EN_CURSO':
      return _StatusConfig(
        label: 'En curso',
        icon: Icons.build,
        backgroundColor: Colors.blue.shade50,
        textColor: Colors.blue.shade700,
      );
    case 'FINALIZADO':
      return _StatusConfig(
        label: 'Finalizado',
        icon: Icons.check_circle_outline,
        backgroundColor: Colors.green.shade50,
        textColor: Colors.green.shade700,
      );
    case 'ENTREGADO':
      return _StatusConfig(
        label: 'Entregado',
        icon: Icons.done_all,
        backgroundColor: Colors.green.shade50,
        textColor: Colors.green.shade800,
      );
    case 'CANCELADO':
      return _StatusConfig(
        label: 'Cancelado',
        icon: Icons.cancel_outlined,
        backgroundColor: Colors.red.shade50,
        textColor: Colors.red.shade700,
      );
    default:
      return _StatusConfig(
        label: status.isEmpty ? 'Sin estado' : status,
        icon: Icons.info_outline,
        backgroundColor: Colors.grey.shade100,
        textColor: Colors.grey.shade700,
      );
  }
}

String _bikeTitle(Map<String, dynamic> data) {
  final brand = data['bike_brand'] ?? data['brand'] ?? data['brand_name'] ?? '';
  final model = data['bike_model'] ?? data['model'] ?? data['model_name'] ?? '';
  final title = '$brand $model'.trim();
  return title.isEmpty ? 'Bicicleta' : title;
}

String _formatDate(dynamic value) {
  if (value == null) return '';
  final date = value is DateTime ? value : DateTime.tryParse(value.toString());
  return date == null ? value.toString() : ChileanUtils.formatDate(date);
}

double? _numeric(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
