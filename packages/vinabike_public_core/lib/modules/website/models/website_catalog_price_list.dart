/// A collection laid out as a price list ([WebsiteCatalogLayout.priceList]):
/// the items grouped by their own category, in the catalog's category order,
/// and the plan category's items apart as plan cards. The Flutter catalog,
/// the workspace preview and the HTML storefront build it with these rules.
library;

import '../../../shared/utils/chilean_utils.dart';

/// One item of the list: what the public catalog read returns for it.
class CatalogPriceItem {
  const CatalogPriceItem({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    this.description = '',
    this.priceMode = 'exact',
  });

  final String id;
  final String name;
  final num? price;
  final String categoryId;

  /// How the price shows (`products.website_price_mode`): `exact`, `from`
  /// («Desde $X») or `quote` («A cotizar»).
  final String priceMode;

  /// The item's «qué incluye» (the catalog description).
  final String description;

  /// The description a price list reads: the store's precedence (the web
  /// text over the catalog's), with its lines kept, since the «qué incluye»
  /// is read by line.
  static String descriptionOf({
    String? websiteDescription,
    String? description,
  }) {
    for (final text in [websiteDescription, description]) {
      if ((text ?? '').trim().isNotEmpty) return text!;
    }
    return '';
  }

  /// The store's price label: the amount, «Desde» the amount, «A cotizar»,
  /// or «Consultar» without one.
  String get priceLabel => catalogPriceLabel(price, mode: priceMode);

  /// Whether the list's search shows this item: its name holds [query],
  /// case and accents aside, as the HTML script compares them.
  bool matches(String query) {
    final key = catalogPriceSearchKey(query);
    return key.isEmpty || catalogPriceSearchKey(name).contains(key);
  }
}

/// Lowercase, trimmed and without accents: «Transmisión» and «transmision»
/// are the same search, as the HTML script folds them (NFD without the
/// combining marks): a precomposed letter loses its accent and a decomposed
/// one its mark (U+0300–U+036F).
String catalogPriceSearchKey(String text) {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñçý';
  const to = 'aaaaaaeeeeiiiiooooouuuuncy';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().trim().runes) {
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer.toString();
}

/// The store's price label (`product_card`): the amount in pesos, or
/// «Consultar» for no price or zero; a service marked `from` reads «Desde»
/// the amount and one marked `quote` «A cotizar» (catalog web, 2026-10-10).
String catalogPriceLabel(num? price, {String mode = 'exact'}) {
  if (mode == 'quote') return 'A cotizar';
  if (price == null || price <= 0) return 'Consultar';
  final amount = ChileanUtils.formatCurrency(price.toDouble());
  return mode == 'from' ? 'Desde $amount' : amount;
}

/// The product page's large price: [catalogPriceLabel] without the space
/// after the sign, as both stores draw it.
String catalogHeroPriceLabel(num? price, {String mode = 'exact'}) =>
    catalogPriceLabel(price, mode: mode).replaceFirst(r'$ ', r'$');

/// The items of one category, cheapest first (those to quote last).
class CatalogPriceGroup {
  const CatalogPriceGroup({
    required this.categoryId,
    required this.label,
    required this.items,
  });

  final String categoryId;
  final String label;
  final List<CatalogPriceItem> items;
}

/// A plan card: the item and what it includes, read from its description.
class CatalogPricePlan {
  CatalogPricePlan(this.item)
    : includes = catalogPlanIncludes(item.description);

  final CatalogPriceItem item;
  final List<CatalogPlanInclude> includes;
}

/// One line of a plan's «qué incluye»: a numbered heading of the description
/// and, folded into one line, what the description lists under it.
class CatalogPlanInclude {
  const CatalogPlanInclude(this.title, [this.detail = '']);

  final String title;
  final String detail;
}

class CatalogPriceList {
  const CatalogPriceList({required this.plans, required this.groups});

  final List<CatalogPricePlan> plans;
  final List<CatalogPriceGroup> groups;

  int get listedCount =>
      groups.fold(0, (count, group) => count + group.items.length);

  int get totalCount => listedCount + plans.length;

  /// The plans side by side with the presentation's [rows]
  /// ([CatalogPlanTable]).
  CatalogPlanTable planTable(List<CatalogPlanRow> rows) =>
      CatalogPlanTable.of(plans, rows);

