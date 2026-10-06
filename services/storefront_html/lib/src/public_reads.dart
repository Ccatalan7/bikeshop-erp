import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/models/public_product_identity_columns.dart';

import 'storefront_config.dart';

/// What every page reads first: the shell (`get_public_storefront_shell_v1`)
/// and the payment methods the store can confirm, at the same time.
typedef ShellReads = ({Map<String, dynamic> shell, Object? payments});

/// A product page: the shell and the page read
/// (`get_public_product_page_v2`, by SKU or by id), in one round trip.
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
    this.services = false,
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

  /// `/servicios`: the workshop's services instead of the products.
  final bool services;
}

/// The listing (`get_public_products_faceted_v2`), its rows completed like
/// the Flutter catalog completes them (`publicProductIdentityColumns` and the
/// `product_brands` rows of their brands), the smaller copies of their card
/// photos (`get_public_image_thumbnails_v1`), its filters with the
/// per-category counts (`get_public_product_facets_v2`) and the option names
/// (`get_public_spec_option_labels_v1`). The facets read takes longest and
/// runs beside the others.
typedef CatalogReads = ({
  List<Object?> products,
  List<Object?> brandRows,
  List<Object?> thumbnails,
  List<Object?> facets,
  List<Object?> optionLabels,
});

/// The shell and the store's information pages ([publicPolicySlugs]) that
/// are published, each with its visible blocks (`website_pages` and
/// `website_blocks`, as the Flutter store reads them), in one round trip.
typedef PolicyPagesReads = ({
  Map<String, dynamic> shell,
  Object? payments,
  List<Object?> pages,
});

/// `/contacto`: the shell and the published `contacto` page, `null` when it
/// is not published (Flutter then shows «Contacto no disponible»).
typedef ContactPageReads = ({
  Map<String, dynamic> shell,
  Object? payments,
  Map<String, dynamic>? page,
});

/// The home: the shell, the published page with `is_home` and its visible
/// blocks, and the products its product blocks pick by hand, completed like
/// a catalog listing (only those in stock, as Flutter's block asks).
typedef HomePageReads = ({
  Map<String, dynamic> shell,
  Object? payments,
  Map<String, dynamic>? page,
  List<Object?> products,
  List<Object?> brandRows,
  List<Object?> thumbnails,
});

/// The saved cart's products by id, in stock or not (Flutter's
/// `restorePublicStoreCartForTenant` asks `get_public_products` with
/// `p_only_in_stock: false`), completed like a listing and with the tax rate
/// checkout needs (`get_public_product_tax_classifications`): without it the
/// cart blocks payment instead of inventing IVA, as Flutter does.
typedef CartReads = ({
  List<Object?> products,
  List<Object?> brandRows,
  List<Object?> thumbnails,
});

abstract interface class PublicReads {
  Future<ShellReads> shell();

  /// The products of the visitor's saved cart, by id.
  Future<CartReads> cartProducts(List<String> productIds);

  /// By [sku], or by [productId] for a product without one (its canonical
  /// route is `/productos/<uuid>`).
  Future<ProductPageReads> productPage({String? sku, String? productId});
  Future<CatalogReads> catalog(CatalogRequest request);

  /// A published product's row by id, for the old `/productos/<uuid>` links.
  Future<Map<String, dynamic>?> productById(String id);

  /// The product an old URL path points to (`product_url_aliases`), if any.
  Future<String?> productIdForAlias(String path);

  Future<PolicyPagesReads> policyPages();

  Future<ContactPageReads> contactPage();

