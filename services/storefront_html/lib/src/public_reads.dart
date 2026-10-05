import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vinabike_public_core/public_store/models/public_product_identity_columns.dart';

import 'storefront_config.dart';

/// What every page reads first: the shell (`get_public_storefront_shell_v1`)
/// and the payment methods the store can confirm, at the same time.
typedef ShellReads = ({Map<String, dynamic> shell, Object? payments});

/// A product page: the shell and the page read
/// (`20261004180000_public_storefront_page_reads.sql`), in one round trip.
typedef ProductPageReads = ({
  Map<String, dynamic> shell,
  Object? payments,
  Map<String, dynamic>? page,
});

/// One catalog listing, already scoped to its categories.
class CatalogRequest {
  const CatalogRequest({
    required this.categoryIds,
    required this.searchQuery,
    required this.brandIds,
    required this.specFilters,
    required this.minPrice,
    required this.maxPrice,
    required this.onlyInStock,
    required this.sortBy,
    required this.limit,
    required this.offset,
  });

  final List<String>? categoryIds;
  final String searchQuery;
  final List<String> brandIds;
  final Map<String, List<String>>? specFilters;
  final double? minPrice;
  final double? maxPrice;

  /// The visitor's availability filter; the site's stock policy is applied by
  /// the listing read itself.
  final bool onlyInStock;
  final String sortBy;
  final int limit;
  final int offset;
}

/// The listing (`get_public_products_faceted_v2`), its rows completed like
/// the Flutter catalog completes them (`publicProductIdentityColumns` and the
/// `product_brands` rows of their brands), its filters with the per-category
/// counts (`get_public_product_facets_v2`) and the option names
/// (`get_public_spec_option_labels_v1`). The facets read takes longest and
/// runs beside the other three.
typedef CatalogReads = ({
  List<Object?> products,
  List<Object?> brandRows,
  List<Object?> facets,
  List<Object?> optionLabels,
});

abstract interface class PublicReads {
  Future<ShellReads> shell();
  Future<ProductPageReads> productPage(String sku);
  Future<CatalogReads> catalog(CatalogRequest request);

  /// A published product's row by id, for the old `/productos/<uuid>` links.
  Future<Map<String, dynamic>?> productById(String id);

  /// The product an old URL path points to (`product_url_aliases`), if any.
  Future<String?> productIdForAlias(String path);
}

class PublicReadException implements Exception {
  PublicReadException(this.message);
  final String message;
  @override
  String toString() => 'PublicReadException: $message';
}

