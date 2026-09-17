import 'package:flutter/foundation.dart';

import '../../utils/bike_finder_search.dart';
import 'global_search_entry.dart';
import 'global_search_query.dart';
import 'global_search_usage.dart';

/// Una fila que sobrevivió al filtro, con el puntaje que la ordena.
@immutable
class GlobalSearchResult {
  const GlobalSearchResult({required this.entry, required this.score});

  final GlobalSearchEntry entry;
  final int score;
}

/// Las filas de una misma clase, ya recortadas a lo que se muestra.
@immutable
class GlobalSearchGroup {
  const GlobalSearchGroup({
    required this.kind,
    required this.results,
    required this.totalCount,
  });

  final GlobalSearchKind kind;
  final List<GlobalSearchResult> results;

  /// Cuántas había antes de recortar: es lo que hace honesto el «Ver todos».
  final int totalCount;

  bool get hasMore => totalCount > results.length;
}

/// El resultado completo de una consulta.
@immutable
class GlobalSearchOutcome {
  const GlobalSearchOutcome({
    required this.query,
    required this.groups,
    required this.flattened,
    required this.usedFuzzyPass,
  });

  static const GlobalSearchOutcome empty = GlobalSearchOutcome(
    query: null,
    groups: <GlobalSearchGroup>[],
    flattened: <GlobalSearchResult>[],
    usedFuzzyPass: false,
  );

  final GlobalSearchQuery? query;
  final List<GlobalSearchGroup> groups;

  /// La misma lista en orden de pantalla: es la que recorre el teclado, para
  /// que ↓ y el resaltado no dependan de reconstruir los grupos.
  final List<GlobalSearchResult> flattened;

  /// `true` cuando el descarte barato no encontró nada y hubo que tolerar
  /// errores de tipeo. Se expone para poder medirlo, no para mostrarlo.
  final bool usedFuzzyPass;

  bool get isEmpty => flattened.isEmpty;
}

/// Bajo esta cantidad de coincidencias literales vale la pena pagar el paso
/// tolerante a errores sobre el índice completo.
///
/// **Por qué existen dos pasos.** El puntaje relacional normaliza y compara
/// palabra por palabra con distancia de edición; sobre ~5.600 filas y por cada
/// tecla, eso se siente. El primer paso descarta con `indexOf` sobre texto ya
/// plegado y deja decenas de filas, no miles. El segundo sólo corre cuando el
/// primero no encontró nada útil —que es exactamente cuando hay un error de
/// tipeo— y ahí el costo es invisible porque no hay nada que mostrar todavía.
const int _fuzzyFallbackFloor = 6;

/// Techo por grupo en la lista. El resto se alcanza con «Ver todos», que abre
/// la lista del módulo con la misma consulta.
const int kGlobalSearchGroupLimit = 5;

/// Calce exacto del identificador completo: `FV-01035`, un SKU, un RUT.
const int _identifierExactBonus = 600;

/// El número sin su prefijo: `1035` encuentra `FV-01035`.
const int _documentNumberBonus = 400;

/// El prefijo tecleado contradice al del documento (`fv 1035` sobre `PG-01035`).
const int _documentPrefixMismatchPenalty = -260;

/// Se pidió **hacer** algo y esta fila lo hace.
const int _createIntentBonus = 250;

/// Lo tecleado **nombra** el título: cada palabra escrita es una palabra suya.
///
/// Nombrar algo no es parecerse a ello. `pos` nombra el módulo **POS**;
/// `Postiza` apenas empieza igual. `plan de cuentas` nombra `Plan de cuentas`.
/// Es la señal más fuerte que existe por debajo de un identificador, y por eso
/// pesa más que cualquier parecido parcial.
///
/// **Causa medida (2026-09-17, reportada por el dueño):** `pos` contestaba
/// postizas antes que el módulo. El defecto de fondo estaba en el puntaje
/// compartido —un `contains` sobre el valor completo cortaba antes de mirar las
/// palabras, así que una palabra escrita entera valía *menos* que ser el
/// principio de otra más larga— y se corrigió ahí, para todo el ERP. Este bono
/// es la otra mitad: hace explícito que nombrar gana.
const int _exactTitleWordBonus = 260;

/// Lo tecleado va camino de nombrar un **destino**, y todavía no lo termina.
///
/// Se aplica sólo a menús y acciones, y la razón no es preferencia: los
/// destinos son un conjunto **cerrado, corto y conocido** —cerca de cien, los
/// del propio menú de ese usuario— mientras que los registros son miles y
/// abiertos. Cuando lo escrito es el principio de una palabra del nombre de un
/// destino, la probabilidad de que el operador esté nombrando ese destino es
/// mucho mayor que la de que quisiera uno cualquiera de los cientos de
/// registros que empiezan igual. `vent` ofrece `Ventas` mientras se sigue
/// escribiendo, sin esconder los productos que empiezan con «vent».
///
/// Queda por debajo del bono de nombrar entero y muy por debajo del de
/// identificador, así que jamás tapa un SKU, un RUT ni un número de documento.
const int _destinationPrefixBonus = 150;

