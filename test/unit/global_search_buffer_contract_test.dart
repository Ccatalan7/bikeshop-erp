import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El campo del buscador nunca usa el buffer del atajo como su controlador.
///
/// **Causa medida (2026-09-30, reportada por el dueño: «funciona con 2
/// búsquedas, después ya no»).** `GlobalSearchShortcut` guarda las teclas de
/// los 200 ms de entrada en su propio buffer, y el panel lo usaba como el
/// controlador de su `TextField`. Al cerrar, el atajo vaciaba ese buffer con el
/// campo todavía montado durante la salida, y en macOS el primer respondedor
/// pasaba a ser la **ventana**: desde ahí ninguna tecla llegaba a Flutter —ni
/// al atajo, ni a ningún campo— hasta hacer clic.
///
/// Un widget test no puede ver al respondedor nativo, así que la prueba real
/// se hizo en la app con accesibilidad: con el buffer compartido el foco nativo
/// quedaba en `AXWindow` desde el primer cierre; con el campo dueño de su texto
/// quedó en `AXGroup` (la vista) en seis ciclos seguidos, y cinco búsquedas que
/// abren su resultado funcionaron una tras otra. Esta prueba impide volver a
/// conectar el campo al buffer.
void main() {
  final source = File(
    'lib/shared/widgets/global_search/global_search_overlay.dart',
  ).readAsStringSync();

  test('el campo del panel tiene su propio controlador', () {
    expect(
      RegExp(r'_text\s*=\s*widget\.sharedText').hasMatch(source),
      isFalse,
      reason: 'El buffer del atajo no puede ser el controlador del campo: '
          'vaciarlo al cerrar deja a macOS sin primer respondedor.',
    );
    expect(
      RegExp(r'_text\s*=\s*TextEditingController').hasMatch(source),
      isTrue,
    );
  });

  test('las teclas del buffer se copian mientras el campo entra', () {
    expect(source, contains('widget.sharedText?.addListener(_adoptBufferedKeys)'));
    expect(
      source,
      contains('widget.sharedText?.removeListener(_adoptBufferedKeys)'),
    );
    // Ya con el foco en el campo, las teclas llegan solas: copiar el buffer
    // encima pisaría lo que el operador escribió en el campo.
    expect(source, contains('if (_fieldFocus.hasFocus'));
  });

  test('el panel destruye su propio texto, nunca el buffer prestado', () {
    expect(source, contains('_text.dispose();'));
    expect(source, isNot(contains('_ownsText')));
  });
}
