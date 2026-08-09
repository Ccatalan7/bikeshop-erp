import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_media_field.dart';
import 'package:vinabike_erp/modules/website/widgets/website_about_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/website_features_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_services_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_stats_block_content.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El lote de contenido por sus superficies reales.
///
/// El inspector es el del producto y el consumidor es el mismo widget
/// compartido que dibujan Edit, Preview y el público. Esta ronda no introduce
/// ningún valor visual: no se consultó DesignSync porque no hay geometría,
/// color ni control nuevos — sólo política declarada y un encuadre que el
/// renderer ya tenía como `Alignment`.
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

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 2400,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Widget inspectorHost({
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

  /// Abre una sección plegable hasta que su contenido esté montado.
  ///
  /// Se comprueba contra el control esperado en vez de contar widgets: una
  /// sección cuyo único campo es compartido no cambia ningún contador, y un
  /// heurístico la volvería a cerrar sin avisar.
  Future<void> openSection(
    WidgetTester tester,
    String title,
    Finder target,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (target.evaluate().isNotEmpty) return;
      final header = find.text(title);
      if (header.evaluate().isEmpty) return;
      // El panel es una lista: un encabezado bajo el pliegue no recibe el
      // toque, y la sección quedaría cerrada.
      await tester.ensureVisible(header.first);
      await settle(tester);
      await tester.tap(header.first, warnIfMissed: false);
      await settle(tester);
    }
  }

  Future<void> discloseSections(WidgetTester tester, String type) async {
    switch (type) {
      case 'about':
        await openSection(
          tester,
          'Medios',
          find.byType(ResponsiveMediaField),
        );
        await openSection(
          tester,
          'Diseño',
          find.text('Posición de la imagen'),
        );
      case 'features':
        await openSection(tester, 'Diseño', shellFor('layout'));
      default:
        break;
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

  Future<WebsiteEditModeProvider> pumpInspector(
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
      inspectorHost(
        provider: provider,
        editorWidth: width,
        brightness: brightness,
      ),
    );
    await settle(tester);
    await discloseSections(tester, type);
    return provider;
  }

  // ------------------------------------------------------------------ fixtures

  Map<String, dynamic> aboutData() => <String, dynamic>{
        'title': 'Somos Vinabike',
        'content': 'Diez años reparando bicicletas.',
        'imageUrl': 'https://cdn/taller.webp',
        'imageAltText': 'Nuestro taller en Viña',
        'imagePosition': 'right',
      };

  Map<String, dynamic> featuresData() => <String, dynamic>{
        'title': 'Por qué elegirnos',
        'layout': 'grid',
        'features': <Map<String, dynamic>>[
          {
            'icon': 'verified',
            'title': 'Técnicos certificados',
            'description': 'Equipo con certificación oficial.',
          },
          {
            'icon': 'build',
            'title': 'Taller propio',
            'description': 'Mantenciones en el día.',
          },
        ],
      };

  Map<String, dynamic> servicesData() => <String, dynamic>{
        'title': 'Nuestros Servicios',
        'services': <Map<String, dynamic>>[
          {
            'icon': 'build',
            'title': 'Mantención completa',
            'description': 'Ajuste integral de tu bicicleta.',
          },
        ],
      };

  Map<String, dynamic> statsData() => <String, dynamic>{
        'title': 'Resultados que nos respaldan',
        'metrics': <Map<String, dynamic>>[
          {'label': 'Bicis reparadas', 'value': '1.200+'},
        ],
      };

  // ------------------------------------------------- 1 · About en el inspector

  group('1 · About: imagen responsive, posición honestamente compartida', () {
    testWidgets(
        '390 Móvil y 834 Tablet: la imagen ofrece personalizar y la '
        'posición dice que siempre es común', (tester) async {
      for (final (width, viewport, label)
          in const <(double, DevicePreviewMode, String)>[
        (390, DevicePreviewMode.mobile, 'Móvil'),
        (834, DevicePreviewMode.tablet, 'Tablet'),
      ]) {
        await pumpInspector(
          tester,
          type: 'about',
          data: aboutData(),
          width: width,
          viewport: viewport,
        );

        expect(shellFor('imageUrl'), findsOneWidget, reason: '@ $width');
        expect(
          stateOf(tester, 'imageUrl').status,
          WebsiteResponsiveFieldStatus.inherited,
          reason: '@ $width',
        );
        expect(
          find.descendant(
            of: shellFor('imageUrl'),
            matching: find.text('Personalizar para $label'),
          ),
          findsOneWidget,
        );
        // El reencuadre existe porque el renderer lo consume.
        expect(
          tester
              .widget<ResponsiveMediaField>(
                find.byType(ResponsiveMediaField),
              )
              .focalState,
          isNotNull,
          reason: '@ $width',
        );

        // La posición sigue editable con su control de siempre, y fuera del
        // protocolo: nunca ofrece un override que el renderer no honraría.
        expect(
          shellFor('imagePosition'),
          findsNothing,
          reason: '@ $width: una propiedad compartida no entra al shell',
        );
        expect(find.text('Posición de la imagen'), findsOneWidget);
        expect(
          find.descendant(
            of: shellFor('imageUrl'),
            matching: find.byKey(ResponsiveFieldShell.resetActionKey),
          ),
          findsNothing,
          reason: 'sin override todavía no hay nada que restablecer',
        );
        expect(tester.takeException(), isNull, reason: '@ $width');
      }
    });

    testWidgets('1440 Escritorio: la imagen es la base y no ofrece override',
        (tester) async {
      await pumpInspector(
        tester,
        type: 'about',
        data: aboutData(),
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );

      expect(
        stateOf(tester, 'imageUrl').status,
        WebsiteResponsiveFieldStatus.common,
      );
      expect(
        find.byKey(ResponsiveFieldShell.customizeActionKey),
        findsNothing,
      );
    });

    testWidgets('compartido → override móvil → reset, con asset y encuadre',
        (tester) async {
      final provider = await pumpInspector(
        tester,
        type: 'about',
        data: aboutData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      await tapShellAction(
        tester,
        'imageUrl',
        ResponsiveFieldShell.customizeActionKey,
      );
      final media = tester.widget<ResponsiveMediaField>(
        find.byType(ResponsiveMediaField),
      );
      media.onChanged('https://cdn/taller-vertical.webp');
      await settle(tester);
      media.onFocalCustomize!();
      await settle(tester);
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onFocalChanged!(0.8, 0.2);
      await settle(tester);

      final mobile = overrideOf(dataOf(provider), 'mobile');
      expect(mobile['imageUrl'], 'https://cdn/taller-vertical.webp');
      expect(mobile['focalPointX'], 0.8);
      expect(mobile['focalPointY'], 0.2);
      // La base y el alt no se movieron, y tablet no heredó nada.
      expect(dataOf(provider)['imageUrl'], 'https://cdn/taller.webp');
      expect(dataOf(provider)['imageAltText'], 'Nuestro taller en Viña');
      expect(dataOf(provider)['imagePosition'], 'right');
      expect(overrideOf(dataOf(provider), 'tablet'), isEmpty);
      // Un override nunca duplica el alias de migración.
      expect(mobile.containsKey('image'), isFalse);

      await tapShellAction(
        tester,
        'imageUrl',
        ResponsiveFieldShell.resetActionKey,
      );
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onFocalReset!();
      await settle(tester);

      expect(dataOf(provider), original, reason: 'igualdad profunda');
      expect(provider.hasUnsavedChanges, isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
    });

    testWidgets('el texto alternativo sigue fuera del protocolo responsive',
        (tester) async {
      await pumpInspector(
        tester,
        type: 'about',
        data: aboutData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      expect(shellFor('imageAltText'), findsNothing);
      expect(find.text('Texto alternativo'), findsOneWidget);
      expect(shellFor('title'), findsNothing);
      expect(shellFor('content'), findsNothing);
    });
  });

  // ------------------------------------------- 2 · Features en el inspector

  group('2 · Features: el diseño por viewport', () {
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

    testWidgets('override móvil a lista, tablet aislado y reset sin cascada',
        (tester) async {
      final provider = await pumpInspector(
        tester,
        type: 'features',
        data: featuresData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      expect(
        stateOf(tester, 'layout').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.customizeActionKey,
      );
      await chooseLayout(tester, current: 'Cuadrícula', next: 'Lista');

      expect(overrideOf(dataOf(provider), 'mobile')['layout'], 'list');
      expect(dataOf(provider)['layout'], 'grid', reason: 'base intacta');
      expect(overrideOf(dataOf(provider), 'tablet'), isEmpty);
      // La colección no se movió.
      expect((dataOf(provider)['features'] as List).length, 2);

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.resetActionKey,
      );
      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('tablet escribe el suyo sin tocar el de móvil', (tester) async {
      final provider = await pumpInspector(
        tester,
        type: 'features',
        data: <String, dynamic>{
          ...featuresData(),
          'responsive': <String, dynamic>{
            'mobile': <String, dynamic>{'layout': 'list'},
          },
        },
        width: 834,
        viewport: DevicePreviewMode.tablet,
      );

      expect(stateOf(tester, 'layout').resolved.value, 'grid');
      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.customizeActionKey,
      );
      await chooseLayout(tester, current: 'Cuadrícula', next: 'Lista');

      expect(overrideOf(dataOf(provider), 'tablet')['layout'], 'list');
      expect(overrideOf(dataOf(provider), 'mobile')['layout'], 'list');
      expect(dataOf(provider)['layout'], 'grid');

      await tapShellAction(
        tester,
        'layout',
        ResponsiveFieldShell.resetActionKey,
      );
      expect(overrideOf(dataOf(provider), 'tablet'), isEmpty);
      expect(
        overrideOf(dataOf(provider), 'mobile')['layout'],
        'list',
        reason: 'restablecer tablet no toca móvil',
      );
    });
  });

  // --------------------------------- 3 · Servicios e Indicadores sin capacidad

  group('3 · Servicios e Indicadores: auto-layout, sin controles falsos', () {
    for (final (type, data, visibleLabel)
        in <(String, Map<String, dynamic>, String)>[
      ('services', servicesData(), 'Servicios'),
      ('stats', statsData(), 'Indicadores'),
    ]) {
      testWidgets('$type a 390 en Móvil no ofrece ninguna personalización',
          (tester) async {
        final provider = await pumpInspector(
          tester,
          type: type,
          data: data,
          width: 390,
          viewport: DevicePreviewMode.mobile,
        );
        final before = dataOf(provider);

        expect(
          find.byKey(ResponsiveFieldShell.customizeActionKey),
          findsNothing,
          reason: '$type compone por ancho, no por dato',
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
        // Y su editor de siempre sigue ahí, sin escribir por montarse.
        expect(find.text(visibleLabel), findsWidgets);
        expect(dataOf(provider), before);
        expect(provider.hasUnsavedChanges, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // -------------------------------------------- 4 · anchos, brillos y targets

  group('4 · anchos, brillos y target táctil', () {
    for (final (width, viewport) in const <(double, DevicePreviewMode)>[
      (390, DevicePreviewMode.mobile),
      (834, DevicePreviewMode.tablet),
      (1440, DevicePreviewMode.desktop),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'About a $width · $brightness sin overflow ni etiqueta '
            'duplicada', (tester) async {
          await pumpInspector(
            tester,
            type: 'about',
            data: aboutData(),
            width: width,
            viewport: viewport,
            brightness: brightness,
          );

          expect(shellFor('imageUrl'), findsOneWidget);
          // Una etiqueta por campo: el shell la pone para la imagen, y el
          // control compartido la suya.
          expect(find.text('Imagen'), findsOneWidget);
          expect(find.text('Posición de la imagen'), findsOneWidget);
          expect(shellFor('imagePosition'), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Features a $width · $brightness sin overflow',
            (tester) async {
          await pumpInspector(
            tester,
            type: 'features',
            data: featuresData(),
            width: width,
            viewport: viewport,
            brightness: brightness,
          );

          expect(shellFor('layout'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto las acciones del shell cumplen 48',
        (tester) async {
      await pumpInspector(
        tester,
        type: 'about',
        data: aboutData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final action = find.descendant(
        of: shellFor('imageUrl'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      await tester.ensureVisible(action);
      await settle(tester);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    });
  });

  // ---------------------------------------------- 5 · el consumidor compartido

  group('5 · el consumidor real dibuja la proyección de su viewport', () {
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

    Widget storefront(Widget child) => MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    final aboutDocument = <String, dynamic>{
      'title': 'Somos Vinabike',
      'content': 'Diez años reparando bicicletas.',
      'imageUrl': 'https://cdn/taller.webp',
      'imageAltText': 'Nuestro taller en Viña',
      'imagePosition': 'right',
      'focalPointX': 0.5,
      'focalPointY': 0.5,
      'responsive': <String, dynamic>{
        'mobile': <String, dynamic>{
          'imageUrl': 'https://cdn/taller-vertical.webp',
          'focalPointX': 0.8,
          'focalPointY': 0.2,
        },
      },
    };

    testWidgets(
        'About: el encuadre resuelto llega a la imagen, y Edit dibuja '
        'el mismo árbol', (tester) async {
      // `focalPointX/Y` 0..1 se convierten en la alineación -1..1 que la
      // imagen ya usaba: 0.5 es el centro histórico, 0.8/0.2 el encuadre
      // móvil autorizado.
      for (final (viewport, width, alignX, alignY, url)
          in <(WebsiteViewport, double, double, double, String)>[
        (WebsiteViewport.desktop, 1440, 0.0, 0.0, 'https://cdn/taller.webp'),
        (WebsiteViewport.tablet, 834, 0.0, 0.0, 'https://cdn/taller.webp'),
        (
          WebsiteViewport.mobile,
          390,
          0.6,
          -0.6,
          'https://cdn/taller-vertical.webp'
        ),
      ]) {
        useViewport(tester, width: width);
        final data = projected(WebsiteBlockType.about, aboutDocument, viewport);

        // Público: la imagen real recibe la alineación resuelta.
        await tester.pumpWidget(
          storefront(WebsiteAboutBlockContent(data: data)),
        );
        await settle(tester);
        final image = tester.widget<Image>(
          find.byKey(const ValueKey<String>('website-about-image')),
        );
        final publicAlignment = image.alignment as Alignment;
        expect(publicAlignment.x, closeTo(alignX, 0.0001), reason: '$viewport');
        expect(publicAlignment.y, closeTo(alignY, 0.0001), reason: '$viewport');
        expect((image.image as NetworkImage).url, url, reason: '$viewport');

        // Edit: el slot que recibe el presenter trae exactamente lo mismo.
        WebsiteInlineMediaSlot? captured;
        await tester.pumpWidget(
          storefront(
            WebsiteAboutBlockContent(
              data: data,
              presenters: WebsiteBlockContentPresenters(
                media: (context, slot) {
                  captured = slot;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        await settle(tester);
        expect(captured, isNotNull, reason: '$viewport');
        expect(captured!.alignment.x, closeTo(alignX, 0.0001),
            reason: '$viewport');
        expect(captured!.alignment.y, closeTo(alignY, 0.0001),
            reason: '$viewport');
        expect(captured!.url, url, reason: '$viewport');
        expect(captured!.semanticLabel, 'Nuestro taller en Viña');
        // Y la composición sigue siendo la misma de siempre en ese ancho.
        expect(
          find.byKey(
            ValueKey<String>(
              viewport == WebsiteViewport.desktop
                  ? 'website-about-desktop-layout'
                  : 'website-about-stacked-layout',
            ),
          ),
          findsOneWidget,
          reason: '$viewport',
        );
      }
    });

    testWidgets('Features: cuadrícula en escritorio y lista en móvil',
        (tester) async {
      final document = <String, dynamic>{
        ...featuresData(),
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'layout': 'list'},
        },
      };

      for (final (viewport, width, expectGrid)
          in const <(WebsiteViewport, double, bool)>[
        (WebsiteViewport.desktop, 1440, true),
        (WebsiteViewport.tablet, 834, true),
        (WebsiteViewport.mobile, 390, false),
      ]) {
        useViewport(tester, width: width);
        await tester.pumpWidget(
          storefront(
            WebsiteFeaturesBlockContent(
              data: projected(WebsiteBlockType.features, document, viewport),
              primaryColor: Colors.teal,
            ),
          ),
        );
        await settle(tester);

        expect(
          find.byKey(WebsiteFeaturesBlockContent.gridKey),
          expectGrid ? findsOneWidget : findsNothing,
          reason: '$viewport',
        );
        expect(
          find.byKey(WebsiteFeaturesBlockContent.listKey),
          expectGrid ? findsNothing : findsOneWidget,
          reason: '$viewport',
        );
        // El contenido es el mismo en los tres.
        expect(find.text('Técnicos certificados'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$viewport');
      }
    });

    testWidgets('Servicios e Indicadores conservan su auto-layout',
        (tester) async {
      for (final (viewport, width) in const <(WebsiteViewport, double)>[
        (WebsiteViewport.desktop, 1440),
        (WebsiteViewport.mobile, 390),
      ]) {
        useViewport(tester, width: width);

        await tester.pumpWidget(
          storefront(
            WebsiteServicesBlockContent(
              data: projected(
                WebsiteBlockType.services,
                servicesData(),
                viewport,
              ),
              primaryColor: Colors.teal,
            ),
          ),
        );
        await settle(tester);
        expect(find.text('Mantención completa'), findsOneWidget);
        expect(
          find.byKey(WebsiteServicesBlockContent.collectionKey),
          findsOneWidget,
          reason: '$viewport',
        );

        await tester.pumpWidget(
          storefront(
            WebsiteStatsBlockContent(
              data: projected(WebsiteBlockType.stats, statsData(), viewport),
              primaryColor: Colors.teal,
              accentColor: Colors.tealAccent,
            ),
          ),
        );
        await settle(tester);
        expect(find.text('1.200+'), findsOneWidget, reason: '$viewport');
        expect(tester.takeException(), isNull, reason: '$viewport');
      }
    });
  });

  // ------------------------------------------ 6 · el inline pasa por el owner

  group('6 · la edición inline escribe donde corresponde', () {
    testWidgets('el título de una característica escribe en su item',
        (tester) async {
      useViewport(tester, width: 390);
      final provider = providerFor('features', featuresData());
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
                    blockType: 'features',
                    data: Map<String, dynamic>.from(
                      watched.blocks.single['block_data'] as Map,
                    ),
                    effectiveViewport: WebsiteViewport.mobile,
                    primaryColor: Colors.teal,
                    accentColor: Colors.tealAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      tester
          .widget<InlineEditableTextV2>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is InlineEditableTextV2 &&
                  widget.text == 'Técnicos certificados',
            ),
          )
          .onTextChanged!('Técnicos con certificación');
      await settle(tester);

      final features = (dataOf(provider)['features'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      expect(features[0]['title'], 'Técnicos con certificación');
      expect(features[1]['title'], 'Taller propio', reason: 'el hermano');
      expect(
        dataOf(provider)['title'],
        'Por qué elegirnos',
        reason: 'la raíz no adquiere el título del item',
      );
      expect(features[0].containsKey('responsive'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
