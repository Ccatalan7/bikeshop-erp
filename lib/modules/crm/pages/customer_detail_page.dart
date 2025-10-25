import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';
import '../../bikeshop/services/bikeshop_service.dart';

class CustomerDetailPage extends StatefulWidget {
  final String customerId;

  const CustomerDetailPage({super.key, required this.customerId});

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late CustomerService _customerService;
  late BikeshopService _bikeshopService;
  Customer? _customer;
  Loyalty? _loyalty;
  List<BikeHistory> _bikeHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    setState(() => _isLoading = true);
    try {
      final customer =
          await _customerService.getCustomerById(widget.customerId);
      final loyalty =
          await _customerService.getCustomerLoyalty(widget.customerId);
      final bikeHistory =
          await _customerService.getCustomerBikeHistory(widget.customerId);

      setState(() {
        _customer = customer;
        _loyalty = loyalty;
        _bikeHistory = bikeHistory;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando datos del cliente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customer == null
              ? _buildCustomerNotFound()
              : _buildCustomerDetail(),
    );
  }

  Widget _buildCustomerNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Cliente no encontrado',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            text: 'Volver',
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetail() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Spacer(),
                  AppButton(
                    text: 'Editar',
                    icon: Icons.edit,
                    type: ButtonType.outline,
                    onPressed: () {
                      context
                          .push('/clientes/${widget.customerId}/editar')
                          .then((_) {
                        _loadCustomerData();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Customer info
              Row(
                children: [
                  ImageService.buildAvatarImage(
                    imageUrl: _customer!.imageUrl,
                    radius: 40,
                    initials: _customer!.initials,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _customer!.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (!_customer!.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Inactivo',
                                  style: TextStyle(
                                    color: Colors.red[800],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'RUT: ${_customer!.rut}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        if (_customer!.email != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _customer!.email!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
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
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Contact Information
                _buildSection('Información de Contacto', [
                  if (_customer!.phone != null)
                    _buildInfoRow(Icons.phone, 'Teléfono', _customer!.phone!),
                  if (_customer!.email != null)
                    _buildInfoRow(Icons.email, 'Email', _customer!.email!),
                  if (_customer!.address != null)
                    _buildInfoRow(Icons.home, 'Dirección', _customer!.address!),
                  if (_customer!.region != null)
                    _buildInfoRow(
                        Icons.location_on, 'Región', _customer!.region!),
                ]),

                const SizedBox(height: 24),

                // Loyalty Information
                if (_loyalty != null) ...[
                  _buildLoyaltySection(),
                  const SizedBox(height: 24),
                ],

                // Bike History
                _buildBikeHistorySection(),

                const SizedBox(height: 24),

                // Customer Stats
                _buildCustomerStats(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Programa de Fidelización',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color:
                            _getLoyaltyColor(_loyalty!.tier).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        _getLoyaltyIcon(_loyalty!.tier),
                        color: _getLoyaltyColor(_loyalty!.tier),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getLoyaltyTierName(_loyalty!.tier),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_loyalty!.points} puntos',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Agregar Puntos',
                        icon: Icons.add,
                        type: ButtonType.outline,
                        onPressed: () {
                          _showAddPointsDialog();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        text: 'Canjear Puntos',
                        icon: Icons.redeem,
                        type: ButtonType.outline,
                        onPressed: () {
                          _showRedeemPointsDialog();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBikeHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Historial de Bicicletas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            AppButton(
              text: 'Agregar Bicicleta',
              icon: Icons.add,
              type: ButtonType.outline,
              onPressed: () {
                // TODO: Navigate to add bike form
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_bikeHistory.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.pedal_bike,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No hay bicicletas registradas',
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...(_bikeHistory.map((bike) => _buildBikeCard(bike))),
      ],
    );
  }

  Widget _buildBikeCard(BikeHistory bike) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: bike.imageUrl != null
                  ? ImageService.buildProductImage(
                      imageUrl: bike.imageUrl,
                      size: 60,
                    )
                  : Icon(
                      Icons.pedal_bike,
                      color: Colors.blue[600],
                      size: 30,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bike.brand} ${bike.model}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (bike.year != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Año: ${bike.year}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        ChileanUtils.formatDate(bike.purchaseDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        ChileanUtils.formatCurrency(bike.purchaseAmount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 3-dot menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[600]),
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
      ),
    );
  }

  Widget _buildCustomerStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estadísticas',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'Cliente desde',
                        ChileanUtils.formatDate(_customer!.createdAt),
                        Icons.calendar_today,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'Bicicletas',
                        _bikeHistory.length.toString(),
                        Icons.pedal_bike,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'Total Invertido',
                        ChileanUtils.formatCurrency(
                          _bikeHistory.fold(
                              0.0, (sum, bike) => sum + bike.purchaseAmount),
                        ),
                        Icons.attach_money,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'Puntos Totales',
                        (_loyalty?.points ?? 0).toString(),
                        Icons.stars,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue[600]),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Color _getLoyaltyColor(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return Colors.brown;
      case LoyaltyTier.silver:
        return Colors.grey;
      case LoyaltyTier.gold:
        return Colors.amber;
      case LoyaltyTier.platinum:
        return Colors.purple;
    }
  }

  IconData _getLoyaltyIcon(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return Icons.workspace_premium;
      case LoyaltyTier.silver:
        return Icons.workspace_premium;
      case LoyaltyTier.gold:
        return Icons.workspace_premium;
      case LoyaltyTier.platinum:
        return Icons.diamond;
    }
  }

  String _getLoyaltyTierName(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return 'Bronce';
      case LoyaltyTier.silver:
        return 'Plata';
      case LoyaltyTier.gold:
        return 'Oro';
      case LoyaltyTier.platinum:
        return 'Platino';
    }
  }

  void _showAddPointsDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Puntos'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Cantidad de puntos',
            hintText: '100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points != null && points > 0) {
                try {
                  await _customerService.addLoyaltyPoints(
                      widget.customerId, points);
                  _loadCustomerData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Puntos agregados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error agregando puntos: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showRedeemPointsDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Canjear Puntos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Puntos disponibles: ${_loyalty?.points ?? 0}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puntos a canjear',
                hintText: '100',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points != null && points > 0) {
                try {
                  await _customerService.redeemLoyaltyPoints(
                      widget.customerId, points);
                  _loadCustomerData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Puntos canjeados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error canjeando puntos: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Canjear'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BIKE MANAGEMENT
  // ============================================================

  void _editBike(BikeHistory bike) {
    // TODO: Navigate to bike edit form
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Editar bicicleta - Por implementar'),
      ),
    );
  }

  Future<void> _confirmDeleteBike(BikeHistory bike) async {
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
              '${bike.brand} ${bike.model}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (bike.year != null) Text('Año: ${bike.year}'),
            if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty)
              Text('N° Serie: ${bike.serialNumber}'),
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
        await _bikeshopService.deleteBike(bike.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bicicleta eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the bike list automatically
          _loadCustomerData();
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
