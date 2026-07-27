import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';

void main() {
  CachedPageSnapshot snapshot(String slug, int revision) {
    final now = DateTime(2026, 7, 26);
    return CachedPageSnapshot(
      page: WebsitePage(
        id: 'page-$slug',
        tenantId: 'tenant-a',
        slug: slug,
        title: 'Page $slug',
        isPublished: true,
        createdAt: now,
        updatedAt: now,
      ),
      blocks: [
        {
          'id': 'block-$revision',
          'page_id': 'page-$slug',
          'tenant_id': 'tenant-a',
          'block_type': 'text',
          'block_data': {'revision': revision},
          'is_visible': true,
          'order_index': 0,
        },
      ],
    );
  }

  int revisionOf(CachedPageSnapshot? value) =>
      (value!.blocks.single['block_data'] as Map)['revision'] as int;

  test('public settings cache rejects credential-like legacy keys', () {
    final filtered = filterPublicWebsiteSettingsForCache({
      'store_name': 'Viña Bike',
      'primary_color': '#112233',
      'mercadopago_access_token': 'must-not-render',
      'provider-api-key': 'must-not-render',
      'refreshToken': 'must-not-render',
      'private_note': 'must-not-render',
    });

    expect(filtered, {
      'store_name': 'Viña Bike',
      'primary_color': '#112233',
    });
    expect(isPublicWebsiteSettingCacheSafe('hero_title'), isTrue);
    expect(isPublicWebsiteSettingCacheSafe('clientSecret'), isFalse);
  });

  test('deduplicates concurrent origin revalidation for the same key',
      () async {
    final cache = WebsitePageSnapshotCache();
    final gate = Completer<CachedPageSnapshot?>();
    var loads = 0;

    final first = cache.revalidate('tenant-a\u0000envios', () {
      loads += 1;
      return gate.future;
    });
    final second = cache.revalidate('tenant-a\u0000envios', () async {
      loads += 1;
      return snapshot('envios', 99);
    });

    expect(identical(first, second), isTrue);
    expect(loads, 1);

    gate.complete(snapshot('envios', 1));
    expect(revisionOf(await first), 1);
    expect(revisionOf(await second), 1);
    expect(revisionOf(cache.peek('tenant-a\u0000envios')), 1);
  });

  test('invalidated old response cannot overwrite a newer snapshot', () async {
    final cache = WebsitePageSnapshotCache();
    final oldGate = Completer<CachedPageSnapshot?>();
    final oldLoad = cache.revalidate(
      'tenant-a\u0000privacidad',
      () => oldGate.future,
    );

    cache.invalidateKey('tenant-a\u0000privacidad');
    final newLoad = cache.revalidate(
      'tenant-a\u0000privacidad',
      () async => snapshot('privacidad', 2),
    );
    expect(revisionOf(await newLoad), 2);

    oldGate.complete(snapshot('privacidad', 1));
    expect(revisionOf(await oldLoad), 2);
    expect(revisionOf(cache.peek('tenant-a\u0000privacidad')), 2);
  });

  test('retention is bounded and least recently used entry is evicted',
      () async {
    final cache = WebsitePageSnapshotCache(capacity: 2);
    await cache.revalidate('tenant-a\u0000a', () async => snapshot('a', 1));
    await cache.revalidate('tenant-a\u0000b', () async => snapshot('b', 2));

    // Touch A so B becomes the least recently used entry.
    expect(cache.peek('tenant-a\u0000a'), isNotNull);
    await cache.revalidate('tenant-b\u0000a', () async => snapshot('a', 3));

    expect(cache.length, 2);
    expect(cache.peek('tenant-a\u0000a'), isNotNull);
    expect(cache.peek('tenant-a\u0000b'), isNull);
    expect(cache.peek('tenant-b\u0000a'), isNotNull);
  });

  test('returned block maps cannot mutate the retained snapshot', () async {
    final cache = WebsitePageSnapshotCache();
    final loaded = await cache.revalidate(
      'tenant-a\u0000terminos',
      () async => snapshot('terminos', 4),
    );

    loaded!.blocks.single['id'] = 'mutated';
    (loaded.blocks.single['block_data'] as Map)['revision'] = 100;

    final retained = cache.peek('tenant-a\u0000terminos');
    expect(retained!.blocks.single['id'], 'block-4');
    expect(revisionOf(retained), 4);
  });

  test('soft-expired page remains paintable while no longer fresh', () async {
    final cache = WebsitePageSnapshotCache(
      ttl: const Duration(microseconds: -1),
      retainFor: const Duration(hours: 1),
    );
    await cache.revalidate(
      'tenant-a\u0000terminos',
      () async => snapshot('terminos', 4),
    );

    expect(cache.isFresh('tenant-a\u0000terminos'), isFalse);
    expect(cache.peek('tenant-a\u0000terminos'), isNotNull);
  });

  test('deep nested block data cannot poison the retained snapshot', () async {
    final nested = snapshot('terminos', 4);
    nested.blocks.single['block_data'] = {
      'slides': [
        {
          'title': 'original',
          'items': ['one']
        }
      ]
    };
    final cache = WebsitePageSnapshotCache();
    final loaded = await cache.revalidate(
      'tenant-a\u0000terminos',
      () async => nested,
    );

    final slides =
        (loaded!.blocks.single['block_data'] as Map)['slides'] as List;
    (slides.single as Map)['title'] = 'mutated';
    ((slides.single as Map)['items'] as List).add('two');

    final retained = cache.peek('tenant-a\u0000terminos')!;
    final retainedSlides =
        (retained.blocks.single['block_data'] as Map)['slides'] as List;
    expect((retainedSlides.single as Map)['title'], 'original');
    expect((retainedSlides.single as Map)['items'], ['one']);
  });
}
