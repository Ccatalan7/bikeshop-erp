import 'package:flutter/material.dart';
import '../../../shared/models/bike_catalog_models.dart';
import '../../../shared/services/bike_catalog_service.dart';
import '../../../shared/widgets/branded_loading.dart';

/// Bike Encyclopedia - Demo page to browse and search bike catalog
class BikeEncyclopediaPage extends StatefulWidget {
  const BikeEncyclopediaPage({super.key});
  
  @override
  State<BikeEncyclopediaPage> createState() => _BikeEncyclopediaPageState();
}

class _BikeEncyclopediaPageState extends State<BikeEncyclopediaPage> {
  final BikeCatalogService _service = BikeCatalogService();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  
  List<BikeCatalogEntry> _bikes = [];
  BikeCatalogEntry? _selectedBike;
  bool _loading = false;
  int _totalCount = 0;
  
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    super.dispose();
  }
  
  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final count = await _service.getTotalCount();
      final bikes = await _service.getAllBikes(limit: 50);
      setState(() {
        _totalCount = count;
        _bikes = bikes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bikes: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }
  
  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final bikes = await _service.searchBikes(
        brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
        model: _modelController.text.trim().isEmpty ? null : _modelController.text.trim(),
      );
      setState(() {
        _bikes = bikes;
        _selectedBike = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚴 Bike Encyclopedia'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Row(
          children: [
            // Left panel: Search + List
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // Search bar
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey[100],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search Bike Catalog',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _brandController,
                                decoration: const InputDecoration(
                                  labelText: 'Brand',
                                  hintText: 'e.g., Trek, Specialized',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onSubmitted: (_) => _search(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _modelController,
                                decoration: const InputDecoration(
                                  labelText: 'Model',
                                  hintText: 'e.g., Marlin, FX',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onSubmitted: (_) => _search(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _loading ? null : _search,
                              icon: const Icon(Icons.search),
                              label: const Text('Search'),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                _brandController.clear();
                                _modelController.clear();
                                _loadInitialData();
                              },
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear filters',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total bikes in catalog: $_totalCount',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(height: 1),
                  
                  // Bikes list
                  Expanded(
                    child: _loading
                        ? const Center(child: BrandedLoading())
                        : _bikes.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.directions_bike, size: 64, color: Colors.grey[400]),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No bikes found',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try different search terms or run the feeder script',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _bikes.length,
                                itemBuilder: (context, index) {
                                  final bike = _bikes[index];
                                  final isSelected = _selectedBike?.id == bike.id;
                                  
                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor: Colors.blue[50],
                                    leading: bike.imageUrl != null
                                        ? Image.network(
                                            bike.imageUrl!,
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.directions_bike, size: 40),
                                          )
                                        : const Icon(Icons.directions_bike, size: 40),
                                    title: Text(
                                      bike.displayName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      [
                                        if (bike.bikeType != null) bike.bikeType!.toUpperCase(),
                                        if (bike.wheelSize != null) bike.wheelSize,
                                        if (bike.frameMaterial != null) bike.frameMaterial,
                                      ].join(' • '),
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      setState(() => _selectedBike = bike);
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            
            // Right panel: Details
            Expanded(
              flex: 3,
              child: _selectedBike == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Select a bike to view details',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildBikeDetails(_selectedBike!),
            ),
          ],
        ),
    );
  }
  
  Widget _buildBikeDetails(BikeCatalogEntry bike) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              if (bike.imageUrl != null)
                Image.network(
                  bike.imageUrl!,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.directions_bike, size: 80),
                ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bike.displayName,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (bike.bikeType != null)
                      Chip(
                        label: Text(bike.bikeType!.toUpperCase()),
                        backgroundColor: Colors.blue[100],
                      ),
                  ],
                ),
              ),
            ],
          ),
          
          const Divider(height: 40),
          
          // Specs sections
          _buildSpecSection(
            '🚵 Frame & Geometry',
            [
              if (bike.frameMaterial != null) _buildSpecRow('Material', bike.frameMaterial!),
              if (bike.wheelSize != null) _buildSpecRow('Wheel Size', bike.wheelSize!),
              if (bike.frameSizeRange != null) _buildSpecRow('Sizes', bike.frameSizeRange!.join(', ')),
              if (bike.weightKg != null) _buildSpecRow('Weight', '${bike.weightKg} kg'),
            ],
          ),
          
          _buildSpecSection(
            '⚙️ Drivetrain',
            [
              if (bike.drivetrainSpeeds != null) _buildSpecRow('Speeds', '${bike.drivetrainSpeeds}-speed'),
              if (bike.drivetrainConfig != null) _buildSpecRow('Configuration', bike.drivetrainConfig!),
              if (bike.cassetteRange != null) _buildSpecRow('Cassette', bike.cassetteRange!),
              if (bike.cranksetModel != null) _buildSpecRow('Crankset', bike.cranksetModel!),
              if (bike.rearDerailleurModel != null) _buildSpecRow('Rear Derailleur', bike.rearDerailleurModel!),
              if (bike.frontDerailleurModel != null) _buildSpecRow('Front Derailleur', bike.frontDerailleurModel!),
            ],
          ),
          
          _buildSpecSection(
            '🛑 Brakes',
            [
              if (bike.brakeType != null) _buildSpecRow('Type', bike.brakeType!),
              if (bike.brakeModel != null) _buildSpecRow('Model', bike.brakeModel!),
              if (bike.brakeRotorSizeFrontMm != null) _buildSpecRow('Rotor Front', '${bike.brakeRotorSizeFrontMm}mm'),
              if (bike.brakeRotorSizeRearMm != null) _buildSpecRow('Rotor Rear', '${bike.brakeRotorSizeRearMm}mm'),
            ],
          ),
          
          _buildSpecSection(
            '🛞 Wheels & Hubs',
            [
              if (bike.frontHubModel != null) _buildSpecRow('Front Hub', bike.frontHubModel!),
              if (bike.rearHubModel != null) _buildSpecRow('Rear Hub', bike.rearHubModel!),
              if (bike.frontHubSpacingMm != null) _buildSpecRow('Front Spacing', '${bike.frontHubSpacingMm}mm'),
              if (bike.rearHubSpacingMm != null) _buildSpecRow('Rear Spacing', '${bike.rearHubSpacingMm}mm'),
              if (bike.frontAxleType != null) _buildSpecRow('Front Axle', bike.frontAxleType!),
              if (bike.rearAxleType != null) _buildSpecRow('Rear Axle', bike.rearAxleType!),
              if (bike.freehubType != null) _buildSpecRow('Freehub', bike.freehubType!),
              if (bike.spokeCount != null) _buildSpecRow('Spoke Count', '${bike.spokeCount}H'),
            ],
          ),
          
          _buildSpecSection(
            '🚴 Tires',
            [
              if (bike.tireSizeFront != null) _buildSpecRow('Front', bike.tireSizeFront!),
              if (bike.tireSizeRear != null) _buildSpecRow('Rear', bike.tireSizeRear!),
              if (bike.maxTireWidthMm != null) _buildSpecRow('Max Width', '${bike.maxTireWidthMm}mm'),
            ],
          ),
          
          _buildSpecSection(
            '🎯 Cockpit',
            [
              if (bike.handlebarType != null) _buildSpecRow('Handlebar', bike.handlebarType!),
              if (bike.stemLengthMm != null) _buildSpecRow('Stem Length', '${bike.stemLengthMm}mm'),
              if (bike.seatpostDiameterMm != null) _buildSpecRow('Seatpost', '${bike.seatpostDiameterMm}mm'),
            ],
          ),
          
          // Data source info
          const Divider(height: 40),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data Source',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Source: ${bike.dataSource}'),
                if (bike.dataConfidence != null)
                  Text('Confidence: ${(bike.dataConfidence! * 100).toStringAsFixed(0)}%'),
                if (bike.lastVerifiedAt != null)
                  Text('Last verified: ${bike.lastVerifiedAt!.toString().split(' ')[0]}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSpecSection(String title, List<Widget> specs) {
    if (specs.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...specs,
        const SizedBox(height: 24),
      ],
    );
  }
  
  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
