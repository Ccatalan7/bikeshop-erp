import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../models/category_models.dart';
import '../services/category_service.dart';

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
                    'Categorías',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: CheckboxListTile(
                    title: const Text('Solo Inactivas'),
                    value: _showInactiveOnly,
                    onChanged: (value) => _onInactiveToggle(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Stats
          if (!_isLoading && _categories.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildStatItem('Total', _categories.length.toString()),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    'Activas', 
                    _categories.where((c) => c.isActive).length.toString(),
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    'Inactivas', 
                    _categories.where((c) => !c.isActive).length.toString(),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Categories List
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _buildCategoriesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesList() {
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

    return RefreshIndicator(
      onRefresh: _loadCategories,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: _filteredCategories.length,
        itemBuilder: (context, index) {
          final category = _filteredCategories[index];
          return _buildCategoryCard(category);
        },
      ),
    );
  }

  Widget _buildCategoryCard(Category category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.isActive 
              ? Colors.blue.withOpacity(0.1) 
              : Colors.grey.withOpacity(0.1),
          child: Icon(
            Icons.category,
            color: category.isActive ? Colors.blue : Colors.grey,
          ),
        ),
        title: Text(
          category.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: category.isActive ? null : Colors.grey,
          ),
        ),
        subtitle: category.description != null
            ? Text(
                category.description!,
                style: TextStyle(
                  color: category.isActive ? Colors.grey[600] : Colors.grey,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: category.isActive ? Colors.green : Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                category.isActive ? 'Activa' : 'Inactiva',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            
            // Actions menu
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
              child: const Icon(Icons.more_vert),
            ),
          ],
        ),
        onTap: () {
          context.push('/inventory/categories/${category.id}/edit').then((_) {
            _loadCategories();
          });
        },
      ),
    );
  }
}