/// Lo tecleado nombra un **módulo**, y ésta es su puerta de entrada.
///
/// **Por qué existe, en vez de una equivalencia escrita a mano.** El dueño
/// piensa el módulo de Trabajos como «el taller», y pidió expresamente que eso
/// no se resolviera cableando `taller → trabajos`. No hace falta: el modelo de
/// navegación ya dice que Trabajos es la primera pantalla del módulo Taller, y
/// nombrar un módulo para aterrizar en su puerta de entrada es lo que cualquiera
/// espera. La misma regla da `ventas → Facturas de venta`,
/// `inventario → Productos` y `contabilidad → Plan de cuentas`, y sigue el orden
/// que ese usuario le haya dado a su propio menú.
const int _moduleFrontDoorBonus = 180;

/// Lo tecleado nombra el módulo, y ésta es otra de sus pantallas. Agrupa al
/// resto del módulo bajo su puerta de entrada en vez de dispersarlo.
const int _moduleMemberBonus = 60;

/// Nadie pidió crear nada.
///
/// **Causa medida:** `clientes` contestaba `Nuevo cliente` antes que
/// `Lista de clientes`, porque el módulo al que pertenece la acción —
/// «Clientes»— calza la frase completa y ese calce pesa más que el del título.
/// Ordenar por parecido de texto no distingue *ir* de *crear*; la que distingue
/// es la intención, y sin verbo no hay intención de crear. Abrir la lista es
/// recuperable en un clic; crear un registro en blanco ensucia la base.
const int _unrequestedCreatePenalty = -140;

/// Ordena el índice contra lo que se acaba de teclear.
///
/// Es una función pura: mismas filas y misma consulta dan siempre el mismo
/// orden. Los empates se rompen por clase, después por lo más reciente y al
/// final por id, de modo que la lista no se reordena sola entre dos teclas.
GlobalSearchOutcome rankGlobalSearch({
  required GlobalSearchQuery query,
  required List<GlobalSearchEntry> entries,
  GlobalSearchUsage usage = GlobalSearchUsage.empty,
  DateTime? now,
  int groupLimit = kGlobalSearchGroupLimit,
}) {
  if (!query.isActionable) return GlobalSearchOutcome.empty;

  final tokens = query.tokens;
  var usedFuzzyPass = false;

  var candidates = <GlobalSearchEntry>[];
  for (final entry in entries) {
    if (_containsEveryToken(entry.haystack, tokens)) candidates.add(entry);
  }
  if (candidates.length < _fuzzyFallbackFloor) {
    usedFuzzyPass = true;
    candidates = entries;
  }

  final resolvedNow = now ?? DateTime.now();
  final scored = <GlobalSearchResult>[];
  for (final entry in candidates) {
    final score = _scoreEntry(
      query: query,
      entry: entry,
      usage: usage,
      now: resolvedNow,
    );
    if (score > 0) scored.add(GlobalSearchResult(entry: entry, score: score));
  }

  scored.sort(_compareResults);

  final byKind = <GlobalSearchKind, List<GlobalSearchResult>>{};
  for (final result in scored) {
    byKind
        .putIfAbsent(result.entry.kind, () => <GlobalSearchResult>[])
        .add(result);
  }

  // Un grupo vale lo que vale su mejor fila: si el mejor cliente le gana al
  // mejor menú, «Clientes» va arriba. Agrupar sin reordenar los grupos es lo
  // que hace que un buscador conteste con la sección equivocada primero.
  final groups = byKind.entries
      .map(
        (bucket) => GlobalSearchGroup(
          kind: bucket.key,
          results: bucket.value.take(groupLimit).toList(growable: false),
          totalCount: bucket.value.length,
        ),
      )
      .toList()
    ..sort((left, right) {
      final byScore =
          right.results.first.score.compareTo(left.results.first.score);
      if (byScore != 0) return byScore;
      return left.kind.index.compareTo(right.kind.index);
    });

  final flattened = <GlobalSearchResult>[
    for (final group in groups) ...group.results,
  ];

  return GlobalSearchOutcome(
    query: query,
    groups: List<GlobalSearchGroup>.unmodifiable(groups),
    flattened: List<GlobalSearchResult>.unmodifiable(flattened),
    usedFuzzyPass: usedFuzzyPass,
  );
}

bool _containsEveryToken(String haystack, List<String> tokens) {
  for (final token in tokens) {
    if (!haystack.contains(token)) return false;
  }
  return true;
}

