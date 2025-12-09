import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/utils/chilean_utils.dart';

/// Customer bikes page - view registered bikes and their service history
class CustomerBikesPage extends StatefulWidget {
  const CustomerBikesPage({super.key});

  @override
  State<CustomerBikesPage> createState() => _CustomerBikesPageState();
}

class _CustomerBikesPageState extends State<CustomerBikesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerAccountService>().loadBikes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      // Not authenticated - show login prompt (no Scaffold - wrapped by layout)
      return Column(
        children: [
          // Header bar
          Container(
            color: Theme.of(context).primaryColor,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 4,
              right: 16,
              bottom: 8,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.go('/cuenta'),
                ),
                const Text(
                  'Mis Bicicletas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Content
          const SizedBox(height: 48),
          const Icon(Icons.pedal_bike_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('Debes iniciar sesión para ver tus bicicletas'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('INICIAR SESIÓN'),
          ),
          const SizedBox(height: 48),
        ],
      );
    }

    // Authenticated - show bikes list (no Scaffold - wrapped by layout)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header bar
        Container(
          color: Theme.of(context).primaryColor,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 4,
            right: 16,
            bottom: 8,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.go('/cuenta'),
              ),
              const Text(
                'Mis Bicicletas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Content
        if (accountService.isLoading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (accountService.bikes.isEmpty)
          _buildEmptyState()
        else
          _buildBikesList(accountService),
      ],
    );
  }

  Widget _buildEmptyState() {
    // No Center/Expanded - parent is inside SingleChildScrollView
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.pedal_bike_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'No tienes bicicletas registradas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Tus bicicletas aparecerán aquí cuando las registres en nuestra tienda o las lleves a servicio técnico.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () => context.go('/contacto'),
            icon: const Icon(Icons.contact_support_outlined),
            label: const Text('CONTACTAR TIENDA'),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildBikesList(CustomerAccountService accountService) {
    // Use Column instead of ListView since parent is already scrollable
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: accountService.bikes.map((bike) {
          return _BikeCard(
            bike: bike,
            onTap: () => _showBikeDetails(bike),
            onViewServices: () => context.go('/cuenta/servicios?bike_id=${bike['id']}'),
          );
        }).toList(),
      ),
    );
  }

  void _showBikeDetails(Map<String, dynamic> bike) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BikeDetailSheet(bike: bike),
    );
  }
}

class _BikeCard extends StatelessWidget {
  final Map<String, dynamic> bike;
  final VoidCallback onTap;
  final VoidCallback onViewServices;

  const _BikeCard({
    required this.bike,
    required this.onTap,
    required this.onViewServices,
  });

