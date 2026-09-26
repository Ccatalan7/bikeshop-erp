import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';

/// Dos colores que el dueño no quiere volver a ver (2026-09-26).
///
/// El verde Material `#2E7D32` y el turquesa de Odoo `#00A09D` llegaron con el
/// primer editor del sitio: el verde era su color principal de partida y quedó
/// guardado como marca de Viñabike sin que nadie lo eligiera; el turquesa
/// estaba escrito a mano en 159 lugares del editor y de la tienda. Cada vez
/// que alguien copiaba un widget viejo, volvían. Esta guardia recorre `lib/`
/// entero: el sitio toma su color del editor, el editor el de su apariencia
/// del ERP y el ERP los roles de Design, así que ninguno de los dos tiene por
/// qué estar escrito en el código.
const _banned = <String, String>{
  '2E7D32': 'verde Material del primer editor («color moco»)',
  '00A09D': 'turquesa de Odoo del primer editor',
};

void main() {
  test('ni el verde ni el turquesa del primer editor están en lib/', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) continue;
        final upper = code.toUpperCase();
        for (final entry in _banned.entries) {
          if (upper.contains(entry.key)) {
            offenders.add('${file.path}:${i + 1} — ${entry.value}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Usa el rol del tema: colorScheme.primary en el sitio, '
          'websiteEditorAccent(context) en las herramientas del editor, '
          'VinabikeThemeRoles en el ERP.',
    );
  });

  test('un tema guardado sin colores no parte en verde', () {
    final preset =
        ThemePreset.fromJson(const {'id': 'p', 'name': 'Sin colores'});
    expect(preset.primaryColor,
        WebsiteResolvedTheme.defaultPrimaryColor.toARGB32());
    expect(
        preset.accentColor, WebsiteResolvedTheme.defaultAccentColor.toARGB32());
    // El sitio sin marca guardada actúa con el azul de «Agregar al carrito».
    expect(
      WebsiteResolvedTheme.defaultPrimaryColor,
      WebsiteResolvedTheme.defaultCommerceAccentColor,
    );
  });
}
