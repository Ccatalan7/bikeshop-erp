/// The catalog's filters as the public facet read describes them
/// (`get_public_product_facets_v2`), shared by the Flutter store and the HTML
/// storefront since 2026-10-05 so both read the rows with one rule.
library;

import 'public_product_brand_names.dart';

class PublicCatalogBrandFacet {
  final String id;
  final String label;
  final int itemCount;

  const PublicCatalogBrandFacet({
    required this.id,
    required this.label,
    required this.itemCount,
  });
}

/// One value of a technical-spec facet («Francesa (Presta)», «622») and how
/// many visible products carry it.
class PublicCatalogSpecFacetValue {
  final String value;
  final int itemCount;

  const PublicCatalogSpecFacetValue({
    required this.value,
    required this.itemCount,
  });
}

/// A filterable technical-spec definition among the visible products of the
/// current collection: its key, its shop label, its data type and unit, and
/// its values with counts. Rows arrive from the facet RPC as
/// `facet_key = spec:<key>:<data_type>:<unit>`.
class PublicCatalogSpecFacet {
  final String key;
  final String label;
  final String dataType;
  final String? unit;
  final List<PublicCatalogSpecFacetValue> values;

  /// The visible name of an option value («Eslabón rápido (missing link)»),
  /// keyed by the label the filter keeps (`Missing link`, cited by links).
  final Map<String, String> optionDisplay;

  /// Products of the collection that carry this spec at all.
  final int productCount;

  /// Products the collection holds once the other filters apply.
  final int scopeCount;

  const PublicCatalogSpecFacet({
    required this.key,
    required this.label,
    required this.dataType,
    required this.unit,
    required this.values,
    required this.productCount,
    required this.scopeCount,
    this.optionDisplay = const {},
  });

  /// Share of the collection this spec describes, 0..1.
  double get coverage =>
      scopeCount <= 0 ? 0 : (productCount / scopeCount).clamp(0, 1);
}

class PublicCatalogFacetSnapshot {
  final List<PublicCatalogBrandFacet> brands;
  final List<PublicCatalogSpecFacet> specFacets;
  final Map<String, int> directCategoryCounts;
  final int? filteredTotalCount;
  final double? minPrice;
  final double? maxPrice;
  final bool isAvailable;

  const PublicCatalogFacetSnapshot({
    required this.brands,
    this.specFacets = const [],
    this.directCategoryCounts = const {},
    this.filteredTotalCount,
    required this.minPrice,
    required this.maxPrice,
    this.isAvailable = true,
  });

  const PublicCatalogFacetSnapshot.unavailable()
      : brands = const [],
        specFacets = const [],
        directCategoryCounts = const {},
        filteredTotalCount = null,
        minPrice = null,
        maxPrice = null,
        isAvailable = false;

  /// Reads the facet RPC's rows: `brand`, `price`, `category`, `summary` and
  /// one `spec:<key>:<data_type>:<unit>` row per value. Brands go by name;
  /// the specs that describe most of the collection come first.
  factory PublicCatalogFacetSnapshot.fromRows(
    Iterable<Object?> rows, {
    Map<String, Map<String, String>> optionDisplayByKey = const {},
  }) {
    final brands = <PublicCatalogBrandFacet>[];
    final specRows = <String, List<Map<String, dynamic>>>{};
    final directCategoryCounts = <String, int>{};
    int? filteredTotalCount;
    double? rangeMin;
    double? rangeMax;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final facetKey = row['facet_key']?.toString() ?? '';
      if (facetKey.startsWith('spec:')) {
        specRows.putIfAbsent(facetKey, () => []).add(row);
        continue;
      }
      switch (facetKey) {
        case 'brand':
          final id = row['value_id']?.toString().trim() ?? '';
          final label = row['value_label']?.toString().trim() ?? '';
          // «Genérico» or «Aliexpress» is not a brand to filter by.
          if (id.isNotEmpty && isPublicProductBrand(label)) {
            brands.add(PublicCatalogBrandFacet(
              id: id,
              label: label,
              itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
            ));
          }
          break;
        case 'price':
          rangeMin = (row['range_min'] as num?)?.toDouble();
          rangeMax = (row['range_max'] as num?)?.toDouble();
          break;
        case 'category':
          final id = row['value_id']?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            directCategoryCounts[id] =
                (row['item_count'] as num?)?.toInt() ?? 0;
          }
          break;
        case 'summary':
          filteredTotalCount = (row['item_count'] as num?)?.toInt() ?? 0;
          break;
      }
    }
    brands.sort((a, b) => a.label.toLowerCase().compareTo(
          b.label.toLowerCase(),
        ));
    final specFacets = <PublicCatalogSpecFacet>[];
    for (final entry in specRows.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 3) continue;
      final key = parts[1].trim();
      final dataType = parts[2].trim();
      final unit = parts.length > 3 ? parts.sublist(3).join(':').trim() : '';
      final label = entry.value
          .map((row) => row['value_label']?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => key);
      final values = <PublicCatalogSpecFacetValue>[
        for (final row in entry.value)
          if ((row['value_id']?.toString().trim() ?? '').isNotEmpty)
            PublicCatalogSpecFacetValue(
              value: row['value_id'].toString().trim(),
              itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
            ),
      ]..sort((a, b) {
          final byCount = b.itemCount.compareTo(a.itemCount);
          return byCount != 0 ? byCount : a.value.compareTo(b.value);
        });
      if (key.isEmpty || values.isEmpty) continue;
      final first = entry.value.first;
      specFacets.add(PublicCatalogSpecFacet(
        key: key,
        label: label,
        dataType: dataType,
        unit: unit.isEmpty ? null : unit,
        values: List.unmodifiable(values),
        productCount: (first['range_min'] as num?)?.toInt() ?? 0,
        scopeCount: (first['range_max'] as num?)?.toInt() ?? 0,
        optionDisplay: optionDisplayByKey[key] ?? const {},
      ));
    }
    // The facets that describe most of the collection come first.
    specFacets.sort((a, b) {
      final byCoverage = b.productCount.compareTo(a.productCount);
      return byCoverage != 0 ? byCoverage : a.label.compareTo(b.label);
    });
    return PublicCatalogFacetSnapshot(
      brands: List.unmodifiable(brands),
      specFacets: List.unmodifiable(specFacets),
      directCategoryCounts: Map.unmodifiable(directCategoryCounts),
      filteredTotalCount: filteredTotalCount,
      minPrice: rangeMin,
      maxPrice: rangeMax,
    );
  }
}

