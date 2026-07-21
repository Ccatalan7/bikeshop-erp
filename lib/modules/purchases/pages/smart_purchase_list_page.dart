import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/smart_purchase_list_service.dart';
import '../services/purchase_service.dart';
import '../models/smart_purchase_list_item.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/inventory_service.dart';
import 'purchase_invoice_form_page.dart';

class SmartPurchaseListPage extends StatefulWidget {
  const SmartPurchaseListPage({super.key});

  @override
  State<SmartPurchaseListPage> createState() => _SmartPurchaseListPageState();
}

class _SmartPurchaseListPageState extends State<SmartPurchaseListPage> {
  String _statusFilter = 'pending';
  String _supplierFilter = 'all';
  String _categoryFilter = 'all';
  String _priorityFilter = 'all';
  String _searchQuery = '';
  final Set<String> _selectedItems = {};
  bool _selectAll = false;
  List<Supplier> _suppliers = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isArchiving = false; // Loading state for bulk operations

  // Alternatives cache: itemId -> list of alternative products with stock
  final Map<String, List<Map<String, dynamic>>> _alternativesCache = {};

  // Pagination
  static const int _itemsPerPage = 100;
  int _currentPage = 1;

  // Cache for invoice data to avoid multiple queries
  final Map<String, Map<String, dynamic>> _invoiceCache = {};

  @override
  void initState() {
    super.initState();
    // Clear alternatives cache to recalculate with new matching logic
    _alternativesCache.clear();
    // Use post-frame callback to avoid blocking initial render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeService();
        _loadSuppliers();
        _loadCategories();
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

      final preloadTime =
          DateTime.now().difference(preloadStart).inMilliseconds;
      debugPrint(
          '✅ [INVOICE CACHE] Preloaded ${_invoiceCache.length} invoices in ${preloadTime}ms');

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
      final cachedTime =
          DateTime.now().difference(pageStartTime).inMilliseconds;
      debugPrint(
          '✅ [PAGE] Using cached data - ready instantly in ${cachedTime}ms');
      return;
    }

    // Initialize service asynchronously
    debugPrint('⏱️ [PAGE] Calling service.initialize()...');
    await service.initialize();
    final totalPageTime =
        DateTime.now().difference(pageStartTime).inMilliseconds;
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

