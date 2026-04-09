import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to import product images from Zoho Inventory
class ZohoImageImportService {
  final String zohoApiKey;
  final String zohoOrgId;
  final String zohoRegion;

  ZohoImageImportService({
    required this.zohoApiKey,
    required this.zohoOrgId,
    this.zohoRegion = 'com',
  });

  String get baseUrl => 'https://www.zohoapis.$zohoRegion/inventory/v1';

  /// Fetch all products from Zoho Inventory
  Future<List<Map<String, dynamic>>> fetchZohoProducts({
    required Function(String) onProgress,
  }) async {
    onProgress('📦 Fetching products from Zoho Inventory...');
    
    final List<Map<String, dynamic>> allProducts = [];
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final response = await http.get(
        Uri.parse('$baseUrl/items?organization_id=$zohoOrgId&page=$page&per_page=200'),
        headers: {
          'Authorization': 'Zoho-oauthtoken $zohoApiKey',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch Zoho products: ${response.body}');
      }

      final data = json.decode(response.body);
      final items = data['items'] as List? ?? [];
      
      allProducts.addAll(items.map((item) => item as Map<String, dynamic>));
      
      hasMore = data['page_context']?['has_more_page'] ?? false;
      page++;
      
      onProgress('   Fetched page $page (${allProducts.length} products so far)');
    }

    onProgress('✅ Total Zoho products fetched: ${allProducts.length}');
    return allProducts;
  }

  /// Download image from Zoho and upload to Supabase
  Future<String?> downloadAndUploadImage({
    required String imageUrl,
    required String productId,
    required String tenantId,
    required SupabaseClient supabase,
    required Function(String) onProgress,
  }) async {
    try {
      // Download image from Zoho
      onProgress('   ⬇️  Downloading image from Zoho...');
      final imageResponse = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'Authorization': 'Zoho-oauthtoken $zohoApiKey',
        },
      );

      if (imageResponse.statusCode != 200) {
        onProgress('   ❌ Failed to download image: ${imageResponse.statusCode}');
        return null;
      }

      // Determine file extension
      final contentType = imageResponse.headers['content-type'] ?? 'image/jpeg';
      final extension = contentType.contains('png') ? 'png' : 'jpg';
      
      // Generate file path
      final fileName = 'product-images/$tenantId/$productId/main.$extension';

      // Upload to Supabase Storage
      onProgress('   ⬆️  Uploading to Supabase Storage...');
      await supabase.storage.from('product-images').uploadBinary(
            fileName,
            imageResponse.bodyBytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl = supabase.storage.from('product-images').getPublicUrl(fileName);
      
      onProgress('   ✅ Image uploaded successfully');
      return publicUrl;
    } catch (e) {
      onProgress('   ❌ Error uploading image: $e');
      return null;
    }
  }

  /// Main import process
  Future<Map<String, int>> importImages({
    required String tenantId,
    required SupabaseClient supabase,
    required Function(String) onProgress,
  }) async {
    onProgress('\n🚀 Starting Zoho Image Import...\n');

    try {
      // 1. Fetch products from Zoho
      final zohoProducts = await fetchZohoProducts(onProgress: onProgress);

      // 2. Fetch local products
      onProgress('\n📦 Fetching local products from database...');
      final localProducts = await supabase
          .from('products')
          .select('id, sku, name, image_url')
          .eq('tenant_id', tenantId);

      onProgress('✅ Total local products: ${localProducts.length}');

      // 3. Create SKU lookup map for Zoho products
      final Map<String, Map<String, dynamic>> zohoProductsBySku = {};
      for (final product in zohoProducts) {
        final sku = product['sku']?.toString().toUpperCase();
        if (sku != null && sku.isNotEmpty) {
          zohoProductsBySku[sku] = product;
        }
      }

      onProgress('\n🔍 Matching products by SKU...\n');

      int matchedCount = 0;
      int successCount = 0;
      int failedCount = 0;
      int skippedCount = 0;

      for (final localProduct in localProducts) {
        final localSku = localProduct['sku']?.toString().toUpperCase();
        final localName = localProduct['name'];
        final localId = localProduct['id'];
        final existingImageUrl = localProduct['image_url'];

        if (localSku == null || localSku.isEmpty) {
          onProgress('⚠️  Skipping "$localName" - No SKU');
          skippedCount++;
          continue;
        }

        final zohoProduct = zohoProductsBySku[localSku];
        
        if (zohoProduct == null) {
          onProgress('⚠️  No match in Zoho for SKU: $localSku ($localName)');
          continue;
        }

        matchedCount++;
        final zohoName = zohoProduct['name'];
        onProgress('\n✅ MATCH: $localSku');
        onProgress('   Local:  $localName');
        onProgress('   Zoho:   $zohoName');

        // Check if product has image in Zoho
        final imageUrl = zohoProduct['image_url']?.toString();
        
        if (imageUrl == null || imageUrl.isEmpty) {
          onProgress('   ⚠️  No image in Zoho');
          skippedCount++;
          continue;
        }

        // Check if already has image
        if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
          onProgress('   ℹ️  Already has image, skipping');
          skippedCount++;
          continue;
        }

        // Download and upload image
        final uploadedUrl = await downloadAndUploadImage(
          imageUrl: imageUrl,
          productId: localId,
          tenantId: tenantId,
          supabase: supabase,
          onProgress: onProgress,
        );

        if (uploadedUrl != null) {
          // Update product with image URL
          await supabase.from('products').update({
            'image_url': uploadedUrl,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', localId);
          
          successCount++;
          onProgress('   ✅ Product updated with image URL');
        } else {
          failedCount++;
        }

        // Add delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }

      onProgress('\n${'=' * 60}');
      onProgress('📊 IMPORT SUMMARY');
      onProgress('=' * 60);
      onProgress('Total local products:    ${localProducts.length}');
      onProgress('Matched by SKU:          $matchedCount');
      onProgress('Successfully imported:   $successCount');
      onProgress('Failed:                  $failedCount');
      onProgress('Skipped:                 $skippedCount');
      onProgress('=' * 60 + '\n');

      return {
        'total': localProducts.length,
        'matched': matchedCount,
        'success': successCount,
        'failed': failedCount,
        'skipped': skippedCount,
      };
    } catch (e, stackTrace) {
      onProgress('\n❌ Import failed: $e');
      onProgress('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
