/// Website Block Image Optimization Migration Script
///
/// This script finds all website block images, optimizes them,
/// and updates the block_data with the new URLs.
///
/// Usage: dart run bin/optimize_website_images.dart [--dry-run] [--limit N]

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

// Configuration
const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';
const storageBucket = 'vinabike-assets';

// Optimization settings
const maxWidth = 1200;
const jpegQuality = 80;

late final SupabaseClient supabase;

String _getServiceRoleKey() {
  final envKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (envKey != null && envKey.isNotEmpty) return envKey;
  
  final envFile = File('.env');
  if (envFile.existsSync()) {
    final lines = envFile.readAsLinesSync();
    for (final line in lines) {
      if (line.startsWith('SUPABASE_SERVICE_ROLE_KEY=')) {
        return line.substring('SUPABASE_SERVICE_ROLE_KEY='.length).trim();
      }
    }
  }
  
  throw Exception('SUPABASE_SERVICE_ROLE_KEY not found!');
}

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final limitIndex = args.indexOf('--limit');
  final limit = limitIndex >= 0 && limitIndex + 1 < args.length
      ? int.tryParse(args[limitIndex + 1])
      : null;

  print('🌐 Website Block Image Optimization Script');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (dryRun) print('⚠️  DRY RUN MODE - No changes will be made');
  if (limit != null) print('📊 Limit: $limit blocks');
  print('');

  final serviceRoleKey = _getServiceRoleKey();
  print('🔑 Using service role key');
  supabase = SupabaseClient(supabaseUrl, serviceRoleKey);

  // Fetch all website blocks with image fields
  print('📋 Fetching website blocks with images...');
  
  final response = await supabase
      .from('website_blocks')
      .select('id, block_type, block_data')
      .order('created_at');

  final blocks = List<Map<String, dynamic>>.from(response as List);
  print('📦 Found ${blocks.length} total blocks');

  // Image field patterns in block_data
  final imageFields = [
    'backgroundImage',
    'imageUrl',
    'image',
    'logoUrl',
    'posterImage',
    'items', // For repeater fields with images
    'slides', // For carousel slides
    'partners', // For partner logos
    'brands', // For brand logos
    'categories', // For category grid
    'features', // For features with images
    'testimonials', // For testimonials with avatars
    'team', // For team members
  ];

  int processed = 0;
  int success = 0;
  int failed = 0;
  int skipped = 0;

  for (final block in blocks) {
    if (limit != null && processed >= limit) break;

    final blockId = block['id'];
    final blockType = block['block_type'];
    final blockData = block['block_data'] as Map<String, dynamic>? ?? {};

    // Find and process image URLs in this block
    final updates = <String, dynamic>{};
    bool hasChanges = false;

    for (final field in imageFields) {
      if (!blockData.containsKey(field)) continue;

      final value = blockData[field];

      if (value is String && _isImageUrl(value) && !_isAlreadyOptimized(value)) {
        processed++;
        print('\n[$processed] Processing $blockType.$field...');
        print('   📍 URL: ${_truncateUrl(value)}');

        if (dryRun) {
          print('   ⏭️  Would optimize (dry run)');
          success++;
        } else {
          final optimizedUrl = await _optimizeImage(value);
          if (optimizedUrl != null) {
            updates[field] = optimizedUrl;
            hasChanges = true;
            success++;
            print('   ✅ Optimized');
          } else {
            failed++;
            print('   ❌ Failed');
          }
        }
      } else if (value is List) {
        // Handle arrays (slides, items, partners, brands)
        final updatedList = <Map<String, dynamic>>[];
        bool listChanged = false;

        for (final item in value) {
          if (item is Map<String, dynamic>) {
            final updatedItem = Map<String, dynamic>.from(item);
            
            // Check common image fields in list items
            for (final imgField in ['image', 'imageUrl', 'logoUrl', 'backgroundImage', 'logo']) {
              if (item.containsKey(imgField)) {
                final imgUrl = item[imgField];
                if (imgUrl is String && _isImageUrl(imgUrl) && !_isAlreadyOptimized(imgUrl)) {
                  processed++;
                  print('\n[$processed] Processing $blockType.$field[].$imgField...');
                  print('   📍 URL: ${_truncateUrl(imgUrl)}');

                  if (dryRun) {
                    print('   ⏭️  Would optimize (dry run)');
                    success++;
                  } else {
                    final optimizedUrl = await _optimizeImage(imgUrl);
                    if (optimizedUrl != null) {
                      updatedItem[imgField] = optimizedUrl;
                      listChanged = true;
                      success++;
                      print('   ✅ Optimized');
                    } else {
                      failed++;
                      print('   ❌ Failed');
                    }
                  }
                }
              }
            }
            updatedList.add(updatedItem);
          }
        }

        if (listChanged) {
          updates[field] = updatedList;
          hasChanges = true;
        }
      }
    }

    // Update the block if we made changes
    if (hasChanges && !dryRun) {
      try {
        final newBlockData = Map<String, dynamic>.from(blockData);
        newBlockData.addAll(updates);
        
        await supabase
            .from('website_blocks')
            .update({'block_data': newBlockData})
            .eq('id', blockId);
        print('   💾 Block updated');
      } catch (e) {
        print('   ❌ Failed to update block: $e');
      }
    }
  }

  print('\n');
  print('═══════════════════════════════════════════');
  print('📊 SUMMARY');
  print('───────────────────────────────────────────');
  print('   Total processed: $processed');
  print('   ✅ Success: $success');
  print('   ❌ Failed: $failed');
  print('   ⏭️  Skipped: $skipped');
  print('═══════════════════════════════════════════');
}

