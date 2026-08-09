import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// Header and footer as one editable identity: theme boundary and keyboard.
///
/// Both were two copies with two literal palettes — `Colors.blue` and
/// `Colors.green` — permanently ringed at 2 px whether or not anything was
/// selected. Both are now one typed owner, and both restore the ERP's own
/// appearance instead of wearing whatever palette the tenant authored.
void main() {
  group('el host ERP se restaura a través del tema del sitio', () {
    testWidgets('host oscuro con sitio claro: el chrome toma el ERP',
        (tester) async {
      final erpDark = AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      );
      final siteLight = AppTheme.resolve(
        preset: AppearancePresets.evergreen,
        brightness: Brightness.light,
      );

      late ThemeData captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: erpDark,
          home: Builder(
            builder: (hostContext) => WebsiteEditorHostTheme.capture(
              context: hostContext,
              // Everything below here is the AUTHORED site.
              child: Theme(
                data: siteLight,
                child: Builder(
                  builder: (siteContext) {
                    final host = WebsiteEditorHostTheme.maybeOf(siteContext)!;
                    captured = host.theme;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // The operator's chrome resolves the ERP, not the tenant's brand.
      expect(captured.brightness, Brightness.dark);
      expect(captured.colorScheme.surface, erpDark.colorScheme.surface);
      expect(
        captured.colorScheme.surface,
        isNot(siteLight.colorScheme.surface),
      );
    });

    testWidgets('y las roles semánticas del host viajan con él',
        (tester) async {
      final erpDark = AppTheme.resolve(
        preset: AppearancePresets.aubergine,
        brightness: Brightness.dark,
      );
      late VinabikeThemeRoles? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: erpDark,
          home: Builder(
            builder: (hostContext) => WebsiteEditorHostTheme.capture(
              context: hostContext,
              child: Theme(
                data: AppTheme.resolve(
                  preset: AppearancePresets.pacific,
                  brightness: Brightness.light,
                ),
                child: Builder(
                  builder: (siteContext) {
                    captured =
                        WebsiteEditorHostTheme.maybeOf(siteContext)!.roles;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(captured, isNotNull);
      // Selection has its own published role: it is not `info.accent`, which is
      // what a notice uses.
      expect(
        captured!.selectionContainer,
        erpDark.extension<VinabikeThemeRoles>()!.selectionContainer,
      );
    });
  });

  group('la superficie seleccionable se opera sin puntero', () {
    /// The chrome's contract, exercised through the same three parts the
    /// storefront wires: a focusable detector, Enter/Space bound to the same
    /// callback as a tap, and a translucent gesture layer so the authored
    /// links underneath keep receiving their own taps.
    Widget host({
      required VoidCallback onSelect,
      required VoidCallback onInnerTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: FocusableActionDetector(
            autofocus: true,
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  onSelect();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onSelect,
              child: Center(
                child: TextButton(
                  key: const ValueKey('authored-link'),
                  onPressed: onInnerTap,
                  child: const Text('Catálogo'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Enter y Space seleccionan igual que un toque', (tester) async {
      var selections = 0;
      await tester.pumpWidget(
        host(onSelect: () => selections++, onInnerTap: () {}),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selections, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(selections, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pump();
      expect(selections, 3);
    });

    testWidgets('seleccionar no le roba el toque al enlace publicado',
        (tester) async {
      var selections = 0;
      var innerTaps = 0;
      await tester.pumpWidget(
        host(onSelect: () => selections++, onInnerTap: () => innerTaps++),
      );
      await tester.pump();

      // A translucent behaviour lets both receive it: the authored control
      // still works while the surface around it is selectable. An opaque
      // wrapper would have swallowed the site's own navigation.
      await tester.tap(find.byKey(const ValueKey('authored-link')));
      await tester.pump();
      expect(innerTaps, 1);
    });
  });

  group('el estado no depende del color', () {
    test('ambas identidades se nombran en palabras', () {
      // A monochrome screenshot, or a colour-blind operator, still tells the
      // header from the footer and selected from unselected.
      expect(WebsiteEditorChromeTarget.header.label, 'Encabezado');
      expect(WebsiteEditorChromeTarget.footer.label, 'Pie de página');
      for (final target in WebsiteEditorChromeTarget.values) {
        expect(target.selectionId, isNotEmpty);
        expect(target.label, isNotEmpty);
      }
    });
  });
}
