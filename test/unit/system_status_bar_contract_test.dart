import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';

/// La barra de estado del teléfono es parte de la app, no del sistema.
///
/// El defecto que fija este contrato: la franja del reloj/wifi/batería salía
/// **blanca** encima de un header navy. Material 3 deja `statusBarColor`
/// transparente y Android la rellena con su default claro; en todo `lib/` no
/// había un solo `SystemUiOverlayStyle` que dijera otra cosa.
void main() {
  const presets = <AppearancePreset>[
    AppearancePresets.vinabike,
    AppearancePresets.midnight,
    AppearancePresets.aubergine,
    AppearancePresets.graphite,
    AppearancePresets.evergreen,
    AppearancePresets.pacific,
  ];

  test('el chrome tiñe la barra de estado en los 6 presets × 2 modos', () {
    for (final palette in AppearanceService.sidebarPalettes) {
      for (final brightness in Brightness.values) {
        final chrome = WorkspaceChromeTheme.resolve(
          palette: palette,
          brightness: brightness,
        );
        final style = chrome.systemOverlayStyle;
        final where = '${palette.code}/${brightness.name}';

        // Nunca transparente: eso es exactamente lo que dejaba la franja
        // blanca del sistema asomando encima del header.
        expect(style.statusBarColor, isNotNull, reason: '$where sin color');
        expect(style.statusBarColor!.a, 1.0, reason: '$where translúcida');
        expect(style.statusBarColor, chrome.canvas,
            reason: '$where no es el chrome de abajo');

        // El icono se decide contra el fondo real, no fijado en claro.
        final chromeIsDark = chrome.canvas.computeLuminance() < 0.35;
        expect(
          style.statusBarIconBrightness,
          chromeIsDark ? Brightness.light : Brightness.dark,
          reason: '$where iconos Android ilegibles',
        );
        // Android nombra el brillo del icono; iOS el del fondo. Opuestos.
        expect(
          style.statusBarBrightness,
          isNot(style.statusBarIconBrightness),
          reason: '$where iOS y Android no pueden coincidir',
        );
      }
    }
  });

  test('el AppBar por defecto se tiñe con SU fondo, no con el navy del shell',
      () {
    for (final preset in presets) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.resolve(preset: preset, brightness: brightness);
        final style = theme.appBarTheme.systemOverlayStyle;
        final where = '${preset.code}/${brightness.name}';

        expect(style, isNotNull, reason: '$where sin overlay style');
        expect(
          style!.statusBarColor,
          theme.appBarTheme.backgroundColor,
          reason: '$where la franja no es el AppBar que hay debajo',
        );
      }
    }
  });

  test('la regla del brillo vive en un solo sitio y se calcula, no se fija',
      () {
    // Un chrome claro tiene que dar iconos oscuros: si esto se fijara en
    // «siempre claros», un preset claro dejaría la barra ilegible.
    const claro = Color(0xFFF2F4F7);
    const oscuro = Color(0xFF0C2537);
    expect(
      vinabikeSystemOverlayStyleFor(claro).statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      vinabikeSystemOverlayStyleFor(oscuro).statusBarIconBrightness,
      Brightness.light,
    );
    expect(vinabikeSystemOverlayStyleFor(claro).statusBarColor, claro);
  });
}
