import 'dart:collection';

/// A bounded, plain-text summary attached to a desktop release manifest.
///
/// The release pipeline may generate this payload with AI, but the installed
/// app treats it as untrusted data and only renders it after strict parsing.
class DesktopReleaseNotes {
  static const int currentSchemaVersion = 1;
  static const String supportedLocale = 'es-CL';
  static const int maxModules = 5;
  static const int maxItemsPerModule = 3;
  static const int maxEvidencePathsPerModule = 12;

  static const Map<String, String> supportedModuleLabels = {
    'workshop': 'Taller',
    'inventory': 'Inventario',
    'sales': 'Ventas y pagos',
    'purchases': 'Compras',
    'hr': 'Personal',
    'messaging': 'Mensajes',
    'mail': 'Correo',
    'website': 'Sitio web',
    'storage': 'Archivos',
    'accounting': 'Contabilidad',
    'settings': 'Configuración',
    'general': 'General',
  };

  final int schemaVersion;
  final String locale;
  final String source;
  final String fromCommit;
  final String toCommit;
  final String title;
  final String summary;
  final List<DesktopReleaseNotesModule> modules;

  DesktopReleaseNotes({
    required this.schemaVersion,
    required this.locale,
    required this.source,
    required this.fromCommit,
    required this.toCommit,
    required this.title,
    required this.summary,
    required List<DesktopReleaseNotesModule> modules,
  }) : modules = UnmodifiableListView(modules);

  /// Returns `null` for any absent, malformed, unsupported, or oversized
  /// payload. A bad optional summary must never block an update.
  static DesktopReleaseNotes? tryParse(
    Object? value, {
    String? expectedToCommit,
  }) {
    try {
      if (value is! Map) return null;
      final map = _stringKeyedMap(value);
      if (map == null ||
          !_hasOnlyKeys(map, const {
            'schema_version',
            'locale',
            'source',
            'from_commit',
            'to_commit',
            'title',
            'summary',
            'modules',
          })) {
        return null;
      }

      final schemaVersion = map['schema_version'];
      final locale = map['locale'];
      final source = map['source'];
      final fromCommit = map['from_commit'];
      final toCommit = map['to_commit'];
      final title = _plainText(map['title'], maxLength: 80);
      final summary = _plainText(map['summary'], maxLength: 280);
      final modulesValue = map['modules'];

      if (schemaVersion != currentSchemaVersion ||
          locale != supportedLocale ||
          (source != 'ai' && source != 'fallback') ||
          !_isCommit(fromCommit) ||
          !_isCommit(toCommit) ||
          (expectedToCommit != null && toCommit != expectedToCommit) ||
          title == null ||
          summary == null ||
          modulesValue is! List ||
          modulesValue.isEmpty ||
          modulesValue.length > maxModules) {
        return null;
      }

      final modules = <DesktopReleaseNotesModule>[];
      final seenModuleIds = <String>{};
      for (final moduleValue in modulesValue) {
        final module = DesktopReleaseNotesModule._tryParse(
          moduleValue,
          source: source,
        );
        if (module == null || !seenModuleIds.add(module.id)) return null;
        modules.add(module);
      }

      return DesktopReleaseNotes(
        schemaVersion: schemaVersion,
        locale: locale,
        source: source,
        fromCommit: fromCommit as String,
        toCommit: toCommit as String,
        title: title,
        summary: summary,
        modules: modules,
      );
    } catch (_) {
      return null;
    }
  }
}

class DesktopReleaseNotesModule {
  final String id;
  final String label;
  final List<String> items;

  /// Kept for release-audit validation and deliberately not rendered by the UI.
  final List<String> evidencePaths;

  DesktopReleaseNotesModule({
    required this.id,
    required this.label,
    required List<String> items,
    required List<String> evidencePaths,
  })  : items = UnmodifiableListView(items),
        evidencePaths = UnmodifiableListView(evidencePaths);

  static DesktopReleaseNotesModule? _tryParse(
    Object? value, {
    required String source,
  }) {
    if (value is! Map) return null;
    final map = _stringKeyedMap(value);
    if (map == null ||
        !_hasOnlyKeys(map, const {
          'id',
          'label',
          'items',
          'evidence_paths',
        })) {
      return null;
    }

    final id = map['id'];
    final label = map['label'];
    final itemsValue = map['items'];
    final evidenceValue = map['evidence_paths'];
    if (id is! String ||
        label is! String ||
        DesktopReleaseNotes.supportedModuleLabels[id] != label ||
        itemsValue is! List ||
        itemsValue.isEmpty ||
        itemsValue.length > DesktopReleaseNotes.maxItemsPerModule ||
        evidenceValue is! List ||
        (source == 'ai' && evidenceValue.isEmpty) ||
        evidenceValue.length > DesktopReleaseNotes.maxEvidencePathsPerModule) {
      return null;
    }

    final items = <String>[];
    for (final itemValue in itemsValue) {
      final item = _plainText(itemValue, maxLength: 160);
      if (item == null) return null;
      items.add(item);
    }

    final evidencePaths = <String>[];
    final seenPaths = <String>{};
    for (final pathValue in evidenceValue) {
      final evidencePath = _repoRelativePath(pathValue);
      if (evidencePath == null || !seenPaths.add(evidencePath)) return null;
      evidencePaths.add(evidencePath);
    }

    return DesktopReleaseNotesModule(
      id: id,
      label: label,
      items: items,
      evidencePaths: evidencePaths,
    );
  }
}

Map<String, dynamic>? _stringKeyedMap(Map<dynamic, dynamic> value) {
  if (value.keys.any((key) => key is! String)) return null;
  return value.cast<String, dynamic>();
}

bool _hasOnlyKeys(Map<String, dynamic> value, Set<String> allowed) =>
    value.keys.every(allowed.contains) && value.length == allowed.length;

bool _isCommit(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{40}$').hasMatch(value);

String? _plainText(Object? value, {required int maxLength}) {
  if (value is! String || value != value.trim()) return null;
  if (value.isEmpty || value.length > maxLength) return null;
  if (RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) return null;
  if (RegExp(r'https?://|www\.', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  if (value.contains('<') ||
      value.contains('>') ||
      value.contains('`') ||
      value.startsWith('- ') ||
      value.startsWith('+ ') ||
      RegExp(r'^\d+\.\s').hasMatch(value) ||
      RegExp(r'(^|\s)#{1,6}\s').hasMatch(value) ||
      RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(value) ||
      RegExp(r'(^|\s)[*_]{1,3}\S').hasMatch(value)) {
    return null;
  }
  return value;
}

String? _repoRelativePath(Object? value) {
  if (value is! String || value != value.trim()) return null;
  if (value.isEmpty || value.length > 240) return null;
  if (value.startsWith('/') ||
      value.startsWith(r'\') ||
      value.contains(r'\') ||
      value.contains('://') ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) {
    return null;
  }

  final segments = value.split('/');
  if (segments
      .any((segment) => segment.isEmpty || segment == '.' || segment == '..')) {
    return null;
  }
  return value;
}
