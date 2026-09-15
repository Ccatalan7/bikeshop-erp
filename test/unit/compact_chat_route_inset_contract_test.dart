import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// En compacto, el módulo de mensajería empujaba `ChatWindow` como un
/// `MaterialPageRoute` pelado: sin `Scaffold`, sin barra y sin nadie que
/// consumiera el inset superior. `ChatWindow` pinta su encabezado desde el borde
/// del viewport, así que el nombre del contacto quedaba debajo del reloj, la
/// señal y la batería.
///
/// La guía móvil lo cubre en «System chrome shares one inset owner with the
/// compact header»: un hijo a pantalla completa **fuera del shell** trae su
/// propio contrato de inset. Esto lo fija en el código, porque en un Mac no hay
/// barra de estado y la prueba visual sólo existe en un teléfono real.
void main() {
  late String routeSource;
  late String pageSource;

  setUpAll(() {
    routeSource = File(
      'lib/modules/messaging/widgets/compact_chat_route.dart',
    ).readAsStringSync();
    pageSource = File(
      'lib/modules/messaging/pages/employee_chat_page.dart',
    ).readAsStringSync();
  });

  test('la conversación a pantalla completa trae su contrato de inset', () {
    expect(routeSource, contains('AnnotatedRegion<SystemUiOverlayStyle>'));
    expect(routeSource, contains('Scaffold('));
    expect(
      routeSource,
      contains('backgroundColor: colorScheme.surface'),
      reason: 'la franja del sistema se pinta con la superficie del '
          'encabezado; si no, queda una costura de otro color arriba',
    );
    expect(routeSource, contains('top: true'));
    expect(
      routeSource,
      contains('bottom: true'),
      reason: 'ChatWindow is embedded and consumes no system inset; the full-screen host owns the gesture bar once',
    );
    expect(
      routeSource,
      contains('colorScheme.surface.computeLuminance()'),
      reason: 'la tinta de los iconos sale del mismo lienzo que pinta debajo',
    );
  });

  test('el módulo no vuelve a empujar ChatWindow sin ese contrato', () {
    expect(
      pageSource,
      isNot(contains('builder: (_) => ChatWindow(')),
      reason: 'una ruta pelada deja el encabezado bajo la barra de estado',
    );
    expect(
      RegExp(r'builder: \(_\) => CompactChatRoute\(')
          .allMatches(pageSource)
          .length,
      3,
      reason: 'las TRES entradas compactas pasan por el mismo contrato; la '
          'tercera se había quedado pelada y la cazó esta afirmación',
    );
  });

  test('ChatWindow NO consume el inset por su cuenta', () {
    final windowSource = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();
    // La misma ventana se compone embebida en el rail derecho y en la bitácora,
    // donde el shell ya consumió el inset. Si se lo comiera otra vez dejaría un
    // hueco arriba en todas esas superficies.
    expect(
      windowSource,
      isNot(contains('SafeArea(\n      top: true')),
    );
  });
}
