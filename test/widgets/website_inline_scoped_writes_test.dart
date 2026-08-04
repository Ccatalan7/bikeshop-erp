import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_image.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/text_formatting_toolbar.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// The inline half of the responsive protocol, through the real edit renderer.
///
/// Every gesture here is the one the product mounts — `InlineEditableTextV2`,
/// `InlineEditableImage`, `WebsiteInlineActionEditor` — driven by the callback
/// the presenter wired, against the real provider. Before
/// `WebsiteInlineResponsiveWriter` existed these callbacks wrote the shared
/// base no matter which viewport the canvas was rendering, so a phone edit
/// silently overwrote desktop.
///
/// No visual value is introduced: this round adds no control and no style.
void main() {
  WebsiteEditModeProvider providerFor(
    String type,
    Map<String, dynamic> data, {
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          {
            'id': 'block-1',
            'block_type': type,
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('block-1')
      ..setDevicePreviewMode(viewport);
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  List<Map<String, dynamic>> itemsOf(
    WebsiteEditModeProvider provider,
    String key,
  ) =>
      (dataOf(provider)[key] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  Map<String, dynamic> overrideOf(
    Map<String, dynamic> node,
    String viewport,
  ) {
    final container = node['responsive'];
    if (container is! Map) return const <String, dynamic>{};
    final values = container[viewport];
    return values is Map
        ? Map<String, dynamic>.from(values)
        : const <String, dynamic>{};
  }

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<WebsiteEditModeProvider> pumpBlock(
    WidgetTester tester, {
    required String type,
    required Map<String, dynamic> data,
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);

    final provider = providerFor(type, data, viewport: viewport);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Consumer<WebsiteEditModeProvider>(
                builder: (context, watched, _) => EditableBlockRenderer.build(
                  context: context,
                  blockId: 'block-1',
                  blockType: type,
                  data: Map<String, dynamic>.from(
                    watched.blocks.single['block_data'] as Map,
                  ),
                  primaryColor: Colors.teal,
                  accentColor: Colors.tealAccent,
                  onNavigate: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return provider;
  }

  /// Promotes the next write of one property to the previewed viewport, the
  /// same operation the visible `Personalizar` action performs.
  void customize(
    WebsiteEditModeProvider provider,
    String propertyKey, {
    required WebsiteResponsivePropertyPolicy policy,
    List<String>? collectionKeys,
    int itemIndex = 0,
    String? identityKey,
    Object? identityValue,
  }) {
    if (collectionKeys == null) {
      provider.setFieldWriteScope(
        blockId: 'block-1',
        propertyKey: propertyKey,
        policy: policy,
        scope: WebsiteWriteScope.viewport,
      );
      return;
    }
    provider.setRepeaterFieldWriteScope(
      blockId: 'block-1',
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      propertyKey: propertyKey,
      policy: policy,
      scope: WebsiteWriteScope.viewport,
      identityKey: identityKey,
      identityValue: identityValue,
    );
  }

  InlineEditableImage imageAt(WidgetTester tester, int index) => tester
      .widgetList<InlineEditableImage>(find.byType(InlineEditableImage))
      .elementAt(index);

  InlineEditableTextV2 textWith(WidgetTester tester, String value) =>
      tester.widget<InlineEditableTextV2>(
        find.byWidgetPredicate(
          (widget) => widget is InlineEditableTextV2 && widget.text == value,
        ),
      );

  // --------------------------------------------------------------- fixtures

  Map<String, dynamic> heroData() => <String, dynamic>{
        'title': 'Tu tienda de bicicletas',
        'subtitle': 'Reparamos y equipamos',
        'ctaText': 'Ver catálogo',
        'ctaLink': '/productos',
        'imageUrl': 'https://cdn/hero.webp',
        'imageAltText': 'Taller de bicicletas',
      };

  Map<String, dynamic> galleryData() => <String, dynamic>{
        'title': 'Nuestro taller',
        'layout': 'masonry',
        'images': <Map<String, dynamic>>[
          {
            'id': 'img-a',
            'imageUrl': 'https://cdn/taller.webp',
            'altText': 'Mecánico ajustando una transmisión',
            'caption': 'Puesta a punto',
          },
          {
            'id': 'img-b',
            'imageUrl': 'https://cdn/ruta.webp',
            'caption': 'Salida de ruta',
          },
        ],
      };

  Map<String, dynamic> teamData() => <String, dynamic>{
        'title': 'Nuestro Equipo',
        'members': <Map<String, dynamic>>[
          {
            'id': 'mbr-a',
            'name': 'Daniela Torres',
            'role': 'Jefa de taller',
            'avatarUrl': 'https://cdn/daniela.webp',
            'image': 'https://cdn/daniela.webp',
            'avatarAltText': 'Daniela en el taller',
          },
        ],
      };

  // ------------------------------------------------- A · media root scoped

  group('A · media de raíz en móvil con alcance de viewport', () {
    testWidgets('la edición inline escribe el override y respeta la base',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'hero',
        data: heroData(),
      );
      customize(
        provider,
        'imageUrl',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      imageAt(tester, 0).onChanged!('https://cdn/hero-vertical.webp');
      await settle(tester);

      final data = dataOf(provider);
      expect(
        overrideOf(data, 'mobile')['imageUrl'],
        'https://cdn/hero-vertical.webp',
      );
      expect(data['imageUrl'], 'https://cdn/hero.webp', reason: 'base intacta');
      // Un override jamás duplica el alias de migración dentro suyo.
      expect(
          overrideOf(data, 'mobile').containsKey('backgroundImage'), isFalse);
      expect(overrideOf(data, 'tablet'), isEmpty, reason: 'sin cascada');
      // Y el alt sigue siendo uno solo, compartido.
      expect(data['imageAltText'], 'Taller de bicicletas');
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------- B · repeater scoped por item

  group('B · media de un item en móvil con alcance de viewport', () {
    testWidgets('sólo el item activo, sólo móvil, y el reset devuelve todo',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
      );
      final original = dataOf(provider);
      customize(
        provider,
        'imageUrl',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        collectionKeys: const <String>['images'],
        identityKey: 'id',
        identityValue: 'img-a',
      );

      imageAt(tester, 0).onChanged!('https://cdn/taller-vertical.webp');
      await settle(tester);

      final images = itemsOf(provider, 'images');
      expect(
        overrideOf(images[0], 'mobile')['imageUrl'],
        'https://cdn/taller-vertical.webp',
      );
      expect(images[0]['imageUrl'], 'https://cdn/taller.webp');
      expect(images[0]['altText'], 'Mecánico ajustando una transmisión');
      // El hermano no se entera, y la raíz no adquiere la propiedad del item.
      expect(images[1].containsKey('responsive'), isFalse);
      expect(images[1]['imageUrl'], 'https://cdn/ruta.webp');
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);

      provider.clearBlockRepeaterItemResponsiveOverride(
        'block-1',
        collectionKeys: const <String>['images'],
        itemIndex: 0,
        propertyKey: 'imageUrl',
        policies: const <String, WebsiteResponsivePropertyPolicy>{
          'imageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
        },
        identityKey: 'id',
        identityValue: 'img-a',
      );
      await settle(tester);
      expect(dataOf(provider), original, reason: 'igualdad profunda');
      expect(provider.hasUnsavedChanges, isFalse);
    });
  });

  // ------------------------------------------------ C · alcance común móvil

  group('C · alcance común en móvil', () {
    testWidgets('media de raíz actualiza canónica y alias en una sola entrada',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'cta',
        data: <String, dynamic>{
          'title': 'Agenda tu mantención',
          'buttonText': 'Agendar',
          'buttonLink': '/contacto',
          'backgroundImage': 'https://cdn/cta.webp',
          'imageUrl': 'https://cdn/cta.webp',
        },
      );
      final historyBefore = provider.canUndo;

      imageAt(tester, 0).onChanged!('https://cdn/cta-2.webp');
      await settle(tester);

      final data = dataOf(provider);
      expect(data['backgroundImage'], 'https://cdn/cta-2.webp');
      expect(
        data['imageUrl'],
        'https://cdn/cta-2.webp',
        reason: 'el alias que el producto todavía lee viaja con la base',
      );
      expect(data.containsKey('responsive'), isFalse);
      expect(provider.canUndo, isTrue);
      expect(historyBefore, isFalse);

      // Una sola entrada de historial: un undo devuelve las DOS claves.
      provider.undo();
      await settle(tester);
      expect(dataOf(provider)['backgroundImage'], 'https://cdn/cta.webp');
      expect(dataOf(provider)['imageUrl'], 'https://cdn/cta.webp');
    });
  });

  // ---------------------------------------------------- D · Equipo shared

  group('D · Equipo: la foto es compartida por contrato', () {
    testWidgets('avatarUrl e image se actualizan juntos y no admiten override',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'team',
        data: teamData(),
      );

      // Aunque alguien pida personalizar, `sharedOnly` coacciona a común.
      customize(
        provider,
        'avatarUrl',
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        collectionKeys: const <String>['members', 'team', 'items'],
        identityKey: 'id',
        identityValue: 'mbr-a',
      );

      imageAt(tester, 0).onChanged!('https://cdn/daniela-2.webp');
      await settle(tester);

      final member = itemsOf(provider, 'members').single;
      expect(member['avatarUrl'], 'https://cdn/daniela-2.webp');
      expect(
        member['image'],
        'https://cdn/daniela-2.webp',
        reason: 'el alias legacy no puede quedarse con la foto vieja',
      );
      expect(member.containsKey('responsive'), isFalse);
      expect(member['avatarAltText'], 'Daniela en el taller');
    });
  });

  // -------------------------------------- E · escalares reales del presenter

  group('E · texto, formato y ancho desde el presenter', () {
    testWidgets('maxWidth respeta el alcance de viewport y el copy no',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'text',
        data: <String, dynamic>{
          'text': 'Cuidamos tu bicicleta',
          'maxWidth': 720.0,
        },
      );

      // `maxWidth` es presentación declarada: puede personalizarse.
      customize(
        provider,
        'maxWidth',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      final editable = textWith(tester, 'Cuidamos tu bicicleta');
      editable.onWidthChanged!(320);
      await settle(tester);

      expect(overrideOf(dataOf(provider), 'mobile')['maxWidth'], 320);
      expect(dataOf(provider)['maxWidth'], 720.0, reason: 'base intacta');

      // El texto es `sharedOnly`: ni pidiendo personalizar deja de ser común.
      customize(
        provider,
        'text',
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      textWith(tester, 'Cuidamos tu bicicleta').onTextChanged!('Texto nuevo');
      await settle(tester);
      expect(dataOf(provider)['text'], 'Texto nuevo');
      expect(
        overrideOf(dataOf(provider), 'mobile').containsKey('text'),
        isFalse,
        reason: 'el copy indexable no puede divergir por dispositivo',
      );

      // Y el formato sigue la política de la propiedad que lo posee.
      textWith(tester, 'Texto nuevo').onFormattingChanged!(
        const TextFormatting(isBold: true),
      );
      await settle(tester);
      expect(dataOf(provider)['formatting'], containsPair('bold', true));
      expect(
        overrideOf(dataOf(provider), 'mobile').containsKey('formatting'),
        isFalse,
      );
    });

    testWidgets('el texto de un item escribe en su item, no en la raíz',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
      );

      textWith(tester, 'Puesta a punto').onTextChanged!('Puesta a punto 2026');
      await settle(tester);

      final images = itemsOf(provider, 'images');
      expect(images[0]['caption'], 'Puesta a punto 2026');
      expect(images[1]['caption'], 'Salida de ruta');
      expect(dataOf(provider).containsKey('caption'), isFalse);
    });
  });

  // ------------------------------------------------------------- F · acción

  group('F · acción inline', () {
    testWidgets('label y destino siguen compartidos, con paridad de alias',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'hero',
        data: heroData(),
      );
      // Aunque el alcance esté en viewport para la propiedad, `sharedOnly`
      // manda: un destino no puede divergir por dispositivo.
      customize(
        provider,
        'ctaLink',
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );

      final editor = tester.widget<WebsiteInlineActionEditor>(
        find.byType(WebsiteInlineActionEditor),
      );
      editor.onChanged(
        const WebsiteActionValue(
          label: 'Agendar hora',
          href: '/contacto',
          variant: WebsiteActionVariant.filled,
        ),
      );
      await settle(tester);

      final data = dataOf(provider);
      expect(data['ctaText'], 'Agendar hora');
      expect(data['ctaLink'], '/contacto');
      // Los alias que el producto todavía lee viajan con el valor común.
      expect(data['buttonText'], 'Agendar hora');
      expect(data['buttonLink'], '/contacto');
      expect(data['actionVariant'], 'filled');
      expect(data.containsKey('responsive'), isFalse);
      // Y el compuesto conserva la paridad.
      final actions = (data['actions'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      final primary = actions.firstWhere(
        (action) => action['type'] == 'navigate',
      );
      expect(primary['label'], 'Agendar hora');
      expect(primary['to'], '/contacto');
      expect(primary['variant'], 'filled');
      expect(tester.takeException(), isNull);
    });

    testWidgets('una acción es una sola entrada de historial', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'hero',
        data: heroData(),
      );
      final original = dataOf(provider);

      tester
          .widget<WebsiteInlineActionEditor>(
            find.byType(WebsiteInlineActionEditor),
          )
          .onChanged(
            const WebsiteActionValue(label: 'Agendar', href: '/contacto'),
          );
      await settle(tester);
      expect(dataOf(provider)['ctaText'], 'Agendar');

      provider.undo();
      await settle(tester);
      expect(
        dataOf(provider),
        original,
        reason: 'un gesto, un undo: label, destino, variante y compuesto',
      );
    });
  });

  // -------------------------------------------------- G · tablet y escritorio

  group('G · tablet aislado y escritorio como base', () {
    testWidgets('tablet escribe su propio override sin tocar el de móvil',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'hero',
        data: <String, dynamic>{
          ...heroData(),
          'responsive': <String, dynamic>{
            'mobile': <String, dynamic>{'imageUrl': 'https://cdn/movil.webp'},
          },
        },
        viewport: DevicePreviewMode.tablet,
        width: 834,
      );
      customize(
        provider,
        'imageUrl',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      imageAt(tester, 0).onChanged!('https://cdn/tablet.webp');
      await settle(tester);

      final data = dataOf(provider);
      expect(overrideOf(data, 'tablet')['imageUrl'], 'https://cdn/tablet.webp');
      expect(overrideOf(data, 'mobile')['imageUrl'], 'https://cdn/movil.webp');
      expect(data['imageUrl'], 'https://cdn/hero.webp');
    });

    testWidgets('en escritorio toda edición inline es la base', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'hero',
        data: heroData(),
        viewport: DevicePreviewMode.desktop,
        width: 1440,
      );
      // Incluso pidiendo viewport: Escritorio ES la base.
      customize(
        provider,
        'imageUrl',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      imageAt(tester, 0).onChanged!('https://cdn/hero-2.webp');
      await settle(tester);

      final data = dataOf(provider);
      expect(data['imageUrl'], 'https://cdn/hero-2.webp');
      expect(data.containsKey('responsive'), isFalse);
    });
  });

  // ---------------------------------------------------- H · guard de owner

  group('H · el presenter no vuelve a escribir por su cuenta', () {
    final rendererSource =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();

    test('los presenters pasan por el writer canónico', () {
      expect(rendererSource, contains('WebsiteInlineResponsiveWriter('));
      expect(rendererSource, contains('WebsiteInlinePropertyWrite('));
      expect(
        rendererSource,
        isNot(contains('updateBoundValues')),
        reason: 'ese helper escribía la base sin mirar viewport ni policy',
      );
      expect(
        rendererSource,
        isNot(contains('editProvider.updateBlockDataMultiple(')),
        reason: 'ningún write schema-bound puede saltarse el protocolo',
      );
    });

    test('la geometría de Canvas ya pasa por sus comandos atómicos', () {
      // Era la única excepción: el renderer reescribía `elements` entero por
      // el writer de repeaters. 7B la cerró — la estructura y las propiedades
      // de una capa se escriben por identidad, una transacción cada una — así
      // que lo que se afirma aquí es que NO queda ningún writer crudo.
      expect(
        'updateBlockRepeaterItemMultiple('.allMatches(rendererSource).length,
        0,
        reason: 'ningún write de Canvas se hace reemplazando la colección',
      );
      expect(
        rendererSource,
        isNot(contains("updates: <String, dynamic>{'elements': elements}")),
      );
      expect(rendererSource, contains('WebsiteCanvasEditorBinding('));
      for (final command in const <String>[
        'editProvider.insertCanvasLayer(',
        'editProvider.removeCanvasLayer(',
        'editProvider.duplicateCanvasLayer(',
        'editProvider.setCanvasLayerProperties(',
        'editProvider.clearCanvasLayerOverrides(',
        'editProvider.reorderCanvasLayer(',
      ]) {
        expect(rendererSource, contains(command));
      }
    });

    test('la media canónica adopta la regla de companions del escalar', () {
      final mediaSource = File(
        'lib/modules/website/widgets/website_responsive_media_binding.dart',
      ).readAsStringSync();
      expect(
        mediaSource,
        contains('WebsiteResponsiveScalarBinding<String>.forField('),
      );
      expect(
        mediaSource,
        isNot(contains('provider.setBlockResponsiveProperty(')),
        reason: 'el asset ya no tiene una segunda implementación de escritura',
      );
      expect(
        mediaSource,
        isNot(contains('provider.setBlockRepeaterItemResponsiveProperty(')),
      );
    });
  });
}
