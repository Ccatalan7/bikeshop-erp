import '../utils/public_spec_display.dart';

/// One published datum of a product's technical sheet, as
/// `get_public_product_technical_specs` sends it.
///
/// Since 20261002130000 the server also sends the store's name for it
/// (`spec_label` is then `store_label`), a one-line explanation of a technical
/// term (`spec_hint`) and its rank among what decides the purchase
/// (`highlight_rank`). An older server sends neither; nothing is invented.
class PublicProductSpecRow {
  const PublicProductSpecRow({
    required this.sectionKey,
    required this.key,
    required this.label,
    required this.value,
    this.unit,
    this.dataType = 'text',
    this.hint,
    this.highlightRank,
  });

  factory PublicProductSpecRow.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return PublicProductSpecRow(
      sectionKey: text('section_key') ?? 'primary',
      key: text('spec_key') ?? '',
      label: text('spec_label') ?? '',
      value: text('display_value') ?? '',
      unit: text('unit'),
      dataType: text('data_type') ?? 'text',
      hint: text('spec_hint'),
      highlightRank: (json['highlight_rank'] as num?)?.toInt(),
    );
  }

  final String sectionKey;
  final String key;
  final String label;
  final String value;
  final String? unit;
  final String dataType;
  final String? hint;
  final int? highlightRank;

  PublicSpecDisplayValue get display => publicSpecSheetValue(
        specKey: key,
        value: value,
        dataType: dataType,
        unit: unit,
      );

  bool get isNegative => dataType == 'boolean' && value == 'No';
}

/// What the product page knows outside the technical sheet.
class PublicSpecIdentity {
  const PublicSpecIdentity({
    this.brand,
    this.model,
    this.manufacturerSku,
    this.gtin,
    this.color,
    this.size,
    this.material,
    this.weightKg = 0,
  });

  final String? brand;
  final String? model;
  final String? manufacturerSku;
  final String? gtin;
  final String? color;
  final String? size;
  final String? material;
  final double weightKg;
}

class PublicSpecItem {
  const PublicSpecItem({
    required this.label,
    required this.value,
    this.detail,
    this.hint,
  });

  final String label;
  final String value;
  final String? detail;
  final String? hint;
}

class PublicSpecGroup {
  const PublicSpecGroup(this.title, this.items);

  final String title;
  final List<PublicSpecItem> items;
}

/// The sheet a customer reads: what decides the purchase next to the price,
/// then every published datum grouped as a shop would group it, then who
/// makes the product.
///
/// Until 2026-10-01 the page mixed the operator's names, a client-side map of
/// 2026-05 keys that no longer matched any sheet, the raw section roles
/// («Según el fabricante») and an identification block led by the SKU, all in
/// identical boxes behind a tab that opened on an empty description.
class PublicProductSpecSheet {
  const PublicProductSpecSheet({
    required this.highlights,
    required this.groups,
  });

  static const int maxHighlights = 4;

  /// Groups the customer reads, by the role the sheet gives each field. A
  /// manufacturer's declaration is a characteristic for the customer; where
  /// every datum comes from is said once, under the sheet.
  static String groupTitleFor(String sectionKey) => switch (sectionKey) {
        'measurement' => 'Medidas',
        'contents' => 'Qué incluye',
        'compatibility' => 'Compatibilidad',
        _ => 'Características',
      };

  static const String identityTitle = 'Marca y modelo';

  final List<PublicSpecItem> highlights;
  final List<PublicSpecGroup> groups;

  bool get isEmpty => groups.isEmpty;

  /// True when the sheet carries technical data and not only the brand.
  bool get hasTechnicalData =>
      groups.any((group) => group.title != identityTitle);

  factory PublicProductSpecSheet.build({
    required List<PublicProductSpecRow> rows,
    PublicSpecIdentity identity = const PublicSpecIdentity(),
  }) {
    final published = rows
        .where((row) => row.label.isNotEmpty && row.value.isNotEmpty)
        .toList(growable: false);
    final groups = <String, List<PublicSpecItem>>{};
    final seen = <String>{};

    void add(String group, PublicSpecItem item) {
      groups.putIfAbsent(group, () => <PublicSpecItem>[]).add(item);
      seen.add(_normalize(item.label));
    }

    for (final row in published) {
      final display = row.display;
      if (display.text.isEmpty) continue;
      add(
        groupTitleFor(row.sectionKey),
        PublicSpecItem(
          label: row.label,
          value: display.text,
          detail: display.detail,
          hint: row.hint,
        ),
      );
    }

    void addOwn(String group, String label, String? value) {
      final clean = value?.trim() ?? '';
      if (clean.isEmpty || seen.contains(_normalize(label))) return;
      add(group, PublicSpecItem(label: label, value: clean));
    }

    const characteristics = 'Características';
    addOwn(characteristics, 'Color', identity.color);
    addOwn(characteristics, 'Talla', identity.size);
    addOwn(characteristics, 'Material', identity.material);
    if (identity.weightKg > 0) {
      addOwn(
        characteristics,
        'Peso',
        identity.weightKg < 1
            ? '${chileanNumber((identity.weightKg * 1000).round().toString())} g'
            : '${chileanNumber(identity.weightKg.toStringAsFixed(2))} kg',
      );
    }
    addOwn(identityTitle, 'Marca', identity.brand);
    addOwn(identityTitle, 'Modelo', identity.model);
    addOwn(identityTitle, 'Código del fabricante', identity.manufacturerSku);
    addOwn(identityTitle, 'Código de barras', identity.gtin);

    return PublicProductSpecSheet(
      highlights: _highlights(published),
      groups: [
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) PublicSpecGroup(entry.key, entry.value),
      ],
    );
  }

  /// Up to four data, ranked by the server; an older server ranks nothing and
  /// the sheet's own order decides. A «No» never sells anything, and the two
  /// ends of a cassette read as one range: «11-34 dientes».
  static List<PublicSpecItem> _highlights(List<PublicProductSpecRow> rows) {
    final usable = rows.where((row) => !row.isNegative).toList();
    final ranked = usable.where((row) => row.highlightRank != null).toList()
      ..sort((a, b) => a.highlightRank!.compareTo(b.highlightRank!));
    final candidates = [
      ...ranked,
      ...usable.where((row) => row.highlightRank == null),
    ];
    final smallest = _first(candidates, 'smallest_cog_teeth');
    final largest = _first(candidates, 'largest_cog_teeth');
    final items = <PublicSpecItem>[];
    for (final row in candidates) {
      if (items.length == maxHighlights) break;
      if (smallest != null && largest != null) {
        if (identical(row, largest)) continue;
        if (identical(row, smallest)) {
          items.add(PublicSpecItem(
            label: 'Piñones',
            value: '${chileanNumber(smallest.value)}-'
                '${publicSpecSheetValue(specKey: largest.key, value: largest.value, dataType: largest.dataType, unit: largest.unit).text}',
          ));
          continue;
        }
      }
      final display = row.display;
      items.add(PublicSpecItem(
        label: row.label,
        value: display.text,
        detail: display.detail,
      ));
    }
    return items.length < 2 ? const [] : items;
  }

  static PublicProductSpecRow? _first(
      List<PublicProductSpecRow> rows, String key) {
    for (final row in rows) {
      if (row.key == key) return row;
    }
    return null;
  }
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '');
