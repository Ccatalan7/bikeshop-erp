/// Elegir en qué parte del catálogo de un proveedor buscar una pieza.
///
/// **Qué reemplaza.** Hoy cada familia trae escritas a mano las palabras que la
/// nombran (`identity_terms`, `search_terms`) y las que la desmienten
/// (`negativeHeads`), y con eso se puntean los rótulos de los nodos. Eso
/// significa que **una familia nueva no se puede buscar hasta que alguien la
/// escriba**, proveedor por proveedor y pieza por pieza — la misma trampa que
/// tenían las specs antes de que el modelo las leyera.
///
/// La taxonomía del proveedor **ya la descubrimos y la tenemos guardada**. Con
/// eso, elegir el nodo es una tarea de lenguaje: «de estos rótulos, ¿cuáles
/// pueden contener un motor de centro sellado?». Una llamada por búsqueda, y
/// sirve para cualquier familia y cualquier proveedor sin configurar nada.
///
/// **La compuerta.** El modelo no puede inventar un nodo: sólo puede devolver
/// ids que se le mandaron, y cualquier otro se descarta. No decide si un
/// producto sirve —eso lo sigue haciendo el calce determinista sobre las filas
/// que se traigan—; sólo dice dónde mirar. Un error suyo cuesta mirar de más o
/// de menos, y la cobertura lo dice; nunca produce un «cumple» falso.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'supplier_need_portal_search.dart';
import 'supplier_spec_extraction.dart' show SupplierSpecExtractor;

/// La instrucción: los rótulos del proveedor y la pieza que se busca.
String buildSupplierTaxonomyPrompt({
  required String requestedObject,
  required List<SupplierPortalTaxonomyNode> nodes,
  required int limit,
}) {
  final catalogo = <Map<String, Object?>>[
    for (final node in nodes)
      <String, Object?>{
        'id': node.id,
        'label': node.label,
        if (node.parentLabel != null && node.parentLabel!.trim().isNotEmpty)
          'parent': node.parentLabel,
      },
  ];

  return '''
Eres un comprador de repuestos de bicicleta mirando el índice de categorías de
un proveedor. Tu tarea es decir DÓNDE buscar una pieza, no si sirve.

Pieza buscada: $requestedObject

Elige las categorías que puedan contener esa pieza, como máximo $limit, de la
más probable a la menos. Reglas:

- Devuelve SOLO ids que estén en la lista. Un id inventado se descarta.
- Una categoría cuyo rótulo nombra OTRA pieza no contiene la buscada, aunque
  se monten juntas, se vendan juntas o se usen en la misma rueda.
- Si dudas entre una categoría amplia y una específica, incluye la específica
  primero y la amplia después.
- Si ninguna categoría puede contenerla, devuelve la lista vacía.

Categorías del proveedor:
${const JsonEncoder.withIndent('  ').convert(catalogo)}

Responde SOLO este JSON, sin texto alrededor:
{"nodes":[{"id":"<id de la lista>","why":"<por qué puede contenerla, breve>"}]}
''';
}

