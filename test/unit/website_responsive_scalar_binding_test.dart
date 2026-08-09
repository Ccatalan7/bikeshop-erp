import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_responsive_scalar_binding.dart';

/// The canonical binding for non-media schema fields.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c and
/// `handoff-t10/spec.json` `property_policy_matrix`.
void main() {
  const responsiveNumber = WebsiteBlockFieldSchema(
    key: 'overlayOpacity',
    label: 'Opacidad overlay',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  );
  const responsiveSelect = WebsiteBlockFieldSchema(
    key: 'alignment',
    label: 'Alineación',
    type: WebsiteBlockFieldType.select,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  );
  const sharedOnlyText = WebsiteBlockFieldSchema(
    key: 'title',
    label: 'Título',
    type: WebsiteBlockFieldType.text,
  );
  const aliasedSelect = WebsiteBlockFieldSchema(
    key: 'style',
    label: 'Estilo',
    type: WebsiteBlockFieldType.select,
    migrationAliases: <String>['buttonStyle'],
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  );

  List<Map<String, dynamic>> blocksWith(Map<String, dynamic> data) {
    return <Map<String, dynamic>>[
      {
        'id': 'block-1',
        'block_type': 'hero',
        'block_data': data,
        'is_visible': true,
        'sort_order': 0,
      },
    ];
  }

  WebsiteEditModeProvider providerWith(
    Map<String, dynamic> data, {
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(blocksWith(data), const <String, dynamic>{})
      ..setDevicePreviewMode(viewport)
      ..selectBlock('block-1')
      ..reportRenderedBlockViewport(
        'block-1',
        switch (viewport) {
          DevicePreviewMode.desktop => WebsiteViewport.desktop,
          DevicePreviewMode.tablet => WebsiteViewport.tablet,
          DevicePreviewMode.mobile => WebsiteViewport.mobile,
        },
      );
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  WebsiteResponsiveScalarBinding<T> bind<T>(
    WebsiteEditModeProvider provider,
    WebsiteBlockFieldSchema field,
    WebsiteResponsiveDecoder<T> decode, {
    WebsiteResponsiveFieldOwner owner = const WebsiteResponsiveRootField(),
  }) {
    return WebsiteResponsiveScalarBinding<T>.forField(
      provider: provider,
      blockId: 'block-1',
      field: field,
      owner: owner,
      decode: decode,
    );
  }

  group('decodificación segura: nada inventa un override', () {
    test('ausente y null son "sin valor" en todos los tipos', () {
      for (final decode in <WebsiteResponsiveDecoder<Object>>[
        WebsiteResponsiveScalarBinding.decodeText,
        WebsiteResponsiveScalarBinding.decodeOption,
        WebsiteResponsiveScalarBinding.decodeColor,
        WebsiteResponsiveScalarBinding.decodeNumber,
        WebsiteResponsiveScalarBinding.decodeBoolean,
        WebsiteResponsiveScalarBinding.decodeStringList,
      ]) {
        expect(decode(null), isNull);
      }
    });

    test('el blanco no es una elección, pero sí es un texto', () {
      expect(WebsiteResponsiveScalarBinding.decodeOption('   '), isNull);
      expect(WebsiteResponsiveScalarBinding.decodeColor(''), isNull);
      expect(WebsiteResponsiveScalarBinding.decodeStringList('  '), isNull);
      // Un texto vacío escrito a propósito sigue siendo un valor.
      expect(WebsiteResponsiveScalarBinding.decodeText(''), '');
    });

    test('number, bool y chips aceptan su forma serializada', () {
      expect(WebsiteResponsiveScalarBinding.decodeNumber('0.4'), 0.4);
      expect(WebsiteResponsiveScalarBinding.decodeNumber('no'), isNull);
      expect(WebsiteResponsiveScalarBinding.decodeBoolean('true'), isTrue);
      expect(WebsiteResponsiveScalarBinding.decodeBoolean('false'), isFalse);
      expect(WebsiteResponsiveScalarBinding.decodeBoolean('quizás'), isNull);
      expect(
        WebsiteResponsiveScalarBinding.decodeStringList('a, b ,c'),
        ['a', 'b', 'c'],
      );
      expect(
        WebsiteResponsiveScalarBinding.decodeStringList(
            <Object?>['x', '', 'y']),
        ['x', 'y'],
      );
    });

    test('el decodificador sale del tipo del schema', () {
      expect(
        WebsiteResponsiveScalarBinding.decoderFor(WebsiteBlockFieldType.number),
        same(WebsiteResponsiveScalarBinding.decodeNumber),
      );
      expect(
        WebsiteResponsiveScalarBinding.decoderFor(WebsiteBlockFieldType.toggle),
        same(WebsiteResponsiveScalarBinding.decodeBoolean),
      );
      expect(
        WebsiteResponsiveScalarBinding.decoderFor(WebsiteBlockFieldType.chips),
        same(WebsiteResponsiveScalarBinding.decodeStringList),
      );
    });
  });

  group('A · binding root', () {
    test('en móvil sin override el valor es el compartido y se lee Heredado',
        () {
      final provider = providerWith(<String, dynamic>{'overlayOpacity': 0.4});
      final binding = bind<num>(
        provider,
        responsiveNumber,
        WebsiteResponsiveScalarBinding.decodeNumber,
      );

      expect(binding.value, 0.4);
      expect(binding.state.status, WebsiteResponsiveFieldStatus.inherited);
      expect(binding.state.canCustomize, isTrue);
      expect(binding.state.canReset, isFalse);
    });

    test('personalizar + write crea responsive.mobile y deja el común intacto',
        () {
      final provider = providerWith(<String, dynamic>{'overlayOpacity': 0.4});
      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .customize();
      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .write(0.8);

      final data = dataOf(provider);
      expect(data['overlayOpacity'], 0.4, reason: 'la base no se toca');
      expect(
        (data['responsive'] as Map)['mobile'],
        containsPair('overlayOpacity', 0.8),
      );

      final after = bind<num>(provider, responsiveNumber,
          WebsiteResponsiveScalarBinding.decodeNumber);
      expect(after.value, 0.8);
      expect(after.state.status, WebsiteResponsiveFieldStatus.overridden);
      expect(after.state.canReset, isTrue);
    });

    test('reset devuelve igualdad profunda y dirty=false', () {
      final provider = providerWith(<String, dynamic>{'overlayOpacity': 0.4});
      final original = dataOf(provider);
      expect(provider.hasUnsavedChanges, isFalse);

      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .customize();
      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .write(0.8);
      expect(provider.hasUnsavedChanges, isTrue);

      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .reset();

      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
    });

    test('escritorio es la base: el scope se coacciona a común', () {
      final provider = providerWith(
        <String, dynamic>{'alignment': 'left'},
        viewport: DevicePreviewMode.desktop,
      );
      final binding = bind<String>(
        provider,
        responsiveSelect,
        WebsiteResponsiveScalarBinding.decodeOption,
      );
      expect(binding.state.effectiveWriteScope, WebsiteWriteScope.shared);
      expect(binding.state.canCustomize, isFalse);

      binding.write('center');

      final data = dataOf(provider);
      expect(data['alignment'], 'center');
      expect(data.containsKey('responsive'), isFalse);
    });

    test('sharedOnly nunca crea responsive, ni en móvil', () {
      final provider = providerWith(<String, dynamic>{'title': 'Hola'});
      final binding = bind<String>(
        provider,
        sharedOnlyText,
        WebsiteResponsiveScalarBinding.decodeText,
      );
      expect(binding.state.status, WebsiteResponsiveFieldStatus.sharedOnly);
      expect(binding.state.canCustomize, isFalse);

      binding.write('Chao');

      final data = dataOf(provider);
      expect(data['title'], 'Chao');
      expect(data.containsKey('responsive'), isFalse);
    });

    test('shared conserva los aliases y es UN solo paso de historia', () {
      final provider = providerWith(<String, dynamic>{
        'style': 'filled',
        'buttonStyle': 'filled',
      }, viewport: DevicePreviewMode.desktop);
      final historyBefore = provider.canUndo;
      expect(historyBefore, isFalse);

      bind<String>(provider, aliasedSelect,
              WebsiteResponsiveScalarBinding.decodeOption)
          .write('outline');

      final data = dataOf(provider);
      expect(data['style'], 'outline');
      expect(data['buttonStyle'], 'outline', reason: 'el alias sigue vivo');

      // Una mutación, un paso: deshacer devuelve el documento completo.
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(dataOf(provider)['style'], 'filled');
      expect(dataOf(provider)['buttonStyle'], 'filled');
      expect(provider.canUndo, isFalse);
    });

    test('el override de viewport crea sólo la autoridad canónica', () {
      final provider = providerWith(<String, dynamic>{
        'style': 'filled',
        'buttonStyle': 'filled',
      });
      bind<String>(provider, aliasedSelect,
              WebsiteResponsiveScalarBinding.decodeOption)
          .customize();
      bind<String>(provider, aliasedSelect,
              WebsiteResponsiveScalarBinding.decodeOption)
          .write('text');

      final mobile = (dataOf(provider)['responsive'] as Map)['mobile'] as Map;
      expect(mobile['style'], 'text');
      expect(
        mobile.containsKey('buttonStyle'),
        isFalse,
        reason: 'un override no duplica el alias',
      );
      expect(dataOf(provider)['buttonStyle'], 'filled');
    });

    test('una misma binding admite escritura rápida y no-op sin congelarse',
        () {
      final provider = providerWith(<String, dynamic>{'title': 'Hola'});
      final binding = bind<String>(
        provider,
        sharedOnlyText,
        WebsiteResponsiveScalarBinding.decodeText,
      );

      binding.write('Hola'); // no-op admitido: renueva el lease.
      binding.write('H');
      binding.write('Ho');
      binding.write('Hola de nuevo');

      expect(dataOf(provider)['title'], 'Hola de nuevo');
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(dataOf(provider)['title'], 'Ho');
      provider.undo();
      expect(dataOf(provider)['title'], 'H');
      provider.undo();
      expect(dataOf(provider)['title'], 'Hola');
      expect(provider.canUndo, isFalse);
    });

    test('callback anterior al cambio de scope falla cerrado', () {
      final provider = providerWith(<String, dynamic>{'overlayOpacity': 0.4});
      final stale = bind<num>(
        provider,
        responsiveNumber,
        WebsiteResponsiveScalarBinding.decodeNumber,
      );

      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: responsiveNumber.key,
        policy: responsiveNumber.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      stale.write(0.8);

      expect(dataOf(provider)['overlayOpacity'], 0.4);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(provider.canUndo, isFalse);

      bind<num>(provider, responsiveNumber,
              WebsiteResponsiveScalarBinding.decodeNumber)
          .write(0.8);
      expect(
        (dataOf(provider)['responsive'] as Map)['mobile'],
        containsPair('overlayOpacity', 0.8),
      );
    });

    test('callback de una página anterior no puede escribir en un id reciclado',
        () {
      final provider = providerWith(<String, dynamic>{'title': 'Página A'});
      final stale = bind<String>(
        provider,
        sharedOnlyText,
        WebsiteResponsiveScalarBinding.decodeText,
      );

      provider.openEditorDocument(
        blocksWith(<String, dynamic>{'title': 'Página B'}),
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-b',
        pageSlug: 'pagina-b',
      );
      provider
        ..selectBlock('block-1')
        ..reportRenderedBlockViewport('block-1', WebsiteViewport.mobile);
      stale.write('Escritura obsoleta');

      expect(dataOf(provider)['title'], 'Página B');
      expect(provider.canUndo, isFalse);
    });
  });

  group('B · binding repeater', () {
    List<Map<String, dynamic>> slides() => <Map<String, dynamic>>[
          {'id': 'slide-a', 'alignment': 'left'},
          {'id': 'slide-b', 'alignment': 'left'},
        ];

    WebsiteEditModeProvider repeaterProvider() {
      return WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[
            {
              'id': 'block-1',
              'block_type': 'carousel',
              'block_data': <String, dynamic>{
                'title': 'Portada',
                'slides': slides(),
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectBlock('block-1')
        ..reportRenderedBlockViewport('block-1', WebsiteViewport.mobile);
    }

    List<Map<String, dynamic>> slidesOf(WebsiteEditModeProvider provider) {
      final raw = dataOf(provider)['slides'] as List;
      return raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    }

    test('sólo cambia el item elegido; el hermano y la raíz quedan intactos',
        () {
      final provider = repeaterProvider();
      final owner = WebsiteResponsiveRepeaterField.forItem(
        collectionKeys: const <String>['slides'],
        itemIndex: 1,
        item: slidesOf(provider)[1],
      );
      // La identidad existe en la fixture y se usa.
      expect(owner.identityKey, 'id');
      expect(owner.identityValue, 'slide-b');

      final binding = WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      );
      binding.customize();
      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).write('right');

      final updated = slidesOf(provider);
      expect(
        (updated[1]['responsive'] as Map)['mobile'],
        containsPair('alignment', 'right'),
      );
      expect(updated[0].containsKey('responsive'), isFalse);
      expect(updated[0]['alignment'], 'left');
      // Y jamás en la raíz del bloque.
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(dataOf(provider).containsKey('alignment'), isFalse);
    });

    test('sin identidad estable se direcciona por índice explícito', () {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[
            {
              'id': 'block-1',
              'block_type': 'carousel',
              'block_data': <String, dynamic>{
                'slides': <Map<String, dynamic>>[
                  {'alignment': 'left'},
                  {'alignment': 'left'},
                ],
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectBlock('block-1')
        ..reportRenderedBlockViewport('block-1', WebsiteViewport.mobile);

      final owner = WebsiteResponsiveRepeaterField.forItem(
        collectionKeys: const <String>['slides'],
        itemIndex: 0,
        item: slidesOf(provider)[0],
      );
      expect(owner.identityKey, isNull, reason: 'no se inventa un id');
      expect(owner.itemIndex, 0);

      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).customize();
      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).write('center');

      final updated = slidesOf(provider);
      expect(
        (updated[0]['responsive'] as Map)['mobile'],
        containsPair('alignment', 'center'),
      );
      expect(updated[1].containsKey('responsive'), isFalse);
    });

    test('reset del item devuelve igualdad profunda y dirty=false', () {
      final provider = repeaterProvider();
      final original = dataOf(provider);
      final owner = WebsiteResponsiveRepeaterField.forItem(
        collectionKeys: const <String>['slides'],
        itemIndex: 0,
        item: slidesOf(provider)[0],
      );

      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).customize();
      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).write('right');
      expect(provider.hasUnsavedChanges, isTrue);

      WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      ).reset();

      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    test('callback de un item anterior no salta al hermano tras reordenar', () {
      final provider = repeaterProvider();
      final originalSlides = slidesOf(provider);
      final owner = WebsiteResponsiveRepeaterField.forItem(
        collectionKeys: const <String>['slides'],
        itemIndex: 1,
        item: originalSlides[1],
      );
      final stale = WebsiteResponsiveScalarBinding<String>.forField(
        provider: provider,
        blockId: 'block-1',
        field: responsiveSelect,
        owner: owner,
        decode: WebsiteResponsiveScalarBinding.decodeOption,
      );

      provider.updateBlockData(
        'block-1',
        'slides',
        <Map<String, dynamic>>[originalSlides[1], originalSlides[0]],
      );
      stale.write('right');

      final reordered = slidesOf(provider);
      expect(reordered[0]['id'], 'slide-b');
      expect(reordered[0]['alignment'], 'left');
      expect(reordered[1]['id'], 'slide-a');
      expect(reordered[1]['alignment'], 'left');
      expect(provider.canUndo, isTrue,
          reason: 'sólo el reorder externo existe');
      provider.undo();
      expect(slidesOf(provider), originalSlides);
      expect(provider.canUndo, isFalse);
    });
  });
}