/// Visible names of option values by spec key and option label, from the
/// rows of `get_public_spec_option_labels_v1` (20261002130000). A filter keeps
/// the option's label, which shared links cite; the visitor reads its name.
Map<String, Map<String, String>> publicSpecOptionDisplayFromRows(
  Iterable<Object?> rows,
) {
  final byKey = <String, Map<String, String>>{};
  for (final raw in rows) {
    if (raw is! Map) continue;
    final key = raw['spec_key']?.toString().trim() ?? '';
    final label = raw['value_label']?.toString().trim() ?? '';
    final display = raw['display_label']?.toString().trim() ?? '';
    if (key.isEmpty || label.isEmpty || display.isEmpty) continue;
    byKey.putIfAbsent(key, () => <String, String>{})[label] = display;
  }
  return byKey;
}

/// `{"valve_standard": ["Francesa (Presta)"]}` for the RPCs, or null when
/// there is nothing to filter. Keys and values are sorted so equal filters
/// give equal requests.
Map<String, List<String>>? publicSpecFiltersForRpc(
  Map<String, Iterable<String>>? specFilters,
) {
  if (specFilters == null || specFilters.isEmpty) return null;
  final result = <String, List<String>>{};
  final keys = specFilters.keys.toList()..sort();
  for (final key in keys) {
    final values = specFilters[key]!
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (values.isNotEmpty) result[key] = values;
  }
  return result.isEmpty ? null : result;
}

/// A spec facet is offered when it describes most of what the visitor is
/// looking at (the tubes of «Cámaras» all have a valve; on the home
/// collection a valve describes a corner), or when one of its values is
/// already selected. At most [maxOffered], best coverage first, selected ones
/// before the rest. A facet with one value and nothing selected narrows
/// nothing and is left out.
const double publicMinSpecFacetCoverage = 0.3;

List<PublicCatalogSpecFacet> offeredPublicSpecFacets(
  Iterable<PublicCatalogSpecFacet> facets, {
  required Map<String, Set<String>> selected,
  int maxOffered = 8,
}) {
  bool isSelected(PublicCatalogSpecFacet facet) =>
      selected[facet.key]?.isNotEmpty == true;
  final offered = <PublicCatalogSpecFacet>[];
  for (final facet in facets) {
    if (!isSelected(facet) && facet.coverage < publicMinSpecFacetCoverage) {
      continue;
    }
    if (!isSelected(facet) && facet.values.length < 2) continue;
    offered.add(facet);
  }
  offered.sort((a, b) {
    final aSelected = isSelected(a);
    final bSelected = isSelected(b);
    if (aSelected != bSelected) return aSelected ? -1 : 1;
    final byCoverage = b.productCount.compareTo(a.productCount);
    return byCoverage != 0 ? byCoverage : a.label.compareTo(b.label);
  });
  return offered.take(maxOffered).toList(growable: false);
}

/// A facet's values in reading order: selected first; a measure by its
/// number (aro 20", 24", 26", 27.5", 29"); then by how many products carry
/// it, then by its visible name.
List<PublicCatalogSpecFacetValue> orderedPublicSpecFacetValues(
  PublicCatalogSpecFacet facet, {
  required Set<String> selected,
  required String Function(String value) labelOf,
}) {
  final numeric = facet.dataType == 'number';
  return List<PublicCatalogSpecFacetValue>.from(facet.values)
    ..sort((a, b) {
      final aSelected = selected.contains(a.value);
      final bSelected = selected.contains(b.value);
      if (aSelected != bSelected) return aSelected ? -1 : 1;
      if (numeric) {
        final aNumber = double.tryParse(a.value.replaceAll(',', '.'));
        final bNumber = double.tryParse(b.value.replaceAll(',', '.'));
        if (aNumber != null && bNumber != null && aNumber != bNumber) {
          return aNumber.compareTo(bNumber);
        }
      }
      final byCount = b.itemCount.compareTo(a.itemCount);
      if (byCount != 0) return byCount;
      return labelOf(a.value).compareTo(labelOf(b.value));
    });
}
