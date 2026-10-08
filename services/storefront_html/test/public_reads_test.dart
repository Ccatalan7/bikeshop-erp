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
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'settings': {}, 'navigation': []}));
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
    var facetStatus = 200;
    var atOnce = 0;
    var mostAtOnce = 0;

    setUp(() async {
      calls.clear();
      facetStatus = 200;
      atOnce = 0;
      mostAtOnce = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final function = request.uri.pathSegments.last;
        calls[function] = (calls[function] ?? 0) + 1;
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

    CatalogRequest request() => CatalogRequest(
      categoryIds: null,
      searchQuery: '',
      brandIds: const [],
      specFilters: null,
      minPrice: null,
      maxPrice: null,
      onlyInStock: true,
      sortBy: 'name',
      limit: 20,
      offset: 0,
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
          case 'get_public_storefront_shell_v1':
            body = <String, Object?>{};
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
