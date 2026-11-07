import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El azul claro que el dueño no quiere volver a ver en el ERP (2026-11-06):
/// «he pedido un millón de veces dejar de usar ese azul claro en todos
/// lados… se supone que ya estaba eliminado, y que no seguía hardcodeado,
/// pero cada vez que le pido algo a algún agente IA, lo vuelven a usar».
///
/// El celeste `#6FD1F6` era el acento del cromo y el principal del modo
/// oscuro del preset Viñabike. El azul Material `#1976D2` no es ese azul
/// claro: era el principal hasta el 2026-09-05 y quedaba escrito a mano en
/// varias pantallas, que ahora lo toman del tema (`VinabikeThemeRoles`,
/// `colorScheme`).
const _banned = <String, String>{
  '6FD1F6': 'celeste del cromo viejo',
  '1976D2': 'azul Material de antes del 2026-09-05',
};

/// Excepciones con dueño y fecha. Cada una se va cuando su dueño se rehace.
const _allowed = <String, String>{
  // La tienda pública es otra MaterialApp; su marca sale del editor del sitio.
  'lib/shared/themes/app_theme.dart': 'tienda pública',
  // Remuneraciones tiene su propio lenguaje visual aprobado; pendiente.
  'lib/modules/hr/payroll/theme/payroll_tokens.dart': 'Remuneraciones',
  // Inicio es del dueño: el azul del saludo y el de «Entrada por tipo» quedan
  // como él los dejó. La 1.0.50 los cambió sin que lo pidiera y tuvo que
  // devolverlos (2026-11-07).
  'lib/shared/screens/dashboard_screen.dart': 'Inicio',
  'lib/shared/widgets/strategic_dashboard_deck.dart': 'Inicio',
};

void main() {
  test('ni el celeste ni el azul Material están escritos en lib/', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !_allowed.containsKey(file.path));
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
      reason: 'Usa el rol del tema (colorScheme.primary, '
          'VinabikeThemeRoles.of(context).shell.accent, avatarA…), nunca el '
          'valor escrito.',
    );
  });
}
