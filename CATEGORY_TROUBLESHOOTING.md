# Common Issues & Solutions

## Issue: Categories not showing in dropdown

**Cause**: Categories might not be loaded or database might be empty.

**Solution**:
1. Check if categories exist in database
2. Run category initialization:
   ```dart
   final categoryService = CategoryService(databaseService);
   await categoryService.initializeDefaultCategories();
   ```

## Issue: Products showing null for category

**Cause**: Products haven't been migrated from enum to category IDs.

**Solution**:
1. Run the migration script:
   ```dart
   final migration = CategoryMigration(databaseService);
   await migration.migrate();
   ```

## Issue: Cannot delete category

**Error**: "No se puede eliminar la categoría porque está siendo utilizada por X producto(s)"

**Cause**: Products are still assigned to this category.

**Solution**:
1. Reassign products to a different category first
2. OR delete/deactivate the products
3. Then delete the category

## Issue: Expandable menu not showing

**Cause**: Missing import or widget not properly added to navigation.

**Solution**:
1. Ensure `expandable_menu_item.dart` is imported in `main_layout.dart`
2. Check that `ExpandableMenuItem` widget is used correctly

## Issue: Category form validation fails

**Cause**: Category name might be duplicate or empty.

**Solution**:
1. Ensure category name is unique
2. Name must be at least 2 characters
3. Check database constraints

## Issue: Navigation not expanding automatically

**Cause**: Route path doesn't match sub-item routes.

**Solution**:
1. Ensure routes use correct paths (e.g., `/inventory/categories`)
2. Check `currentLocation` is being passed correctly

## Compilation Errors After Migration

### Error: "The method 'getCategoryNames' isn't defined"

**Cause**: Old code still referencing removed helper methods.

**Solution**: 
- Remove references to `InventoryService.getCategoryNames()`
- Use category data from database instead

### Error: "The getter 'category' isn't defined for the type 'Product'"

**Cause**: Product model no longer has `category` enum field.

**Solution**:
- Use `categoryId` instead of `category`
- Use `categoryName` for display purposes
- Update any old code referencing `product.category`

### Error: Type 'ProductCategory' is not a subtype of type 'int'

**Cause**: Trying to assign enum value to categoryId field.

**Solution**:
- Pass category ID (integer) instead of enum value
- Update filter and search logic to use IDs

## Database Issues

### Foreign Key Constraint Violation

**Error**: "insert or update on table products violates foreign key constraint"

**Cause**: Trying to assign a category_id that doesn't exist.

**Solution**:
1. Ensure categories are created first
2. Use valid category IDs only
3. Run category initialization if needed

### Column Not Found: category_id

**Cause**: Database schema not updated.

**Solution**:
1. Run database migration to add `category_id` column
2. Ensure table structure matches schema in documentation

## Performance Tips

1. **Load categories once**: Cache categories in memory instead of fetching repeatedly
2. **Use JOINs**: Fetch category names with products in single query
3. **Index category_id**: Add database index for faster filtering
4. **Lazy loading**: Only load categories when navigation expands

## Migration Checklist

- [ ] Database tables created (categories)
- [ ] Products table updated with category_id column
- [ ] Migration script executed
- [ ] Default categories initialized
- [ ] Products migrated from enum to category IDs
- [ ] Routes added to app_router.dart
- [ ] Navigation updated with expandable menu
- [ ] All compilation errors resolved
- [ ] App tested end-to-end
