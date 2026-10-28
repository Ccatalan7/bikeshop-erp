import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart' show Request, Response;
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'product_card.dart';
import 'public_reads.dart';
import 'storefront_shell.dart';

/// How many products and services the header's search suggests.
const searchSuggestedProducts = 6;
const searchSuggestedServices = 3;
const searchSuggestedCategories = 5;

/// The longest term the search reads; more is cut.
const searchTermMaxLength = 80;

/// `POST /buscar/sin-resultados` with `q=<what was searched>` (2026-10-24):
/// the page's beacon for a search it showed nothing for, handed to the base
/// (`catalog_search_miss_record_v1`), which searches again and keeps it only
/// if the whole store lists nothing. The ERP shows them in «Búsquedas» of
/// the store catalog. Answers 204 whatever happens: a visitor's page never
/// waits on it nor learns anything from it.
const searchMissPath = '/buscar/sin-resultados';

Future<Response> searchMissResponse(
  Request request, {
  required PublicReads reads,
}) async {
  const headers = {'cache-control': 'no-store', 'x-robots-tag': 'noindex'};
  final bytes = <int>[];
  try {
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > 1024) return Response(413, headers: headers);
    }
  } on Object {
    return Response(400, headers: headers);
  }
  var term = '';
  try {
    term =
        (Uri.splitQueryString(utf8.decode(bytes, allowMalformed: true))['q'] ??
                '')
            .trim();
  } on FormatException {
    term = '';
  }
  if (term.length >= 2 && term.length <= searchTermMaxLength) {
    try {
      await reads.recordSearchMiss(term);
    } on Object catch (error) {
      // Only the kind: the term is the visitor's.
      stderr.writeln('search miss not kept: ${error.runtimeType}');
    }
  }
  return Response(204, headers: headers);
}

/// What `/buscar?q=` reads (2026-10-24): the shell (for the categories'
/// names and paths), and the catalog's own search, once for the products
/// with its category facet and once for the workshop's services.
typedef SearchSuggestionReads = ({
  StorefrontShell shell,
  CatalogReads products,
  CatalogReads services,
});

/// The header's search while the visitor types, as JSON for the page
/// script: the products and services the catalog's search ranks first (its
/// relevance, accents and typos are the database's,
/// `get_public_products_faceted_v2`), the categories where those products
/// are, and how many products «Ver todos» leads to.
///
/// [withOutOfStock] («Incluir agotados») lists what is out of stock too (the
/// database puts what can be bought now first, 20261024060000), and «Ver
/// todos» keeps it (`stock=all`).
///
/// [fixed] is what the search looked for instead of a misspelt [term]
/// (2026-10-28, «kasco» is «casco»): the box says so, marks those words and
/// names the categories by them. [outOfStock] is how many more products
/// there are out of stock when «Incluir agotados» is off, so the box offers
/// them instead of ending the search.
Map<String, Object?> searchSuggestionsJson(
  String term,
  SearchSuggestionReads? reads, {
  required String tenantId,
  bool withOutOfStock = false,
  String? fixed,
  int outOfStock = 0,
}) {
  final all = Uri(
    path: '/productos',
    queryParameters: {'q': term, if (withOutOfStock) 'stock': 'all'},
  ).toString();
  if (reads == null) {
    return {
      'q': term,
      'all': all,
      'total': 0,
      'products': const [],
      'services': const [],
      'categories': const [],
    };
  }
  final productRows = rowsOf(reads.products.products);
  final found = _items(reads.products, productRows, tenantId: tenantId);
  final serviceRows = rowsOf(reads.services.products);
  return {
    'q': term,
    'all': all,
    'total': searchSuggestionsTotal(reads.products),
    if (fixed != null && fixed.isNotEmpty) 'fixed': fixed,
    if (outOfStock > 0) 'agotados': outOfStock,
    'products': found,
    'services': [
      for (final item in _items(
        reads.services,
        serviceRows,
        tenantId: tenantId,
      ))
        {...item, 'out': false},
    ],
    'categories': _categories(reads.shell, reads.products, fixed ?? term),
  };
}

/// How many products a suggestion's search lists in all.
int searchSuggestionsTotal(CatalogReads products) {
  final rows = rowsOf(products.products);
  return rows.isEmpty
      ? 0
      : (rows.first['total_count'] as num?)?.toInt() ?? rows.length;
}

