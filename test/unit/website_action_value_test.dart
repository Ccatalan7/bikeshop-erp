import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  test('standalone button style wins over a stale structured variant', () {
    final action = WebsiteActionValue.resolvePrimary(
      const <String, dynamic>{
        'label': 'Comprar',
        'link': '/comprar',
        'style': 'outline',
        'actions': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'navigate',
            'label': 'Comprar',
            'to': '/comprar',
            'variant': 'filled',
          },
        ],
      },
      labelKeys: const ['label', 'text'],
      hrefKeys: const ['link'],
      variantKeys: const ['style'],
    );

    expect(action, isNotNull);
    expect(action!.variant, WebsiteActionVariant.outline);
  });

  test('structured variant remains authoritative without visible aliases', () {
    final action = WebsiteActionValue.resolvePrimary(
      const <String, dynamic>{
        'actions': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'navigate',
            'label': 'Comprar',
            'to': '/comprar',
            'variant': 'text',
          },
        ],
      },
      labelKeys: const ['label', 'text'],
      hrefKeys: const ['link'],
      variantKeys: const ['style'],
    );

    expect(action, isNotNull);
    expect(action!.variant, WebsiteActionVariant.text);
  });

  test('button aliases and structured action update in one history entry', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'button-1',
            'block_type': 'button',
            'block_data': <String, dynamic>{
              'label': 'Anterior',
              'text': 'Anterior',
              'link': '/anterior',
              'style': 'filled',
              'actions': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'navigate',
                  'label': 'Anterior',
                  'to': '/anterior',
                  'variant': 'filled',
                },
              ],
            },
          },
        ],
        const <String, dynamic>{},
      );
    addTearDown(provider.dispose);

    const nextAction = WebsiteActionValue(
      label: 'Comprar ahora',
      href: '/comprar',
      variant: WebsiteActionVariant.outline,
    );
    provider.updateBlockDataMultiple(
      'button-1',
      <String, dynamic>{
        'label': nextAction.label,
        'text': nextAction.label,
        'link': nextAction.href,
        'style': nextAction.variant.storageValue,
        'actions': WebsiteActionValue.mergePrimary(
          provider.blocks.single['block_data']['actions'],
          nextAction,
        ),
      },
    );

    final data = Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
    final action = Map<String, dynamic>.from(
      (data['actions'] as List).single as Map,
    );
    expect(data['label'], 'Comprar ahora');
    expect(data['text'], 'Comprar ahora');
    expect(data['link'], '/comprar');
    expect(data['style'], 'outline');
    expect(action['label'], 'Comprar ahora');
    expect(action['to'], '/comprar');
    expect(action['variant'], 'outline');
    expect(provider.canUndo, isTrue);

    provider.undo();
    final restored = Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
    expect(restored['label'], 'Anterior');
    expect(restored['style'], 'filled');
    expect(provider.canUndo, isFalse);
  });
}
