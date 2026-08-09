import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  test('product snapshot candidates keyset-page beyond one thousand rows',
      () async {
    const pageSize = 1000;
    final requestedUris = <Uri>[];
    final firstPage = List.generate(
      pageSize,
      (index) => <String, dynamic>{
        'id': index.toString().padLeft(4, '0'),
      },
    );
    final secondPage = List.generate(
      205,
      (index) => <String, dynamic>{
        'id': (pageSize + index).toString().padLeft(4, '0'),
      },
    );

    final products = await snapshots.fetchSeoSnapshotProductCandidates(
      supabaseUrl: 'https://example.supabase.co',
      tenantId: 'tenant',
      serviceRoleKey: 'not-used-by-test-loader',
      onlyMerchant: false,
      pageSize: pageSize,
      pageLoader: (uri) async {
        requestedUris.add(uri);
        return requestedUris.length == 1 ? firstPage : secondPage;
      },
    );

    expect(products, hasLength(1205));
    expect(requestedUris, hasLength(2));
    expect(requestedUris.first.queryParameters['order'], 'id.asc');
    expect(requestedUris.first.queryParameters.containsKey('id'), isFalse);
    expect(requestedUris.last.queryParameters['id'], 'gt.0999');
    expect(
      products.map((product) => product['id']).toSet(),
      hasLength(1205),
    );
  });

  test('product aliases keep a total order across timestamp-tied pages',
      () async {
    const pageSize = 1000;
    const aliasCount = 2205;
    const sharedCreatedAt = '2026-06-14T21:12:47.59316Z';
    final sourceRows = List.generate(
      aliasCount,
      (index) => <String, dynamic>{
        'product_id': 'product-${index.toString().padLeft(4, '0')}',
        'alias_path': '/productos/alias-${index.toString().padLeft(4, '0')}',
        'source': 'historical-import',
        'created_at': sharedCreatedAt,
      },
      growable: false,
    );
    final requestedUris = <Uri>[];

    final aliases = await snapshots.fetchSeoSnapshotProductUrlAliases(
      supabaseUrl: 'https://example.supabase.co',
      tenantId: 'tenant',
      serviceRoleKey: 'not-used-by-test-loader',
      pageSize: pageSize,
      pageLoader: (uri) async {
        requestedUris.add(uri);
        final offset = int.parse(uri.queryParameters['offset']!);
        final hasTotalOrder =
            uri.queryParameters['order'] == 'created_at.asc,alias_path.asc';
        final rowsInDatabaseOrder = hasTotalOrder || requestedUris.length.isOdd
            ? sourceRows
            : sourceRows.reversed.toList(growable: false);
        final end = offset + pageSize < rowsInDatabaseOrder.length
            ? offset + pageSize
            : rowsInDatabaseOrder.length;
        return offset >= sourceRows.length
            ? const <Map<String, dynamic>>[]
            : rowsInDatabaseOrder.sublist(offset, end);
      },
    );

    expect(requestedUris, hasLength(3));
    expect(
      requestedUris.map((uri) => uri.queryParameters['order']).toSet(),
      {'created_at.asc,alias_path.asc'},
    );
    expect(
      requestedUris.map((uri) => uri.queryParameters['offset']),
      ['0', '1000', '2000'],
    );
    expect(aliases, hasLength(aliasCount));
    expect(
      aliases.map((alias) => alias['alias_path']).toSet(),
      hasLength(aliasCount),
    );
    expect(
      aliases.map((alias) => alias['alias_path']),
      sourceRows.map((alias) => alias['alias_path']),
    );
  });

  test('redirect ledger keeps a published product outside current availability',
      () {
    const productId = '85164038-dcd0-424b-880f-082071c8de51';
    final publishedCandidates = [
      <String, dynamic>{
        'id': productId,
        'name': 'Producto temporalmente sin stock',
        'sku': 'STABLE-1',
        'is_active': true,
        'is_published': true,
        'show_on_website': true,
      },
    ];
    const currentlyAvailable = <Map<String, dynamic>>[];

    final canonicalLedger = snapshots.buildSeoProductCanonicalPathLedger(
      publishedProducts: publishedCandidates,
    );
    final redirects = snapshots.buildSeoProductRedirectAliases(
      products: publishedCandidates,
      aliases: const [],
      canonicalPathByProductId: canonicalLedger,
    );

    expect(currentlyAvailable, isEmpty);
    expect(
      canonicalLedger[productId],
      '/productos/producto-temporalmente-sin-stock/STABLE-1',
    );
    expect(
      redirects
          .where((redirect) => redirect.aliasPath == '/productos/$productId'),
      hasLength(1),
    );
    expect(
      redirects
          .singleWhere(
            (redirect) => redirect.aliasPath == '/productos/$productId',
          )
          .productId,
      productId,
    );
  });

  test('Merchant snapshot scope cannot narrow the redirect owner ledger', () {
    final publishedOwners = [
      <String, dynamic>{
        'id': 'merchant-product',
        'name': 'Producto Merchant',
        'sku': 'MERCHANT-1',
        'is_google_merchant': true,
        'is_active': true,
        'is_published': true,
        'show_on_website': true,
      },
      <String, dynamic>{
        'id': 'ordinary-product',
        'name': 'Producto web',
        'sku': 'WEB-1',
        'is_google_merchant': false,
        'is_active': true,
        'is_published': true,
        'show_on_website': true,
      },
    ];

    final merchantSnapshots = snapshots.selectSeoSnapshotCandidatesForScope(
      publishedProducts: publishedOwners,
      onlyMerchant: true,
    );
    final canonicalLedger = snapshots.buildSeoProductCanonicalPathLedger(
      publishedProducts: publishedOwners,
    );
    final redirects = snapshots.buildSeoProductRedirectAliases(
      products: publishedOwners,
      aliases: const [],
      canonicalPathByProductId: canonicalLedger,
    );

    expect(merchantSnapshots.map((row) => row['id']), ['merchant-product']);
    expect(
        canonicalLedger.keys,
        containsAll(<String>[
          'merchant-product',
          'ordinary-product',
        ]));
    expect(
      redirects.map((redirect) => redirect.aliasPath),
      contains('/productos/ordinary-product'),
    );
  });

  test('published website pages keyset-page deterministically', () async {
    final requestedUris = <Uri>[];
    final pages = await snapshots.fetchSeoSnapshotPublishedWebsitePages(
      supabaseUrl: 'https://example.supabase.co',
      tenantId: 'tenant',
      serviceRoleKey: 'not-used-by-test-loader',
      pageSize: 2,
      pageLoader: (uri) async {
        requestedUris.add(uri);
        if (uri.queryParameters['id'] == null) {
          return [
            {'id': 'page-a', 'slug': 'a', 'is_published': true},
            {'id': 'page-b', 'slug': 'b', 'is_published': true},
          ];
        }
        return [
          {'id': 'page-c', 'slug': 'c', 'is_published': true},
        ];
      },
    );

    expect(pages.map((page) => page['id']), ['page-a', 'page-b', 'page-c']);
    expect(requestedUris, hasLength(2));
    expect(requestedUris.first.queryParameters['order'], 'id.asc');
    expect(requestedUris.first.queryParameters['is_published'], 'eq.true');
    expect(requestedUris.last.queryParameters['id'], 'gt.page-b');
  });

  test('website blocks page by stable id and sort by editor order', () async {
    final requestedUris = <Uri>[];
    final blocksByPage = await snapshots.fetchSeoSnapshotWebsiteBlocksForPages(
      supabaseUrl: 'https://example.supabase.co',
      pages: const [
        {'id': 'page-c'},
        {'id': 'page-a'},
        {'id': 'page-b'},
      ],
      serviceRoleKey: 'not-used-by-test-loader',
      pageSize: 2,
      pageIdBatchSize: 2,
      pageLoader: (uri) async {
        requestedUris.add(uri);
        final filter = uri.queryParameters['page_id'] ?? '';
        final afterId = uri.queryParameters['id'];
        if (filter.contains('page-a')) {
          if (afterId == null) {
            return [
              {
                'id': 'block-a',
                'page_id': 'page-a',
                'order_index': 2,
              },
              {
                'id': 'block-b',
                'page_id': 'page-b',
                'order_index': 0,
              },
            ];
          }
          return [
            {
              'id': 'block-c',
              'page_id': 'page-a',
              'order_index': 1,
            },
          ];
        }
        return [
          {
            'id': 'block-d',
            'page_id': 'page-c',
            'order_index': 0,
          },
        ];
      },
    );

    expect(requestedUris, hasLength(3));
    expect(requestedUris.first.queryParameters['order'], 'id.asc');
    expect(
      requestedUris.first.queryParameters['page_id'],
      'in.(page-a,page-b)',
    );
    expect(requestedUris[1].queryParameters['id'], 'gt.block-b');
    expect(
      blocksByPage['page-a']!.map((block) => block['id']),
      ['block-c', 'block-a'],
    );
    expect(blocksByPage['page-b']!.single['id'], 'block-b');
    expect(blocksByPage['page-c']!.single['id'], 'block-d');
  });
}