  /// The plan the cards mark («La más completa»): the one that includes the
  /// most, the dearest of a tie; none for a single plan. A fact of the
  /// catalog, not a claim.
  CatalogPricePlan? get fullestPlan {
    if (plans.length < 2) return null;
    CatalogPricePlan? fullest;
    for (final plan in plans) {
      if (fullest == null ||
          plan.includes.length > fullest.includes.length ||
          (plan.includes.length == fullest.includes.length &&
              (plan.item.price ?? 0) > (fullest.item.price ?? 0))) {
        fullest = plan;
      }
    }
    return fullest;
  }

  /// [items] grouped by category; [compareCategories] is the catalog's order
  /// (`sort_order`, then name) and [categoryLabel] a category's own name.
  /// Items without a category close the list as «Otros».
  static CatalogPriceList build({
    required List<CatalogPriceItem> items,
    required int Function(String a, String b) compareCategories,
    required String Function(String categoryId) categoryLabel,
    String plansCategoryId = '',
  }) {
    int byPrice(CatalogPriceItem a, CatalogPriceItem b) {
      final pa = (a.price ?? 0) > 0 ? a.price! : double.infinity;
      final pb = (b.price ?? 0) > 0 ? b.price! : double.infinity;
      final byAmount = pa.compareTo(pb);
      return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
    }

    final plans = <CatalogPriceItem>[];
    final byCategory = <String, List<CatalogPriceItem>>{};
    for (final item in items) {
      if (plansCategoryId.isNotEmpty && item.categoryId == plansCategoryId) {
        plans.add(item);
      } else {
        byCategory.putIfAbsent(item.categoryId, () => []).add(item);
      }
    }
    final categoryIds = byCategory.keys.where((id) => id.isNotEmpty).toList()
      ..sort(compareCategories);
    if (byCategory.containsKey('')) categoryIds.add('');
    return CatalogPriceList(
      plans: [for (final item in plans..sort(byPrice)) CatalogPricePlan(item)],
      groups: [
        for (final id in categoryIds)
          CatalogPriceGroup(
            categoryId: id,
            label: switch (id.isEmpty ? '' : categoryLabel(id).trim()) {
              '' => 'Otros',
              final label => label,
            },
            items: byCategory[id]!..sort(byPrice),
          ),
      ],
    );
  }
}

/// A row of the plans' comparison, as the editor saves it in the price
/// list's presentation (`plan_rows`, 2026-11-18): what the row is about,
/// written where a plan does not include it («Mantención de transmisión»),
/// and the lines of each plan's «qué incluye» it holds: by the plan's item
/// id, each line's title as its description writes it.
class CatalogPlanRow {
  CatalogPlanRow({
    required String label,
    Map<String, List<String>> picks = const {},
  }) : label = label.trim(),
       picks = Map.unmodifiable({
         for (final MapEntry(:key, :value) in picks.entries)
           if (key.trim().isNotEmpty &&
               value.any((title) => title.trim().isNotEmpty))
             key.trim(): List<String>.unmodifiable([
               for (final title in value)
                 if (title.trim().isNotEmpty) title.trim(),
             ]),
       });

  factory CatalogPlanRow.fromJson(Map<String, dynamic> json) => CatalogPlanRow(
    label: (json['label'] ?? '').toString(),
    picks: {
      if (json['picks'] case final Map raw)
        for (final MapEntry(:key, :value) in raw.entries)
          if (value is List)
            key.toString(): [for (final title in value) title.toString()],
    },
  );

  final String label;
  final Map<String, List<String>> picks;

  /// The titles this row holds of [itemId]'s «qué incluye».
  List<String> picksOf(String itemId) => picks[itemId] ?? const [];

  /// Whether [title] of [itemId]'s «qué incluye» is in this row.
  bool holds(String itemId, String title) {
    final key = catalogPlanLineKey(title);
    return picksOf(
      itemId,
    ).any((picked) => catalogPlanLineKey(picked) == key);
  }

  /// This row with [title] of [itemId] put in it, or taken out if it was.
  CatalogPlanRow toggled(String itemId, String title) {
    final key = catalogPlanLineKey(title);
    final current = picksOf(itemId);
    final next = holds(itemId, title)
        ? [
            for (final picked in current)
              if (catalogPlanLineKey(picked) != key) picked,
          ]
        : [...current, title];
    return CatalogPlanRow(label: label, picks: {...picks, itemId: next});
  }

  CatalogPlanRow copyWith({String? label}) =>
      CatalogPlanRow(label: label ?? this.label, picks: picks);

