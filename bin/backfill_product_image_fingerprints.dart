library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import 'package:vinabike_erp/modules/inventory/services/product_image_fingerprint_service.dart';

const _defaultSupabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';
late final SupabaseClient supabase;
late final http.Client httpClient;

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);

  stdout.writeln('🧬 Product Image Fingerprint Backfill');
  stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (config.dryRun) {
    stdout.writeln('⚠️  DRY RUN MODE - No database changes will be made');
  }
  if (config.tenantId != null) {
    stdout.writeln('🏢 Tenant filter: ${config.tenantId}');
  } else {
    stdout.writeln('🏢 Tenant filter: all tenants');
  }
  stdout.writeln('📦 Page size: ${config.pageSize}');
  stdout.writeln('⚡ Concurrency: ${config.concurrency}');
  if (config.limit != null) {
    stdout.writeln('🔢 Limit: ${config.limit} products');
  }
  stdout.writeln('');

  final supabaseUrl = _getEnvValue('SUPABASE_URL') ?? _defaultSupabaseUrl;
  final serviceRoleKey = _getEnvValue('SUPABASE_SECRET_KEY') ?? '';

  if (serviceRoleKey.isEmpty) {
    stderr.writeln('❌ SUPABASE_SECRET_KEY is missing');
    exit(64);
  }

  supabase = SupabaseClient(supabaseUrl, serviceRoleKey);
  httpClient = http.Client();

  try {
    final products = await _fetchProductsNeedingBackfill(config);
    stdout.writeln(
        '📦 Found ${products.length} products needing fingerprint backfill');
    if (products.isEmpty) {
      stdout.writeln('✅ Nothing to do');
      return;
    }

    final stats = _RunStats();
    final failures = <String>[];

    for (var start = 0; start < products.length; start += config.concurrency) {
      final endExclusive =
          math.min(start + config.concurrency, products.length);
      final batch = products.sublist(start, endExclusive);
      final results = await Future.wait(batch.map((product) {
        return _processProduct(product, dryRun: config.dryRun);
      }));

      for (final result in results) {
        stats.processed++;
        switch (result.status) {
          case _ProcessStatus.success:
            stats.success++;
            break;
          case _ProcessStatus.skipped:
            stats.skipped++;
            break;
          case _ProcessStatus.failed:
            stats.failed++;
            failures.add(result.message);
            break;
        }
      }

      if (stats.processed == products.length || stats.processed % 50 == 0) {
        stdout.writeln(
          '   Progress ${stats.processed}/${products.length} '
          '(ok=${stats.success}, failed=${stats.failed}, skipped=${stats.skipped})',
        );
      }
    }

    stdout.writeln('');
    stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    stdout.writeln('📊 SUMMARY');
    stdout.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    stdout.writeln('   Processed: ${stats.processed}');
    stdout.writeln('   ✅ Success: ${stats.success}');
    stdout.writeln('   ⏭️  Skipped: ${stats.skipped}');
    stdout.writeln('   ❌ Failed: ${stats.failed}');

    if (failures.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('⚠️ Sample failures:');
      for (final failure in failures.take(20)) {
        stdout.writeln('   $failure');
      }
      if (failures.length > 20) {
        stdout.writeln('   ... ${failures.length - 20} more');
      }
    }

    if (stats.failed > 0) {
      exitCode = 2;
    }
  } finally {
    httpClient.close();
  }
}

Future<List<_BackfillProduct>> _fetchProductsNeedingBackfill(
  _Config config,
) async {
  final products = <_BackfillProduct>[];
  var offset = 0;
  final targetCount = config.limit;

  while (true) {
    dynamic query = supabase
        .from('products')
        .select(
            'id, tenant_id, sku, name, image_url, image_url_optimized, image_fingerprint')
        .isFilter('image_fingerprint', null)
        .or('image_url.not.is.null,image_url_optimized.not.is.null');

    if (config.tenantId != null) {
      query = query.eq('tenant_id', config.tenantId!);
    }

    query = query.order('id').range(offset, offset + config.pageSize - 1);

    final rows = await query;
    final list = (rows as List)
        .map((row) =>
            _BackfillProduct.fromJson(Map<String, dynamic>.from(row as Map)))
        .where((product) => product.hasAnyImageUrl)
        .toList();

    if (list.isEmpty) {
      break;
    }

    for (final product in list) {
      products.add(product);
      if (targetCount != null && products.length >= targetCount) {
        return products;
      }
    }

    if (list.length < config.pageSize) {
      break;
    }

    offset += config.pageSize;
  }

  return products;
}

