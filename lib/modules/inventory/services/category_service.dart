import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../models/category_models.dart' as models;

class CategoryService extends ChangeNotifier {
  final DatabaseService _db;

  CategoryService(this._db);

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
            await _db.searchRecords('categories', 'name', searchTerm);
        final descResults =
            await _db.searchRecords('categories', 'description', searchTerm);

        // Combine and deduplicate results
        final Set<int> ids = {};
        data = [...nameResults, ...descResults]
            .where((item) => ids.add(item['id']))
            .toList();
      } else {
        data = await _db.select('categories');
      }

      List<models.Category> categories =
          data.map((json) => models.Category.fromJson(json)).toList();

      // Apply filters
      if (activeOnly == true) {
        categories = categories.where((c) => c.isActive).toList();
      }

      // Sort by name
      categories.sort((a, b) => a.name.compareTo(b.name));

      return categories;
    } catch (e) {
      if (kDebugMode) print('Error fetching categories: $e');
      rethrow;
    }
  }

  Future<models.Category?> getCategoryById(String id) async {
    try {
      final data = await _db.selectById('categories', id);
      return data != null ? models.Category.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching category: $e');
      rethrow;
    }
  }

  Future<models.Category?> getCategoryByName(String name) async {
    try {
      final data = await _db.select('categories', where: 'name=${name}');
      return data.isNotEmpty ? models.Category.fromJson(data.first) : null;
    } catch (e) {
      if (kDebugMode) print('Error fetching category by name: $e');
      rethrow;
    }
  }

  Future<models.Category> createCategory(models.Category category) async {
    try {
      // Check if name already exists
      final existingCategory = await getCategoryByName(category.name);
      if (existingCategory != null) {
        throw Exception('Ya existe una categoría con este nombre');
      }

      final data = await _db.insert('categories', category.toJson());
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

      // Check if name already exists (excluding current category)
      final existingCategory = await getCategoryByName(category.name);
      if (existingCategory != null && existingCategory.id != category.id) {
        throw Exception('Ya existe una categoría con este nombre');
      }

      final updatedCategory = category.copyWith(updatedAt: DateTime.now());
      await _db.update('categories', category.id!, updatedCategory.toJson());
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

      await _db.delete('categories', id);
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
            description: 'Bicicletas completas de todos los tipos'),
        models.Category(
            name: 'Repuestos',
            description: 'Piezas y componentes para bicicletas'),
        models.Category(
            name: 'Accesorios',
            description: 'Accesorios y complementos para ciclistas'),
        models.Category(
            name: 'Ropa',
            description: 'Vestimenta y equipamiento para ciclistas'),
        models.Category(
            name: 'Herramientas',
            description: 'Herramientas para mantenimiento y reparación'),
        models.Category(
            name: 'Mantenimiento',
            description: 'Productos para mantenimiento y limpieza'),
        models.Category(
            name: 'Otros', description: 'Productos diversos no clasificados'),
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
}
