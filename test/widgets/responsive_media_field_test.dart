import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/widgets/focal_point_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_media_field.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// `ResponsiveMediaField` contract.
///
/// Design source: `Website Builder Responsive Authoring` t10 frames 10a
/// (compact media row), 10b (override) and 10f (phone sheet).
///
/// The screenshot that motivated the plan showed a large picker plus a desktop
/// focal editor plus a mobile focal editor at once. These tests pin that this
/// is now impossible by construction.
void main() {
  const imageSchema = WebsiteBlockFieldSchema(
    key: 'imageUrl',
    label: 'Imagen de fondo',
    type: WebsiteBlockFieldType.image,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  );

  const framingSchema = WebsiteBlockFieldSchema(
    key: 'focalPoint',
    label: 'Encuadre',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
  );

  WebsiteAuthoringContext contextFor(WebsiteViewport viewport) {
    return WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: viewport,
      writeScope: viewport == WebsiteViewport.desktop
          ? WebsiteWriteScope.shared
          : WebsiteWriteScope.viewport,
    );
  }

  WebsiteResponsiveFieldState<String> urlState({
    WebsiteViewport viewport = WebsiteViewport.desktop,
    String url = 'https://cdn.example/hero-taller-2026.webp',
    bool isOverride = false,
  }) {
    return WebsiteResponsiveFieldState<String>.resolve(
      schema: imageSchema,
      context: contextFor(viewport),
      resolved: WebsiteResolvedResponsiveValue<String>(
        shared: url,
        value: url,
        viewport: viewport,
        isOverride: isOverride,
        isLegacyOverride: false,
      ),
    );
  }

  WebsiteResponsiveFieldState<Offset> focalState({
    WebsiteViewport viewport = WebsiteViewport.desktop,
    bool isOverride = false,
    bool isLegacyOverride = false,
  }) {
    return WebsiteResponsiveFieldState<Offset>.resolve(
      schema: framingSchema,
      context: contextFor(viewport),
      resolved: WebsiteResolvedResponsiveValue<Offset>(
        shared: const Offset(0.5, 0.5),
        value: isOverride ? const Offset(0.7, 0.3) : const Offset(0.5, 0.5),
        viewport: viewport,
        isOverride: isOverride,
        isLegacyOverride: isLegacyOverride,
      ),
    );
  }

  Widget host({
    required WebsiteResponsiveFieldState<String> url,
    required WebsiteResponsiveFieldState<Offset> focal,
    double width = 420,
    Size size = const Size(1440, 900),
    ValueChanged<String>? onChanged,
    void Function(double, double)? onFocalChanged,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: ResponsiveMediaField(
                state: url,
                focalState: focal,
                onChanged: onChanged ?? (_) {},
                onFocalChanged: onFocalChanged ?? (_, __) {},
                // The shell only paints an action that has a callback; a real
                // consumer always supplies all four.
                onCustomize: () {},
                onReset: () {},
                onFocalCustomize: () {},
                onFocalReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('colapsado: una fila, cero editores de foco', () {
    testWidgets('monta exactamente una miniatura y ningún FocalPointPicker',
        (tester) async {
      await tester.pumpWidget(
        host(url: urlState(), focal: focalState()),
      );

      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
      expect(find.byType(FocalPointPicker), findsNothing);
      expect(find.byKey(ResponsiveMediaField.focalEditorKey), findsNothing);
    });

    testWidgets('la miniatura mide 48, no un preview grande', (tester) async {
      await tester.pumpWidget(
        host(url: urlState(), focal: focalState()),
      );
      final size =
          tester.getSize(find.byKey(ResponsiveMediaField.thumbnailKey));
      expect(size.width, ResponsiveMediaField.thumbnailSize);
      expect(size.height, ResponsiveMediaField.thumbnailSize);
      expect(size.width, 48);
    });

    testWidgets('el nombre del archivo se lee, no la URL completa',
        (tester) async {
      await tester.pumpWidget(
        host(url: urlState(), focal: focalState()),
      );
      expect(find.text('hero-taller-2026.webp'), findsOneWidget);
    });
  });

  group('Reencuadrar: precisión bajo demanda, siempre uno solo', () {
    testWidgets('abre exactamente un editor focal y cerrar vuelve a cero',
        (tester) async {
      await tester.pumpWidget(
        host(url: urlState(), focal: focalState()),
      );

      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();
      expect(find.byType(FocalPointPicker), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.focalEditorKey), findsOneWidget);

      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();
      expect(find.byType(FocalPointPicker), findsNothing);
    });

    testWidgets('en móvil sigue habiendo UN solo editor, no dos',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(viewport: WebsiteViewport.mobile),
          focal: focalState(viewport: WebsiteViewport.mobile),
        ),
      );

      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();

      expect(
        find.byType(FocalPointPicker),
        findsOneWidget,
        reason: 'el encuadre pertenece al viewport previsualizado',
      );
      expect(find.text('Foco móvil'), findsNothing);
    });

    testWidgets('sin capacidad focal no hay acción ni editor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: ResponsiveMediaField(
                state: urlState(),
                // Un logo, un avatar o media inline: nada que reencuadrar.
                focalState: null,
                onChanged: (_) {},
                onFocalChanged: null,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
      expect(find.text('Reencuadrar'), findsNothing);
      expect(
        find.byKey(ResponsiveMediaField.reframeActionKey),
        findsNothing,
      );
      expect(find.byType(FocalPointPicker), findsNothing);
    });

    testWidgets('sin imagen no se ofrece reencuadrar', (tester) async {
      await tester.pumpWidget(
        host(url: urlState(url: ''), focal: focalState()),
      );
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Reencuadrar'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Sin imagen'), findsOneWidget);
    });
  });

  group('estados de herencia visibles sin depender del color', () {
    testWidgets('heredado ofrece personalizar y nombra el estado',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(viewport: WebsiteViewport.mobile),
          focal: focalState(viewport: WebsiteViewport.mobile),
        ),
      );
      expect(find.text('Heredado'), findsOneWidget);
      expect(
        find.text('Los cambios se guardan sólo para Móvil.'),
        findsOneWidget,
      );
    });

    testWidgets('override nombra el viewport y ofrece restablecer',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(viewport: WebsiteViewport.mobile, isOverride: true),
          focal: focalState(viewport: WebsiteViewport.mobile),
        ),
      );
      expect(find.text('Personalizado para Móvil'), findsOneWidget);
      expect(find.text('Restablecer a Común'), findsOneWidget);
    });

    testWidgets('un eje legacy marca el encuadre completo como conflicto',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(viewport: WebsiteViewport.mobile),
          focal: focalState(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
            isLegacyOverride: true,
          ),
        ),
      );

      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();
      expect(find.text('Configuración móvil anterior'), findsOneWidget);
    });
  });

  group('compacto', () {
    testWidgets('sin overflow a 390 con el editor focal abierto',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(viewport: WebsiteViewport.mobile),
          focal: focalState(viewport: WebsiteViewport.mobile),
          width: 390,
          size: const Size(390, 844),
        ),
      );
      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('bajo 900 las acciones alcanzan el target táctil de 48',
        (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(),
          focal: focalState(),
          width: 390,
          size: const Size(390, 844),
        ),
      );
      for (final key in <Key>[
        ResponsiveMediaField.replaceActionKey,
        ResponsiveMediaField.reframeActionKey,
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(48),
        );
      }
    });

    testWidgets('sin overflow a 420 en oscuro', (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(),
          focal: focalState(),
          brightness: Brightness.dark,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
    });
  });

  group('ancho anidado: la fila fluye en vez de desbordar', () {
    // The width a repeater's indented section actually leaves at 390 — the
    // case that overflowed by 30 px and was found through Category Grid.
    const nestedAt390 = 250.0;

    for (final width in const <double>[nestedAt390, 320, 420, 560]) {
      for (final brightness in Brightness.values) {
        testWidgets('$width · $brightness sin RenderFlex overflow',
            (tester) async {
          await tester.pumpWidget(
            host(
              url: urlState(),
              focal: focalState(),
              width: width,
              brightness: brightness,
            ),
          );
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: 'la fila desborda a $width en $brightness',
          );
        });
      }
    }

    testWidgets('a ancho anidado conserva UNA miniatura y sus dos acciones',
        (tester) async {
      await tester.pumpWidget(
        host(url: urlState(), focal: focalState(), width: nestedAt390),
      );
      await tester.pump();

      expect(find.byKey(ResponsiveMediaField.thumbnailKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.replaceActionKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.reframeActionKey), findsOneWidget);
      // La miniatura conserva su tamaño publicado: la fila fluye, no encoge.
      expect(
        tester.getSize(find.byKey(ResponsiveMediaField.thumbnailKey)).height,
        ResponsiveMediaField.thumbnailSize,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('las acciones siguen operables y con target táctil a 390',
        (tester) async {
      var replaced = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          // Un host compacto real: `F-06` fuerza densidad touch bajo 900.
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: nestedAt390,
                  child: ResponsiveMediaField(
                    state: urlState(),
                    focalState: focalState(),
                    onChanged: (_) => replaced++,
                    onFocalChanged: (_, __) {},
                    onCustomize: () {},
                    onReset: () {},
                    onFocalCustomize: () {},
                    onFocalReset: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final key in const <Key>[
        ResponsiveMediaField.replaceActionKey,
        ResponsiveMediaField.reframeActionKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
        expect(size.width, greaterThan(0), reason: '$key');
      }

      // La fila colapsada — la que se ve siempre — no desborda a este ancho.
      expect(tester.takeException(), isNull);
      expect(replaced, 0);
    });

    testWidgets('Reencuadrar abre el picker a ancho anidado sin desbordar',
        (tester) async {
      // El caso que quedaba abierto: el editor de foco también se abre dentro
      // de la sección indentada de un repeater, donde recibe ~250 px.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          // Host compacto real: `F-06` fuerza densidad touch bajo 900.
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: nestedAt390,
                  child: ResponsiveMediaField(
                    state: urlState(),
                    focalState: focalState(),
                    onChanged: (_) {},
                    onFocalChanged: (_, __) {},
                    onCustomize: () {},
                    onReset: () {},
                    onFocalCustomize: () {},
                    onFocalReset: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();

      // Exactamente un picker, y ninguna excepción de layout.
      expect(find.byType(FocalPointPicker), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.focalEditorKey), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Las coordenadas siguen legibles y `Centrar` sigue alcanzable.
      expect(find.textContaining('X:'), findsOneWidget);
      expect(find.textContaining('Y:'), findsOneWidget);
      // `TextButton.icon` construye una subclase, así que se busca por
      // predicado en vez de por tipo exacto.
      final centrar = find.ancestor(
        of: find.text('Centrar'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      expect(centrar, findsOneWidget);
      expect(
        tester.getSize(centrar.first).height,
        greaterThanOrEqualTo(48),
        reason: 'el target táctil de Centrar en host compacto',
      );

      // Y cerrar vuelve a cero pickers.
      await tester.tap(find.byKey(ResponsiveMediaField.reframeActionKey));
      await tester.pumpAndSettle();
      expect(find.byType(FocalPointPicker), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'un nombre de archivo largo elide en vez de empujar las '
        'acciones', (tester) async {
      await tester.pumpWidget(
        host(
          url: urlState(
            url: 'https://cdn.example/'
                'una-imagen-con-un-nombre-larguisimo-de-verdad-2026.webp',
          ),
          focal: focalState(),
          width: nestedAt390,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ResponsiveMediaField.replaceActionKey), findsOneWidget);
      expect(find.byKey(ResponsiveMediaField.reframeActionKey), findsOneWidget);
    });
  });
}
