import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El wiki de compatibilidad (docs/wiki/compatibilidad) es el mapa del motor.
/// Una familia nueva que el motor juzga, o un campo de la ficha de la bici que
/// el motor lee, no se agrega sin nombrarlo en el wiki: así no queda como «una
/// carpeta paralela que será olvidada» (dueño, 2026-10-02). Vale igual para
/// Claude y para Codex porque corre en el gate de cada publicación.
void main() {
  final engine = File(
    'lib/modules/bikeshop/services/bike_product_compatibility_service.dart',
  ).readAsStringSync();
  final pages = Directory('docs/wiki/compatibilidad/paginas')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.md'))
      .toList();
  final wiki = pages.map((file) => file.readAsStringSync()).join('\n');
  final map = File(
    'docs/wiki/compatibilidad/paginas/modelo-vinabike.md',
  ).readAsStringSync();
  final index = File('docs/wiki/compatibilidad/index.md').readAsStringSync();

  test('every family the engine judges is named in the wiki', () {
    final families =
        RegExp(r'_assess([A-Za-z]+Family|DrivetrainKit)Compatibility\(')
            .allMatches(engine)
            .map((match) => '_assess${match.group(1)}Compatibility')
            .toSet()
          ..remove('_assessTechnicalFamilyCompatibility');
    expect(families, isNotEmpty);
    final missing = families.where((name) => !wiki.contains(name)).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Nombra cada familia en la sección «En Vinabike» de su página '
          'del wiki (docs/wiki/compatibilidad/paginas).',
    );
  });

  test('every bike field the engine reads is in the wiki map', () {
    final keys = RegExp(r"technicalValues\['([A-Za-z]+)'\]")
        .allMatches(engine)
        .map((match) => match.group(1)!)
        .toSet();
    expect(keys, isNotEmpty);
    final missing = keys.where((key) => !map.contains('`$key`')).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'Agrega el campo a la tabla de '
          'docs/wiki/compatibilidad/paginas/modelo-vinabike.md.',
    );
  });

  test('the wiki index links every page', () {
    final missing = pages
        .map((file) => file.uri.pathSegments.last)
        .where((name) => !index.contains('paginas/$name'))
        .toList()
      ..sort();
    expect(missing, isEmpty);
  });
}
