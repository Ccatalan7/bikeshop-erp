import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';

class CustomerBikeDirectoryPage extends StatefulWidget {
  const CustomerBikeDirectoryPage({super.key});

  @override
  State<CustomerBikeDirectoryPage> createState() =>
      _CustomerBikeDirectoryPageState();
}

class _CustomerBikeDirectoryPageState extends State<CustomerBikeDirectoryPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Bike> _bikes = [];
  List<Bike> _filteredBikes = [];
  Map<String, Customer> _customers = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();

      final results = await Future.wait([
        bikeshopService.getBikes(),
        customerService.getCustomers(),
      ]);

      final bikes = results[0] as List<Bike>;
      final customersList = results[1] as List<Customer>;
      final customerMap = <String, Customer>{
        for (final customer in customersList)
          if (customer.id != null) customer.id!: customer
      };

      setState(() {
        _customers = customerMap;
        _bikes = bikes;
        _filteredBikes = bikes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar bicicletas: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final search = _searchController.text.trim().toLowerCase();

    if (search.isEmpty) {
      setState(() => _filteredBikes = _bikes);
      return;
    }

    final filtered = _bikes.where((bike) {
      final customer = _customers[bike.customerId];
      final matchesOwner =
          customer?.name.toLowerCase().contains(search) ?? false;
      final matchesRut = customer?.rut.toLowerCase().contains(search) ?? false;
      final matchesEmail =
          customer?.email?.toLowerCase().contains(search) ?? false;
      final matchesPhone =
          customer?.phone?.toLowerCase().contains(search) ?? false;
      final matchesBike = bike.displayName.toLowerCase().contains(search);
      final matchesSerial =
          bike.serialNumber?.toLowerCase().contains(search) ?? false;

      return matchesOwner ||
          matchesRut ||
          matchesEmail ||
          matchesPhone ||
          matchesBike ||
          matchesSerial;
    }).toList();

    setState(() => _filteredBikes = filtered);
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Bicicletas registradas',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSearchField(),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalBikes = _bikes.length;
    final uniqueCustomers =
        _bikes.map((bike) => bike.customerId).toSet().length;

    return Row(
      children: [
        Text(
          'Directorio de bicicletas',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        Chip(
          label: Text('$totalBikes bicicletas'),
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
        ),
        const SizedBox(width: 8),
        Chip(
          label: Text('$uniqueCustomers clientes'),
          backgroundColor:
              Theme.of(context).colorScheme.secondary.withOpacity(0.1),
        ),
        const Spacer(),
        IconButton(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar',
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Buscar por cliente, bicicleta, serie, RUT o contacto',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_filteredBikes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pedal_bike_outlined, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('No se encontraron bicicletas'),
            const SizedBox(height: 12),
            Text(
              'Prueba ajustando los filtros o agregando una nueva bicicleta desde el perfil del cliente.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _filteredBikes.length,
      itemBuilder: (context, index) {
        final bike = _filteredBikes[index];
        final customer = _customers[bike.customerId];
        return _buildBikeTile(bike, customer);
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
    );
  }

  Widget _buildBikeTile(Bike bike, Customer? owner) {
    final theme = Theme.of(context);
    final ownerNameRaw = owner != null ? owner.name.trim() : '';
    final ownerInitials = ownerNameRaw.isNotEmpty
        ? ownerNameRaw
            .split(RegExp(r'\s+'))
            .map((word) => word[0])
            .take(2)
            .join()
            .toUpperCase()
        : '?';
    final ownerName =
        ownerNameRaw.isNotEmpty ? ownerNameRaw : 'Cliente desconocido';
    final bikeName =
        bike.displayName.isNotEmpty ? bike.displayName : 'Bicicleta sin nombre';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
          child: Text(
            ownerInitials,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          bikeName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(ownerName, style: TextStyle(color: Colors.grey[700])),
            if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Serie: ${bike.serialNumber}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
            if (bike.bikeType != null) ...[
              const SizedBox(height: 2),
              Text('Tipo: ${bike.bikeType!.displayName}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
            if (bike.isUnderWarranty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.verified_user, size: 14, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text('En garantía',
                      style: TextStyle(color: Colors.green[700], fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: owner?.id != null
                  ? () => context.push('/clientes/${owner!.id}?tab=bicicletas')
                  : null,
              icon: const Icon(Icons.person_outline),
              label: const Text('Abrir cliente'),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => context.push(
                  '/taller/pegas/nueva?customer_id=${bike.customerId}&bike_id=${bike.id ?? ''}'),
              icon: const Icon(Icons.build),
              label: const Text('Nueva pega'),
            ),
          ],
        ),
      ),
    );
  }
}
