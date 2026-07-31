import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

void main() {
  testWidgets(
    'changing preset repaints mounted content without losing route state',
    (tester) async {
      final preset = ValueNotifier<AppearancePreset>(
        AppearancePresets.vinabike,
      );
      addTearDown(preset.dispose);

      await tester.pumpWidget(
        _ThemeSwitchHarness(
          preset: preset,
          themeMode: ThemeMode.light,
        ),
      );

      final initialTheme = _themeAtProbe(tester);
      final initialSurface = _probeContainer(tester).color;
      expect(
        initialTheme.extension<VinabikeThemeRoles>()?.presetCode,
        'vinabike',
      );
      expect(find.text('Estado 0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('state-action')));
      await tester.pump();
      expect(find.text('Estado 1'), findsOneWidget);

      preset.value = AppearancePresets.aubergine;
      await tester.pump();

      final switchedTheme = _themeAtProbe(tester);
      final switchedSurface = _probeContainer(tester).color;
      expect(
        switchedTheme.extension<VinabikeThemeRoles>()?.presetCode,
        'aubergine',
      );
      expect(switchedTheme.colorScheme.primary,
          isNot(initialTheme.colorScheme.primary));
      // Light-mode work surfaces remain neutral across presets. The selected
      // palette repaints actions, focus, selection and shell chrome without
      // washing every content block in the preset hue.
      expect(switchedSurface, initialSurface);
      expect(find.text('Estado 1'), findsOneWidget);
    },
  );

  testWidgets(
    'ThemeMode.system follows platform brightness and preserves mounted state',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(
        tester.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      final preset = ValueNotifier<AppearancePreset>(
        AppearancePresets.pacific,
      );
      addTearDown(preset.dispose);

      await tester.pumpWidget(
        _ThemeSwitchHarness(
          preset: preset,
          themeMode: ThemeMode.system,
        ),
      );

      final lightTheme = _themeAtProbe(tester);
      final lightSurface = _probeContainer(tester).color;
      expect(lightTheme.brightness, Brightness.light);
      expect(
        lightTheme.extension<VinabikeThemeRoles>()?.brightness,
        Brightness.light,
      );

      await tester.tap(find.byKey(const ValueKey('state-action')));
      await tester.pump();
      expect(find.text('Estado 1'), findsOneWidget);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();

      final darkTheme = _themeAtProbe(tester);
      final darkSurface = _probeContainer(tester).color;
      expect(darkTheme.brightness, Brightness.dark);
      expect(
        darkTheme.extension<VinabikeThemeRoles>()?.brightness,
        Brightness.dark,
      );
      expect(darkSurface, isNot(lightSurface));
      expect(find.text('Estado 1'), findsOneWidget);
    },
  );
}

ThemeData _themeAtProbe(WidgetTester tester) {
  return Theme.of(
    tester.element(find.byKey(const ValueKey('theme-probe'))),
  );
}

Container _probeContainer(WidgetTester tester) {
  return tester.widget<Container>(
    find.byKey(const ValueKey('theme-probe')),
  );
}

class _ThemeSwitchHarness extends StatefulWidget {
  const _ThemeSwitchHarness({
    required this.preset,
    required this.themeMode,
  });

  final ValueNotifier<AppearancePreset> preset;
  final ThemeMode themeMode;

  @override
  State<_ThemeSwitchHarness> createState() => _ThemeSwitchHarnessState();
}

class _ThemeSwitchHarnessState extends State<_ThemeSwitchHarness> {
  int _state = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppearancePreset>(
      valueListenable: widget.preset,
      builder: (context, preset, _) {
        return MaterialApp(
          theme: AppTheme.resolve(
            preset: preset,
            brightness: Brightness.light,
          ),
          darkTheme: AppTheme.resolve(
            preset: preset,
            brightness: Brightness.dark,
          ),
          themeMode: widget.themeMode,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Container(
                  key: const ValueKey('theme-probe'),
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Column(
                    children: [
                      Text('Estado $_state'),
                      FilledButton(
                        key: const ValueKey('state-action'),
                        onPressed: () => setState(() => _state += 1),
                        child: const Text('Avanzar'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
