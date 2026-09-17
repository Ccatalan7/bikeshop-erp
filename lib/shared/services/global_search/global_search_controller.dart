import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/browser_omnibox.dart';

import 'global_search_engine.dart';
import 'global_search_entry.dart';
import 'global_search_query.dart';
import 'global_search_usage.dart';

/// El estado vivo del buscador: qué se escribió, qué se encontró y qué fila
/// está resaltada.
///
/// El índice (filas) y la superficie (pintura) son de otros. Acá vive lo único
/// que las dos necesitan compartir, y por eso es lo único que se prueba para
/// saber si el teclado se comporta.
class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({List<GlobalSearchEntry> entries = const []})
      : _entries = entries;

  List<GlobalSearchEntry> _entries;
  GlobalSearchOutcome _outcome = GlobalSearchOutcome.empty;
  GlobalSearchUsage _usage = GlobalSearchUsage.empty;
  String _text = '';
  int? _highlight;
  final Set<GlobalSearchKind> _expandedGroups = <GlobalSearchKind>{};

  String get text => _text;
  GlobalSearchOutcome get outcome => _outcome;
  GlobalSearchUsage get usage => _usage;
  List<GlobalSearchEntry> get entries => _entries;

  /// `null` es el texto libre, igual que en el omnibox del navegador: la
  /// primera ↓ resalta la primera fila y ↑ desde ahí devuelve el foco a lo
  /// escrito, sin ciclar por los extremos.
  int? get highlight => _highlight;

  bool get hasQuery => _text.trim().isNotEmpty;

  /// Hay texto suficiente para afirmar algo sobre el resultado.
  bool get hasActionableQuery => GlobalSearchQuery.parse(_text).isActionable;

  /// Las filas en el orden en que se ven, ya con los grupos expandidos.
  List<GlobalSearchResult> get visibleResults {
    final visible = <GlobalSearchResult>[];
    for (final group in _outcome.groups) {
      visible.addAll(
        _expandedGroups.contains(group.kind) ? _allOf(group) : group.results,
      );
    }
    return visible;
  }

  bool isExpanded(GlobalSearchKind kind) => _expandedGroups.contains(kind);

  List<GlobalSearchResult> resultsOf(GlobalSearchGroup group) =>
      _expandedGroups.contains(group.kind) ? _allOf(group) : group.results;

  List<GlobalSearchResult> _allOf(GlobalSearchGroup group) {
    final query = _outcome.query;
    if (query == null) return group.results;
    final full = rankGlobalSearch(
      query: query,
      entries: _entries,
      usage: _usage,
      groupLimit: group.totalCount,
    );
    for (final candidate in full.groups) {
      if (candidate.kind == group.kind) return candidate.results;
    }
    return group.results;
  }

  void replaceEntries(List<GlobalSearchEntry> entries) {
    if (identical(_entries, entries)) return;
    _entries = entries;
    _recompute(keepHighlight: true);
  }

  void updateText(String value) {
    if (_text == value) return;
    _text = value;
    // Al escribir, el resaltado deja de describir lo que hay en pantalla: se
    // invalida en vez de arrastrarse a otra fila. Es el contrato del omnibox.
    _expandedGroups.clear();
    _recompute(keepHighlight: false);
  }

  void clear() {
    if (_text.isEmpty && _outcome.isEmpty && _highlight == null) return;
    _text = '';
    _expandedGroups.clear();
    _recompute(keepHighlight: false);
  }

  void expandGroup(GlobalSearchKind kind) {
    if (!_expandedGroups.add(kind)) return;
    notifyListeners();
  }

  void moveHighlight(int delta) {
    final count = visibleResults.length;
    final next = nextOmniboxHighlight(
      current: _highlight,
      count: count,
      delta: delta,
    );
    if (next == _highlight) return;
    _highlight = next;
    notifyListeners();
  }

  GlobalSearchResult? get highlighted {
    final index = _highlight;
    if (index == null) return null;
    final visible = visibleResults;
    if (index < 0 || index >= visible.length) return null;
    return visible[index];
  }

  /// La fila que abre `Enter`: la resaltada, o la primera cuando nadie bajó
  /// todavía. Escribir y apretar Enter tiene que abrir lo obvio.
  GlobalSearchResult? get primaryTarget {
    final explicit = highlighted;
    if (explicit != null) return explicit;
    final visible = visibleResults;
    return visible.isEmpty ? null : visible.first;
  }

  void _recompute({required bool keepHighlight}) {
    final query = GlobalSearchQuery.parse(_text);
    _outcome = query.isActionable
        ? rankGlobalSearch(query: query, entries: _entries, usage: _usage)
        : GlobalSearchOutcome.empty;
    if (!keepHighlight) _highlight = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- costumbre

  static const String _usagePrefix = 'global_search_usage';
  String? _usageKey;

  /// Carga lo aprendido por **este** usuario en **este** tenant. Dos cuentas en
  /// el mismo equipo no comparten costumbres.
  Future<void> loadUsage({
    required String? userId,
    required String? tenantId,
  }) async {
    if (userId == null || tenantId == null) {
      _usageKey = null;
      _usage = GlobalSearchUsage.empty;
      return;
    }
    final key = '${_usagePrefix}_${userId}_$tenantId';
    _usageKey = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      _usage = GlobalSearchUsage.decode(prefs.getString(key))
          .pruned(now: DateTime.now());
    } catch (_) {
      _usage = GlobalSearchUsage.empty;
    }
    if (_text.isNotEmpty) _recompute(keepHighlight: true);
  }

  /// Registra la apertura **y la palabra con que se pidió**.
  ///
  /// Sin la palabra sólo se aprende qué es popular; con ella se aprende el
  /// vocabulario de este taller, que es lo que hace que la segunda vez la
  /// búsqueda acierte donde la primera no.
  Future<void> recordOpened(GlobalSearchEntry entry) async {
    _usage = _usage.recording(
      entry.id,
      now: DateTime.now(),
      query: GlobalSearchQuery.parse(_text).normalized,
    );
    final key = _usageKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, _usage.encode());
    } catch (_) {
      // Perder la costumbre de una apertura no vale una alerta: se vuelve a
      // aprender sola.
    }
  }

  /// Lo que se ofrece antes de escribir: primero lo que este usuario abre, y
  /// si todavía no abrió nada, el principio de su propio menú.
  List<GlobalSearchEntry> suggestions({int limit = 6}) {
    final now = DateTime.now();
    final byId = <String, GlobalSearchEntry>{
      for (final entry in _entries) entry.id: entry,
    };
    final used = <GlobalSearchEntry>[
      for (final id in _usage.topIds(now: now, limit: limit))
        if (byId[id] case final entry?) entry,
    ];
    if (used.length >= limit) return used;

    final seen = used.map((entry) => entry.id).toSet();
    for (final entry in _entries) {
      if (used.length >= limit) break;
      if (entry.kind != GlobalSearchKind.menu) continue;
      if (!seen.add(entry.id)) continue;
      used.add(entry);
    }
    return used;
  }
}
