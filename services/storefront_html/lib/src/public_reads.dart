import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vinabike_public_core/public_store/models/customer_portal_snapshot.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/models/public_product_identity_columns.dart';

import 'block_product_picks.dart';
import 'database_gate.dart';
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
    this.facets = true,
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

  /// Whether to read the filters too (facets and option names); a price
  /// list reads only its rows.
  final bool facets;
}

/// The listing (`get_public_products_faceted_v2`), its rows completed like
/// the Flutter catalog completes them (`publicProductIdentityColumns` and the
/// `product_brands` rows of their brands), the smaller copies of their card
/// photos (`get_public_image_thumbnails_v1`), its filters with the
/// per-category counts (`get_public_product_facets_v2`) and the option names
/// (`get_public_spec_option_labels_v1`). The facets read takes longest and
/// runs beside the others; `facets` is `null` when it failed, and the page
/// keeps its products.
typedef CatalogReads = ({
  List<Object?> products,
  List<Object?> brandRows,
  List<Object?> thumbnails,
  List<Object?>? facets,
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

  /// The ids of each list the page's blocks ask for, in its order, by
  /// [BlockProductList.key]; their rows are among [products].
  Map<String, List<String>> lists,
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

/// The customer's account as the portal reads it, with the customer's own
/// session (`CustomerAccountService`: the idempotent
/// `provision_current_public_store_customer`, then `customers` by
/// `auth_user_id` and tenant, their addresses (the principal first, then the
/// newest), orders with their lines,
/// active bikes with their brand and model rows, and jobs). [profile] is null
/// when the session is not a customer of this store. [jobBikes] are the
/// bikes the jobs name, read apart as Flutter reads them; [productImages] the
/// order lines' products (`customerOrderImageColumns`, public); [jobFiles]
/// each job file's link to show it, resolved with the same session (only
/// when asked: the profile and addresses pages show none).
typedef CustomerPortalReads = ({
  Map<String, dynamic> shell,
  Map<String, dynamic>? profile,
  List<Object?> addresses,
  List<Object?> orders,
  List<Object?> bikes,
  List<Object?> jobs,
  List<Object?> jobBikes,
  List<Object?> productImages,
  Map<String, String> jobFiles,
});

/// What Supabase Auth answered a customer's request: its [status] and, when
/// it refused, its error code and message (the request is never kept).
typedef CustomerAuthAnswer = ({int status, String? code, String message});

/// The Supabase Auth calls the portal makes with the customer's session.
enum CustomerAuthCall {
  /// `PUT /auth/v1/user` with `{password, nonce?}`.
  updatePassword,

  /// `GET /auth/v1/reauthenticate`: mails the customer a one-time code.
  reauthenticate,

  /// `POST /auth/v1/logout?scope=others`: closes every other session.
  signOutOthers,

  /// `POST /auth/v1/logout?scope=global`: closes every session, this one
  /// too (an e-mail link's, once it set the password).
  signOutEverywhere,
}

/// Storage did not sign a private object for the session's user:
/// [statusCode] is what Storage named (`404` for an object it does not show
/// this user, as Flutter's `StorageException` reads it), or the HTTP status.
class StorageRefused implements Exception {
  const StorageRefused(this.statusCode);
  final String statusCode;
  @override
  String toString() => 'StorageRefused($statusCode)';
}

/// Supabase refused the customer's session (expired or not valid): the page
/// renews it and asks again, or shows the way in.
class CustomerSessionRefused implements Exception {
  const CustomerSessionRefused();
  @override
  String toString() => 'CustomerSessionRefused';
}

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

  /// [picks] says what of the catalog the page's blocks show (a function of
  /// the page, so it runs after it): the products they pick and the lists
  /// they ask for.
  Future<HomePageReads> homePage(PagePicker picks);

  /// A published editor page by its slug (`/pagina/<slug>`, Flutter's
  /// `DynamicWebsitePage`), read as [homePage] reads the home.
  Future<HomePageReads> websitePage(String slug, PagePicker picks);

  /// An order through its access token
  /// (`get_public_online_order_by_access_token`, the read Flutter's order
  /// page makes), for its summary PDF; null when the token opens nothing.
  Future<Object?> publicOrder(String accessToken);

  /// Whether the session [accessToken] may edit this store's site: the rule
  /// saving the site follows (`can_edit_tenant_settings`), asked as that
  /// person. Throws [CustomerSessionRefused] when Supabase does not accept
  /// the token. The token is only sent to Supabase.
  Future<bool> canEditSite(String accessToken);

  /// What a draft of the editor needs besides its own blocks and settings:
  /// the shell, the payment methods and what [page]'s blocks show of the
  /// catalog, read as [homePage] reads them.
  Future<HomePageReads> draftPage(Map<String, dynamic> page, PagePicker picks);

  /// The portal's reads with the customer's [accessToken]; throws
  /// [CustomerSessionRefused] when Supabase does not accept it. The token is
  /// only sent to Supabase: never kept nor written to a log. [files] resolves
  /// the jobs' files.
  Future<CustomerPortalReads> customerPortal(
    String accessToken, {
    bool files = true,
  });

  /// The session's customer row in this store, or null (no provisioning:
  /// the page that sends a write has read the account already).
  Future<Map<String, dynamic>?> customerProfile(String accessToken);

  /// What entering does once Supabase Auth gave a session: the store's
  /// customer behind it, created first when it is missing (the idempotent
  /// `provision_current_public_store_customer`, as
  /// `CustomerAccountService._loadCustomerData`), or null when the session
  /// cannot be one (the function refuses it).
  Future<Map<String, dynamic>?> customerEnter(String accessToken);

  /// A write of the customer's own [table] (`customers` or
  /// `customer_addresses`) with their session: row security decides, and
  /// [filters] must name the store (`tenant_id`). [method] is `PATCH`,
  /// `POST` or `DELETE`; true when a row was written.
  Future<bool> customerWrite(
    String accessToken, {
    required String method,
    required String table,
    Map<String, String> filters = const {},
    Map<String, Object?>? body,
  });

  /// [call] to Supabase Auth with the customer's session; throws
  /// [CustomerSessionRefused] when Auth does not accept it. Neither the
  /// session nor [body] (a password) is kept or written to a log.
  Future<CustomerAuthAnswer> customerAuth(
    String accessToken,
    CustomerAuthCall call, {
    Map<String, Object?>? body,
  });

  /// A link to open one of a job's files now
  /// (`WorkshopAssetService.resolve`), or null when the session may not.
  Future<String?> customerJobFile(String accessToken, String reference);

  /// A signed link to a private Storage object, asked as the session's own
  /// user, so Storage's row security decides (`createSignedUrl`). Throws
  /// [StorageRefused] when it does not sign.
  Future<String> customerSignedObject(
    String accessToken,
    String bucket,
    String path, {
    required int expiresIn,
  });

  /// The bytes behind a signed Storage link, never from a cache; null when
  /// Storage does not answer 200 or the object is larger than [maxBytes].
  Future<List<int>?> signedObjectBytes(String url, {required int maxBytes});
}

/// The claims of a customer's session token, read without checking its
/// signature: only to name what Supabase will check when the same token is
/// sent (`user_metadata` of the account), never to decide who it is.
Map<String, Object?> customerSessionClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return const {};
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map ? Map<String, Object?>.from(payload) : const {};
  } on FormatException {
    return const {};
  }
}

