import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **La barra de estado de iOS es VISIBLE, y su contraste lo decide la UI.**
///
/// Defecto reproducido el 2026-08-03 en un iPhone 17 Pro del simulador:
/// `ios/Runner/Info.plist` declaraba `UIStatusBarHidden = true`, así que la app
/// **no dibujaba reloj, wifi ni batería**. La misma captura sobre la pantalla
/// de inicio del sistema sí los mostraba, lo que descarta un artefacto de
/// captura: los ocultaba la app.
///
/// Importa más allá de la estética: `6a` compone el cromo móvil como
/// `status 47 + nav 56 + alcance 48 = 151` **con la barra de estado dentro del
/// header**. Con la barra oculta esa banda de 47 no existe y el contrato de
/// `5l` no se puede cumplir en iPhone.
///
/// Se prueba el **plist**, que es el dueño real, y no una compensación en un
/// widget: si alguien vuelve a esconderla, esto se pone rojo aunque la UI
/// «parezca» bien en macOS, donde este archivo ni siquiera participa.
void main() {
  late String plist;

  setUpAll(() {
    final file = File('ios/Runner/Info.plist');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'se ejecuta desde la raíz del repo',
    );
    plist = file.readAsStringSync();
  });

  /// Devuelve el valor booleano declarado para [key] en el plist.
  ///
  /// Se lee por posición —`<key>` y el primer `<true/>`/`<false/>` que le
  /// sigue— porque es exactamente como lo interpreta iOS.
  bool? boolFor(String key) {
    final index = plist.indexOf('<key>$key</key>');
    if (index < 0) return null;
    final rest = plist.substring(index + '<key>$key</key>'.length);
    final trueAt = rest.indexOf('<true/>');
    final falseAt = rest.indexOf('<false/>');
    if (trueAt < 0 && falseAt < 0) return null;
    if (falseAt < 0) return true;
    if (trueAt < 0) return false;
    return trueAt < falseAt;
  }

  test('la barra de estado NO se oculta', () {
    final hidden = boolFor('UIStatusBarHidden');
    expect(
      hidden,
      isNot(isTrue),
      reason: 'con la barra oculta el iPhone pierde la banda de 47 de `6a`, '
          'y el operador se queda sin reloj, wifi ni batería',
    );
  });

  test('el contraste lo decide el view controller, no un valor congelado', () {
    expect(
      boolFor('UIViewControllerBasedStatusBarAppearance'),
      isTrue,
      reason: 'esta app tiene pantallas claras y un header navy: ningún estilo '
          'global sirve para las dos, así que lo pide cada pantalla',
    );
  });

  test('la clave existe de forma explícita, no por omisión', () {
    // El default de iOS ya es «no oculta», pero dejarlo implícito es cómo
    // volvió a aparecer la vez pasada: alguien agrega la clave y nadie nota
    // que cambió el cromo. Declarada, este contrato la vigila.
    expect(plist.contains('<key>UIStatusBarHidden</key>'), isTrue);
  });
}
