import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/image_service.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  late CustomerService _customerService;
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchTerm = '';
  
  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 50;
  int get _totalPages => (_filteredCustomers.length / _itemsPerPage).ceil();
  List<Customer> get _paginatedCustomers {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, _filteredCustomers.length);
    return _filteredCustomers.sublist(startIndex, endIndex);
  }

  @override
  void initState() {
    super.initState();
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });
    try {
      final customers = await _customerService.getCustomers();
      setState(() {
        _customers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando clientes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
      if (searchTerm.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers
            .where((customer) =>
                customer.name
                    .toLowerCase()
                    .contains(searchTerm.toLowerCase()) ||
                (customer.rut.isNotEmpty &&
                    customer.rut
                        .toLowerCase()
                        .contains(searchTerm.toLowerCase())) ||
                (customer.email
                        ?.toLowerCase()
                        .contains(searchTerm.toLowerCase()) ??
                    false))
            .toList();
      }
    });
  }

  Future<void> _confirmDelete(Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Estás seguro de que deseas eliminar a este cliente?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                      'RUT: ${customer.rut.isEmpty ? "Sin RUT" : customer.rut}'),
                  if (customer.email != null) Text('Email: ${customer.email}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '⚠️ Esta acción no se puede deshacer.',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Ensure customer.id is not null before deleting
        if (customer.id == null || customer.id!.isEmpty) {
          throw Exception('ID de cliente inválido');
        }

        await _customerService.deleteCustomer(customer.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Cliente "${customer.name}" eliminado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadCustomers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar cliente: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
                    'Clientes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nuevo Cliente',
                  icon: Icons.person_add,
                  onPressed: () {
                    context.push('/clientes/nuevo').then((_) {
                      _loadCustomers();
                    });
                  },
                ),
              ],
            ),
          ),

          // Search
          SearchWidget(
            hintText: 'Buscar por nombre, RUT o email...',
            onSearchChanged: _onSearchChanged,
          ),

          // Stats
          if (!_isLoading && _customers.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildStatItem('Total', _customers.length.toString()),
                  const SizedBox(width: 24),
                  _buildStatItem('Activos',
                      _customers.where((c) => c.isActive).length.toString()),
                  const SizedBox(width: 24),
                  _buildStatItem(
                      'Mostrando', _filteredCustomers.length.toString()),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildCustomersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.blue[700],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomersList() {
    if (_filteredCustomers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay clientes registrados'
                  : 'No se encontraron clientes',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Agregar Primer Cliente',
                onPressed: () {
                  context.push('/clientes/nuevo').then((_) {
                    _loadCustomers();
                  });
                },
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCustomers,
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _paginatedCustomers.length,
              itemBuilder: (context, index) {
                final customer = _paginatedCustomers[index];
                return _buildCustomerCard(customer);
              },
            ),
          ),
        ),
        // Pagination controls at the bottom
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          context.push('/clientes/${customer.id}').then((_) {
            _loadCustomers();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Avatar
              ImageService.buildAvatarImage(
                imageUrl: customer.imageUrl,
                radius: 30,
                initials: customer.initials,
              ),
              const SizedBox(width: 16),

              // Customer info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!customer.isActive)
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
                    if (customer.rut.isNotEmpty)
                      Text(
                        'RUT: ${customer.rut}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (customer.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.email!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (customer.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.phone!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (customer.region != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            customer.region!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Actions - 3-dot menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Opciones',
                onSelected: (value) async {
                  if (value == 'edit') {
                    context.push('/clientes/${customer.id}/editar').then((_) {
                      _loadCustomers();
                    });
                  } else if (value == 'delete') {
                    _confirmDelete(customer);
                  } else if (value == 'view') {
                    context.push('/clientes/${customer.id}').then((_) {
                      _loadCustomers();
                    });
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility, size: 20),
                        SizedBox(width: 12),
                        Text('Ver Detalles'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 12),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationControls() {
    if (_totalPages <= 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Page info
          Text(
            'Página $_currentPage de $_totalPages (${_filteredCustomers.length} clientes)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Navigation controls
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 1 ? _goToFirstPage : null,
                tooltip: 'Primera página',
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1 ? _previousPage : null,
                tooltip: 'Página anterior',
              ),
              // Page selector dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentPage,
                    items: List.generate(_totalPages, (index) {
                      final pageNum = index + 1;
                      return DropdownMenuItem(
                        value: pageNum,
                        child: Text('$pageNum'),
                      );
                    }),
                    onChanged: (page) {
                      if (page != null) _goToPage(page);
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages ? _nextPage : null,
                tooltip: 'Página siguiente',
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < _totalPages ? _goToLastPage : null,
                tooltip: 'Última página',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToFirstPage() {
    setState(() => _currentPage = 1);
  }

  void _previousPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      setState(() => _currentPage++);
    }
  }

  void _goToLastPage() {
    setState(() => _currentPage = _totalPages);
  }

  void _goToPage(int page) {
    if (page >= 1 && page <= _totalPages) {
      setState(() => _currentPage = page);
    }
  }
}
