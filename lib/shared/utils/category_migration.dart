import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../services/tenant_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/models/category_models.dart'
    as inventory_models;

/// Migration helper to convert from enum-based categories to database-driven categories
class CategoryMigration {
  final DatabaseService _db;
  final TenantService _tenantService;
  final CategoryService _categoryService;

  CategoryMigration(this._db, this._tenantService) 
    : _categoryService = CategoryService(_db, _tenantService);

  /// Run the complete migration process
  Future<void> migrate() async {
    try {
      if (kDebugMode) print('Starting category migration...');

      // Step 1: Check if categories table exists and has data
      final existingCategories = await _categoryService.getCategories();
      if (existingCategories.isNotEmpty) {
        if (kDebugMode) print('Categories already exist. Skipping migration.');
        return;
      }

      // Step 2: Create default categories from enum values
      await _createDefaultCategories();

      // Step 3: Migrate product category enum values to category IDs
      await _migrateProductCategories();

      if (kDebugMode) print('Category migration completed successfully!');
    } catch (e) {
      if (kDebugMode) print('Error during category migration: $e');
      rethrow;
    }
  }

  /// Create default categories based on the old enum values
  Future<void> _createDefaultCategories() async {
    final defaultCategories = [
      inventory_models.Category(
        name: 'Bicicletas',
        fullPath: 'Bicicletas',
        description:
            'Bicicletas completas de todos los tipos (MTB, ruta, urbana, etc.)',
      ),
      inventory_models.Category(
        name: 'Repuestos',
        fullPath: 'Repuestos',
        description:
            'Piezas y componentes para bicicletas (frenos, cambios, etc.)',
      ),
      inventory_models.Category(
        name: 'Accesorios',
        fullPath: 'Accesorios',
        description:
            'Accesorios y complementos para ciclistas (luces, timbre, candados)',
      ),
      inventory_models.Category(
        name: 'Ropa',
        fullPath: 'Ropa',
        description:
            'Vestimenta y equipamiento para ciclistas (cascos, guantes, jersey)',
      ),
      inventory_models.Category(
        name: 'Herramientas',
        fullPath: 'Herramientas',
        description:
            'Herramientas para mantenimiento y reparación de bicicletas',
      ),
      inventory_models.Category(
        name: 'Mantenimiento',
        fullPath: 'Mantenimiento',
        description: 'Productos para mantenimiento y limpieza de bicicletas',
      ),
      inventory_models.Category(
        name: 'Otros',
        fullPath: 'Otros',
        description: 'Productos diversos no clasificados en otras categorías',
      ),
    ];

    for (final category in defaultCategories) {
      try {
        await _categoryService.createCategory(category);
        if (kDebugMode) print('Created category: ${category.name}');
      } catch (e) {
        if (kDebugMode) print('Error creating category ${category.name}: $e');
      }
    }
  }

  /// Migrate existing products from enum-based categories to category IDs
  Future<void> _migrateProductCategories() async {
    try {
      // Get all categories
      final categories = await _categoryService.getCategories();

      // Create a map of old enum names to new category IDs
      final categoryMap = <String, String>{
        'bicycle': _findCategoryId(categories, 'Bicicletas'),
        'parts': _findCategoryId(categories, 'Repuestos'),
        'accessories': _findCategoryId(categories, 'Accesorios'),
        'clothing': _findCategoryId(categories, 'Ropa'),
        'tools': _findCategoryId(categories, 'Herramientas'),
        'maintenance': _findCategoryId(categories, 'Mantenimiento'),
        'other': _findCategoryId(categories, 'Otros'),
      };

      // Get all products
      final products = await _db.select('products');

      if (products.isEmpty) {
        if (kDebugMode) print('No products to migrate.');
        return;
      }

      // Update each product with the new category ID
      int migratedCount = 0;
      for (final product in products) {
        try {
          final oldCategory = product['category'] as String?;
          if (oldCategory != null && categoryMap.containsKey(oldCategory)) {
            final categoryId = categoryMap[oldCategory];

            // Update the product with the new category_id
            await _db.update('products', product['id'].toString(), {
              'category_id': categoryId,
              'updated_at': DateTime.now().toIso8601String(),
            });

            migratedCount++;
          }
        } catch (e) {
          if (kDebugMode) print('Error migrating product ${product['id']}: $e');
        }
      }

      if (kDebugMode)
        print('Migrated $migratedCount products to new category system.');
    } catch (e) {
      if (kDebugMode) print('Error migrating product categories: $e');
    }
  }

  /// Helper to find category ID by name
  String _findCategoryId(
      List<inventory_models.Category> categories, String name) {
    try {
      return categories.firstWhere((cat) => cat.name == name).id!;
    } catch (e) {
      if (kDebugMode) print('Category not found: $name');
      // Return ID of "Otros" category as fallback
      return categories.firstWhere((cat) => cat.name == 'Otros').id!;
    }
  }

  /// Check if migration is needed
  Future<bool> needsMigration() async {
    try {
      final categories = await _categoryService.getCategories();
      return categories.isEmpty;
    } catch (e) {
      return true;
    }
  }
}
