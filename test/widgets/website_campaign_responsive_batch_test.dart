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
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Campaign/cover batch through the real inspector.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c
/// (`Común` / `Heredado de Escritorio` / `Personalizado para móvil` /
/// `Restablecer al común`). No visual value is introduced by this round.
void main() {
  Map<String, dynamic> blockOf(String type, Map<String, dynamic> data) {
    return <String, dynamic>{
      'id': 'block-1',
      'block_type': type,
      'block_data': data,
      'is_visible': true,
      'sort_order': 0,
    };
  }

  WebsiteEditModeProvider providerFor(
    String type,
    Map<String, dynamic> data, {
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[blockOf(type, data)],
        const <String, dynamic>{},
      )
      ..selectBlock('block-1')
      ..setDevicePreviewMode(viewport);
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  List<Map<String, dynamic>> slidesOf(WebsiteEditModeProvider provider) =>
      (dataOf(provider)['slides'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 1600,
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
        'Overlay',
        'Imagen y encuadre',
        'Layout',
        'Estilo',
        'Diseño',
        'Contenido',
        'Fondo',
        'Botón',
        'Video',
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
    Finder shell,
    Key actionKey,
  ) async {
    final action = find.descendant(of: shell, matching: find.byKey(actionKey));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await settle(tester);
    await tester.tap(action);
    await settle(tester);
  }

  group('2 · Carrusel: el overlay del slide es del slide', () {
    Map<String, dynamic> carouselData() => <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            {
              'id': 'slide-a',
              'title': 'Uno',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
            {
              'id': 'slide-b',
              'title': 'Dos',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
          ],
        };

    testWidgets('customize + write + reset sobre showOverlay y overlayOpacity',
        (tester) async {
      useViewport(tester, width: 420);
      final provider = providerFor('carousel', carouselData());
      final original = dataOf(provider);
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      // Llega heredado: el slide no tiene override todavía.
      expect(
        stateOf(tester, 'showOverlay').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      expect(stateOf(tester, 'overlayOpacity').resolved.value, 0.55);

      // --- opacidad: personalizar, escribir ---
      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<Slider>(
            find.descendant(
              of: shellFor('overlayOpacity'),
              matching: find.byType(Slider),
            ),
          )
          .onChanged!(0.2);
      await settle(tester);

      // --- visibilidad del overlay: personalizar, escribir ---
      await tapShellAction(
        tester,
        shellFor('showOverlay'),
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<Switch>(
            find.descendant(
              of: shellFor('showOverlay'),
              matching: find.byType(Switch),
            ),
          )
          .onChanged!(false);
      await settle(tester);

      final slides = slidesOf(provider);
      final mobile = (slides[0]['responsive'] as Map)['mobile'] as Map;
      expect(mobile['overlayOpacity'], 0.2);
      expect(mobile['showOverlay'], isFalse);
      // El valor común del slide elegido sigue intacto…
      expect(slides[0]['overlayOpacity'], 0.55);
      expect(slides[0]['showOverlay'], isTrue);
      // …el hermano no se enteró…
      expect(slides[1].containsKey('responsive'), isFalse);
      expect(slides[1]['overlayOpacity'], 0.55);
      // …y la raíz del bloque nunca adquirió la propiedad del item.
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(dataOf(provider).containsKey('overlayOpacity'), isFalse);
      expect(dataOf(provider).containsKey('showOverlay'), isFalse);

      // Restablecer los dos devuelve igualdad profunda y dirty=false.
      await tapShellAction(
        tester,
        shellFor('showOverlay'),
        ResponsiveFieldShell.resetActionKey,
      );
      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.resetActionKey,
      );

      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('la media del slide conserva un solo owner y el alt compartido',
        (tester) async {
      useViewport(tester, width: 420);
      final provider = providerFor('carousel', carouselData());
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      // Un único control de media, con su editor de foco bajo demanda.
      expect(find.byType(ResponsiveMediaField), findsOneWidget);
      expect(find.text('Foco móvil'), findsNothing);

      await tapShellAction(
        tester,
        shellFor('imageUrl'),
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onChanged('https://cdn/slide-a-mobile.webp');
      await settle(tester);

      final slides = slidesOf(provider);
      expect(
        (slides[0]['responsive'] as Map)['mobile'],
        containsPair('imageUrl', 'https://cdn/slide-a-mobile.webp'),
      );
      expect(slides[1].containsKey('responsive'), isFalse);
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);

      // El alt text es del sujeto, no del viewport: sigue compartido y fuera
      // de cualquier shell.
      expect(shellFor('altText'), findsNothing);
      expect(find.text('Texto alternativo'), findsOneWidget);
    });
  });

  group('3 · CTA, Video Banner y Partners en el inspector real', () {
    const cases = <(String, Map<String, dynamic>, List<String>)>[
      (
        'cta',
        <String, dynamic>{
          'title': 'Agenda tu mantención',
          'buttonText': 'Agendar',
          'buttonLink': '/contacto',
          'backgroundImage': 'https://cdn/cta.webp',
          'overlayColor': '#000000',
          'overlayOpacity': 0.5,
        },
        <String>['backgroundImage', 'overlayColor', 'overlayOpacity'],
      ),
      (
        'videoBanner',
        <String, dynamic>{
          'title': 'Vive la experiencia',
          'imageUrl': 'https://cdn/video-fallback.webp',
          'videoUrl': 'https://youtu.be/abc',
          'showCta': true,
          'ctaText': 'Ver productos',
          'ctaLink': '/productos',
          'overlayOpacity': 0.5,
        },
        <String>['imageUrl', 'overlayOpacity', 'showCta'],
      ),
      (
        'partnersBanner',
        <String, dynamic>{
          'title': 'Partners',
          'imageUrl': 'https://cdn/partners.webp',
          'items': <Map<String, dynamic>>[
            {'label': 'Envíos a Chile'},
          ],
        },
        <String>['imageUrl'],
      ),
    ];

    for (final (type, data, responsiveKeys) in cases) {
      for (final width in <double>[390, 834]) {
        testWidgets('$type a $width dice Heredado y ofrece personalizar',
            (tester) async {
          useViewport(tester, width: width);
          final provider = providerFor(type, data);
          await tester.pumpWidget(host(provider: provider, editorWidth: width));
          await settle(tester);
          await discloseSections(tester);

          for (final key in responsiveKeys) {
            expect(shellFor(key), findsOneWidget, reason: '$type.$key');
            expect(
              stateOf(tester, key).status,
              WebsiteResponsiveFieldStatus.inherited,
              reason: '$type.$key',
            );
            expect(
              find.descendant(
                of: shellFor(key),
                matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
              ),
              findsOneWidget,
              reason: '$type.$key',
            );
          }
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('$type en Escritorio dice Común y no permite personalizar',
          (tester) async {
        useViewport(tester, width: 1440);
        final provider = providerFor(
          type,
          data,
          viewport: DevicePreviewMode.desktop,
        );
        await tester.pumpWidget(host(provider: provider, editorWidth: 1440));
        await settle(tester);
        await discloseSections(tester);

        for (final key in responsiveKeys) {
          expect(
            stateOf(tester, key).status,
            WebsiteResponsiveFieldStatus.common,
            reason: '$type.$key',
          );
          expect(
            stateOf(tester, key).effectiveWriteScope,
            WebsiteWriteScope.shared,
            reason: '$type.$key',
          );
          expect(
            find.descendant(
              of: shellFor(key),
              matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
            ),
            findsNothing,
            reason: '$type.$key',
          );
        }
      });
    }

    testWidgets('Video Banner: las dos fuentes de video siguen compartidas',
        (tester) async {
      useViewport(tester, width: 390);
      final provider = providerFor('videoBanner', cases[1].$2);
      await tester.pumpWidget(host(provider: provider, editorWidth: 390));
      await settle(tester);
      await discloseSections(tester);

      expect(shellFor('videoUrl'), findsNothing);
      expect(shellFor('videoFileUrl'), findsNothing);
      expect(shellFor('ctaText'), findsNothing);
      expect(shellFor('ctaLink'), findsNothing);
    });

    testWidgets('CTA: override + reset por el inspector real', (tester) async {
      useViewport(tester, width: 390);
      final provider = providerFor('cta', cases[0].$2);
      final original = dataOf(provider);
      await tester.pumpWidget(host(provider: provider, editorWidth: 390));
      await settle(tester);
      await discloseSections(tester);

      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<Slider>(
            find.descendant(
              of: shellFor('overlayOpacity'),
              matching: find.byType(Slider),
            ),
          )
          .onChanged!(0.85);
      await settle(tester);

      expect(dataOf(provider)['overlayOpacity'], 0.5);
      expect(
        (dataOf(provider)['responsive'] as Map)['mobile'],
        containsPair('overlayOpacity', 0.85),
      );
      expect(
        stateOf(tester, 'overlayOpacity').status,
        WebsiteResponsiveFieldStatus.overridden,
      );

      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.resetActionKey,
      );
      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });
  });

  group('5 · una sola projection para Edit, Preview y Público', () {
    test('el mismo documento resuelve por viewport en las tres superficies',
        () {
      final document = <String, dynamic>{
        'title': 'Agenda tu mantención',
        'buttonLink': '/contacto',
        'backgroundImage': 'https://cdn/cta.webp',
        'overlayOpacity': 0.5,
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{
            'overlayOpacity': 0.85,
            'backgroundImage': 'https://cdn/cta-mobile.webp',
          },
          'tablet': <String, dynamic>{'overlayOpacity': 0.7},
        },
      };

      Map<String, dynamic> projected(WebsiteViewport viewport) {
        return WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.cta,
          data: document,
          viewport: viewport,
        );
      }

      // Escritorio es la base.
      expect(projected(WebsiteViewport.desktop)['overlayOpacity'], 0.5);
      expect(
        projected(WebsiteViewport.desktop)['backgroundImage'],
        'https://cdn/cta.webp',
      );
      // Tablet toma SU override y no hereda del móvil.
      expect(projected(WebsiteViewport.tablet)['overlayOpacity'], 0.7);
      expect(
        projected(WebsiteViewport.tablet)['backgroundImage'],
        'https://cdn/cta.webp',
        reason: 'tablet hereda de la base, nunca de móvil',
      );
      // Móvil toma el suyo.
      expect(projected(WebsiteViewport.mobile)['overlayOpacity'], 0.85);
      expect(
        projected(WebsiteViewport.mobile)['backgroundImage'],
        'https://cdn/cta-mobile.webp',
      );
      // El destino compartido es el mismo en los tres.
      for (final viewport in WebsiteViewport.values) {
        expect(projected(viewport)['buttonLink'], '/contacto');
        expect(projected(viewport)['title'], 'Agenda tu mantención');
      }
    });

    test('un slide de Carrusel proyecta su propio override', () {
      final document = <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          {
            'id': 'slide-a',
            'overlayOpacity': 0.55,
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'overlayOpacity': 0.2},
            },
          },
          {'id': 'slide-b', 'overlayOpacity': 0.55},
        ],
      };

      List<Map<String, dynamic>> slides(WebsiteViewport viewport) {
        final projected = WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.carousel,
          data: document,
          viewport: viewport,
        );
        return (projected['slides'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      }

      expect(slides(WebsiteViewport.mobile)[0]['overlayOpacity'], 0.2);
      expect(slides(WebsiteViewport.mobile)[1]['overlayOpacity'], 0.55);
      expect(slides(WebsiteViewport.desktop)[0]['overlayOpacity'], 0.55);
      expect(slides(WebsiteViewport.tablet)[0]['overlayOpacity'], 0.55);
    });
  });

  group('6 · anchos, brillos y ausencia de duplicados', () {
    for (final width in <double>[390, 834, 1440]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'CTA a $width · $brightness sin overflow ni etiqueta '
            'duplicada', (tester) async {
          useViewport(tester, width: width);
          final provider = providerFor('cta', <String, dynamic>{
            'title': 'Agenda',
            'buttonLink': '/contacto',
            'backgroundImage': 'https://cdn/cta.webp',
            'overlayColor': '#000000',
            'overlayOpacity': 0.5,
          });
          await tester.pumpWidget(
            host(
              provider: provider,
              editorWidth: width,
              brightness: brightness,
            ),
          );
          await settle(tester);
          await discloseSections(tester);

          expect(shellFor('overlayOpacity'), findsOneWidget);
          expect(find.text('Opacidad de superposición'), findsOneWidget);
          expect(find.text('Color de superposición'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto la acción del shell cumple 48',
        (tester) async {
      useViewport(tester, width: 390);
      final provider = providerFor('partnersBanner', <String, dynamic>{
        'title': 'Partners',
        'imageUrl': 'https://cdn/partners.webp',
      });
      await tester.pumpWidget(host(provider: provider, editorWidth: 390));
      await settle(tester);
      await discloseSections(tester);

      final action = find.descendant(
        of: shellFor('imageUrl'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      expect(action, findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    });
  });
}
