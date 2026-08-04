import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/focal_point_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// A 1×1 transparent PNG, served from loopback so the focal picker can paint a
/// real image instead of reporting a load failure per frame.
const _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

/// The test binding answers every request with 400. An explicit empty override
/// restores the real client so the loopback origin below can answer.
class _LoopbackHttpOverrides extends HttpOverrides {}

/// 7B-3A — the REAL Canvas inspector, wired to the canonical authority.
///
/// Everything here goes through `WebsiteBlockEditSurface`, the surface the
/// product mounts, so what is asserted is what an operator gets: the projected
/// value for the previewed viewport, a write that lands in exactly one branch,
/// one focal control, typed visibility, and structural commands addressed by
/// identity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer origin;
  late StreamSubscription<HttpRequest> originRequests;
  late String imageUrl;
  HttpOverrides? previousOverrides;

  setUpAll(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    imageUrl = 'http://${origin.address.address}:${origin.port}/hero.png';
    originRequests = origin.listen((request) async {
      await request.drain<void>();
      final bytes = base64Decode(_pixelPng);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await originRequests.cancel();
    await origin.close(force: true);
    HttpOverrides.global = previousOverrides;
  });

  Map<String, dynamic> canvasDocument() => <String, dynamic>{
        'canvasResponsiveVersion': 2,
        'blockHeight': 480.0,
        'designWidth': 1200.0,
        'heightMode': 'fixed',
        'responsive': <String, dynamic>{
          'version': 2,
          'tablet': <String, dynamic>{'blockHeight': 700.0},
          'mobile': <String, dynamic>{'blockHeight': 320.0},
        },
        'elements': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'layer-a',
            'type': 'text',
            'x': 100.0,
            'y': 40.0,
            'w': 240.0,
            'h': 72.0,
            'text': 'Capa A',
            'responsive': <String, dynamic>{
              'version': 2,
              'tablet': <String, dynamic>{'x': 700.0},
            },
          },
          <String, dynamic>{
            'id': 'layer-b',
            'type': 'text',
            'x': 300.0,
            'y': 140.0,
            'w': 240.0,
            'h': 72.0,
            'text': 'Capa B',
          },
        ],
      };

  Map<String, dynamic> canvasBlock() => <String, dynamic>{
        'id': 'canvas-block',
        'block_type': 'canvas',
        'order_index': 0,
        'is_visible': true,
        'block_data': canvasDocument(),
      };

  Map<String, dynamic> carouselBlock() => <String, dynamic>{
        'id': 'carousel-block',
        'block_type': 'carousel',
        'order_index': 0,
        'is_visible': true,
        'block_data': <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            <String, dynamic>{'useComposition': true, ...canvasDocument()},
            <String, dynamic>{'useComposition': true, ...canvasDocument()},
          ],
        },
      };

  WebsiteEditModeProvider providerFor(
    List<Map<String, dynamic>> blocks, {
    required String selected,
    DevicePreviewMode viewport = DevicePreviewMode.desktop,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        blocks,
        const <String, dynamic>{},
        pageId: 'canvas-page',
        pageSlug: 'canvas-page',
      )
      ..selectBlock(selected)
      ..setDevicePreviewMode(viewport);
  }

  Map<String, dynamic> documentOf(
    WebsiteEditModeProvider provider,
    String blockId, {
    int? slideIndex,
  }) =>
      provider.canvasDocument(blockId, slideIndex: slideIndex)!;

  Map<String, dynamic> layerOf(
    WebsiteEditModeProvider provider,
    String blockId,
    String layerId, {
    int? slideIndex,
  }) {
    final elements =
        documentOf(provider, blockId, slideIndex: slideIndex)['elements']
            as List;
    return Map<String, dynamic>.from(
      elements.firstWhere((e) => (e as Map)['id'] == layerId) as Map,
    );
  }

  void useViewport(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);
  }

  Widget host(
    WebsiteEditModeProvider provider,
    WebsiteBlockEditSection section, {
    double editorWidth = 380,
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
                section: section,
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
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> expand(WidgetTester tester, String title) async {
    final header = find.text(title);
    if (header.evaluate().isEmpty) return;
    await tester.ensureVisible(header.first);
    await tester.tap(header.first, warnIfMissed: false);
    await settle(tester);
  }

  Future<void> tapAction(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  group('A · el valor visible es la proyección del viewport', () {
    for (final probe in const <(double, DevicePreviewMode, double, double)>[
      (390, DevicePreviewMode.mobile, 320.0, 100.0),
      (834, DevicePreviewMode.tablet, 700.0, 700.0),
      (1440, DevicePreviewMode.desktop, 480.0, 100.0),
    ]) {
      testWidgets('raíz y capa a ${probe.$1.toStringAsFixed(0)}',
          (tester) async {
        useViewport(tester, probe.$1);
        final provider = providerFor(
          <Map<String, dynamic>>[canvasBlock()],
          selected: 'canvas-block',
          viewport: probe.$2,
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          host(provider, WebsiteBlockEditSection.content),
        );
        await settle(tester);

        expect(
          stateOf(tester, 'blockHeight').resolved.value,
          probe.$3,
          reason: 'la raíz muestra lo que el viewport resuelve',
        );

        provider.selectCanvasElement('canvas-block', 'layer-a');
        await tester.pumpWidget(host(provider, WebsiteBlockEditSection.layout));
        await settle(tester);

        expect(
          stateOf(tester, 'x').resolved.value,
          probe.$4,
          reason: 'la capa muestra lo que el viewport resuelve',
        );
      });
    }
  });

  testWidgets('B · editar en móvil crea sólo responsive.mobile, y Reset vuelve',
      (tester) async {
    useViewport(tester, 390);
    final provider = providerFor(
      <Map<String, dynamic>>[canvasBlock()],
      selected: 'canvas-block',
      viewport: DevicePreviewMode.mobile,
    );
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    provider.selectCanvasElement('canvas-block', 'layer-a');
    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.layout));
    await settle(tester);

    // "Personalizar" es por campo: promueve x, no w ni la capa hermana.
    await tapAction(
      tester,
      find.descendant(
        of: shellFor('x'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      ),
    );
    await tester.enterText(
      find.descendant(of: shellFor('x'), matching: find.byType(TextField)),
      '55',
    );
    await settle(tester);

    final layer = layerOf(provider, 'canvas-block', 'layer-a');
    expect(layer['x'], 100.0, reason: 'la base no se toca');
    expect(
      (layer['responsive'] as Map)['mobile'],
      <String, dynamic>{'x': 55.0},
    );
    expect(
      (layer['responsive'] as Map)['tablet'],
      <String, dynamic>{'x': 700.0},
      reason: 'la rama tablet queda intacta',
    );
    expect(
      layerOf(provider, 'canvas-block', 'layer-b')['x'],
      300.0,
      reason: 'la capa hermana queda intacta',
    );
    expect(
      documentOf(provider, 'canvas-block')['blockHeight'],
      480.0,
      reason: 'la raíz queda intacta',
    );

    await tapAction(
      tester,
      find.descendant(
        of: shellFor('x'),
        matching: find.byKey(ResponsiveFieldShell.resetActionKey),
      ),
    );

    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'Restablecer devuelve la igualdad profunda',
    );
  });

  testWidgets('C · un solo control de foco, contextual, y una sola transacción',
      (tester) async {
    useViewport(tester, 1440);
    final block = canvasBlock();
    (block['block_data'] as Map<String, dynamic>)['backgroundImageUrl'] =
        imageUrl;
    final provider = providerFor(
      <Map<String, dynamic>>[block],
      selected: 'canvas-block',
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);
    await expand(tester, 'Background & Overlay');

    expect(
      shellFor('focalPoint'),
      findsOneWidget,
      reason: 'un solo control de foco, nunca uno de escritorio y otro móvil',
    );
    expect(find.text('Foco móvil'), findsNothing);
    expect(
      find.text('Punto focal (móvil)'),
      findsNothing,
      reason: 'en escritorio no se rotula un valor de escritorio como móvil',
    );
    expect(
      stateOf(tester, 'focalPoint').context.previewViewport,
      WebsiteViewport.desktop,
    );

    await tapAction(tester, find.text('Reencuadrar'));
    expect(find.byType(FocalPointPicker), findsOneWidget);
    expect(
      find.text(FocalPointPicker.defaultLabel),
      findsNothing,
      reason: 'abierto en escritorio tampoco aparece el rótulo móvil',
    );
    expect(
      find.textContaining('Centrar'),
      findsOneWidget,
      reason: 'una sola acción de centrar, la del control canónico',
    );
  });

  testWidgets('C · un arrastre real persiste una vez, al soltar',
      (tester) async {
    useViewport(tester, 1440);
    final block = canvasBlock();
    (block['block_data'] as Map<String, dynamic>)['backgroundImageUrl'] =
        imageUrl;
    final provider = providerFor(
      <Map<String, dynamic>>[block],
      selected: 'canvas-block',
    );
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);
    await expand(tester, 'Background & Overlay');
    await tapAction(tester, find.text('Reencuadrar'));

    var notifications = 0;
    provider.addListener(() => notifications++);

    // Un gesto real: bajar, varios movimientos y soltar.
    final area = tester.getRect(find.byType(FocalPointPicker));
    final start = Offset(area.left + area.width * 0.3, area.top + 40);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 3; step++) {
      await gesture.moveBy(const Offset(18, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      notifications,
      0,
      reason: 'mientras se arrastra el feedback es local, no persistencia',
    );
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'ningún movimiento intermedio llega al documento',
    );

    await gesture.up();
    await settle(tester);

    final document = documentOf(provider, 'canvas-block');
    expect(document.containsKey('focalPointX'), isTrue);
    expect(document.containsKey('focalPointY'), isTrue);
    expect(
      notifications,
      1,
      reason: 'un arrastre entero es una sola escritura de x+y',
    );

    provider.undo();
    expect(
      jsonEncode(provider.blocks),
      before,
      reason: 'un solo deshacer devuelve los dos ejes originales',
    );
    expect(provider.canUndo, isFalse);
  });

  testWidgets('C · un gesto cancelado no persiste nada', (tester) async {
    useViewport(tester, 1440);
    final block = canvasBlock();
    (block['block_data'] as Map<String, dynamic>)['backgroundImageUrl'] =
        imageUrl;
    final provider = providerFor(
      <Map<String, dynamic>>[block],
      selected: 'canvas-block',
    );
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);
    await expand(tester, 'Background & Overlay');
    await tapAction(tester, find.text('Reencuadrar'));

    final area = tester.getRect(find.byType(FocalPointPicker));
    final gesture = await tester.startGesture(
      Offset(area.left + area.width * 0.4, area.top + 50),
    );
    await gesture.moveBy(const Offset(25, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.cancel();
    await settle(tester);

    expect(jsonEncode(provider.blocks), before);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);

    // "Centrar" sí es discreto: una pulsación, una entrada.
    await tapAction(tester, find.textContaining('Centrar'));
    final document = documentOf(provider, 'canvas-block');
    expect(document['focalPointX'], 0.5);
    expect(document['focalPointY'], 0.5);
    provider.undo();
    expect(provider.canUndo, isFalse);
  });

  testWidgets('D · alta, duplicado, borrado y orden van por identidad',
      (tester) async {
    useViewport(tester, 1440);
    final provider = providerFor(
      <Map<String, dynamic>>[canvasBlock()],
      selected: 'canvas-block',
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);

    await tapAction(tester, find.widgetWithText(OutlinedButton, 'Texto'));
    var ids = (documentOf(provider, 'canvas-block')['elements'] as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();
    expect(ids.length, 3);
    expect(ids.take(2), <String>['layer-a', 'layer-b']);
    final added = ids.last;
    expect(
      provider.canvasElementSelection('canvas-block'),
      added,
      reason: 'la selección sigue al comando que sí aterrizó',
    );

    // Duplicar y borrar por identidad, desde la fila de la capa. Con una capa
    // seleccionada el inspector muestra su editor, así que se deselecciona.
    provider.selectCanvasElement('canvas-block', null);
    await settle(tester);
    expect(find.byTooltip('Duplicar'), findsNWidgets(3));
    await tapAction(tester, find.byTooltip('Duplicar').first);
    ids = (documentOf(provider, 'canvas-block')['elements'] as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();
    expect(ids.length, 4);
    expect(ids[1], 'layer-a_copia', reason: 'la copia queda junto al original');
    expect(ids.toSet().length, 4, reason: 'identidades únicas');

    await tapAction(tester, find.byTooltip('Eliminar').first);
    ids = (documentOf(provider, 'canvas-block')['elements'] as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();
    expect(ids, isNot(contains('layer-a')));
    expect(ids.length, 3);

    // Orden: el escritorio mueve la lista base, una posición y por identidad.
    final beforeOrder = List<String>.from(ids);
    expect(beforeOrder[1], 'layer-b');
    provider.selectCanvasElement('canvas-block', 'layer-b');
    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.layout));
    await settle(tester);
    await tapAction(
        tester, find.byKey(const ValueKey('inspector_layer_forward')));
    ids = (documentOf(provider, 'canvas-block')['elements'] as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();
    expect(
      ids,
      <String>[beforeOrder[0], beforeOrder[2], beforeOrder[1]],
      reason: 'una adelante intercambia con la vecina, no salta al frente',
    );
    expect(
      layerOf(provider, 'canvas-block', 'layer-b')['responsive'],
      isNull,
      reason: 'en escritorio el orden es la lista base, nunca un override',
    );
  });

  testWidgets('D · el slide anidado exacto, sin tocar al hermano',
      (tester) async {
    useViewport(tester, 1440);
    final provider = providerFor(
      <Map<String, dynamic>>[carouselBlock()],
      selected: 'carousel-block',
    );
    addTearDown(provider.dispose);
    provider.selectCarouselSlide('carousel-block', 1, 2);
    final sibling = jsonEncode(
      documentOf(provider, 'carousel-block', slideIndex: 0),
    );

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);
    await tapAction(tester, find.widgetWithText(OutlinedButton, 'Texto'));

    expect(
      (documentOf(provider, 'carousel-block', slideIndex: 1)['elements']
              as List)
          .length,
      3,
    );
    expect(
      jsonEncode(documentOf(provider, 'carousel-block', slideIndex: 0)),
      sibling,
      reason: 'el slide hermano no se toca',
    );
    expect(
      provider.canvasElementSelection('carousel-block', slideIndex: 1),
      isNotNull,
    );
    expect(
      provider.canvasElementSelection('carousel-block', slideIndex: 0),
      isNull,
    );
  });

  group('CTA · contenido compartido y presentación responsive no se mezclan',
      () {
    Map<String, dynamic> buttonBlock() {
      final document = canvasDocument();
      document['elements'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'cta',
          'type': 'button',
          'x': 100.0,
          'y': 40.0,
          'w': 220.0,
          'h': 56.0,
          'label': 'Ver ofertas',
          'link': '/ofertas',
          'style': 'filled',
          'inheritTheme': true,
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'navigate',
              'label': 'Ver ofertas',
              'href': '/ofertas',
              'variant': 'filled',
            },
          ],
        },
      ];
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'canvas-block',
          'block_type': 'canvas',
          'order_index': 0,
          'is_visible': true,
          'block_data': document,
        },
      ].single;
    }

    testWidgets('en móvil, editar el texto no toca style ni su override',
        (tester) async {
      useViewport(tester, 390);
      final provider = providerFor(
        <Map<String, dynamic>>[buttonBlock()],
        selected: 'canvas-block',
        viewport: DevicePreviewMode.mobile,
      );
      addTearDown(provider.dispose);
      provider.selectCanvasElement('canvas-block', 'cta');

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      // El selector de variante no vive en Contenido.
      expect(shellFor('label'), findsOneWidget);
      expect(shellFor('style'), findsNothing);
      expect(find.text('Estilo'), findsNothing);

      await tester.enterText(
        find
            .descendant(of: shellFor('label'), matching: find.byType(TextField))
            .first,
        'Comprar ahora',
      );
      await settle(tester);

      final layer = layerOf(provider, 'canvas-block', 'cta');
      expect(layer['label'], 'Comprar ahora');
      expect(layer['style'], 'filled', reason: 'la base de style no se toca');
      expect(
        layer['responsive'],
        isNull,
        reason: 'editar contenido en móvil no abre una rama responsive',
      );
      final mirror = (layer['actions'] as List).single as Map;
      expect(mirror['label'], 'Comprar ahora');
      expect(
        mirror['variant'],
        'filled',
        reason: 'el espejo usa la variante COMPARTIDA, no la proyectada',
      );
    });

    testWidgets('en móvil, personalizar style escribe sólo responsive.mobile',
        (tester) async {
      useViewport(tester, 390);
      final provider = providerFor(
        <Map<String, dynamic>>[buttonBlock()],
        selected: 'canvas-block',
        viewport: DevicePreviewMode.mobile,
      );
      addTearDown(provider.dispose);
      provider.selectCanvasElement('canvas-block', 'cta');
      final before = jsonEncode(provider.blocks);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.style));
      await settle(tester);

      expect(shellFor('style'), findsOneWidget);
      expect(
        stateOf(tester, 'style').status,
        WebsiteResponsiveFieldStatus.inherited,
      );

      await tapAction(
        tester,
        find.descendant(
          of: shellFor('style'),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        ),
      );
      await tapAction(
        tester,
        find.descendant(of: shellFor('style'), matching: find.text('Sólido')),
      );
      await tester.pumpAndSettle();
      await tapAction(tester, find.text('Contorno').last);

      final layer = layerOf(provider, 'canvas-block', 'cta');
      expect(layer['style'], 'filled', reason: 'la base sigue compartida');
      expect(
        (layer['responsive'] as Map)['mobile'],
        <String, dynamic>{'style': 'outline'},
      );
      expect(
        ((layer['actions'] as List).single as Map)['variant'],
        'filled',
        reason: 'el espejo compartido no adopta la variante del teléfono',
      );

      await tapAction(
        tester,
        find.descendant(
          of: shellFor('style'),
          matching: find.byKey(ResponsiveFieldShell.resetActionKey),
        ),
      );
      expect(
        jsonEncode(provider.blocks),
        before,
        reason: 'Restablecer elimina sólo ese override',
      );
    });

    // Una capa compatible/antigua no tiene `style` directo: su presentación
    // vive sólo dentro del `actions` estructurado. Preguntar por `style` a
    // secas respondería "filled", y editar el texto reescribiría un botón de
    // contorno como sólido sin que nadie lo pidiera.
    for (final variant in const <String>['outline', 'text']) {
      testWidgets('sin style directo, el espejo conserva variant=$variant',
          (tester) async {
        useViewport(tester, 390);
        final document = canvasDocument();
        document['elements'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cta',
            'type': 'button',
            'x': 100.0,
            'y': 40.0,
            'w': 220.0,
            'h': 56.0,
            'label': 'Ver ofertas',
            'link': '/ofertas',
            'inheritTheme': true,
            'actions': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'navigate',
                'label': 'Ver ofertas',
                'to': '/ofertas',
                'variant': variant,
              },
            ],
          },
        ];
        final provider = providerFor(
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'canvas-block',
              'block_type': 'canvas',
              'order_index': 0,
              'is_visible': true,
              'block_data': document,
            },
          ],
          selected: 'canvas-block',
          viewport: DevicePreviewMode.mobile,
        );
        addTearDown(provider.dispose);
        provider.selectCanvasElement('canvas-block', 'cta');

        await tester.pumpWidget(
          host(provider, WebsiteBlockEditSection.content),
        );
        await settle(tester);

        await tester.enterText(
          find
              .descendant(
                  of: shellFor('label'), matching: find.byType(TextField))
              .first,
          'Comprar ahora',
        );
        await settle(tester);

        final layer = layerOf(provider, 'canvas-block', 'cta');
        expect(layer['label'], 'Comprar ahora');
        expect(
          layer.containsKey('style'),
          isFalse,
          reason: 'editar el texto no inventa una presentación base',
        );
        expect(
          layer['responsive'],
          isNull,
          reason: 'ni abre una rama por dispositivo',
        );
        final mirror = (layer['actions'] as List).single as Map;
        expect(mirror['label'], 'Comprar ahora');
        expect(
          mirror['variant'],
          variant,
          reason: 'la variante compartida real se conserva, no se normaliza',
        );
      });
    }

    test('ningún writeMany gobernado por label incluye style', () {
      final source = File(
        'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
      ).readAsStringSync();
      final buttonControls = source.substring(
        source.indexOf('List<Widget> _buildButtonLayerControls('),
        source.indexOf('List<Widget> _buildImageLayerControls('),
      );
      final writeMany = buttonControls.substring(
        buttonControls.indexOf('binding.writeMany('),
        buttonControls.indexOf('),\n          ),\n        ),'),
      );
      expect(writeMany, contains("'label': action.label"));
      expect(writeMany, contains("'link': action.href"));
      expect(
        writeMany,
        isNot(contains("'style'")),
        reason: 'style tiene su propia política y su propio binding',
      );
      expect(buttonControls, contains('showVariant: false'));
      expect(buttonControls, contains("surface.text(\n            'style'"));
    });
  });

  // 7B-3B · el estado heredado, visible y explícito en el inspector.
  //
  // Diseño: proyecto a0fa3196-6315-4b96-bde7-7cc801e7a74e, página
  // `Website Builder Responsive Authoring`, turno t10, frame 10i «Estados del
  // sistema» (estado `documento ambiguo`) y 10d «Capas responsive».
  // Componentes E-04 VbNotice, E-01 VbStatusBadge y A-01 texto.
  group('Migración · estado visible y decisión explícita', () {
    const migrateKey = Key('canvas-migration-apply');
    const keepDistinctKey = Key('canvas-migration-keep-distinct');
    const restoreKey = Key('canvas-migration-restore');
    const reviewKey = Key('canvas-migration-review');
    const reasonsKey = Key('canvas-migration-reasons');

    Map<String, dynamic> twin(
      String id, {
      required bool mobile,
      String text = 'Campaña',
    }) =>
        <String, dynamic>{
          'id': id,
          'type': 'text',
          'text': text,
          'x': 120.0,
          'y': 190.0,
          'w': 620.0,
          'h': 130.0,
          'fontSize': mobile ? 42.0 : 58.0,
          'hideOnMobile': !mobile,
          'showOnMobile': mobile,
        };

    Map<String, dynamic> legacyBlock(List<Map<String, dynamic>> layers) =>
        <String, dynamic>{
          'id': 'canvas-block',
          'block_type': 'canvas',
          'order_index': 0,
          'is_visible': true,
          'block_data': <String, dynamic>{
            'blockHeight': 480.0,
            'designWidth': 1200.0,
            'elements': layers,
          },
        };

    List<Map<String, dynamic>> safeLayers() => <Map<String, dynamic>>[
          twin('hero_desktop', mobile: false),
          twin('hero_mobile', mobile: true),
        ];

    List<Map<String, dynamic>> ambiguousLayers() => <Map<String, dynamic>>[
          ...safeLayers(),
          twin('cta_desktop', mobile: false, text: 'Ver ofertas'),
          twin('cta_mobile', mobile: true, text: 'Ver'),
        ];

    testWidgets('A · montar, seleccionar y cambiar viewport no escribe nada',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[legacyBlock(ambiguousLayers())],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);
      expect(find.text('Este bloque tiene capas duplicadas por dispositivo'),
          findsOneWidget);

      for (final mode in <DevicePreviewMode>[
        DevicePreviewMode.mobile,
        DevicePreviewMode.tablet,
        DevicePreviewMode.desktop,
      ]) {
        provider.setDevicePreviewMode(mode);
        await settle(tester);
      }
      provider.selectCanvasElement('canvas-block', 'cta_desktop');
      await settle(tester);
      provider.selectCanvasElement('canvas-block', null);
      await settle(tester);

      // Abrir y cerrar el detalle tampoco es un cambio.
      await tapAction(tester, find.byKey(reviewKey));
      expect(find.byKey(reasonsKey), findsOneWidget);
      await tapAction(tester, find.byKey(reviewKey));
      expect(find.byKey(reasonsKey), findsNothing);

      expect(jsonEncode(provider.blocks), before);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
    });

    testWidgets('B · seguro: una CTA, una entrada de historial y rollback',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[legacyBlock(safeLayers())],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      expect(find.text('Este bloque usa una configuración anterior'),
          findsOneWidget);
      expect(find.byKey(keepDistinctKey), findsNothing);
      expect(find.byKey(restoreKey), findsNothing);
      expect(find.byKey(reviewKey), findsNothing,
          reason: 'sin ambigüedades no hay motivos que mostrar');

      var notifications = 0;
      provider.addListener(() => notifications++);
      await tapAction(tester, find.byKey(migrateKey));

      expect(notifications, 1);
      final document = documentOf(provider, 'canvas-block');
      expect(
        (document['elements'] as List)
            .map((layer) => (layer as Map)['id'])
            .toList(),
        <String>['hero'],
      );
      // Las banderas legacy no sobreviven en ninguna capa. El nombre sí
      // aparece dentro de la procedencia: es lo que hace exacta la vuelta.
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(document),
        isFalse,
      );
      expect(find.text('Configuración actualizada'), findsOneWidget);
      expect(find.byKey(migrateKey), findsNothing);

      await tapAction(tester, find.byKey(restoreKey));
      expect(
        jsonDecode(jsonEncode(provider.blocks)),
        equals(jsonDecode(before)),
        reason: 'restaurar devuelve la configuración anterior',
      );
      expect(find.text('Este bloque usa una configuración anterior'),
          findsOneWidget);
    });

    testWidgets('C · el slide anidado usa el mismo owner y sólo su documento',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'carousel-block',
            'block_type': 'carousel',
            'order_index': 0,
            'is_visible': true,
            'block_data': <String, dynamic>{
              'slides': <Map<String, dynamic>>[
                <String, dynamic>{
                  'useComposition': true,
                  'elements': safeLayers(),
                },
                <String, dynamic>{
                  'useComposition': true,
                  'elements': safeLayers(),
                },
              ],
            },
          },
        ],
        selected: 'carousel-block',
      );
      addTearDown(provider.dispose);
      provider.selectCarouselSlide('carousel-block', 1, 2);
      final sibling = jsonEncode(
        documentOf(provider, 'carousel-block', slideIndex: 0),
      );

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);
      await tapAction(tester, find.byKey(migrateKey));

      expect(
        (documentOf(provider, 'carousel-block', slideIndex: 1)['elements']
                as List)
            .length,
        1,
      );
      expect(
        jsonEncode(documentOf(provider, 'carousel-block', slideIndex: 0)),
        sibling,
        reason: 'el slide hermano no se toca',
      );
    });

    testWidgets('D · ambiguo: los motivos se explican y se conservan ambas',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[legacyBlock(ambiguousLayers())],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      expect(find.byKey(migrateKey), findsNothing,
          reason: 'lo ambiguo nunca se une sin decisión');
      expect(find.byKey(keepDistinctKey), findsOneWidget);
      expect(find.text('Revisar'), findsOneWidget);

      await tapAction(tester, find.byKey(reviewKey));
      final reasons = tester
          .widgetList<Text>(
            find.descendant(
                of: find.byKey(reasonsKey), matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .join(' ');
      expect(reasons, contains('cta_desktop'));
      expect(reasons, contains('cta_mobile'));
      expect(reasons, contains('«text»'));
      expect(reasons, isNot(contains('differingSharedValue')),
          reason: 'el motivo se explica, no se imprime el enum');

      var notifications = 0;
      provider.addListener(() => notifications++);
      await tapAction(tester, find.byKey(keepDistinctKey));
      expect(notifications, 1);

      final document = documentOf(provider, 'canvas-block');
      expect(
        (document['elements'] as List)
            .map((layer) => (layer as Map)['id'])
            .toList(),
        <String>['hero', 'cta_desktop', 'cta_mobile'],
        reason: 'lo seguro se une y lo ambiguo queda separado, en su lugar',
      );
      expect(
        WebsiteCanvasMigration.carriesLegacyLayerFlags(document),
        isFalse,
        reason: 'ninguna capa queda con banderas legacy tras la decisión',
      );
      expect(
        WebsiteCanvasMigration.analyze(document).issues,
        isEmpty,
        reason: 'y no queda ambigüedad escondida tras el marcador',
      );
      expect(find.text('Configuración actualizada'), findsOneWidget);
    });

    testWidgets('E · identidad en conflicto: se explica y no se migra',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[
          legacyBlock(<Map<String, dynamic>>[
            twin('hero_desktop', mobile: false),
            twin('hero_desktop', mobile: true),
          ]),
        ],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      expect(find.text('Este bloque tiene capas sin identidad única'),
          findsOneWidget);
      expect(find.byKey(migrateKey), findsNothing);
      expect(find.byKey(keepDistinctKey), findsNothing);
      expect(find.byKey(restoreKey), findsNothing);

      await tapAction(tester, find.byKey(reviewKey));
      final reasons = tester
          .widgetList<Text>(
            find.descendant(
                of: find.byKey(reasonsKey), matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .join(' ');
      expect(reasons, contains('hero_desktop'));

      expect(jsonEncode(provider.blocks), before,
          reason: 'revisar identidades nunca muta el documento');
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
    });

    testWidgets('F · un documento canónico no muestra ningún aviso',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[canvasBlock()],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      expect(find.byKey(migrateKey), findsNothing);
      expect(find.byKey(keepDistinctKey), findsNothing);
      expect(find.byKey(restoreKey), findsNothing);
      expect(find.byKey(reviewKey), findsNothing);
      expect(find.text('Configuración actualizada'), findsNothing);
    });

    testWidgets('2 · gemelos sin banderas: la CTA ofrecida sí completa',
        (tester) async {
      useViewport(tester, 1440);
      final provider = providerFor(
        <Map<String, dynamic>>[
          legacyBlock(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'hero_desktop',
              'type': 'text',
              'text': 'Campaña',
              'x': 120.0,
              'y': 190.0,
              'w': 620.0,
              'h': 130.0,
            },
            <String, dynamic>{
              'id': 'hero_mobile',
              'type': 'text',
              'text': 'Campaña móvil',
              'x': 28.0,
              'y': 160.0,
              'w': 334.0,
              'h': 150.0,
            },
          ]),
        ],
        selected: 'canvas-block',
      );
      addTearDown(provider.dispose);
      final before = jsonEncode(provider.blocks);

      await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
      await settle(tester);

      expect(find.byKey(keepDistinctKey), findsOneWidget);
      await tapAction(tester, find.byKey(keepDistinctKey));

      final document = documentOf(provider, 'canvas-block');
      expect(
        (document['elements'] as List)
            .map((layer) => (layer as Map)['id'])
            .toList(),
        <String>['hero_desktop', 'hero_mobile'],
        reason: 'ninguna capa se une ni se descarta',
      );
      expect(find.text('Configuración actualizada'), findsOneWidget,
          reason: 'la acción visible completó de verdad');
      expect(provider.canUndo, isTrue);

      await tapAction(tester, find.byKey(restoreKey));
      expect(
        jsonDecode(jsonEncode(provider.blocks)),
        equals(jsonDecode(before)),
      );
    });

    testWidgets('1 · el aviso resuelve color y tipografía desde el tema',
        (tester) async {
      // El defecto original: literales claros dentro del aviso, ilegibles
      // sobre un host claro. Lo que se afirma es el contrato, no un hex:
      // el texto usa el rol semántico neutral, cambia con la brightness y
      // mantiene contraste suficiente contra la superficie que lo aloja.
      double luminance(Color color) => color.computeLuminance();
      double contrast(Color a, Color b) {
        final first = luminance(a) + 0.05;
        final second = luminance(b) + 0.05;
        return first > second ? first / second : second / first;
      }

      final resolved = <Brightness, Color>{};
      for (final brightness in Brightness.values) {
        // Árbol nuevo por iteración: `pumpWidget` reutiliza el elemento del
        // aviso, y con él su estado de detalle abierto, que haría que el
        // segundo toque lo cerrara en vez de abrirlo.
        await tester.pumpWidget(const SizedBox.shrink());
        useViewport(tester, 390);
        final provider = providerFor(
          <Map<String, dynamic>>[legacyBlock(ambiguousLayers())],
          selected: 'canvas-block',
          viewport: DevicePreviewMode.mobile,
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          host(
            provider,
            WebsiteBlockEditSection.content,
            editorWidth: 390,
            brightness: brightness,
          ),
        );
        await settle(tester);
        await tapAction(tester, find.byKey(reviewKey));
        expect(find.byKey(reasonsKey), findsOneWidget,
            reason: 'el detalle se abre también a 390');

        final reason = tester.widget<Text>(
          find
              .descendant(
                of: find.byKey(reasonsKey),
                matching: find.byType(Text),
              )
              .first,
        );
        final color = reason.style!.color!;
        resolved[brightness] = color;

        final context = tester.element(find.byKey(reasonsKey));
        expect(
          color,
          VinabikeThemeRoles.of(context).neutral.accent,
          reason: 'el color es el rol semántico, no un literal',
        );
        expect(reason.style!.fontSize, isNotNull,
            reason: 'la tipografía viene del textTheme');
        expect(
          contrast(color, Theme.of(context).colorScheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'texto de cuerpo legible sobre su superficie en '
              '${brightness.name}',
        );

        // La acción conserva el objetivo táctil de F-06 bajo 900 px.
        final action = tester.getRect(find.byKey(keepDistinctKey));
        expect(action.height, greaterThanOrEqualTo(48.0));
        expect(tester.takeException(), isNull,
            reason: 'sin overflow en ${brightness.name}');
      }

      expect(
        resolved[Brightness.light],
        isNot(resolved[Brightness.dark]),
        reason: 'un literal congelado daría el mismo color en ambos modos',
      );
    });

    test('1 · el aviso no declara color ni tipografía propios', () {
      final source = File(
        'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
      ).readAsStringSync();
      final slice = source.substring(
        source.indexOf('class _CanvasMigrationNotice extends StatefulWidget'),
        source.indexOf('/// The Canvas inspector on a target that owns no'),
      );
      final code = slice.split('\n').map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      }).join('\n');

      for (final forbidden in const <String>[
        'Color(0x',
        'Colors.white',
        'Colors.black',
        'styleFrom',
        'TextStyle(',
        'fontSize:',
        'VisualDensity',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'el aviso no puede declarar "$forbidden": la cascada '
              'canónica la resuelven el tema y los owners compartidos',
        );
      }
      expect(code, contains('VbNotice('));
      expect(code, contains('VbStatusBadge('));
      expect(code, contains('VbDensity.resolve(context)'));
      expect(code, contains('VinabikeThemeRoles.of(context)'));
    });

    testWidgets('I · el aviso cabe en 390 y en oscuro, sin overflow',
        (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        useViewport(tester, 390);
        final provider = providerFor(
          <Map<String, dynamic>>[legacyBlock(ambiguousLayers())],
          selected: 'canvas-block',
          viewport: DevicePreviewMode.mobile,
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          host(
            provider,
            WebsiteBlockEditSection.content,
            editorWidth: 390,
            brightness: brightness,
          ),
        );
        await settle(tester);
        await tapAction(tester, find.byKey(reviewKey));

        expect(find.byKey(reasonsKey), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: 'sin overflow en ${brightness.name}');
        expect(find.byKey(keepDistinctKey), findsOneWidget);
      }
    });
  });

  testWidgets('E · la visibilidad escribe sólo la propiedad tipada',
      (tester) async {
    useViewport(tester, 390);
    final provider = providerFor(
      <Map<String, dynamic>>[canvasBlock()],
      selected: 'canvas-block',
      viewport: DevicePreviewMode.mobile,
    );
    addTearDown(provider.dispose);

    provider.selectCanvasElement('canvas-block', 'layer-a');
    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.layout));
    await settle(tester);

    await tapAction(
      tester,
      find.descendant(
        of: shellFor('visible'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      ),
    );
    await tapAction(
      tester,
      find.descendant(of: shellFor('visible'), matching: find.byType(Switch)),
    );

    final layer = layerOf(provider, 'canvas-block', 'layer-a');
    expect((layer['responsive'] as Map)['mobile'], <String, dynamic>{
      'visible': false,
    });
    final encoded = jsonEncode(provider.blocks);
    expect(encoded, isNot(contains('hideOnMobile')));
    expect(encoded, isNot(contains('showOnMobile')));
  });

  testWidgets('F · un documento legacy queda legible y no muta',
      (tester) async {
    useViewport(tester, 390);
    final legacy = canvasDocument();
    legacy['elements'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'hero_desktop',
        'type': 'text',
        'x': 100.0,
        'y': 40.0,
        'w': 240.0,
        'h': 72.0,
        'text': 'Hero',
        'showOnMobile': false,
      },
      <String, dynamic>{
        'id': 'hero_mobile',
        'type': 'text',
        'x': 10.0,
        'y': 20.0,
        'w': 200.0,
        'h': 60.0,
        'text': 'Hero',
        'showOnMobile': true,
      },
    ];
    final provider = providerFor(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'canvas-block',
          'block_type': 'canvas',
          'order_index': 0,
          'is_visible': true,
          'block_data': legacy,
        },
      ],
      selected: 'canvas-block',
      viewport: DevicePreviewMode.mobile,
    );
    addTearDown(provider.dispose);
    final before = jsonEncode(provider.blocks);

    provider.selectCanvasElement('canvas-block', 'hero_mobile');
    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.layout));
    await settle(tester);

    expect(
      stateOf(tester, 'x').status,
      WebsiteResponsiveFieldStatus.unavailable,
      reason: 'un gemelo legacy se lee, no se escribe a ciegas',
    );
    expect(
      stateOf(tester, 'visible').status,
      WebsiteResponsiveFieldStatus.unavailable,
    );
    expect(
      stateOf(tester, 'x').resolved.value,
      10.0,
      reason: 'el valor sigue visible',
    );

    await tester.enterText(
      find.descendant(of: shellFor('x'), matching: find.byType(TextField)),
      '999',
    );
    await settle(tester);
    await tapAction(
      tester,
      find.descendant(of: shellFor('visible'), matching: find.byType(Switch)),
    );

    expect(jsonEncode(provider.blocks), before, reason: 'no muta los bytes');
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
  });

  testWidgets('G · activar composición crea identidades únicas y un history',
      (tester) async {
    useViewport(tester, 1440);
    final provider = providerFor(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'carousel-block',
          'block_type': 'carousel',
          'order_index': 0,
          'is_visible': true,
          'block_data': <String, dynamic>{
            'slides': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Campaña de invierno',
                'subtitle': 'Hasta 40% en repuestos',
                'ctaText': 'Ver ofertas',
                'ctaLink': '/ofertas',
              },
            ],
          },
        },
      ],
      selected: 'carousel-block',
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(host(provider, WebsiteBlockEditSection.content));
    await settle(tester);

    await tapAction(
      tester,
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Diseño avanzado por capas'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Switch),
      ),
    );

    final slide = documentOf(provider, 'carousel-block', slideIndex: 0);
    final layers = (slide['elements'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ids = layers.map((layer) => layer['id'].toString()).toList();

    expect(ids, <String>['title', 'subtitle', 'cta']);
    expect(ids.toSet().length, ids.length,
        reason: 'una identidad por elemento');
    for (final id in ids) {
      expect(id.endsWith('_desktop'), isFalse);
      expect(id.endsWith('_mobile'), isFalse);
    }
    final encoded = jsonEncode(provider.blocks);
    expect(encoded, isNot(contains('hideOnMobile')));
    expect(encoded, isNot(contains('showOnMobile')));
    expect(encoded, isNot(contains('mobileDesignWidth')));

    expect(layers.first['text'], 'Campaña de invierno');
    expect(layers.first['x'], 120.0);
    expect(
      (layers.first['responsive'] as Map)['mobile'],
      <String, dynamic>{
        'x': 28.0,
        'y': 160.0,
        'w': 334.0,
        'h': 150.0,
        'fontSize': 42.0,
      },
      reason:
          'la geometría del teléfono es un override tipado de la misma capa',
    );
    expect(layers.last['label'], 'Ver ofertas');
    expect((slide['responsive'] as Map)['mobile'], <String, dynamic>{
      'designWidth': 390.0,
    });
    expect(slide['canvasResponsiveVersion'], 2);

    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(
      provider.canUndo,
      isFalse,
      reason: 'la inicialización es una sola entrada de historial',
    );
    final restored = Map<String, dynamic>.from(
      ((provider.blocks.single['block_data'] as Map)['slides'] as List).single
          as Map,
    );
    expect(
      restored.containsKey('elements'),
      isFalse,
      reason: 'un solo deshacer devuelve el slide sin composición',
    );
    expect(restored['title'], 'Campaña de invierno');
  });

  test('H · guard estático sobre los tres archivos de producción', () {
    // Sólo mira código: un comentario que NOMBRA la clave legacy para explicar
    // por qué ya no se escribe no puede hacer fallar el guard.
    String code(String path) {
      final source = File(path).readAsStringSync();
      return source.split('\n').map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      }).join('\n');
    }

    const paths = <String>[
      'lib/modules/website/widgets/editor_panel/canvas_controls.dart',
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
      'lib/modules/website/widgets/editor_panel/edit_block_tab.dart',
    ];

    for (final path in paths) {
      final source = code(path);
      for (final token in const <String>[
        'onElementsChanged',
        'onCanvasSettingChanged',
        '_setElements',
        '_updateElement',
        'hideOnMobile',
        'showOnMobile',
      ]) {
        expect(
          source.contains(token),
          isFalse,
          reason: '$path todavía nombra "$token"',
        );
      }

      // Ningún writer reconstruye la colección de capas.
      expect(
        RegExp(r"'elements'\s*:").hasMatch(source),
        isFalse,
        reason: '$path escribe una lista de capas completa',
      );
      expect(
        RegExp(r"updateBlockData[^;]*'elements'", dotAll: true)
            .hasMatch(source),
        isFalse,
        reason: '$path escribe "elements" por updateBlockData',
      );
    }
  });
}
