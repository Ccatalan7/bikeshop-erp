import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../models/category_models.dart';
import '../services/category_service.dart';

enum CategoryViewMode { list, cards }

/// Hierarchical Category Browser (Odoo-style)
/// Navigate through categories like a file explorer with breadcrumbs
class HierarchicalCategoryPage extends StatefulWidget {
  final String? categoryId; // Current category being viewed (null = root)
  final bool embedded;

  const HierarchicalCategoryPage({
    super.key,
    this.categoryId,
    this.embedded = false,
  });

  @override
  State<HierarchicalCategoryPage> createState() => _HierarchicalCategoryPageState();
}

class _HierarchicalCategoryPageState extends State<HierarchicalCategoryPage> {
  late CategoryService _categoryService;
  late DatabaseService _databaseService;
  Category? _currentCategory;
  List<Category> _subcategories = [];
  List<Map<String, dynamic>> _products = []; // Products in current category
  List<Category> _allCategories = []; // All categories for global search
  Map<String, Category> _categoryByPath = {};
  List<CategoryBreadcrumb> _breadcrumbs = [];
  bool _isLoading = true;
  CategoryViewMode _viewMode = CategoryViewMode.cards;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _loadData();
  }

  @override
  void didUpdateWidget(HierarchicalCategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload data when categoryId changes (when navigating via cards/search)
    if (oldWidget.categoryId != widget.categoryId) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final startTime = DateTime.now();
    debugPrint('⏱️ [LOAD] Starting _loadData for categoryId: ${widget.categoryId}');
    
    setState(() => _isLoading = true);
    try {
      // Only load all categories if search is active
      if (_searchTerm.isNotEmpty && _allCategories.isEmpty) {
        final searchStart = DateTime.now();
        _allCategories = await _categoryService.getCategories(activeOnly: true);
        _indexCategoryPaths();
        debugPrint('⏱️ [LOAD] All categories loaded in ${DateTime.now().difference(searchStart).inMilliseconds}ms');
      }
      
      if (widget.categoryId == null) {
        // Load root categories (no products at root level)
        final rootStart = DateTime.now();
        _currentCategory = null;
        _subcategories = await _categoryService.getRootCategories();
        debugPrint('⏱️ [LOAD] Root categories loaded (${_subcategories.length} items) in ${DateTime.now().difference(rootStart).inMilliseconds}ms');
        _products = [];
        _breadcrumbs = await _generateBreadcrumbs(null);
      } else {
        // Load category, subcategories, and products in PARALLEL
        final parallelStart = DateTime.now();
        final results = await Future.wait([
          _categoryService.getCategoryById(widget.categoryId!),
          _categoryService.getSubcategories(widget.categoryId!),
          _loadProductsForCategory(widget.categoryId!),
        ]);
        debugPrint('⏱️ [LOAD] Parallel queries completed in ${DateTime.now().difference(parallelStart).inMilliseconds}ms');
        
        _currentCategory = results[0] as Category?;
        _subcategories = results[1] as List<Category>;
        _products = results[2] as List<Map<String, dynamic>>;
        
        debugPrint('⏱️ [LOAD] Loaded: ${_subcategories.length} subcategories, ${_products.length} products');
        
        if (_currentCategory != null) {
          _breadcrumbs = await _generateBreadcrumbs(_currentCategory!);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
      
      debugPrint('⏱️ [LOAD] TOTAL _loadData completed in ${DateTime.now().difference(startTime).inMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ [LOAD] Error after ${DateTime.now().difference(startTime).inMilliseconds}ms: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadProductsForCategory(String categoryId) async {
    try {
      final products = await _databaseService.select(
        'products',
        where: 'category_id=$categoryId',
        orderBy: 'name',
      );
      return products;
    } catch (e) {
      if (mounted) {
        print('Error loading products: $e');
      }
      return [];
    }
  }

  void _navigateToCategory(String? categoryId) {
    if (categoryId == null) {
      context.push('/inventory/categories');
    } else {
      context.push('/inventory/categories/$categoryId');
    }
  }

  void _indexCategoryPaths() {
    _categoryByPath = {};
    for (final category in _allCategories) {
      final fullPath = category.fullPath.trim();
      if (fullPath.isNotEmpty) {
        _categoryByPath[fullPath] = category;
      }
    }
  }

  Future<List<CategoryBreadcrumb>> _generateBreadcrumbs(Category? category) async {
    final breadcrumbs = <CategoryBreadcrumb>[
      CategoryBreadcrumb(name: 'Todas las Categorías', categoryId: null, level: -1),
    ];

    if (category == null) {
      return breadcrumbs;
    }

    // Build breadcrumb path by traversing parent chain
    final path = <Category>[];
    Category? current = category;
    
    // Traverse up the parent chain
    while (current != null) {
      path.insert(0, current); // Insert at beginning to maintain order
      
      // Stop if we've reached a root category (no parent)
      if (current.parentId == null) {
        break;
      }
      
      // Fetch parent category
      try {
        current = await _categoryService.getCategoryById(current.parentId!);
      } catch (e) {
        debugPrint('⚠️ Error fetching parent category: $e');
        break;
      }
    }

    // Build breadcrumbs from the path
    for (int i = 0; i < path.length; i++) {
      breadcrumbs.add(
        CategoryBreadcrumb(
          name: path[i].name,
          categoryId: path[i].id,
          level: i,
        ),
      );
    }

    return breadcrumbs;
  }

  Future<void> _showImportDialog() async {
    showDialog(
      context: context,
      builder: (context) => _ImportCategoriesDialog(
        categoryService: _categoryService,
        onComplete: () {
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
          // Header with breadcrumbs and actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumb Navigation
                _buildBreadcrumbs(),
                const SizedBox(height: 16),
                
                // Action Bar
                Row(
                  children: [
                    // Search
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar categorías...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) async {
                          setState(() => _searchTerm = value);
                          // Load all categories when user starts searching
                          if (value.isNotEmpty && _allCategories.isEmpty) {
                            setState(() => _isLoading = true);
                            _allCategories = await _categoryService.getCategories(activeOnly: true);
                            _indexCategoryPaths();
                            setState(() => _isLoading = false);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // View Toggle
                    SegmentedButton<CategoryViewMode>(
                      segments: const [
                        ButtonSegment(
                          value: CategoryViewMode.cards,
                          icon: Icon(Icons.grid_view),
                          tooltip: 'Vista de tarjetas',
                        ),
                        ButtonSegment(
                          value: CategoryViewMode.list,
                          icon: Icon(Icons.view_list),
                          tooltip: 'Vista de lista',
                        ),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (Set<CategoryViewMode> newSelection) {
                        setState(() => _viewMode = newSelection.first);
                      },
                    ),
                    const SizedBox(width: 12),
                    
                    // Import Button
                    AppButton(
                      text: 'Importar',
                      icon: Icons.upload_file,
                      type: ButtonType.secondary,
                      onPressed: _showImportDialog,
                    ),
                    const SizedBox(width: 8),
                    
                    // Create Button
                    AppButton(
                      text: 'Nueva Categoría',
                      icon: Icons.add,
                      type: ButtonType.primary,
                      onPressed: () async {
                        // Pass current category as parent context
                        final parentId = widget.categoryId;
                        if (parentId != null) {
                          await context.push('/inventory/categories/new?parent=$parentId');
                        } else {
                          await context.push('/inventory/categories/new');
                        }
                        // Reload after returning from form
                        _loadData();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _buildContent(),
          ),
      ],
    );

    if (widget.embedded) return body;

    return MainLayout(
      title: 'Categorías',
      child: body,
    );
  }

  Widget _buildBreadcrumbs() {
    return Wrap(
      spacing: 4,
      children: [
        for (int i = 0; i < _breadcrumbs.length; i++) ...[
          if (i > 0) Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
          InkWell(
            onTap: () {
              final breadcrumb = _breadcrumbs[i];
              debugPrint('🔗 Breadcrumb clicked: ${breadcrumb.name} -> categoryId: ${breadcrumb.categoryId}');
              // Navigate to the breadcrumb's category
              _navigateToCategory(breadcrumb.categoryId);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _breadcrumbs[i].name,
                style: TextStyle(
                  color: i == _breadcrumbs.length - 1
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[700],
                  fontWeight: i == _breadcrumbs.length - 1
                      ? FontWeight.bold
                      : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent() {
    // When searching, search ALL categories globally (don't show products in search)
    if (_searchTerm.isNotEmpty) {
      final filteredCategories = _allCategories.where((cat) =>
          cat.fullPath.toLowerCase().contains(_searchTerm.toLowerCase()) ||
          cat.name.toLowerCase().contains(_searchTerm.toLowerCase())).toList();

      if (filteredCategories.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No se encontraron resultados para "$_searchTerm"',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchTerm = '';
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpiar búsqueda'),
              ),
            ],
          ),
        );
      }

      return _viewMode == CategoryViewMode.cards
          ? _buildCardsView(filteredCategories)
          : _buildListView(filteredCategories);
    }

    // Not searching - show subcategories and products
    final hasSubcategories = _subcategories.isNotEmpty;
    final hasProducts = _products.isNotEmpty;

    if (!hasSubcategories && !hasProducts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Esta categoría está vacía',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Subcategories section
        if (hasSubcategories) ...[
          Row(
            children: [
              Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Subcategorías (${_subcategories.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _viewMode == CategoryViewMode.cards
              ? GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1,
                  ),
                  itemCount: _subcategories.length,
                  itemBuilder: (context, index) {
                    return _buildCategoryCard(_subcategories[index]);
                  },
                )
              : Column(
                  children: _subcategories.map((cat) => _buildCategoryListTile(cat)).toList(),
                ),
          if (hasProducts) const SizedBox(height: 24),
        ],

        // Products section
        if (hasProducts) ...[
          Row(
            children: [
              Icon(Icons.inventory_2, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Productos (${_products.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _viewMode == CategoryViewMode.cards
              ? GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    return _buildProductCard(_products[index]);
                  },
                )
              : Column(
                  children: _products.map((product) => _buildProductListTile(product)).toList(),
                ),
        ],
      ],
    );
  }

  Widget _buildCardsView(List<Category> categories) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildCategoryCard(category);
      },
    );
  }

  Widget _buildListView(List<Category> categories) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildCategoryListTile(category);
      },
    );
  }

  Widget _buildCategoryCard(Category category) {
    final isSearchResult = _searchTerm.isNotEmpty;
    
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _navigateToCategory(category.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Category image or placeholder
                  category.imageUrl != null && category.imageUrl!.isNotEmpty
                      ? Image.network(
                          category.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildImagePlaceholder();
                          },
                        )
                      : _buildImagePlaceholder(),
                  
                  // Three-dot menu button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.white.withOpacity(0.9),
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'edit') {
                            context.push('/inventory/categories/${category.id}/edit');
                          } else if (value == 'delete') {
                            _showDeleteConfirmation(category);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Eliminar', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Name section
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                alignment: Alignment.center,
                child: Text(
                  isSearchResult ? category.fullPath : category.name,
                  style: TextStyle(
                    fontSize: isSearchResult ? 11 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.category,
        size: 64,
        color: Colors.grey[400],
      ),
    );
  }

  Widget _buildCategoryListTile(Category category) {
    final isSearchResult = _searchTerm.isNotEmpty;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: category.imageUrl != null && category.imageUrl!.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  category.imageUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.category, color: Colors.grey[400]),
                    );
                  },
                ),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.category, color: Colors.grey[400]),
              ),
        title: Text(
          isSearchResult ? category.fullPath : category.name,
          style: TextStyle(
            fontWeight: category.level == 0 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: category.description != null
            ? Text(
                category.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'edit') {
              context.push('/inventory/categories/${category.id}/edit');
            } else if (value == 'delete') {
              _showDeleteConfirmation(category);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _navigateToCategory(category.id),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la categoría "${category.name}"?\n\n'
          'Esta acción no se puede deshacer.',
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

    if (confirmed == true) {
      try {
        await _categoryService.deleteCategory(category.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Categoría eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData(); // Reload the list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final imageUrl = product['image_url'] as String?;
    final name = product['name'] as String;
    final price = product['price'] as num?;
    final stock = product['stock'] as num? ?? 0;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push('/inventory/products/${product['id']}/edit');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Product image
            Expanded(
              flex: 3,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: Icon(Icons.image, size: 48, color: Colors.grey[400]),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: Icon(Icons.image, size: 48, color: Colors.grey[400]),
                    ),
            ),
            
            // Product info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (price != null)
                          Text(
                            '\$${price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        Text(
                          'Stock: $stock',
                          style: TextStyle(
                            fontSize: 11,
                            color: stock > 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListTile(Map<String, dynamic> product) {
    final imageUrl = product['image_url'] as String?;
    final name = product['name'] as String;
    final price = product['price'] as num?;
    final stock = product['stock'] as num? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: imageUrl != null && imageUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.image, color: Colors.grey[400]),
                    );
                  },
                ),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image, color: Colors.grey[400]),
              ),
        title: Text(name),
        subtitle: Text(
          'Stock: $stock',
          style: TextStyle(
            color: stock > 0 ? Colors.green : Colors.red,
          ),
        ),
        trailing: price != null
            ? Text(
                '\$${price.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : null,
        onTap: () {
          context.push('/inventory/products/${product['id']}/edit');
        },
      ),
    );
  }
}

/// Dialog for importing categories from Excel
class _ImportCategoriesDialog extends StatefulWidget {
  final CategoryService categoryService;
  final VoidCallback onComplete;

  const _ImportCategoriesDialog({
    required this.categoryService,
    required this.onComplete,
  });

  @override
  State<_ImportCategoriesDialog> createState() => _ImportCategoriesDialogState();
}

class _ImportCategoriesDialogState extends State<_ImportCategoriesDialog> {
  bool _isImporting = false;
  String? _selectedFileName;
  List<String>? _previewData;
  Uint8List? _fullDataBytes; // Store file bytes for import
  late CategoryService _categoryService;

  @override
  void initState() {
    super.initState();
    _categoryService = widget.categoryService;
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, // Important for web
      );

      if (result != null) {
        // Get bytes (works on both web and mobile)
        final bytes = result.files.single.bytes;
        if (bytes == null) {
          throw Exception('No se pudieron leer los datos del archivo');
        }

        final excel = excel_lib.Excel.decodeBytes(bytes);

        // Get first sheet
        final sheet = excel.tables.keys.first;
        final rows = excel.tables[sheet]!.rows;

        // Extract first column (skip header if exists)
        final categories = <String>[];
        for (int i = 0; i < rows.length; i++) {
          final cell = rows[i].first;
          if (cell != null && cell.value != null) {
            final value = cell.value.toString().trim();
            if (value.isNotEmpty && value != 'Nombre en pantalla') {
              categories.add(value);
            }
          }
        }

        setState(() {
          _selectedFileName = result.files.single.name;
          _previewData = categories.take(10).toList();
          _fullDataBytes = bytes; // Store for import
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error leyendo archivo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _import() async {
    if (_previewData == null || _fullDataBytes == null) return;

    setState(() => _isImporting = true);

    try {
      // Use stored bytes from preview (no need to pick file again)
      final excel = excel_lib.Excel.decodeBytes(_fullDataBytes!);

      final sheet = excel.tables.keys.first;
      final rows = excel.tables[sheet]!.rows;

      final categories = <String>[];
      for (int i = 0; i < rows.length; i++) {
        final cell = rows[i].first;
        if (cell != null && cell.value != null) {
          final value = cell.value.toString().trim();
          if (value.isNotEmpty && value != 'Nombre en pantalla') {
            categories.add(value);
          }
        }
      }

      // Import
      final stats = await _categoryService.importCategoriesFromList(categories);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Importación completada:\n'
              '✅ ${stats['created']} creadas\n'
              '⏭️ ${stats['skipped']} omitidas\n'
              '❌ ${stats['errors']} errores',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        widget.onComplete(); // Reload categories in parent
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importando: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar Categorías desde Excel'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formato del archivo:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Una sola columna con nombres de categorías'),
            const Text('• Use "/" para separar niveles (e.g., "Accesorios / Asientos / Tija")'),
            const Text('• El sistema creará automáticamente la jerarquía'),
            const Divider(height: 24),
            
            if (_selectedFileName != null) ...[
              Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_selectedFileName!)),
                ],
              ),
              const SizedBox(height: 16),
              
              if (_previewData != null && _previewData!.isNotEmpty) ...[
                const Text(
                  'Vista previa (primeras 10):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: _previewData!.length,
                    itemBuilder: (context, index) {
                      final path = _previewData![index];
                      final level = '/'.allMatches(path).length;
                      return Padding(
                        padding: EdgeInsets.only(
                          left: 16.0 + (level * 16.0),
                          top: 4,
                          bottom: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              level == 0 ? Icons.folder : Icons.subdirectory_arrow_right,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                path,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_selectedFileName == null)
          ElevatedButton.icon(
            onPressed: _isImporting ? null : _pickFile,
            icon: const Icon(Icons.file_upload),
            label: const Text('Seleccionar Archivo'),
          )
        else
          ElevatedButton.icon(
            onPressed: _isImporting ? null : _import,
            icon: _isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isImporting ? 'Importando...' : 'Importar'),
          ),
      ],
    );
  }
}
