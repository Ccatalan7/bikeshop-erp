import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que va sobre el navy del drawer tiene que decir de qué color va.
///
/// **El defecto que fija este contrato.** Los resultados del buscador y el pie
/// del drawer montaban `ListTile` sin color. Medido en la app real, el título
/// salía con tinta `#10243A` —el `onSurface` del tema **claro**— sobre el navy
/// `#0C2537`: **1,03:1 de contraste**, invisible. Los iconos sí se veían, así
/// que parecía que el buscador no encontraba nada cuando en realidad filtraba
/// bien. Tras atar la tinta al chrome: **15,26:1** el título y **9,32:1** el
/// subtítulo, medidos sobre la misma captura.
///
/// **Por qué este guard es de código y no de render.** La fuga no se reproduce
/// en el entorno de test: montado con el mismo `sidebarTheme`, un `ListTile`
/// sin color resuelve bien y da 15:1. Un test de contraste renderizado pasaría
/// igual con el defecto puesto, así que sería un guard que no muerde. Lo que sí
/// es verificable de forma determinista es la causa: **un `ListTile` del drawer
/// que no declara su tinta**. Eso es lo que se exige acá.
void main() {
  test('todo ListTile del drawer compacto declara su tinta contra el chrome',
      () {
    final source =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();

    final classStart = source.indexOf('class _AppDrawerState');
    expect(classStart, greaterThan(0),
        reason: 'no se encontró el estado del drawer compacto');

    // La hoja de reordenar se abre a propósito CON EL CONTEXTO DE LA APP, por
    // encima del Theme cromático del drawer, para que el modal no salga navy.
    // Sus filas van sobre superficie clara: atarlas al chrome sería el mismo
    // defecto al revés, así que quedan fuera del guard.
    final sheetStart = source.indexOf('void _showReorderSheet');
    expect(sheetStart, greaterThan(classStart));
    final sheetEnd = source.indexOf('\n  Widget ', sheetStart);
    var drawerSource =
        source.substring(classStart, sheetStart) + source.substring(sheetEnd);

    // Misma razón para la hoja que elige el destino de un espacio nuevo: se
    // muestra como modal sobre el contexto de la app, no sobre el navy del
    // drawer. Declararle la tinta del chrome la haría ilegible sobre la
    // superficie clara de la hoja.
    final launcherStart = drawerSource.indexOf(
      'Future<void> _openCompactWorkspaceLauncher',
    );
    expect(launcherStart, greaterThan(0),
        reason: 'la hoja de espacios nuevos dejó de existir o cambió de nombre');
    final launcherEnd = drawerSource.indexOf('\n  Widget ', launcherStart);
    expect(launcherEnd, greaterThan(launcherStart));
    drawerSource = drawerSource.substring(0, launcherStart) +
        drawerSource.substring(launcherEnd);

    final offenders = <String>[];
    for (final match in RegExp(r'ListTile\(').allMatches(drawerSource)) {
      final body = _balancedCall(drawerSource, match.end - 1);
      if (body == null) continue;
      // Vale cualquiera de las tres formas de decirlo: el color del tile, el
      // estilo del título del tile, o el estilo del propio Text.
      final declaresInk = body.contains('textColor:') ||
          body.contains('titleTextStyle:') ||
          RegExp(r'title:\s*Text\([^;]*?style:', dotAll: true).hasMatch(body);
      if (!declaresInk) {
        final title = RegExp(r"title:\s*(?:const\s*)?Text\(\s*'([^']*)'")
                .firstMatch(body)
                ?.group(1) ??
            body.substring(0, math.min(60, body.length)).replaceAll('\n', ' ');
        offenders.add(title);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'estos ListTile del drawer van sobre el navy del chrome y no '
          'declaran tinta, así que heredan la del tema de la app y '
          'desaparecen: $offenders',
    );
  });
}

/// Devuelve el cuerpo de la llamada que abre en [openParen], equilibrando
/// paréntesis. Sin esto, un `ListTile` anidado se mide contra el paréntesis
/// equivocado y el guard miente.
String? _balancedCall(String source, int openParen) {
  var depth = 0;
  for (var i = openParen; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen + 1, i);
    }
  }
  return null;
}
