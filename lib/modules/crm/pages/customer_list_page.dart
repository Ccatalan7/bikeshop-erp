import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';

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

  // Mobile UI state
  bool _isSearchExpanded = false;

  // Pagination
  int _currentPage = 1;
  final int _itemsPerPage = 50;
  int get _totalPages => (_filteredCustomers.length / _itemsPerPage).ceil();
  List<Customer> get _paginatedCustomers {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex =
        (startIndex + _itemsPerPage).clamp(0, _filteredCustomers.length);
    return _filteredCustomers.sublist(startIndex, endIndex);
  }

  // Table state
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  
  static const double _minColumnWidth = 80.0;
  static const double _maxColumnWidth = 400.0;

  final Map<String, double> _columnWidths = {
    'name': 250.0,
    'rut': 120.0,
    'email': 200.0,
    'phone': 150.0,
    'region': 180.0,
    'bikes': 180.0,
    'status': 100.0,
  };

  final Map<String, bool> _visibleColumns = {
    'name': true,
    'rut': true,
    'email': true,
    'phone': true,
    'region': true,
    'bikes': true,
    'status': true,
  };

  Map<String, List<Bike>> _bikesByCustomer = {};

  String _sortColumn = 'name';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _loadCustomers();

    // Sync scroll positions
    _headerScrollController.addListener(() {
      if (_bodyScrollController.offset != _headerScrollController.offset) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
    });

    _bodyScrollController.addListener(() {
      if (_headerScrollController.offset != _bodyScrollController.offset) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var key in _columnWidths.keys.toList()) {
        _columnWidths[key] =
            prefs.getDouble('customer_col_$key') ?? _columnWidths[key]!;
      }

      for (var key in _visibleColumns.keys.toList()) {
        _visibleColumns[key] =
            prefs.getBool('customer_visible_$key') ?? _visibleColumns[key]!;
      }
    });
  }

  Future<void> _saveColumnWidth(String column, double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('customer_col_$column', width);
  }

  Future<void> _saveColumnVisibility(String column, bool isVisible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('customer_visible_$column', isVisible);
  }

  Future<void> _loadCustomers() async {
    // Grab services before async gaps
    final bikeshopService = context.read<BikeshopService>();

    // 🚀 INSTANT RENDER: Show cached data immediately if available
    if (_customerService.hasCustomersCache && _customers.isEmpty) {
      setState(() {
        _customers = _customerService.cachedCustomers;
        _filteredCustomers = _customers;
        _isLoading = false;
        _currentPage = 1;
      });
      // Apply search filter if any
      if (_searchTerm.isNotEmpty) {
        _onSearchChanged(_searchTerm);
      } else {
        _applyFiltersAndSort();
      }
    } else {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
      });
    }

    try {
      // Fetch fresh data (will use cache if still valid)
      final customers = await _customerService.getCustomers();
      
      // Load Bikes mapping
      final allBikes = await bikeshopService.getBikes();
      final Map<String, List<Bike>> bikesMap = {};
      for (var bike in allBikes) {
        if (bike.customerId.isNotEmpty) {
          bikesMap.putIfAbsent(bike.customerId, () => []).add(bike);
        }
      }

      if (mounted) {
        setState(() {
          _customers = customers;
          _filteredCustomers = customers;
          _bikesByCustomer = bikesMap;
          _isLoading = false;
        });
        // Apply search filter if any
        if (_searchTerm.isNotEmpty) {
          _onSearchChanged(_searchTerm);
        } else {
          _applyFiltersAndSort();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    List<Customer> filtered = List.from(_customers);

    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      filtered = filtered.where((customer) {
        return customer.name.toLowerCase().contains(term) ||
            (customer.rut.isNotEmpty &&
                customer.rut.toLowerCase().contains(term)) ||
            (customer.email?.toLowerCase().contains(term) ?? false);
      }).toList();
    }

    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortColumn) {
        case 'name':
          comparison = a.name.compareTo(b.name);
          break;
        case 'rut':
          comparison = a.rut.compareTo(b.rut);
          break;
        case 'email':
          comparison = (a.email ?? '').compareTo(b.email ?? '');
          break;
        case 'phone':
          comparison = (a.phone ?? '').compareTo(b.phone ?? '');
          break;
        case 'region':
          comparison = (a.region ?? '').compareTo(b.region ?? '');
          break;
        case 'status':
          // Simple active/inactive sort (true comes first generally, but let's compare as int)
          comparison = (a.isActive ? 1 : 0).compareTo(b.isActive ? 1 : 0);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    _filteredCustomers = filtered;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _applyFiltersAndSort();
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          if (isMobile) {
            return _buildMobileLayout();
          }

          return _buildDesktopLayout();
        },
      ),
    );
  }

  // ============ MOBILE LAYOUT ============

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Compact Mobile Header
        _buildMobileHeader(),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: BrandedLoading())
              : _buildCustomersList(),
        ),
      ],
    );
  }

  Widget _buildMobileHeader() {
    final theme = Theme.of(context);

    if (_isSearchExpanded) {
      // Expanded search mode
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: TextField(
          autofocus: true,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, RUT o email...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () {
                _onSearchChanged('');
                setState(() => _isSearchExpanded = false);
              },
            ),
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
    }

    // Collapsed header
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            'Clientes',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_filteredCustomers.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _isSearchExpanded = true),
            tooltip: 'Buscar',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              context.push('/clientes/nuevo').then((_) => _loadCustomers());
            },
            tooltip: 'Nuevo cliente',
          ),
        ],
      ),
    );
  }

  // ============ DESKTOP LAYOUT ============

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Title Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Clientes',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[800],
                        ),
                  ),
                  if (!_isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_filteredCustomers.length} cliente${_filteredCustomers.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              
              const Spacer(),
              
              // Search Widget (Moved to header)
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey[100],
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Action Buttons
              Container(
                height: 38,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Actualizar',
                      color: Colors.grey[700],
                      onPressed: _loadCustomers,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                      padding: EdgeInsets.zero,
                    ),
                    Container(width: 1, color: Colors.grey[300]),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.view_column_outlined, size: 20, color: Colors.grey[700]),
                      tooltip: 'Columnas',
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) {
                        return _visibleColumns.keys.map((column) {
                          return CheckedPopupMenuItem<String>(
                            value: column,
                            checked: _visibleColumns[column] ?? false,
                            child: Text(
                              column == 'name' ? 'Cliente' :
                              column == 'rut' ? 'RUT' :
                              column == 'email' ? 'Email' :
                              column == 'phone' ? 'Teléfono' :
                              column == 'region' ? 'Región' :
                              column == 'bikes' ? 'Bicicletas' :
                              column == 'status' ? 'Estado' : column
                            ),
                          );
                        }).toList();
                      },
                      onSelected: (column) {
                        setState(() {
                          _visibleColumns[column] = !(_visibleColumns[column] ?? false);
                        });
                        _saveColumnVisibility(column, _visibleColumns[column] ?? false);
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
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

        // Optional extra spacing below header if you want
        const SizedBox(height: 16),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: BrandedLoading())
              : _buildCustomersTable(),
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

  Widget _buildCustomersTable() {
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

    final theme = Theme.of(context);

    // Compute total width based on visible columns
    double totalTableWidth = 60; // 60px for actions menu at the end
    _visibleColumns.forEach((key, isVisible) {
      if (isVisible) {
        totalTableWidth += (_columnWidths[key] ?? 100.0) + 1; // +1 for divider
      }
    });

    return Column(
      children: [
        // ERP Table Header
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            controller: _headerScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(), // Important to sync properly
            child: SizedBox(
              width: totalTableWidth < MediaQuery.of(context).size.width - 32 
                  ? MediaQuery.of(context).size.width - 32 
                  : totalTableWidth,
              child: Row(
                children: [
                  const SizedBox(width: 16), // Left padding
                  if (_visibleColumns['name'] == true)
                    _buildColumnHeaderCell('name', 'CLIENTE'),
                  if (_visibleColumns['rut'] == true)
                    _buildColumnHeaderCell('rut', 'RUT'),
                  if (_visibleColumns['email'] == true)
                    _buildColumnHeaderCell('email', 'EMAIL'),
                  if (_visibleColumns['phone'] == true)
                    _buildColumnHeaderCell('phone', 'TELÉFONO'),
                  if (_visibleColumns['region'] == true)
                    _buildColumnHeaderCell('region', 'REGIÓN'),
                  if (_visibleColumns['bikes'] == true)
                    _buildColumnHeaderCell('bikes', 'BICICLETAS'),
                  if (_visibleColumns['status'] == true)
                    _buildColumnHeaderCell('status', 'ESTADO'),
                  
                  // Action column header
                  Container(
                    width: 44,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCustomers,
            child: SingleChildScrollView(
              controller: _bodyScrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalTableWidth < MediaQuery.of(context).size.width - 32 
                    ? MediaQuery.of(context).size.width - 32 
                    : totalTableWidth,
                child: ListView.builder(
                  itemCount: _paginatedCustomers.length,
                  itemBuilder: (context, index) {
                    final customer = _paginatedCustomers[index];
                    return _buildTableRow(customer, theme, index.isEven);
                  },
                ),
              ),
            ),
          ),
        ),
        // Pagination controls at the bottom
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildColumnHeaderCell(String columnKey, String label) {
    final isSorted = _sortColumn == columnKey;
    final width = _columnWidths[columnKey] ?? 100.0;
    final theme = Theme.of(context);

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _onSort(columnKey),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: isSorted ? theme.colorScheme.primary : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSorted)
                    Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
          _buildResizeHandle(columnKey),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(String columnKey) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        setState(() {
          final newWidth = (_columnWidths[columnKey] ?? 100.0) + details.delta.dx;
          _columnWidths[columnKey] = newWidth.clamp(_minColumnWidth, _maxColumnWidth);
        });
      },
      onHorizontalDragEnd: (_) {
        _saveColumnWidth(columnKey, _columnWidths[columnKey] ?? 100.0);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 8,
          height: double.infinity,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              height: 20,
              color: Colors.grey[300], // Subtle separator only in header
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableRow(Customer customer, ThemeData theme, bool isEven) {
    return InkWell(
      onTap: () {
        context.push('/clientes/${customer.id}').then((_) {
          _loadCustomers();
        });
      },
      hoverColor: Colors.blue[50]?.withValues(alpha: 0.5),
      child: Container(
        height: 52, // ERP standard row height
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16), // Left padding
            if (_visibleColumns['name'] == true)
              _buildDataCell('name', Row(
                children: [
                  ImageService.buildAvatarImage(
                    imageUrl: customer.imageUrl,
                    radius: 14, // Slightly smaller
                    initials: customer.initials,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customer.name, 
                      style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[900], fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )),
            
            if (_visibleColumns['rut'] == true)
              _buildDataCell('rut', Text(
                customer.rut.isEmpty ? '-' : ChileanUtils.formatRut(customer.rut),
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              )),
              
            if (_visibleColumns['email'] == true)
              _buildDataCell('email', Text(
                customer.email ?? '-',
                style: TextStyle(color: customer.email != null ? Colors.grey[800] : Colors.grey[400], fontSize: 13),
                overflow: TextOverflow.ellipsis,
              )),
              
            if (_visibleColumns['phone'] == true)
              _buildDataCell('phone', Text(
                customer.phone ?? '-',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              )),
              
            if (_visibleColumns['region'] == true)
              _buildDataCell('region', Text(
                customer.region ?? '-',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              )),
              
            if (_visibleColumns['bikes'] == true)
              _buildDataCell('bikes', _CustomerBikesCell(
                bikes: _bikesByCustomer[customer.id] ?? [],
              )),
              
            if (_visibleColumns['status'] == true)
              _buildDataCell('status', Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: customer.isActive ? Colors.green[50] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    customer.isActive ? 'ACTIVO' : 'INACTIVO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: customer.isActive ? Colors.green[700] : Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              )),
              
            // Action column
            Container(
              width: 44,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 20, color: Colors.grey[600]),
                padding: EdgeInsets.zero,
                splashRadius: 20,
                tooltip: 'Opciones',
                onSelected: (value) async {
                  if (value == 'edit') {
                    context.push('/clientes/${customer.id}/editar').then((_) => _loadCustomers());
                  } else if (value == 'delete') {
                    _confirmDelete(customer);
                  } else if (value == 'view') {
                    context.push('/clientes/${customer.id}').then((_) => _loadCustomers());
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(String columnKey, Widget child) {
    final width = _columnWidths[columnKey] ?? 100.0;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: child,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: isMobile
              ? Column(
                  children: [
                    Text(
                      'Página $_currentPage de $_totalPages (${_filteredCustomers.length} clientes)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _buildPaginationButtons(theme),
                    ),
                  ],
                )
              : Row(
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
                      children: _buildPaginationButtons(theme),
                    ),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _buildPaginationButtons(ThemeData theme) {
    return [
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
    ];
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

class _CustomerBikesCell extends StatefulWidget {
  final List<Bike> bikes;

  const _CustomerBikesCell({required this.bikes});

  @override
  State<_CustomerBikesCell> createState() => _CustomerBikesCellState();
}

class _CustomerBikesCellState extends State<_CustomerBikesCell> {
  int _currentIndex = 0;

  void _nextBike() {
    setState(() {
      if (_currentIndex < widget.bikes.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
    });
  }

  void _prevBike() {
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = widget.bikes.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bikes.isEmpty) {
      return const Text('-', style: TextStyle(fontSize: 13, color: Colors.grey));
    }

    final currentBike = widget.bikes[_currentIndex];
    final displayString = currentBike.displayName;

    if (widget.bikes.length == 1) {
      return Text(
        displayString.isEmpty ? 'Bicicleta' : displayString,
        style: TextStyle(fontSize: 13, color: Colors.blueGrey[800]),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            displayString.isEmpty ? 'Bicicleta ${_currentIndex + 1}' : displayString,
            style: TextStyle(fontSize: 13, color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _prevBike,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.chevron_left, size: 16, color: Colors.grey),
              ),
            ),
            Text(
              '${_currentIndex + 1}/${widget.bikes.length}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            InkWell(
              onTap: _nextBike,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
