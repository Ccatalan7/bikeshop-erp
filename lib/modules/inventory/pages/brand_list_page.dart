import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../models/brand_models.dart';
import '../services/brand_service.dart';

class BrandListPage extends StatefulWidget {
  const BrandListPage({super.key});

  @override
  State<BrandListPage> createState() => _BrandListPageState();
}

class _BrandListPageState extends State<BrandListPage> {
  late BrandService _brandService;
  final TextEditingController _searchController = TextEditingController();

  List<ProductBrand> _brands = [];
  List<ProductBrand> _filteredBrands = [];
  bool _isLoading = true;
  bool _showInactiveOnly = false;
  String? _selectedCountry;

  @override
  void initState() {
    super.initState();
    _brandService = BrandService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _loadBrands();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    setState(() => _isLoading = true);
    try {
      final brands = await _brandService.getBrands();
      setState(() {
        _brands = brands;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando marcas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyFilters() {
    var filtered = List<ProductBrand>.from(_brands);
    final term = _searchController.text.trim().toLowerCase();

    if (term.isNotEmpty) {
      filtered = filtered.where((brand) {
        final description = brand.description ?? '';
        final website = brand.website ?? '';
        final country = brand.country ?? '';
        return brand.name.toLowerCase().contains(term) ||
            description.toLowerCase().contains(term) ||
            website.toLowerCase().contains(term) ||
            country.toLowerCase().contains(term);
      }).toList();
    }

    if (_showInactiveOnly) {
      filtered = filtered.where((brand) => !brand.isActive).toList();
    }

    if (_selectedCountry != null && _selectedCountry!.isNotEmpty) {
      filtered = filtered
          .where((brand) =>
              brand.country?.toLowerCase() ==
              _selectedCountry!.trim().toLowerCase())
          .toList();
    }

    filtered.sort((a, b) => a.name.compareTo(b.name));
    setState(() => _filteredBrands = filtered);
  }

  Future<void> _toggleBrandStatus(ProductBrand brand) async {
    try {
      await _brandService.toggleBrandStatus(brand.id!);
      await _loadBrands();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            brand.isActive ? 'Marca desactivada' : 'Marca activada',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cambiando estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteBrand(ProductBrand brand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar marca'),
        content: Text(
          '¿Estás seguro de eliminar la marca "${brand.name}"? Esta acción no se puede deshacer.',
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

    if (confirmed != true) return;

    try {
      await _brandService.deleteBrand(brand.id!);
      await _loadBrands();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marca eliminada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar la marca: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Set<String> get _availableCountries {
    final countries = _brands
        .map((brand) => brand.country?.trim() ?? '')
        .where((country) => country.isNotEmpty)
        .toSet();
    return countries;
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          _buildHeader(context),
          SearchBarWidget(
            controller: _searchController,
            hintText: 'Buscar por nombre, país o sitio web...',
            onChanged: (_) => _applyFilters(),
          ),
          _buildFilters(context),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildBrandListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final activeCount = _brands.where((brand) => brand.isActive).length;
    final inactiveCount = _brands.length - activeCount;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Marcas',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildStatChip(Icons.check_circle, 'Activas', activeCount,
              Colors.green.shade600),
          const SizedBox(width: 8),
          _buildStatChip(Icons.pause_circle, 'Inactivas', inactiveCount,
              Colors.orange.shade600),
          const SizedBox(width: 16),
          AppButton(
            text: 'Nueva Marca',
            icon: Icons.add,
            onPressed: () async {
              await context.push('/inventory/brands/new');
              if (!mounted) return;
              await _loadBrands();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final countries = _availableCountries.toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.start,
        children: [
          FilterChip(
            label: const Text('Solo inactivas'),
            selected: _showInactiveOnly,
            onSelected: (value) {
              setState(() => _showInactiveOnly = value);
              _applyFilters();
            },
          ),
          if (countries.isNotEmpty)
            DropdownButton<String?>(
              value: _selectedCountry,
              hint: const Text('Filtrar por país'),
              onChanged: (value) {
                setState(() => _selectedCountry = value);
                _applyFilters();
              },
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos los países'),
                ),
                ...countries.map(
                  (country) => DropdownMenuItem<String?>(
                    value: country,
                    child: Text(country),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBrandListView() {
    if (_filteredBrands.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadBrands,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.sell_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No se encontraron marcas',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBrands,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
        itemCount: _filteredBrands.length,
        itemBuilder: (context, index) {
          final brand = _filteredBrands[index];
          return _buildBrandTile(brand);
        },
      ),
    );
  }

  Widget _buildBrandTile(ProductBrand brand) {
    final theme = Theme.of(context);
    final subtitle = <String>[
      if (brand.description != null && brand.description!.isNotEmpty)
        brand.description!,
      if (brand.website != null && brand.website!.isNotEmpty)
        brand.website!,
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          child: Icon(
            Icons.sell_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          brand.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: Text(subtitle),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: Icon(
                    brand.isActive ? Icons.check_circle : Icons.pause_circle,
                    size: 18,
                    color: brand.isActive ? Colors.green : Colors.orange,
                  ),
                  label: Text(brand.isActive ? 'Activa' : 'Inactiva'),
                  backgroundColor: (brand.isActive
                          ? Colors.greenAccent
                          : Colors.orangeAccent)
                      .withOpacity(0.18),
                ),
                Chip(
                  avatar: const Icon(Icons.public, size: 18),
                  label: Text(brand.country?.isNotEmpty == true
                      ? brand.country!
                      : 'País no especificado'),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                context.push('/inventory/brands/${brand.id}/edit').then((_) {
                  _loadBrands();
                });
                break;
              case 'toggle':
                _toggleBrandStatus(brand);
                break;
              case 'delete':
                _deleteBrand(brand);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Editar'),
              ),
            ),
            PopupMenuItem(
              value: 'toggle',
              child: ListTile(
                leading: Icon(
                  brand.isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                title: Text(brand.isActive ? 'Desactivar' : 'Activar'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Eliminar'),
              ),
            ),
          ],
        ),
        onTap: () {
          context.push('/inventory/brands/${brand.id}/edit').then((_) {
            _loadBrands();
          });
        },
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withOpacity(0.1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }
}
