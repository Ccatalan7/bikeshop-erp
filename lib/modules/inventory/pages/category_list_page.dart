import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/themes/app_theme.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../models/category_models.dart';
import '../services/category_service.dart';

enum CategoryViewMode { list, cards }

class CategoryListPage extends StatefulWidget {
  const CategoryListPage({super.key});

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  final TextEditingController _searchController = TextEditingController();
  late CategoryService _categoryService;
  List<Category> _categories = [];
  List<Category> _filteredCategories = [];
  bool _isLoading = true;
  String _searchTerm = '';
  bool _showInactiveOnly = false;
  CategoryViewMode _viewMode = CategoryViewMode.list;

  @override
  void initState() {
    super.initState();
    _categoryService = CategoryService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final categories = await _categoryService.getCategories(
        searchTerm: _searchTerm.isEmpty ? null : _searchTerm,
      );
      setState(() {
        _categories = categories;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando categorías: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _applyFilters() {
    List<Category> filtered = _categories;
    
    if (_searchTerm.isNotEmpty) {
      filtered = filtered
          .where((category) =>
              category.name.toLowerCase().contains(_searchTerm.toLowerCase()) ||
              (category.description?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false))
          .toList();
    }
    
    if (_showInactiveOnly) {
      filtered = filtered.where((category) => !category.isActive).toList();
    }
    
    setState(() => _filteredCategories = filtered);
  }

  void _onSearchChanged(String searchTerm) {
    setState(() => _searchTerm = searchTerm);
    _applyFilters();
  }

  void _onInactiveToggle(bool value) {
    setState(() => _showInactiveOnly = value);
    _applyFilters();
  }

  Future<void> _toggleCategoryStatus(Category category) async {
    try {
      await _categoryService.toggleCategoryStatus(category.id!);
      await _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(category.isActive 
                ? 'Categoría desactivada' 
                : 'Categoría activada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cambiando estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Está seguro que desea eliminar la categoría "${category.name}"?'),
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

    if (confirmed == true) {
      try {
        await _categoryService.deleteCategory(category.id!);
        await _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Categoría eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando categoría: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = AppTheme.isMobile(context);
    
    return MainLayout(
      child: Column(
        children: [
          // Header - Mobile responsive
          Padding(
            padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Categorías',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        text: 'Nueva Categoría',
                        icon: Icons.add,
                        fullWidth: true,
                        onPressed: () {
                          context.push('/inventory/categories/new').then((_) {
                            _loadCategories();
                          });
                        },
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Categorías',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // View mode toggle (desktop only)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.view_list),
                              onPressed: () => setState(() => _viewMode = CategoryViewMode.list),
                              color: _viewMode == CategoryViewMode.list ? Colors.blue : Colors.grey,
                              tooltip: 'Vista de lista',
                            ),
                            IconButton(
                              icon: const Icon(Icons.grid_view),
                              onPressed: () => setState(() => _viewMode = CategoryViewMode.cards),
                              color: _viewMode == CategoryViewMode.cards ? Colors.blue : Colors.grey,
                              tooltip: 'Vista de tarjetas',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      AppButton(
                        text: 'Nueva Categoría',
                        icon: Icons.add,
                        onPressed: () {
                          context.push('/inventory/categories/new').then((_) {
                            _loadCategories();
                          });
                        },
                      ),
                    ],
                  ),
          ),
          
          // Search
          SearchBarWidget(
            controller: _searchController,
            hintText: 'Buscar por nombre o descripción...',
            onChanged: _onSearchChanged,
          ),
          
          // Filters
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12.0 : 16.0),
            child: Row(
              children: [
                SizedBox(
                  width: isMobile ? null : 200,
                  child: CheckboxListTile(
                    title: const Text('Solo Inactivas'),
                    value: _showInactiveOnly,
                    onChanged: (value) => _onInactiveToggle(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Stats - Mobile responsive
          if (!_isLoading && _categories.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: isMobile
                  ? Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('Total', _categories.length.toString(), isMobile),
                            _buildStatItem(
                              'Activas', 
                              _categories.where((c) => c.isActive).length.toString(),
                              isMobile,
                            ),
                            _buildStatItem(
                              'Inactivas', 
                              _categories.where((c) => !c.isActive).length.toString(),
                              isMobile,
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _buildStatItem('Total', _categories.length.toString(), isMobile),
                        const SizedBox(width: 24),
                        _buildStatItem(
                          'Activas', 
                          _categories.where((c) => c.isActive).length.toString(),
                          isMobile,
                        ),
                        const SizedBox(width: 24),
                        _buildStatItem(
                          'Inactivas', 
                          _categories.where((c) => !c.isActive).length.toString(),
                          isMobile,
                        ),
                      ],
                    ),
            ),
          
          const SizedBox(height: 16),
          
          // Categories List
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _buildCategoriesList(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, bool isMobile) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: isMobile ? 18 : 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 11 : 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesList(bool isMobile) {
    if (_filteredCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty && !_showInactiveOnly
                  ? 'No hay categorías registradas'
                  : 'No se encontraron categorías',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty && !_showInactiveOnly) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Agregar Primera Categoría',
                onPressed: () {
                  context.push('/inventory/categories/new').then((_) {
                    _loadCategories();
                  });
                },
              ),
            ],
          ],
        ),
      );
    }

    // Force list view on mobile
    final effectiveViewMode = isMobile ? CategoryViewMode.list : _viewMode;

    return RefreshIndicator(
      onRefresh: _loadCategories,
      child: effectiveViewMode == CategoryViewMode.list
          ? ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12.0 : 16.0),
              itemCount: _filteredCategories.length,
              itemBuilder: (context, index) {
                final category = _filteredCategories[index];
                return _buildCategoryListItem(category, isMobile);
              },
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
              ),
              itemCount: _filteredCategories.length,
              itemBuilder: (context, index) {
                final category = _filteredCategories[index];
                return _buildCategoryGridItem(category);
              },
            ),
    );
  }

  Widget _buildCategoryListItem(Category category, bool isMobile) {
    final theme = Theme.of(context);
    final bool hasImage = category.imageUrl != null && category.imageUrl!.isNotEmpty;
    
    return Card(
      margin: EdgeInsets.only(bottom: isMobile ? 10 : 12),
      child: InkWell(
        onTap: () {
          context.push('/inventory/products?category=${category.id}');
        },
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Row(
            children: [
              // Image/Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasImage
                    ? CachedNetworkImage(
                        imageUrl: category.imageUrl!,
                        width: isMobile ? 48 : 56,
                        height: isMobile ? 48 : 56,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: isMobile ? 48 : 56,
                          height: isMobile ? 48 : 56,
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: isMobile ? 48 : 56,
                          height: isMobile ? 48 : 56,
                          decoration: BoxDecoration(
                            color: category.isActive 
                                ? theme.colorScheme.primary.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.category,
                            color: category.isActive ? theme.colorScheme.primary : Colors.grey,
                            size: isMobile ? 24 : 28,
                          ),
                        ),
                      )
                    : Container(
                        width: isMobile ? 48 : 56,
                        height: isMobile ? 48 : 56,
                        decoration: BoxDecoration(
                          color: category.isActive 
                              ? theme.colorScheme.primary.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.category,
                          color: category.isActive ? theme.colorScheme.primary : Colors.grey,
                          size: isMobile ? 24 : 28,
                        ),
                      ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: isMobile ? 15 : 16,
                              color: category.isActive ? null : Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 8, 
                            vertical: isMobile ? 2 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: category.isActive ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            category.isActive ? 'Activa' : 'Inactiva',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 10 : 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (category.description != null && category.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        category.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: category.isActive 
                              ? theme.colorScheme.onSurface.withOpacity(0.6)
                              : Colors.grey,
                          fontSize: isMobile ? 12 : 13,
                        ),
                        maxLines: isMobile ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              
              // Actions
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      context.push('/inventory/categories/${category.id}/edit').then((_) {
                        _loadCategories();
                      });
                      break;
                    case 'toggle':
                      _toggleCategoryStatus(category);
                      break;
                    case 'delete':
                      _deleteCategory(category);
                      break;
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
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      leading: Icon(category.isActive ? Icons.visibility_off : Icons.visibility),
                      title: Text(category.isActive ? 'Desactivar' : 'Activar'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                child: Icon(
                  Icons.more_vert,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryGridItem(Category category) {
    final bool hasImage = category.imageUrl != null && category.imageUrl!.isNotEmpty;
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Navigate to products filtered by this category
          context.push('/inventory/products?category=${category.id}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section
            Expanded(
              flex: 3,
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: category.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: category.isActive 
                            ? Colors.blue.withOpacity(0.1) 
                            : Colors.grey.withOpacity(0.1),
                        child: Icon(
                          Icons.category,
                          size: 48,
                          color: category.isActive ? Colors.blue : Colors.grey,
                        ),
                      ),
                    )
                  : Container(
                      color: category.isActive 
                          ? Colors.blue.withOpacity(0.1) 
                          : Colors.grey.withOpacity(0.1),
                      child: Icon(
                        Icons.category,
                        size: 48,
                        color: category.isActive ? Colors.blue : Colors.grey,
                      ),
                    ),
            ),
            // Info section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: category.isActive ? null : Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                context.push('/inventory/categories/${category.id}/edit').then((_) {
                                  _loadCategories();
                                });
                                break;
                              case 'toggle':
                                _toggleCategoryStatus(category);
                                break;
                              case 'delete':
                                _deleteCategory(category);
                                break;
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
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    category.isActive ? Icons.visibility_off : Icons.visibility, 
                                    size: 20
                                  ),
                                  const SizedBox(width: 8),
                                  Text(category.isActive ? 'Desactivar' : 'Activar'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red, size: 20),
                                  SizedBox(width: 8),
                                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          child: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    if (category.description != null && category.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          category.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: category.isActive ? Colors.grey[600] : Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: category.isActive ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        category.isActive ? 'Activa' : 'Inactiva',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
}