  /// The plans in a fixed order, so the same row encodes the same way.
  Map<String, dynamic> toJson() => {
    'label': label,
    'picks': {
      for (final id in picks.keys.toList()..sort()) id: picks[id],
    },
  };
}

/// How a line of a «qué incluye» is recognized in a row: its words, case,
/// accents and spacing aside.
String catalogPlanLineKey(String title) =>
    catalogPriceSearchKey(title).replaceAll(RegExp(r'\s+'), ' ');

/// A plan's head on the table: the word every plan's name starts with
/// («Mantención»), the rest of its name («Full») and what the name says in
/// parentheses («Bici rígida, frenos mecánicos»).
class CatalogPlanHead {
  const CatalogPlanHead({
    required this.kicker,
    required this.name,
    required this.note,
  });

  final String kicker;
  final String name;
  final String note;
}

/// The plans' heads: a word all the names share at the start goes above as
/// the kicker, and a closing parenthesis goes below as a note with its first
/// letter raised. One plan, or names that share nothing, keep their name.
List<CatalogPlanHead> catalogPlanHeads(List<String> names) {
  final parsed = [
    for (final name in names)
      switch (RegExp(r'^(.*?)\s*\(([^()]+)\)\s*$').firstMatch(name.trim())) {
        final match? when match.group(1)!.trim().isNotEmpty => (
          base: match.group(1)!.trim(),
          note: _raiseFirst(match.group(2)!.trim()),
        ),
        _ => (base: name.trim(), note: ''),
      },
  ];
  final words = [
    for (final each in parsed) each.base.split(RegExp(r'\s+')),
  ];
  final shared =
      names.length > 1 &&
      words.every((each) => each.length > 1) &&
      words.every(
        (each) =>
            catalogPriceSearchKey(each.first) ==
            catalogPriceSearchKey(words.first.first),
      );
  return [
    for (final (index, each) in parsed.indexed)
      CatalogPlanHead(
        kicker: shared ? words[index].first : '',
        name: shared ? words[index].skip(1).join(' ') : each.base,
        note: each.note,
      ),
  ];
}