bool _isImageUrl(String url) {
  final lower = url.toLowerCase();
  return (lower.contains('supabase') || lower.startsWith('http')) &&
      (lower.contains('.jpg') ||
          lower.contains('.jpeg') ||
          lower.contains('.png') ||
          lower.contains('.webp') ||
          lower.contains('.gif'));
}

bool _isAlreadyOptimized(String url) {
  return url.contains('_optimized') || url.contains('/optimized/');
}

String _truncateUrl(String url) {
  if (url.length <= 60) return url;
  return '${url.substring(0, 30)}...${url.substring(url.length - 27)}';
}

Future<String?> _optimizeImage(String imageUrl) async {
  try {
    // Download original image
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      print('   ⚠️  Download failed: ${response.statusCode}');
      return null;
    }

    final originalBytes = response.bodyBytes;
    final originalKB = (originalBytes.length / 1024).toStringAsFixed(1);
    print('   📥 Downloaded: $originalKB KB');

    // Decode image
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      print('   ⚠️  Could not decode image');
      return null;
    }

    // Resize if needed
    img.Image optimized = originalImage;
    if (originalImage.width > maxWidth) {
      optimized = img.copyResize(originalImage, width: maxWidth);
      print('   📐 Resized: ${originalImage.width}x${originalImage.height} → ${optimized.width}x${optimized.height}');
    }

    // Encode as JPEG
    final optimizedBytes = Uint8List.fromList(img.encodeJpg(optimized, quality: jpegQuality));
    final optimizedKB = (optimizedBytes.length / 1024).toStringAsFixed(1);
    final reduction = ((1 - optimizedBytes.length / originalBytes.length) * 100).toStringAsFixed(1);
    print('   📦 Optimized: $optimizedKB KB ($reduction% reduction)');

    // Skip if optimization made it bigger
    if (optimizedBytes.length >= originalBytes.length) {
      print('   ⏭️  Skipping (optimization not beneficial)');
      return null;
    }

    // Generate filename
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'website_${timestamp}_optimized.jpg';
    final objectPath = 'website/blocks/optimized/$fileName';

    // Upload
    await supabase.storage.from(storageBucket).uploadBinary(
      objectPath,
      optimizedBytes,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: true,
        contentType: 'image/jpeg',
      ),
    );

    final publicUrl = supabase.storage.from(storageBucket).getPublicUrl(objectPath);
    print('   🚀 Uploaded: ${_truncateUrl(publicUrl)}');

    return publicUrl;
  } catch (e) {
    print('   ❌ Error: $e');
    return null;
  }
}
