/// Centralized storage configuration for Supabase buckets and folder paths.
class StorageConfig {
  const StorageConfig._();

  /// Default Supabase Storage bucket where media assets are uploaded.
  ///
  /// Update this value to match the bucket you create in the Supabase dashboard.
  static const String defaultBucket = 'vinabike-assets';
}

class StorageFolders {
  const StorageFolders._();

  /// Primary product hero images.
  static const String productMain = 'inventory/products/main';

  /// Additional gallery images linked to a product.
  static const String productGallery = 'inventory/products/gallery';

  /// Category thumbnail images.
  static const String categories = 'inventory/categories';

  /// Customer avatars inside the CRM module.
  static const String customers = 'crm/customers';

  /// Supplier logos and documents for the purchases module.
  static const String suppliers = 'purchases/suppliers';

  /// Shared placeholder for marketing assets when needed.
  static const String marketingAssets = 'marketing/assets';
}