Future<_ProcessResult> _processProduct(
  _BackfillProduct product, {
  required bool dryRun,
}) async {
  final urls = product.preferredImageUrls;
  if (urls.isEmpty) {
    return _ProcessResult.skipped(
      '${product.tenantId}|${product.sku}|no image url after filtering',
    );
  }

  List<int>? imageBytes;
  String? sourceUrl;

  for (final url in urls) {
    final downloadedBytes = await _downloadImage(url);
    if (downloadedBytes != null) {
      imageBytes = downloadedBytes;
      sourceUrl = url;
      break;
    }
  }

  if (imageBytes == null || sourceUrl == null) {
    return _ProcessResult.failed(
      '${product.tenantId}|${product.sku}|download failed for ${urls.join(' or ')}',
    );
  }

  final fingerprint = ProductImageFingerprintService.computeStorageJson(
    Uint8List.fromList(imageBytes),
  );
  if (fingerprint == null) {
    return _ProcessResult.failed(
      '${product.tenantId}|${product.sku}|decode/fingerprint failed from $sourceUrl',
    );
  }

  if (!dryRun) {
    await supabase
        .from('products')
        .update({'image_fingerprint': fingerprint})
        .eq('id', product.id)
        .eq('tenant_id', product.tenantId)
        .isFilter('image_fingerprint', null);
  }

  return _ProcessResult.success(
    '${product.tenantId}|${product.sku}|backfilled from $sourceUrl',
  );
}

Future<List<int>?> _downloadImage(String url) async {
  try {
    final response = await httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      return response.bodyBytes;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _getEnvValue(String key) {
  final envValue = Platform.environment[key];
  if (envValue != null && envValue.isNotEmpty) {
    return envValue;
  }

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    return null;
  }

  for (final line in envFile.readAsLinesSync()) {
    if (!line.startsWith('$key=')) {
      continue;
    }
    return line.substring(key.length + 1).trim();
  }

  return null;
}

_Config _parseArgs(List<String> args) {
  String? tenantId;
  int? limit;
  var dryRun = false;
  var pageSize = 200;
  var concurrency = 12;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    switch (arg) {
      case '--dry-run':
        dryRun = true;
        break;
      case '--tenant-id':
        tenantId = _nextArgValue(args, ++index, '--tenant-id');
        break;
      case '--limit':
        limit = int.parse(_nextArgValue(args, ++index, '--limit'));
        break;
      case '--page-size':
        pageSize = int.parse(_nextArgValue(args, ++index, '--page-size'));
        break;
      case '--concurrency':
        concurrency = int.parse(_nextArgValue(args, ++index, '--concurrency'));
        break;
      case '--help':
        stdout.writeln(
          'Usage: dart run bin/backfill_product_image_fingerprints.dart '
          '[--dry-run] [--tenant-id UUID] [--limit N] [--page-size N] [--concurrency N]',
        );
        exit(0);
      default:
        throw ArgumentError('Unknown argument: $arg');
    }
  }

  if (pageSize <= 0) {
    throw ArgumentError('--page-size must be > 0');
  }
  if (concurrency <= 0) {
    throw ArgumentError('--concurrency must be > 0');
  }
  if (limit != null && limit <= 0) {
    throw ArgumentError('--limit must be > 0');
  }

  return _Config(
    dryRun: dryRun,
    tenantId: tenantId,
    limit: limit,
    pageSize: pageSize,
    concurrency: concurrency,
  );
}

String _nextArgValue(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw ArgumentError('Missing value for $flag');
  }
  return args[index];
}

class _Config {
  const _Config({
    required this.dryRun,
    required this.tenantId,
    required this.limit,
    required this.pageSize,
    required this.concurrency,
  });

  final bool dryRun;
  final String? tenantId;
  final int? limit;
  final int pageSize;
  final int concurrency;
}

class _BackfillProduct {
  const _BackfillProduct({
    required this.id,
    required this.tenantId,
    required this.sku,
    required this.name,
    required this.imageUrl,
    required this.imageUrlOptimized,
  });

  factory _BackfillProduct.fromJson(Map<String, dynamic> json) {
    return _BackfillProduct(
      id: (json['id'] ?? '').toString(),
      tenantId: (json['tenant_id'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      imageUrl: json['image_url']?.toString(),
      imageUrlOptimized: json['image_url_optimized']?.toString(),
    );
  }

  final String id;
  final String tenantId;
  final String sku;
  final String name;
  final String? imageUrl;
  final String? imageUrlOptimized;

  bool get hasAnyImageUrl => preferredImageUrls.isNotEmpty;

  List<String> get preferredImageUrls {
    final candidates = <String>[];
    final optimized = imageUrlOptimized?.trim();
    final original = imageUrl?.trim();

    if (optimized != null && optimized.isNotEmpty) {
      candidates.add(optimized);
    }
    if (original != null && original.isNotEmpty && original != optimized) {
      candidates.add(original);
    }

    return candidates;
  }
}

class _RunStats {
  int processed = 0;
  int success = 0;
  int skipped = 0;
  int failed = 0;
}

enum _ProcessStatus { success, skipped, failed }

class _ProcessResult {
  const _ProcessResult(this.status, this.message);

  factory _ProcessResult.success(String message) {
    return _ProcessResult(_ProcessStatus.success, message);
  }

  factory _ProcessResult.skipped(String message) {
    return _ProcessResult(_ProcessStatus.skipped, message);
  }

  factory _ProcessResult.failed(String message) {
    return _ProcessResult(_ProcessStatus.failed, message);
  }

  final _ProcessStatus status;
  final String message;
}
