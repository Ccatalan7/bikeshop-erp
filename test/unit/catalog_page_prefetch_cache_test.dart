import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/catalog_page_prefetch_cache.dart';

void main() {
  group('CatalogPagePrefetchCache', () {
    test('deduplicates concurrent page loads and reuses the result', () async {
      final cache = CatalogPagePrefetchCache<String>();
      final completer = Completer<String>();
      var loadCount = 0;

      Future<String> loader() {
        loadCount++;
        return completer.future;
      }

      final first = cache.load(
        signature: 'products',
        pageNumber: 2,
        loader: loader,
      );
      final second = cache.load(
        signature: 'products',
        pageNumber: 2,
        loader: loader,
      );

      expect(loadCount, 1);
      expect(cache.inFlightCount, 1);

      completer.complete('page two');
      expect(await first, 'page two');
      expect(await second, 'page two');
      expect(cache.inFlightCount, 0);

      expect(
        await cache.load(
          signature: 'products',
          pageNumber: 2,
          loader: loader,
        ),
        'page two',
      );
      expect(loadCount, 1);
    });

    test('does not let an old signature repopulate the active cache', () async {
      final cache = CatalogPagePrefetchCache<String>();
      final staleCompleter = Completer<String>();

      final stale = cache.load(
        signature: 'search=old',
        pageNumber: 2,
        loader: () => staleCompleter.future,
      );
      expect(
        await cache.load(
          signature: 'search=new',
          pageNumber: 1,
          loader: () async => 'new result',
        ),
        'new result',
      );

      staleCompleter.complete('stale result');
      expect(await stale, 'stale result');
      expect(
        cache.peek(signature: 'search=new', pageNumber: 2),
        isNull,
      );
      expect(
        cache.peek(signature: 'search=new', pageNumber: 1),
        'new result',
      );
    });

    test('expires entries and evicts the least recently used page', () async {
      var now = DateTime(2026, 7, 26, 12);
      final cache = CatalogPagePrefetchCache<String>(
        maxAge: const Duration(seconds: 30),
        maxEntries: 2,
        now: () => now,
      );

      await cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () async => 'one',
      );
      await cache.load(
        signature: 'products',
        pageNumber: 2,
        loader: () async => 'two',
      );
      expect(cache.peek(signature: 'products', pageNumber: 1), 'one');

      await cache.load(
        signature: 'products',
        pageNumber: 3,
        loader: () async => 'three',
      );
      expect(cache.peek(signature: 'products', pageNumber: 2), isNull);
      expect(cache.peek(signature: 'products', pageNumber: 1), 'one');

      now = now.add(const Duration(seconds: 30));
      expect(cache.peek(signature: 'products', pageNumber: 1), isNull);
      expect(cache.cachedPageCount, 1);
    });

    test('retains a soft-expired page while one origin refresh replaces it',
        () async {
      var now = DateTime(2026, 7, 26, 12);
      final cache = CatalogPagePrefetchCache<String>(
        maxAge: const Duration(seconds: 5),
        retainFor: const Duration(minutes: 10),
        now: () => now,
      );
      var loads = 0;

      expect(
        await cache.load(
          signature: 'products',
          pageNumber: 1,
          loader: () async {
            loads++;
            return 'old';
          },
        ),
        'old',
      );

      now = now.add(const Duration(seconds: 6));
      expect(cache.peek(signature: 'products', pageNumber: 1), 'old');
      expect(
        cache.isFresh(signature: 'products', pageNumber: 1),
        isFalse,
      );

      final gate = Completer<String>();
      final first = cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () {
          loads++;
          return gate.future;
        },
      );
      final second = cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () async => 'duplicate',
      );

      expect(cache.peek(signature: 'products', pageNumber: 1), 'old');
      expect(loads, 2);
      gate.complete('new');
      expect(await first, 'new');
      expect(await second, 'new');
      expect(cache.peek(signature: 'products', pageNumber: 1), 'new');
    });

    test('markStale retains paint data and forces the next load', () async {
      final cache = CatalogPagePrefetchCache<String>(
        maxAge: const Duration(minutes: 1),
        retainFor: const Duration(minutes: 10),
      );
      var loads = 0;

      await cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () async {
          loads++;
          return 'one';
        },
      );
      cache.markStale(signature: 'products');

      expect(cache.peek(signature: 'products', pageNumber: 1), 'one');
      expect(
        await cache.load(
          signature: 'products',
          pageNumber: 1,
          loader: () async {
            loads++;
            return 'two';
          },
        ),
        'two',
      );
      expect(loads, 2);
    });

    test(
        'markStale detaches an in-flight request and blocks stale repopulation',
        () async {
      final cache = CatalogPagePrefetchCache<String>();
      final staleCompleter = Completer<String>();
      final freshCompleter = Completer<String>();
      var loads = 0;

      final stale = cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () {
          loads++;
          return staleCompleter.future;
        },
      );

      cache.markStale(signature: 'products');
      expect(cache.inFlightCount, 0);

      final fresh = cache.load(
        signature: 'products',
        pageNumber: 1,
        loader: () {
          loads++;
          return freshCompleter.future;
        },
      );
      expect(loads, 2);
      expect(cache.inFlightCount, 1);

      staleCompleter.complete('stale');
      expect(await stale, 'stale');
      expect(cache.peek(signature: 'products', pageNumber: 1), isNull);
      expect(cache.inFlightCount, 1);

      freshCompleter.complete('fresh');
      expect(await fresh, 'fresh');
      expect(cache.peek(signature: 'products', pageNumber: 1), 'fresh');
      expect(cache.inFlightCount, 0);
    });

    test('failed loads are retried instead of cached', () async {
      final cache = CatalogPagePrefetchCache<String>();
      var attempts = 0;

      Future<String> loader() async {
        attempts++;
        if (attempts == 1) throw StateError('temporary failure');
        return 'recovered';
      }

      await expectLater(
        cache.load(
          signature: 'products',
          pageNumber: 2,
          loader: loader,
        ),
        throwsStateError,
      );
      expect(cache.inFlightCount, 0);
      expect(
        await cache.load(
          signature: 'products',
          pageNumber: 2,
          loader: loader,
        ),
        'recovered',
      );
      expect(attempts, 2);
    });

    test('values rejected by the cache policy are fetched again', () async {
      var attempts = 0;
      final cache = CatalogPagePrefetchCache<String>(
        shouldCache: (value) => value != 'unavailable',
      );

      expect(
        await cache.load(
          signature: 'facets',
          pageNumber: 1,
          loader: () async {
            attempts++;
            return 'unavailable';
          },
        ),
        'unavailable',
      );
      expect(cache.cachedPageCount, 0);

      expect(
        await cache.load(
          signature: 'facets',
          pageNumber: 1,
          loader: () async {
            attempts++;
            return 'available';
          },
        ),
        'available',
      );
      expect(attempts, 2);
      expect(cache.cachedPageCount, 1);
    });
  });
}