int _scoreEntry({
  required GlobalSearchQuery query,
  required GlobalSearchEntry entry,
  required GlobalSearchUsage usage,
  required DateTime now,
}) {
  var score = bikeFinderRelationalSearchScore(
    query: query.normalized,
    fields: entry.fields,
  );

  // Pedir «hacer una factura» no se parece literalmente a «Nueva factura»: el
  // verbo sobra y el sustantivo es lo único que nombra el destino.
  if (entry.kind == GlobalSearchKind.action) {
    final createNoun = query.createNoun;
    if (createNoun != null) {
      final nounScore = bikeFinderRelationalSearchScore(
        query: createNoun,
        fields: entry.fields,
      );
      if (nounScore > score) score = nounScore;
    }
    if (score > 0) {
      score += query.looksLikeCreate
          ? _createIntentBonus
          : _unrequestedCreatePenalty;
    }
  }

  // **Una señal, un premio.** Los bonos son excluyentes y en este orden porque
  // describen la misma evidencia con distinta precisión: nombrar la pantalla es
  // más específico que nombrar su módulo, y eso más que ir camino de nombrarla.
  // Sumarlos contaba dos veces la misma palabra — con `pos`, que es a la vez el
  // título y el módulo, eso inflaba el puntaje hasta volver inalcanzable
  // cualquier otra cosa, incluido lo que el propio usuario hubiera enseñado.
  final isDestination = _isDestination(entry.kind);
  if (_namesTitle(query, entry)) {
    score += _exactTitleWordBonus;
  } else if (isDestination && _namesModule(query, entry)) {
    score +=
        entry.isModuleFrontDoor ? _moduleFrontDoorBonus : _moduleMemberBonus;
  } else if (isDestination && _prefixesTitle(query, entry)) {
    score += _destinationPrefixBonus;
  }

  final identifier = entry.normalizedIdentifier;
  if (identifier != null && identifier.isNotEmpty) {
    final compactQuery = query.normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compactQuery == identifier) {
      score += _identifierExactBonus;
    } else {
      final documentNumber = query.documentNumber;
      if (documentNumber != null) {
        final entryNumber = _trailingNumber(identifier);
        if (entryNumber == documentNumber) {
          final typedPrefix = query.documentPrefix;
          final entryPrefix = _leadingLetters(identifier);
          if (typedPrefix == null || typedPrefix == entryPrefix) {
            // `1035` sin prefijo: el operador dice el número que recuerda y el
            // sistema le muestra los documentos que lo llevan, de cualquier
            // familia. El prefijo tecleado sólo sirve para descartar.
            score += _documentNumberBonus;
          } else {
            score += _documentPrefixMismatchPenalty;
          }
        }
      }
    }
  }

  if (score <= 0) return 0;
  return score +
      usage.bonusFor(entry.id, now: now) +
      usage.choiceBonusFor(
        entry.id,
        normalizedQuery: query.normalized,
        now: now,
      );
}

/// Cada palabra escrita nombra al módulo de este destino.
bool _namesModule(GlobalSearchQuery query, GlobalSearchEntry entry) {
  if (query.tokens.isEmpty || entry.moduleWords.isEmpty) return false;
  for (final token in query.tokens) {
    if (!entry.moduleWords.contains(token)) return false;
  }
  return true;
}

bool _isDestination(GlobalSearchKind kind) =>
    kind == GlobalSearchKind.menu || kind == GlobalSearchKind.action;

/// Cada palabra escrita es una palabra del título.
bool _namesTitle(GlobalSearchQuery query, GlobalSearchEntry entry) {
  if (query.tokens.isEmpty || entry.titleWords.isEmpty) return false;
  for (final token in query.tokens) {
    if (!entry.titleWords.contains(token)) return false;
  }
  return true;
}

/// Cada palabra escrita es el principio de alguna palabra del título.
bool _prefixesTitle(GlobalSearchQuery query, GlobalSearchEntry entry) {
  if (query.tokens.isEmpty || entry.titleWords.isEmpty) return false;
  for (final token in query.tokens) {
    if (token.length < 2) return false;
    var matched = false;
    for (final word in entry.titleWords) {
      if (word.startsWith(token)) {
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}

int? _trailingNumber(String compactIdentifier) {
  final match = RegExp(r'(\d+)$').firstMatch(compactIdentifier);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

String? _leadingLetters(String compactIdentifier) {
  final match = RegExp(r'^([a-z]+)').firstMatch(compactIdentifier);
  return match?.group(1);
}

int _compareResults(GlobalSearchResult left, GlobalSearchResult right) {
  final byScore = right.score.compareTo(left.score);
  if (byScore != 0) return byScore;

  final byKind = left.entry.kind.index.compareTo(right.entry.kind.index);
  if (byKind != 0) return byKind;

  final leftUpdated = left.entry.updatedAt;
  final rightUpdated = right.entry.updatedAt;
  if (leftUpdated != null && rightUpdated != null) {
    final byRecency = rightUpdated.compareTo(leftUpdated);
    if (byRecency != 0) return byRecency;
  } else if (leftUpdated != null) {
    return -1;
  } else if (rightUpdated != null) {
    return 1;
  }

  return left.entry.id.compareTo(right.entry.id);
}
