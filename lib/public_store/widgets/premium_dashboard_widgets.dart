import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// -----------------------------------------------------------------------------
// 1. LIVE JOB TRACKER - LIGHT MODE + SPANISH
// -----------------------------------------------------------------------------
class LiveJobTracker extends StatelessWidget {
  final Map<String, dynamic>? activeService;

  const LiveJobTracker({super.key, this.activeService});

  @override
  Widget build(BuildContext context) {
    if (activeService == null) {
      return _buildEmptyState();
    }

    final status = activeService!['status'] ?? 'INGRESADO';
    final progress = _calculateProgress(status);
    final statusLabel = _getReadableStatus(status);
    final bikeName =
        '${activeService!['bike_brand']} ${activeService!['bike_model']}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Seguimiento en Vivo',
                style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: Colors.orange.shade600),
                    const SizedBox(width: 5),
                    Text('Servicio activo',
                        style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Trabajo actual: $bikeName – Etapa: $statusLabel',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 16),
          // Progress Bar with Dot
          LayoutBuilder(
            builder: (context, constraints) {
              final dotPosition = constraints.maxWidth * progress;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(3))),
                  Container(
                    height: 6,
                    width: dotPosition,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Colors.blue.shade400, Colors.teal.shade400]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Positioned(
                    left: dotPosition - 6,
                    top: -3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.blue.shade400, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.grey[500], size: 16),
                const SizedBox(width: 8),
                Text('Entrega estimada: ',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const Text('Mañana PM',
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.green.shade50, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline,
                size: 40, color: Colors.green.shade400),
          ),
          const SizedBox(height: 16),
          const Text('¡Todo al día!',
              style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('No hay trabajos activos.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    );
  }

  double _calculateProgress(String status) {
    switch (status) {
      case 'INGRESADO':
        return 0.1;
      case 'DIAGNOSTICO':
        return 0.25;
      case 'APROBACION':
        return 0.35;
      case 'EN_COLA':
        return 0.45;
      case 'EN_PROCESO':
        return 0.65;
      case 'CONTROL_CALIDAD':
        return 0.85;
      case 'TERMINADO':
        return 1.0;
      default:
        return 0.1;
    }
  }

  String _getReadableStatus(String status) {
    switch (status) {
      case 'INGRESADO':
        return 'Ingresado';
      case 'DIAGNOSTICO':
        return 'En Diagnóstico';
      case 'APROBACION':
        return 'Esperando Aprobación';
      case 'EN_COLA':
        return 'En Cola';
      case 'EN_PROCESO':
        return 'En Reparación';
      case 'CONTROL_CALIDAD':
        return 'Control de Calidad';
      case 'TERMINADO':
        return 'Listo para Retiro';
      default:
        return status;
    }
  }
}

// -----------------------------------------------------------------------------
// 2. GARAGE GRID - LIGHT MODE + SPANISH
// -----------------------------------------------------------------------------
class GarageGrid extends StatelessWidget {
  final List<dynamic> bikes;

  const GarageGrid({super.key, required this.bikes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Mi Garage',
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => context.go('/cuenta/bicicletas'),
                icon: const Text('Ver Todo', style: TextStyle(fontSize: 12)),
                label: const Icon(Icons.chevron_right, size: 14),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: EdgeInsets.zero),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tus bicicletas registradas y su estado.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 16),
          if (bikes.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.pedal_bike, size: 44, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Text('No hay bicicletas registradas.',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 13)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/cuenta/bicicletas'),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Agregar Bicicleta',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey.shade300)),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.0),
              itemCount: bikes.take(2).length,
              itemBuilder: (context, index) => _buildBikeCard(bikes[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildBikeCard(Map<String, dynamic> bike) {
    final bool needsService = (bike['id']?.hashCode ?? 0) % 3 == 0;
    final statusColor = needsService ? Colors.orange : Colors.green;
    final statusText = needsService ? 'Necesita Servicio' : 'Salud: Buena';

    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                image: bike['image_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(bike['image_url']),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: bike['image_url'] == null
                  ? Center(
                      child: Icon(Icons.pedal_bike,
                          size: 50, color: Colors.grey[400]))
                  : null,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7)
                    ]),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration:
                  BoxDecoration(color: statusColor, shape: BoxShape.circle),
              child: Icon(needsService ? Icons.warning : Icons.check,
                  size: 14, color: Colors.white),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${bike['brand'] ?? ''} ${bike['model'] ?? 'Bici'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(statusText,
                    style: TextStyle(
                        color: statusColor.shade100,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. RECENT ACTIVITY - LIGHT MODE + SPANISH
// -----------------------------------------------------------------------------
class RecentActivity extends StatefulWidget {
  final List<dynamic> orders;
  final List<dynamic> services;

  const RecentActivity(
      {super.key, required this.orders, required this.services});

  @override
  State<RecentActivity> createState() => _RecentActivityState();
}

class _RecentActivityState extends State<RecentActivity> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Actividad Reciente',
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    Text('Reciente',
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 11)),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down,
                        color: Colors.grey[600], size: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTab('Pedidos', 0),
              const SizedBox(width: 20),
              _buildTab('Historial Servicios', 1),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _selectedTab == 0 ? _buildOrdersList() : _buildServicesList(),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.blue : Colors.grey[500],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13)),
          const SizedBox(height: 6),
          Container(
              height: 2,
              width: 50,
              color: isSelected ? Colors.blue : Colors.transparent),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    if (widget.orders.isEmpty) return _buildEmptyList('Sin pedidos aún');
    return Column(
        children: widget.orders
            .take(3)
            .map((order) => _buildActivityItem(
                icon: Icons.receipt_long,
                title: 'Pedido #${order['order_number'] ?? 'N/A'}',
                subtitle: 'A las ${_formatTime(order['created_at'])}'))
            .toList());
  }

  Widget _buildServicesList() {
    if (widget.services.isEmpty)
      return _buildEmptyList('Sin historial de servicios');
    return Column(
        children: widget.services
            .take(3)
            .map((service) => _buildActivityItem(
                icon: Icons.build_circle_outlined,
                title:
                    '${service['bike_brand'] ?? ''} ${service['bike_model'] ?? ''} Mantención',
                subtitle: 'A las ${_formatTime(service['created_at'])}'))
            .toList());
  }

  Widget _buildEmptyList(String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
          child: Text(message,
              style: TextStyle(color: Colors.grey[500], fontSize: 13))));

  Widget _buildActivityItem(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.grey[600], size: 18)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                      fontSize: 13)),
              const SizedBox(height: 1),
              Text(subtitle,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ]),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr.toString());
      final hour =
          date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
    } catch (e) {
      return 'N/A';
    }
  }
}
