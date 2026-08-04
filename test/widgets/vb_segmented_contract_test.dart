import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

/// `S-04 VbSegmented` contract.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `GUÍA GENERAL Viñabike - Componentes` (S-04, F-02, F-04, F-05, F-06, A-01),
/// consumed through `Website Builder Responsive Authoring` t10/t11.
void main() {
  Widget host({
    required Widget child,
    Size size = const Size(1440, 900),
    AppearancePreset preset = AppearancePresets.pacific,
    Brightness brightness = Brightness.light,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(preset: preset, brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  List<VbSegmentedOption<String>> viewportOptions({
    bool desktopEnabled = true,
  }) {
    return [
      VbSegmentedOption<String>(
        value: 'desktop',
        label: 'Escritorio',
        enabled: desktopEnabled,
        disabledReason: desktopEnabled
            ? null
            : 'Escritorio es la base: aquí siempre se edita el valor común.',
      ),
      const VbSegmentedOption<String>(value: 'tablet', label: 'Tablet'),
      const VbSegmentedOption<String>(value: 'mobile', label: 'Móvil'),
    ];
  }

  double trackHeight(WidgetTester tester) {
    // The SizedBox that owns the segmented height sits inside the track
    // padding; its own box is the geometry under test.
    final sized = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(VbSegmented<String>),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    return sized.height!;
  }

  group('S-04 geometría', () {
    testWidgets('compact 28 sobre un host de puntero >= 900', (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      expect(trackHeight(tester), 28);
    });

    testWidgets('touch 48 bajo 900 px lógicos, sin preguntar preferencia',
        (tester) async {
      await tester.pumpWidget(
        host(
          size: const Size(390, 844),
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      expect(trackHeight(tester), 48);
    });

    testWidgets('la densidad la decide el host, no el ancho de la caja local',
        (tester) async {
      // A 420 px inspector pane on a 1440 px desktop is a narrow box on a
      // pointer host. `F-06` speaks about logical viewport width.
      await tester.pumpWidget(
        host(
          child: SizedBox(
            width: 420,
            child: VbSegmented<String>(
              options: viewportOptions(),
              value: 'desktop',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(trackHeight(tester), 28);
    });

    testWidgets('radios y trazo salen de F-04', (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      expect(VbSegmentedMetrics.trackRadius, 6);
      expect(VbSegmentedMetrics.segmentRadius, 4);
      expect(VbSegmentedMetrics.focusRingWidth, 3);
      expect(VbSegmentedMetrics.hairline, 1);

      // `F-05`: una superficie dentro de otra no gana sombra.
      final containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(VbSegmented<String>),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(containers, isNotEmpty);
      for (final container in containers) {
        final decoration = container.decoration as BoxDecoration?;
        expect(decoration?.boxShadow, anyOf(isNull, isEmpty));
      }
    });

    testWidgets('S-04 rechaza conjuntos fuera de 2–4 opciones', (tester) async {
      expect(
        () => VbSegmented<String>(
          options: const [VbSegmentedOption<String>(value: 'a', label: 'A')],
          value: 'a',
          onChanged: (_) {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('S-04 selección con puntero', () {
    testWidgets('tocar un segmento habilitado emite su valor', (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: emitted.add,
          ),
        ),
      );

      await tester.tap(find.text('Móvil'));
      await tester.pumpAndSettle();
      expect(emitted, ['mobile']);
    });

    testWidgets('re-tocar el valor activo no emite', (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: emitted.add,
          ),
        ),
      );

      await tester.tap(find.text('Escritorio'));
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);
    });

    testWidgets('un segmento deshabilitado no emite al tocarlo',
        (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(desktopEnabled: false),
            value: 'tablet',
            onChanged: emitted.add,
          ),
        ),
      );

      await tester.tap(find.text('Escritorio'));
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);
    });
  });

  group('S-04 teclado', () {
    Future<void> pumpFocused(
      WidgetTester tester,
      List<String> emitted, {
      String value = 'tablet',
      bool desktopEnabled = true,
    }) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(desktopEnabled: desktopEnabled),
            value: value,
            onChanged: emitted.add,
          ),
        ),
      );
      final focusNode = tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(VbSegmented<String>),
                  matching: find.byType(Focus),
                )
                .first,
          )
          .focusNode!;
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);
    }

    testWidgets('flecha derecha e izquierda cambian la selección',
        (tester) async {
      final emitted = <String>[];
      await pumpFocused(tester, emitted);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(emitted, ['mobile']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(emitted, ['mobile', 'desktop']);
    });

    testWidgets('Home y End van a los extremos', (tester) async {
      final emitted = <String>[];
      await pumpFocused(tester, emitted);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(emitted.last, 'mobile');

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(emitted.last, 'desktop');
    });

    testWidgets('las flechas saltan los deshabilitados y no se salen del rango',
        (tester) async {
      final emitted = <String>[];
      await pumpFocused(
        tester,
        emitted,
        value: 'tablet',
        desktopEnabled: false,
      );

      // Escritorio está deshabilitado: la izquierda no tiene destino válido y
      // la selección no se sale del rango.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);

      // Home salta al primer habilitado, que es Tablet y ya está seleccionado.
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);

      // End sí tiene destino.
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(emitted, ['mobile']);
    });

    testWidgets('Enter y Espacio confirman sin duplicar emisión',
        (tester) async {
      final emitted = <String>[];
      await pumpFocused(tester, emitted);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(emitted, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(emitted, ['mobile']);
    });

    testWidgets('el grupo es un solo stop de Tab', (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      final focusables = tester
          .widgetList<Focus>(
            find.descendant(
              of: find.byType(VbSegmented<String>),
              matching: find.byType(Focus),
            ),
          )
          .where((focus) => focus.canRequestFocus)
          .toList();
      expect(focusables.length, 1);
    });
  });

  group('S-04 grupo deshabilitado', () {
    const groupReason =
        'Selecciona un bloque para elegir la vista que quieres editar.';

    testWidgets('onChanged nulo sin razón de grupo es un error de contrato',
        (tester) async {
      expect(
        () => VbSegmented<String>(
          options: viewportOptions(),
          value: 'desktop',
          onChanged: null,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('una razón de grupo en blanco tampoco explica nada',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: null,
            groupDisabledReason: '   ',
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('la razón del grupo se muestra una sola vez', (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: null,
            groupDisabledReason: groupReason,
          ),
        ),
      );
      expect(find.text(groupReason), findsOneWidget);
    });

    testWidgets('ninguna semántica contiene la palabra null', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            groupLabel: 'Vista del sitio',
            options: viewportOptions(),
            value: 'desktop',
            onChanged: null,
            groupDisabledReason: groupReason,
          ),
        ),
      );

      for (final label in ['Escritorio', 'Tablet', 'Móvil']) {
        final node = tester.getSemantics(find.text(label));
        expect(
          node.label,
          isNot(contains('null')),
          reason: '$label no puede anunciar "null"',
        );
        expect(node.label, contains('No disponible'));
        expect(node.label, contains(groupReason));
        expect(node, containsSemantics(isEnabled: false));
      }
      handle.dispose();
    });

    testWidgets('el grupo inerte no toma foco ni responde al puntero',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: null,
            groupDisabledReason: groupReason,
          ),
        ),
      );

      final focusNode = tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(VbSegmented<String>),
                  matching: find.byType(Focus),
                )
                .first,
          )
          .focusNode!;
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.text('Móvil'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('la razón por opción sobrevive cuando el grupo está activo',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(desktopEnabled: false),
            value: 'tablet',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.textContaining('Escritorio es la base'), findsOneWidget);
      expect(find.text(groupReason), findsNothing);
    });
  });

  group('S-04 estado y semántica', () {
    testWidgets('el foco pinta el anillo desde VinabikeThemeRoles.focusRing',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      final context = tester.element(find.byType(VbSegmented<String>));
      final roles = VinabikeThemeRoles.of(context);

      BoxDecoration trackDecoration() {
        return tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(VbSegmented<String>),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration as BoxDecoration;
      }

      expect(
        (trackDecoration().border as Border).top.color,
        roles.neutral.border,
      );

      final focusNode = tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(VbSegmented<String>),
                  matching: find.byType(Focus),
                )
                .first,
          )
          .focusNode!;
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final border = trackDecoration().border as Border;
      expect(border.top.color, roles.focusRing);
      expect(border.top.width, VbSegmentedMetrics.focusRingWidth);
    });

    testWidgets('la razón del deshabilitado es texto, no sólo tooltip',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(desktopEnabled: false),
            value: 'tablet',
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        find.textContaining('Escritorio es la base'),
        findsOneWidget,
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('S-04 exige razón para un segmento deshabilitado',
        (tester) async {
      expect(
        () => VbSegmentedOption<String>(
          value: 'x',
          label: 'X',
          enabled: false,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('semántica anuncia grupo, seleccionado y deshabilitado',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            groupLabel: 'Vista del sitio',
            options: viewportOptions(desktopEnabled: false),
            value: 'tablet',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Vista del sitio'), findsOneWidget);

      // `containsSemantics` verifica sólo lo declarado. `matchesSemantics` es
      // exhaustivo y fallaría por banderas que Flutter agrega entre versiones,
      // ajenas a este contrato.
      expect(
        tester.getSemantics(find.text('Tablet')),
        containsSemantics(
          label: 'Tablet',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );

      final disabled = tester.getSemantics(find.text('Escritorio'));
      expect(disabled, containsSemantics(isEnabled: false));
      expect(disabled.label, contains('No disponible'));
      expect(disabled.label, contains('Escritorio es la base'));
      handle.dispose();
    });

    testWidgets('el seleccionado se distingue sin depender del color',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'mobile',
            onChanged: (_) {},
          ),
        ),
      );
      final selected = tester.widget<Text>(find.text('Móvil'));
      final unselected = tester.widget<Text>(find.text('Tablet'));
      expect(selected.style!.fontWeight, FontWeight.w600);
      expect(
        unselected.style!.fontWeight,
        isNot(FontWeight.w600),
      );
    });

    testWidgets('disableAnimations acorta el motion a la duración reducida',
        (tester) async {
      await tester.pumpWidget(
        host(
          disableAnimations: true,
          child: VbSegmented<String>(
            options: viewportOptions(),
            value: 'desktop',
            onChanged: (_) {},
          ),
        ),
      );
      final container = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(VbSegmented<String>),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .first;
      expect(container.duration, VbSegmentedMetrics.motionReduced);
      expect(container.curve, VbSegmentedMetrics.motionCurve);
    });
  });

  group('S-04 matriz de roles · 6 presets × 2 brightness', () {
    testWidgets('la pista y el texto salen siempre de roles resueltos',
        (tester) async {
      for (final preset in AppearancePresets.all) {
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            host(
              preset: preset,
              brightness: brightness,
              child: VbSegmented<String>(
                options: viewportOptions(),
                value: 'desktop',
                onChanged: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final context = tester.element(find.byType(VbSegmented<String>));
          final roles = VinabikeThemeRoles.of(context);
          final scheme = Theme.of(context).colorScheme;

          final track = tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byType(VbSegmented<String>),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration as BoxDecoration;
          expect(
            track.color,
            roles.neutral.container,
            reason: '${preset.code}/$brightness usa neutral.container',
          );

          final selected = tester.widget<Text>(find.text('Escritorio'));
          expect(
            selected.style!.color,
            scheme.onSurface,
            reason: '${preset.code}/$brightness usa onSurface',
          );
          final unselected = tester.widget<Text>(find.text('Tablet'));
          expect(
            unselected.style!.color,
            roles.neutral.accent,
            reason: '${preset.code}/$brightness usa neutral.accent',
          );
        }
      }
    });
  });
}
