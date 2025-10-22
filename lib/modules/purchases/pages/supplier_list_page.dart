import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../services/purchase_service.dart';

enum SupplierViewMode { list, cards }

class SupplierListPage extends StatefulWidget {
  const SupplierListPage({super.key});

  @override
  State<SupplierListPage> createState() => _SupplierListPageState();
}

class _SupplierListPageState extends State<SupplierListPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Supplier> _suppliers = const [];
  List<Supplier> _filteredSuppliers = const [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  SupplierViewMode _viewMode = SupplierViewMode.list;

  late PurchaseService _purchaseService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _purchaseService = context.read<PurchaseService>();
      _loadSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      setState(() => _isLoading = true);
      final suppliers = await _purchaseService.getSuppliers(forceRefresh: true);
      setState(() {
        _suppliers = suppliers;
        _filteredSuppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar proveedores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterSuppliers(String query) {
    setState(() {
      _filteredSuppliers = _suppliers.where((supplier) {
        final matchesSearch = query.isEmpty ||
            supplier.name.toLowerCase().contains(query.toLowerCase()) ||
            (supplier.rut?.toLowerCase().contains(query.toLowerCase()) ??
                false) ||
            (supplier.email?.toLowerCase().contains(query.toLowerCase()) ??
                false);

        final matchesFilter = _selectedFilter == 'all' ||
            (_selectedFilter == 'active' && supplier.isActive) ||
            (_selectedFilter == 'inactive' && !supplier.isActive);

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Proveedores',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // View mode toggle
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.view_list),
                        onPressed: () =>
                            setState(() => _viewMode = SupplierViewMode.list),
                        color: _viewMode == SupplierViewMode.list
                            ? Colors.blue
                            : Colors.grey,
                        tooltip: 'Vista de lista',
                      ),
                      IconButton(
                        icon: const Icon(Icons.grid_view),
                        onPressed: () =>
                            setState(() => _viewMode = SupplierViewMode.cards),
                        color: _viewMode == SupplierViewMode.cards
                            ? Colors.blue
                            : Colors.grey,
                        tooltip: 'Vista de tarjetas',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  text: 'Nuevo Proveedor',
                  icon: Icons.add,
                  onPressed: () async {
                    final created =
                        await context.push<bool>('/purchases/suppliers/new');
                    if (created == true) {
                      _loadSuppliers();
                    }
                  },
                ),
              ],
            ),
          ),

          // Search and filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                SearchBarWidget(
                  controller: _searchController,
                  hintText: 'Buscar por nombre, RUT o email...',
                  onChanged: _filterSuppliers,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Estado: '),
                    DropdownButton<String>(
                      value: _selectedFilter,
                      onChanged: (value) {
                        setState(() => _selectedFilter = value!);
                        _filterSuppliers(_searchController.text);
                      },
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Activos')),
                        DropdownMenuItem(
                            value: 'inactive', child: Text('Inactivos')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? _buildEmptyState()
                    : _buildSupplierList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay proveedores registrados',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega tu primer proveedor para comenzar',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Agregar Proveedor',
              icon: Icons.add,
              onPressed: () async {
                final created =
                    await context.push<bool>('/purchases/suppliers/new');
                if (created == true) {
                  _loadSuppliers();
                }
              },
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 72,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No encontramos resultados',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Intenta con otros términos de búsqueda',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierList() {
    return _viewMode == SupplierViewMode.list
        ? ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _filteredSuppliers.length,
            itemBuilder: (context, index) {
              final supplier = _filteredSuppliers[index];
              return _buildSupplierListItem(supplier);
            },
          )
        : GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: _filteredSuppliers.length,
            itemBuilder: (context, index) {
              final supplier = _filteredSuppliers[index];
              return _buildSupplierGridItem(supplier);
            },
          );
  }

  Widget _buildSupplierListItem(Supplier supplier) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        onTap: () {
          // Navigate to products filtered by this supplier
          context.push('/inventory/products?supplier=${supplier.id}');
        },
        leading: CircleAvatar(
          backgroundColor: supplier.isActive ? Colors.green : Colors.grey,
          child: Text(
            supplier.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          supplier.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplier.rut != null && supplier.rut!.isNotEmpty)
              Text('RUT: ${ChileanUtils.formatRut(supplier.rut!)}'),
            if (supplier.email != null) Text(supplier.email!),
            if (supplier.phone != null) Text('Tel: ${supplier.phone}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!supplier.isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Inactivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  context
                      .push('/purchases/suppliers/${supplier.id}/edit')
                      .then((updated) {
                    if (updated == true) {
                      _loadSuppliers();
                    }
                  });
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              child: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierGridItem(Supplier supplier) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Navigate to products filtered by this supplier
          context.push('/inventory/products?supplier=${supplier.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        supplier.isActive ? Colors.green : Colors.grey,
                    child: Text(
                      supplier.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        context
                            .push('/purchases/suppliers/${supplier.id}/edit')
                            .then((updated) {
                          if (updated == true) {
                            _loadSuppliers();
                          }
                        });
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
                    ],
                    child: Icon(Icons.more_vert,
                        size: 20, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                supplier.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (supplier.rut != null && supplier.rut!.isNotEmpty)
                Text(
                  'RUT: ${ChileanUtils.formatRut(supplier.rut!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              if (supplier.email != null) ...[
                const SizedBox(height: 4),
                Text(
                  supplier.email!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (supplier.phone != null) ...[
                const SizedBox(height: 4),
                Text(
                  supplier.phone!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: supplier.isActive ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  supplier.isActive ? 'Activo' : 'Inactivo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
