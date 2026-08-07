import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La barra del navegador se recompone bajo 900px, no se encoge.
///
/// **El defecto que fija este contrato.** En un teléfono de 420px la barra de
/// escritorio entraba entera —panel, atrás, adelante, recargar, inicio,
/// dirección, marcador, menú y abrir-afuera— y la dirección quedaba reducida a
/// un candado de unos 40px: ilegible, intocable y sin forma de saber en qué
/// sitio estabas. Encoger la composición de escritorio hasta que «cabe» es
/// justamente lo que la guía móvil llama anti-patrón.
void main() {
  final source =
      File('lib/shared/widgets/webview_module_page.dart').readAsStringSync();

  test('compacto conserva sólo atrás, dirección y menú en la barra', () {
    // La frontera es la del resto del shell; no se inventa otra aquí.
    expect(source, contains('ResponsiveViewport.usesCompactShell(context)'));
    expect(source, contains('final compactBrowserChrome'));

    // Adelante, recargar, inicio, marcador y abrir-afuera salen de la fila.
    for (final control in [
      "tooltip: 'Adelante'",
      "tooltip: 'Recargar'",
      "tooltip: 'Inicio'",
      "tooltip: 'Abrir en navegador externo'",
    ]) {
      final index = source.indexOf(control);
      expect(index, greaterThan(0), reason: 'desapareció $control');
      final preceding = source.substring(0, index);
      expect(
        preceding.lastIndexOf('if (!compactBrowserChrome)'),
        greaterThan(preceding.lastIndexOf("tooltip: 'Atrás'")),
        reason: '$control debe quedar fuera de la barra compacta',
      );
    }
  });

  test('lo que sale de la barra reaparece en el menú, no se pierde', () {
    for (final action in [
      '_BrowserMenuAction.reload',
      '_BrowserMenuAction.forward',
      '_BrowserMenuAction.home',
      '_BrowserMenuAction.toggleBookmark',
    ]) {
      expect(source, contains('case $action:'),
          reason: '$action debe estar manejada');
      expect(source, contains('value: $action'),
          reason: '$action debe ofrecerse en el menú');
    }
    // Y sólo se ofrecen en compacto: en escritorio siguen siendo botones.
    final menuStart = source.indexOf('itemBuilder: (context) => [');
    expect(menuStart, greaterThan(0));
    expect(
      source.substring(menuStart, menuStart + 600),
      contains('if (compactBrowserChrome)'),
    );
  });

  test('el control que sobrevive en compacto usa un objetivo de 48', () {
    final backIndex = source.indexOf("tooltip: 'Atrás'");
    expect(backIndex, greaterThan(0));
    final block = source.substring(backIndex, backIndex + 320);
    expect(block, contains('compactBrowserChrome ? 48 : 36'));
  });
}