/// Los nodos que el modelo eligió y que existen de verdad.
///
/// Se conserva el orden que dio el modelo —es su ranking— y se descarta todo lo
/// que no venga de la lista enviada. Un id repetido cuenta una vez.
List<SupplierPortalTaxonomyNode> verifySupplierTaxonomySelection({
  required List<SupplierPortalTaxonomyNode> nodes,
  required Object? response,
  required int limit,
  List<String> excludedTerms = const <String>[],
  void Function(List<String> rejected)? onRejected,
}) {
  final rejected = <String>[];
  Object? decoded = response;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      onRejected?.call(<String>['respuesta ilegible']);
      return const <SupplierPortalTaxonomyNode>[];
    }
  }
  if (decoded is! Map) {
    onRejected?.call(<String>['respuesta sin nodos']);
    return const <SupplierPortalTaxonomyNode>[];
  }

  final byId = <String, SupplierPortalTaxonomyNode>{
    for (final node in nodes) node.id: node,
  };
  final chosen = <String, SupplierPortalTaxonomyNode>{};
  for (final raw in (decoded['nodes'] as List? ?? const <Object?>[])) {
    if (raw is! Map) continue;
    final id = raw['id']?.toString().trim() ?? '';
    final node = byId[id];
    if (node == null) {
      rejected.add('nodo inexistente: «$id»');
      continue;
    }
    // **Veto con lo que la taxonomía canónica ya sabe.** Pedir cámaras y
    // recibir `NEUMATICOS RUTA` pasó de verdad el 2026-08-30: el modelo gastó
    // cuatro páginas del presupuesto en una categoría de otra pieza. Los
    // términos negativos ya existen para la familia; acá sólo se usan como
    // desmentido, no como la lista que elige.
    final rotulo = _normalizar(node.label);
    final vetado = excludedTerms
        .map(_normalizar)
        .where((term) => term.isNotEmpty)
        .any((term) => _nombraPalabra(rotulo, term));
    if (vetado) {
      rejected.add('«${node.label}» nombra otra pieza');
      continue;
    }
    chosen.putIfAbsent(id, () => node);
    if (chosen.length >= limit) break;
  }
  if (rejected.isNotEmpty) onRejected?.call(rejected);
  return List<SupplierPortalTaxonomyNode>.unmodifiable(chosen.values);
}

String _normalizar(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Si el rótulo NOMBRA esa pieza, en singular o en plural.
///
/// Un rótulo de catálogo casi siempre va en plural —`NEUMATICOS RUTA`,
/// `CAMARAS MTB`— y el término canónico en singular. Exigir la palabra exacta
/// dejaba el veto ciego justo donde se necesita; aceptar la subcadena lo haría
/// vetar `CAMARAS` por contener `cama`. El punto medio es la palabra entera con
/// su plural español.
bool _nombraPalabra(String haystack, String needle) =>
    RegExp('(^|[^a-z0-9])${RegExp.escape(needle)}(e?s)?([^a-z0-9]|\$)')
        .hasMatch(haystack);

/// Dónde buscar esta pieza en este catálogo.
///
/// [fallback] es el punteo por vocabulario de siempre. Se usa cuando no hay
/// modelo, cuando la respuesta no sirve, o cuando el modelo no eligió nada:
/// **quedarse sin buscar es peor que buscar donde decía la lista vieja.**
Future<List<SupplierPortalTaxonomyNode>> chooseSupplierTaxonomyNodes({
  required SupplierPortalCatalogTaxonomy? taxonomy,
  required String requestedObject,
  required List<SupplierPortalTaxonomyNode> fallback,
  required int limit,
  List<String> excludedTerms = const <String>[],
  SupplierSpecExtractor? extractor,
  Duration deadline = const Duration(seconds: 25),
}) async {
  final nodes = taxonomy?.nodes ?? const <SupplierPortalTaxonomyNode>[];
  if (extractor == null ||
      nodes.isEmpty ||
      limit < 1 ||
      requestedObject.trim().isEmpty) {
    return fallback;
  }

  Object? response;
  try {
    response = await extractor(
      buildSupplierTaxonomyPrompt(
        requestedObject: requestedObject.trim(),
        nodes: nodes,
        limit: limit,
      ),
    ).timeout(deadline);
  } catch (error) {
    debugPrint('🧭 elección de categorías: sin modelo ($error)');
    return fallback;
  }

  final chosen = verifySupplierTaxonomySelection(
    nodes: nodes,
    response: response,
    limit: limit,
    excludedTerms: excludedTerms,
    onRejected: (rejected) =>
        debugPrint('🧭 elección de categorías: ${rejected.join(' · ')}'),
  );
  if (chosen.isEmpty) return fallback;
  debugPrint('🧭 elección de categorías: '
      '${chosen.map((node) => node.label).join(' · ')}');
  return chosen;
}
