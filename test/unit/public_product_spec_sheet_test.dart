import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_product_spec_sheet.dart';

PublicProductSpecRow row(
  String section,
  String key,
  String label,
  String value, {
  String? unit,
  String type = 'single_select',
  String? hint,
  int? rank,
}) =>
    PublicProductSpecRow(
      sectionKey: section,
      key: key,
      label: label,
      value: value,
      unit: unit,
      dataType: type,
      hint: hint,
      highlightRank: rank,
    );

void main() {
  // The Maxxis Tomahawk 27.5 x 2.30 on vinabike.cl, 2026-10-01, with the
  // store words of 20261002130000.
  final tomahawk = [
    row('measurement', 'bead_seat_diameter_mm', 'Aro', '584',
        unit: 'mm', type: 'number', rank: 1),
    row('declaration', 'tire_etrto', 'Medida ETRTO', '58-584',
        type: 'text', hint: 'Medida exacta impresa en el costado.'),
    row('measurement', 'tire_width_mm', 'Ancho', '58.4',
        unit: 'mm', type: 'number', rank: 2),
    row('primary', 'tire_bead_type', 'Talón', 'Plegable (kevlar)', rank: 4),
    row('primary', 'tire_tubeless_ready', 'Tubeless Ready', 'Sí',
        type: 'boolean', rank: 5),
    row('primary', 'tire_tpi', 'TPI', '60',
        unit: 'TPI', type: 'number', rank: 6),
    row('measurement', 'tire_weight_g', 'Peso', '810',
        unit: 'g', type: 'number'),
    row('declaration', 'tire_use', 'Uso', 'MTB', rank: 3),
  ];

  test('the server ranks what decides the purchase', () {
    final sheet = PublicProductSpecSheet.build(rows: tomahawk);
    expect(
      sheet.highlights.map((item) => '${item.label}: ${item.value}'),
      [
        'Aro: 27.5" / 650b',
        'Ancho: 2.3" · 58 mm',
        'Uso: MTB',
        'Talón: Plegable (kevlar)',
      ],
    );
  });

  test('the groups are the shop\'s, in the sheet\'s order, with explanations',
      () {
    final sheet = PublicProductSpecSheet.build(
      rows: tomahawk,
      identity: const PublicSpecIdentity(
        brand: 'Maxxis',
        model: 'Tomahawk',
        manufacturerSku: 'TB91000300',
      ),
    );
    expect(sheet.groups.map((group) => group.title),
        ['Medidas', 'Características', 'Marca y modelo']);
    final characteristics = sheet.groups[1].items;
    expect(characteristics.map((item) => item.label),
        ['Medida ETRTO', 'Talón', 'Tubeless Ready', 'TPI', 'Uso'],
        reason: 'A manufacturer\'s declaration is a characteristic for the '
            'customer; «Según el fabricante» was the sheet\'s role, not a '
            'shop heading.');
    expect(characteristics.first.hint, 'Medida exacta impresa en el costado.');
    expect(sheet.groups.first.items.first.detail, 'ISO 584');
    expect(sheet.groups.last.items.map((item) => item.label),
        ['Marca', 'Modelo', 'Código del fabricante'],
        reason: 'The SKU is already beside the stock and the category in the '
            'breadcrumb; neither leads the sheet any more.');
    expect(sheet.hasTechnicalData, isTrue);
  });

  test('an older server ranks nothing: the sheet order decides', () {
    final unranked = [
      for (final r in tomahawk)
        row(r.sectionKey, r.key, r.label, r.value,
            unit: r.unit, type: r.dataType),
    ];
    final sheet = PublicProductSpecSheet.build(rows: unranked);
    expect(sheet.highlights.map((item) => item.label),
        ['Aro', 'Medida ETRTO', 'Ancho', 'Talón']);
  });

  test('a «No» never sells, and one datum is not a highlight', () {
    final sheet = PublicProductSpecSheet.build(rows: [
      row('primary', 'quick_link_included', 'Incluye eslabón rápido', 'No',
          type: 'boolean', rank: 1),
      row('measurement', 'chain_speeds', 'Velocidades', '6',
          type: 'multi_select', rank: 2),
    ]);
    expect(sheet.highlights, isEmpty);
    expect(sheet.groups.expand((group) => group.items).map((i) => i.value),
        containsAll(['No', '6']),
        reason: 'The full sheet still states the explicit false.');
  });

  test('the two ends of a cassette read as one range', () {
    final sheet = PublicProductSpecSheet.build(rows: [
      row('primary', 'sprocket_count', 'Velocidades', '12',
          type: 'number', rank: 1),
      row('measurement', 'smallest_cog_teeth', 'Piñón más chico', '11',
          unit: 'T', type: 'number', rank: 2),
      row('measurement', 'largest_cog_teeth', 'Piñón más grande', '34',
          unit: 'T', type: 'number', rank: 3),
      row('measurement', 'cassette_spline_standard', 'Núcleo',
          'Shimano HG spline L2 (ruta 12v)',
          rank: 4),
    ]);
    expect(
      sheet.highlights.map((item) => '${item.label}: ${item.value}'),
      [
        'Velocidades: 12',
        'Piñones: 11-34 dientes',
        'Núcleo: Shimano HG spline L2 (ruta 12v)',
      ],
    );
  });

  test('a product without a sheet still names its maker', () {
    final sheet = PublicProductSpecSheet.build(
      rows: const [],
      identity: const PublicSpecIdentity(brand: 'KMC', gtin: '4715575896793'),
    );
    expect(sheet.hasTechnicalData, isFalse);
    expect(sheet.groups.single.items.map((item) => item.label),
        ['Marca', 'Código de barras']);
    expect(sheet.highlights, isEmpty);
  });

  test('the product\'s own fields never repeat a published datum', () {
    final sheet = PublicProductSpecSheet.build(
      rows: [row('primary', 'material', 'Material', 'Aluminio')],
      identity:
          const PublicSpecIdentity(material: 'Aluminio 6061', color: 'Negro'),
    );
    expect(
      sheet.groups.single.items.map((item) => '${item.label}: ${item.value}'),
      ['Material: Aluminio', 'Color: Negro'],
    );
  });

  test('the row reads the server columns and tolerates an older server', () {
    final current = PublicProductSpecRow.fromJson({
      'section_key': 'primary',
      'spec_key': 'tire_tpi',
      'spec_label': 'TPI',
      'display_value': '60',
      'unit': 'TPI',
      'data_type': 'number',
      'spec_hint': 'Hilos por pulgada de la carcasa.',
      'highlight_rank': 6,
    });
    expect(current.hint, 'Hilos por pulgada de la carcasa.');
    expect(current.highlightRank, 6);
    final older = PublicProductSpecRow.fromJson({
      'section_key': 'primary',
      'spec_key': 'tire_tpi',
      'spec_label': 'TPI (densidad de la carcasa)',
      'display_value': '60',
      'unit': 'TPI',
      'data_type': 'number',
    });
    expect(older.hint, isNull);
    expect(older.highlightRank, isNull);
  });
}
