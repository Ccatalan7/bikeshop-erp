import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_responsive_media_binding.dart';

/// Binding contracts of [WebsiteResponsiveMediaBinding] against the real
/// provider — the layer the visual test cannot reach.
void main() {
  const coverField = WebsiteBlockFieldSchema(
    key: 'imageUrl',
    label: 'Imagen de fondo',
    type: WebsiteBlockFieldType.image,
    mediaRole: WebsiteMediaRole.cover,
    supportsFocalPoint: true,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    legacyResponsiveAliases: <String>['mobileImageUrl'],
  );

  const logoField = WebsiteBlockFieldSchema(
    key: 'logoUrl',
    label: 'Logo',
    type: WebsiteBlockFieldType.image,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  );

  WebsiteEditModeProvider providerWith(Map<String, dynamic> blockData) {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'hero-1',
          'block_type': 'hero',
          'block_data': blockData,
        },
      ],
      const {},
      pageId: 'page-1',
      pageSlug: 'inicio',
    );
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) {
    return Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
  }

  int historyDepth(WebsiteEditModeProvider provider) {
    var undos = 0;
    while (provider.canUndo) {
      provider.undo();
      undos++;
    }
    return undos;
  }

  group('1 · personalizar cambia scope, no datos', () {
    test('customize no ensucia el borrador ni crea historia', () {
      final provider = providerWith({'imageUrl': 'https://cdn/base.webp'});
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);
      final before = dataOf(provider);

      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).customizeUrl();

      expect(dataOf(provider), before, reason: 'no escribe dato');
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);

      // El siguiente cambio sí crea el override del viewport.
      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).writeUrl('https://cdn/vertical.webp');

      final after = dataOf(provider);
      expect(after['imageUrl'], 'https://cdn/base.webp');
      final responsive = after['responsive'] as Map?;
      expect(responsive, isNotNull);
      expect(
        (responsive!['mobile'] as Map)['imageUrl'],
        'https://cdn/vertical.webp',
      );
    });
  });

  group('2 · reset root borra canónico y alias legacy', () {
    test('una sola historia y vuelve al valor común', () {
      final provider = providerWith({
        'imageUrl': 'https://cdn/base.webp',
        'mobileImageUrl': 'https://cdn/legacy-mobile.webp',
        'responsive': {
          'mobile': {'imageUrl': 'https://cdn/vertical.webp'},
        },
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).resetUrl();

      final after = dataOf(provider);
      expect(
        after.containsKey('mobileImageUrl'),
        isFalse,
        reason: 'el alias legacy no puede sobrevivir al reset',
      );
      final responsive = after['responsive'] as Map?;
      expect(
        responsive == null ||
            (responsive['mobile'] as Map?) == null ||
            !(responsive['mobile'] as Map).containsKey('imageUrl'),
        isTrue,
      );

      final state = WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).urlState;
      expect(state.resolved.isOverride, isFalse);
      expect(state.resolved.value, 'https://cdn/base.webp');
      expect(historyDepth(provider), 1, reason: 'una sola entrada de undo');
    });
  });

  group('3–5 · repeater estable y aislado', () {
    Map<String, dynamic> slideData(
      WebsiteEditModeProvider provider,
      String id,
    ) {
      final slides = dataOf(provider)['slides'] as List;
      return Map<String, dynamic>.from(
        slides.cast<Map>().singleWhere((slide) => slide['id'] == id),
      );
    }

    WebsiteResponsiveMediaBinding slideBinding(
      WebsiteEditModeProvider provider, {
      required int index,
      required String id,
    }) {
      return WebsiteResponsiveMediaBinding.repeaterItem(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
        collectionKeys: const <String>['slides'],
        itemIndex: index,
        identityKey: 'id',
        identityValue: id,
      );
    }

    test('override de slide A no toca slide B', () {
      final provider = providerWith({
        'slides': [
          {'id': 'a', 'imageUrl': 'https://cdn/a.webp'},
          {'id': 'b', 'imageUrl': 'https://cdn/b.webp'},
        ],
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      slideBinding(provider, index: 0, id: 'a')
        ..customizeUrl()
        ..writeUrl('https://cdn/a-mobile.webp');

      expect(
        ((slideData(provider, 'a')['responsive'] as Map)['mobile']
            as Map)['imageUrl'],
        'https://cdn/a-mobile.webp',
      );
      expect(slideData(provider, 'b').containsKey('responsive'), isFalse);
    });

    test('la identidad estable gana al índice stale después de reorder', () {
      final provider = providerWith({
        'slides': [
          {'id': 'a', 'imageUrl': 'https://cdn/a.webp'},
          {'id': 'b', 'imageUrl': 'https://cdn/b.webp'},
        ],
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);
      final binding = slideBinding(provider, index: 0, id: 'a');
      provider.updateBlockData('hero-1', 'slides', [
        {'id': 'b', 'imageUrl': 'https://cdn/b.webp'},
        {'id': 'a', 'imageUrl': 'https://cdn/a.webp'},
      ]);

      binding
        ..customizeUrl()
        ..writeUrl('https://cdn/a-mobile.webp');

      expect(slideData(provider, 'a')['responsive'], isNotNull);
      expect(slideData(provider, 'b').containsKey('responsive'), isFalse);
    });

    test('reset limpia sólo la slide activa, canónico y alias', () {
      final provider = providerWith({
        'slides': [
          {
            'id': 'a',
            'imageUrl': 'https://cdn/a.webp',
            'mobileImageUrl': 'https://cdn/a-legacy.webp',
            'responsive': {
              'mobile': {'imageUrl': 'https://cdn/a-mobile.webp'},
            },
          },
          {
            'id': 'b',
            'imageUrl': 'https://cdn/b.webp',
            'mobileImageUrl': 'https://cdn/b-legacy.webp',
            'responsive': {
              'mobile': {'imageUrl': 'https://cdn/b-mobile.webp'},
            },
          },
        ],
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      slideBinding(provider, index: 0, id: 'a').resetUrl();

      final a = slideData(provider, 'a');
      final b = slideData(provider, 'b');
      expect(a.containsKey('mobileImageUrl'), isFalse);
      expect(
        (a['responsive'] as Map?)?['mobile'],
        anyOf(isNull, isNot(containsPair('imageUrl', anything))),
      );
      expect(b['mobileImageUrl'], 'https://cdn/b-legacy.webp');
      expect(
        ((b['responsive'] as Map)['mobile'] as Map)['imageUrl'],
        'https://cdn/b-mobile.webp',
      );
      expect(historyDepth(provider), 1);
    });
  });

  group('6 · metadata descriptiva sigue siendo común', () {
    test('alt text en móvil actualiza la base sin crear responsive map', () {
      const altField = WebsiteBlockFieldSchema(
        key: 'imageAlt',
        label: 'Texto alternativo',
        type: WebsiteBlockFieldType.text,
        responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      final provider = providerWith({
        'imageUrl': 'https://cdn/base.webp',
        'imageAlt': 'Anterior',
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      provider.setBlockResponsiveProperty(
        'hero-1',
        altField.key,
        'Descripción compartida',
        policy: altField.responsivePolicy,
      );

      final after = dataOf(provider);
      expect(after['imageAlt'], 'Descripción compartida');
      expect(after.containsKey('responsive'), isFalse);
    });
  });

  group('7 · el encuadre es una decisión, no dos', () {
    test('escribir X/Y produce una sola historia', () {
      final provider = providerWith({'imageUrl': 'https://cdn/base.webp'});
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      // Mismo protocolo que la URL: sin personalizar, el destino sigue siendo
      // el valor común. Personalizar no escribe dato ni historia.
      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).customizeFocal!();
      expect(provider.canUndo, isFalse);

      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).writeFocal!(0.7, 0.3);

      final mobile = (dataOf(provider)['responsive'] as Map)['mobile'] as Map;
      expect(mobile['focalPointX'], 0.7);
      expect(mobile['focalPointY'], 0.3);
      expect(
        historyDepth(provider),
        1,
        reason: 'X e Y son una sola decisión de encuadre',
      );
    });

    test('reset borra canónico y legacy X/Y en una sola historia', () {
      final provider = providerWith({
        'imageUrl': 'https://cdn/base.webp',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'mobileFocalPointX': 0.9,
        'mobileFocalPointY': 0.1,
        'responsive': {
          'mobile': {'focalPointX': 0.7, 'focalPointY': 0.3},
        },
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).resetFocal!();

      final after = dataOf(provider);
      expect(after.containsKey('mobileFocalPointX'), isFalse);
      expect(after.containsKey('mobileFocalPointY'), isFalse);
      expect(historyDepth(provider), 1);
    });

    test('un solo eje en legacy marca el encuadre completo', () {
      final provider = providerWith({
        'imageUrl': 'https://cdn/base.webp',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'mobileFocalPointX': 0.9,
      });
      provider.setDevicePreviewMode(DevicePreviewMode.mobile);

      final focal = WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      ).focalState!;

      expect(focal.status, WebsiteResponsiveFieldStatus.legacyConflict);
      expect(focal.resolved.value!.dx, 0.9);
    });
  });

  group('8 · la capacidad focal la declara el schema', () {
    test('un logo no expone encuadre ni puede escribirlo', () {
      final provider = providerWith({'logoUrl': 'https://cdn/logo.png'});
      final binding = WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: logoField,
      );

      expect(logoField.hasFocalPointControl, isFalse);
      expect(binding.supportsFocalPoint, isFalse);
      expect(binding.focalState, isNull);
      expect(binding.writeFocal, isNull);
      expect(binding.customizeFocal, isNull);
      expect(binding.resetFocal, isNull);
    });

    test('una portada sí lo expone', () {
      final provider = providerWith({'imageUrl': 'https://cdn/base.webp'});
      final binding = WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
      );

      expect(coverField.hasFocalPointControl, isTrue);
      expect(binding.supportsFocalPoint, isTrue);
      expect(binding.focalState, isNotNull);
      expect(binding.writeFocal, isNotNull);
    });

    test('el host real se propaga al estado del campo', () {
      final provider = providerWith({'imageUrl': 'https://cdn/base.webp'});
      final binding = WebsiteResponsiveMediaBinding.root(
        provider: provider,
        blockId: 'hero-1',
        field: coverField,
        hostClass: WebsiteAuthoringHostClass.phone,
      );

      expect(
        binding.urlState.context.hostClass,
        WebsiteAuthoringHostClass.phone,
      );
      expect(
        binding.focalState!.context.hostClass,
        WebsiteAuthoringHostClass.phone,
      );
    });
  });

  group('composición del encuadre', () {
    WebsiteResponsiveFieldState<double> axis({
      required bool isOverride,
      bool isLegacy = false,
      double value = 0.5,
    }) {
      const schema = WebsiteBlockFieldSchema(
        key: 'focalPointX',
        label: 'Encuadre',
        type: WebsiteBlockFieldType.number,
        responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      return WebsiteResponsiveFieldState<double>.resolve(
        schema: schema,
        context: const WebsiteAuthoringContext(
          hostClass: WebsiteAuthoringHostClass.desktop,
          previewViewport: WebsiteViewport.mobile,
          writeScope: WebsiteWriteScope.viewport,
        ),
        resolved: WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: value,
          viewport: WebsiteViewport.mobile,
          isOverride: isOverride,
          isLegacyOverride: isLegacy,
        ),
      );
    }

    test('el estado es el más fuerte de los dos ejes', () {
      final composed = WebsiteResponsiveMediaBinding.composeFocalState(
        x: axis(isOverride: true, value: 0.8),
        y: axis(isOverride: false),
      );
      expect(composed.resolved.isOverride, isTrue);
      expect(composed.resolved.value, const Offset(0.8, 0.5));
      expect(composed.status, WebsiteResponsiveFieldStatus.overridden);
    });

    test('sin override en ninguno queda heredado', () {
      final composed = WebsiteResponsiveMediaBinding.composeFocalState(
        x: axis(isOverride: false),
        y: axis(isOverride: false),
      );
      expect(composed.status, WebsiteResponsiveFieldStatus.inherited);
    });
  });
}
