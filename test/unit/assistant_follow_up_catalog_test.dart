import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El servidor elige QUÉ continuación ofrecer; el cliente decide qué dice.
///
/// Si el servidor ofrece un id que este cliente no conoce, el botón aparece y
/// al tocarlo no pasa NADA: no hay error, no hay mensaje, el operador toca dos
/// veces y concluye que el asistente está roto. Es la peor forma de fallar, y
/// no la cubre ninguna prueba de Deno ni de Flutter por separado porque el
/// defecto vive en la costura entre los dos.
void main() {
  test('cada opción que ofrece el servidor tiene texto en el cliente', () {
    final servidor = File('supabase/functions/_shared/ai_agent/cards.ts');
    final cliente = File(
      'lib/modules/ai_assistant/widgets/ai_chat_bubble.dart',
    );
    expect(servidor.existsSync(), isTrue, reason: servidor.path);
    expect(cliente.existsSync(), isTrue, reason: cliente.path);

    final ofrecidos =
        _idsOfrecidosComoContinuacion(servidor.readAsStringSync());
    final conocidos = _idsConocidosPorElCliente(cliente.readAsStringSync());

    expect(
      ofrecidos,
      isNotEmpty,
      reason: 'sin ids que revisar, esta prueba no cuida nada',
    );
    expect(
      ofrecidos.difference(conocidos),
      isEmpty,
      reason: 'el servidor ofrece continuaciones que el cliente no sabe enviar',
    );
  });
}

/// Ids dentro de cada tarjeta que declara `optionKind: "follow_up"`.
Set<String> _idsOfrecidosComoContinuacion(String source) {
  final ids = <String>{};
  const marca = 'optionKind: "follow_up"';
  var desde = source.indexOf(marca);
  while (desde != -1) {
    // El bloque de opciones que sigue a la familia, acotado para no arrastrar
    // ids de otras tarjetas.
    final bloque = source.substring(
      desde,
      (desde + 1400).clamp(0, source.length),
    );
    for (final match in RegExp(r'id: "([a-z0-9_]+)"').allMatches(bloque)) {
      ids.add(match.group(1)!);
    }
    desde = source.indexOf(marca, desde + marca.length);
  }
  return ids;
}

Set<String> _idsConocidosPorElCliente(String source) {
  final inicio = source.indexOf('_followUpPrompts');
  expect(inicio, isNot(-1), reason: 'el catálogo del cliente cambió de nombre');
  final fin = source.indexOf('};', inicio);
  final bloque = source.substring(inicio, fin);
  return RegExp(r"'([a-z0-9_]+)':")
      .allMatches(bloque)
      .map((match) => match.group(1)!)
      .toSet();
}