/// Calls the public Supabase functions with the publishable key, as `anon`.
class SupabasePublicReads implements PublicReads {
  SupabasePublicReads(this.config, {HttpClient? client})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..idleTimeout = const Duration(seconds: 60));

  final StorefrontConfig config;
  final HttpClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<ShellReads> shell() async {
    final results = await Future.wait([_shell(), _payments()]);
    return (shell: results[0] as Map<String, dynamic>, payments: results[1]);
  }

  @override
  Future<ProductPageReads> productPage(String sku) async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _rpc('get_public_product_page_v1', {
        'p_tenant_id': config.tenantId,
        'p_sku': sku,
      }),
    ]);
    final page = results[2];
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      page: page is Map ? Map<String, dynamic>.from(page) : null,
    );
  }

  @override
  Future<CatalogReads> catalog(CatalogRequest request) async {
    final filters = {
      'p_tenant_id': config.tenantId,
      'p_category_ids': request.categoryIds,
      'p_search_term': request.searchQuery.isEmpty ? null : request.searchQuery,
      'p_product_type': 'product',
      'p_only_in_stock': request.onlyInStock,
      'p_brand_ids': request.brandIds.isEmpty ? null : request.brandIds,
      'p_spec_filters': request.specFilters,
      'p_min_price': request.minPrice,
      'p_max_price': request.maxPrice,
    };
    List<Object?> list(Object? value) => value is List ? value : const [];
    final results = await Future.wait<Object?>([
      _rpc('get_public_products_faceted_v2', {
        ...filters,
        'p_sort_by': request.sortBy,
        'p_limit': request.limit,
        'p_offset': request.offset,
      }).then((rows) => _completeRows(list(rows))),
      _rpc('get_public_product_facets_v2', filters),
      _rpc('get_public_spec_option_labels_v1', {'p_tenant_id': config.tenantId}),
    ]);
    final listing = results[0]! as ({List<Object?> rows, List<Object?> brands});
    return (
      products: listing.rows,
      brandRows: listing.brands,
      facets: list(results[1]),
      optionLabels: list(results[2]),
    );
  }

  @override
  Future<Map<String, dynamic>?> productById(String id) async {
    final rows = await _rpc('get_public_products', {
      'p_tenant_id': config.tenantId,
      'p_product_ids': [id],
      'p_only_in_stock': false,
      'p_limit': 1,
    });
    if (rows is List && rows.isNotEmpty && rows.first is Map) {
      return Map<String, dynamic>.from(rows.first as Map);
    }
    return null;
  }

  @override
  Future<String?> productIdForAlias(String path) async {
    final id = await _rpc('resolve_public_product_url_alias', {
      'p_tenant_id': config.tenantId,
      'p_alias_path': path,
    });
    final text = id?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// A listing's rows with their public identity columns, and the brand rows
  /// their cards are named from. Like Flutter, a failed completion keeps the
  /// rows as the listing returned them.
  Future<({List<Object?> rows, List<Object?> brands})> _completeRows(
    List<Object?> rows,
  ) async {
    String ids(Iterable<Object?> values) => values
        .map((value) => value?.toString().trim() ?? '')
        .where(_uuid.hasMatch)
        .toSet()
        .join(',');
    final productIds = ids(rows.map((row) => row is Map ? row['id'] : null));
    if (productIds.isEmpty) return (rows: rows, brands: const <Object?>[]);
    final brandIds = ids(rows.map((row) => row is Map ? row['brand_id'] : null));
    // Two layers, each falling back on its own, as in Flutter: a failed brand
    // read keeps the commercial titles, and the other way round.
    Future<List<Object?>> layer(String name, Future<List<Object?>> read) =>
        read.catchError((Object error) {
          stderr.writeln('listing $name unavailable: $error');
          return const <Object?>[];
        });
    final completed = await Future.wait([
      layer(
        'identity',
        _select('products', {
          'select': publicProductIdentityColumns,
          'tenant_id': 'eq.${config.tenantId}',
          'id': 'in.($productIds)',
        }),
      ),
      if (brandIds.isEmpty)
        Future.value(const <Object?>[])
      else
        layer(
          'brands',
          _select('product_brands', {
            'select': 'id,name,tenant_id,is_active',
            'id': 'in.($brandIds)',
            'is_active': 'eq.true',
          }),
        ),
    ]);
    final identity = {
      for (final row in completed[0])
        if (row is Map && row['id'] != null) row['id'].toString(): row,
    };
    return (
      rows: [
        for (final row in rows)
          if (row is Map) {...row, ...?identity[row['id']?.toString()]} else row,
      ],
      brands: completed[1],
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<List<Object?>> _select(
    String table,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(
      '${config.supabaseUrl}/rest/v1/$table',
    ).replace(queryParameters: query);
    final request = await _client.getUrl(uri).timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer ${config.publishableKey}');
    final response = await request.close().timeout(_timeout);
    final text = await response.transform(utf8.decoder).join().timeout(_timeout);
    if (response.statusCode >= 300) {
      throw PublicReadException('$table → ${response.statusCode}');
    }
    final decoded = jsonDecode(text);
    return decoded is List ? decoded : const [];
  }

  Future<Map<String, dynamic>> _shell() async {
    final shell = await _rpc('get_public_storefront_shell_v1', {
      'p_tenant_id': config.tenantId,
    });
    if (shell is! Map) throw PublicReadException('shell is not an object');
    return Map<String, dynamic>.from(shell);
  }

  /// The footer names no payment method when this read fails: unknown is not
  /// an answer, the same rule the Flutter footer follows.
  Future<Object?> _payments() async {
    try {
      return await _rpc('get_public_checkout_capabilities', {
        'p_tenant_id': config.tenantId,
      });
    } on Object catch (error) {
      stderr.writeln('payment capabilities unavailable: $error');
      return null;
    }
  }

  Future<Object?> _rpc(String function, Map<String, Object?> body) async {
    final uri = Uri.parse('${config.supabaseUrl}/rest/v1/rpc/$function');
    final request = await _client.postUrl(uri).timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer ${config.publishableKey}')
      ..contentType = ContentType.json;
    request.write(jsonEncode({
      for (final entry in body.entries)
        if (entry.value != null) entry.key: entry.value,
    }));
    final response = await request.close().timeout(_timeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
    if (response.statusCode >= 300) {
      throw PublicReadException('$function → ${response.statusCode}');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}
