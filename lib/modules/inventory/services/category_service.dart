import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/category_models.dart' as models;

class CategoryService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService;

  CategoryService(this._db, this._tenantService);

  // Category operations
  Future<List<models.Category>> getCategories({
    String? searchTerm,
    bool? activeOnly,
  }) async {
    try {
      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.isNotEmpty) {
        // Search by name or description
        final nameResults =
            await _db.searchRecords('product_categories', 'name', searchTerm);
        final descResults =
            await _db.searchRecords('product_categories', 'description', searchTerm);

        // Combine and deduplicate results
        final Set<int> ids = {};
        data = [...nameResults, ...descResults]
            .where((item) => ids.add(item['id']))
            .toList();
      } else {
        data = await _db.select('product_categories');
      }

      List<models.Category> categories =
          data.map((json) => models.Category.fromJson(json)).toList();

      // Apply filters
      if (activeOnly == true) {
        categories = categories.where((c) => c.isActive).toList();
      }

      // Sort by full_path for hierarchical display
      categories.sort((a, b) => a.fullPath.compareTo(b.fullPath));

      return categories;
    } catch (e) {
      if (kDebugMode) print('Error fetching categories: $e');
      rethrow;
    }
  }

  Future<models.Category?> getCategoryById(String id) async {
    try {
      final data = await _db.selectById('product_categories', id);
      return data != null ? models.Category.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching category: $e');
      rethrow;
    }
  }

  Future<models.Category?> getCategoryByName(String name) async {
    try {
      final data = await _db.select('product_categories', where: 'name=${name}');
      return data.isNotEmpty ? models.Category.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching category by name: $e');
      rethrow;
    }
  }

  Future<models.Category> createCategory(models.Category category) async {
    try {
      // Check if full_path already exists
      final existingCategory = await getCategoryByPath(category.fullPath);
      if (existingCategory != null) {
        throw Exception('Ya existe una categoría con esta ruta: ${category.fullPath}');
      }

      // Add tenant_id to category data
      final categoryData = _tenantService.addTenantId(category.toJson());
      final data = await _db.insert('product_categories', categoryData);
      return models.Category.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('Error creating category: $e');
      rethrow;
    }
  }

  Future<models.Category> updateCategory(models.Category category) async {
    try {
      if (category.id == null) {
        throw Exception('Category ID is required for update');
      }

      // Check if full_path already exists (excluding current category)
      final existingCategory = await getCategoryByPath(category.fullPath);
      if (existingCategory != null && existingCategory.id != category.id) {
        throw Exception('Ya existe una categoría con esta ruta: ${category.fullPath}');
      }

      final updatedCategory = category.copyWith(updatedAt: DateTime.now());
      await _db.update('product_categories', category.id!, updatedCategory.toJson());
      return updatedCategory;
    } catch (e) {
      if (kDebugMode) print('Error updating category: $e');
      rethrow;
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      // Check if category is in use by products
      final productsUsingCategory =
          await _db.select('products', where: 'category_id=$id');
      if (productsUsingCategory.isNotEmpty) {
        throw Exception(
            'No se puede eliminar la categoría porque está siendo utilizada por ${productsUsingCategory.length} producto(s)');
      }

      // Check if category has subcategories
      final subcategories = await getSubcategories(id);
      if (subcategories.isNotEmpty) {
        throw Exception(
            'No se puede eliminar la categoría porque tiene ${subcategories.length} subcategoría(s)');
      }

      await _db.delete('product_categories', id);
    } catch (e) {
      if (kDebugMode) print('Error deleting category: $e');
      rethrow;
    }
  }

  Future<void> toggleCategoryStatus(String id) async {
    try {
      final category = await getCategoryById(id);
      if (category == null) {
        throw Exception('Category not found');
      }

      final updatedCategory = category.copyWith(
        isActive: !category.isActive,
        updatedAt: DateTime.now(),
      );

      await updateCategory(updatedCategory);
    } catch (e) {
      if (kDebugMode) print('Error toggling category status: $e');
      rethrow;
    }
  }

  // Get category statistics
  Future<Map<String, dynamic>> getCategoryAnalytics() async {
    try {
      final categories = await getCategories();
      final totalCategories = categories.length;
      final activeCategories = categories.where((c) => c.isActive).length;

      // Get product count per category
      final categoryProductCounts = <String, int>{};
      for (final category in categories) {
        final products =
            await _db.select('products', where: 'category_id=${category.id}');
        categoryProductCounts[category.id!] = products.length;
      }

      return {
        'total_categories': totalCategories,
        'active_categories': activeCategories,
        'inactive_categories': totalCategories - activeCategories,
        'category_product_counts': categoryProductCounts,
      };
    } catch (e) {
      if (kDebugMode) print('Error getting category analytics: $e');
      return {};
    }
  }

  // Initialize default categories (migration helper)
  Future<void> initializeDefaultCategories() async {
    try {
      final existingCategories = await getCategories();
      if (existingCategories.isNotEmpty) {
        if (kDebugMode)
          print('Categories already exist, skipping initialization');
        return;
      }

      final defaultCategories = [
        models.Category(
            name: 'Bicicletas',
            fullPath: 'Bicicletas',
            description: 'Bicicletas completas de todos los tipos'),
        models.Category(
            name: 'Repuestos',
            fullPath: 'Repuestos',
            description: 'Piezas y componentes para bicicletas'),
        models.Category(
            name: 'Accesorios',
            fullPath: 'Accesorios',
            description: 'Accesorios y complementos para ciclistas'),
        models.Category(
            name: 'Ropa',
            fullPath: 'Ropa',
            description: 'Vestimenta y equipamiento para ciclistas'),
        models.Category(
            name: 'Herramientas',
            fullPath: 'Herramientas',
            description: 'Herramientas para mantenimiento y reparación'),
        models.Category(
            name: 'Mantenimiento',
            fullPath: 'Mantenimiento',
            description: 'Productos para mantenimiento y limpieza'),
        models.Category(
            name: 'Otros', 
            fullPath: 'Otros',
            description: 'Productos diversos no clasificados'),
      ];

      for (final category in defaultCategories) {
        await createCategory(category);
      }

      if (kDebugMode) print('Default categories initialized successfully');
    } catch (e) {
      if (kDebugMode) print('Error initializing default categories: $e');
      rethrow;
    }
  }

  // ============================================================================
  // HIERARCHICAL CATEGORY METHODS
  // ============================================================================

  /// Get root categories (level 0)
  Future<List<models.Category>> getRootCategories() async {
    try {
      final data = await _db.select(
        'product_categories',
        where: 'level=0',
        orderBy: 'sort_order, name',
      );
      return data.map((json) => models.Category.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching root categories: $e');
      rethrow;
    }
  }

  /// Get direct children of a category
  Future<List<models.Category>> getSubcategories(String parentId) async {
    try {
      final data = await _db.select(
        'product_categories',
        where: 'parent_id=$parentId',
        orderBy: 'sort_order, name',
      );
      return data.map((json) => models.Category.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching subcategories: $e');
      rethrow;
    }
  }

  /// Get category by full path
  Future<models.Category?> getCategoryByPath(String fullPath) async {
    try {
      final data = await _db.select(
        'product_categories',
        where: 'full_path=$fullPath',
      );
      return data.isNotEmpty ? models.Category.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching category by path: $e');
      rethrow;
    }
  }

  /// Build breadcrumbs from a category's full path
  List<models.CategoryBreadcrumb> buildBreadcrumbs(models.Category category) {
    final parts = category.breadcrumbs;
    final breadcrumbs = <models.CategoryBreadcrumb>[];

    // Add "All Categories" as root
    breadcrumbs.add(models.CategoryBreadcrumb(
      name: 'Todas las Categorías',
      categoryId: null,
      level: -1,
    ));

    // Add each level
    for (int i = 0; i < parts.length; i++) {
      breadcrumbs.add(models.CategoryBreadcrumb(
        name: parts[i],
        categoryId: category.id, // Will be resolved when navigating
        level: i,
      ));
    }

    return breadcrumbs;
  }

  /// Import categories from Excel format (single column with slashes)
  /// Format: ["Accesorios", "Accesorios / Asientos", "Accesorios / Asientos / Tija"]
  Future<Map<String, dynamic>> importCategoriesFromList(List<String> paths) async {
    try {
      int created = 0;
      int skipped = 0;
      int errors = 0;
      final Map<String, String> pathToIdMap = {}; // full_path -> id

      // Sort paths by depth (fewer slashes first)
      final sortedPaths = paths.toList()..sort((a, b) {
        final aDepth = '/'.allMatches(a).length;
        final bDepth = '/'.allMatches(b).length;
        return aDepth.compareTo(bDepth);
      });

      for (final fullPath in sortedPaths) {
        try {
          final trimmedPath = fullPath.trim();
          if (trimmedPath.isEmpty) {
            skipped++;
            continue;
          }

          // Check if already exists
          final existing = await getCategoryByPath(trimmedPath);
          if (existing != null) {
            pathToIdMap[trimmedPath] = existing.id!;
            skipped++;
            continue;
          }

          // Parse path
          final parts = trimmedPath.split('/').map((s) => s.trim()).toList();
          final level = parts.length - 1;
          final name = parts.last;

          // Find parent ID (if not root)
          String? parentId;
          if (level > 0) {
            final parentPath = parts.sublist(0, parts.length - 1).join(' / ');
            parentId = pathToIdMap[parentPath];
            if (parentId == null) {
              // Parent doesn't exist yet, try to find it
              final parentCategory = await getCategoryByPath(parentPath);
              if (parentCategory != null) {
                parentId = parentCategory.id;
                pathToIdMap[parentPath] = parentId!;
              } else {
                throw Exception('Parent category not found: $parentPath');
              }
            }
          }

          // Create category
          final category = models.Category(
            name: name,
            fullPath: trimmedPath,
            parentId: parentId,
            level: level,
          );

          final createdCategory = await createCategory(category);
          pathToIdMap[trimmedPath] = createdCategory.id!;
          created++;

        } catch (e) {
          if (kDebugMode) print('Error importing category "$fullPath": $e');
          errors++;
        }
      }

      return {
        'created': created,
        'skipped': skipped,
        'errors': errors,
        'total': paths.length,
      };
    } catch (e) {
      if (kDebugMode) print('Error importing categories: $e');
      rethrow;
    }
  }
}
