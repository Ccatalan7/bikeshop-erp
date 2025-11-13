import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/smart_purchase_list_service.dart';
import '../services/purchase_service.dart';
import '../models/smart_purchase_list_item.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/models/supplier.dart';
import 'purchase_invoice_form_page.dart';

class SmartPurchaseListPage extends StatefulWidget {
  const SmartPurchaseListPage({super.key});

  @override
  State<SmartPurchaseListPage> createState() => _SmartPurchaseListPageState();
}

class _SmartPurchaseListPageState extends State<SmartPurchaseListPage> {
  String _statusFilter = 'pending';
  String _supplierFilter = 'all';
  String _priorityFilter = 'all';
  String _searchQuery = '';
  final Set<String> _selectedItems = {};
  bool _selectAll = false;
  List<Supplier> _suppliers = [];
  
  // Pagination
  static const int _itemsPerPage = 100;
  int _currentPage = 1;
  
  // Cache for invoice data to avoid multiple queries
  final Map<String, Map<String, dynamic>> _invoiceCache = {};

  @override
  void initState() {
    super.initState();
    // Use post-frame callback to avoid blocking initial render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeService();
        _loadSuppliers();
        _preloadInvoiceData();
      }
    });
  }
  
  /// Preload all invoice data in one query
  Future<void> _preloadInvoiceData() async {
    final preloadStart = DateTime.now();
    debugPrint('⏱️ [INVOICE CACHE] Starting preload...');
    
    try {
      final response = await Supabase.instance.client
          .from('purchase_invoices')
          .select('id, invoice_number, created_at');
      
      for (final invoice in response) {
        _invoiceCache[invoice['id'] as String] = invoice;
      }
      
      final preloadTime = DateTime.now().difference(preloadStart).inMilliseconds;
      debugPrint('✅ [INVOICE CACHE] Preloaded ${_invoiceCache.length} invoices in ${preloadTime}ms');
      
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ [INVOICE CACHE] Error: $e');
    }
  }

  /// Initialize service once (sets up real-time listeners)
  Future<void> _initializeService() async {
    final pageStartTime = DateTime.now();
    debugPrint('⏱️ [PAGE] Smart Purchase List page mounted');
    
    final service = context.read<SmartPurchaseListService>();
    
    // If already initialized, data is instantly available
    if (service.isInitialized) {
      final cachedTime = DateTime.now().difference(pageStartTime).inMilliseconds;
      debugPrint('✅ [PAGE] Using cached data - ready instantly in ${cachedTime}ms');
      return;
    }
    
    // Initialize service asynchronously
    debugPrint('⏱️ [PAGE] Calling service.initialize()...');
    await service.initialize();
    final totalPageTime = DateTime.now().difference(pageStartTime).inMilliseconds;
    debugPrint('✅ [PAGE] TOTAL PAGE LOAD TIME: ${totalPageTime}ms');
  }

  String? _getInvoiceNumber(String? invoiceId) {
    if (invoiceId == null) return null;
    return _invoiceCache[invoiceId]?['invoice_number'] as String?;
  }

  DateTime? _getInvoiceCreatedDate(String? invoiceId) {
    if (invoiceId == null) return null;
    
    final createdAtStr = _invoiceCache[invoiceId]?['created_at'] as String?;
    if (createdAtStr == null) return null;
    
    try {
      return DateTime.parse(createdAtStr);
    } catch (e) {
      return null;
    }
  }

  void _navigateToInvoice(String invoiceId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseInvoiceFormPage(
          invoiceId: invoiceId,
          readOnly: true, // View-only mode from Smart Purchase List
        ),
      ),
    );
    
    // When returning, reload with 'received' filter
    if (mounted && result != null) {
      setState(() {
        _statusFilter = 'received';
      });
      context.read<SmartPurchaseListService>().loadItems(
        statusFilter: 'received',
        supplierFilter: _supplierFilter,
        searchQuery: _searchQuery,
      );
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers(forceRefresh: true);
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
        });
      }
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildStart = DateTime.now();
    debugPrint('⏱️ [PAGE BUILD] Starting build...');
    
    final widget = MainLayout(
      title: 'Lista Inteligente de Compras',
      child: Column(
        children: [
          // Top actions bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recargar'),
                  onPressed: () async {
                    try {
                      await context.read<SmartPurchaseListService>().refresh();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Lista actualizada'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.scanner),
                  label: const Text('Escanear Stock Bajo'),
                  onPressed: _scanLowStockProducts,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Limpiar Todo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _cleanupAllData,
                ),
                const SizedBox(width: 8),
                FloatingActionButton.extended(
                  onPressed: _showAddItemDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Producto'),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: Consumer<SmartPurchaseListService>(
              builder: (context, service, _) {
                if (service.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (service.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${service.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => service.refresh(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }

                final filteredItems = _getFilteredItems(service);

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Dashboard Summary
                        _buildDashboard(service),
                        const SizedBox(height: 16),
                        
                        // Filters and Search
                        _buildFilters(service),
                        const SizedBox(height: 16),
                        
                        // Bulk Actions
                        if (_selectedItems.isNotEmpty) _buildBulkActions(),
                        if (_selectedItems.isNotEmpty) const SizedBox(height: 16),
                        
                        // Items List
                        filteredItems.isEmpty
                            ? _buildEmptyState()
                            : _buildItemsList(service),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    
    final buildTime = DateTime.now().difference(buildStart).inMilliseconds;
    debugPrint('✅ [PAGE BUILD] Completed in ${buildTime}ms');
    
    return widget;
  }

  Widget _buildDashboard(SmartPurchaseListService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDashboardCard(
                    'Total Pendiente',
                    service.totalPendingItems.toString(),
                    Icons.shopping_cart,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDashboardCard(
                    'Urgentes',
                    service.urgentItemsCount.toString(),
                    Icons.priority_high,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDashboardCard(
                    'Sin Stock',
                    service.outOfStockCount.toString(),
                    Icons.warning,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDashboardCard(
                    'Proveedor Principal',
                    service.topSupplier ?? 'N/A',
                    Icons.business,
                    Colors.green,
                    isNumber: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool isNumber = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isNumber ? 24 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(SmartPurchaseListService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // First row: Search and Status
            Row(
              children: [
                // Search
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _currentPage = 1; // Reset to first page
                      });
                      service.loadItems(
                        statusFilter: _statusFilter,
                        supplierFilter: _supplierFilter,
                        searchQuery: value,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                
                // Status Filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'ordered', child: Text('Ordenado')),
                      DropdownMenuItem(value: 'received', child: Text('Recibido')),
                      DropdownMenuItem(value: 'ignored', child: Text('Ignorado')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _statusFilter = value;
                          _currentPage = 1; // Reset to first page
                        });
                        service.loadItems(
                          statusFilter: value,
                          supplierFilter: _supplierFilter,
                          searchQuery: _searchQuery,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Second row: Supplier and Priority
            Row(
              children: [
                // Supplier Filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _supplierFilter,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('Todos')),
                      const DropdownMenuItem(value: 'none', child: Text('Sin proveedor')),
                      ..._suppliers.map((supplier) => DropdownMenuItem(
                        value: supplier.id,
                        child: Text(supplier.name),
                      )),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _supplierFilter = value;
                          _currentPage = 1; // Reset to first page
                        });
                        service.loadItems(
                          statusFilter: _statusFilter,
                          supplierFilter: value,  // Pass the value as-is ('all', 'none', or supplier_id)
                          searchQuery: _searchQuery,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                
                // Priority Filter
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _priorityFilter,
                    decoration: const InputDecoration(
                      labelText: 'Prioridad',
                      prefixIcon: Icon(Icons.priority_high),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todas')),
                      DropdownMenuItem(value: 'critical', child: Text('Crítica (>80)')),
                      DropdownMenuItem(value: 'high', child: Text('Alta (60-80)')),
                      DropdownMenuItem(value: 'medium', child: Text('Media (40-60)')),
                      DropdownMenuItem(value: 'low', child: Text('Baja (<40)')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _priorityFilter = value;
                          _currentPage = 1; // Reset to first page
                        });
                        _applyClientSideFilters();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _applyClientSideFilters() {
    // Priority filter is applied client-side
    setState(() {});
  }

  Widget _buildBulkActions() {
    return Card(
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '${_selectedItems.length} seleccionados',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _generatePurchaseOrder,
              icon: const Icon(Icons.shopping_bag),
              label: const Text('Generar Orden de Compra'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _generateExpense,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Generar Gasto'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedItems.clear();
                  _selectAll = false;
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );
  }

  List<SmartPurchaseListItem> _getFilteredItems(SmartPurchaseListService service) {
    // Get items with current filters applied
    var items = service.getFilteredItems(
      statusFilter: _statusFilter,
      supplierFilter: _supplierFilter,
      searchQuery: _searchQuery,
    );
    
    // Apply priority filter
    if (_priorityFilter != 'all') {
      items = items.where((item) {
        final priority = item.priority;
        switch (_priorityFilter) {
          case 'critical':
            return priority > 80;
          case 'high':
            return priority >= 60 && priority <= 80;
          case 'medium':
            return priority >= 40 && priority < 60;
          case 'low':
            return priority < 40;
          default:
            return true;
        }
      }).toList();
    }
    
    return items;
  }
  
  /// Get paginated items for current page
  List<SmartPurchaseListItem> _getPaginatedItems(List<SmartPurchaseListItem> allItems) {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, allItems.length);
    
    if (startIndex >= allItems.length) {
      return [];
    }
    
    return allItems.sublist(startIndex, endIndex);
  }
  
  /// Get total number of pages
  int _getTotalPages(int totalItems) {
    return (totalItems / _itemsPerPage).ceil();
  }
  
  /// Go to specific page
  void _goToPage(int page) {
    setState(() {
      _currentPage = page;
      _selectedItems.clear(); // Clear selection when changing pages
      _selectAll = false;
    });
  }

  Widget _buildItemsList(SmartPurchaseListService service) {
    final buildStart = DateTime.now();
    final filteredItems = _getFilteredItems(service);
    final totalItems = filteredItems.length;
    final totalPages = _getTotalPages(totalItems);
    final paginatedItems = _getPaginatedItems(filteredItems);
    
    debugPrint('⏱️ [LIST BUILD] Building page $_currentPage/$totalPages with ${paginatedItems.length} items (${totalItems} total)...');

    final widget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pagination info and controls at top
        if (totalItems > _itemsPerPage) ...[
          _buildPaginationControls(totalItems, totalPages),
          const SizedBox(height: 8),
        ],
        
        _buildTableHeader(),
        ...paginatedItems.map((item) => _buildItemRow(item, service)),
        
        // Pagination controls at bottom
        if (totalItems > _itemsPerPage) ...[
          const SizedBox(height: 16),
          _buildPaginationControls(totalItems, totalPages),
        ],
      ],
    );
    
    final buildTime = DateTime.now().difference(buildStart).inMilliseconds;
    debugPrint('✅ [LIST BUILD] Completed in ${buildTime}ms');
    
    return widget;
  }

  Widget _buildTableHeader() {
    final isReceivedView = _statusFilter == 'received';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (!isReceivedView) ...[
            SizedBox(
              width: 40,
              child: Checkbox(
                value: _selectAll,
                onChanged: (value) {
                  setState(() {
                    _selectAll = value ?? false;
                    if (_selectAll) {
                      _selectedItems.addAll(
                        context.read<SmartPurchaseListService>().items.map((i) => i.id),
                      );
                    } else {
                      _selectedItems.clear();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 50, child: Text('Prioridad', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
          ],
          const Expanded(flex: 2, child: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          const Expanded(child: Text('Proveedor', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          if (isReceivedView) ...[
            const SizedBox(width: 120, child: Text('Stock Inicial', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 120, child: Text('Stock Final', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 100, child: Text('Diferencia', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 130, child: Text('N° Factura', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 120, child: Text('Creado el', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 120, child: Text('Recibido el', style: TextStyle(fontWeight: FontWeight.bold))),
          ] else ...[
            const SizedBox(width: 80, child: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 80, child: Text('Cant. Sug.', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            const SizedBox(width: 100, child: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          const SizedBox(width: 16),
          const SizedBox(width: 120, child: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildItemRow(SmartPurchaseListItem item, SmartPurchaseListService service) {
    final isSelected = _selectedItems.contains(item.id);
    final isReceivedView = _statusFilter == 'received';
    
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : null,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Checkbox - only for non-received view
          if (!isReceivedView) ...[
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: item.isPending
                    ? (value) {
                        setState(() {
                          if (value == true) {
                            _selectedItems.add(item.id);
                          } else {
                            _selectedItems.remove(item.id);
                            _selectAll = false;
                          }
                        });
                      }
                    : null,
              ),
            ),
            
            // Priority Indicator - only for non-received view
            SizedBox(
              width: 50,
              child: _buildPriorityBadge(item.priority, item.priorityLevel),
            ),
            const SizedBox(width: 16),
          ],
          
          // Product
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (item.productSku != null)
                  Text(
                    'SKU: ${item.productSku}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                if (!isReceivedView && item.isOutOfStock)
                  const Text(
                    'SIN STOCK',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          
          // Supplier
          Expanded(
            flex: 1,
            child: Text(item.supplierName ?? 'Sin proveedor'),
          ),
          const SizedBox(width: 16),
          
          if (isReceivedView) ...[
            // Stock Inicial (when order was generated)
            SizedBox(
              width: 120,
              child: Text(
                item.stockAtOrder?.toString() ?? 'N/A',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: item.stockAtOrder == null ? Colors.grey : null,
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Stock Final (stock at receipt time, not current stock)
            SizedBox(
              width: 120,
              child: Text(
                item.stockAtReceipt != null 
                    ? item.stockAtReceipt.toString() 
                    : 'N/A',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: item.stockAtReceipt != null ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Diferencia (Stock Final - Stock Inicial)
            SizedBox(
              width: 100,
              child: Builder(
                builder: (context) {
                  if (item.stockAtOrder == null || item.stockAtReceipt == null) {
                    return const Text(
                      'N/A',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  
                  final stockInitial = item.stockAtOrder!;
                  final stockFinal = item.stockAtReceipt!;
                  final difference = stockFinal - stockInitial;
                  
                  return Text(
                    difference >= 0 ? '+$difference' : difference.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: difference > 0 ? Colors.green : (difference < 0 ? Colors.red : Colors.grey),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            
            // N° Factura (invoice number) - Synchronous cache lookup
            SizedBox(
              width: 130,
              child: Builder(
                builder: (context) {
                  final invoiceNumber = _getInvoiceNumber(item.linkedPurchaseInvoiceId);
                  
                  if (invoiceNumber == null) {
                    return Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    );
                  }
                  
                  return InkWell(
                    onTap: () => _navigateToInvoice(item.linkedPurchaseInvoiceId!),
                    child: Text(
                      invoiceNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            
            // Creado el (invoice creation date) - Synchronous cache lookup
            SizedBox(
              width: 120,
              child: Builder(
                builder: (context) {
                  final createdDate = _getInvoiceCreatedDate(item.linkedPurchaseInvoiceId);
                  
                  if (createdDate == null) {
                    return Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    );
                  }
                  
                  return Text(
                    '${createdDate.day}/${createdDate.month}/${createdDate.year}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            
            // Recibido el (received date)
            SizedBox(
              width: 120,
              child: Text(
                item.receivedDate != null
                    ? '${item.receivedDate!.day}/${item.receivedDate!.month}/${item.receivedDate!.year}'
                    : '-',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ] else ...[
            // Stock - for non-received view
            SizedBox(
              width: 80,
              child: Text(
                '${item.currentStock} / ${item.minStockLevel}',
                style: TextStyle(
                  color: item.currentStock <= item.minStockLevel ? Colors.red : null,
                  fontWeight: item.currentStock <= item.minStockLevel ? FontWeight.bold : null,
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Suggested Quantity
            SizedBox(
              width: 80,
              child: Text(
                item.suggestedQuantity.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            
            // Status
            SizedBox(
              width: 100,
              child: _buildStatusChip(item.status),
            ),
          ],
          const SizedBox(width: 16),
          
          // Actions
          SizedBox(
            width: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.isPending) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _showEditItemDialog(item, service),
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: const Icon(Icons.visibility_off, size: 18),
                    onPressed: () => service.markAsIgnored(item.id),
                    tooltip: 'Ignorar',
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: () => _confirmDelete(item, service),
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(double priority, String level) {
    Color color;
    String label;
    
    switch (level) {
      case 'critical':
        color = Colors.red;
        label = priority.toStringAsFixed(0);
        break;
      case 'high':
        color = Colors.orange;
        label = priority.toStringAsFixed(0);
        break;
      case 'medium':
        color = Colors.yellow[700]!;
        label = priority.toStringAsFixed(0);
        break;
      default:
        color = Colors.green;
        label = priority.toStringAsFixed(0);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    
    switch (status) {
      case 'pending':
        color = Colors.blue;
        label = 'Pendiente';
        break;
      case 'ordered':
        color = Colors.orange;
        label = 'Ordenado';
        break;
      case 'received':
        color = Colors.green;
        label = 'Recibido';
        break;
      case 'ignored':
        color = Colors.grey;
        label = 'Ignorado';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color, fontSize: 12),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '¡Todo en orden!',
            style: TextStyle(fontSize: 20, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'No hay productos que necesiten ser reabastecidos',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _scanLowStockProducts,
            icon: const Icon(Icons.scanner),
            label: const Text('Escanear Productos'),
          ),
        ],
      ),
    );
  }

  // Dialog actions
  void _showAddItemDialog() {
    final productController = TextEditingController();
    final skuController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final notesController = TextEditingController();
    String? selectedProductId;
    String? selectedSupplierId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Agregar Producto a Lista de Compras'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Buscar producto existente o agregar item ad-hoc',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  // Product search/input
                  TextField(
                    controller: productController,
                    decoration: const InputDecoration(
                      labelText: 'Producto *',
                      hintText: 'Buscar o escribir nombre del producto',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) async {
                      if (value.length > 2) {
                        // Search for existing products
                        try {
                          final products = await Supabase.instance.client
                              .from('products')
                              .select('id, name, sku, supplier_id')
                              .ilike('name', '%$value%')
                              .limit(5);
                          
                          if (products.isNotEmpty && context.mounted) {
                            // Show autocomplete suggestions (simplified)
                            debugPrint('Found ${products.length} products');
                          }
                        } catch (e) {
                          debugPrint('Error searching products: $e');
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // SKU
                  TextField(
                    controller: skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      hintText: 'Código del producto (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Quantity
                  TextField(
                    controller: qtyController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad Sugerida *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  
                  // Supplier dropdown
                  FutureBuilder<List<Supplier>>(
                    future: context.read<PurchaseService>().getSuppliers(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      
                      final suppliers = snapshot.data!;
                      return DropdownButtonFormField<String>(
                        value: selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'Proveedor',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Sin proveedor'),
                          ),
                          ...suppliers.map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          )),
                        ],
                        onChanged: (value) {
                          setState(() => selectedSupplierId = value);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Notes
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notas',
                      hintText: 'Información adicional (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (productController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('El nombre del producto es requerido')),
                  );
                  return;
                }
                
                final qty = int.tryParse(qtyController.text) ?? 1;
                if (qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('La cantidad debe ser mayor a 0')),
                  );
                  return;
                }
                
                try {
                  final service = context.read<SmartPurchaseListService>();
                  
                  // Get supplier name if selected
                  String? supplierName;
                  if (selectedSupplierId != null) {
                    final suppliers = await context.read<PurchaseService>().getSuppliers();
                    supplierName = suppliers.firstWhere((s) => s.id == selectedSupplierId).name;
                  }
                  
                  await service.addItem(
                    productId: selectedProductId,
                    productName: productController.text.trim(),
                    productSku: skuController.text.trim().isEmpty ? null : skuController.text.trim(),
                    quantity: qty,
                    supplierId: selectedSupplierId,
                    supplierName: supplierName,
                    notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Producto agregado a la lista de compras')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditItemDialog(SmartPurchaseListItem item, SmartPurchaseListService service) {
    // TODO: Implement edit dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Función de editar en desarrollo')),
    );
  }

  void _confirmDelete(SmartPurchaseListItem item, SmartPurchaseListService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Eliminar "${item.productName}" de la lista de compras?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              service.deleteItem(item.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanLowStockProducts() async {
    final service = context.read<SmartPurchaseListService>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Escaneando productos...'),
          ],
        ),
      ),
    );

    final result = await service.scanAndAddLowStockProducts();
    
    if (mounted) {
      Navigator.pop(context); // Close loading dialog
      
      // Reload the list to show changes
      await service.loadItems(
        statusFilter: _statusFilter,
        supplierFilter: _supplierFilter,
        searchQuery: _searchQuery,
      );
      
      if (mounted) {
        String message;
        Color color;
        
        if (result.total == 0) {
          message = 'No hay cambios - lista ya está actualizada';
          color = Colors.blue;
        } else {
          final parts = <String>[];
          if (result.added > 0) {
            parts.add('${result.added} agregado${result.added > 1 ? "s" : ""}');
          }
          if (result.removed > 0) {
            parts.add('${result.removed} eliminado${result.removed > 1 ? "s" : ""}');
          }
          message = 'Escaneo completo: ${parts.join(", ")}';
          color = Colors.green;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: color,
          ),
        );
      }
    }
  }

  Future<void> _cleanupAllData() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Limpiar Tabla Completa'),
        content: const Text(
          'Esto eliminará TODOS los items de la lista de compras inteligente '
          'y restablecerá los filtros a sus valores por defecto.\n\n'
          '¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, Limpiar Todo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = context.read<SmartPurchaseListService>();
    
    try {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Limpiando datos...'),
              ],
            ),
          ),
        );
      }

      // Delete all items from smart_purchase_list table
      await service.deleteAllItems();

      // Reset filters to default
      if (mounted) {
        setState(() {
          _statusFilter = 'pending';
          _supplierFilter = 'all';
          _priorityFilter = 'all';
          _searchQuery = '';
        });
      }

      // Reload with default filters
      await service.loadItems(
        statusFilter: _statusFilter,
        supplierFilter: _supplierFilter,
        searchQuery: _searchQuery,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Tabla limpiada y filtros restablecidos'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al limpiar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generatePurchaseOrder() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final service = context.read<SmartPurchaseListService>();
      final selectedItemsList = service.items
          .where((item) => _selectedItems.contains(item.id))
          .toList();

      // Get unique suppliers from selected items (for suggestion only)
      final supplierIds = selectedItemsList
          .where((item) => item.supplierId != null)
          .map((item) => item.supplierId!)
          .toSet()
          .toList();

      // Show supplier selection dialog (including option for any supplier)
      final selectedSupplier = await showDialog<String?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Seleccionar Proveedor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('¿A qué proveedor deseas comprar estos productos?'),
                const SizedBox(height: 16),
                // Show suppliers from selected items
                ...supplierIds.map((supplierId) {
                  final itemsForSupplier = selectedItemsList
                      .where((item) => item.supplierId == supplierId)
                      .toList();
                  final supplierName = itemsForSupplier.first.supplierName ?? 'Sin nombre';
                  return ListTile(
                    title: Text(supplierName),
                    subtitle: Text('${itemsForSupplier.length} producto(s) asignado(s)'),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () => Navigator.pop(context, supplierId),
                  );
                }),
                const Divider(),
                // Option to select a different supplier
                ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('Otro proveedor'),
                  subtitle: const Text('Seleccionar un proveedor diferente'),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => Navigator.pop(context, 'SELECT_OTHER'),
                ),
                // Option for no supplier
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Sin proveedor'),
                  subtitle: const Text('Crear sin proveedor asignado'),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () => Navigator.pop(context, null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (selectedSupplier == 'CANCELLED' || !mounted) return;
      
      // If user wants to select another supplier, show supplier list
      String? finalSupplierId = selectedSupplier;
      if (selectedSupplier == 'SELECT_OTHER') {
        finalSupplierId = await _showSupplierPicker();
        if (finalSupplierId == null && !mounted) return;
      }
      
      // Navigate with ALL selected products, regardless of their assigned supplier
      await _navigateToPurchaseForm(selectedItemsList, finalSupplierId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _showSupplierPicker() async {
    // TODO: Load suppliers from database and show selection dialog
    // For now, return null (no supplier selected)
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Proveedor'),
        content: const Text('Función de selección de proveedores en desarrollo'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToPurchaseForm(
    List<SmartPurchaseListItem> items,
    String? supplierId,
  ) async {
    if (!mounted) return;
    
    // Prepare line items data
    final lineItems = items.map((item) => {
      'product_id': item.productId,
      'product_name': item.productName,
      'product_sku': item.productSku,
      'suggested_quantity': item.suggestedQuantity,
    }).toList();
    
    // Navigate to purchase invoice form with pre-filled data
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseInvoiceFormPage(
          initialSupplierId: supplierId,
          initialLineItems: lineItems,
        ),
      ),
    );
    
    // Reload the list when coming back
    if (mounted) {
      context.read<SmartPurchaseListService>().loadItems();
    }
  }

  void _generateExpense() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final service = context.read<SmartPurchaseListService>();
      final selectedItemsList = service.items
          .where((item) => _selectedItems.contains(item.id))
          .toList();

      final itemNames = selectedItemsList.map((e) => e.productName).join(', ');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generando registro de gasto para:\n$itemNames',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Navigate to expense form
      // TODO: Add support for passing pre-filled items to ExpenseFormPage
      context.go('/accounting/expenses/new');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// Build pagination controls with page numbers
  Widget _buildPaginationControls(int totalItems, int totalPages) {
    final startItem = (_currentPage - 1) * _itemsPerPage + 1;
    final endItem = (_currentPage * _itemsPerPage).clamp(0, totalItems);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items count info
          Text(
            'Mostrando $startItem-$endItem de $totalItems productos',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          
          // Pagination controls
          Row(
            children: [
              // First page button
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 1 ? () => _goToPage(1) : null,
                tooltip: 'Primera página',
              ),
              
              // Previous page button
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                tooltip: 'Página anterior',
              ),
              
              // Page numbers
              ..._buildPageNumbers(totalPages),
              
              // Next page button
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages ? () => _goToPage(_currentPage + 1) : null,
                tooltip: 'Página siguiente',
              ),
              
              // Last page button
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages ? () => _goToPage(totalPages) : null,
                tooltip: 'Última página',
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Build page number buttons (show current +/- 2 pages)
  List<Widget> _buildPageNumbers(int totalPages) {
    final List<Widget> pageButtons = [];
    
    // Show current page +/- 2 pages
    final startPage = (_currentPage - 2).clamp(1, totalPages);
    final endPage = (_currentPage + 2).clamp(1, totalPages);
    
    // Add ellipsis before if needed
    if (startPage > 1) {
      pageButtons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }
    
    // Add page numbers
    for (int i = startPage; i <= endPage; i++) {
      final isCurrentPage = i == _currentPage;
      pageButtons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: isCurrentPage
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$i',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: () => _goToPage(i),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('$i'),
                ),
        ),
      );
    }
    
    // Add ellipsis after if needed
    if (endPage < totalPages) {
      pageButtons.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }
    
    return pageButtons;
  }
}