  Future<void> _loadCategories() async {
    try {
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) return;

      final response = await Supabase.instance.client
          .from('product_categories')
          .select('id, name, full_path')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .order('full_path');

      if (mounted) {
        setState(() {
          _categories =
              (response as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  String _getCategoryDisplayName() {
    if (_categoryFilter == 'all') return 'Todas';
    if (_categoryFilter == 'none') return 'Sin categoría';

    final category = _categories.firstWhere(
      (cat) => cat['id'] == _categoryFilter,
      orElse: () => {},
    );

    return category['full_path'] as String? ??
        category['name'] as String? ??
        'Seleccionar...';
  }

  String _extractCategoryName(String? fullPath) {
    if (fullPath == null || fullPath.isEmpty) return 'Sin categoría';

    // Extract last part after final " / "
    final parts = fullPath.split(' / ');
    return parts.last.trim();
  }

  /// Find alternative products with similar specs/keywords
  Future<List<Map<String, dynamic>>> _findAlternatives(
      SmartPurchaseListItem item) async {
    // Check cache first
    if (_alternativesCache.containsKey(item.id)) {
      return _alternativesCache[item.id]!;
    }

    try {
      final inventoryService = context.read<InventoryService>();
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) return [];

      // Extract keywords from product name (remove common words)
      final keywords = _extractKeywords(item.productName);
      if (keywords.length < 2) return []; // Need at least 2 keywords to match

      // Build search query - match products with same category and similar keywords
      var query = Supabase.instance.client
          .from('products')
          .select('id')
          .eq('tenant_id', tenantId)
          .eq('is_active', true);

      // Filter by category if available
      if (item.categoryId != null && item.categoryId!.isNotEmpty) {
        query = query.eq('category_id', item.categoryId!);
      }

      // Exclude the current product
      if (item.productId != null && item.productId!.isNotEmpty) {
        query = query.neq('id', item.productId!);
      }

      final response = await query.limit(50);
      final products = await inventoryService.getProductsByIds(
        (response as List<dynamic>)
            .map((row) => row['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
        forceRefresh: true,
      );

      // Extract specs from original product (keywords already extracted above)
      final originalSpecs = _extractSpecs(item.productName);

      // Debug: Log extracted specs
      debugPrint('🔍 Original: ${item.productName}');
      debugPrint(
          '   Sizes: ${originalSpecs['sizes']}, Widths: ${originalSpecs['widths']}, Keywords: $keywords');

      // Score and filter products based on SPEC matching (critical) + keyword overlap
      final alternatives = <Map<String, dynamic>>[];
      for (final product in products) {
        if (product.isSetComponent || product.availableStockQuantity <= 0) {
          continue;
        }
        final productName = product.name;
        final productSpecs = _extractSpecs(productName);
        final productNameLower = productName.toLowerCase();

        int specMatchScore = 0;

        // CRITICAL: Match wheel sizes (must match!)
        if (originalSpecs['sizes']!.isNotEmpty) {
          for (final size in originalSpecs['sizes']!) {
            if (productSpecs['sizes']!.contains(size)) {
              specMatchScore += 10; // Size match is CRITICAL
              break;
            }
          }
        }

        // Match widths (important for tubes/tires)
        if (originalSpecs['widths']!.isNotEmpty) {
          for (final width in originalSpecs['widths']!) {
            if (productSpecs['widths']!.contains(width)) {
              specMatchScore += 3;
              break;
            }
          }
        }

        // Match diameters (important for axles, hubs)
        if (originalSpecs['diameters']!.isNotEmpty) {
          for (final diameter in originalSpecs['diameters']!) {
            if (productSpecs['diameters']!.contains(diameter)) {
              specMatchScore += 5;
              break;
            }
          }
        }

        // Match standards (QR, presta, etc.)
        if (originalSpecs['standards']!.isNotEmpty) {
          for (final standard in originalSpecs['standards']!) {
            if (productSpecs['standards']!.contains(standard)) {
              specMatchScore += 2;
              break;
            }
          }
        }

        // Secondary: keyword matching
        int keywordMatches = 0;
        for (final keyword in keywords) {
          if (productNameLower.contains(keyword)) {
            keywordMatches++;
          }
        }

        // STRICT MATCHING: If original has wheel size, alternative MUST have matching size
        final originalHasSize = originalSpecs['sizes']!.isNotEmpty;
        final hasSpecMatch = specMatchScore >= 10; // Size match
        final hasStrongKeywordMatch =
            keywordMatches >= (keywords.length * 0.6).ceil();

        // If original has detectable wheel size, alternative MUST match it (no keyword fallback)
        final isValidMatch = originalHasSize
            ? hasSpecMatch
            : (hasSpecMatch || hasStrongKeywordMatch);

        if (isValidMatch) {
          alternatives.add({
            'id': product.id,
            'name': product.name,
            'sku': product.sku,
            'stock': product.availableStockQuantity,
            'cost': product.cost,
            'price': product.price,
            'match_score': specMatchScore + keywordMatches,
            'spec_score': specMatchScore,
          });
        }
      }

      // Sort by spec score first (most important), then total score
      alternatives.sort((a, b) {
        final specCompare =
            (b['spec_score'] as int).compareTo(a['spec_score'] as int);
        if (specCompare != 0) return specCompare;
        return (b['match_score'] as int).compareTo(a['match_score'] as int);
      });

      // Cache the results
      _alternativesCache[item.id] = alternatives;

      return alternatives;
    } catch (e) {
      debugPrint('Error finding alternatives: $e');
      return [];
    }
  }

  /// Extract meaningful keywords from product name
  List<String> _extractKeywords(String productName) {
    final name = productName.toLowerCase();

    // Common words to ignore (Spanish and English) + TOO GENERIC product types
    final stopWords = {
      'de', 'del', 'la', 'el', 'los', 'las', 'un', 'una', 'para', 'con', 'sin',
      'the', 'a', 'an', 'and', 'or', 'of', 'for', 'with', 'without', 'in', 'on',
      'camara', 'eje', 'valvula', 'tube', 'axle', 'valve',
      'bicicleta', // Too generic
    };

    // Split by spaces and special characters
    final words = name.split(RegExp(r'[\s\-\/,]+'));

    // Filter out stop words and very short words
    final keywords = words
        .where((word) => word.length >= 2 && !stopWords.contains(word))
        .toList();

    return keywords;
  }

  /// Extract critical specs (sizes, measurements, standards)
  Map<String, List<String>> _extractSpecs(String productName) {
    final specs = <String, List<String>>{
      'sizes': [], // 26, 27.5, 29, 700c, etc.
      'widths': [], // 1.5, 1.95, 2.0, etc.
      'diameters': [], // 9mm, 12mm, 15mm, etc.
      'standards': [], // QR, thru-axle, presta, schrader, etc.
    };

    final nameLower = productName.toLowerCase();

    // Extract wheel sizes - MUST be preceded by space/start and followed by space/X/x/-
    // This prevents matching "20" in "2.20" or "16" in "M16"
    final sizePattern =
        RegExp(r'(?:^|\s)(16|20|24|26|27\.?5?|28|29|700c?)(?:\s|x|X|-|$)');
    for (final match in sizePattern.allMatches(nameLower)) {
      final size = match.group(1)!;
      if (!specs['sizes']!.contains(size)) {
        specs['sizes']!.add(size);
      }
    }

    // Extract widths (1.5, 1.95, 2.0, 2.125, etc.) - the SECOND number in "26 X 1.5" pattern
    final widthPattern = RegExp(r'\b(\d+\.?\d*)\s*(?:x|X|a)\s*(\d+\.?\d*)');
    final widthMatches = widthPattern.allMatches(nameLower);
    for (final match in widthMatches) {
      if (match.group(2) != null) {
        final width = match.group(2)!;
        if (!specs['widths']!.contains(width)) {
          specs['widths']!.add(width);
        }
      }
    }

    // Extract diameters (9mm, 12mm, 15mm, 33mm, 48mm, etc.)
    final diameterPattern = RegExp(r'\b(\d+)\s*mm\b');
    for (final match in diameterPattern.allMatches(nameLower)) {
      final diameter = '${match.group(1)!}mm';
      if (!specs['diameters']!.contains(diameter)) {
        specs['diameters']!.add(diameter);
      }
    }

    // Extract valve types and standards
    if (nameLower.contains('presta')) specs['standards']!.add('presta');
    if (nameLower.contains('schrader')) specs['standards']!.add('schrader');
    if (nameLower.contains('auto')) specs['standards']!.add('auto');
    if (nameLower.contains('qr') || nameLower.contains('quick')) {
      specs['standards']!.add('qr');
    }
    if (nameLower.contains('thru') || nameLower.contains('eje pasante')) {
      specs['standards']!.add('thru-axle');
    }

    return specs;
  }

  Future<void> _showCategoryPicker(BuildContext context) async {
    String searchQuery = '';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCategories = searchQuery.isEmpty
              ? _categories
              : _categories.where((cat) {
                  final fullPath =
                      (cat['full_path'] as String? ?? '').toLowerCase();
                  final name = (cat['name'] as String? ?? '').toLowerCase();
                  final query = searchQuery.toLowerCase();
                  return fullPath.contains(query) || name.contains(query);
                }).toList();

          return AlertDialog(
            title: const Text('Seleccionar Categoría'),
            content: SizedBox(
              width: 500,
              height: 500,
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar categoría',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        searchQuery = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Categories list
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.all_inclusive),
                          title: const Text('Todas'),
                          selected: _categoryFilter == 'all',
                          onTap: () {
                            setState(() {
                              _categoryFilter = 'all';
                              _currentPage = 1;
                            });
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.category_outlined),
                          title: const Text('Sin categoría'),
                          selected: _categoryFilter == 'none',
                          onTap: () {
                            setState(() {
                              _categoryFilter = 'none';
                              _currentPage = 1;
                            });
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(),
                        ...filteredCategories.map((category) {
                          final categoryId = category['id'] as String;
                          final fullPath = category['full_path'] as String? ??
                              category['name'] as String;
                          final name = category['name'] as String;

                          return ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(name),
                            subtitle: Text(
                              fullPath,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                            ),
                            selected: _categoryFilter == categoryId,
                            onTap: () {
                              setState(() {
                                _categoryFilter = categoryId;
                                _currentPage = 1;
                              });
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
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
          );
        },
      ),
    );
  }

  Future<void> _showAlternativesDialog(
    BuildContext context,
    SmartPurchaseListItem item,
    List<Map<String, dynamic>> alternatives,
  ) async {
    final totalStock = alternatives.fold<int>(
      0,
      (sum, alt) => sum + (alt['stock'] as int),
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shopping_bag, color: Colors.green),
            SizedBox(width: 8),
            Text('Alternativas Disponibles'),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Original product info
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Producto sin stock:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Stock: ${item.currentStock} / ${item.minStockLevel}',
                        style: TextStyle(fontSize: 12, color: Colors.red[700]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Summary
              Text(
                'Se encontraron ${alternatives.length} alternativas con $totalStock unidades en total:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Alternatives list
              Expanded(
                child: ListView.builder(
                  itemCount: alternatives.length,
                  itemBuilder: (context, index) {
                    final alt = alternatives[index];
                    final stock = alt['stock'] as int;
                    final matchScore = alt['match_score'] as int;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              stock > 10 ? Colors.green : Colors.orange,
                          child: Text(
                            '$stock',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          alt['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (alt['sku'] != null)
                              Text('SKU: ${alt['sku']}',
                                  style: const TextStyle(fontSize: 11)),
                            Text(
                              'Stock disponible: $stock unidades',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    stock > 10 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (alt['price'] != null)
                              Text(
                                '\$${(alt['price'] as num).toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                matchScore.clamp(0, 5),
                                (i) => const Icon(Icons.star,
                                    size: 12, color: Colors.amber),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buildStart = DateTime.now();
    debugPrint('⏱️ [PAGE BUILD] Starting build...');

    final widget = Stack(
      children: [
        MainLayout(
          title: 'Lista Inteligente de Compras',
          child: Column(
            children: [
              // Top actions bar
              // Sleek SaaS Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestión de Compras',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Prioriza y organiza el reabastecimiento de tu inventario',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Action Buttons - Minimalist
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Recargar Datos',
                          child: IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () async {
                              try {
                                await context
                                    .read<SmartPurchaseListService>()
                                    .refresh();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ Lista actualizada')),
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
                        ),
                        Tooltip(
                          message: 'Escanear Stock Bajo',
                          child: IconButton(
                            icon: const Icon(Icons.scanner, size: 20),
                            onPressed: _scanLowStockProducts,
                          ),
                        ),
                        Tooltip(
                          message: 'Limpiar Todo',
                          child: IconButton(
                            icon: const Icon(Icons.delete_sweep,
                                size: 20, color: Colors.redAccent),
                            onPressed: _cleanupAllData,
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: _showAddItemDialog,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar'),
                          style: FilledButton.styleFrom(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Main content
              Expanded(
                child: Consumer<SmartPurchaseListService>(
                  builder: (context, service, _) {
                    if (service.isLoading) {
                      return const Center(child: BrandedLoading());
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

                    return CustomScrollView(
                      slivers: [
                        // Dashboard summary (scrolls)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                            child: _buildDashboard(service),
                          ),
                        ),

                        // Sticky Filter Bar (pins to top)
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _StickyHeaderDelegate(
                            height:
                                80.0, // Increased height to accommodate dropdowns safely
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SizedBox(
                                  width: constraints.maxWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: _buildFilters(service),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Bulk Actions
                        if (_selectedItems.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                              child: _buildBulkActions(),
                            ),
                          ),

                        // Items List (already uses Slivers)
                        if (filteredItems.isEmpty)
                          SliverToBoxAdapter(child: _buildEmptyState())
                        else
                          ..._buildItemsListSlivers(service),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Loading overlay for bulk operations
        if (_isArchiving)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Archivando productos...',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final buildTime = DateTime.now().difference(buildStart).inMilliseconds;
    debugPrint('✅ [PAGE BUILD] Completed in ${buildTime}ms');

    return widget;
  }

  Widget _buildDashboard(SmartPurchaseListService service) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;
        final theme = Theme.of(context);

        final metrics = [
          _buildMetricItem(
            'TOTAL PENDIENTE',
            service.totalPendingItems.toString(),
            theme,
          ),
          _buildMetricItem(
            'URGENTES',
            service.urgentItemsCount.toString(),
            theme,
            isAlert: service.urgentItemsCount > 0,
          ),
          _buildMetricItem(
            'SIN STOCK',
            service.outOfStockCount.toString(),
            theme,
            isAlert: service.outOfStockCount > 0,
          ),
          _buildMetricItem(
            'PROV. PRINCIPAL',
            service.topSupplier ?? '-',
            theme,
            isText: true,
          ),
        ];

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: isMobile
              ? Column(
                  children: metrics.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final widget = entry.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        widget,
                        if (idx < metrics.length - 1)
                          Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5)),
                      ],
                    );
                  }).toList(),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: metrics.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final widget = entry.value;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          widget,
                          if (idx < metrics.length - 1)
                            Container(
                              height: 48,
                              width: 1,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildMetricItem(
    String label,
    String value,
    ThemeData theme, {
    bool isAlert = false,
    bool isText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isAlert) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ]
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isText ? 20 : 32,
              fontWeight: isText ? FontWeight.w600 : FontWeight.w700,
              letterSpacing: isText ? 0 : -1.0,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(SmartPurchaseListService service) {
    return SizedBox(
        height:
            60, // Enforce a strict height boundary on the filters themselves
        child: LayoutBuilder(builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          if (isMobile) {
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar producto...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _currentPage = 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _showMobileFilters(service),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      Icons.tune,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            );
          }

          // Desktop Filters (New Layout)
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            child: Row(
              children: [
                // Search Bar
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.5)),
                    ),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar productos o SKU...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _currentPage = 1;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Filter Pills
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill(
                            label: 'Estado',
                            value: _statusFilter,
                            items: const {
                              'all': 'Todos',
                              'pending': 'Pendiente',
                              'ordered': 'Ordenado',
                              'received': 'Recibido',
                              'ignored': 'Ignorado',
                              'archived': 'Archivado'
                            },
                            onChanged: (val) {
                              setState(() {
                                _statusFilter = val;
                                _currentPage = 1;
                              });
                              service.loadItems(
                                  statusFilter: val,
                                  supplierFilter: _supplierFilter,
                                  searchQuery: _searchQuery);
                            }),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                            label: 'Proveedor',
                            value: _supplierFilter,
                            items: {
                              'all': 'Todos',
                              'none': 'Sin proveedor',
                              ...Map.fromEntries(_suppliers
                                  .map((s) => MapEntry(s.id, s.name))),
                            },
                            onChanged: (val) {
                              setState(() {
                                _supplierFilter = val;
                                _currentPage = 1;
                              });
                              service.loadItems(
                                  statusFilter: _statusFilter,
                                  supplierFilter: val,
                                  searchQuery: _searchQuery);
                            }),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                            label: 'Prioridad',
                            value: _priorityFilter,
                            items: const {
                              'all': 'Todas',
                              'critical': 'Crítica',
                              'high': 'Alta',
                              'medium': 'Media',
                              'low': 'Baja'
                            },
                            onChanged: (val) {
                              setState(() {
                                _priorityFilter = val;
                                _currentPage = 1;
                              });
                            }),
                        const SizedBox(width: 8),
                        // Category Filter Pill
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _showCategoryPicker(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Categoría: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  _getCategoryDisplayName(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }));
  }

  Widget _buildFilterPill({
    required String label,
    required String value,
    required Map<String, String> items,
    required Function(String) onChanged,
  }) {
    final theme = Theme.of(context);
    final displayValue = items[value] ?? value;

    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) {
        return items.entries
            .map((e) => PopupMenuItem(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 14)),
                ))
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              displayValue,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showMobileFilters(SmartPurchaseListService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filtros',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            // Reset filters
                            _statusFilter = 'pending';
                            _supplierFilter = 'all';
                            _priorityFilter = 'all';
                            _categoryFilter = 'all';
                            _currentPage = 1;
                            _searchQuery = '';
                          });
                          service.loadItems(
                            statusFilter: 'pending',
                            supplierFilter: 'all',
                            searchQuery: '',
                          );
                          Navigator.pop(context);
                        },
                        child: const Text('Restablecer'),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Status
                  DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(
                          value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(
                          value: 'ordered', child: Text('Ordenado')),
                      DropdownMenuItem(
                          value: 'received', child: Text('Recibido')),
                      DropdownMenuItem(
                          value: 'ignored', child: Text('Ignorado')),
                      DropdownMenuItem(
                          value: 'archived', child: Text('Archivado')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => _statusFilter = value);
                        setState(() => _statusFilter = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Supplier
                  DropdownButtonFormField<String>(
                    initialValue: _supplierFilter,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('Todos')),
                      const DropdownMenuItem(
                          value: 'none', child: Text('Sin proveedor')),
                      ..._suppliers.map((supplier) => DropdownMenuItem(
                            value: supplier.id,
                            child: Text(supplier.name),
                          )),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => _supplierFilter = value);
                        setState(() => _supplierFilter = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Priority
                  DropdownButtonFormField<String>(
                    initialValue: _priorityFilter,
                    decoration: const InputDecoration(
                      labelText: 'Prioridad',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todas')),
                      DropdownMenuItem(
                          value: 'critical', child: Text('Crítica (80+)')),
                      DropdownMenuItem(
                          value: 'high', child: Text('Alta (60-80)')),
                      DropdownMenuItem(
                          value: 'medium', child: Text('Media (40-60)')),
                      DropdownMenuItem(value: 'low', child: Text('Baja (<40)')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => _priorityFilter = value);
                        setState(() => _priorityFilter = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category
                  InkWell(
                    onTap: () async {
                      Navigator.pop(
                          context); // Close sheet temporarily to show dialog
                      await _showCategoryPicker(context);
                      // Re-open sheet logic would be complex here, so we just apply and let user reopen if needed
                      // Alternatively, we could implement an inline category picker or verify if _showCategoryPicker supports being called from here
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_forward_ios, size: 16),
                      ),
                      child: Text(
                        _getCategoryDisplayName(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
                      service.loadItems(
                        statusFilter: _statusFilter,
                        supplierFilter: _supplierFilter,
                        searchQuery: _searchQuery,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('Aplicar Filtros'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBulkActions() {
    final isArchivedView = _statusFilter == 'archived';

    return Card(
      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
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
              onPressed: isArchivedView ? _bulkUnarchive : _bulkArchive,
              icon: Icon(isArchivedView ? Icons.unarchive : Icons.archive),
              label: Text(isArchivedView ? 'Desarchivar' : 'Archivar'),
            ),
            const SizedBox(width: 8),
            if (!isArchivedView)
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

  List<SmartPurchaseListItem> _getFilteredItems(
      SmartPurchaseListService service) {
    // Get items with current filters applied
    var items = service.getFilteredItems(
      statusFilter: _statusFilter,
      supplierFilter: _supplierFilter,
      categoryFilter: _categoryFilter,
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
  List<SmartPurchaseListItem> _getPaginatedItems(
      List<SmartPurchaseListItem> allItems) {
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

    debugPrint(
        '⏱️ [LIST BUILD] Building page $_currentPage/$totalPages with ${paginatedItems.length} items ($totalItems total)...');

    final widget = LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        // Common Pagination Controls
        final paginationControls = totalItems > _itemsPerPage
            ? _buildPaginationControls(totalItems, totalPages)
            : const SizedBox.shrink();

        if (isMobile) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totalItems > _itemsPerPage) ...[
                paginationControls,
                const SizedBox(height: 8),
              ],

              // Mobile Cards List
              ...paginatedItems
                  .map((item) => _buildMobileItemCard(item, service)),

              if (totalItems > _itemsPerPage) ...[
                const SizedBox(height: 16),
                paginationControls,
              ],
            ],
          );
        }

        // Desktop Table View
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pagination info and controls at top
            if (totalItems > _itemsPerPage) ...[
              paginationControls,
              const SizedBox(height: 8),
            ],

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width:
                    constraints.maxWidth > 1200 ? constraints.maxWidth : 1200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment
                      .stretch, // SAFE now because of bounded parent width
                  children: [
                    _buildTableHeader(paginatedItems, filteredItems),
                    ...paginatedItems
                        .map((item) => _buildItemRow(item, service)),
                  ],
                ),
              ),
            ),

            // Pagination controls at bottom
            if (totalItems > _itemsPerPage) ...[
              const SizedBox(height: 16),
              paginationControls,
            ],
          ],
        );
      },
    );

    final buildTime = DateTime.now().difference(buildStart).inMilliseconds;
    debugPrint('✅ [LIST BUILD] Completed in ${buildTime}ms');

    return widget;
  }

  List<Widget> _buildItemsListSlivers(SmartPurchaseListService service) {
    return [
      SliverToBoxAdapter(
        child: _buildItemsList(service),
      ),
    ];
  }

  Widget _buildMobileItemCard(
      SmartPurchaseListItem item, SmartPurchaseListService service) {
    final isSelected = _selectedItems.contains(item.id);
    final theme = Theme.of(context);
    final isReceivedView = _statusFilter == 'received';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: item.isPending
            ? () {
                setState(() {
                  if (isSelected) {
                    _selectedItems.remove(item.id);
                    _selectAll = false;
                  } else {
                    _selectedItems.add(item.id);
                  }
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Priority, Name, Selection Checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isReceivedView)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: _buildPriorityBadge(
                          item.priority, item.priorityLevel,
                          isCompact: true),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.productSku != null)
                          Text(
                            item.productSku!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isReceivedView && item.isPending)
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedItems.add(item.id);
                          } else {
                            _selectedItems.remove(item.id);
                            _selectAll = false;
                          }
                        });
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
              const Divider(),

              // Key Metrics Grid
              Row(
                children: [
                  // Stock Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stock / Min',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Row(
                          children: [
                            Text(
                              '${item.currentStock}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: item.isOutOfStock ? Colors.red : null,
                              ),
                            ),
                            const Text(' / ',
                                style: TextStyle(color: Colors.grey)),
                            Text('${item.minStockLevel}'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Suggested Quantity
                  if (!isReceivedView)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sugerido',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            '${item.suggestedQuantity} u',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Supplier
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Proveedor',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Text(
                          item.supplierName ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Only search alternatives if not received
              if (!isReceivedView) ...[
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _findAlternatives(item),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final alternatives = snapshot.data!;
                    final totalStock = alternatives.fold<int>(
                      0,
                      (sum, alt) => sum + (alt['stock'] as int),
                    );

                    return InkWell(
                      onTap: () =>
                          _showAlternativesDialog(context, item, alternatives),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swap_horiz,
                              size: 14,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${alternatives.length} alt. disponibles (${totalStock}u)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],

              // Received View Extras (Dates, Inv #)
              if (isReceivedView) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (item.receivedDate != null)
                      _buildInfoTag(
                        Icons.calendar_today,
                        'Rec: ${item.receivedDate!.day}/${item.receivedDate!.month}',
                      ),
                    if (item.linkedPurchaseInvoiceId != null)
                      Builder(builder: (context) {
                        final invoiceNumber =
                            _getInvoiceNumber(item.linkedPurchaseInvoiceId);
                        return InkWell(
                          onTap: () =>
                              _navigateToInvoice(item.linkedPurchaseInvoiceId!),
                          child: _buildInfoTag(
                            Icons.receipt,
                            invoiceNumber ?? 'Ver Fact.',
                            color: Colors.blue,
                          ),
                        );
                      }),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTag(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color ?? Colors.grey[800],
            fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(
    List<SmartPurchaseListItem> paginatedItems,
    List<SmartPurchaseListItem> filteredItems,
  ) {
    final isReceivedView = _statusFilter == 'received';
    final hasMultiplePages = filteredItems.length > _itemsPerPage;
    final theme = Theme.of(context);

    final headerTextStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 11,
      letterSpacing: 0.5,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            if (!isReceivedView) ...[
              SizedBox(
                width: 80, // Reduced from 120: Checkbox + Todos icon
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Tooltip(
                        message: 'Seleccionar productos en esta página',
                        child: Checkbox(
                          value: _selectAll,
                          onChanged: (value) {
                            setState(() {
                              _selectAll = value ?? false;
                              if (_selectAll) {
                                _selectedItems.addAll(
                                  paginatedItems.map((i) => i.id),
                                );
                              } else {
                                _selectedItems.clear();
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    if (hasMultiplePages)
                      Tooltip(
                        message:
                            'Seleccionar todos los productos (todas las páginas)',
                        child: IconButton(
                          icon: const Icon(Icons.select_all, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedItems.clear();
                              _selectedItems.addAll(
                                filteredItems.map((i) => i.id),
                              );
                              _selectAll = true;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                  width: 70, child: Text('Prioridad', style: headerTextStyle)),
              const SizedBox(width: 16),
            ],
            Expanded(flex: 4, child: Text('Producto', style: headerTextStyle)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Text('Categoría', style: headerTextStyle)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Text('Proveedor', style: headerTextStyle)),
            const SizedBox(width: 16),
            SizedBox(
                width: 120,
                child: Text('Alternativas', style: headerTextStyle)),
            const SizedBox(width: 16),
            if (isReceivedView) ...[
              SizedBox(
                  width: 120,
                  child: Text('Stock Inicial', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 120,
                  child: Text('Stock Final', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 100,
                  child: Text('Diferencia', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 130,
                  child: Text('N° Factura', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 120, child: Text('Creado el', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 120,
                  child: Text('Recibido el', style: headerTextStyle)),
            ] else ...[
              SizedBox(width: 80, child: Text('Stock', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 80, child: Text('Cant. Sug.', style: headerTextStyle)),
              const SizedBox(width: 16),
              SizedBox(
                  width: 100, child: Text('Estado', style: headerTextStyle)),
            ],
            const SizedBox(width: 16),
            SizedBox(
                width: 200, child: Text('Acciones', style: headerTextStyle)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(
      SmartPurchaseListItem item, SmartPurchaseListService service) {
    final isSelected = _selectedItems.contains(item.id);
    final isReceivedView = _statusFilter == 'received';
    final theme = Theme.of(context);
    bool isHovered = false;

    return StatefulBuilder(
      builder: (context, setRowState) {
        return MouseRegion(
          onEnter: (_) => setRowState(() => isHovered = true),
          onExit: (_) => setRowState(() => isHovered = false),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.2))),
            ),
            child: Material(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                  : Colors.transparent,
              child: InkWell(
                onTap: item.isPending
                    ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedItems.remove(item.id);
                            _selectAll = false;
                          } else {
                            _selectedItems.add(item.id);
                          }
                        });
                      }
                    : null,
                hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.02),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      // Checkbox - only for non-received view
                      if (!isReceivedView) ...[
                        SizedBox(
                          width: 80, // Match the Header Checkbox + Todos width
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
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
                          ),
                        ),

                        // Priority Indicator - only for non-received view
                        SizedBox(
                          width: 70,
                          child: _buildPriorityBadge(
                              item.priority, item.priorityLevel),
                        ),
                        const SizedBox(width: 16),
                      ],

                      // Product
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            if (item.productSku != null)
                              Text(
                                'SKU: ${item.productSku}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant),
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

                      // Category
                      Expanded(
                        flex: 2,
                        child: Tooltip(
                          message: item.categoryName ?? 'Sin categoría',
                          waitDuration: const Duration(milliseconds: 500),
                          child: Text(
                            _extractCategoryName(item.categoryName),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Supplier
                      Expanded(
                        flex: 2,
                        child: Text(item.supplierName ?? 'Sin proveedor'),
                      ),
                      const SizedBox(width: 16),

                      // Alternatives
                      SizedBox(
                        width: 120,
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: _findAlternatives(item),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text('-',
                                  style: TextStyle(color: Colors.grey));
                            }

                            final alternatives = snapshot.data!;
                            final totalStock = alternatives.fold<int>(
                              0,
                              (sum, alt) => sum + (alt['stock'] as int),
                            );

                            return InkWell(
                              onTap: () => _showAlternativesDialog(
                                  context, item, alternatives),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: totalStock > 10
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${alternatives.length} (${totalStock}u)',
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        decoration: TextDecoration.underline,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
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
                              color: item.stockAtOrder == null
                                  ? Colors.grey
                                  : null,
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
                              color: item.stockAtReceipt != null
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Diferencia (Stock Final - Stock Inicial)
                        SizedBox(
                          width: 100,
                          child: Builder(
                            builder: (context) {
                              if (item.stockAtOrder == null ||
                                  item.stockAtReceipt == null) {
                                return const Text(
                                  'N/A',
                                  style: TextStyle(color: Colors.grey),
                                );
                              }

                              final stockInitial = item.stockAtOrder!;
                              final stockFinal = item.stockAtReceipt!;
                              final difference = stockFinal - stockInitial;

                              return Text(
                                difference >= 0
                                    ? '+$difference'
                                    : difference.toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: difference > 0
                                      ? Colors.green
                                      : (difference < 0
                                          ? Colors.red
                                          : Colors.grey),
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
                              final invoiceNumber = _getInvoiceNumber(
                                  item.linkedPurchaseInvoiceId);

                              if (invoiceNumber == null) {
                                return Text(
                                  '-',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                );
                              }

                              return InkWell(
                                onTap: () => _navigateToInvoice(
                                    item.linkedPurchaseInvoiceId!),
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
                              final createdDate = _getInvoiceCreatedDate(
                                  item.linkedPurchaseInvoiceId);

                              if (createdDate == null) {
                                return Text(
                                  '-',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                );
                              }

                              return Text(
                                '${createdDate.day}/${createdDate.month}/${createdDate.year}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant),
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
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ] else ...[
                        // Stock - for non-received view
                        SizedBox(
                          width: 80,
                          child: Text(
                            '${item.currentStock} / ${item.minStockLevel}',
                            style: TextStyle(
                              color: item.currentStock <= item.minStockLevel
                                  ? Colors.red
                                  : null,
                              fontWeight:
                                  item.currentStock <= item.minStockLevel
                                      ? FontWeight.bold
                                      : null,
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
                        width:
                            200, // Match the Header width to fit 4 IconButtons
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: isHovered || isSelected ? 1.0 : 0.2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.isPending) ...[
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () =>
                                      _showEditItemDialog(item, service),
                                  tooltip: 'Editar',
                                  color: theme.colorScheme.onSurfaceVariant,
                                  hoverColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.1),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.archive, size: 18),
                                  onPressed: () =>
                                      service.updateStatus(item.id, 'archived'),
                                  tooltip: 'Archivar',
                                  color: theme.colorScheme.onSurfaceVariant,
                                  hoverColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.1),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.visibility_off,
                                      size: 18),
                                  onPressed: () =>
                                      service.markAsIgnored(item.id),
                                  tooltip: 'Ignorar',
                                  color: theme.colorScheme.onSurfaceVariant,
                                  hoverColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.1),
                                ),
                              ],
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: () => _confirmDelete(item, service),
                                tooltip: 'Eliminar',
                                color: theme.colorScheme.error
                                    .withValues(alpha: 0.7),
                                hoverColor: theme.colorScheme.error
                                    .withValues(alpha: 0.1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPriorityBadge(double priority, String level,
      {bool isCompact = false}) {
    Color color;

    switch (level) {
      case 'critical':
        color = Colors.redAccent;
        break;
      case 'high':
        color = Colors.orangeAccent;
        break;
      case 'medium':
        color = Colors.amber;
        break;
      default:
        color = Colors.green;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (!isCompact) ...[
          const SizedBox(width: 6),
          Text(
            priority.toStringAsFixed(0),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]
      ],
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
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
                        initialValue: selectedSupplierId,
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
                    const SnackBar(
                        content: Text('El nombre del producto es requerido')),
                  );
                  return;
                }

                final qty = int.tryParse(qtyController.text) ?? 1;
                if (qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('La cantidad debe ser mayor a 0')),
                  );
                  return;
                }

                try {
                  final service = context.read<SmartPurchaseListService>();

                  // Get supplier name if selected
                  String? supplierName;
                  if (selectedSupplierId != null) {
                    final suppliers =
                        await context.read<PurchaseService>().getSuppliers();
                    supplierName = suppliers
                        .firstWhere((s) => s.id == selectedSupplierId)
                        .name;
                  }

                  await service.addItem(
                    productId: selectedProductId,
                    productName: productController.text.trim(),
                    productSku: skuController.text.trim().isEmpty
                        ? null
                        : skuController.text.trim(),
                    quantity: qty,
                    supplierId: selectedSupplierId,
                    supplierName: supplierName,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Producto agregado a la lista de compras')),
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

  void _showEditItemDialog(
      SmartPurchaseListItem item, SmartPurchaseListService service) {
    // TODO: Implement edit dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Función de editar en desarrollo')),
    );
  }

  void _confirmDelete(
      SmartPurchaseListItem item, SmartPurchaseListService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content:
            Text('¿Eliminar "${item.productName}" de la lista de compras?'),
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
            parts.add(
                '${result.removed} eliminado${result.removed > 1 ? "s" : ""}');
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

  void _bulkArchive() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archivar productos'),
        content:
            Text('¿Archivar ${_selectedItems.length} productos seleccionados?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      final service = context.read<SmartPurchaseListService>();
      final count = _selectedItems.length;

      // Bulk archive in single query (much faster!)
      await service.bulkUpdateStatus(_selectedItems.toList(), 'archived');

      if (mounted) {
        setState(() {
          _selectedItems.clear();
          _selectAll = false;
          _currentPage = 1; // Reset to page 1 after archiving
          _isArchiving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $count productos archivados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isArchiving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al archivar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _bulkUnarchive() async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desarchivar productos'),
        content: Text(
            '¿Desarchivar ${_selectedItems.length} productos seleccionados?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desarchivar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      final service = context.read<SmartPurchaseListService>();
      final count = _selectedItems.length;

      // Bulk unarchive (set status back to pending)
      await service.bulkUpdateStatus(_selectedItems.toList(), 'pending');

      if (mounted) {
        setState(() {
          _selectedItems.clear();
          _selectAll = false;
          _currentPage = 1;
          _isArchiving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $count productos desarchivados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isArchiving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desarchivar: $e'),
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
                  final supplierName =
                      itemsForSupplier.first.supplierName ?? 'Sin nombre';
                  return ListTile(
                    title: Text(supplierName),
                    subtitle: Text(
                        '${itemsForSupplier.length} producto(s) asignado(s)'),
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
        if (finalSupplierId == null) {
          return; // User cancelled supplier selection
        }
      }

      debugPrint(
          '📦 Creating purchase order with ${selectedItemsList.length} items for supplier: $finalSupplierId');

      // Navigate with ALL selected products, regardless of their assigned supplier
      if (!mounted) return;
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
    String searchQuery = '';

    return showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredSuppliers = searchQuery.isEmpty
              ? _suppliers
              : _suppliers.where((supplier) {
                  final name = supplier.name.toLowerCase();
                  final query = searchQuery.toLowerCase();
                  return name.contains(query);
                }).toList();

          return AlertDialog(
            title: const Text('Seleccionar Proveedor'),
            content: SizedBox(
              width: 500,
              height: 500,
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar proveedor',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        searchQuery = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Suppliers list
                  Expanded(
                    child: filteredSuppliers.isEmpty
                        ? const Center(
                            child: Text('No se encontraron proveedores'),
                          )
                        : ListView.builder(
                            itemCount: filteredSuppliers.length,
                            itemBuilder: (context, index) {
                              final supplier = filteredSuppliers[index];
                              return ListTile(
                                title: Text(supplier.name),
                                subtitle: supplier.email != null
                                    ? Text(supplier.email!)
                                    : null,
                                onTap: () =>
                                    Navigator.pop(context, supplier.id),
                              );
                            },
                          ),
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
          );
        },
      ),
    );
  }

  Future<void> _navigateToPurchaseForm(
    List<SmartPurchaseListItem> items,
    String? supplierId,
  ) async {
    if (!mounted) return;

    try {
      debugPrint('🚀 Navigating to purchase form with ${items.length} items');

      // Store data in service to be picked up by the form
      final purchaseService = context.read<PurchaseService>();
      purchaseService.setPendingSmartPurchaseData(
        supplierId: supplierId,
        lineItems: items
            .map((item) => {
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'product_sku': item.productSku,
                  'purchase_treatment': item.purchaseTreatment.dbValue,
                  'suggested_quantity': item.suggestedQuantity,
                })
            .toList(),
      );

      // Navigate using GoRouter like everyone else!
      context.go('/purchases/new');

      debugPrint('✅ Navigated to purchase form');
    } catch (e) {
      debugPrint('❌ Error navigating to purchase form: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir formulario: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                onPressed:
                    _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                tooltip: 'Página anterior',
              ),

              // Page numbers
              ..._buildPageNumbers(totalPages),

              // Next page button
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                tooltip: 'Página siguiente',
              ),

              // Last page button
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages
                    ? () => _goToPage(totalPages)
                    : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  final Color backgroundColor;

  _StickyHeaderDelegate({
    required this.child,
    required this.height,
    required this.backgroundColor,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: height,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.child != child ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
