import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato del `stop` de `scripts/dev/native_session.sh`.
///
/// **Por qué es un guard de código y no de ciclo de vida:** probar el apagado
/// de verdad exigiría levantar un `flutter run` real dentro del arnés de
/// pruebas, que tarda minutos y pelea por el mismo checkout que la sesión
/// canónica. Lo que sí es determinista es la **forma** del comando, y es donde
/// estuvo el defecto: el 2026-08-01 `stop` era una sola línea,
/// `screen -S <s> -X quit`, que mata screen y deja `login → flutter → frontend`
/// colgando de `init`. Ocurrió dos veces en una jornada.
void main() {
  final script = File('scripts/dev/native_session.sh');

  test('el script existe y tiene el bit ejecutable del dueño', () {
    expect(script.existsSync(), isTrue);
    // `existsSync` no dice nada sobre poder ejecutarlo, y el nombre del test
    // prometía las dos cosas. 0x40 = 0o100 = ejecución del dueño.
    expect(
      script.statSync().mode & 0x40,
      isNonZero,
      reason: 'sin el bit ejecutable, `native_session.sh stop` falla al '
          'invocarse directamente y el owner deja de ser el owner',
    );
  });

  test('la sesión canónica usa el gateway moderno salvo rollback explícito',
      () {
    final body = script.readAsStringSync();
    expect(
      body,
      contains(r'${NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED:-true}'),
      reason: 'un flag ausente no puede degradar silenciosamente al asistente '
          'legado durante una sesión canónica',
    );
    expect(
      body,
      contains('--dart-define=AI_AGENT_GATEWAY_ENABLED=true'),
    );
    expect(
      body,
      contains('--dart-define=AI_AGENT_GATEWAY_ENABLED=false'),
      reason: 'el rollback debe quedar explícito en los argumentos del proceso',
    );
    expect(body, contains('Vinabike ERP Supabase publishable key'));
    expect(body, contains('El gateway IA requiere la publishable key'));
    expect(
      body.indexOf('El gateway IA requiere la publishable key'),
      lessThan(body.indexOf('\ncase "\${1:-}" in')),
      reason: 'la sesión debe fallar antes de entrar a la rama start y compilar',
    );
  });

  test('stop captura TODOS los hijos directos de screen, no sólo el primero',
      () {
    final body = _stopBranch(script.readAsStringSync());
    // `pgrep -P <screen> | head -1` deja fuera cualquier ventana adicional, y
    // sus descendientes quedan huérfanos igual que antes del arreglo.
    expect(
      RegExp(r'pgrep\s+-P\s+"\$screen_pid"[^\n]*head').hasMatch(body),
      isFalse,
      reason: 'quedarse con el primer hijo reintroduce el defecto',
    );
    expect(body, contains(r'for root in $(pgrep -P "$screen_pid"'));
  });

  test('stop falla cerrado si no puede resolver la screen o su árbol', () {
    final body = _stopBranch(script.readAsStringSync());
    // Dos salidas de error ANTES de tocar screen: sin pid y sin árbol.
    final guards = RegExp('exit 1').allMatches(body).length;
    expect(guards, greaterThanOrEqualTo(3),
        reason: 'sin pid, sin árbol y con sobrevivientes: los tres fallan');
    final noPid = body.indexOf(r'if [ -z "$screen_pid" ]');
    final quit = body.indexOf('-X quit');
    expect(noPid, greaterThanOrEqualTo(0));
    expect(noPid, lessThan(quit),
        reason: 'la comprobación va antes de cerrar nada');
  });

  test('stop captura el árbol antes de cerrar screen, no después', () {
    final body = _stopBranch(script.readAsStringSync());

    final capture = body.indexOf('collect_tree');
    final quit = body.indexOf('-X quit');
    expect(capture, greaterThanOrEqualTo(0),
        reason: 'stop debe capturar el árbol de descendientes');
    expect(quit, greaterThanOrEqualTo(0));
    expect(
      capture,
      lessThan(quit),
      reason: 'una vez que screen muere ya no se sabe qué descendientes eran '
          'suyos: capturar después obliga a adivinar por patrón',
    );
  });

  test('stop intenta primero la salida grácil de flutter run', () {
    final body = _stopBranch(script.readAsStringSync());
    expect(body, contains("-X stuff 'q'"),
        reason: '`q` cierra la app y libera el VM service en orden');
    final graceful = body.indexOf("stuff 'q'");
    final force = body.indexOf('kill ');
    expect(graceful, lessThan(force),
        reason: 'primero se pide salir, después se termina');
  });

  test('stop verifica que no quede descendiente y lo dice si queda', () {
    final body = _stopBranch(script.readAsStringSync());
    expect(body, contains('leftovers'));
    expect(body, contains('exit 1'),
        reason: 'un stop que informa éxito sin comprobarlo es lo que produjo '
            'los árboles huérfanos');
  });

  test('stop nunca termina por patrón', () {
    final body = _stopBranch(script.readAsStringSync());
    expect(body.contains('pkill'), isFalse);
    expect(body.contains('killall'), isFalse);
    // `pgrep -P <pid>` es por padre exacto, que es lo correcto; `pgrep -f` es
    // por patrón y alcanzaría la sesión de otra persona.
    expect(RegExp(r'pgrep\s+-f').hasMatch(body), isFalse);
  });
}

/// Aísla la rama `stop)` del `case` **y le quita los comentarios**.
///
/// Sin quitarlos, un `indexOf('-X quit')` engancha la prosa que explica el
/// defecto en vez del comando, y el test mide el comentario. Pasó en la primera
/// versión de este archivo: es la misma trampa que buscar una cadena sin
/// comprobar cuál de sus apariciones encontraste.
String _stopBranch(String source) {
  final start = source.indexOf('\n  stop)');
  expect(start, greaterThanOrEqualTo(0), reason: 'no existe la rama stop)');
  final end = source.indexOf('\n    ;;', start);
  expect(end, greaterThan(start));
  return source
      .substring(start, end)
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
}
