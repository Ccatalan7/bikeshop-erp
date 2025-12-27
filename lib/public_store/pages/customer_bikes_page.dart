import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../../shared/utils/chilean_utils.dart';

/// Customer bikes page - view registered bikes and their service history
class CustomerBikesPage extends StatefulWidget {
  const CustomerBikesPage({super.key});

  @override
  State<CustomerBikesPage> createState() => _CustomerBikesPageState();
}

class _CustomerBikesPageState extends State<CustomerBikesPage>
    with AutomaticKeepAliveClientMixin {
  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerAccountService>().loadBikes();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return CustomerPortalLayout(
        title: 'Mis Bicicletas',
        child: _buildLoginPrompt(),
      );
    }

    final hasBikes =
        !accountService.isLoading && accountService.bikes.isNotEmpty;

    return CustomerPortalLayout(
      title: 'Mis Bicicletas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Intro Text (only if has bikes, otherwise empty state handles it)
          if (hasBikes) ...[
            Text(
              'Gestiona tus bicicletas y revisa su historial de servicios.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
          ],

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
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Inicia sesión',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Debes iniciar sesión para ver tus bicicletas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('IR AL LOGIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.pedal_bike_outlined,
              size: 48,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No tienes bicicletas registradas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Tus bicicletas aparecerán aquí cuando las registres en nuestra tienda o las lleves a servicio técnico.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => context.go('/contacto'),
            icon: const Icon(Icons.contact_support_outlined),
            label: const Text('CONTACTAR TIENDA'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikesList(CustomerAccountService accountService) {
    return Column(
      children: accountService.bikes.map((bike) {
        return _BikeCard(
          bike: bike,
          onTap: () => _showBikeDetails(bike),
          onViewServices: () =>
              context.go('/tienda/cuenta/servicios?bike_id=${bike['id']}'),
        );
      }).toList(),
    );
  }

  void _showBikeDetails(Map<String, dynamic> bike) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    final bikeType = bike['bike_type'];
    final serviceCount = bike['service_count'] ?? 0;
    final lastService = bike['last_service_date'];
    final imageUrl = bike['image_url'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            // Image Section
            if (imageUrl != null && imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 2.5, // Wider aspect ratio for header feel
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                ),
              )
            else
              _buildPlaceholderImage(),

            // Content Section
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$brand $model',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            if (year != null)
                              Text(
                                'Año $year',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (bikeType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _getBikeTypeColor(bikeType).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getBikeTypeLabel(bikeType),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getBikeTypeColor(bikeType),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildInfoItem(
                        Icons.build_circle_outlined,
                        'Servicios',
                        '$serviceCount',
                      ),
                      const SizedBox(width: 24),
                      _buildInfoItem(
                        Icons.calendar_month_outlined,
                        'Último',
                        lastService != null
                            ? ChileanUtils.formatDate(
                                DateTime.parse(lastService))
                            : '-',
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onViewServices,
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('HISTORIAL'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
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

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 120, // Shorter placeholder
      color: Colors.grey[100],
      child: Center(
        child: Icon(
          Icons.pedal_bike,
          size: 48,
          color: Colors.grey[300],
        ),
      ),
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
    final imageUrl = bike['image_url'];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Image
            if (imageUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(imageUrl, fit: BoxFit.cover),
                ),
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Center(
                  child:
                      Icon(Icons.pedal_bike, size: 40, color: Colors.grey[300]),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$brand $model',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                        ),
                      )
                    ],
                  ),
                  if (year != null)
                    Text(
                      'Año $year',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildDetailSection('Especificaciones', [
                    if (bikeType != null)
                      _DetailRow('Tipo', _getBikeTypeLabel(bikeType)),
                    if (color != null) _DetailRow('Color', color),
                    if (frameSize != null) _DetailRow('Talla', frameSize),
                    if (wheelSize != null) _DetailRow('Ruedas', wheelSize),
                    if (serialNumber != null)
                      _DetailRow('N° Serie', serialNumber),
                  ]),
                  if (purchaseDate != null || warrantyUntil != null) ...[
                    const SizedBox(height: 24),
                    _buildDetailSection('Compra y Garantía', [
                      if (purchaseDate != null)
                        _DetailRow(
                          'Fecha de compra',
                          ChileanUtils.formatDate(DateTime.parse(purchaseDate)),
                        ),
                      if (warrantyUntil != null)
                        _DetailRow(
                          'Garantía hasta',
                          ChileanUtils.formatDate(
                              DateTime.parse(warrantyUntil)),
                          valueColor: DateTime.parse(warrantyUntil)
                                  .isAfter(DateTime.now())
                              ? Colors.green
                              : Colors.red,
                        ),
                    ]),
                  ],
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Notas',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        notes,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.go(
                            '/tienda/cuenta/servicios?bike_id=${bike['id']}');
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('VER HISTORIAL COMPLETO'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...rows.map((row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(row.label, style: TextStyle(color: Colors.grey[600])),
                  Text(
                    row.value,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: row.valueColor ?? Colors.black87,
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
