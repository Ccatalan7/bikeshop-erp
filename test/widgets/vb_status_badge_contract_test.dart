import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';

/// `E-01 VbStatusBadge` contract.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `GUÍA GENERAL Viñabike - Componentes` (E-01, F-01, F-02, F-04).
void main() {
  Widget host({
    required Widget child,
    AppearancePreset preset = AppearancePresets.pacific,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(preset: preset, brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    return tester
        .widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(VbStatusBadge),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .decoration as BoxDecoration;
  }

  group('E-01 anatomía', () {
    testWidgets('píldora r999, padding 3/9 y texto 9.5/600', (tester) async {
      await tester.pumpWidget(
        host(child: const VbStatusBadge(label: 'Común')),
      );

      expect(VbStatusBadge.radius, 999);
      expect(
        VbStatusBadge.padding,
        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      );

      final decoration = decorationOf(tester);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(VbStatusBadge.radius),
      );

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(VbStatusBadge),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, VbStatusBadge.padding);

      final text = tester.widget<Text>(find.text('Común'));
      expect(text.style!.fontSize, 9.5);
      expect(text.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('denso baja a 8.5 con el mismo texto', (tester) async {
      await tester.pumpWidget(
        host(child: const VbStatusBadge(label: 'Común', dense: true)),
      );
      final text = tester.widget<Text>(find.text('Común'));
      expect(text.style!.fontSize, 8.5);
      expect(text.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('sin sombra y con hairline de 1', (tester) async {
      await tester.pumpWidget(
        host(child: const VbStatusBadge(label: 'Común')),
      );
      final decoration = decorationOf(tester);
      expect(decoration.boxShadow, anyOf(isNull, isEmpty));
      expect((decoration.border! as Border).top.width, 1);
    });

    testWidgets('no aplica mayúsculas al texto', (tester) async {
      await tester.pumpWidget(
        host(child: const VbStatusBadge(label: 'Personalizado para Móvil')),
      );
      expect(find.text('Personalizado para Móvil'), findsOneWidget);
    });

    testWidgets('E-01 exige texto: el label vacío es un error', (tester) async {
      expect(() => VbStatusBadge(label: ''), throwsAssertionError);
    });

    testWidgets('un label de sólo espacios tampoco nombra el estado',
        (tester) async {
      await tester.pumpWidget(host(child: const VbStatusBadge(label: '   ')));
      expect(tester.takeException(), isAssertionError);
    });
  });

  group('E-01 informa, no ejecuta', () {
    testWidgets('no expone gesto ni acción de tap', (tester) async {
      await tester.pumpWidget(
        host(child: const VbStatusBadge(label: 'Común')),
      );
      expect(
        find.descendant(
          of: find.byType(VbStatusBadge),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(VbStatusBadge),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('el estado se anuncia por texto, no sólo por color',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          child: const VbStatusBadge(
            label: 'Configuración móvil anterior',
            tone: VbStatusTone.warning,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Configuración móvil anterior'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('el icono es decorativo y no duplica la semántica',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          child: const VbStatusBadge(
            label: 'Heredado',
            icon: Icons.link_rounded,
          ),
        ),
      );
      final node = tester.getSemantics(find.byType(VbStatusBadge));
      expect(node.label, 'Heredado');
      handle.dispose();
    });

    testWidgets('el icono decorativo usa la misma tinta que el texto',
        (tester) async {
      await tester.pumpWidget(
        host(
          child: const VbStatusBadge(
            label: 'Heredado',
            icon: Icons.link_rounded,
          ),
        ),
      );
      final context = tester.element(find.byType(VbStatusBadge));
      final roles = VinabikeThemeRoles.of(context);
      final icon = tester.widget<Icon>(find.byIcon(Icons.link_rounded));
      expect(icon.color, roles.neutral.onContainer);
      expect(
        icon.color,
        tester.widget<Text>(find.text('Heredado')).style!.color,
      );
    });

    testWidgets('semanticLabel enriquece sin cambiar el texto visible',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          child: const VbStatusBadge(
            label: 'Heredado',
            semanticLabel: 'Altura: Heredado del valor común',
          ),
        ),
      );
      expect(find.text('Heredado'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Altura: Heredado del valor común'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('E-01 tonos desde roles · 6 presets × 2 brightness', () {
    testWidgets('cada tono resuelve fondo, borde y tinta desde su rol',
        (tester) async {
      const cases = <VbStatusTone, String>{
        VbStatusTone.neutral: 'Común',
        VbStatusTone.info: 'Personalizado para Móvil',
        VbStatusTone.success: 'Guardado',
        VbStatusTone.warning: 'Configuración móvil anterior',
        VbStatusTone.danger: 'No disponible',
      };

      for (final preset in AppearancePresets.all) {
        for (final brightness in Brightness.values) {
          for (final entry in cases.entries) {
            await tester.pumpWidget(
              host(
                preset: preset,
                brightness: brightness,
                child: VbStatusBadge(label: entry.value, tone: entry.key),
              ),
            );
            await tester.pumpAndSettle();

            final context = tester.element(find.byType(VbStatusBadge));
            final roles = VinabikeThemeRoles.of(context);
            final tone = switch (entry.key) {
              VbStatusTone.neutral => roles.neutral,
              VbStatusTone.info => roles.info,
              VbStatusTone.success => roles.success,
              VbStatusTone.warning => roles.warning,
              VbStatusTone.danger => roles.danger,
            };

            final where = '${preset.code}/$brightness/${entry.key.name}';
            final decoration = decorationOf(tester);
            expect(decoration.color, tone.container, reason: '$where fondo');
            expect(
              (decoration.border! as Border).top.color,
              tone.border,
              reason: '$where borde',
            );
            // La superficie es `container`; la tinta de ese par es
            // `onContainer`. `accent` pertenece al par `accent`/`onAccent` y
            // su contraste sobre `container` no está garantizado por el
            // modelo de roles.
            //
            // Deliberadamente NO se afirma `isNot(tone.accent)`: que ambos
            // coincidan en un preset concreto es libertad del resolver, no un
            // defecto del badge. El contrato es de qué rol se lee.
            expect(
              tester.widget<Text>(find.text(entry.value)).style!.color,
              tone.onContainer,
              reason: '$where tinta',
            );
          }
        }
      }
    });

    testWidgets('los cinco tonos son distinguibles entre sí en cada brightness',
        (tester) async {
      for (final brightness in Brightness.values) {
        final backgrounds = <Color>{};
        for (final tone in VbStatusTone.values) {
          await tester.pumpWidget(
            host(
              brightness: brightness,
              child: VbStatusBadge(label: tone.name, tone: tone),
            ),
          );
          await tester.pumpAndSettle();
          backgrounds.add(decorationOf(tester).color!);
        }
        expect(
          backgrounds.length,
          VbStatusTone.values.length,
          reason: 'ningún tono colisiona en $brightness',
        );
      }
    });
  });
}
