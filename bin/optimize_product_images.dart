/// Image Optimization Migration Script
///
/// This script downloads all product images, converts them to optimized WebP format,
/// uploads the optimized versions, and updates the database with the new URLs.
///
/// Usage: dart run bin/optimize_product_images.dart [--dry-run] [--limit N]
///
/// Options:
///   --dry-run   Show what would be done without making changes
///   --limit N   Only process N products (for testing)
///
/// IMPORTANT: Requires SUPABASE_SECRET_KEY environment variable to bypass RLS
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

// Configuration
const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';
const storageBucket = 'vinabike-assets';

// Optimization settings
const maxWidth = 1200; // Max width for optimized images
const webpQuality = 80; // WebP quality (0-100)

late final SupabaseClient supabase;

String _getServiceRoleKey() {
  // Try environment variable first
  final envKey = Platform.environment['SUPABASE_SECRET_KEY'];
  if (envKey != null && envKey.isNotEmpty) {
    return envKey;
  }
  
  // Try to read from .env file
  final envFile = File('.env');
  if (envFile.existsSync()) {
    final lines = envFile.readAsLinesSync();
    for (final line in lines) {
      if (line.startsWith('SUPABASE_SECRET_KEY=')) {
        return line.substring('SUPABASE_SECRET_KEY='.length).trim();
      }
    }
  }
  
  throw Exception(
    'SUPABASE_SECRET_KEY not found!\n'
    'Set it as environment variable or add to .env file.\n'
    'This key is required to bypass RLS for storage uploads.'
  );
}

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final limitIndex = args.indexOf('--limit');
  final limit = limitIndex >= 0 && limitIndex + 1 < args.length
      ? int.tryParse(args[limitIndex + 1])
      : null;

  print('🖼️  Product Image Optimization Script');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (dryRun) print('⚠️  DRY RUN MODE - No changes will be made');
  if (limit != null) print('📊 Limit: $limit products');
  print('');

  // Initialize Supabase with service role key (bypasses RLS)
  final serviceRoleKey = _getServiceRoleKey();
  print('🔑 Using service role key for storage access');
  supabase = SupabaseClient(supabaseUrl, serviceRoleKey);

  // Fetch products that need optimization
  print('📋 Fetching products with images but no optimized version...');

  final baseQuery = supabase
      .from('products')
      .select('id, name, sku, image_url, image_url_optimized')
      .not('image_url', 'is', null)
      .isFilter('image_url_optimized', null);

  final response = limit != null 
      ? await baseQuery.limit(limit)
      : await baseQuery;
  final products = response as List;

  print('📦 Found ${products.length} products to optimize');
  print('');

  int processed = 0;
  int success = 0;
  int failed = 0;
  int skipped = 0;

  for (final product in products) {
    processed++;
    final id = product['id'] as String;
    final name = product['name'] as String;
    final sku = product['sku'] as String;
    final imageUrl = product['image_url'] as String?;

    print(
        '[$processed/${products.length}] Processing: $sku - ${name.substring(0, name.length > 40 ? 40 : name.length)}...');

    if (imageUrl == null || imageUrl.isEmpty) {
      print('   ⏭️  Skipped: No image URL');
      skipped++;
      continue;
    }

    try {
      // Download original image
      final imageBytes = await _downloadImage(imageUrl);
      if (imageBytes == null) {
        print('   ❌ Failed: Could not download image');
        failed++;
        continue;
      }
      print(
          '   📥 Downloaded: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');

      // Decode and optimize image
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        print('   ❌ Failed: Could not decode image');
        failed++;
        continue;
      }

      // Resize if larger than max width
      img.Image optimized = originalImage;
      if (originalImage.width > maxWidth) {
        optimized = img.copyResize(originalImage, width: maxWidth);
        print(
            '   📐 Resized: ${originalImage.width}x${originalImage.height} → ${optimized.width}x${optimized.height}');
      }

      // Encode to WebP
      final webpBytes = img.encodeJpg(optimized, quality: webpQuality);
      // Note: Using JPEG as fallback since 'image' package WebP support varies
      // For production, consider using a dedicated WebP encoder

      final reduction =
          ((1 - webpBytes.length / imageBytes.length) * 100).toStringAsFixed(1);
      print(
          '   🗜️  Optimized: ${(webpBytes.length / 1024).toStringAsFixed(1)} KB ($reduction% reduction)');

      if (dryRun) {
        print('   ✅ Would upload and update database (dry run)');
        success++;
        continue;
      }

      // Generate optimized path
      final originalPath = _extractPathFromUrl(imageUrl);
      final optimizedPath = _generateOptimizedPath(originalPath);

      // Upload optimized image
      await supabase.storage.from(storageBucket).uploadBinary(
            optimizedPath,
            Uint8List.fromList(webpBytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      // Get public URL
      final optimizedUrl =
          supabase.storage.from(storageBucket).getPublicUrl(optimizedPath);
      print('   📤 Uploaded: $optimizedPath');

      // Update database
      await supabase
          .from('products')
          .update({'image_url_optimized': optimizedUrl}).eq('id', id);

      print('   ✅ Database updated');
      success++;
    } catch (e) {
      print('   ❌ Error: $e');
      failed++;
    }
  }

  // Summary
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 SUMMARY');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('   Total processed: $processed');
  print('   ✅ Success: $success');
  print('   ❌ Failed: $failed');
  print('   ⏭️  Skipped: $skipped');
  print('');

  if (dryRun) {
    print('💡 This was a dry run. Run without --dry-run to apply changes.');
  }
}

Future<Uint8List?> _downloadImage(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    return null;
  } catch (e) {
    return null;
  }
}

String _extractPathFromUrl(String url) {
  // Extract path from Supabase storage URL
  // URL format: https://xxx.supabase.co/storage/v1/object/public/bucket/path/to/file.jpg
  final uri = Uri.parse(url);
  final pathSegments = uri.pathSegments;

  // Find the bucket name and get everything after it
  final bucketIndex = pathSegments.indexOf(storageBucket);
  if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
    return pathSegments.sublist(bucketIndex + 1).join('/');
  }

  // Fallback: use last part of URL
  return pathSegments.last;
}

String _generateOptimizedPath(String originalPath) {
  // Add _optimized suffix before extension
  final lastDot = originalPath.lastIndexOf('.');
  if (lastDot > 0) {
    return '${originalPath.substring(0, lastDot)}_optimized.jpg';
  }
  return '${originalPath}_optimized.jpg';
}
