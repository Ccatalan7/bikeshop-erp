import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  Map<String, dynamic> block(Map<String, dynamic> data) => <String, dynamic>{
        'id': 'block-1',
        'block_type': 'carousel',
        'block_data': data,
        'sort_order': 0,
      };

  WebsiteEditModeProvider providerFor(
    Map<String, dynamic> data, {
    String pageId = 'page-a',
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[block(data)],
        const <String, dynamic>{},
        pageId: pageId,
        pageSlug: pageId,
      )
      ..selectBlock('block-1');
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );

  List<Map<String, dynamic>> listOf(
    WebsiteEditModeProvider provider,
    String key,
  ) =>
      (dataOf(provider)[key] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  WebsiteRepeaterCollectionTarget slidesTarget({
    int? minItems,
    int? maxItems,
  }) =>
      WebsiteRepeaterCollectionTarget(
        blockId: 'block-1',
        collectionKeys: const <String>['slides'],
        minItems: minItems,
        maxItems: maxItems,
      );

  WebsiteRepeaterItemRef persisted(String id, int index) =>
      WebsiteRepeaterItemRef.persisted(
        fallbackIndex: index,
        identityKey: 'id',
        identityValue: id,
      );

  test('one lease commits once, creates one undo and then rejects reuse', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    });
    addTearDown(provider.dispose);
    final before = dataOf(provider);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;
    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterAddItem(const <String, dynamic>{'title': 'B'}),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.committed);
    expect(outcome.selectionIndex, 1);
    expect(listOf(provider, 'slides').length, 2);
    expect(notifications, 1);
    expect(provider.canUndo, isTrue);

    expect(
      provider
          .commitRepeaterMutation(
            lease,
            const WebsiteRepeaterDeleteItem(
              WebsiteRepeaterItemRef.index(1),
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(notifications, 1, reason: 'reuse is zero-write');

    provider.undo();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  test('capture and abandoned/cancelled intent have zero side effects', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    });
    addTearDown(provider.dispose);
    final before = dataOf(provider);
    final dirty = provider.hasUnsavedChanges;
    final navigationRevision = provider.navigationStateRevision;
    var notifications = 0;
    provider.addListener(() => notifications++);

    expect(provider.captureRepeaterMutationLease(slidesTarget()), isNotNull);

    expect(dataOf(provider), before);
    expect(provider.hasUnsavedChanges, dirty);
    expect(provider.canUndo, isFalse);
    expect(provider.navigationStateRevision, navigationRevision);
    expect(notifications, 0);
  });

  test('page/session ABA rejects an old callback with the same ids and bytes',
      () {
    final source = <String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    };
    final provider = providerFor(source);
    addTearDown(provider.dispose);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;

    provider
      ..enterEditMode(
        <Map<String, dynamic>>[block(source)],
        const <String, dynamic>{},
        pageId: 'page-b',
        pageSlug: 'page-b',
      )
      ..selectBlock('block-1');
    final before = dataOf(provider);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterAddItem(
        const <String, dynamic>{'title': 'redirected'},
      ),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.rejected);
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
    expect(notifications, 0);
  });

  test('reopening the same page and bytes rejects the previous session', () {
    final source = <String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    };
    final provider = providerFor(source);
    addTearDown(provider.dispose);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;

    provider
      ..enterEditMode(
        <Map<String, dynamic>>[block(source)],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      )
      ..selectBlock('block-1');
    final before = dataOf(provider);

    expect(
      provider
          .commitRepeaterMutation(
            lease,
            WebsiteRepeaterAddItem(
              const <String, dynamic>{'title': 'redirected'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  test('byte-identical edit then undo ABA still rejects by document epoch', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
      'title': 'Original',
    });
    addTearDown(provider.dispose);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;
    final original = dataOf(provider);

    provider.updateBlockData('block-1', 'title', 'Intermedio');
    provider.undo();
    expect(dataOf(provider), original, reason: 'A→B→A is byte-identical');
    var notifications = 0;
    provider.addListener(() => notifications++);

    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterPatchItem(
        target: const WebsiteRepeaterItemRef.persisted(
          fallbackIndex: 0,
          identityKey: 'id',
          identityValue: 'a',
        ),
        updates: const <String, dynamic>{'title': 'stale'},
      ),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.rejected);
    expect(dataOf(provider), original);
    expect(notifications, 0);
  });

  test('source edit or reorder rejects stale patch without clobbering it', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
        {'id': 'b', 'title': 'B'},
      ],
    });
    addTearDown(provider.dispose);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;

    provider.updateBlockData('block-1', 'slides', <Map<String, dynamic>>[
      {'id': 'b', 'title': 'B nuevo'},
      {'id': 'a', 'title': 'A'},
    ]);
    final afterExternalWrite = dataOf(provider);
    var notifications = 0;
    provider.addListener(() => notifications++);

    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterPatchItem(
        target: persisted('a', 0),
        updates: const <String, dynamic>{'title': 'stale'},
      ),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.rejected);
    expect(dataOf(provider), afterExternalWrite);
    expect(notifications, 0);
  });

  test('move resolves source and anchor identities and undoes once', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
        {'id': 'b', 'title': 'B'},
        {'id': 'c', 'title': 'C'},
      ],
    });
    addTearDown(provider.dispose);
    final before = dataOf(provider);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;

    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterMoveItem(
        source: persisted('a', 0),
        anchor: persisted('c', 2),
        placement: WebsiteRepeaterMovePlacement.after,
      ),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.committed);
    expect(
      listOf(provider, 'slides').map((item) => item['id']),
      <String>['b', 'c', 'a'],
    );
    expect(outcome.selectionIndex, 2);
    provider.undo();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  test('missing, omitted and duplicate persisted identities fail closed', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
        {'id': 'b', 'title': 'B'},
      ],
    });
    addTearDown(provider.dispose);
    final before = dataOf(provider);

    final missingLease = provider.captureRepeaterMutationLease(slidesTarget())!;
    expect(
      provider
          .commitRepeaterMutation(
            missingLease,
            WebsiteRepeaterDeleteItem(persisted('missing', 0)),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );

    final omittedLease = provider.captureRepeaterMutationLease(slidesTarget())!;
    expect(
      provider
          .commitRepeaterMutation(
            omittedLease,
            const WebsiteRepeaterDeleteItem(
              WebsiteRepeaterItemRef.index(0),
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
      reason: 'an item with id cannot be addressed as index-only',
    );
    expect(dataOf(provider), before);

    provider.updateBlockData('block-1', 'slides', <Map<String, dynamic>>[
      {'id': 'dup', 'title': 'A'},
      {'id': 'dup', 'title': 'B'},
    ]);
    expect(
      provider.captureRepeaterMutationLease(slidesTarget()),
      isNull,
      reason: 'ambiguous source is rejected at capture',
    );
  });

  test('identityless fallback is exact-source protected', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'title': 'A'},
        {'title': 'B'},
      ],
    });
    addTearDown(provider.dispose);
    var lease = provider.captureRepeaterMutationLease(slidesTarget())!;

    expect(
      provider
          .commitRepeaterMutation(
            lease,
            WebsiteRepeaterPatchItem(
              target: const WebsiteRepeaterItemRef.index(1),
              updates: const <String, dynamic>{'title': 'B editado'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.committed,
    );
    expect(listOf(provider, 'slides')[1]['title'], 'B editado');

    lease = provider.captureRepeaterMutationLease(slidesTarget())!;
    provider.updateBlockData('block-1', 'slides', <Map<String, dynamic>>[
      {'title': 'B editado'},
      {'title': 'A'},
    ]);
    final external = dataOf(provider);
    expect(
      provider
          .commitRepeaterMutation(
            lease,
            WebsiteRepeaterPatchItem(
              target: const WebsiteRepeaterItemRef.index(1),
              updates: const <String, dynamic>{'title': 'stale'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(dataOf(provider), external);
  });

  test('unchanged consumes its lease without history and allows recapture', () {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    });
    addTearDown(provider.dispose);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;
    final command = WebsiteRepeaterPatchItem(
      target: persisted('a', 0),
      updates: const <String, dynamic>{'title': 'A'},
    );

    expect(
      provider.commitRepeaterMutation(lease, command).result,
      WebsiteRepeaterMutationResult.unchanged,
    );
    expect(provider.canUndo, isFalse);
    expect(
      provider.commitRepeaterMutation(lease, command).result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(provider.captureRepeaterMutationLease(slidesTarget()), isNotNull);
  });

  test('nested ancestor identity mutates only its collection and aliases', () {
    final provider = providerFor(<String, dynamic>{
      'columns': <Map<String, dynamic>>[
        {
          'id': 'col-a',
          'title': 'A',
          'items': <Map<String, dynamic>>[
            {'id': 'link-a', 'label': 'Uno', 'link': '/uno'},
          ],
          'links': <Map<String, dynamic>>[
            {'id': 'link-a', 'label': 'Uno', 'link': '/uno'},
          ],
        },
        {
          'id': 'col-b',
          'title': 'B',
          'items': <Map<String, dynamic>>[
            {'id': 'link-b', 'label': 'Dos', 'link': '/dos'},
          ],
        },
      ],
    });
    addTearDown(provider.dispose);
    final target = WebsiteRepeaterCollectionTarget(
      blockId: 'block-1',
      ancestors: <WebsiteRepeaterAncestorRef>[
        WebsiteRepeaterAncestorRef(
          collectionKeys: const <String>['columns'],
          item: persisted('col-a', 0),
        ),
      ],
      collectionKeys: const <String>['items', 'links'],
    );
    final before = dataOf(provider);
    final lease = provider.captureRepeaterMutationLease(target)!;

    final outcome = provider.commitRepeaterMutation(
      lease,
      WebsiteRepeaterPatchItem(
        target: persisted('link-a', 0),
        updates: const <String, dynamic>{
          'label': 'Uno editado',
          'link': '/nuevo',
        },
      ),
    );

    expect(outcome.result, WebsiteRepeaterMutationResult.committed);
    final columns = listOf(provider, 'columns');
    expect((columns[0]['items'] as List).single['label'], 'Uno editado');
    expect(columns[0]['items'], columns[0]['links']);
    expect((columns[1]['items'] as List).single['label'], 'Dos');
    provider.undo();
    expect(dataOf(provider), before);
  });

  test('nested ancestor reorder or sibling edit rejects the old lease', () {
    final provider = providerFor(<String, dynamic>{
      'columns': <Map<String, dynamic>>[
        {
          'id': 'col-a',
          'title': 'A',
          'items': <Map<String, dynamic>>[
            {'id': 'link-a', 'label': 'Uno'},
          ],
        },
        {
          'id': 'col-b',
          'title': 'B',
          'items': <Map<String, dynamic>>[
            {'id': 'link-b', 'label': 'Dos'},
          ],
        },
      ],
    });
    addTearDown(provider.dispose);
    final target = WebsiteRepeaterCollectionTarget(
      blockId: 'block-1',
      ancestors: <WebsiteRepeaterAncestorRef>[
        WebsiteRepeaterAncestorRef(
          collectionKeys: const <String>['columns'],
          item: persisted('col-a', 0),
        ),
      ],
      collectionKeys: const <String>['items'],
    );
    final lease = provider.captureRepeaterMutationLease(target)!;
    final changed = listOf(provider, 'columns');
    changed[1]['title'] = 'B cambió';
    provider.updateBlockData('block-1', 'columns', changed);
    final afterExternalWrite = dataOf(provider);

    expect(
      provider
          .commitRepeaterMutation(
            lease,
            WebsiteRepeaterPatchItem(
              target: persisted('link-a', 0),
              updates: const <String, dynamic>{'label': 'stale'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(dataOf(provider), afterExternalWrite);
  });

  test('nested ancestor reorder rejects the old child lease', () {
    final provider = providerFor(<String, dynamic>{
      'columns': <Map<String, dynamic>>[
        {
          'id': 'col-a',
          'items': <Map<String, dynamic>>[
            {'id': 'link-a', 'label': 'Uno'},
          ],
        },
        {
          'id': 'col-b',
          'items': <Map<String, dynamic>>[
            {'id': 'link-b', 'label': 'Dos'},
          ],
        },
      ],
    });
    addTearDown(provider.dispose);
    final target = WebsiteRepeaterCollectionTarget(
      blockId: 'block-1',
      ancestors: <WebsiteRepeaterAncestorRef>[
        WebsiteRepeaterAncestorRef(
          collectionKeys: const <String>['columns'],
          item: persisted('col-a', 0),
        ),
      ],
      collectionKeys: const <String>['items'],
    );
    final lease = provider.captureRepeaterMutationLease(target)!;
    final columns = listOf(provider, 'columns').reversed.toList();
    provider.updateBlockData('block-1', 'columns', columns);
    final reordered = dataOf(provider);

    expect(
      provider
          .commitRepeaterMutation(
            lease,
            WebsiteRepeaterPatchItem(
              target: persisted('link-a', 0),
              updates: const <String, dynamic>{'label': 'stale'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(dataOf(provider), reordered);
  });

  test('async carousel completion cannot redirect to a later selection',
      () async {
    final provider = providerFor(<String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A', 'videoFileUrl': ''},
        {'id': 'b', 'title': 'B', 'videoFileUrl': ''},
      ],
    });
    addTearDown(provider.dispose);
    provider.selectCarouselSlide('block-1', 0, 2);
    final lease = provider.captureRepeaterMutationLease(slidesTarget())!;
    final uploadFinished = Completer<String>();

    final completion = () async {
      final url = await uploadFinished.future;
      return provider.commitRepeaterMutation(
        lease,
        WebsiteRepeaterPatchItem(
          target: persisted('a', 0),
          updates: <String, dynamic>{
            'videoFileUrl': url,
            'videoUrl': '',
          },
        ),
      );
    }();

    provider.selectCarouselSlide('block-1', 1, 2);
    uploadFinished.complete('https://cdn.example/video.mp4');
    final outcome = await completion;

    expect(outcome.result, WebsiteRepeaterMutationResult.rejected);
    final slides = listOf(provider, 'slides');
    expect(slides[0]['videoFileUrl'], '');
    expect(slides[1]['videoFileUrl'], '');
    expect(provider.canUndo, isFalse);
  });

  test('Carousel upload captures before await and never reads live selection',
      () {
    final source = File(
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _uploadSlideVideoFile(');
    final end = source.indexOf(
      "/// The active slide's image and framing",
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    final capture = method.indexOf('captureRepeaterMutationLease(target)');
    final firstAwait = method.indexOf('await FilePicker.platform.pickFiles');
    final commit = method.indexOf('commitRepeaterMutation(');
    expect(capture, inInclusiveRange(0, firstAwait - 1));
    expect(commit, greaterThan(firstAwait));
    expect(method, contains('target: slideRef'));
    final executable = method.replaceAll(RegExp(r'//[^\n]*'), '');
    expect(executable, isNot(contains('_selectedSlideIndex')));
    expect(executable, isNot(contains('updateBlockData(')));
  });

  test('Schema and Carousel expose commands, not whole-list writer bridges',
      () {
    final schema = File(
      'lib/modules/website/widgets/editor_panel/schema_controls.dart',
    ).readAsStringSync();
    final schemaOwnerStart = schema.indexOf('class _SchemaRepeaterEditor ');
    final schemaOwnerEnd = schema.indexOf(
      'class _SchemaRepeaterEditorState',
      schemaOwnerStart,
    );
    expect(schemaOwnerStart, greaterThanOrEqualTo(0));
    expect(schemaOwnerEnd, greaterThan(schemaOwnerStart));
    final schemaOwner = schema.substring(schemaOwnerStart, schemaOwnerEnd);
    expect(schemaOwner, contains('WebsiteRepeaterCollectionTarget target'));
    expect(schemaOwner, contains('_RepeaterCommandCallback onCommand'));
    expect(schemaOwner, isNot(contains('onChanged')));
    expect(schema, isNot(contains('widget.onChanged')));
    expect(schema, contains('WebsiteRepeaterMoveItem('));

    final carousel = File(
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
    ).readAsStringSync();
    final legacyStart = carousel.indexOf('/// Individual slide editor');
    expect(legacyStart, greaterThan(0));
    final activeCarousel = carousel.substring(0, legacyStart);
    expect(activeCarousel, contains('commitRepeaterMutation('));
    expect(activeCarousel, isNot(contains('_updateSlides(')));
    expect(activeCarousel, isNot(contains('_updateSlide(')));
    expect(activeCarousel, isNot(contains('_updateSlideMultiple(')));
    expect(
      activeCarousel,
      isNot(
        matches(
          RegExp(
            r'''updateBlockData(?:Multiple)?\([\s\S]*?["']slides["']''',
          ),
        ),
      ),
    );
  });

  test('lease from another provider is rejected with identical state', () {
    final source = <String, dynamic>{
      'slides': <Map<String, dynamic>>[
        {'id': 'a', 'title': 'A'},
      ],
    };
    final providerA = providerFor(source);
    final providerB = providerFor(source);
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    final beforeA = dataOf(providerA);
    final beforeB = dataOf(providerB);
    final lease = providerA.captureRepeaterMutationLease(slidesTarget());

    expect(lease, isNotNull);
    expect(
      providerB
          .commitRepeaterMutation(
            lease!,
            WebsiteRepeaterAddItem(
              const <String, dynamic>{'title': 'Redirigido'},
            ),
          )
          .result,
      WebsiteRepeaterMutationResult.rejected,
    );
    expect(dataOf(providerA), beforeA);
    expect(dataOf(providerB), beforeB);
    expect(providerA.canUndo, isFalse);
    expect(providerB.canUndo, isFalse);
  });
}