  /// [productIds] reads the products the page's blocks pick (a function of
  /// the page, so it runs after it).
  Future<HomePageReads> homePage(
    List<String> Function(Map<String, dynamic> page) productIds,
  );
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
            // Supabase's edge drops a kept-alive connection after a short
            // quiet spell, and the next read on it fails with «Connection
            // reset by peer» (seen 2026-10-05 after ~40 s): close them first.
            ..idleTimeout = const Duration(seconds: 10));

  final StorefrontConfig config;
  final HttpClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<ShellReads> shell() async {
    final results = await Future.wait([_shell(), _payments()]);
    return (shell: results[0] as Map<String, dynamic>, payments: results[1]);
  }

  @override
  Future<ProductPageReads> productPage({String? sku, String? productId}) async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _rpc('get_public_product_page_v2', {
        'p_tenant_id': config.tenantId,
        'p_sku': ?sku,
        'p_product_id': ?productId,
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
  Future<PolicyPagesReads> policyPages() async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _select('website_pages', {
        'select':
            'id,slug,title,meta_title,meta_description,meta_keywords,'
            'og_image_url,is_published,'
            'website_blocks(id,block_type,block_data,is_visible,order_index)',
        'tenant_id': 'eq.${config.tenantId}',
        'is_published': 'eq.true',
        'slug': 'in.(${publicPolicySlugs.join(',')})',
        'website_blocks.tenant_id': 'eq.${config.tenantId}',
      }),
    ]);
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      pages: results[2] as List<Object?>,
    );
  }

  @override
  Future<ContactPageReads> contactPage() async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _select('website_pages', {
        'select':
            'id,slug,title,meta_title,meta_description,og_image_url,'
            'is_published',
        'tenant_id': 'eq.${config.tenantId}',
        'is_published': 'eq.true',
        'slug': 'eq.contacto',
      }),
    ]);
    final rows = results[2] as List<Object?>;
    final page = rows.isEmpty ? null : rows.first;
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      page: page is Map ? Map<String, dynamic>.from(page) : null,
    );
  }

  @override
  Future<CartReads> cartProducts(List<String> productIds) async {
    final ids = productIds.where(_uuid.hasMatch).toSet().toList();
    if (ids.isEmpty) {
      return (
        products: const <Object?>[],
        brandRows: const <Object?>[],
        thumbnails: const <Object?>[],
      );
    }
    final results = await Future.wait([
      _rpc('get_public_products', {
        'p_tenant_id': config.tenantId,
        'p_product_ids': ids,
        'p_only_in_stock': false,
        'p_sort_by': 'name',
        'p_limit': ids.length,
        'p_offset': 0,
      }),
      // A failed classification keeps the rows: the cart then blocks
      // payment, as Flutter's `_attachCheckoutTaxRates` does.
      _rpc('get_public_product_tax_classifications', {
        'p_tenant_id': config.tenantId,
        'p_product_ids': ids,
      }).catchError((Object error) {
        stderr.writeln('cart tax classification unavailable: $error');
        return const <Object?>[];
      }),
    ]);
    final rows = results[0] is List ? results[0] as List : const <Object?>[];
    final listing = await _completeRows(rows.cast<Object?>());
    final taxRates = <String, Object?>{
      for (final row in results[1] is List ? results[1] as List : const [])
        if (row is Map && row['id'] != null)
          row['id'].toString(): row['tax_rate'],
    };
    return (
      products: [
        for (final row in listing.rows)
          if (row is Map)
            {
              ...row,
              if (taxRates.containsKey(row['id']?.toString()))
                'tax_rate': taxRates[row['id'].toString()],
            },
      ],
      brandRows: listing.brands,
      thumbnails: listing.thumbnails,
    );
  }

  @override
  Future<HomePageReads> homePage(
    List<String> Function(Map<String, dynamic> page) productIds,
  ) async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _select('website_pages', {
        'select':
            'id,slug,title,meta_title,meta_description,meta_keywords,'
            'og_image_url,is_published,'
            'website_blocks(id,block_type,block_data,is_visible,order_index)',
        'tenant_id': 'eq.${config.tenantId}',
        'is_home': 'eq.true',
        'is_published': 'eq.true',
        'website_blocks.tenant_id': 'eq.${config.tenantId}',
        'limit': '1',
      }),
    ]);
    final pages = results[2] as List<Object?>;
    final page = pages.isNotEmpty && pages.first is Map
        ? Map<String, dynamic>.from(pages.first as Map)
        : null;
    final ids = page == null ? const <String>[] : productIds(page);
    var listing = (
      rows: const <Object?>[],
      brands: const <Object?>[],
      thumbnails: const <Object?>[],
    );
    if (ids.isNotEmpty) {
      final rows = await _rpc('get_public_products', {
        'p_tenant_id': config.tenantId,
        'p_product_ids': ids,
        'p_only_in_stock': true,
        'p_sort_by': 'name',
        'p_limit': ids.length,
        'p_offset': 0,
      });
      listing = await _completeRows(rows is List ? rows : const []);
    }
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      page: page,
      products: listing.rows,
      brandRows: listing.brands,
      thumbnails: listing.thumbnails,
    );
  }

  @override
  Future<CatalogReads> catalog(CatalogRequest request) async {
    final filters = {
      'p_tenant_id': config.tenantId,
      'p_category_ids': request.categoryIds,
      'p_search_term': request.searchQuery.isEmpty ? null : request.searchQuery,
      'p_product_type': request.services ? 'service' : 'product',
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
      _rpc('get_public_spec_option_labels_v1', {
        'p_tenant_id': config.tenantId,
      }),
    ]);
    final listing =
        results[0]!
            as ({
              List<Object?> rows,
              List<Object?> brands,
              List<Object?> thumbnails,
            });
    return (
      products: listing.rows,
      brandRows: listing.brands,
      thumbnails: listing.thumbnails,
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

  /// A listing's rows with their public identity columns, the brand rows
  /// their cards are named from and the smaller copies of their card photos.
  /// Like Flutter, a failed completion keeps the rows as the listing returned
  /// them; without copies a card shows the large photo.
  Future<({List<Object?> rows, List<Object?> brands, List<Object?> thumbnails})>
  _completeRows(List<Object?> rows) async {
    String ids(Iterable<Object?> values) => values
        .map((value) => value?.toString().trim() ?? '')
        .where(_uuid.hasMatch)
        .toSet()
        .join(',');
    final productIds = ids(rows.map((row) => row is Map ? row['id'] : null));
    if (productIds.isEmpty) {
      return (
        rows: rows,
        brands: const <Object?>[],
        thumbnails: const <Object?>[],
      );
    }
    final brandIds = ids(
      rows.map((row) => row is Map ? row['brand_id'] : null),
    );
    // The identity columns carry no photo: the card's is the listing row's.
    final photos = {
      for (final row in rows)
        if (row is Map)
          ...PublicCommerceProductProjection.fromJson(
            Map<String, dynamic>.from(row),
          ).imageUrls.take(1),
    }.toList();
    // Each layer falls back on its own, as in Flutter: a failed brand read
    // keeps the commercial titles, and the other way round.
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
      if (photos.isEmpty)
        Future.value(const <Object?>[])
      else
        layer(
          'thumbnails',
          _rpc('get_public_image_thumbnails_v1', {
            'p_tenant_id': config.tenantId,
            'p_urls': photos,
          }).then((value) => value is List ? value : const <Object?>[]),
        ),
    ]);
    final identity = {
      for (final row in completed[0])
        if (row is Map && row['id'] != null) row['id'].toString(): row,
    };
    return (
      rows: [
        for (final row in rows)
          if (row is Map)
            {...row, ...?identity[row['id']?.toString()]}
          else
            row,
      ],
      brands: completed[1],
      thumbnails: completed[2],
    );
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Every read here is idempotent, so one that fails on the connection
  /// itself (a kept-alive socket the other side already closed) is asked
  /// again once, on a fresh connection, before the visitor sees an error.
  Future<T> _retrying<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on HttpException {
      return read();
    } on SocketException {
      return read();
    }
  }

  Future<List<Object?>> _select(String table, Map<String, String> query) =>
      _retrying(() => _selectOnce(table, query));

  Future<List<Object?>> _selectOnce(
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
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
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

  Future<Object?> _rpc(String function, Map<String, Object?> body) =>
      _retrying(() => _rpcOnce(function, body));

  Future<Object?> _rpcOnce(String function, Map<String, Object?> body) async {
    final uri = Uri.parse('${config.supabaseUrl}/rest/v1/rpc/$function');
    final request = await _client.postUrl(uri).timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer ${config.publishableKey}')
      ..contentType = ContentType.json;
    request.write(
      jsonEncode({
        for (final entry in body.entries)
          if (entry.value != null) entry.key: entry.value,
      }),
    );
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
