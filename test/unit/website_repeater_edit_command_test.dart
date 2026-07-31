import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  WebsiteEditModeProvider documentWith(Map<String, dynamic> data) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        [
          {
            'id': 'block-1',
            'block_type': 'stats',
            'block_data': data,
            'order_index': 0,
          },
        ],
        const {},
      );
  }

  Map<String, dynamic> blockData(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );

  test('nested item aliases update in one notification and one undo step', () {
    final provider = documentWith({
      'metrics': [
        {'value': '10', 'label': 'Antes'},
      ],
    });
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    expect(
      provider.updateBlockRepeaterItemMultiple(
        'block-1',
        collectionKeys: const ['metrics', 'stats', 'items'],
        itemIndex: 0,
        updates: const {
          'label': 'Después',
          'labelFormatting': {'bold': true},
        },
      ),
      isTrue,
    );

    final updated = blockData(provider);
    expect(updated['metrics'], updated['stats']);
    expect(updated['metrics'], updated['items']);
    expect(
      (updated['metrics'] as List).single,
      {
        'value': '10',
        'label': 'Después',
        'labelFormatting': {'bold': true},
      },
    );
    expect(notifications, 1);
    expect(provider.canUndo, isTrue);

    provider.undo();

    expect(blockData(provider), {
      'metrics': [
        {'value': '10', 'label': 'Antes'},
      ],
    });
    expect(provider.canUndo, isFalse);
  });

  test('each nested write resolves the latest document collection', () {
    final provider = documentWith({
      'metrics': [
        {'value': '10', 'label': 'Antes'},
      ],
    });
    addTearDown(provider.dispose);

    provider.updateBlockRepeaterItemMultiple(
      'block-1',
      collectionKeys: const ['metrics', 'stats', 'items'],
      itemIndex: 0,
      updates: const {'value': '20'},
    );
    provider.updateBlockRepeaterItemMultiple(
      'block-1',
      collectionKeys: const ['metrics', 'stats', 'items'],
      itemIndex: 0,
      updates: const {'label': 'Después'},
    );

    expect(
      (blockData(provider)['metrics'] as List).single,
      {'value': '20', 'label': 'Después'},
    );
  });

  test('an explicit empty canonical collection wins over stale aliases', () {
    final provider = documentWith({
      'metrics': const <Map<String, dynamic>>[],
      'stats': [
        {'value': 'stale', 'label': 'No publicar'},
      ],
    });
    addTearDown(provider.dispose);
    var notifications = 0;
    provider.addListener(() => notifications++);

    expect(
      provider.updateBlockRepeaterItemMultiple(
        'block-1',
        collectionKeys: const ['metrics', 'stats', 'items'],
        itemIndex: 0,
        updates: const {'label': 'No debe escribirse'},
      ),
      isFalse,
    );

    expect(notifications, 0);
    expect(provider.canUndo, isFalse);
    expect(blockData(provider)['stats'], [
      {'value': 'stale', 'label': 'No publicar'},
    ]);
  });

  test('persisted identity resolves the intended item after a reorder', () {
    final provider = documentWith({
      'metrics': [
        {'id': 'metric-a', 'value': '1', 'label': 'A'},
        {'id': 'metric-b', 'value': '2', 'label': 'B'},
      ],
    });
    addTearDown(provider.dispose);

    expect(
      provider.updateBlockRepeaterItemMultiple(
        'block-1',
        collectionKeys: const ['metrics'],
        itemIndex: 0,
        identityKey: 'id',
        identityValue: 'metric-b',
        updates: const {'label': 'B editada'},
      ),
      isTrue,
    );

    final metrics = blockData(provider)['metrics'] as List;
    expect(metrics.first['label'], 'A');
    expect(metrics.last['label'], 'B editada');
  });
}
