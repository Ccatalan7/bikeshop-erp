import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_media_field.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// The generic schema editor consuming the canonical scalar binding.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c and
/// `handoff-t10/spec.json` `property_policy_matrix`.
void main() {
  Map<String, dynamic> block({
    required String type,
    required Map<String, dynamic> data,
  }) {
    return <String, dynamic>{
      'id': 'block-1',
      'block_type': type,
      'block_data': data,
      'is_visible': true,
      'sort_order': 0,
    };
  }

  WebsiteEditModeProvider providerFor(
    Map<String, dynamic> source, {
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(<Map<String, dynamic>>[source], const <String, dynamic>{})
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

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 900,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  Widget host({
    required WebsiteEditModeProvider provider,
    required double editorWidth,
    WebsiteBlockEditSection section = WebsiteBlockEditSection.content,
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
          // Production mounts this surface under a `watch` (the panel and the
          // contextual sheet both do). The harness reproduces that, otherwise
          // a write would never rebuild the inspector.
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

  /// The shell that owns one schema key, whatever its value type.
  Finder shellFor(String key) => find.byWidgetPredicate(
        (widget) =>
            widget is ResponsiveFieldShell && widget.state.schema.key == key,
      );

  Finder attributionFor(String key) => find.byWidgetPredicate(
        (widget) =>
            widget is ResponsiveFieldAttribution &&
            widget.state.schema.key == key,
      );

  Finder textFieldWithValue(String value) => find.byWidgetPredicate(
        (widget) => widget is TextFormField && widget.controller?.text == value,
      );

  WebsiteResponsiveFieldState<dynamic> stateOf(
    WidgetTester tester,
    String key,
  ) {
    return (tester.widget(shellFor(key)) as ResponsiveFieldShell).state;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Taps an action of one shell, bringing it into view first: the inspector
  /// scrolls, and a tap that lands off-screen silently does nothing.
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

  /// The inspector opens only its first section; the rest are progressive
  /// disclosure. A collapsed section builds nothing, so the responsive fields
  /// have to be disclosed the same way the operator discloses them.
  Future<void> discloseSections(WidgetTester tester) async {
    int disclosedFieldCount() =>
        find
            .byWidgetPredicate((widget) => widget is ResponsiveFieldShell)
            .evaluate()
            .length +
        find
            .byWidgetPredicate(
              (widget) => widget is ResponsiveFieldAttribution,
            )
            .evaluate()
            .length;

    // Two passes: an item's own groups only exist once its collection section
    // is open. A tap that REDUCES the disclosed fields just closed a section
    // that was already open, so it is undone — the helper discloses, it never
    // toggles blindly.
    for (var pass = 0; pass < 2; pass++) {
      for (final title in const [
        'Layout',
        'Estilo',
        'Diseño',
        'Contenido',
        'Video',
        'Otros',
        'Imagen y medios',
        'Texto y datos',
      ]) {
        // Target the disclosure owner, not an arbitrary text node with the
        // same value (for example a block title equal to "Video").
        final header = find.widgetWithText(InkWell, title);
        if (header.evaluate().isEmpty) continue;
        await tester.ensureVisible(header.first);
        await settle(tester);
        final before = disclosedFieldCount();
        await tester.tap(header.first, warnIfMissed: false);
        await settle(tester);
        if (disclosedFieldCount() < before) {
          await tester.tap(header.first, warnIfMissed: false);
          await settle(tester);
        }
      }
    }
  }

  group('C · el editor genérico muestra el valor efectivo y su herencia', () {
    testWidgets(
        'Hero: alignment y overlayOpacity se montan bajo el shell '
        'sin duplicar la etiqueta', (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'hero',
          data: <String, dynamic>{
            'title': 'Portada',
            'alignment': 'left',
            'overlayOpacity': 0.4,
            'showOverlay': true,
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      for (final key in const ['alignment', 'overlayOpacity', 'showOverlay']) {
        expect(shellFor(key), findsOneWidget, reason: key);
      }

      // Una sola etiqueta por campo: la del shell.
      expect(find.text('Alineación'), findsOneWidget);
      expect(find.text('Opacidad overlay'), findsOneWidget);

      // Valor efectivo, no `block_data` leído a mano.
      expect(stateOf(tester, 'alignment').resolved.value, 'left');
      expect(stateOf(tester, 'overlayOpacity').resolved.value, 0.4);

      // En móvil sin override: Heredado y con acción de personalizar.
      expect(
        stateOf(tester, 'alignment').status,
        WebsiteResponsiveFieldStatus.inherited,
      );
      expect(
        find.descendant(
          of: shellFor('alignment'),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'personalizar + escribir crea el override y luego se restablece',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'hero',
          data: <String, dynamic>{
            'title': 'Portada',
            'overlayOpacity': 0.4,
            'showOverlay': true,
          },
        ),
      );
      final original = dataOf(provider);
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.customizeActionKey,
      );

      // El control real del shell escribe por el binding.
      final slider = tester.widget<Slider>(
        find.descendant(
          of: shellFor('overlayOpacity'),
          matching: find.byType(Slider),
        ),
      );
      slider.onChangeStart!(slider.value);
      slider.onChanged!(0.9);
      slider.onChangeEnd!(0.9);
      await settle(tester);

      expect(dataOf(provider)['overlayOpacity'], 0.4,
          reason: 'la base intacta');
      expect(
        (dataOf(provider)['responsive'] as Map)['mobile'],
        containsPair('overlayOpacity', 0.9),
      );
      expect(
        stateOf(tester, 'overlayOpacity').status,
        WebsiteResponsiveFieldStatus.overridden,
      );
      expect(stateOf(tester, 'overlayOpacity').resolved.value, 0.9);

      await tapShellAction(
        tester,
        shellFor('overlayOpacity'),
        ResponsiveFieldShell.resetActionKey,
      );

      expect(dataOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('un toggle responsive escribe por el binding', (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'hero',
          data: <String, dynamic>{'title': 'P', 'showOverlay': true},
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      await tapShellAction(
        tester,
        shellFor('showOverlay'),
        ResponsiveFieldShell.customizeActionKey,
      );

      final toggle = tester.widget<Switch>(
        find.descendant(
          of: shellFor('showOverlay'),
          matching: find.byType(Switch),
        ),
      );
      toggle.onChanged!(false);
      await settle(tester);

      expect(dataOf(provider)['showOverlay'], isTrue);
      expect(
        (dataOf(provider)['responsive'] as Map)['mobile'],
        containsPair('showOverlay', false),
      );
    });

    testWidgets('Text: preset y maxWidth son responsive; el texto NO',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'text',
          data: <String, dynamic>{
            'text': 'Hola',
            'preset': 'paragraph',
            'maxWidth': 800,
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      expect(shellFor('preset'), findsOneWidget);
      expect(shellFor('maxWidth'), findsOneWidget);
      expect(stateOf(tester, 'preset').resolved.value, 'paragraph');
      expect(stateOf(tester, 'maxWidth').resolved.value, 800);

      // El contenido compartido no recibe el formulario responsive completo,
      // pero su control sí declara la atribución compacta canónica.
      expect(shellFor('text'), findsNothing);
      expect(attributionFor('text'), findsOneWidget);
      expect(
        (tester.widget(attributionFor('text')) as ResponsiveFieldAttribution)
            .state
            .status,
        WebsiteResponsiveFieldStatus.sharedOnly,
      );
      expect(find.text('Siempre común'), findsOneWidget);
    });

    testWidgets(
        'el texto sharedOnly usa el mismo lease y admite escritura IME rápida',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'text',
          data: <String, dynamic>{
            'text': 'Hola',
            'preset': 'paragraph',
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      final field = textFieldWithValue('Hola');
      expect(field, findsOneWidget);
      final onChanged = tester.widget<TextFormField>(field).onChanged!;

      // El mismo callback puede recibir varias composiciones antes del
      // rebuild. Cada commit aceptado recaptura un lease nuevo; no se congela
      // tras el primer carácter ni cae al writer live anterior.
      onChanged('Hola 1');
      onChanged('Hola 12');
      onChanged('Hola 123');
      await settle(tester);

      expect(dataOf(provider)['text'], 'Hola 123');
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(provider.canUndo, isTrue);
    });

    testWidgets('CTA subtitle y alias description se escriben atómicamente',
        (tester) async {
      useViewport(tester, width: 420, height: 1600);
      final provider = providerFor(
        block(
          type: 'cta',
          data: <String, dynamic>{
            'title': 'Oferta',
            'subtitle': 'Bajada',
            'description': 'Bajada',
            'buttonText': 'Comprar',
            'buttonLink': '/productos',
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      final field = textFieldWithValue('Bajada');
      expect(field, findsOneWidget);
      tester.widget<TextFormField>(field).onChanged!('Nueva bajada');
      await settle(tester);

      expect(dataOf(provider)['subtitle'], 'Nueva bajada');
      expect(dataOf(provider)['description'], 'Nueva bajada');
      provider.undo();
      expect(dataOf(provider)['subtitle'], 'Bajada');
      expect(dataOf(provider)['description'], 'Bajada');
    });

    testWidgets('Video Banner cambia fuente y limpia la alternativa en un undo',
        (tester) async {
      useViewport(tester, width: 420, height: 1800);
      final provider = providerFor(
        block(
          type: 'videoBanner',
          data: <String, dynamic>{
            'title': 'Video',
            'videoUrl': 'https://youtube.example/old',
            'videoFileUrl': 'https://cdn.example/old.mp4',
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      final visibleTextValues = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((field) => field.controller?.text)
          .toList(growable: false);
      expect(
        visibleTextValues,
        contains('https://youtube.example/old'),
        reason: 'campos visibles: $visibleTextValues',
      );
      final youtube = textFieldWithValue('https://youtube.example/old');
      tester
          .widget<TextFormField>(youtube)
          .onChanged!('https://youtube.example/new');
      await settle(tester);

      expect(dataOf(provider)['videoUrl'], 'https://youtube.example/new');
      expect(dataOf(provider)['videoFileUrl'], '');
      provider.undo();
      expect(dataOf(provider)['videoUrl'], 'https://youtube.example/old');
      expect(
        dataOf(provider)['videoFileUrl'],
        'https://cdn.example/old.mp4',
      );
    });

    testWidgets('un callback sharedOnly viejo no salta a otro documento',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'text',
          data: <String, dynamic>{'text': 'Primero', 'preset': 'paragraph'},
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      final stale = tester
          .widget<TextFormField>(textFieldWithValue('Primero'))
          .onChanged!;
      provider
        ..enterEditMode(
          <Map<String, dynamic>>[
            block(
              type: 'text',
              data: <String, dynamic>{
                'text': 'Segundo',
                'preset': 'paragraph',
              },
            ),
          ],
          const <String, dynamic>{},
        )
        ..selectBlock('block-1')
        ..reportRenderedBlockViewport('block-1', WebsiteViewport.mobile);

      // Sin pump: el callback viejo no puede recapturar contra el bloque con
      // el mismo id del documento nuevo.
      stale('No debe aterrizar');
      expect(dataOf(provider)['text'], 'Segundo');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('Button: style usa el binding y el destino sigue compartido',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'button',
          data: <String, dynamic>{
            'label': 'Comprar',
            // La clave canónica del destino en el schema de Button es `link`.
            // Con cualquier otra, la aserción de abajo sería vacua: no existe
            // ningún campo con esa clave, así que nunca tendría shell.
            'link': '/productos',
            'style': 'filled',
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      expect(shellFor('style'), findsOneWidget);
      expect(stateOf(tester, 'style').resolved.value, 'filled');
      // Etiqueta y destino son sharedOnly: no montan el shell completo y el
      // editor de acción atribuye el grupo una sola vez.
      expect(shellFor('link'), findsNothing);
      expect(shellFor('label'), findsNothing);
      expect(attributionFor('link'), findsOneWidget);
      expect(find.text('Siempre común'), findsOneWidget);

      final actionEditor =
          tester.widget<WebsiteActionEditor>(find.byType(WebsiteActionEditor));
      expect(actionEditor.showVariant, isFalse,
          reason: 'style ya tiene su propio shell responsive');
      actionEditor.onChanged(
        const WebsiteActionValue(
          label: 'Ver bicicletas',
          href: '/bicicletas',
          variant: WebsiteActionVariant.outline,
        ),
      );
      await settle(tester);

      expect(dataOf(provider)['label'], 'Ver bicicletas');
      expect(dataOf(provider)['link'], '/bicicletas');
      expect(dataOf(provider)['style'], 'filled',
          reason: 'el action editor no duplica el control de estilo');
      expect(dataOf(provider)['actions'], isNotEmpty);
      provider.undo();
      expect(dataOf(provider)['label'], 'Comprar');
      expect(dataOf(provider)['link'], '/productos');
    });

    testWidgets('editar la etiqueta de acción completa crea un solo undo',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'button',
          data: <String, dynamic>{
            'label': 'Comprar',
            'link': '/productos',
            'style': 'filled',
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      final labelField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'Comprar',
      );
      expect(labelField, findsOneWidget);
      await tester.ensureVisible(labelField);
      await tester.tap(labelField);
      await tester.pump();

      await tester.enterText(labelField, 'V');
      await settle(tester);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.controller?.text == 'V',
        ),
        'Ver',
      );
      await settle(tester);
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is TextField && widget.controller?.text == 'Ver',
        ),
        'Ver bicicletas',
      );
      await settle(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(dataOf(provider)['label'], 'Ver bicicletas');
      expect(dataOf(provider)['link'], '/productos');
      expect(dataOf(provider)['actions'], isNotEmpty);
      expect(provider.canUndo, isTrue);

      provider.undo();
      expect(dataOf(provider)['label'], 'Comprar');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('en Escritorio el campo dice Común y no ofrece personalizar',
        (tester) async {
      useViewport(tester, width: 1440, height: 1400);
      final provider = providerFor(
        block(
          type: 'hero',
          data: <String, dynamic>{'title': 'P', 'alignment': 'left'},
        ),
        viewport: DevicePreviewMode.desktop,
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 1440));
      await settle(tester);
      await discloseSections(tester);

      expect(
        stateOf(tester, 'alignment').status,
        WebsiteResponsiveFieldStatus.common,
      );
      expect(
        stateOf(tester, 'alignment').effectiveWriteScope,
        WebsiteWriteScope.shared,
      );
      expect(
        find.descendant(
          of: shellFor('alignment'),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        ),
        findsNothing,
      );
    });
  });

  group('D · un campo anidado pertenece a su item, no a la raíz', () {
    testWidgets('la imagen de un item de Gallery escribe en el item',
        (tester) async {
      useViewport(tester, width: 420, height: 1400);
      final provider = providerFor(
        block(
          type: 'gallery',
          data: <String, dynamic>{
            'title': 'Galería',
            'images': <Map<String, dynamic>>[
              {
                'id': 'img-a',
                'imageUrl': 'https://cdn/a.webp',
                'altText': 'Foto A',
              },
              {
                'id': 'img-b',
                'imageUrl': 'https://cdn/b.webp',
                'altText': 'Foto B',
              },
            ],
          },
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 420));
      await settle(tester);
      await discloseSections(tester);

      // El shell del item existe y resuelve el valor DEL ITEM, no el de la
      // raíz — que ni siquiera tiene `imageUrl`.
      final state = stateOf(tester, 'imageUrl');
      expect(state.resolved.value, 'https://cdn/a.webp');
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);

      // Desde el lote de colecciones la imagen de un item de Galería declara
      // `responsiveOptional`, así que en móvil dice Heredado y ofrece
      // personalizar. Lo que este test sigue custodiando es OTRA cosa: que sin
      // pedir la personalización la escritura aterrice en el valor común DEL
      // ITEM. La matriz de la familia vive en
      // `website_collections_responsive_policies_test.dart`.
      expect(state.status, WebsiteResponsiveFieldStatus.inherited);
      expect(
        find.descendant(
          of: shellFor('imageUrl'),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        ),
        findsOneWidget,
      );

      // La escritura sale del control montado en producción — el mismo
      // callback que el binding le cableó — no de un binding reconstruido en
      // el test ni de un método privado.
      // El shell vive DENTRO de `ResponsiveMediaField` — el control es quien lo
      // monta —, así que el campo es su ancestro, no su descendiente.
      final mediaField = tester.widget<ResponsiveMediaField>(
        find.ancestor(
          of: shellFor('imageUrl'),
          matching: find.byType(ResponsiveMediaField),
        ),
      );
      mediaField.onChanged('https://cdn/a-mobile.webp');
      await settle(tester);

      final images = (dataOf(provider)['images'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

      // La autoridad correcta: el valor común DEL ITEM 0.
      expect(images[0]['imageUrl'], 'https://cdn/a-mobile.webp');
      // Sin `Personalizar`, el alcance sigue siendo el común: escribir en
      // móvil no crea un override por su cuenta.
      expect(images[0].containsKey('responsive'), isFalse);
      // El hermano no se enteró.
      expect(images[1]['imageUrl'], 'https://cdn/b.webp');
      expect(images[1].containsKey('responsive'), isFalse);
      // Y la raíz del bloque no adquirió la propiedad del item: ESTE es el
      // defecto que la fase corrigió, cuando la media anidada usaba la factory
      // `root` y escribía `block_data.imageUrl`.
      expect(dataOf(provider).containsKey('imageUrl'), isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);

      // Y el editor ya muestra el valor nuevo del item.
      expect(
        stateOf(tester, 'imageUrl').resolved.value,
        'https://cdn/a-mobile.webp',
      );

      final altField = textFieldWithValue('Foto A');
      expect(altField, findsOneWidget);
      tester.widget<TextFormField>(altField).onChanged!('Detalle de A');
      await settle(tester);
      final afterAlt = (dataOf(provider)['images'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      expect(afterAlt[0]['altText'], 'Detalle de A');
      expect(afterAlt[1]['altText'], 'Foto B');
      expect(dataOf(provider).containsKey('altText'), isFalse);
    });
  });

  group('E · el mismo editor sirve a los tres anchos y a las dos luces', () {
    for (final width in <double>[390, 834, 1440]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            '$width · $brightness sin overflow y con un solo shell '
            'por campo', (tester) async {
          useViewport(tester, width: width, height: 1600);
          final provider = providerFor(
            block(
              type: 'hero',
              data: <String, dynamic>{
                'title': 'Portada',
                'alignment': 'left',
                'overlayOpacity': 0.4,
                'showOverlay': true,
              },
            ),
          );
          await tester.pumpWidget(
            host(
              provider: provider,
              editorWidth: width,
              brightness: brightness,
            ),
          );
          await settle(tester);
          await discloseSections(tester);

          expect(shellFor('alignment'), findsOneWidget);
          expect(find.text('Alineación'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto la acción del shell cumple 48',
        (tester) async {
      useViewport(tester, width: 390, height: 1600);
      final provider = providerFor(
        block(
          type: 'hero',
          data: <String, dynamic>{'title': 'P', 'alignment': 'left'},
        ),
      );
      await tester.pumpWidget(host(provider: provider, editorWidth: 390));
      await settle(tester);
      await discloseSections(tester);

      final action = find.descendant(
        of: shellFor('alignment'),
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      expect(action, findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    });
  });

  group('F · guard estático', () {
    final schemaSource =
        File('lib/modules/website/widgets/editor_panel/schema_controls.dart')
            .readAsStringSync();

    test('los campos responsive del genérico pasan por el binding', () {
      expect(schemaSource, contains('WebsiteResponsiveScalarBinding<'));
      expect(schemaSource, contains('field.allowsViewportOverride'));
      expect(schemaSource, contains('_responsiveField<'));
      // El valor mostrado sale del estado resuelto.
      expect(schemaSource, contains('binding.value'));
    });

    test('la media anidada no puede volver a la raíz', () {
      expect(
        schemaSource,
        contains('WebsiteResponsiveMediaBinding.repeaterItem('),
        reason: 'un item debe usar la factory de repeater',
      );
      expect(
        schemaSource,
        contains('WebsiteResponsiveRepeaterField.forItem('),
        reason: 'el repeater debe propagar su owner a los itemFields',
      );
      // Y el owner es un parámetro del constructor de campo, no una suposición.
      expect(schemaSource, contains('WebsiteResponsiveFieldOwner owner'));
    });

    test('el shell no recibe una segunda etiqueta', () {
      // Cada control montado bajo el shell entra con label vacío; el shell es
      // el único que escribe `field.label`.
      final responsiveMounts =
          RegExp(r'_responsiveField<[^>]+>\(').allMatches(schemaSource).length;
      expect(responsiveMounts, greaterThanOrEqualTo(5));
      expect(schemaSource, contains("label: ''"));
    });
  });
}
