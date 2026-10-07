import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_html_draft_picks.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_field_binding.dart';

WebsiteEditModeProvider _provider(String type, Map<String, dynamic> data) {
  return WebsiteEditModeProvider()
    ..enterEditMode(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'b1',
          'block_type': type,
          'block_data': data,
          'is_visible': true,
          'sort_order': 0,
        },
      ],
      const <String, dynamic>{},
      pageId: 'page-a',
      pageSlug: '/inicio',
    )
    ..selectBlock('b1')
    ..setDevicePreviewMode(DevicePreviewMode.desktop)
    ..reportRenderedBlockViewport('b1', WebsiteViewport.desktop);
}

Map<String, dynamic> _data(WebsiteEditModeProvider provider) =>
    Map<String, dynamic>.from(provider.getBlock('b1')!['block_data'] as Map);

WebsiteInlineFieldBinding _fields(
  WebsiteEditModeProvider provider,
  String type,
) =>
    WebsiteInlineFieldBinding(
      provider: provider,
      blockId: 'b1',
      blockType: type,
    );

final _firstQuestion = WebsiteInlineRepeaterTarget(
  collectionKeys: ['items'],
  itemIndex: 0,
);

void main() {
  group('the field a text of the HTML view names', () {
    test('its keys and, in a list, the list and the item', () {
      final title = WebsiteHtmlDraftTextField.parse('title')!;
      expect(title.keys, ['title']);
      expect(title.collectionKeys, isEmpty);

      final subtitle = WebsiteHtmlDraftTextField.parse('subtitle,description')!;
      expect(subtitle.keys, ['subtitle', 'description']);

      final feature =
          WebsiteHtmlDraftTextField.parse('title@features,items#3')!;
      expect(feature.keys, ['title']);
      expect(feature.collectionKeys, ['features', 'items']);
      expect(feature.index, 3);
      expect(feature.spec, 'title@features,items#3');
    });

    test('anything else is no field', () {
      for (final spec in [
        '',
        'a b',
        'title@items',
        'title@items#-1',
        'title@items#x',
        '<script>',
        'title,',
        '__proto__.x',
        'x' * 201,
      ]) {
        expect(WebsiteHtmlDraftTextField.parse(spec), isNull, reason: spec);
      }
    });
  });

  group('what the page tells the editor', () {
    test('through the web view handlers', () {
      expect(
        WebsiteHtmlDraftMessage.fromHandler('vbDraftPick', ['b1']),
        isA<WebsiteHtmlDraftPick>().having((m) => m.id, 'id', 'b1'),
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler('vbDraftPick', [null]),
        isA<WebsiteHtmlDraftPick>().having((m) => m.id, 'id', isNull),
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler('vbDraftAction', ['b1', 'up']),
        isA<WebsiteHtmlDraftAction>().having((m) => m.action, 'action', 'up'),
      );
      final commit = WebsiteHtmlDraftMessage.fromHandler(
        'vbDraftEdit',
        ['b1', 'question@items#0', 'commit', '¿Arman bicis?'],
      )! as WebsiteHtmlDraftEdit;
      expect(commit.step, WebsiteHtmlDraftEditStep.commit);
      expect(commit.field.collectionKeys, ['items']);
      expect(commit.text, '¿Arman bicis?');
      // A written text may be empty; a commit without one is no message.
      expect(
        (WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'commit', ''],
        )! as WebsiteHtmlDraftEdit)
            .text,
        '',
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'commit', null],
        ),
        isNull,
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'erase', null],
        ),
        isNull,
      );
      expect(WebsiteHtmlDraftMessage.fromHandler('other', ['b1']), isNull);
    });

    test('as a frame message, the same', () {
      final begin = WebsiteHtmlDraftMessage.fromPost({
        'type': 'vb-draft-edit',
        'id': 'b1',
        'field': 'title',
        'phase': 'begin',
      })! as WebsiteHtmlDraftEdit;
      expect(begin.step, WebsiteHtmlDraftEditStep.begin);
      expect(begin.text, isNull);
      expect(
        WebsiteHtmlDraftMessage.fromPost({'type': 'vb-draft-pick', 'id': ''}),
        isA<WebsiteHtmlDraftPick>().having((m) => m.id, 'id', isNull),
      );
      expect(
        WebsiteHtmlDraftMessage.fromPost({'type': 'vb-draft-action'}),
        isNull,
      );
    });
  });

  group('writing a text where it is drawn', () {
    test(
        'a question of the list: the text as drawn, then written once, '
        'one step of the history', () {
      final provider = _provider('faq', {
        'title': 'Preguntas',
        'items': [
          {'question': '¿Arman?', 'answer': 'Sí'},
          {'question': '¿Despachan?', 'answer': 'A todo Chile'},
        ],
      });
      addTearDown(provider.dispose);
      final history = provider.canUndo;

      final write =
          _fields(provider, 'faq').beginText(_firstQuestion, ['question'])!;
      expect(write.text, '¿Arman?');
      expect(write.commit('¿Arman bicis nuevas?'), isTrue);

      final items = _data(provider)['items'] as List;
      expect((items[0] as Map)['question'], '¿Arman bicis nuevas?');
      expect((items[0] as Map)['answer'], 'Sí');
      expect((items[1] as Map)['question'], '¿Despachan?');
      expect(provider.canUndo, isTrue);
      expect(history, isFalse);
      provider.undo();
      expect(((_data(provider)['items'] as List)[0] as Map)['question'],
          '¿Arman?');
    });

    test('only a text field the block declares', () {
      final provider = _provider('hero', {
        'title': 'Portada',
        'imageUrl': 'https://example.invalid/a.jpg',
      });
      addTearDown(provider.dispose);
      final fields = _fields(provider, 'hero');
      expect(fields.beginText(null, ['imageUrl']), isNull);
      expect(fields.beginText(null, ['nope']), isNull);
      expect(fields.beginText(_firstQuestion, ['title']), isNull);
      expect(fields.beginText(null, ['title'])?.text, 'Portada');
    });

    test('a block not drawn yet, or not picked, is not written', () {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'b1',
              'block_type': 'hero',
              'block_data': {'title': 'Portada'},
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: '/inicio',
        )
        ..selectBlock('b1');
      addTearDown(provider.dispose);
      expect(_fields(provider, 'hero').beginText(null, ['title']), isNull);
      provider
        ..reportRenderedBlockViewport('b1', WebsiteViewport.desktop)
        ..selectBlock(null);
      expect(_fields(provider, 'hero').beginText(null, ['title']), isNull);
    });

    test('a draft changed meanwhile is not overwritten', () {
      final provider = _provider('hero', {'title': 'Portada'});
      addTearDown(provider.dispose);
      final write = _fields(provider, 'hero').beginText(null, ['title'])!;
      provider.updateBlockData('b1', 'title', 'Desde el panel');
      expect(write.commit('Desde la página'), isFalse);
      expect(_data(provider)['title'], 'Desde el panel');
    });

    test(
        'a field with an older name: the text it shows, written under the '
        'name the schema keeps', () {
      final provider = _provider('cta', {
        'title': 'Agenda',
        'description': 'Hoy mismo',
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'cta')
          .beginText(null, ['subtitle', 'description'])!;
      expect(write.text, 'Hoy mismo');
      expect(write.commit('Esta semana'), isTrue);
      final data = _data(provider);
      expect(data[write.key], 'Esta semana');
    });
  });
}