  @override
  Widget build(BuildContext context) {
    final brand = bike['brand'] ?? bike['brand_name'] ?? 'Sin marca';
    final model = bike['model'] ?? bike['model_name'] ?? 'Sin modelo';
    final year = bike['year'];
    final color = bike['color'];
    final bikeType = bike['bike_type'];
    final serviceCount = bike['service_count'] ?? 0;
    final lastService = bike['last_service_date'];
    final imageUrl = bike['image_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section
            if (imageUrl != null && imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                ),
              )
            else
              _buildPlaceholderImage(),

            // Info section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand & Model
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$brand $model',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      if (bikeType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getBikeTypeColor(bikeType).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getBikeTypeLabel(bikeType),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getBikeTypeColor(bikeType),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Details row
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (year != null)
                        _buildDetailChip(Icons.calendar_today, year.toString()),
                      if (color != null)
                        _buildDetailChip(Icons.palette_outlined, color),
                      if (bike['frame_size'] != null)
                        _buildDetailChip(Icons.straighten, bike['frame_size']),
                      if (bike['wheel_size'] != null)
                        _buildDetailChip(Icons.tire_repair, bike['wheel_size']),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Service info row
                  Row(
                    children: [
                      Icon(
                        Icons.build_outlined,
                        size: 16,
                        color: PublicStoreTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        serviceCount > 0
                            ? '$serviceCount servicio${serviceCount > 1 ? 's' : ''}'
                            : 'Sin servicios',
                        style: TextStyle(
                          color: PublicStoreTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (lastService != null) ...[
                        const SizedBox(width: 16),
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: PublicStoreTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Último: ${ChileanUtils.formatDate(DateTime.parse(lastService))}',
                          style: TextStyle(
                            color: PublicStoreTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const Spacer(),
                      TextButton(
                        onPressed: onViewServices,
                        child: const Text('VER SERVICIOS'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.grey[200],
        child: Icon(
          Icons.pedal_bike,
          size: 64,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Color _getBikeTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'road':
        return Colors.red;
      case 'mountain':
        return Colors.green;
      case 'electric':
        return Colors.blue;
      case 'hybrid':
        return Colors.purple;
      case 'gravel':
        return Colors.orange;
      case 'bmx':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _getBikeTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'road':
        return 'Ruta';
      case 'mountain':
        return 'MTB';
      case 'electric':
        return 'Eléctrica';
      case 'hybrid':
        return 'Híbrida';
      case 'gravel':
        return 'Gravel';
      case 'bmx':
        return 'BMX';
      case 'folding':
        return 'Plegable';
      case 'cruiser':
        return 'Cruiser';
      default:
        return type;
    }
  }
}

class _BikeDetailSheet extends StatelessWidget {
  final Map<String, dynamic> bike;

  const _BikeDetailSheet({required this.bike});

  @override
  Widget build(BuildContext context) {
    final brand = bike['brand'] ?? bike['brand_name'] ?? 'Sin marca';
    final model = bike['model'] ?? bike['model_name'] ?? 'Sin modelo';
    final year = bike['year'];
    final serialNumber = bike['serial_number'];
    final color = bike['color'];
    final frameSize = bike['frame_size'];
    final wheelSize = bike['wheel_size'];
    final bikeType = bike['bike_type'];
    final purchaseDate = bike['purchase_date'];
    final warrantyUntil = bike['warranty_until'];
    final notes = bike['notes'];
    final imageUrls = (bike['image_urls'] as List?)?.cast<String>() ?? [];
    final imageUrl = bike['image_url'];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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

            // Image gallery
            if (imageUrl != null || imageUrls.isNotEmpty)
              SizedBox(
                height: 200,
                child: PageView(
                  children: [
                    if (imageUrl != null)
                      Image.network(imageUrl, fit: BoxFit.cover),
                    ...imageUrls.map((url) => Image.network(url, fit: BoxFit.cover)),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    '$brand $model',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (year != null)
                    Text(
                      'Año $year',
                      style: TextStyle(
                        color: PublicStoreTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Details grid
                  _buildDetailSection('Información General', [
                    if (bikeType != null)
                      _DetailRow('Tipo', _getBikeTypeLabel(bikeType)),
                    if (color != null) _DetailRow('Color', color),
                    if (frameSize != null) _DetailRow('Talla', frameSize),
                    if (wheelSize != null) _DetailRow('Ruedas', wheelSize),
                    if (serialNumber != null)
                      _DetailRow('N° Serie', serialNumber),
                  ]),

                  if (purchaseDate != null || warrantyUntil != null) ...[
                    const SizedBox(height: 16),
                    _buildDetailSection('Compra y Garantía', [
                      if (purchaseDate != null)
                        _DetailRow(
                          'Fecha de compra',
                          ChileanUtils.formatDate(
                              DateTime.parse(purchaseDate)),
                        ),
                      if (warrantyUntil != null)
                        _DetailRow(
                          'Garantía hasta',
                          ChileanUtils.formatDate(
                              DateTime.parse(warrantyUntil)),
                          valueColor:
                              DateTime.parse(warrantyUntil).isAfter(DateTime.now())
                                  ? Colors.green
                                  : Colors.red,
                        ),
                    ]),
                  ],

                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildDetailSection('Notas', []),
                    const SizedBox(height: 8),
                    Text(
                      notes,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.go('/tienda/cuenta/servicios?bike_id=${bike['id']}');
                          },
                          icon: const Icon(Icons.history),
                          label: const Text('HISTORIAL DE SERVICIOS'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<_DetailRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map((row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(row.label, style: const TextStyle(color: Colors.grey)),
                  Text(
                    row.value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: row.valueColor,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  String _getBikeTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'road':
        return 'Ruta';
      case 'mountain':
        return 'MTB';
      case 'electric':
        return 'Eléctrica';
      case 'hybrid':
        return 'Híbrida';
      case 'gravel':
        return 'Gravel';
      case 'bmx':
        return 'BMX';
      case 'folding':
        return 'Plegable';
      case 'cruiser':
        return 'Cruiser';
      default:
        return type;
    }
  }
}

class _DetailRow {
  final String label;
  final String value;
  final Color? valueColor;

  _DetailRow(this.label, this.value, {this.valueColor});
}
