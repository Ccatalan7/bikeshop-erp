import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vinabike_storefront_html/src/block_product_picks.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

/// Supabase's edge closes a kept-alive connection after a quiet spell; the
/// next read on it failed with «Connection reset by peer» and the visitor got
/// a bare 500 (2026-10-05). A read is idempotent: it is asked again once.
void main() {
  test(
    'a read on a connection the other side dropped is asked again',
    () async {
      var calls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        calls++;
        if (calls == 1) {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        final shell = {'settings': {}, 'navigation': []};
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              request.uri.path.endsWith('_shell_if_changed_v1')
                  ? {'stamp': 'a', 'shell': shell}
                  : shell,
            ),
          );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final reads = SupabasePublicReads(
        StorefrontConfig(
          supabaseUrl: 'http://127.0.0.1:${server.port}',
          publishableKey: 'test',
        ),
      );
      final shell = await reads.shell();
      expect(shell.shell['navigation'], isEmpty);
      // The shell and the payment methods, plus the one retried.
      expect(calls, greaterThanOrEqualTo(3));
    },
  );

  // Every page read the whole shell (~37 kB compressed) and crawlers ask for
  // ~4,400 pages a day: the largest share of the project's egress
  // (2026-10-31). A page now trusts the kept shell for a few seconds, then
  // asks with the stamp it knows; the shell travels only when it changed.
  test('the shell travels once and then only its stamp', () async {
    final shellAsks = <String?>[];
    var paymentReads = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      Object? body = const <Object?>[];
      if (name == 'get_public_storefront_shell_if_changed_v1') {
        final args = jsonDecode(await utf8.decodeStream(request)) as Map;
        final known = args['p_known_stamp'] as String?;
        shellAsks.add(known);
        body = known == 'a'
            ? {'stamp': 'a'}
            : {
                'stamp': 'a',
                'shell': {
                  'settings': {'store_name': 'Vinabike'},
                  'navigation': [],
                },
              };
      } else if (name == 'get_public_checkout_capabilities') {
        paymentReads++;
        body = {'card': true};
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final reads = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );

    final first = await reads.shell();
    first.shell['settings']['store_name'] = 'cambiado por una página';
    final second = await reads.shell();

    expect(shellAsks, [null], reason: 'two pages in a row read it once');
    expect(paymentReads, 1);
    expect(
      second.shell['settings']['store_name'],
      'Vinabike',
      reason: 'a page never sees what another one did to its copy',
    );
    expect(second.payments, {'card': true});

    // Once the kept shell is old enough to ask again, it asks with its
    // stamp and keeps the shell it has.
    final asking = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
      shellCheckEvery: Duration.zero,
    );
    shellAsks.clear();
    await asking.shell();
    final kept = await asking.shell();
    expect(shellAsks, [null, 'a']);
    expect(kept.shell['settings']['store_name'], 'Vinabike');
  });

  // An editor page is served at the path its template gives it: a guide at
  // `/guias/<slug>`, dated and timed. The page read once left the template
  // out, the test doubles carried it, and every guide moved back to
  // `/pagina/` (2026-10-09).
  test('an editor page is read with its template and its dates', () async {
    final selects = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.endsWith('/website_pages')) {
        selects.add(request.uri.queryParameters['select'] ?? '');
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          request.uri.path.endsWith('_shell_if_changed_v1')
              ? '{"stamp":"a","shell":{}}'
              : request.uri.path.contains('/rpc/')
              ? '{}'
              : '[]',
        );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final reads = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );
    await reads.websitePage('mantencion', (_) => const PagePicks());
    await reads.guides();
    expect(selects, hasLength(2));
    for (final select in selects) {
      final columns = select.split(',');
      for (final column in [
        'template',
        'is_home',
        'published_at',
        'created_at',
        'updated_at',
      ]) {
        expect(columns, contains(column), reason: select);
      }
    }
  });

  // Entering provisions the store's customer; a refusal means «not a
  // customer here», the database failing does not (2026-10-07).
  test('entering tells a refusal from the database failing', () async {
    var status = 400;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = status;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    String b64(Map<String, Object?> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${b64({'alg': 'HS256'})}.'
        '${b64({'sub': '7fac2000-0000-4000-8000-000000000001', 'exp': 4102444800})}.'
        'firma';
    final reads = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );
    expect(await reads.customerEnter(token), isNull);
    status = 503;
    await expectLater(
      reads.customerEnter(token),
      throwsA(
        isA<PublicReadException>().having(
          (error) => error.retryable,
          'retryable',
          isTrue,
        ),
      ),
    );
  });

  // Two sends of the same chat message at once both miss the key; the base
  // keeps one row per key (`messages_one_per_client_key`) and refuses the
  // second with 23505, which is a message already sent (2026-10-08).
  test('a chat message the base already holds counts as sent', () async {
    var stored = false;
    var refuseWithoutRow = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      if (request.method == 'GET') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              stored
                  ? [
                      {'id': 'f1000000-0000-4000-8000-000000000001'},
                    ]
                  : [],
            ),
          );
      } else {
        // The other request wrote it between the look and the insert.
        stored = !refuseWithoutRow;
        request.response
          ..statusCode = 409
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'code': '23505',
              'message': 'duplicate key value violates unique constraint',
            }),
          );
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    String b64(Map<String, Object?> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${b64({'alg': 'HS256'})}.'
        '${b64({'sub': '7fac2000-0000-4000-8000-000000000001', 'exp': 4102444800})}.'
        'firma';
    final reads = SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );
    Future<bool> send() => reads.customerChatMessage(
      token,
      conversationId: 'c0000000-0000-4000-8000-0000000000c1',
      text: 'Hola',
      clientId: 'k0123456789abcdef',
    );
    expect(await send(), isTrue);
    // A conflict whose row the customer cannot see is not «sent».
    stored = false;
    refuseWithoutRow = true;
    expect(await send(), isFalse);
  });

  group('a catalog read', () {
    late HttpServer server;
    final calls = <String, int>{};
    final bodies = <String, Map<String, dynamic>>{};
    var facetStatus = 200;
    var atOnce = 0;
    var mostAtOnce = 0;

    setUp(() async {
      calls.clear();
      bodies.clear();
      facetStatus = 200;
      atOnce = 0;
      mostAtOnce = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final function = request.uri.pathSegments.last;
        calls[function] = (calls[function] ?? 0) + 1;
        final body = await utf8.decoder.bind(request).join();
        if (body.isNotEmpty) {
          bodies[function] = Map<String, dynamic>.from(jsonDecode(body) as Map);
        }
        atOnce++;
        if (atOnce > mostAtOnce) mostAtOnce = atOnce;
        // Long enough for the burst below to arrive while it is answered.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        atOnce--;
        if (function == 'get_public_product_facets_v2' && facetStatus != 200) {
          request.response.statusCode = facetStatus;
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                function == 'get_public_product_facets_v2'
                    ? [
                        {'facet_key': 'summary', 'item_count': 3},
                      ]
                    : [],
              ),
            );
        }
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    SupabasePublicReads reads() => SupabasePublicReads(
      StorefrontConfig(
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'test',
      ),
    );

    CatalogRequest request({
      String searchQuery = '',
      bool includeOutOfStock = false,
    }) => CatalogRequest(
      categoryIds: null,
      searchQuery: searchQuery,
      includeOutOfStock: includeOutOfStock,
      brandIds: const [],
      specFilters: null,
      minPrice: null,
      maxPrice: null,
      onlyInStock: true,
      sortBy: 'name',
      limit: 20,
      offset: 0,
    );

    // «Incluir agotados» (2026-10-24): the listing and its facets ask for it;
    // a read that does not want it does not send the parameter at all.
    test(
      'a search widened to what is out of stock says so to both reads',
      () async {
        await reads().catalog(
          request(searchQuery: 'camara fv', includeOutOfStock: true),
        );
        expect(
          bodies['get_public_products_faceted_v2']?['p_include_out_of_stock'],
          isTrue,
        );
        expect(
          bodies['get_public_product_facets_v2']?['p_include_out_of_stock'],
          isTrue,
        );

        bodies.clear();
        await reads().catalog(request(searchQuery: 'camara fv'));
        expect(
          bodies['get_public_products_faceted_v2'],
          isNot(contains('p_include_out_of_stock')),
        );
        expect(
          bodies['get_public_product_facets_v2'],
          isNot(contains('p_include_out_of_stock')),
        );
      },
    );

    // A crawler asked `/productos` a dozen times in a few seconds
    // (PerplexityBot, 2026-10-06): the same reads, once.
    test('a burst on one page asks each read once', () async {
      final store = reads();
      final pages = await Future.wait([
        for (var i = 0; i < 6; i++) store.catalog(request()),
      ]);
      expect(pages, hasLength(6));
      expect(calls['get_public_products_faceted_v2'], 1);
      expect(calls['get_public_product_facets_v2'], 1);
      expect(calls['get_public_spec_option_labels_v1'], 1);
      // Each page decodes its own rows: no two share them.
      expect(identical(pages[0].facets, pages[1].facets), isFalse);

      // Once answered, the next visit reads again: nothing is kept.
      await store.catalog(request());
      expect(calls['get_public_product_facets_v2'], 2);
    });

    // Twelve different pages at once (a crawler, 2026-10-07) put some
    // eighty queries on the free database together, and the ones past
    // anon's 3 s were cancelled: the database sees four at a time and every
    // page arrives.
    test('twelve different pages reach the database four at a time', () async {
      final store = reads();
      final pages = await Future.wait([
        for (var i = 0; i < 12; i++)
          store.catalog(
            CatalogRequest(
              categoryIds: null,
              searchQuery: 'pagina $i',
              brandIds: const [],
              specFilters: null,
              minPrice: null,
              maxPrice: null,
              onlyInStock: true,
              sortBy: 'name',
              limit: 20,
              offset: 0,
            ),
          ),
      ]);
      expect(pages, hasLength(12));
      expect(pages.every((page) => page.facets != null), isTrue);
      expect(calls['get_public_product_facets_v2'], 12);
      expect(mostAtOnce, 4);
    });

    test('a facet read that fails leaves the listing', () async {
      facetStatus = 500;
      final page = await reads().catalog(request());
      expect(page.facets, isNull);
      expect(page.products, isEmpty);
      expect(page.optionLabels, isEmpty);
    });
  });

  // A home with a featured block and a hand-picked one: the featured list
  // failing (2026-10-07, Codex) answered the whole home with a 503; Flutter
  // only leaves that block empty.
  test(
    'a product list that cannot be read leaves only its block empty',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final name = request.uri.pathSegments.last;
        Object? body;
        switch (name) {
          case 'get_public_featured_products':
            request.response.statusCode = 500;
          case 'get_public_storefront_shell_if_changed_v1':
            body = {'stamp': 'a', 'shell': <String, Object?>{}};
          case 'website_pages':
            body = [
              {
                'id': 'home',
                'slug': 'inicio',
                'is_published': true,
                'website_blocks': [
                  {
                    'id': 'f',
                    'block_type': 'products',
                    'order_index': 0,
                    'is_visible': true,
                    'block_data': {'productSource': 'featured'},
                  },
                  {
                    'id': 'm',
                    'block_type': 'products',
                    'order_index': 1,
                    'is_visible': true,
                    'block_data': {
                      'productSource': 'manual',
                      'productIds': ['p1'],
                    },
                  },
                ],
              },
            ];
          case 'get_public_products':
            body = [
              {'id': 'p1', 'name': 'Casco', 'sku': 'C1', 'price': 1000},
            ];
          default:
            body = <Object?>[];
        }
        if (request.response.statusCode == 200) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(body));
        }
        await request.response.close();
      });
      final reads = SupabasePublicReads(
        StorefrontConfig(
          supabaseUrl: 'http://127.0.0.1:${server.port}',
          publishableKey: 'test',
        ),
      );
      final home = await reads.homePage(pagePicks);
      expect(home.lists.values.single, isEmpty);
      expect(home.products, hasLength(1));
    },
  );
}
