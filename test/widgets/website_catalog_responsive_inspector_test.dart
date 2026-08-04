import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_media_field.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Catalogue batch through the real inspectors.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c. The batch
/// adds no control and no visual value: Products reuses its own chips and
/// toggle inside the approved `ResponsiveFieldShell`, and Category/Brand go
/// through the generic schema path.
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
        'Diseño de productos',
        'Información visible',
        'Diseño',
        'Contenido',
        'Imagen y medios',
        'Texto y datos',
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

  Map<String, dynamic> productsData() => <String, dynamic>{
        'title': 'Productos Destacados',
        'productSource': 'featured',
        'maxProducts': 8,
        'itemsPerRow': 4,
        'showViewAll': true,
        'showPrice': true,
        'viewAllText': 'Ver todos los productos',
        'viewAllLink': '/productos',
      };

  Map<String, dynamic> categoryData() => <String, dynamic>{
        'title': 'Explora por categoría',
        'subtitle': 'Elige tu terreno',
        'categories': <Map<String, dynamic>>[
          {
            'id': 'cat-a',
            'title': 'MTB',
            'link': '/productos',
            'altText': 'Bicicletas de montaña',
            'imageUrl': 'https://cdn/mtb.webp',
          },
          {
            'id': 'cat-b',
            'title': 'Ruta',
            'link': '/productos',
            'imageUrl': 'https://cdn/ruta.webp',
          },
        ],
      };

  Map<String, dynamic> brandData() => <String, dynamic>{
        'title': 'Marcas',
        'logoSize': 'large',
        'brands': <Map<String, dynamic>>[
          {'name': 'Shimano', 'imageUrl': 'https://cdn/shimano.svg'},
        ],
      };

  group('B · Products: el editor custom pasa por el owner canónico', () {
    testWidgets('390 Móvil y 834 Tablet: showViewAll ofrece personalizar',
        (tester) async {
      for (final (width, viewport) in const <(double, DevicePreviewMode)>[
        (390, DevicePreviewMode.mobile),
        (834, DevicePreviewMode.tablet),
      ]) {
        await pumpBlock(
          tester,
          type: 'products',
          data: productsData(),
          width: width,
          viewport: viewport,
        );

        expect(shellFor('showViewAll'), findsOneWidget, reason: '@ $width');
        expect(
          stateOf(tester, 'showViewAll').status,
          WebsiteResponsiveFieldStatus.inherited,
          reason: '@ $width',
        );
        expect(
          find.descendant(
            of: shellFor('showViewAll'),
            matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
          ),
          findsOneWidget,
          reason: '@ $width',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '390 Móvil y 834 Tablet: itemsPerRow queda visible, inerte y '
        'con su razón verdadera', (tester) async {
      for (final (width, viewport, fragment)
          in const <(double, DevicePreviewMode, String)>[
        (390, DevicePreviewMode.mobile, 'carrusel automático'),
        (834, DevicePreviewMode.tablet, 'se calculan solas'),
      ]) {
        final provider = await pumpBlock(
          tester,
          type: 'products',
          data: productsData(),
          width: width,
          viewport: viewport,
        );
        final before = dataOf(provider);

        // Visible, no escondido.
        expect(shellFor('itemsPerRow'), findsOneWidget, reason: '@ $width');
        expect(
          stateOf(tester, 'itemsPerRow').status,
          WebsiteResponsiveFieldStatus.unavailable,
          reason: '@ $width',
        );
        // Y dice por qué, con la palabra que corresponde a ese viewport.
        expect(find.textContaining(fragment), findsOneWidget,
            reason: '@$width');
        // Sin acción de personalizar: no hay override que ofrecer.
        expect(
          find.descendant(
            of: shellFor('itemsPerRow'),
            matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
          ),
          findsNothing,
          reason: '@ $width',
        );

        // Inerte de verdad: tocar un chip no escribe nada.
        final chip = find.descendant(
          of: shellFor('itemsPerRow'),
          matching: find.text('2'),
        );
        expect(chip, findsOneWidget);
        await tester.tap(chip, warnIfMissed: false);
        await settle(tester);
        expect(dataOf(provider), before, reason: '@ $width');
        expect(provider.hasUnsavedChanges, isFalse, reason: '@ $width');
        expect(
          dataOf(provider).containsKey('responsive'),
          isFalse,
          reason: 'móvil/tablet no pueden escribir itemsPerRow',
        );
      }
    });

    testWidgets('1440 Escritorio: itemsPerRow es la base editable',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'products',
        data: productsData(),
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );

      // `showViewAll` puede variar por viewport, así que en la base dice Común.
      expect(
        stateOf(tester, 'showViewAll').status,
        WebsiteResponsiveFieldStatus.common,
      );
      // `itemsPerRow` nunca varía: dice que es siempre común.
      expect(
        stateOf(tester, 'itemsPerRow').status,
        WebsiteResponsiveFieldStatus.sharedOnly,
      );
      for (final key in const ['itemsPerRow', 'showViewAll']) {
        expect(
          find.descendant(
            of: shellFor(key),
            matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
          ),
          findsNothing,
          reason: key,
        );
      }

      // Y en escritorio SÍ escribe, como valor común.
      await tester.tap(
        find.descendant(of: shellFor('itemsPerRow'), matching: find.text('2')),
      );
      await settle(tester);
      expect(dataOf(provider)['itemsPerRow'], 2);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
    });

    testWidgets('override sólo en su viewport, y reset lo borra entero',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'products',
        data: productsData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      // El toggle real del editor de Products.
      await tapShellAction(
        tester,
        'showViewAll',
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<Switch>(
            find.descendant(
              of: shellFor('showViewAll'),
              matching: find.byType(Switch),
            ),
          )
          .onChanged!(false);
      await settle(tester);

      final mobile = (dataOf(provider)['responsive'] as Map)['mobile'] as Map;
      expect(mobile['showViewAll'], isFalse);
      expect(
        mobile.containsKey('itemsPerRow'),
        isFalse,
        reason: 'itemsPerRow es compartido: no puede aparecer en un override',
      );
      // La base intacta…
      expect(dataOf(provider)['itemsPerRow'], 4);
      expect(dataOf(provider)['showViewAll'], isTrue);
      // …y nada para tablet: sin cascada.
      expect(
        (dataOf(provider)['responsive'] as Map).containsKey('tablet'),
        isFalse,
      );
      // La identidad de catálogo no se movió.
      expect(dataOf(provider)['maxProducts'], 8);
      expect(dataOf(provider)['viewAllLink'], '/productos');

      await tapShellAction(
        tester,
        'showViewAll',
        ResponsiveFieldShell.resetActionKey,
      );

      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
    });

    testWidgets('los pickers y campos de negocio siguen fuera del shell',
        (tester) async {
      await pumpBlock(
        tester,
        type: 'products',
        data: productsData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      for (final key in const [
        'maxProducts',
        'productSource',
        'viewAllLink',
        'showPrice',
      ]) {
        expect(shellFor(key), findsNothing, reason: key);
      }
      // Y sus controles siguen existiendo con su etiqueta de siempre.
      expect(find.text('Máximo de productos'), findsOneWidget);
      expect(find.text('Mostrar precios'), findsOneWidget);
    });
  });

  group('E · Category Grid: dos items no se contaminan', () {
    testWidgets('la imagen del item es responsive y el alt es compartido',
        (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'categoryGrid',
        data: categoryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      expect(shellFor('imageUrl'), findsOneWidget);
      expect(
        stateOf(tester, 'imageUrl').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      expect(
          stateOf(tester, 'imageUrl').resolved.value, 'https://cdn/mtb.webp');

      await tapShellAction(
        tester,
        'imageUrl',
        ResponsiveFieldShell.customizeActionKey,
      );
      tester
          .widget<ResponsiveMediaField>(find.byType(ResponsiveMediaField))
          .onChanged('https://cdn/mtb-mobile.webp');
      await settle(tester);

      final categories = (dataOf(provider)['categories'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

      expect(
        (categories[0]['responsive'] as Map)['mobile'],
        containsPair('imageUrl', 'https://cdn/mtb-mobile.webp'),
      );
      expect(categories[0]['imageUrl'], 'https://cdn/mtb.webp');
      // El hermano intacto.
      expect(categories[1].containsKey('responsive'), isFalse);
      expect(categories[1]['imageUrl'], 'https://cdn/ruta.webp');
      // Y la raíz nunca adquiere la propiedad del item.
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);

      // Alt text compartido y fuera del shell.
      expect(shellFor('altText'), findsNothing);
      expect(find.text('Texto alternativo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la fila de media NO desborda a 390 dentro de un repeater',
        (tester) async {
      // Regresión del defecto que este lote destapó: anidada en la sección
      // indentada de un repeater la fila recibe ~250 px y desbordaba 30. La
      // composición del owner canónico ahora fluye, y esto queda en verde.
      await pumpBlock(
        tester,
        type: 'categoryGrid',
        data: categoryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      expect(tester.takeException(), isNull);
      // Una sola miniatura, y las dos acciones siguen presentes y alcanzables.
      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.replaceActionKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.reframeActionKey), findsOneWidget);
    });

    testWidgets('el subtítulo del bloque ya es alcanzable y sigue compartido',
        (tester) async {
      await pumpBlock(
        tester,
        type: 'categoryGrid',
        data: categoryData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      expect(find.text('Subtítulo'), findsWidgets);
      expect(shellFor('subtitle'), findsNothing);
      expect(shellFor('title'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('F · Brand Logos', () {
    testWidgets('logoSize es responsive; las marcas no', (tester) async {
      final provider = await pumpBlock(
        tester,
        type: 'brandLogos',
        data: brandData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );
      final original = dataOf(provider);

      expect(shellFor('logoSize'), findsOneWidget);
      expect(
        stateOf(tester, 'logoSize').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      expect(stateOf(tester, 'logoSize').resolved.value, 'large');
      // La marca entera queda fuera del protocolo.
      for (final key in const ['name', 'link', 'brands', 'title']) {
        expect(shellFor(key), findsNothing, reason: key);
      }

      await tapShellAction(
        tester,
        'logoSize',
        ResponsiveFieldShell.customizeActionKey,
      );
      expect(
        stateOf(tester, 'logoSize').effectiveWriteScope,
        WebsiteWriteScope.viewport,
      );

      await tapShellAction(
        tester,
        'logoSize',
        ResponsiveFieldShell.customizeActionKey,
      ).catchError((Object _) {});
      // Personalizar sin escribir no crea dato.
      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });
  });

  group('G · anchos, brillos y ausencia de duplicados', () {
    for (final (width, viewport) in const <(double, DevicePreviewMode)>[
      (390, DevicePreviewMode.mobile),
      (834, DevicePreviewMode.tablet),
      (1440, DevicePreviewMode.desktop),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Products a $width · $brightness sin overflow ni etiqueta '
            'duplicada', (tester) async {
          await pumpBlock(
            tester,
            type: 'products',
            data: productsData(),
            width: width,
            viewport: viewport,
            brightness: brightness,
          );

          expect(shellFor('itemsPerRow'), findsOneWidget);
          expect(find.text('Productos por fila'), findsOneWidget);
          expect(find.text('Mostrar botón "Ver todos"'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto la acción del shell cumple 48',
        (tester) async {
      await pumpBlock(
        tester,
        type: 'brandLogos',
        data: brandData(),
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      final action = find.descendant(
        of: shellFor('logoSize'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      await tester.ensureVisible(action);
      await settle(tester);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    });
  });
}
