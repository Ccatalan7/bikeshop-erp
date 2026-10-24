import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/google_reviews_carousel.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Fase 8 · los dos gaps que se cierran dentro del editor y del bloque.
///
/// Design: proyecto `a0fa3196-6315-4b96-bde7-7cc801e7a74e`, página
/// `Website Builder Responsive Authoring`, turnos t10 (`F-06` densidad táctil,
/// `A-01` acciones) y t11 (cada rol se consume de `VinabikeThemeRoles`; el
/// Website Builder no declara un hex propio). No se introduce ningún valor
/// visual nuevo: la geometría y las opacidades son las que ya existían.
void main() {
  // ---------------------------------------------------- gap 1 · colección

  WebsiteEditModeProvider providerFor(Map<String, dynamic> data) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          {
            'id': 'block-1',
            'block_type': 'carousel',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('block-1');
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  List<Map<String, dynamic>> slidesOf(WebsiteEditModeProvider provider) =>
      (dataOf(provider)['slides'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Map<String, dynamic> carouselData() => <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          {
            'id': 'slide-a',
            'title': 'Servicio técnico',
            'subtitle': 'Mantenciones completas',
            'ctaText': 'Agendar',
            'ctaLink': '/contacto',
          },
          {
            'id': 'slide-b',
            'title': 'Bicicletas urbanas',
            'subtitle': 'Modelos livianos',
            'ctaText': 'Ver',
            'ctaLink': '/productos',
          },
        ],
      };

  Future<WebsiteEditModeProvider> pumpCarouselInspector(
    WidgetTester tester, {
    Map<String, dynamic>? data,
    double width = 390,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 2400);
    addTearDown(tester.view.reset);

    final provider = providerFor(data ?? carouselData());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: WebsiteEditorChromeScope(
            editorWidth: width,
            canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
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
      ),
    );
    await settle(tester);
    return provider;
  }

  group('1 · el Carrusel usa el owner canónico de colección', () {
    testWidgets('las cinco operaciones existen y cumplen 48', (tester) async {
      await pumpCarouselInspector(tester);

      for (final key in <Key>[
        repeaterAddKey,
        repeaterMoveBackKey,
        repeaterMoveForwardKey,
        repeaterDuplicateKey,
        repeaterDeleteKey,
      ]) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget, reason: '$key');
        await tester.ensureVisible(finder);
        await settle(tester);
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48), reason: '$key alto');
        expect(size.width, greaterThanOrEqualTo(48), reason: '$key ancho');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicar copia el contenido y NO clona la identidad',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);
      final original = dataOf(provider);

      await tester.tap(find.byKey(repeaterDuplicateKey));
      await settle(tester);

      final slides = slidesOf(provider);
      expect(slides.length, 3);
      expect(slides[0]['id'], 'slide-a');
      expect(slides[1]['title'], 'Servicio técnico', reason: 'es la copia');
      expect(slides[1]['ctaLink'], '/contacto');
      expect(
        slides[1].containsKey('id'),
        isFalse,
        reason: 'dos slides con el mismo id romperían la escritura por '
            'identidad',
      );
      expect(slides[2]['id'], 'slide-b', reason: 'el hermano se corrió');

      // Un gesto, una entrada de historial.
      provider.undo();
      await settle(tester);
      expect(dataOf(provider), original);
    });

    testWidgets('reordenar mueve el slide y la selección lo sigue',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);

      await tester.tap(find.byKey(repeaterMoveForwardKey));
      await settle(tester);

      final slides = slidesOf(provider);
      expect(slides.map((slide) => slide['id']), <String>[
        'slide-b',
        'slide-a',
      ]);
      expect(
        provider.carouselSlideSelection('block-1', slides.length),
        1,
        reason: 'la selección viaja con el slide movido',
      );

      // Y la operación inversa vuelve al orden original.
      await tester.tap(find.byKey(repeaterMoveBackKey));
      await settle(tester);
      expect(
        slidesOf(provider).map((slide) => slide['id']),
        <String>['slide-a', 'slide-b'],
      );
    });

    testWidgets('agregar conserva los valores por defecto de la familia',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);

      await tester.tap(find.byKey(repeaterAddKey));
      await settle(tester);

      final slides = slidesOf(provider);
      expect(slides.length, 3);
      expect(slides.last['title'], 'Nuevo Slide');
      expect(slides.last['ctaLink'], '/productos');
      expect(slides.last['overlayOpacity'], 0.55);
      expect(
        provider.carouselSlideSelection('block-1', slides.length),
        2,
        reason: 'el slide nuevo queda seleccionado',
      );
    });

    testWidgets('doble callback antes del rebuild ejecuta un solo comando',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);
      final before = dataOf(provider);
      final add = tester.widget<IconButton>(find.byKey(repeaterAddKey));

      // Dos eventos nacidos del mismo árbol comparten la misma lease. El
      // segundo debe fallar cerrado aunque todavía no haya ocurrido un pump.
      add.onPressed!();
      add.onPressed!();
      await settle(tester);

      expect(slidesOf(provider).length, 3);
      provider.undo();
      await settle(tester);
      expect(dataOf(provider), before, reason: 'hubo una sola historia');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('el último slide no se puede eliminar', (tester) async {
      final provider = await pumpCarouselInspector(
        tester,
        data: <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            {'id': 'slide-a', 'title': 'Único'},
          ],
        },
      );
      final before = dataOf(provider);

      final delete = tester.widget<IconButton>(find.byKey(repeaterDeleteKey));
      expect(
        delete.onPressed,
        isNull,
        reason: '`minItems: 1` del registro, no una regla local',
      );
      expect(dataOf(provider), before);
    });

    testWidgets('eliminar quita el slide activo y reubica la selección',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);

      await tester.tap(find.byKey(repeaterDeleteKey));
      await settle(tester);

      final slides = slidesOf(provider);
      expect(slides.length, 1);
      expect(slides.single['id'], 'slide-b');
      expect(provider.carouselSlideSelection('block-1', slides.length), 0);
    });
  });

  // ------------------------- gap 1b · reordenar con el dedo, sin robar scroll

  group('1b · el dedo reordena desde el handle y sigue pudiendo desplazar', () {
    Finder handleAt(int index) => find.byKey(repeaterDragHandleKey(index));

    testWidgets('el handle existe por item y cumple 48', (tester) async {
      await pumpCarouselInspector(tester);

      for (var index = 0; index < 2; index++) {
        expect(handleAt(index), findsOneWidget, reason: 'handle $index');
        final size = tester.getSize(handleAt(index));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      // Y se anuncia como lo que es.
      expect(
        tester.getSemantics(handleAt(0)).label.contains('Reordenar'),
        isTrue,
      );
    });

    testWidgets('long press + arrastre TÁCTIL reordena, con un solo undo',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);
      final before = dataOf(provider);

      final from = tester.getCenter(handleAt(0));
      final to = tester.getCenter(handleAt(1));

      // Un dedo de verdad: el mismo tipo de puntero que falla en el teléfono.
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await settle(tester);

      expect(
        slidesOf(provider).map((slide) => slide['id']),
        <String>['slide-b', 'slide-a'],
        reason: 'el dedo movió el slide',
      );
      expect(
        provider.carouselSlideSelection('block-1', 2),
        1,
        reason: 'la selección sigue al slide movido',
      );

      // Un gesto, una entrada de historial.
      provider.undo();
      await settle(tester);
      expect(dataOf(provider), before);
    });

    testWidgets('un swipe desde el handle desplaza la tira y NO reordena',
        (tester) async {
      // Seis items en 390: la tira desborda de verdad, así que hay scroll que
      // perder. Con dos no lo habría y la prueba no diría nada.
      final provider = await pumpCarouselInspector(
        tester,
        data: <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            for (var index = 0; index < 6; index++)
              <String, dynamic>{
                'id': 'slide-$index',
                'title': 'Slide número $index',
                'subtitle': 'Detalle $index',
              },
          ],
        },
      );
      final before = dataOf(provider);

      final strip = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .firstWhere((state) => state.position.axis == Axis.horizontal);
      expect(strip.position.maxScrollExtent, greaterThan(100),
          reason: 'la tira desborda de verdad');
      expect(strip.position.pixels, 0);

      // El dedo empieza EXACTAMENTE sobre el handle y arrastra sin esperar.
      final gesture = await tester.startGesture(
        tester.getCenter(handleAt(0)),
        kind: PointerDeviceKind.touch,
      );
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);

      expect(strip.position.pixels, greaterThan(80),
          reason: 'antes del long press el gesto es de la tira');
      expect(
        dataOf(provider),
        before,
        reason: 'deslizar la tira no puede reordenar la colección',
      );
      expect(provider.canUndo, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('un drag ya iniciado no adopta un source nuevo',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);
      final before = dataOf(provider);
      final from = tester.getCenter(handleAt(0));
      final to = tester.getCenter(handleAt(1));

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));

      final external = <Map<String, dynamic>>[
        {
          'id': 'slide-b',
          'title': 'Bicicletas urbanas editadas',
          'subtitle': 'Modelos livianos',
          'ctaText': 'Ver',
          'ctaLink': '/productos',
        },
        {
          'id': 'slide-a',
          'title': 'Servicio técnico',
          'subtitle': 'Mantenciones completas',
          'ctaText': 'Agendar',
          'ctaLink': '/contacto',
        },
      ];
      // No pump: el DragTarget visible sigue siendo el árbol anterior. Aun
      // así su payload retiene la lease exacta del source que inició el drag.
      provider.updateBlockData('block-1', 'slides', external);
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await settle(tester);

      expect(slidesOf(provider), external,
          reason: 'el drop stale no clobberiza ni redirige la colección');
      provider.undo();
      await settle(tester);
      expect(dataOf(provider), before,
          reason: 'sólo quedó la escritura externa en historia');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('los botones siguen siendo la alternativa sin arrastre',
        (tester) async {
      final provider = await pumpCarouselInspector(tester);

      await tester.tap(find.byKey(repeaterMoveForwardKey));
      await settle(tester);
      expect(
        slidesOf(provider).map((slide) => slide['id']),
        <String>['slide-b', 'slide-a'],
      );
    });
  });

  // ------------------------------------------------ gap 3 · Google Reviews

  group('3 · Google Reviews consume el theme, no literales', () {
    Map<String, dynamic> reviewsData() => <String, dynamic>{
          'title': 'Reseñas',
          'minRating': 4,
          'reviews': <Map<String, dynamic>>[
            {
              'author_name': 'Carla Pérez',
              'rating': 5,
              'text': 'Quedó impecable.',
              'relative_time': 'hace 2 semanas',
            },
          ],
        };

    Future<ColorScheme> pumpReviews(
      WidgetTester tester, {
      required Brightness brightness,
      Color primary = Colors.teal,
      Color accent = Colors.tealAccent,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);

      final theme = AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GoogleReviewsCarousel(
                data: reviewsData(),
                primaryColor: primary,
                accentColor: accent,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      return theme.colorScheme;
    }

    for (final brightness in Brightness.values) {
      testWidgets('$brightness: superficies, tinta y bordes salen del esquema',
          (tester) async {
        final scheme = await pumpReviews(tester, brightness: brightness);

        // La tarjeta y su borde.
        final card = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = card.decoration! as BoxDecoration;
        expect(decoration.color, scheme.surfaceContainer);
        expect(
          (decoration.border! as Border).top.color,
          scheme.outlineVariant,
        );
        expect(decoration.boxShadow!.single.color.a, closeTo(0.05, 0.001));

        // La tinta del texto de la reseña.
        final reviewText = tester.widget<Text>(find.text('Quedó impecable.'));
        expect(reviewText.style?.color, scheme.onSurface);
        // Y la hora relativa, atenuada por rol.
        final time = tester.widget<Text>(find.text('hace 2 semanas'));
        expect(time.style?.color, scheme.onSurfaceVariant);

        // Ni blanco ni negro literales sobrevivieron en esas piezas.
        for (final color in <Color?>[
          decoration.color,
          reviewText.style?.color,
          time.style?.color,
        ]) {
          expect(color, isNot(Colors.white));
          expect(color, isNot(Colors.black87));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('la marca Google sobrevive; el resto sigue a los tokens',
        (tester) async {
      await pumpReviews(
        tester,
        brightness: Brightness.light,
        primary: const Color(0xFF7B1FA2),
        accent: const Color(0xFFFF6D00),
      );

      // La nota agregada usa el primary de la tienda, que antes se ignoraba.
      final rating = tester.widget<Text>(find.text('5.0'));
      expect(rating.style?.color, const Color(0xFF7B1FA2));

      // El monograma usa el accent recibido.
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, const Color(0xFFFF6D00));

      // Y las estrellas y la G siguen siendo de Google.
      final stars = tester.widgetList<Icon>(find.byIcon(Icons.star));
      expect(stars, isNotEmpty);
      expect(
        stars.map((icon) => icon.color).toSet(),
        contains(const Color(0xFFFBBC04)),
      );
      final wordmark = tester.widget<Text>(find.text('G'));
      expect(wordmark.style?.color, const Color(0xFF4285F4));
    });

    testWidgets('cambiar los tokens cambia el bloque', (tester) async {
      await pumpReviews(
        tester,
        brightness: Brightness.light,
        primary: const Color(0xFF00695C),
      );
      final first = tester.widget<Text>(find.text('5.0')).style?.color;

      await pumpReviews(
        tester,
        brightness: Brightness.light,
        primary: const Color(0xFFB71C1C),
      );
      final second = tester.widget<Text>(find.text('5.0')).style?.color;

      expect(first, const Color(0xFF00695C));
      expect(second, const Color(0xFFB71C1C));
      expect(first, isNot(second));
    });
  });
}
