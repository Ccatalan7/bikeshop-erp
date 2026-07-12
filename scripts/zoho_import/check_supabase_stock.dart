import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  final anonKey = Platform.environment['ZOHO_IMPORT_SUPABASE_ANON_KEY'] ?? '';
  if (anonKey.isEmpty) {
    stderr.writeln(
      'Missing required ZOHO_IMPORT_SUPABASE_ANON_KEY environment variable.',
    );
    exit(64);
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://jhizdkvxumzipjmplmwo.supabase.co',
    anonKey: anonKey,
  );

  // Load test SKUs
  final testFile = File('test_import_products.json');
  final testProducts = jsonDecode(await testFile.readAsString()) as List;
  final skus = testProducts.map((p) => p['sku'] as String).toList();

  print('🔍 Checking ${skus.length} SKUs in Supabase...\n');

  // Query products (using anon key - may be filtered by RLS)
  final response = await Supabase.instance.client
      .from('products')
      .select('sku, name, stock_quantity, price')
      .inFilter('sku', skus);

  final supabaseProducts = response as List;

  print('📊 Found ${supabaseProducts.length} matching products in Supabase\n');

  // Compare stocks
  print('Stock Comparison (Supabase → Zoho):');
  print('─' * 80);

  for (final zohoItem in testProducts) {
    final sku = zohoItem['sku'];
    final zohoStock = (zohoItem['available_stock'] as num).toInt();
    final zohoName = zohoItem['name'] as String;

    final supabaseItem = supabaseProducts
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['sku'] == sku, orElse: () => <String, dynamic>{});

    if (supabaseItem.isEmpty) {
      print('❌ SKU: $sku - NOT FOUND in Supabase');
      final displayName =
          zohoName.length > 50 ? '${zohoName.substring(0, 50)}...' : zohoName;
      print('   Zoho: $displayName (Stock: $zohoStock)');
    } else {
      final currentStock = supabaseItem['stock_quantity'] as int;
      final diff = zohoStock - currentStock;
      final symbol = diff > 0
          ? '📈'
          : diff < 0
              ? '📉'
              : '➡️';

      print('$symbol SKU: $sku');
      print('   Current: $currentStock → New: $zohoStock (Δ $diff)');
      final name = supabaseItem['name'] as String;
      final displayName =
          name.length > 50 ? '${name.substring(0, 50)}...' : name;
      print('   Name: $displayName');
    }
    print('');
  }

  exit(0);
}