class PublicReadException implements Exception {
  PublicReadException(this.message, {this.statusCode, this.busy = false});
  final String message;

  /// What Supabase answered, when it answered.
  final int? statusCode;

  /// No turn at the database in time ([DatabaseGate]).
  final bool busy;

  /// Worth asking again in a moment: the database was busy or Supabase
  /// failed on its side. A refusal (4xx) says something about the request.
  bool get retryable =>
      busy ||
      switch (statusCode) {
        null => false,
        408 || 429 => true,
        final code => code >= 500,
      };
  @override
  String toString() => 'PublicReadException: $message';
}

/// Calls the public Supabase functions with the publishable key, as `anon`.
class SupabasePublicReads implements PublicReads {
  SupabasePublicReads(this.config, {HttpClient? client, DatabaseGate? gate})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            // Supabase's edge drops a kept-alive connection after a short
            // quiet spell, and the next read on it fails with «Connection
            // reset by peer» (seen 2026-10-05 after ~40 s): close them first.
            ..idleTimeout = const Duration(seconds: 10)),
      _gate = gate ?? DatabaseGate();

  final StorefrontConfig config;
  final HttpClient _client;

  /// Every round trip to the database, the visitor's own included, takes
  /// its turn here.
  final DatabaseGate _gate;

  static const _timeout = Duration(seconds: 15);

  /// A read that failed but whose page can go on without it.
  static final _unavailable = Object();

  /// The answers of public reads already on their way, by function and
  /// arguments: a burst on one page (a crawler asked `/productos` a dozen
  /// times in a few seconds) asks Supabase once. Shared as text, so no two
  /// requests hold the same decoded rows.
  final _inFlight = <String, Future<String>>{};

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
  Future<Object?> publicOrder(String accessToken) =>
      // Not retried: each read counts a use of the token.
      _rpcOnce('get_public_online_order_by_access_token', {
        'p_token': accessToken,
      });

  @override
  Future<HomePageReads> homePage(PagePicker picks) =>
      _editorPage({'is_home': 'eq.true'}, picks);

  @override
  Future<HomePageReads> websitePage(String slug, PagePicker picks) =>
      _editorPage({'slug': 'eq.$slug'}, picks);

  /// One published editor page ([which] picks it) with its blocks, and what
  /// its blocks show of the catalog.
  Future<HomePageReads> _editorPage(
    Map<String, String> which,
    PagePicker picks,
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
        ...which,
        'is_published': 'eq.true',
        'website_blocks.tenant_id': 'eq.${config.tenantId}',
        'limit': '1',
      }),
    ]);
    final pages = results[2] as List<Object?>;
    final page = pages.isNotEmpty && pages.first is Map
        ? Map<String, dynamic>.from(pages.first as Map)
        : null;
    final listing = await _pageProducts(
      page == null ? const PagePicks() : picks(page),
    );
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      page: page,
      products: listing.rows,
      brandRows: listing.brands,
      thumbnails: listing.thumbnails,
      lists: listing.lists,
    );
  }

  /// What a page's blocks show of the catalog, in stock and public and
  /// completed like a listing: the products they pick by hand
  /// (`get_public_products` by id) and each list they ask for
  /// ([BlockProductList]), read together.
  Future<
    ({
      List<Object?> rows,
      List<Object?> brands,
      List<Object?> thumbnails,
      Map<String, List<String>> lists,
    })
  >
  _pageProducts(PagePicks picks) async {
    if (picks.isEmpty) {
      return (
        rows: const <Object?>[],
        brands: const <Object?>[],
        thumbnails: const <Object?>[],
        lists: const <String, List<String>>{},
      );
    }
    // A list that cannot be read leaves its block empty, as Flutter's
    // products block does when its read fails, instead of the whole page.
    Future<Object?> optional(String what, Future<Object?> read) async {
      try {
        return await read;
      } on Exception catch (error) {
        stderr.writeln('page products read failed ($what): $error');
        return const <Object?>[];
      }
    }

    final reads = await Future.wait([
      if (picks.ids.isEmpty)
        Future<Object?>.value(const <Object?>[])
      else
        optional(
          'picked',
          _rpc('get_public_products', {
            'p_tenant_id': config.tenantId,
            'p_product_ids': picks.ids,
            'p_only_in_stock': true,
            'p_sort_by': 'name',
            'p_limit': picks.ids.length,
            'p_offset': 0,
          }),
        ),
      for (final list in picks.lists)
        optional(
          list.key,
          list.source == 'featured'
              ? _rpc('get_public_featured_products', {
                  'p_tenant_id': config.tenantId,
                  'p_limit': list.limit,
                })
              : _rpc('get_public_products', {
                  'p_tenant_id': config.tenantId,
                  if (list.categoryId case final id?) 'p_category_ids': [id],
                  'p_only_in_stock': true,
                  'p_sort_by': list.source == 'newest' ? 'newest' : 'name',
                  'p_limit': list.limit,
                  'p_offset': 0,
                }),
        ),
    ]);
    List<Object?> rowsOf(Object? read) =>
        read is List ? read.cast<Object?>() : const <Object?>[];
    final byId = <String, Object?>{};
    void keep(List<Object?> rows) {
      for (final row in rows) {
        if (row is Map && row['id'] != null) {
          byId.putIfAbsent(row['id'].toString(), () => row);
        }
      }
    }

    keep(rowsOf(reads.first));
    final lists = <String, List<String>>{};
    for (final (index, list) in picks.lists.indexed) {
      final rows = rowsOf(reads[index + 1]);
      keep(rows);
      lists[list.key] = [
        for (final row in rows)
          if (row is Map && row['id'] != null) row['id'].toString(),
      ];
    }
    final listing = await _completeRows(byId.values.toList(growable: false));
    return (
      rows: listing.rows,
      brands: listing.brands,
      thumbnails: listing.thumbnails,
      lists: lists,
    );
  }

  @override
  Future<bool> canEditSite(String accessToken) async {
    if (_sessionUser(accessToken) == null) {
      throw const CustomerSessionRefused();
    }
    final answer = await _customerRpc(accessToken, 'can_edit_tenant_settings', {
      'p_tenant_id': config.tenantId,
    });
    return answer == true;
  }

  @override
  Future<HomePageReads> draftPage(
    Map<String, dynamic> page,
    PagePicker picks,
  ) async {
    final results = await Future.wait([
      _shell(),
      _payments(),
      _pageProducts(picks(page)),
    ]);
    final listing =
        results[2]
            as ({
              List<Object?> rows,
              List<Object?> brands,
              List<Object?> thumbnails,
              Map<String, List<String>> lists,
            });
    return (
      shell: results[0] as Map<String, dynamic>,
      payments: results[1],
      page: page,
      products: listing.rows,
      brandRows: listing.brands,
      thumbnails: listing.thumbnails,
      lists: listing.lists,
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
    // The filters are not the page: under a burst the facet read is the one
    // `anon`'s 3 s statement timeout cancels (500), and the whole catalog
    // answered 503 although its products had been read (22 times to
    // PerplexityBot on 2026-10-06). Without them the page lists its products
    // and leaves the counts and filters out, like Flutter's unavailable
    // snapshot.
    Future<Object?> optional(String name, Future<Object?> read) =>
        read.catchError((Object error) {
          stderr.writeln('catalog $name unavailable: $error');
          return _unavailable;
        });
    final listingRead = _rpc('get_public_products_faceted_v2', {
      ...filters,
      'p_sort_by': request.sortBy,
      'p_limit': request.limit,
      'p_offset': request.offset,
    }).then((rows) => _completeRows(list(rows)));
    final facetsRead = request.facets
        ? optional('facets', _rpc('get_public_product_facets_v2', filters))
        : Future<Object?>.value(const <Object?>[]);
    final labelsRead = request.facets
        ? optional(
            'option labels',
            _rpc('get_public_spec_option_labels_v1', {
              'p_tenant_id': config.tenantId,
            }),
          )
        : Future<Object?>.value(const <Object?>[]);
    // The brands the URL filters by, named even when the other filters
    // leave them no product and the facet read no longer lists them: their
    // checkbox stays, checked, so the visitor sees why nothing is listed
    // and can take them off.
    final selectedBrandIds = request.brandIds.where(_uuid.hasMatch).toSet();
    final selectedBrandsRead = request.facets && selectedBrandIds.isNotEmpty
        ? optional('selected brands', _brandRows(selectedBrandIds))
        : Future<Object?>.value(const <Object?>[]);
    final listing = await listingRead;
    final facets = await facetsRead;
    final labels = await labelsRead;
    final selectedBrands = list(await selectedBrandsRead);
    final listedBrandIds = {
      for (final row in listing.brands)
        if (row is Map) row['id']?.toString(),
    };
    return (
      products: listing.rows,
      brandRows: [
        ...listing.brands,
        for (final row in selectedBrands)
          if (row is Map && !listedBrandIds.contains(row['id']?.toString()))
            row,
      ],
      thumbnails: listing.thumbnails,
      facets: identical(facets, _unavailable) ? null : list(facets),
      optionLabels: list(labels),
    );
  }

  /// Active brands by id: the store's own and the shared catalog's
  /// (`tenant_id` null), never another store's.
  Future<List<Object?>> _brandRows(Iterable<String> ids) =>
      _select('product_brands', {
        'select': 'id,name,tenant_id,is_active',
        'id': 'in.(${ids.join(',')})',
        'is_active': 'eq.true',
        'or': '(tenant_id.is.null,tenant_id.eq.${config.tenantId})',
      });

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
    final brandIds = {
      for (final row in rows)
        if (row is Map && _uuid.hasMatch(row['brand_id']?.toString() ?? ''))
          row['brand_id'].toString(),
    };
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
        layer('brands', _brandRows(brandIds)),
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

  @override
  Future<CustomerPortalReads> customerPortal(
    String accessToken, {
    bool files = true,
  }) async {
    final userId = _sessionUser(accessToken);
    if (userId == null) throw const CustomerSessionRefused();
    final tenant = config.tenantId;
    Future<List<Object?>> profileRead() =>
        _customerSelect(accessToken, 'customers', {
          'select': '*',
          'auth_user_id': 'eq.$userId',
          'tenant_id': 'eq.$tenant',
          'limit': '1',
        });
    // The account's creation is idempotent and almost always done: read the
    // profile beside it, and again after it only when it was missing.
    final provision = _customerRpc(
      accessToken,
      'provision_current_public_store_customer',
      {'p_tenant_id': tenant},
    );
    final first = await Future.wait<Object?>([
      _shell(),
      profileRead(),
      provision.then<Object?>((_) => null),
    ]);
    final shell = first[0] as Map<String, dynamic>;
    var rows = first[1] as List<Object?>;
    if (rows.isEmpty) rows = await profileRead();
    final row = rows.isEmpty ? null : rows.first;
    final profile =
        row is Map &&
            row['auth_user_id']?.toString() == userId &&
            row['tenant_id']?.toString() == tenant
        ? Map<String, dynamic>.from(row)
        : null;
    if (profile == null) {
      return (
        shell: shell,
        profile: null,
        addresses: const <Object?>[],
        orders: const <Object?>[],
        bikes: const <Object?>[],
        jobs: const <Object?>[],
        jobBikes: const <Object?>[],
        productImages: const <Object?>[],
        jobFiles: const <String, String>{},
      );
    }
    final customer = profile['id'].toString();
    final second = await Future.wait<List<Object?>>([
      _customerSelect(accessToken, 'customer_addresses', {
        'select': '*',
        'customer_id': 'eq.$customer',
        'tenant_id': 'eq.$tenant',
        'order': 'is_default.desc,created_at.desc',
      }),
      _customerSelect(accessToken, 'online_orders', {
        'select': '*,online_order_items(*)',
        'customer_id': 'eq.$customer',
        'tenant_id': 'eq.$tenant',
        'order': 'created_at.desc',
      }),
      _customerSelect(accessToken, 'bikes', {
        'select': '*,bike_brands(name),bike_models(name)',
        'tenant_id': 'eq.$tenant',
        'customer_id': 'eq.$customer',
        'is_active': 'eq.true',
        'order': 'created_at.desc',
      }),
      _customerSelect(accessToken, 'mechanic_jobs', {
        'select': '*',
        'tenant_id': 'eq.$tenant',
        'customer_id': 'eq.$customer',
        'deleted_at': 'is.null',
        'order': 'created_at.desc',
      }),
    ]);
    final orders = second[1];
    final jobs = second[3];
    final productIds = <String>{
      for (final order in orders)
        if (order is Map)
          for (final item in order['online_order_items'] as List? ?? const [])
            if (item is Map &&
                _uuid.hasMatch(item['product_id']?.toString().trim() ?? ''))
              item['product_id'].toString().trim(),
    };
    final bikeIds = <String>{
      for (final job in jobs)
        if (job is Map && _uuid.hasMatch(job['bike_id']?.toString() ?? ''))
          job['bike_id'].toString(),
    };
    final references = <String>{
      if (files)
        for (final job in jobs)
          if (job is Map)
            for (final value in job['image_urls'] as List? ?? const [])
              if (value is String && value.trim().isNotEmpty) value.trim(),
    };
    final third = await Future.wait<Object?>([
      productIds.isEmpty
          ? Future.value(const <Object?>[])
          : _select('products', {
              'select': customerOrderImageColumns,
              'tenant_id': 'eq.$tenant',
              'id': 'in.(${productIds.join(',')})',
            }).catchError((Object error) {
              // Flutter shows the rows without photos when this fails.
              stderr.writeln(
                'portal order images unavailable: ${error.runtimeType}',
              );
              return const <Object?>[];
            }),
      bikeIds.isEmpty
          ? Future.value(const <Object?>[])
          : _customerSelect(accessToken, 'bikes', {
              'select': 'id,brand,model,color,bike_type,wheel_size',
              'tenant_id': 'eq.$tenant',
              'id': 'in.(${bikeIds.join(',')})',
            }).catchError((Object error) {
              if (error is CustomerSessionRefused) throw error;
              stderr.writeln(
                'portal job bikes unavailable: ${error.runtimeType}',
              );
              return const <Object?>[];
            }),
      Future.wait([
        for (final reference in references)
          customerJobFile(
            accessToken,
            reference,
          ).then((url) => MapEntry(reference, url)),
      ]),
    ]);
    return (
      shell: shell,
      profile: profile,
      addresses: second[0],
      orders: orders,
      bikes: second[2],
      jobs: jobs,
      jobBikes: third[1] as List<Object?>,
      productImages: third[0] as List<Object?>,
      jobFiles: {
        for (final entry in third[2] as List<MapEntry<String, String?>>)
          if (entry.value != null) entry.key: entry.value!,
      },
    );
  }

  @override
  Future<String?> customerJobFile(String accessToken, String reference) async {
    final uri = Uri.tryParse(reference);
    final needsResolution =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path.startsWith(
          '/storage/v1/object/public/vinabike-assets/mechanic_jobs/',
        );
    if (!needsResolution) return reference;
    final expected =
        '${config.supabaseUrl}/storage/v1/object/public/vinabike-assets/'
        'mechanic_jobs/';
    if (!reference.startsWith(expected)) return null;
    try {
      final raw = await _customerRpc(
        accessToken,
        'workshop_legacy_asset_read_v1',
        {'p_reference': reference},
      );
      if (raw is! Map) return null;
      if (raw['mode'] == 'legacy' && raw['url'] == reference) return reference;
      const bucket = 'workshop-legacy-private';
      final path = raw['path'];
      if (raw['mode'] != 'private' ||
          raw['bucket'] != bucket ||
          path is! String ||
          path.split('/').length != 4) {
        return null;
      }
      final signed = await _customerPost(
        accessToken,
        '/storage/v1/object/sign/$bucket/$path',
        {'expiresIn': 300},
      );
      final relative = signed is Map ? signed['signedURL'] : null;
      if (relative is! String || relative.isEmpty) return null;
      return '${config.supabaseUrl}/storage/v1$relative';
    } on CustomerSessionRefused {
      rethrow;
    } on Object catch (error) {
      // No server payload nor private link in the log, as Flutter.
      stderr.writeln('portal job file unavailable: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<String> customerSignedObject(
    String accessToken,
    String bucket,
    String path, {
    required int expiresIn,
  }) => _retrying(
    () => _atTheDatabase(() async {
      // The path goes as written, as `createSignedUrl` sends it: Storage
      // signs the name it reads in the address, so `1.0.16%2B116` would
      // sign a name no link can open (2026-10-08).
      if (path.contains(RegExp(r'[?#%]'))) throw const StorageRefused('400');
      final uri = Uri.parse(
        '${config.supabaseUrl}/storage/v1/object/sign/$bucket/$path',
      );
      final request = await _client.openUrl('POST', uri).timeout(_timeout);
      request.headers
        ..set('apikey', config.publishableKey)
        ..set('authorization', 'Bearer $accessToken')
        ..contentType = ContentType.json;
      request.write(jsonEncode({'expiresIn': expiresIn}));
      final (response, text) = await _exchange(request);
      if (response.statusCode == 401) throw const CustomerSessionRefused();
      Object? body;
      try {
        body = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        body = null;
      }
      final relative = body is Map ? body['signedURL'] : null;
      if (response.statusCode < 300 &&
          relative is String &&
          relative.isNotEmpty) {
        return '${config.supabaseUrl}/storage/v1$relative';
      }
      // Storage names an expired or bad token in the body (`InvalidJWT`,
      // «jwt expired») rather than with a 401.
      final error = body is Map ? '${body['error']} ${body['message']}' : '';
      if (error.toLowerCase().contains('jwt')) {
        throw const CustomerSessionRefused();
      }
      final named = body is Map ? body['statusCode'] : null;
      throw StorageRefused(named == null ? '${response.statusCode}' : '$named');
    }),
  );

  @override
  Future<List<int>?> signedObjectBytes(String url, {required int maxBytes}) =>
      _retrying(() async {
        final uri = Uri.parse(url);
        // Only this project's Storage: the link was signed here.
        if (!url.startsWith('${config.supabaseUrl}/storage/v1/object/sign/')) {
          return null;
        }
        final request = await _client.getUrl(uri).timeout(_timeout);
        request.headers
          ..set('cache-control', 'no-cache, no-store, max-age=0')
          ..set('pragma', 'no-cache');
        final response = await request.close().timeout(_timeout);
        if (response.statusCode != 200) {
          await response.drain<void>();
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(_timeout)) {
          bytes.addAll(chunk);
          if (bytes.length > maxBytes) return null;
        }
        return bytes;
      });

  @override
  Future<Map<String, dynamic>?> customerEnter(String accessToken) async {
    if (_sessionUser(accessToken) == null) {
      throw const CustomerSessionRefused();
    }
    try {
      await _customerRpc(
        accessToken,
        'provision_current_public_store_customer',
        {'p_tenant_id': config.tenantId},
      );
    } on PublicReadException catch (error) {
      // The database busy or failing is not an answer about the customer:
      // the page says «try again», not «not a customer».
      if (error.retryable) rethrow;
      // Refused (an unconfirmed e-mail, an inactive or taken customer): not
      // a customer of this store. Only the kind is logged.
      stderr.writeln('customer enter refused: ${error.message}');
      return null;
    }
    return customerProfile(accessToken);
  }

  @override
  Future<Map<String, dynamic>?> customerProfile(String accessToken) async {
    final userId = _sessionUser(accessToken);
    if (userId == null) throw const CustomerSessionRefused();
    final tenant = config.tenantId;
    final rows = await _customerSelect(accessToken, 'customers', {
      'select': '*',
      'auth_user_id': 'eq.$userId',
      'tenant_id': 'eq.$tenant',
      'limit': '1',
    });
    final row = rows.isEmpty ? null : rows.first;
    return row is Map &&
            row['auth_user_id']?.toString() == userId &&
            row['tenant_id']?.toString() == tenant
        ? Map<String, dynamic>.from(row)
        : null;
  }

  static const _customerTables = {'customers', 'customer_addresses'};

  @override
  Future<bool> customerWrite(
    String accessToken, {
    required String method,
    required String table,
    Map<String, String> filters = const {},
    Map<String, Object?>? body,
  }) async {
    if (!_customerTables.contains(table) ||
        !const {'PATCH', 'POST', 'DELETE'}.contains(method)) {
      throw ArgumentError('not a portal write: $method $table');
    }
    final names = method == 'POST'
        ? (body ?? const {})['tenant_id']?.toString() == config.tenantId
        : filters['tenant_id'] == 'eq.${config.tenantId}';
    if (!names) throw ArgumentError('a portal write names its store');
    Future<Object?> send() => _customerSend(
      accessToken,
      method,
      Uri.parse(
        '${config.supabaseUrl}/rest/v1/$table',
      ).replace(queryParameters: filters.isEmpty ? null : filters),
      body,
      '$table ${method.toLowerCase()}',
      prefer: 'return=representation',
    );
    // A change or a removal can be sent twice; a new row cannot.
    final written = method == 'POST' ? await send() : await _retrying(send);
    return written is List && written.isNotEmpty;
  }

  @override
  Future<CustomerAuthAnswer> customerAuth(
    String accessToken,
    CustomerAuthCall call, {
    Map<String, Object?>? body,
  }) async {
    final (method, path) = switch (call) {
      CustomerAuthCall.updatePassword => ('PUT', '/auth/v1/user'),
      CustomerAuthCall.reauthenticate => ('GET', '/auth/v1/reauthenticate'),
      CustomerAuthCall.signOutOthers => (
        'POST',
        '/auth/v1/logout?scope=others',
      ),
      CustomerAuthCall.signOutEverywhere => (
        'POST',
        '/auth/v1/logout?scope=global',
      ),
    };
    final request = await _client
        .openUrl(method, Uri.parse('${config.supabaseUrl}$path'))
        .timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer $accessToken');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final (response, text) = await _exchange(request);
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map ? decoded : const {};
    final rawCode = error['error_code'] ?? error['code'];
    final code = rawCode is String ? rawCode : null;
    final message =
        (error['msg'] ?? error['message'] ?? error['error_description'] ?? '')
            .toString();
    if (response.statusCode == 401 ||
        const {
          'bad_jwt',
          'no_authorization',
          'session_not_found',
          'session_expired',
        }.contains(code)) {
      throw const CustomerSessionRefused();
    }
    return (
      status: response.statusCode,
      code: response.statusCode < 300 ? null : code,
      message: response.statusCode < 300 ? '' : message,
    );
  }

  /// The user a session token names (`sub`). Not trusted for anything but
  /// the filter Flutter also applies: Supabase checks the signature of every
  /// read that carries it.
  static String? _sessionUser(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final sub = payload is Map ? payload['sub']?.toString() : null;
      return sub != null && _uuid.hasMatch(sub) ? sub : null;
    } on FormatException {
      return null;
    }
  }

  Future<List<Object?>> _customerSelect(
    String token,
    String table,
    Map<String, String> query,
  ) async {
    final decoded = await _retrying(
      () => _customerSend(
        token,
        'GET',
        Uri.parse(
          '${config.supabaseUrl}/rest/v1/$table',
        ).replace(queryParameters: query),
        null,
        table,
      ),
    );
    return decoded is List ? decoded : const [];
  }

  Future<Object?> _customerRpc(
    String token,
    String function,
    Map<String, Object?> body,
  ) => _retrying(
    () => _customerSend(
      token,
      'POST',
      Uri.parse('${config.supabaseUrl}/rest/v1/rpc/$function'),
      body,
      function,
    ),
  );

  Future<Object?> _customerPost(
    String token,
    String path,
    Map<String, Object?> body,
  ) => _retrying(
    () => _customerSend(
      token,
      'POST',
      Uri.parse('${config.supabaseUrl}$path'),
      body,
      'storage sign',
    ),
  );

  Future<Object?> _customerSend(
    String token,
    String method,
    Uri uri,
    Map<String, Object?>? body,
    String name, {
    String? prefer,
  }) => _atTheDatabase(() async {
    final request = await _client.openUrl(method, uri).timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer $token');
    if (prefer != null) request.headers.set('prefer', prefer);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final (response, text) = await _exchange(request);
    if (response.statusCode == 401) throw const CustomerSessionRefused();
    if (response.statusCode >= 300) {
      throw PublicReadException(
        '$name → ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return text.isEmpty ? null : jsonDecode(text);
  });

  /// Sends [request] and reads its answer, each step within [_timeout].
  /// Past it the request is aborted, not only abandoned: the place it held
  /// at the database is handed on, and it must really be free.
  Future<(HttpClientResponse, String)> _exchange(
    HttpClientRequest request,
  ) async {
    try {
      final response = await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      return (response, text);
    } on TimeoutException {
      request.abort();
      rethrow;
    }
  }

  /// [send] when the database has a place for it; a read that waited too
  /// long fails like any other, so its page answers «try again».
  Future<T> _atTheDatabase<T>(Future<T> Function() send) async {
    try {
      return await _gate.run(send);
    } on DatabaseBusy {
      throw PublicReadException('database busy', busy: true);
    }
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

  Future<List<Object?>> _selectOnce(String table, Map<String, String> query) =>
      _atTheDatabase(() async {
        final uri = Uri.parse(
          '${config.supabaseUrl}/rest/v1/$table',
        ).replace(queryParameters: query);
        final request = await _client.getUrl(uri).timeout(_timeout);
        request.headers
          ..set('apikey', config.publishableKey)
          ..set('authorization', 'Bearer ${config.publishableKey}');
        final (response, text) = await _exchange(request);
        if (response.statusCode >= 300) {
          throw PublicReadException(
            '$table → ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        final decoded = jsonDecode(text);
        return decoded is List ? decoded : const <Object?>[];
      });

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
    final key = '$function ${jsonEncode(body)}';
    // A block body: `remove` returns this very future, and `whenComplete`
    // would wait for it forever.
    final text = await (_inFlight[key] ??=
        _retrying(() => _rpcOnce(function, body)).whenComplete(() {
          _inFlight.remove(key);
        }));
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<String> _rpcOnce(String function, Map<String, Object?> body) =>
      _atTheDatabase(() async {
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
        final (response, text) = await _exchange(request);
        if (response.statusCode >= 300) {
          throw PublicReadException(
            '$function → ${response.statusCode}',
            statusCode: response.statusCode,
          );
        }
        return text;
      });
}
