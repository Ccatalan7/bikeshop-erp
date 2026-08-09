import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/widgets/vb_sub_tabs.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// The inspector pane's navigation, at the widths a pane actually has.
///
/// The pane overflowed on every host that mounted it: five tabs in five
/// `Expanded`s, each an icon plus a gap plus a label. `Expanded` divides width
/// but does not shrink what is inside it. These gates fail on ANY overflow —
/// there is no `takeException` here.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 — `subtabs_anatomy` for `T-04`
/// and `surface_component_map`, which already recorded the divergence this
/// replaces (*«la implementación vigente usa una cápsula con íconos; T-04
/// prohíbe fondos por tab, cápsulas e íconos»*).
void main() {
  const tabs = <VbSubTab<String>>[
    VbSubTab<String>(value: 'add', label: 'Agregar'),
    VbSubTab<String>(value: 'edit', label: 'Editar'),
    VbSubTab<String>(value: 'page', label: 'Página'),
    VbSubTab<String>(value: 'theme', label: 'Tema'),
    VbSubTab<String>(value: 'sync', label: 'Google'),
  ];

  Widget host({
    required double width,
    String activeId = 'add',
    Brightness brightness = Brightness.light,
    ValueChanged<String>? onSelected,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: VbSubTabs<String>(
            tabs: tabs,
            value: activeId,
            onChanged: onSelected ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('la navegación del pane no desborda a ningún ancho publicado', () {
    testWidgets('420, 380 y 320, claro y oscuro', (tester) async {
      for (final brightness in Brightness.values) {
        for (final width in <double>[
          WebsiteEditorChromeGeometry.inspectorWidth, // 420, el publicado
          380,
          320,
        ]) {
          await tester.pumpWidget(
            host(width: width, brightness: brightness),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'desbordó a $width en $brightness',
          );
          // Y sigue siendo navegación: la sección activa se ve.
          expect(find.text('Agregar'), findsOneWidget);
        }
      }
    });

    testWidgets('la altura publicada de T-04 se respeta', (tester) async {
      await tester.pumpWidget(host(width: 420));
      await tester.pump();
      expect(
        tester.getSize(find.byType(VbSubTabs<String>)).height,
        VbSubTabs.compactHeight,
      );
      expect(VbSubTabs.compactHeight, 32);
      expect(VbSubTabs.underline, 2);
      expect(VbSubTabs.labelSize, 12);
    });

    testWidgets('sin íconos: T-04 los prohíbe y eran la mitad del ancho',
        (tester) async {
      await tester.pumpWidget(host(width: 420));
      await tester.pump();
      // El único ícono permitido es el disparador del overflow, y sólo cuando
      // hace falta.
      final icons = find.byType(Icon);
      for (final element in icons.evaluate()) {
        expect(
          (element.widget as Icon).icon,
          Icons.more_horiz,
          reason: 'un tab no lleva ícono (T-04)',
        );
      }
    });
  });

  group('la composición se deriva del ancho, no se comprime', () {
    test('a un ancho holgado están todas inline', () {
      final layout = VbSubTabs.split<String>(
        tabs: tabs,
        value: 'add',
        maxWidth: 1000,
      );
      expect(layout.inline.length, tabs.length);
      expect(layout.overflow, isEmpty);
    });

    test('a un ancho estrecho las que no caben pasan al cajón', () {
      final layout = VbSubTabs.split<String>(
        tabs: tabs,
        value: 'add',
        maxWidth: 160,
      );
      expect(layout.inline, isNotEmpty);
      expect(layout.overflow, isNotEmpty);
      // Nada se pierde: cada destino está exactamente en un lugar.
      expect(
        {...layout.inline, ...layout.overflow},
        {for (final tab in tabs) tab.value},
      );
    });

    test('la sección activa nunca queda escondida en el cajón', () {
      for (final tab in tabs) {
        final layout = VbSubTabs.split<String>(
          tabs: tabs,
          value: tab.value,
          maxWidth: 150,
        );
        expect(
          layout.inline,
          contains(tab.value),
          reason: 'una navegación que esconde dónde estás no es navegación',
        );
        expect(layout.overflow, isNot(contains(tab.value)));
      }
    });

    test('un texto más grande mueve destinos al cajón, no los aplasta', () {
      final normal = VbSubTabs.split<String>(
        tabs: tabs,
        value: 'add',
        maxWidth: 420,
      );
      final scaled = VbSubTabs.split<String>(
        tabs: tabs,
        value: 'add',
        maxWidth: 420,
        textScaler: const TextScaler.linear(1.6),
      );
      expect(scaled.inline.length, lessThanOrEqualTo(normal.inline.length));
      expect(
        {...scaled.inline, ...scaled.overflow},
        {for (final tab in tabs) tab.value},
      );
    });
  });

  group('el cajón es navegación real', () {
    testWidgets('elegir en el overflow cambia de sección', (tester) async {
      final chosen = <String>[];
      await tester.pumpWidget(
        host(width: 150, onSelected: chosen.add),
      );
      await tester.pump();

      expect(find.byKey(VbSubTabs.overflowKey), findsOneWidget);
      await tester.tap(find.byKey(VbSubTabs.overflowKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Google').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(chosen, ['sync']);
      expect(tester.takeException(), isNull);
    });
  });
}
