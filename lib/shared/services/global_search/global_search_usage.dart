import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Cuántas veces y cuándo se abrió un destino desde el buscador.
@immutable
class GlobalSearchUsageStat {
  const GlobalSearchUsageStat({required this.count, required this.lastOpened});

  final int count;
  final DateTime lastOpened;
}

/// Lo que este usuario abre, y **con qué palabra lo pide**.
///
/// Son dos aprendizajes distintos y hacen falta los dos:
///
/// - **La costumbre** (`stats`): qué destinos abre seguido. Desempata entre
///   parecidos.
/// - **El vocabulario** (`choices`): qué eligió *después de escribir tal cosa*.
///   Es lo que permite que el buscador aprenda que en este taller «taller»
///   significa el módulo de Trabajos, sin que nadie escriba esa equivalencia en
///   el código. Lo enseña el uso, no una tabla de sinónimos — que además
///   envejecería y sólo serviría para las palabras que alguien alcanzó a
///   imaginar.
///
/// No es un historial de búsquedas: guarda la palabra sólo como llave del
/// destino que se eligió con ella, y todo vence.
@immutable
class GlobalSearchUsage {
  const GlobalSearchUsage(this.stats, [this.choices = const {}]);

  static const GlobalSearchUsage empty = GlobalSearchUsage(
    <String, GlobalSearchUsageStat>{},
  );

  final Map<String, GlobalSearchUsageStat> stats;

  /// Consulta plegada → destinos elegidos con ella.
  final Map<String, Map<String, GlobalSearchUsageStat>> choices;

  /// Techo del premio por costumbre.
  ///
  /// Deliberadamente **menor** que cualquier bono de identidad: abrir mucho
  /// «Productos» no puede tapar el cliente cuyo RUT se acaba de teclear. La
  /// costumbre desempata entre parecidos, no sustituye a lo exacto.
  static const int maxBonus = 120;

  /// Techo del premio por vocabulario cuando la palabra escrita es **la misma**
  /// con la que ya se eligió ese destino.
  ///
  /// Queda por debajo del bono de identificador —un SKU tecleado manda siempre—
  /// y por encima del de nombrar, porque «con esta palabra yo abro esto» es un
  /// dato de este usuario y le gana a una coincidencia de letras. Escala con la
  /// cantidad de veces: **una sola elección no alcanza para tapar un nombre
  /// literal**, y así un clic equivocado no queda grabado en piedra.
  static const int maxChoiceBonus = 400;

  /// Lo mismo, cuando lo escrito es todavía un prefijo de aquella palabra.
  /// Es lo que hace el aprendizaje *progresivo*: enseñado «taller», ya en
  /// `tall` empieza a ofrecerlo.
  static const int maxChoicePrefixBonus = 200;

  /// Sobre este número de aperturas ya no se gana más: sirve para que un
  /// destino abierto cien veces no sea inamovible.
  static const int _countCeiling = 6;

  /// Tope de palabras aprendidas. Más que esto no mejora nada y engorda el
  /// archivo; se descartan las que ya no puntúan.
  static const int _maxLearnedQueries = 240;

  /// Una palabra de una letra no enseña nada: la escribe todo el mundo camino
  /// de otra cosa.
  static const int _minLearnedQueryLength = 2;

  int bonusFor(String id, {required DateTime now}) =>
      _scaled(stats[id], now: now, ceiling: maxBonus);

  int _scaled(
    GlobalSearchUsageStat? stat, {
    required DateTime now,
    required int ceiling,
  }) {
    if (stat == null) return 0;
    final days = now.difference(stat.lastOpened).inDays;
    final recency = switch (days) {
      < 0 => 0.0, // Un reloj que retrocedió no es una costumbre.
      <= 1 => 1.0,
      <= 7 => 0.8,
      <= 30 => 0.5,
      <= 120 => 0.25,
      _ => 0.0,
    };
    if (recency == 0) return 0;
    final capped = stat.count > _countCeiling ? _countCeiling : stat.count;
    final bonus = (ceiling * (capped / _countCeiling) * recency).round();
    return bonus > ceiling ? ceiling : bonus;
  }

  /// Cuánto pesa, para [id], haber sido elegido antes con esta consulta.
  ///
  /// Se mira la palabra exacta y también las palabras **más largas** que ya se
  /// enseñaron y que empiezan igual: mientras se escribe `tall`, lo aprendido
  /// para `taller` ya orienta.
  int choiceBonusFor(
    String id, {
    required String normalizedQuery,
    required DateTime now,
  }) {
    if (normalizedQuery.length < _minLearnedQueryLength) return 0;

    var best = 0;
    for (final learned in choices.entries) {
      final stat = learned.value[id];
      if (stat == null) continue;

      final int bonus;
      if (learned.key == normalizedQuery) {
        bonus = _scaled(stat, now: now, ceiling: maxChoiceBonus);
      } else if (learned.key.startsWith(normalizedQuery)) {
        bonus = _scaled(stat, now: now, ceiling: maxChoicePrefixBonus);
      } else {
        continue;
      }
      if (bonus > best) best = bonus;
    }
    return best;
  }