List<Map<String, Object?>> _items(
  CatalogReads reads,
  List<Map<String, dynamic>> rows, {
  required String tenantId,
}) {
  final thumbnails = PublicImageThumbnail.byUrl(reads.thumbnails);
  final brandNames = canonicalPublicProductBrandNames(
    rows: rowsOf(reads.brandRows),
    tenantId: tenantId,
    requestedBrandIds: [
      for (final row in rows)
        if ((row['brand_id'] ?? '').toString().isNotEmpty)
          row['brand_id'].toString(),
    ],
  );
  return [
    for (final row in rows)
      if (PublicCommerceProductProjection.fromJson(
            row,
            resolvedBrand: brandNames[(row['brand_id'] ?? '').toString()],
          )
          case final commerce)
        {
          'id': commerce.sku.isNotEmpty ? commerce.sku : commerce.id,
          'name': commerce.title,
          'brand': commerce.brand,
          'value': commerce.price.round(),
          'price': commerce.price > 0 ? publicPrice(commerce.price) : '',
          'path': publicProductPath(Product.fromJson(row)),
          'img': switch (commerce.imageUrls) {
            [] => '',
            [final first, ...] => thumbnails[first]?.smallestUrl ?? first,
          },
          'out': commerce.availability != PublicCommerceAvailability.inStock,
        },
  ];
}

/// Where the products found are (the listing's category facet, which counts
/// the categories that hold them), up to [searchSuggestedCategories]. A
/// public category whose own name holds every word of [term] comes first
/// and leads to itself, with the products found below it: «frenos» →
/// Frenos, although its products sit in Pastillas and the rest; a category
/// of the workshop's services, with no product found below it, is not one.
/// One whose name holds some of the words comes next («neumatico 29» →
/// Neumáticos before Cámaras). Those and the others lead to themselves
/// filtered by the search, most products first («cadena» → Lubricantes, 7).
List<Map<String, Object?>> _categories(
  StorefrontShell shell,
  CatalogReads products,
  String term,
) {
  final words = _words(term);
  if (words.isEmpty) return const [];
  // 2: the name holds every word; 1: some; 0: none.
  int named(String name) {
    final theirs = _words(name, singular: false);
    final hits = words
        .where((word) => theirs.any((their) => their.startsWith(word)))
        .length;
    return hits == words.length ? 2 : (hits > 0 ? 1 : 0);
  }

  final counts = <String, int>{
    for (final row in rowsOf(products.facets))
      if (row['facet_key'] == 'category' &&
          (row['value_id'] ?? '').toString().isNotEmpty)
        row['value_id'].toString(): (row['item_count'] as num?)?.toInt() ?? 0,
  };
  final ranked =
      [
        for (final id in shell.categories.keys)
          if (shell.isPublishedCategory(id))
            if (named(shell.categoryName(id)) case final match)
              if (match == 2
                      ? shell
                            .subtreeOf(id)
                            .fold<int>(0, (sum, x) => sum + (counts[x] ?? 0))
                      : counts[id] ?? 0
                  case final count when count > 0)
                (
                  id: id,
                  name: shell.categoryName(id),
                  count: count,
                  match: match,
                ),
      ]..sort((a, b) {
        final byMatch = b.match.compareTo(a.match);
        return byMatch != 0 ? byMatch : b.count.compareTo(a.count);
      });
  return [
    for (final category in ranked.take(searchSuggestedCategories))
      {
        'name': category.name,
        'parent': switch (shell.parentOf(category.id)) {
          final parent? => shell.categoryName(parent),
          null => '',
        },
        'count': category.count,
        'path': category.match == 2
            ? shell.categoryPath(category.id)
            : Uri(
                path: shell.categoryPath(category.id),
                queryParameters: {'q': term},
              ).toString(),
      },
  ];
}

/// The words of [text] without accents or case; a searched word loses a
/// plural «s» so it is the start of the singular too.
List<String> _words(String text, {bool singular = true}) => [
  for (final word in productUrlSlug(text).split('-'))
    if (word.isNotEmpty)
      singular && word.length > 3 && word.endsWith('s')
          ? word.substring(0, word.length - 1)
          : word,
];
