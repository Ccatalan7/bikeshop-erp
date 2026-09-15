import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Compuerta de ownership: el host dual O-02/O-05 (`vb_overlay_surfaces.dart`)
/// compone superficies, no las duplica.
///
/// La superficie O-02 (radio, borde y sombra F-05) tiene UN owner:
/// `VbPopoverSurface` en `vb_anchored_popover.dart`. Reintroducir aquí un
/// `DecoratedBox`/`BoxShadow` de popover paralelo fue exactamente el defecto
/// que esta prueba impide repetir (blur 28 / offset 0,10 inventados,
/// 2026-08-27). La única sombra permitida en el archivo es la de la hoja
/// O-05, cuyo chrome canónico (radio 14, handle 34×4 pill) publica la guía.
void main() {
  test('el host O-02 reutiliza VbPopoverSurface y no duplica F-05', () {
    final source =
        File('lib/shared/widgets/vb_overlay_surfaces.dart').readAsStringSync();

    expect(source.contains('VbPopoverSurface('), isTrue,
        reason: 'la superficie O-02 debe venir del owner canónico');

    final shadowCount = 'BoxShadow('.allMatches(source).length;
    expect(shadowCount, 1,
        reason: 'una sola sombra: la de la hoja O-05; la del popover es del '
            'owner VbPopoverSurface');

    expect(source.contains('blurRadius: 28'), isFalse,
        reason: 'la sombra F-05 del popover no se reinventa aquí');
  });
}