  /// Registra que, escribiendo [query], se abrió [id].
  GlobalSearchUsage recording(
    String id, {
    required DateTime now,
    String? query,
  }) {
    final previous = stats[id];
    final nextStats = Map<String, GlobalSearchUsageStat>.from(stats);
    nextStats[id] = GlobalSearchUsageStat(
      count: (previous?.count ?? 0) + 1,
      lastOpened: now,
    );

    var nextChoices = choices;
    final key = query?.trim();
    if (key != null && key.length >= _minLearnedQueryLength) {
      nextChoices = <String, Map<String, GlobalSearchUsageStat>>{
        for (final entry in choices.entries) entry.key: entry.value,
      };
      final forQuery = Map<String, GlobalSearchUsageStat>.from(
        nextChoices[key] ?? const <String, GlobalSearchUsageStat>{},
      );
      final previousChoice = forQuery[id];
      forQuery[id] = GlobalSearchUsageStat(
        count: (previousChoice?.count ?? 0) + 1,
        lastOpened: now,
      );
      nextChoices[key] = forQuery;
    }

    return GlobalSearchUsage(
      Map<String, GlobalSearchUsageStat>.unmodifiable(nextStats),
      Map<String, Map<String, GlobalSearchUsageStat>>.unmodifiable(nextChoices),
    );
  }

  /// Los destinos más usados, para la lista de antes de escribir.
  List<String> topIds({required DateTime now, int limit = 6}) {
    final ranked = stats.keys.toList()
      ..sort((left, right) {
        final byBonus =
            bonusFor(right, now: now).compareTo(bonusFor(left, now: now));
        if (byBonus != 0) return byBonus;
        return left.compareTo(right);
      });
    return ranked
        .where((id) => bonusFor(id, now: now) > 0)
        .take(limit)
        .toList(growable: false);
  }

  /// Descarta lo que ya no puntúa, para que el archivo no crezca sin fin.
  GlobalSearchUsage pruned({required DateTime now}) {
    final keptStats = <String, GlobalSearchUsageStat>{
      for (final entry in stats.entries)
        if (bonusFor(entry.key, now: now) > 0) entry.key: entry.value,
    };

    final keptChoices = <String, Map<String, GlobalSearchUsageStat>>{};
    for (final learned in choices.entries) {
      final live = <String, GlobalSearchUsageStat>{
        for (final choice in learned.value.entries)
          if (_scaled(choice.value, now: now, ceiling: maxChoiceBonus) > 0)
            choice.key: choice.value,
      };
      if (live.isNotEmpty) keptChoices[learned.key] = live;
    }

    if (keptChoices.length > _maxLearnedQueries) {
      final ordered = keptChoices.keys.toList()
        ..sort((left, right) {
          final leftSeen = _lastSeen(keptChoices[left]!);
          final rightSeen = _lastSeen(keptChoices[right]!);
          return rightSeen.compareTo(leftSeen);
        });
      final trimmed = <String, Map<String, GlobalSearchUsageStat>>{
        for (final key in ordered.take(_maxLearnedQueries))
          key: keptChoices[key]!,
      };
      keptChoices
        ..clear()
        ..addAll(trimmed);
    }

    return GlobalSearchUsage(
      Map<String, GlobalSearchUsageStat>.unmodifiable(keptStats),
      Map<String, Map<String, GlobalSearchUsageStat>>.unmodifiable(keptChoices),
    );
  }

  static DateTime _lastSeen(Map<String, GlobalSearchUsageStat> forQuery) {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final stat in forQuery.values) {
      if (stat.lastOpened.isAfter(latest)) latest = stat.lastOpened;
    }
    return latest;
  }

  String encode() => jsonEncode(<String, dynamic>{
        'v': 2,
        'd': <String, dynamic>{
          for (final entry in stats.entries)
            entry.key: _encodeStat(entry.value),
        },
        'q': <String, dynamic>{
          for (final learned in choices.entries)
            learned.key: <String, dynamic>{
              for (final choice in learned.value.entries)
                choice.key: _encodeStat(choice.value),
            },
        },
      });

  static Map<String, dynamic> _encodeStat(GlobalSearchUsageStat stat) =>
      <String, dynamic>{
        'n': stat.count,
        't': stat.lastOpened.toUtc().toIso8601String(),
      };

  static GlobalSearchUsageStat? _decodeStat(dynamic value) {
    if (value is! Map) return null;
    final count = value['n'];
    final lastOpened = DateTime.tryParse('${value['t']}');
    if (count is! int || count <= 0 || lastOpened == null) return null;
    return GlobalSearchUsageStat(count: count, lastOpened: lastOpened);
  }

  static Map<String, GlobalSearchUsageStat> _decodeStats(dynamic source) {
    if (source is! Map) return const <String, GlobalSearchUsageStat>{};
    final stats = <String, GlobalSearchUsageStat>{};
    for (final entry in source.entries) {
      final key = entry.key;
      final stat = _decodeStat(entry.value);
      if (key is String && stat != null) stats[key] = stat;
    }
    return stats;
  }

  /// Un archivo corrupto o de una versión anterior no puede romper el
  /// buscador: se vuelve a aprender, que cuesta dos clics. La versión 1 —sólo
  /// destinos, sin vocabulario— se lee igual.
  static GlobalSearchUsage decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return empty;

      if (decoded['v'] != 2) {
        return GlobalSearchUsage(
          Map<String, GlobalSearchUsageStat>.unmodifiable(
            _decodeStats(decoded),
          ),
        );
      }

      final choices = <String, Map<String, GlobalSearchUsageStat>>{};
      final rawQueries = decoded['q'];
      if (rawQueries is Map) {
        for (final learned in rawQueries.entries) {
          final key = learned.key;
          if (key is! String) continue;
          final forQuery = _decodeStats(learned.value);
          if (forQuery.isNotEmpty) {
            choices[key] = Map<String, GlobalSearchUsageStat>.unmodifiable(
              forQuery,
            );
          }
        }
      }

      return GlobalSearchUsage(
        Map<String, GlobalSearchUsageStat>.unmodifiable(
          _decodeStats(decoded['d']),
        ),
        Map<String, Map<String, GlobalSearchUsageStat>>.unmodifiable(choices),
      );
    } catch (_) {
      return empty;
    }
  }
}
