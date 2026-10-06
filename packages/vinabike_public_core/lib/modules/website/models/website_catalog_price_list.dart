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
  });

  final String id;
  final String name;
  final num? price;
  final String categoryId;

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

  /// The store's price label: the amount, or «Consultar» without one.
  String get priceLabel => catalogPriceLabel(price);

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
/// «Consultar» for no price or zero.
String catalogPriceLabel(num? price) => price != null && price > 0
    ? ChileanUtils.formatCurrency(price.toDouble())
    : 'Consultar';

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
