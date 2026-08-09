import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_media_field.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/google_reviews_carousel.dart';
import 'package:vinabike_erp/modules/website/widgets/website_faq_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_gallery_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_team_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_testimonials_block_content.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El lote de colecciones por sus superficies reales.
///
/// El inspector es el del producto —`WebsiteBlockEditSurface` sobre el panel
/// canónico— y el consumidor es el mismo widget compartido que dibujan Edit,
/// Preview y el público. Ninguna prueba repite la fórmula de la proyección:
/// monta el árbol y mide lo que cambia.
///
/// Esta ronda no introduce ningún valor visual: reutiliza `ResponsiveFieldShell`
/// y `ResponsiveMediaField` tal como quedaron aprobados en los lotes previos.
void main() {
  // ---------------------------------------------------------------- inspector

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
      ..setDevicePreviewMode(viewport)
      ..reportRenderedBlockViewport(
        'block-1',
        switch (viewport) {
          DevicePreviewMode.desktop => WebsiteViewport.desktop,
          DevicePreviewMode.tablet => WebsiteViewport.tablet,
          DevicePreviewMode.mobile => WebsiteViewport.mobile,
        },
      );
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  List<Map<String, dynamic>> imagesOf(WebsiteEditModeProvider provider) =>
      (dataOf(provider)['images'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 2000,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  Widget host({
    required WebsiteEditModeProvider provider,
    required double editorWidth,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: editorWidth,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth),
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, watched, _) => Scaffold(
              body: WebsiteBlockEditSurface(
                editProvider: watched,
                section: WebsiteBlockEditSection.content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder shellFor(String key) => find.byWidgetPredicate(
        (widget) =>
            widget is ResponsiveFieldShell && widget.state.schema.key == key,
      );

  WebsiteResponsiveFieldState<dynamic> stateOf(
    WidgetTester tester,
    String key,
  ) =>
      (tester.widget(shellFor(key)) as ResponsiveFieldShell).state;

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> discloseSections(WidgetTester tester) async {
    int shellCount() => find
        .byWidgetPredicate((widget) => widget is ResponsiveFieldShell)
        .evaluate()
        .length;

    for (var pass = 0; pass < 2; pass++) {
      for (final title in const [
        'Contenido',
        'Diseño',
        'Texto y datos',
        'Imagen y medios',
        'Acción y enlace',
        'Otros',
      ]) {
        final header = find.text(title);
        if (header.evaluate().isEmpty) continue;
        final before = shellCount();
        await tester.tap(header.first, warnIfMissed: false);
        await settle(tester);
        if (shellCount() < before) {
          await tester.tap(header.first, warnIfMissed: false);
          await settle(tester);
        }
      }
    }
  }

  Future<void> tapShellAction(
    WidgetTester tester,
    String key,
    Key actionKey,
  ) async {
    final action = find.descendant(
      of: shellFor(key),
      matching: find.byKey(actionKey),
    );
    expect(action, findsOneWidget, reason: '$key / $actionKey');
    await tester.ensureVisible(action);
    await settle(tester);
    await tester.tap(action);
    await settle(tester);
  }

  /// Abre el menú real del selector y elige una opción, como el usuario.
  Future<void> chooseLayout(
    WidgetTester tester, {
    required String current,
    required String next,
  }) async {
    final anchor = find.descendant(
      of: shellFor('layout'),
      matching: find.text(current),
    );
    expect(anchor, findsOneWidget, reason: 'anchor $current');
    await tester.ensureVisible(anchor);
    await settle(tester);
    await tester.tap(anchor);
    await settle(tester);

    final option = find.widgetWithText(MenuItemButton, next);
    expect(option, findsOneWidget, reason: 'opción $next');
    await tester.tap(option);
    await settle(tester);
  }

  Future<WebsiteEditModeProvider> pumpBlock(
    WidgetTester tester, {
    required String type,
    required Map<String, dynamic> data,
    required double width,
    required DevicePreviewMode viewport,
    Brightness brightness = Brightness.light,
  }) async {
    useViewport(tester, width: width);
    final provider = providerFor(type, data, viewport: viewport);
    await tester.pumpWidget(
      host(provider: provider, editorWidth: width, brightness: brightness),
    );
    await settle(tester);
    await discloseSections(tester);
    return provider;
  }

  // ------------------------------------------------------------------ fixtures

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

  Map<String, dynamic> testimonialsData() => <String, dynamic>{
        'title': 'Lo que dicen nuestros clientes',
        'testimonials': <Map<String, dynamic>>[
          {
            'id': 'tst-a',
            'name': 'Carla Pérez',
            'role': 'Ciclista urbana',
            'comment': 'Quedó impecable y a tiempo.',
            'rating': 5,
          },
        ],
      };

  Map<String, dynamic> faqData() => <String, dynamic>{
        'title': 'Preguntas Frecuentes',
        'subtitle': 'Respondemos lo que más nos consultan',
        'items': <Map<String, dynamic>>[
          {
            'question': '¿Cuánto se demora una mantención?',
            'answer': 'Normalmente entre 24 y 48 horas.',
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
            'bio': 'Especialista en bike fitting.',
            'avatarUrl': 'https://cdn/daniela.webp',
            'avatarAltText': 'Daniela en el taller',
          },
        ],
      };

  Map<String, dynamic> reviewsData() => <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 4,
        'maxItems': 8,
      };

  // ------------------------------------------------------- 1 · Galería inspector

  group('1 · Galería: el diseño y la imagen del item en el inspector real', () {
    testWidgets(
        '390 Móvil y 834 Tablet: layout dice Heredado y ofrece '
        'personalizar', (tester) async {
      for (final (width, viewport, label)
          in const <(double, DevicePreviewMode, String)>[
        (390, DevicePreviewMode.mobile, 'Móvil'),
        (834, DevicePreviewMode.tablet, 'Tablet'),
      ]) {
        await pumpBlock(
          tester,
          type: 'gallery',
          data: galleryData(),
          width: width,
          viewport: viewport,
        );

        expect(shellFor('layout'), findsOneWidget, reason: '@ $width');
        expect(
          stateOf(tester, 'layout').status,
          WebsiteResponsiveFieldStatus.inherited,
          reason: '@ $width',
        );
        expect(stateOf(tester, 'layout').resolved.value, 'masonry');
        expect(
          find.descendant(
            of: shellFor('layout'),
            matching: find.text('Personalizar para $label'),
          ),
          findsOneWidget,
          reason: '@ $width',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('1440 Escritorio: layout es la base y no ofrece personalizar',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );

      expect(
        stateOf(tester, 'layout').status,
        WebsiteResponsiveFieldStatus.common,
      );
      expect(
        find.descendant(
          of: shellFor('layout'),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        ),
        findsNothing,
      );
      // Y escribe la base, sin crear contenedor responsive.
      expect(dataOf(provider)['layout'], 'masonry');
      expect(dataOf(provider).containsKey('responsive'), isFalse);
    });

    testWidgets(
        'customize + write + reset de layout en Móvil, sin cascada a '
        'Tablet', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.customizeActionKey,
      );
      expect(
        stateOf(tester, 'layout').effectiveWriteScope,
        WebsiteWriteScope.viewport,
      );
      // Personalizar sin escribir no crea dato.
      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);

      await chooseLayout(tester, current: 'Mosaico', next: 'Cuadrícula');

      final responsive = dataOf(provider)['responsive'] as Map;
      expect((responsive['mobile'] as Map)['layout'], 'grid');
      expect(
        responsive.containsKey('tablet'),
        isFalse,
        reason: 'móvil no puede arrastrar a tablet',
      );
      expect(dataOf(provider)['layout'], 'masonry', reason: 'la base intacta');
      expect(
        stateOf(tester, 'layout').status,
        WebsiteResponsiveFieldStatus.overridden,
      );

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.resetActionKey,
      );

      expect(dataOf(provider), original, reason: 'igualdad profunda');
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('Tablet escribe su propio override y no toca el de Móvil',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: <String, dynamic>{
          ...galleryData(),
          'responsive': <String, dynamic>{
            'mobile': <String, dynamic>{'layout': 'grid'},
          },
        },
        width: 834,
        viewport: DevicePreviewMode.tablet,
      );

      // Tablet no hereda del móvil: parte del valor común.
      expect(stateOf(tester, 'layout').resolved.value, 'masonry');
      expect(
        stateOf(tester, 'layout').status,
        WebsiteResponsiveFieldStatus.inherited,
      );

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.customizeActionKey,
      );
      await chooseLayout(tester, current: 'Mosaico', next: 'Cuadrícula');

      final responsive = dataOf(provider)['responsive'] as Map;
      expect((responsive['tablet'] as Map)['layout'], 'grid');
      expect(
        (responsive['mobile'] as Map)['layout'],
        'grid',
        reason: 'el override de móvil sigue siendo suyo',
      );

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.resetActionKey,
      );
      final afterReset = dataOf(provider)['responsive'] as Map;
      expect(afterReset.containsKey('tablet'), isFalse);
      expect((afterReset['mobile'] as Map)['layout'], 'grid');
    });

    testWidgets(
        'la imagen del item escribe en SU item y el alt sigue '
        'compartido', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      expect(shellFor('imageUrl'), findsOneWidget);
      expect(
        stateOf(tester, 'imageUrl').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      expect(
        stateOf(tester, 'imageUrl').resolved.value,
        'https://cdn/taller.webp',
      );

      await tapShellAction(
        tester,
        'imageUrl',
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onChanged('https://cdn/taller-vertical.webp');
      await settle(tester);

      final images = imagesOf(provider);
      expect(
        (images[0]['responsive'] as Map)['mobile'],
        containsPair('imageUrl', 'https://cdn/taller-vertical.webp'),
      );
      expect(images[0]['imageUrl'], 'https://cdn/taller.webp');
      expect(
        images[0]['altText'],
        'Mecánico ajustando una transmisión',
        reason: 'un sujeto, una descripción',
      );
      expect(images[0]['caption'], 'Puesta a punto');
      // El hermano intacto y la raíz sin la propiedad del item.
      expect(images[1].containsKey('responsive'), isFalse);
      expect(images[1]['imageUrl'], 'https://cdn/ruta.webp');
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);

      // El alt vive fuera del protocolo responsive, con su input de siempre.
      expect(shellFor('altText'), findsNothing);
      expect(find.text('Texto alternativo'), findsOneWidget);

      await tapShellAction(
        tester,
        'imageUrl',
        ResponsiveFieldShell.resetActionKey,
      );
      expect(dataOf(provider), original, reason: 'igualdad profunda');
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('el encuadre del item se personaliza y se restablece solo',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      final media = tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField));
      expect(media.focalState, isNotNull, reason: 'la galería sí reencuadra');
      media.onFocalCustomize!();
      await settle(tester);
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onFocalChanged!(0.75, 0.25);
      await settle(tester);

      final images = imagesOf(provider);
      final mobile = (images[0]['responsive'] as Map)['mobile'] as Map;
      expect(mobile['focalPointX'], 0.75);
      expect(mobile['focalPointY'], 0.25);
      expect(
        mobile.containsKey('imageUrl'),
        isFalse,
        reason: 'reencuadrar no clona el asset',
      );
      expect(images[1].containsKey('responsive'), isFalse);

      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onFocalReset!();
      await settle(tester);
      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('la fila de media no desborda a 390 dentro del repeater',
        (tester) async {
      await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.replaceActionKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.reframeActionKey), findsOneWidget);
    });
  });

  // ------------------------------------- 2 · las otras cuatro, sin control falso

  group(
      '2 · las cuatro familias compartidas no muestran ningún control '
      'responsive', () {
    for (final (type, data, visibleLabel)
        in <(String, Map<String, dynamic>, String)>[
      ('testimonials', testimonialsData(), 'Testimonios'),
      ('faq', faqData(), 'Preguntas frecuentes'),
      ('team', teamData(), 'Integrantes'),
      ('googleReviews', reviewsData(), 'Calificación mínima'),
    ]) {
      testWidgets(
          '$type a 390 en Móvil: ninguna capacidad ofrecida y sus '
          'controles intactos', (tester) async {
        final provider = await pumpBlock(
          tester,
          type: type,
          data: data,
          width: 390,
          viewport: DevicePreviewMode.mobile,
        );
        final before = dataOf(provider);

        // Nadie puede personalizar ni restablecer nada en estas familias.
        expect(
          find.byKey(ResponsiveFieldShell.customizeActionKey),
          findsNothing,
          reason: '$type no tiene ninguna propiedad responsive honesta',
        );
        expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
        for (final element in find
            .byWidgetPredicate((widget) => widget is ResponsiveFieldShell)
            .evaluate()) {
          final shell = element.widget as ResponsiveFieldShell;
          expect(
            shell.state.canCustomize || shell.state.canReset,
            isFalse,
            reason: '$type.${shell.state.schema.key}',
          );
        }
        // Y el editor de siempre sigue ahí.
        expect(find.text(visibleLabel), findsWidgets, reason: type);
        // Montar el inspector no escribe.
        expect(dataOf(provider), before);
        expect(provider.hasUnsavedChanges, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Equipo: la foto se edita, pero sin prometer un override',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'team',
        data: teamData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      final media = find.byType(ResponsiveMediaField);
      expect(media, findsOneWidget, reason: 'el picker canónico sigue ahí');
      final field = tester.widget<ResponsiveMediaField>(media);
      expect(
        field.state.status,
        WebsiteResponsiveFieldStatus.sharedOnly,
        reason: 'dice que no varía por dispositivo, en vez de callarlo',
      );
      expect(field.focalState, isNull, reason: 'el avatar no reencuadra');
      expect(find.byKey(ResponsiveMediaField.reframeActionKey), findsNothing);
      expect(
        find.byKey(ResponsiveFieldShell.customizeActionKey),
        findsNothing,
      );

      // Y escribe compartido, como siempre.
      field.onChanged('https://cdn/daniela-2.webp');
      await settle(tester);
      final member = (dataOf(provider)['members'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .single;
      expect(member['avatarUrl'], 'https://cdn/daniela-2.webp');
      expect(member.containsKey('responsive'), isFalse);
      expect(member['avatarAltText'], 'Daniela en el taller');
    });
  });

  // ------------------------------------------- 3 · anchos, brillos y targets

  group('3 · anchos, brillos y target táctil', () {
    for (final (width, viewport) in const <(double, DevicePreviewMode)>[
      (390, DevicePreviewMode.mobile),
      (834, DevicePreviewMode.tablet),
      (1440, DevicePreviewMode.desktop),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Galería a $width · $brightness sin overflow ni etiqueta '
            'duplicada', (tester) async {
          await pumpBlock(
            tester,
            type: 'gallery',
            data: galleryData(),
            width: width,
            viewport: viewport,
            brightness: brightness,
          );

          expect(shellFor('layout'), findsOneWidget);
          expect(shellFor('imageUrl'), findsOneWidget);
          // El shell pone la etiqueta una sola vez; el control interior no.
          expect(
            find.descendant(
              of: shellFor('layout'),
              matching: find.text('Diseño'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto las acciones del shell cumplen 48',
        (tester) async {
      await pumpBlock(
        tester,
        type: 'gallery',
        data: galleryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      for (final key in const <String>['layout', 'imageUrl']) {
        final action = find.descendant(
          of: shellFor(key),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        );
        await tester.ensureVisible(action);
        await settle(tester);
        expect(
          tester.getSize(action).height,
          greaterThanOrEqualTo(48),
          reason: key,
        );
      }
    });
  });

  // ---------------------------------------------- 4 · el consumidor compartido

  group('4 · el consumidor real dibuja la proyección de su viewport', () {
    Map<String, dynamic> projected(
      WebsiteBlockType type,
      Map<String, dynamic> document,
      WebsiteViewport viewport,
    ) =>
        WebsiteResponsiveBlockProjection.project(
          type: type,
          data: document,
          viewport: viewport,
        );

    Widget storefront(Widget child,
        {Brightness brightness = Brightness.light}) {
      return MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: brightness,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
    }

    final galleryDocument = <String, dynamic>{
      'title': 'Nuestro taller',
      'layout': 'masonry',
      'images': <Map<String, dynamic>>[
        {
          'id': 'img-a',
          'imageUrl': 'https://cdn/taller.webp',
          'altText': 'Mecánico ajustando una transmisión',
          'caption': 'Puesta a punto',
          'focalPointX': 0.5,
          'focalPointY': 0.5,
          'responsive': <String, dynamic>{
            'mobile': <String, dynamic>{
              'imageUrl': 'https://cdn/taller-vertical.webp',
              'focalPointX': 0.8,
            },
          },
        },
        {
          'id': 'img-b',
          'imageUrl': 'https://cdn/ruta.webp',
          'caption': 'Salida de ruta',
        },
      ],
      'responsive': <String, dynamic>{
        'mobile': <String, dynamic>{'layout': 'grid'},
      },
    };

    testWidgets('Galería: proporción, asset y encuadre cambian; el copy no',
        (tester) async {
      final observed = <WebsiteViewport, (double, String, Alignment, String)>{};

      for (final (viewport, width) in const <(WebsiteViewport, double)>[
        (WebsiteViewport.desktop, 1440),
        (WebsiteViewport.tablet, 834),
        (WebsiteViewport.mobile, 390),
      ]) {
        useViewport(tester, width: width);
        await tester.pumpWidget(
          storefront(
            WebsiteGalleryBlockContent(
              data: projected(
                WebsiteBlockType.gallery,
                galleryDocument,
                viewport,
              ),
              imageProviderBuilder: (url) => _RecordingImageProvider(url),
            ),
          ),
        );
        await settle(tester);

        final frame = tester.widget<AspectRatio>(
          find.byKey(WebsiteGalleryBlockContent.mediaFrameKey(0)),
        );
        final image = tester.widget<Image>(
          find.byKey(WebsiteGalleryBlockContent.imageKey(0)),
        );
        final provider = image.image as _RecordingImageProvider;
        final caption = tester.widget<Text>(
          find.descendant(
            of: find.byKey(WebsiteGalleryBlockContent.captionKey(0)),
            matching: find.byType(Text),
          ),
        );
        observed[viewport] = (
          frame.aspectRatio,
          provider.url,
          image.alignment as Alignment,
          caption.data ?? '',
        );
        expect(tester.takeException(), isNull, reason: '$viewport');
      }

      // Escritorio y tablet dibujan la base: mosaico (1.2 en el primer tile).
      expect(observed[WebsiteViewport.desktop]!.$1, 1.2);
      expect(observed[WebsiteViewport.tablet]!.$1, 1.2);
      // Móvil dibuja su override de layout: cuadrícula, tile cuadrado.
      expect(observed[WebsiteViewport.mobile]!.$1, 1.0);

      expect(observed[WebsiteViewport.desktop]!.$2, 'https://cdn/taller.webp');
      expect(
        observed[WebsiteViewport.tablet]!.$2,
        'https://cdn/taller.webp',
        reason: 'tablet hereda de la base, no de móvil',
      );
      expect(
        observed[WebsiteViewport.mobile]!.$2,
        'https://cdn/taller-vertical.webp',
      );

      // El encuadre efectivo llega hasta la alineación real de la imagen.
      expect(observed[WebsiteViewport.desktop]!.$3.x, 0.0);
      expect(
        observed[WebsiteViewport.mobile]!.$3.x,
        closeTo(0.6, 0.0001),
        reason: 'focalPointX 0.8 -> alignment 0.6',
      );

      // Y la leyenda es la misma en los tres.
      for (final viewport in WebsiteViewport.values) {
        expect(observed[viewport]!.$4, 'Puesta a punto', reason: '$viewport');
      }
    });

    testWidgets(
        'Galería: el ancho del tile sigue al viewport y el hermano no '
        'hereda nada', (tester) async {
      for (final (viewport, width, expectedUrl)
          in const <(WebsiteViewport, double, String)>[
        (WebsiteViewport.desktop, 1440, 'https://cdn/ruta.webp'),
        (WebsiteViewport.mobile, 390, 'https://cdn/ruta.webp'),
      ]) {
        useViewport(tester, width: width);
        await tester.pumpWidget(
          storefront(
            WebsiteGalleryBlockContent(
              data: projected(
                WebsiteBlockType.gallery,
                galleryDocument,
                viewport,
              ),
              imageProviderBuilder: (url) => _RecordingImageProvider(url),
            ),
          ),
        );
        await settle(tester);

        final tileWidth = tester
            .getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(1)))
            .width;
        if (viewport == WebsiteViewport.mobile) {
          expect(tileWidth, greaterThan(300));
        } else {
          expect(tileWidth, lessThan(400), reason: 'tres columnas');
        }
        final sibling = tester.widget<Image>(
          find.byKey(WebsiteGalleryBlockContent.imageKey(1)),
        );
        expect((sibling.image as _RecordingImageProvider).url, expectedUrl);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('el renderer canónico enruta la galería a ese mismo contenido',
        (tester) async {
      useViewport(tester, width: 390);
      await tester.pumpWidget(
        storefront(
          Builder(
            builder: (context) => WebsiteBlockRenderer.build(
              context: context,
              blockType: 'gallery',
              data: projected(
                WebsiteBlockType.gallery,
                <String, dynamic>{
                  'title': 'Nuestro taller',
                  'layout': 'masonry',
                  'images': const <Map<String, dynamic>>[],
                  'responsive': <String, dynamic>{
                    'mobile': <String, dynamic>{'layout': 'grid'},
                  },
                },
                WebsiteViewport.mobile,
              ),
              effectiveViewport: WebsiteViewport.mobile,
              primaryColor: Colors.teal,
              accentColor: Colors.tealAccent,
              previewMode: true,
            ),
          ),
        ),
      );
      await settle(tester);

      final content = tester.widget<WebsiteGalleryBlockContent>(
        find.byType(WebsiteGalleryBlockContent),
      );
      expect(content.data['layout'], 'grid');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Testimonios, FAQ y Equipo dibujan lo mismo en los tres '
        'viewports', (tester) async {
      final testimonials = <String, dynamic>{
        'title': 'Lo que dicen',
        'testimonials': <Map<String, dynamic>>[
          {
            'name': 'Carla Pérez',
            'comment': 'Quedó impecable y a tiempo.',
            'rating': 5,
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'comment': 'Otro testimonio'},
            },
          },
        ],
      };
      final faq = <String, dynamic>{
        'title': 'Preguntas Frecuentes',
        'items': <Map<String, dynamic>>[
          {
            'question': '¿Cuánto se demora una mantención?',
            'answer': 'Entre 24 y 48 horas.',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'question': 'Otra pregunta'},
            },
          },
        ],
      };
      final team = <String, dynamic>{
        'title': 'Nuestro Equipo',
        'members': <Map<String, dynamic>>[
          {
            'name': 'Daniela Torres',
            'role': 'Jefa de taller',
            'avatarUrl': 'https://cdn/daniela.webp',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'avatarUrl': 'https://cdn/otra-persona.webp',
              },
            },
          },
        ],
      };

      for (final (viewport, width) in const <(WebsiteViewport, double)>[
        (WebsiteViewport.desktop, 1440),
        (WebsiteViewport.tablet, 834),
        (WebsiteViewport.mobile, 390),
      ]) {
        useViewport(tester, width: width);

        await tester.pumpWidget(
          storefront(
            WebsiteTestimonialsBlockContent(
              data: projected(
                WebsiteBlockType.testimonials,
                testimonials,
                viewport,
              ),
              primaryColor: Colors.teal,
            ),
          ),
        );
        await settle(tester);
        expect(
          find.text('Quedó impecable y a tiempo.'),
          findsOneWidget,
          reason: '$viewport: el testimonio del cliente no cambia',
        );
        expect(find.text('Otro testimonio'), findsNothing);

        await tester.pumpWidget(
          storefront(
            WebsiteFaqBlockContent(
              data: projected(WebsiteBlockType.faq, faq, viewport),
              primaryColor: Colors.teal,
            ),
          ),
        );
        await settle(tester);
        expect(
          find.text('¿Cuánto se demora una mantención?'),
          findsOneWidget,
          reason: '$viewport',
        );
        expect(find.text('Otra pregunta'), findsNothing);

        await tester.pumpWidget(
          storefront(
            WebsiteTeamBlockContent(
              data: projected(WebsiteBlockType.team, team, viewport),
              accentColor: Colors.teal,
              imageProviderBuilder: (url) => _RecordingImageProvider(url),
            ),
          ),
        );
        await settle(tester);
        final avatar = tester.widget<Image>(
          find.descendant(
            of: find.byKey(WebsiteTeamBlockContent.memberAvatarKey(0)),
            matching: find.byType(Image),
          ),
        );
        expect(
          (avatar.image as _RecordingImageProvider).url,
          'https://cdn/daniela.webp',
          reason: '$viewport: la foto no cambia de persona',
        );
        expect(tester.takeException(), isNull, reason: '$viewport');
      }
    });
  });

  // -------------------------------------- 5 · Google Reviews: sólo lo real

  group('5 · Google Reviews: la fuente real manda', () {
    Map<String, dynamic> review({
      required String author,
      required Object? rating,
      String text = 'Reseña publicada en Google.',
    }) =>
        <String, dynamic>{
          'author_name': author,
          'rating': rating,
          'text': text,
          'relative_time': 'hace 2 semanas',
        };

    Future<void> pumpCarousel(
      WidgetTester tester,
      Map<String, dynamic> data, {
      double width = 1440,
      Brightness brightness = Brightness.light,
    }) async {
      useViewport(tester, width: width);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: brightness,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GoogleReviewsCarousel(
                data: data,
                primaryColor: Colors.teal,
                accentColor: Colors.tealAccent,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('sin reseñas reales no inventa ninguna', (tester) async {
      for (final source in <Map<String, dynamic>>[
        <String, dynamic>{'title': 'Reseñas'},
        <String, dynamic>{'title': 'Reseñas', 'reviews': <dynamic>[]},
      ]) {
        await pumpCarousel(tester, source);

        // Cero tarjetas y cero personas inventadas.
        expect(find.byType(ListView), findsNothing);
        for (final invented in const <String>[
          'Carlos Rivera',
          'Maria José Soto',
          'Felipe Andrés',
          'Andrea Pvez',
        ]) {
          expect(find.text(invented), findsNothing, reason: invented);
        }
        expect(find.byType(CircleAvatar), findsNothing);
        // Sin nota agregada real no se dibuja una nota.
        expect(find.textContaining('en Google'), findsNothing);
        expect(find.text('0.0'), findsNothing);
        // Y el título del dueño sigue ahí, con la geometría de siempre.
        expect(find.text('RESEÑAS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('filtra por minRating, respeta maxItems y conserva el orden',
        (tester) async {
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 4,
        'maxItems': 2,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Primera', rating: 5),
          review(author: 'Regular', rating: 3),
          review(author: 'Segunda', rating: 'FOUR'),
          review(author: 'Tercera', rating: '5'),
          review(author: 'Sin nota', rating: 'DESCONOCIDO'),
        ],
      });

      // Pasan las que alcanzan la nota mínima…
      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsOneWidget);
      // …y el tope corta la tercera, que sí calificaba.
      expect(find.text('Tercera'), findsNothing);
      // La que no llega, fuera.
      expect(find.text('Regular'), findsNothing);
      // Y una nota ilegible no se promueve a cinco estrellas.
      expect(find.text('Sin nota'), findsNothing);

      // El orden es el de la fuente, no uno inventado.
      final first = tester.getTopLeft(find.text('Primera')).dx;
      final second = tester.getTopLeft(find.text('Segunda')).dx;
      expect(first, lessThan(second));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'los topes del schema se respetan aunque el dato venga fuera '
        'de rango', (tester) async {
      // minRating 0 -> 1 y maxItems 99 -> 20: nada se cae por un dato viejo.
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 0,
        'maxItems': 99,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Una estrella', rating: 1),
          review(author: 'Cinco estrellas', rating: 5),
        ],
      });
      expect(find.text('Una estrella'), findsOneWidget);
      expect(find.text('Cinco estrellas'), findsOneWidget);

      // minRating 9 -> 5: sólo las perfectas.
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 9,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Cuatro', rating: 4),
          review(author: 'Cinco', rating: 5),
        ],
      });
      expect(find.text('Cuatro'), findsNothing);
      expect(find.text('Cinco'), findsOneWidget);

      // maxItems 0 -> 1: se muestra una, no ninguna.
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'maxItems': 0,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Primera', rating: 5),
          review(author: 'Segunda', rating: 5),
        ],
      });
      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el rating agregado no se sesga al filtrar las tarjetas',
        (tester) async {
      final source = <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 4,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Buena', rating: 5),
          review(author: 'Buena dos', rating: 5),
          review(author: 'Mala', rating: 2),
        ],
      };
      await pumpCarousel(tester, source);

      // Se ven dos tarjetas…
      expect(find.text('Buena'), findsOneWidget);
      expect(find.text('Mala'), findsNothing);
      // …pero la nota promedia las TRES reseñas reales: (5+5+2)/3 = 4.0.
      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('5.0'), findsNothing);

      // Y la fuente no se tocó al filtrar ni al ordenar.
      final reviews = (source['reviews'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      expect(reviews.map((item) => item['author_name']).toList(), <String>[
        'Buena',
        'Buena dos',
        'Mala',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'la nota y el total explícitos del negocio mandan sobre el '
        'cálculo', (tester) async {
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 5,
        'rating': '4.8',
        'totalReviews': 214,
        'reviews': <Map<String, dynamic>>[
          review(author: 'Perfecta', rating: 5),
          review(author: 'Mala', rating: 1),
        ],
      });

      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('en Google (214 reseñas)'), findsOneWidget);
      // Filtrar tarjetas no cambia la verdad agregada del negocio.
      expect(find.text('Perfecta'), findsOneWidget);
      expect(find.text('Mala'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el formato del título se pinta de verdad', (tester) async {
      const data = <String, dynamic>{
        'title': 'Reseñas',
        'titleFormatting': <String, dynamic>{
          'italic': true,
          'fontSize': 40.0,
          'textAlign': 'end',
        },
      };
      await pumpCarousel(tester, data);

      final title = tester.widget<Text>(find.text('RESEÑAS'));
      expect(title.style?.fontSize, 40.0);
      expect(title.style?.fontStyle, FontStyle.italic);
      expect(title.textAlign, TextAlign.end);
      // Lo que el formato no toca sigue siendo la base del bloque.
      expect(title.style?.fontWeight, FontWeight.w900);
      expect(title.style?.letterSpacing, 1.5);

      // `start` significa «sin fijar», como en el resto de los bloques: gana
      // el centrado propio del bloque.
      await pumpCarousel(tester, <String, dynamic>{
        'title': 'Reseñas',
        'titleFormatting': <String, dynamic>{'textAlign': 'left'},
      });
      expect(tester.widget<Text>(find.text('RESEÑAS')).textAlign,
          TextAlign.center);

      // Y sin formato guardado, la base intacta y centrada.
      await pumpCarousel(tester, <String, dynamic>{'title': 'Reseñas'});
      final plain = tester.widget<Text>(find.text('RESEÑAS'));
      expect(plain.style?.fontSize, 28);
      expect(plain.textAlign, TextAlign.center);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'editar los filtros en el inspector real cambia lo que la '
        'tienda muestra', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'googleReviews',
        data: <String, dynamic>{
          'title': 'Reseñas',
          'minRating': 4,
          'maxItems': 8,
          'reviews': <Map<String, dynamic>>[
            review(author: 'Cinco', rating: 5),
            review(author: 'Cuatro', rating: 4),
          ],
        },
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );

      // Los controles reales del inspector: cada slider por su rango.
      Finder sliderWithMax(double max) => find.byWidgetPredicate(
            (widget) => widget is Slider && widget.max == max,
          );
      expect(sliderWithMax(5), findsOneWidget, reason: 'minRating');
      expect(sliderWithMax(20), findsOneWidget, reason: 'maxItems');

      final minRatingSlider = tester.widget<Slider>(sliderWithMax(5));
      minRatingSlider.onChangeStart!(minRatingSlider.value);
      minRatingSlider.onChanged!(5);
      minRatingSlider.onChangeEnd!(5);
      await settle(tester);
      expect(dataOf(provider)['minRating'], 5);
      // Es un filtro de negocio: se guarda compartido, nunca como override.
      expect(dataOf(provider).containsKey('responsive'), isFalse);

      // Y el consumidor lo obedece, con la misma proyección de siempre.
      await pumpCarousel(
        tester,
        WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.googleReviews,
          data: dataOf(provider),
          viewport: WebsiteViewport.mobile,
        ),
        width: 390,
      );
      expect(find.text('Cinco'), findsOneWidget);
      expect(
        find.text('Cuatro'),
        findsNothing,
        reason: 'el inspector movió la nota mínima y la tienda lo respeta',
      );

      // El mismo camino para el tope visible.
      final second = await pumpBlock(
        tester,
        type: 'googleReviews',
        data: <String, dynamic>{
          ...dataOf(provider),
          'minRating': 1,
        },
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );
      final maxItemsSlider = tester.widget<Slider>(sliderWithMax(20));
      maxItemsSlider.onChangeStart!(maxItemsSlider.value);
      maxItemsSlider.onChanged!(1);
      maxItemsSlider.onChangeEnd!(1);
      await settle(tester);
      expect(dataOf(second)['maxItems'], 1);

      await pumpCarousel(
        tester,
        WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.googleReviews,
          data: dataOf(second),
          viewport: WebsiteViewport.desktop,
        ),
      );
      expect(find.text('Cinco'), findsOneWidget);
      expect(
        find.text('Cuatro'),
        findsNothing,
        reason: 'el tope de una tarjeta corta la segunda',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Un `ImageProvider` inerte que sólo recuerda su URL.
///
/// Deja que la prueba afirme QUÉ asset resolvió la proyección sin abrir una
/// conexión de red desde el consumidor real.
class _RecordingImageProvider extends ImageProvider<_RecordingImageProvider> {
  const _RecordingImageProvider(this.url);

  final String url;

  @override
  Future<_RecordingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_RecordingImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _RecordingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Completer<ImageInfo>().future,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _RecordingImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