String _raiseFirst(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// One row of the table: its label and, plan by plan, the lines of its «qué
/// incluye» the row holds; an empty cell is a plan that does not include it.
class CatalogPlanTableRow {
  const CatalogPlanTableRow(this.label, this.cells);

  final String label;
  final List<List<CatalogPlanInclude>> cells;
}

/// The plans side by side, as TradingView shows its plans (the owner's
/// reference, 2026-11-01; built in the store 2026-11-18): each plan's head,
/// price and button on the same lines, then the presentation's rows, so every
/// plan answers the same row on the same line and one that does not include
/// it says so. What a plan includes that no row holds follows the rows in its
/// own column ([extras]): a plan never hides a line of its description, and a
/// price list without rows is each plan's «qué incluye» under its button.
class CatalogPlanTable {
  const CatalogPlanTable._({
    required this.plans,
    required this.heads,
    required this.rows,
    required this.extras,
  });

  factory CatalogPlanTable.of(
    List<CatalogPricePlan> plans,
    List<CatalogPlanRow> rows,
  ) {
    final placed = [for (final _ in plans) <String>{}];
    final tableRows = <CatalogPlanTableRow>[];
    for (final row in rows) {
      final cells = <List<CatalogPlanInclude>>[];
      for (final (index, plan) in plans.indexed) {
        final picked = {
          for (final title in row.picksOf(plan.item.id))
            catalogPlanLineKey(title),
        };
        final cell = [
          for (final include in plan.includes)
            if (picked.contains(catalogPlanLineKey(include.title))) include,
        ];
        placed[index].addAll(
          cell.map((include) => catalogPlanLineKey(include.title)),
        );
        cells.add(cell);
      }
      // A row no plan answers (its lines were renamed or removed) says
      // nothing true: it is left out until the editor fixes it.
      if (cells.any((cell) => cell.isNotEmpty)) {
        tableRows.add(CatalogPlanTableRow(row.label, cells));
      }
    }
    return CatalogPlanTable._(
      plans: plans,
      heads: catalogPlanHeads([for (final plan in plans) plan.item.name]),
      rows: tableRows,
      extras: [
        for (final (index, plan) in plans.indexed)
          [
            for (final include in plan.includes)
              if (!placed[index].contains(catalogPlanLineKey(include.title)))
                include,
          ],
      ],
    );
  }

  final List<CatalogPricePlan> plans;
  final List<CatalogPlanHead> heads;
  final List<CatalogPlanTableRow> rows;

  /// Plan by plan, what it includes that no row holds.
  final List<List<CatalogPlanInclude>> extras;

  /// The lines under the heads the longest plan needs after the rows.
  int get extraLines =>
      extras.fold(0, (most, each) => each.length > most ? each.length : most);

  /// Every line of cells under the heads: the rows, then the extras.
  int get cellLines => rows.length + extraLines;
}

/// The store's Google rating, as the editor synced it
/// (`google_reviews_rating`, `google_reviews_total`); null without one.
class CatalogPriceListRating {
  const CatalogPriceListRating(this.rating, this.total);

  static CatalogPriceListRating? read(String Function(String key) setting) {
    final rating = double.tryParse(setting('google_reviews_rating').trim());
    if (rating == null || rating <= 0) return null;
    return CatalogPriceListRating(
      rating.clamp(0, 5).toDouble(),
      int.tryParse(setting('google_reviews_total').trim()) ?? 0,
    );
  }

  final double rating;
  final int total;

  /// «4,4».
  String get label => rating.toStringAsFixed(1).replaceAll('.', ',');

  /// «36 reseñas en Google», or empty without a count.
  String get totalLabel =>
      total <= 0 ? '' : '$total ${total == 1 ? 'reseña' : 'reseñas'} en Google';
}

final _numbered = RegExp(r'^\s*\d+\s*[).]\s*(.+)$');
final _bullet = RegExp(r'^\s*[-•*·]\s*(.+)$');

/// A description's «qué incluye»: each numbered line (`1) …`, `2. …`) is one
/// include and the lines under it (`Limpieza profunda de:`, `- Cadena`) its
/// detail, joined in one line; a description without numbers is one include
/// per line. Words are kept as written, only the markers go.
List<CatalogPlanInclude> catalogPlanIncludes(String description) {
  final lines = description
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const [];
  if (!lines.any(_numbered.hasMatch)) {
    return [
      for (final line in lines)
        CatalogPlanInclude(_bullet.firstMatch(line)?.group(1)?.trim() ?? line),
    ];
  }
  final includes = <({String title, List<String> detail})>[];
  for (final line in lines) {
    final heading = _numbered.firstMatch(line);
    if (heading != null) {
      includes.add((title: heading.group(1)!.trim(), detail: []));
    } else if (includes.isNotEmpty) {
      includes.last.detail.add(
        _bullet.firstMatch(line)?.group(1)?.trim() ?? line,
      );
    } else {
      includes.add((
        title: _bullet.firstMatch(line)?.group(1)?.trim() ?? line,
        detail: [],
      ));
    }
  }
  return [
    for (final include in includes)
      CatalogPlanInclude(
        _withoutTrailing(include.title),
        _foldDetail(include.title, include.detail),
      ),
  ];
}

String _withoutTrailing(String text) =>
    text.replaceFirst(RegExp(r'[.:;,]+$'), '').trim();

/// «Limpieza profunda de:», «Cadena», «Piñón» → «Limpieza profunda de:
/// cadena, piñón». After a colon (the heading's or a line's) a capital that
/// starts a lowercase word is lowered, as in running text.
String _foldDetail(String title, List<String> detail) {
  if (detail.isEmpty) return '';
  final buffer = StringBuffer();
  var afterColon = title.trimRight().endsWith(':');
  for (var index = 0; index < detail.length; index++) {
    var part = _withoutTrailing(detail[index]);
    if (part.isEmpty) continue;
    if (afterColon || buffer.isNotEmpty) part = _lowerFirst(part);
    if (buffer.isNotEmpty) {
      buffer.write(buffer.toString().endsWith(':') ? ' ' : ', ');
    }
    buffer.write(part);
    if (detail[index].trimRight().endsWith(':')) buffer.write(':');
    afterColon = detail[index].trimRight().endsWith(':');
  }
  return buffer.toString();
}

String _lowerFirst(String text) {
  if (text.length < 2) return text;
  final first = text[0];
  final second = text[1];
  // An acronym or a name in capitals («SRAM», «XT») keeps its case.
  if (second.toUpperCase() == second && second.toLowerCase() != second) {
    return text;
  }
  return first.toLowerCase() + text.substring(1);
}
