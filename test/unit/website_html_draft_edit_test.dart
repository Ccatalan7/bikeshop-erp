import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_image_fields.dart';
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
        ['b1', 'question@items#0', 'commit', '¿Arman bicis?', 't.1'],
      )! as WebsiteHtmlDraftEdit;
      expect(commit.step, WebsiteHtmlDraftEditStep.commit);
      expect(commit.field.collectionKeys, ['items']);
      expect(commit.text, '¿Arman bicis?');
      expect(commit.token, 't.1');
      // Each edit carries the page's token; a missing or malformed one is
      // no message (an answer for another edit could not be told apart).
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'begin', null],
        ),
        isNull,
      );
      expect(
        (WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'begin', null, 'lq3x.4'],
        )! as WebsiteHtmlDraftEdit)
            .token,
        'lq3x.4',
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'begin', null, '<x>'],
        ),
        isNull,
      );
      // A written text may be empty; a commit without one is no message.
      expect(
        (WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'commit', '', 't.2'],
        )! as WebsiteHtmlDraftEdit)
            .text,
        '',
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'commit', null, 't.3'],
        ),
        isNull,
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftEdit',
          ['b1', 'title', 'erase', null, 't.4'],
        ),
        isNull,
      );
      expect(WebsiteHtmlDraftMessage.fromHandler('other', ['b1']), isNull);
      // The picked block dropped on a seam.
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftMove',
          ['b1', 'b2', 'before'],
        ),
        isA<WebsiteHtmlDraftMove>()
            .having((m) => m.anchor, 'anchor', 'b2')
            .having((m) => m.side, 'side', WebsiteHtmlDraftSide.before),
      );
      for (final side in ['inside', null]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler(
              'vbDraftMove', ['b1', 'b2', side]),
          isNull,
        );
      }
      // A carousel turned in the page: its slide, a whole number.
      expect(
        WebsiteHtmlDraftMessage.fromHandler('vbDraftSlide', ['b1', 2]),
        isA<WebsiteHtmlDraftSlide>().having((m) => m.index, 'index', 2),
      );
      expect(
        WebsiteHtmlDraftMessage.fromHandler('vbDraftSlide', ['b1', 1.0]),
        isA<WebsiteHtmlDraftSlide>().having((m) => m.index, 'index', 1),
      );
      for (final index in [-1, 1.5, '2', null]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler('vbDraftSlide', ['b1', index]),
          isNull,
          reason: '$index',
        );
      }
    });

    test('as a frame message, the same', () {
      final begin = WebsiteHtmlDraftMessage.fromPost({
        'type': 'vb-draft-edit',
        'id': 'b1',
        'field': 'title',
        'phase': 'begin',
        'token': 'm.1',
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
      // On the ERP on the web: the page says it is ready, and what
      // vbDraftPicked found comes back as a message.
      expect(
        WebsiteHtmlDraftMessage.fromPost({'type': 'vb-draft-ready'}),
        isA<WebsiteHtmlDraftReady>(),
      );
      expect(
        WebsiteHtmlDraftMessage.fromPost(
          {'type': 'vb-draft-result', 'call': 'vbDraftPicked', 'result': true},
        ),
        isA<WebsiteHtmlDraftShown>().having((m) => m.found, 'found', true),
      );
      expect(
        WebsiteHtmlDraftMessage.fromPost(
          {'type': 'vb-draft-result', 'call': 'other', 'result': true},
        ),
        isNull,
      );
      expect(
        WebsiteHtmlDraftMessage.fromPost(
          {'type': 'vb-draft-slide', 'id': 'b1', 'index': 0},
        ),
        isA<WebsiteHtmlDraftSlide>().having((m) => m.id, 'id', 'b1'),
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

    test(
        'an item is addressed where it is stored, past an entry that is '
        'not one', () {
      final provider = _provider('faq', {
        'title': 'Preguntas',
        'items': [
          {'question': '¿Arman?', 'answer': 'Sí'},
          'no es una pregunta',
          {'question': '¿Despachan?', 'answer': 'A todo Chile'},
        ],
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'faq').beginText(
        WebsiteInlineRepeaterTarget(collectionKeys: ['items'], itemIndex: 2),
        ['question'],
      )!;
      expect(write.text, '¿Despachan?');
      expect(write.commit('¿Despachan a regiones?'), isTrue);
      final items = _data(provider)['items'] as List;
      expect(items[1], 'no es una pregunta');
      expect((items[2] as Map)['question'], '¿Despachan a regiones?');
      expect(
        _fields(provider, 'faq').beginText(
          WebsiteInlineRepeaterTarget(collectionKeys: ['items'], itemIndex: 1),
          ['question'],
        ),
        isNull,
      );
    });

    test(
        'the toolbar\'s changes travel with the text, in the same step, '
        'over the formatting the text has', () {
      final provider = _provider('faq', {
        'title': 'Preguntas',
        'titleFormatting': {'italic': true, 'textColor': 0xFF112233},
        'items': <Object?>[],
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'faq').beginText(null, ['title'])!;
      expect(write.formattingKey, 'titleFormatting');
      expect(write.formatting, {'italic': true, 'textColor': 0xFF112233});
      expect(write.formattingWith({'italic': true}), isNull);
      final next = write.formattingWith({
        'bold': true,
        'italic': false,
        'fontSize': 32,
      })!;
      expect(next, {'textColor': 0xFF112233, 'bold': true, 'fontSize': 32.0});
      expect(write.commit('Preguntas frecuentes', formatting: next), isTrue);
      final data = _data(provider);
      expect(data['title'], 'Preguntas frecuentes');
      expect(data['titleFormatting'], next);
      provider.undo();
      expect(_data(provider)['titleFormatting'], {
        'italic': true,
        'textColor': 0xFF112233,
      });
    });

    test('a toolbar may change only bold, italic, underline and the size', () {
      expect(
        WebsiteInlineTextWrite.acceptsFormattingChanges({
          'bold': true,
          'underline': null,
          'fontSize': 18,
        }),
        isTrue,
      );
      for (final changes in <Map<String, Object?>>[
        {'textColor': 0xFF000000},
        {'bold': 'yes'},
        {'fontSize': 2},
        {'fontSize': double.infinity},
        {'linkUrl': 'javascript:alert(1)'},
      ]) {
        expect(
          WebsiteInlineTextWrite.acceptsFormattingChanges(changes),
          isFalse,
          reason: '$changes',
        );
      }
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

  group('the picked block\'s height, from the HTML view\'s handle', () {
    test(
        'one drag, one step of the history; a reset gives the content its '
        'own height back', () {
      final provider = _provider('hero', {'title': 'Portada'});
      addTearDown(provider.dispose);
      final fields = _fields(provider, 'hero');
      expect(fields.heightRange, (min: 200.0, max: 1000.0));

      final lease = fields.beginHeight()!;
      expect(fields.commitHeight(lease, 520), isTrue);
      expect(_data(provider)['blockHeight'], 520);
      expect(provider.canUndo, isTrue);

      expect(fields.commitHeight(fields.beginHeight()!, null), isTrue);
      expect(_data(provider)['blockHeight'], isNull);
      provider.undo();
      expect(_data(provider)['blockHeight'], 520);
    });

    test('a block whose content owns its height has no handle', () {
      final provider = _provider('text', {'text': 'Un párrafo'});
      addTearDown(provider.dispose);
      expect(_fields(provider, 'text').beginHeight(), isNull);
    });

    test('a draft changed during the drag is not overwritten', () {
      final provider = _provider('hero', {'title': 'Portada'});
      addTearDown(provider.dispose);
      final fields = _fields(provider, 'hero');
      final lease = fields.beginHeight()!;
      provider.updateBlockData('b1', 'title', 'Desde el panel');
      expect(fields.commitHeight(lease, 520), isFalse);
      expect(_data(provider)['blockHeight'], isNull);
    });

    test('the page\'s messages for it', () {
      final commit = WebsiteHtmlDraftMessage.fromHandler(
        'vbDraftHeight',
        ['b1', 'commit', 520],
      )! as WebsiteHtmlDraftHeight;
      expect(commit.step, WebsiteHtmlDraftHeightStep.commit);
      expect(commit.value, 520);
      expect(
        (WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftHeight',
          ['b1', 'reset', null],
        )! as WebsiteHtmlDraftHeight)
            .step,
        WebsiteHtmlDraftHeightStep.reset,
      );
      for (final value in [null, -5, double.nan, '520']) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler(
            'vbDraftHeight',
            ['b1', 'commit', value],
          ),
          isNull,
          reason: '$value',
        );
      }
    });
  });

  group('a button of the HTML view, written as the canvas writes it', () {
    test('the page names it by its fields and says where it is', () {
      final press = WebsiteHtmlDraftMessage.fromHandler('vbDraftButton', [
        'b1',
        'plan#2',
        [0.1, 0.5, 0.2, 0.04],
      ])! as WebsiteHtmlDraftButton;
      expect(press.fields, WebsiteButtonFields.plan);
      expect(press.index, 2);
      expect(press.where?.left, 0.1);
      expect(press.where?.height, 0.04);

      final posted = WebsiteHtmlDraftMessage.fromPost({
        'type': 'vb-draft-button',
        'id': 'b1',
        'button': 'cta',
        'where': ['x', 0, 0, 0],
      })! as WebsiteHtmlDraftButton;
      expect(posted.fields, WebsiteButtonFields.cta);
      expect(posted.where, isNull);

      // A page names a button the editor knows, never a field of its own.
      for (final spec in ['title', 'plan', 'cta#1', 'actions', null]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler('vbDraftButton', ['b1', spec]),
          isNull,
          reason: '$spec',
        );
      }
    });

    test(
        'label, destination and look in one step of the history, the '
        'primary mirrored in actions; an empty destination stays empty', () {
      final provider = _provider('cta', {
        'title': 'Agenda',
        'buttonText': 'Escríbenos',
        'buttonLink': '',
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'cta').beginButton(
        WebsiteButtonFields.cta,
        0,
      )!;
      expect(write.value.label, 'Escríbenos');
      expect(write.value.href, '');
      expect(write.value.variant, WebsiteActionVariant.filled);
      expect(write.destinationHelp, 'Vacío, abre el WhatsApp de la tienda.');

      expect(
        write.commit(
          const WebsiteActionValue(
            label: 'Agendar',
            href: '/contacto',
            variant: WebsiteActionVariant.outline,
          ),
        ),
        isTrue,
      );
      final data = _data(provider);
      expect(data['buttonText'], 'Agendar');
      expect(data['buttonLink'], '/contacto');
      expect(data['actionVariant'], 'outline');
      expect((data['actions'] as List).single, containsPair('to', '/contacto'));
      provider.undo();
      expect(_data(provider)['buttonText'], 'Escríbenos');
    });

    test('the second button never writes over the primary', () {
      final primary = {
        'type': 'navigate',
        'label': 'Escríbenos',
        'to': '/contacto',
        'variant': 'filled',
      };
      final provider = _provider('cta', {
        'title': 'Agenda',
        'buttonText': 'Escríbenos',
        'buttonLink': '/contacto',
        'secondaryText': 'Ver mapa',
        'actions': [primary],
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'cta').beginButton(
        WebsiteButtonFields.ctaSecondary,
        0,
      )!;
      expect(write.value.label, 'Ver mapa');
      expect(write.value.href, '');
      expect(
        write.commit(
            const WebsiteActionValue(label: 'Cómo llegar', href: '/mapa')),
        isTrue,
      );
      final data = _data(provider);
      expect(data['secondaryText'], 'Cómo llegar');
      expect(data['secondaryLink'], '/mapa');
      expect(data['actions'], [primary]);
      expect(data['buttonText'], 'Escríbenos');
    });

    test('a plan\'s button, in the plan stored where the page says', () {
      final provider = _provider('pricing', {
        'title': 'Planes',
        'plans': [
          {'name': 'Básica', 'ctaText': 'Agendar', 'ctaLink': '/a'},
          {'name': 'Full', 'ctaText': 'Agendar full', 'ctaLink': '/b'},
        ],
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'pricing').beginButton(
        WebsiteButtonFields.plan,
        1,
      )!;
      expect(write.value.label, 'Agendar full');
      expect(
        write.commit(const WebsiteActionValue(label: 'Reservar', href: '/b')),
        isTrue,
      );
      final plans = _data(provider)['plans'] as List;
      expect(plans[1], containsPair('ctaText', 'Reservar'));
      expect(plans[0], containsPair('ctaText', 'Agendar'));
    });

    test(
        'nothing changed writes nothing; a draft changed meanwhile is not '
        'overwritten; a block not picked has no button to edit', () {
      final provider = _provider('hero', {
        'title': 'Portada',
        'ctaText': 'Agendar',
        'ctaLink': '/contacto',
      });
      addTearDown(provider.dispose);
      final fields = _fields(provider, 'hero');
      final same = fields.beginButton(WebsiteButtonFields.hero, 0)!;
      // The hero's button is outlined unless the block says otherwise:
      // applying the card untouched does not change its look.
      expect(same.value.variant, WebsiteActionVariant.outline);
      expect(same.commit(same.value), isFalse);
      expect(provider.canUndo, isFalse);

      final stale = fields.beginButton(WebsiteButtonFields.hero, 0)!;
      provider.updateBlockData('b1', 'title', 'Desde el panel');
      expect(
        stale.commit(const WebsiteActionValue(label: 'Ver', href: '/')),
        isFalse,
      );
      expect(_data(provider)['ctaText'], 'Agendar');

      provider.selectBlock(null);
      expect(fields.beginButton(WebsiteButtonFields.hero, 0), isNull);
    });
  });

  group('a canvas layer clicked in the HTML view', () {
    final carousel = <String, dynamic>{
      'id': 'b1',
      'block_type': 'carousel',
      'block_data': {
        'slides': [
          {'title': 'Primera'},
          {
            'title': 'Cámaras',
            'elements': [
              {'id': 'camaras_desk_title', 'type': 'text'},
            ],
          },
        ],
      },
    };

    test('the page names the slide and the layer', () {
      final press = WebsiteHtmlDraftMessage.fromHandler(
        'vbDraftLayer',
        ['b1', 1, 'camaras_desk_title'],
      )! as WebsiteHtmlDraftLayer;
      expect(press.slide, 1);
      expect(press.layer, 'camaras_desk_title');
      final own = WebsiteHtmlDraftMessage.fromPost({
        'type': 'vb-draft-layer',
        'id': 'b1',
        'slide': -1,
        'layer': 'l1',
      })! as WebsiteHtmlDraftLayer;
      expect(own.slide, isNull);
      for (final args in [
        ['b1', -2, 'l1'],
        ['b1', 1.5, 'l1'],
        ['b1', 1, ''],
        ['b1', 1, 'a b'],
        ['b1', 1, '<x>'],
        ['b1', 1, 'x' * 121],
      ]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler('vbDraftLayer', args),
          isNull,
          reason: '$args',
        );
      }
    });

    test('only a layer the slide or the canvas holds is picked', () {
      expect(
        websiteHtmlDraftLayerPlace(
          carousel,
          const WebsiteHtmlDraftLayer('b1', 1, 'camaras_desk_title'),
        ),
        (slide: 1, count: 2),
      );
      for (final press in const [
        WebsiteHtmlDraftLayer('b1', 0, 'camaras_desk_title'),
        WebsiteHtmlDraftLayer('b1', 2, 'camaras_desk_title'),
        WebsiteHtmlDraftLayer('b1', null, 'camaras_desk_title'),
        WebsiteHtmlDraftLayer('b1', 1, 'otra'),
      ]) {
        expect(websiteHtmlDraftLayerPlace(carousel, press), isNull);
      }
      final canvas = <String, dynamic>{
        'id': 'c1',
        'block_type': 'canvas',
        'block_data': {
          'elements': [
            {'id': 'l1', 'type': 'shape'},
          ],
        },
      };
      expect(
        websiteHtmlDraftLayerPlace(
          canvas,
          const WebsiteHtmlDraftLayer('c1', null, 'l1'),
        ),
        (slide: null, count: 0),
      );
      expect(
        websiteHtmlDraftLayerPlace(
          canvas,
          const WebsiteHtmlDraftLayer('c1', 0, 'l1'),
        ),
        isNull,
      );
    });
  });

  group('a photo replaced in the HTML view', () {
    test('the page names it by its fields', () {
      final press = WebsiteHtmlDraftMessage.fromHandler(
        'vbDraftImage',
        ['b1', 'gallery#3'],
      )! as WebsiteHtmlDraftImage;
      expect(press.fields, WebsiteImageFields.gallery);
      expect(press.index, 3);
      for (final spec in ['hero', 'imageUrl', 'gallery', 'about#1', null]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler('vbDraftImage', ['b1', spec]),
          isNull,
          reason: '$spec',
        );
      }
    });

    test('one step of the history, in the item stored where the page says', () {
      final provider = _provider('gallery', {
        'title': 'Galería',
        'images': [
          {'imageUrl': 'https://x/a.jpg', 'caption': 'A'},
          {'imageUrl': '', 'caption': 'B'},
        ],
      });
      addTearDown(provider.dispose);
      final write = _fields(provider, 'gallery').beginImage(
        WebsiteImageFields.gallery,
        1,
      )!;
      expect(write.url, '');
      expect(write.commit('https://x/b.jpg'),
          WebsiteInlineMutationResult.committed);
      final images = _data(provider)['images'] as List;
      expect(images[1], containsPair('imageUrl', 'https://x/b.jpg'));
      expect(images[0], containsPair('imageUrl', 'https://x/a.jpg'));
      provider.undo();
      expect(
          (_data(provider)['images'] as List)[1], containsPair('imageUrl', ''));
    });

    test(
        'the same photo writes nothing; a draft changed meanwhile is not '
        'overwritten; a block not picked has no photo to replace', () {
      final provider = _provider('about', {
        'title': 'Nosotros',
        'imageUrl': 'https://x/a.jpg',
      });
      addTearDown(provider.dispose);
      final fields = _fields(provider, 'about');
      final same = fields.beginImage(WebsiteImageFields.about, 0)!;
      expect(same.commit('https://x/a.jpg'),
          WebsiteInlineMutationResult.unchanged);
      expect(provider.canUndo, isFalse);

      final stale = fields.beginImage(WebsiteImageFields.about, 0)!;
      provider.updateBlockData('b1', 'title', 'Desde el panel');
      expect(stale.commit('https://x/b.jpg'),
          WebsiteInlineMutationResult.rejected);
      expect(_data(provider)['imageUrl'], 'https://x/a.jpg');

      provider.selectBlock(null);
      expect(fields.beginImage(WebsiteImageFields.about, 0), isNull);
    });
  });

  group('a canvas layer dragged in the HTML view', () {
    test('the page says the layer, the step and its new place or size', () {
      final move = WebsiteHtmlDraftMessage.fromHandler('vbDraftLayerDrag', [
        'b1',
        2,
        'camaras_desk_title',
        'commit',
        'move',
        {'x': 96, 'y': 128.5},
      ])! as WebsiteHtmlDraftLayerDrag;
      expect(move.slide, 2);
      expect(move.resize, isFalse);
      expect(move.step, WebsiteHtmlDraftLayerDragStep.commit);
      expect(move.values, {'x': 96.0, 'y': 128.5});

      final resize = WebsiteHtmlDraftMessage.fromPost({
        'type': 'vb-draft-layer-drag',
        'id': 'c1',
        'slide': -1,
        'layer': 'l1',
        'phase': 'begin',
        'mode': 'resize',
      })! as WebsiteHtmlDraftLayerDrag;
      expect(resize.slide, isNull);
      expect(resize.resize, isTrue);
      expect(resize.values, isNull);
    });

    test('a commit writes only its two keys, as finite numbers in range', () {
      for (final values in [
        null,
        {'x': 1},
        {'x': 1, 'y': 2, 'w': 3},
        {'w': 10, 'h': 10},
        {'x': -1, 'y': 0},
        {'x': double.infinity, 'y': 0},
        {'x': 30000, 'y': 0},
        {'x': '10', 'y': 0},
      ]) {
        expect(
          WebsiteHtmlDraftMessage.fromHandler('vbDraftLayerDrag', [
            'b1',
            0,
            'l1',
            'commit',
            'move',
            values,
          ]),
          isNull,
          reason: '$values',
        );
      }
      expect(
        WebsiteHtmlDraftMessage.fromHandler(
          'vbDraftLayerDrag',
          ['b1', 0, 'l1', 'begin', 'rotate', null],
        ),
        isNull,
      );
    });
  });
}
