import 'package:flutter/widgets.dart';

import 'website_block_registry.dart';
import 'website_block_type.dart';

/// Where a new block lands, expressed the way the operator states it.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t11 frame **11a** — `Posición` is a
/// two-option control against one named block, decided **before** inserting:
/// *"La posición es parte de la tarea y es editable antes de insertar; no se
/// descubre después."*
enum WebsiteBlockInsertSide {
  before('Antes de'),
  after('Después de');

  const WebsiteBlockInsertSide(this.label);

  /// The exact word t11a uses.
  final String label;
}

/// The gap an insert affordance speaks for.
///
/// A gap is named by the block it is anchored to plus a side, never by a bare
/// number: `Después de Carrusel` is checkable by the operator, `atIndex: 3` is
/// not. Both sides resolve to a real, *different* index, so flipping the
/// control actually moves the insertion.
@immutable
class WebsiteBlockInsertionAnchor {
  const WebsiteBlockInsertionAnchor({
    required this.anchorIndex,
    required this.anchorTitle,
    required this.initialSide,
  });

  /// Position of the anchor block in the page's own block order.
  final int anchorIndex;

  /// The anchor block's registry title — what the operator sees.
  final String anchorTitle;

  /// The side the affordance was born on: the gap above a block preselects
  /// [WebsiteBlockInsertSide.before], the gap below it preselects `after`.
  final WebsiteBlockInsertSide initialSide;

  /// The canonical `atIndex` for [side].
  int indexFor(WebsiteBlockInsertSide side) =>
      side == WebsiteBlockInsertSide.before ? anchorIndex : anchorIndex + 1;
}

/// One insertable family, as the operator meets it.
@immutable
class WebsiteBlockCatalogEntry {
  const WebsiteBlockCatalogEntry({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    required this.tags,
    required this.isInsertable,
    this.unavailableReason,
  });

  final WebsiteBlockType type;
  final String title;
  final String description;
  final IconData icon;
  final String category;
  final List<String> tags;

  /// Whether choosing this row may insert a block right now.
  final bool isInsertable;

  /// Why it cannot, in one line. `O-01`: an unavailable entry is shown dimmed
  /// with its reason, never hidden — hiding it turns a rule into a mystery.
  final String? unavailableReason;

  /// The stable identity every surface stores and every test asserts on. It is
  /// the persisted `block_type`, not a display string.
  String get id => type.name;

  /// Everything a search should be able to reach.
  String get searchText => <String>[
        title,
        type.name,
        category,
        description,
        ...tags,
      ].join(' ').toLowerCase();

  /// Case- and accent-insensitive containment. A query of "catalogo" must find
  /// "Catálogo": the operator types on a phone keyboard, not in a database.
  bool matches(String query) {
    final needle = WebsiteBlockCatalog.normalize(query);
    if (needle.isEmpty) return true;
    return WebsiteBlockCatalog.normalize(searchText).contains(needle);
  }
}

/// The one catalog of insertable blocks, derived from
/// [WebsiteBlockRegistry].
///
/// Design source: `Website Builder Responsive Authoring` t11 frame **11a**.
///
/// Before this owner the same list was built three times — the editor panel's
/// insert tab, [AddBlockDialog] and (in this round) the phone sheet — each with
/// its own filter, its own idea of which families exist and its own silent
/// exclusion of the footer. Three lists are three chances for a registered
/// family to disappear from one surface only.
///
/// Canvas *elements* are deliberately NOT here. They are not page blocks: they
/// are placed inside a selected Canvas block and follow a different command.
abstract final class WebsiteBlockCatalog {
  /// t11a · the first chip, always selected on open.
  static const String allCategory = 'Todos';

  /// The order the editor has always shown, kept so the compact sheet and the
  /// desktop tab group the same way. Unknown categories are appended in
  /// registry order rather than dropped.
  static const List<String> categoryOrder = <String>[
    'Estructura',
    'Elementos',
    'Contenido',
    'Media',
    'Social',
    'Conversión',
    'Especial',
  ];

  /// Families the page may contain at most once.
  ///
  /// The footer is the only one today: it is the site's closing chrome, not a
  /// section an operator stacks. It stays **visible and disabled with its
  /// reason** (t11a) instead of being filtered out, which is what the three
  /// previous copies did — leaving the operator to guess why a registered
  /// family was missing.
  static const Set<WebsiteBlockType> singletonTypes = <WebsiteBlockType>{
    WebsiteBlockType.footer,
  };

  /// Strips diacritics and case so a phone query matches the real titles.
  static String normalize(String value) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    const to = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
    final buffer = StringBuffer();
    for (final rune in value.trim().toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      buffer.write(index == -1 ? char : to[index]);
    }
    return buffer.toString();
  }

  /// Every registered family, exactly once, in registry order.
  ///
  /// [presentBlockTypes] are the `block_type` values already on the page; they
  /// only change the *reason* a singleton gives, never whether it is listed.
  static List<WebsiteBlockCatalogEntry> entries({
    Iterable<String> presentBlockTypes = const <String>[],
  }) {
    final present =
        presentBlockTypes.map((type) => type.trim().toLowerCase()).toSet();

    return WebsiteBlockRegistry.all().map((definition) {
      final type = definition.type;
      final isSingleton = singletonTypes.contains(type);
      final alreadyOnPage = present.contains(type.name.toLowerCase());
      return WebsiteBlockCatalogEntry(
        type: type,
        title: definition.title,
        description: definition.description,
        icon: definition.icon,
        category: type.editorCategory,
        tags: definition.tags,
        isInsertable: !isSingleton,
        unavailableReason: !isSingleton
            ? null
            // t11a copy for the case it drew; the other case still has to say
            // something true rather than repeat a sentence that would be a lie
            // on an empty page.
            : alreadyOnPage
                ? 'Ya existe en esta página'
                : 'El pie de página lo aporta el sitio, no esta página',
      );
    }).toList(growable: false);
  }

  /// [entries] narrowed by a query and a category.
  ///
  /// Filtering never changes insertability: a disabled family that matches the
  /// query is still listed, dimmed, with its reason.
  static List<WebsiteBlockCatalogEntry> filtered({
    Iterable<String> presentBlockTypes = const <String>[],
    String query = '',
    String category = allCategory,
  }) {
    return entries(presentBlockTypes: presentBlockTypes)
        .where((entry) => category == allCategory || entry.category == category)
        .where((entry) => entry.matches(query))
        .toList(growable: false);
  }

  /// `Todos` plus every category that actually has entries, ordered.
  static List<String> categories({
    Iterable<String> presentBlockTypes = const <String>[],
  }) {
    final present = <String>{
      for (final entry in entries(presentBlockTypes: presentBlockTypes))
        entry.category,
    };
    final ordered = <String>[
      allCategory,
      for (final category in categoryOrder)
        if (present.remove(category)) category,
      ...present,
    ];
    return List<String>.unmodifiable(ordered);
  }
}
