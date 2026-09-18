import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';

/// Un proveedor unificado se encuentra por el nombre de la ficha que absorbió.
///
/// Las filas replican producción (2026-09-18): «Transvayve» y «garozzo» eran
/// fichas duplicadas y vacías; quedaron inactivas y su nombre pasó a alias de
/// «Transportes Vayve» y «Bicicletas Garozzo», que tienen el historial.
void main() {
  Map<String, dynamic> row(
    String id,
    String name, {
    List<Object?>? aliases,
    bool isActive = true,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'aliases': aliases,
        'is_active': isActive,
        'updated_at': '2026-09-18T12:00:00Z',
      };

  final vayve = row('vayve', 'Transportes Vayve', aliases: <Object?>[
    'Transvayve',
  ]);
  final transvayve = row('transvayve', 'Transvayve', isActive: false);
  final garozzo = row('garozzo-shop', 'Bicicletas Garozzo', aliases: <Object?>[
    'Garozzo',
  ]);
  final retiredGarozzo = row('garozzo-retired', 'garozzo', isActive: false);

  List<String> ranked(String query, List<Map<String, dynamic>> rows) =>
      rankGlobalSearch(
        query: GlobalSearchQuery.parse(query),
        entries: <GlobalSearchEntry>[
          for (final r in rows) globalSearchSupplierEntry(r),
        ],
      ).flattened.map((result) => result.entry.id).toList();

  test('el nombre retirado lleva a la ficha que lo absorbió', () {
    expect(ranked('transvayve', <Map<String, dynamic>>[vayve]),
        <String>['supplier:vayve']);
  });

  test('la ficha activa va antes que su duplicado inactivo', () {
    expect(
      ranked('transvayve', <Map<String, dynamic>>[transvayve, vayve]).first,
      'supplier:vayve',
    );
    // El caso difícil: «garozzo» coincide exacto con el título de la inactiva
    // y sólo como alias con la activa.
    expect(
      ranked('garozzo', <Map<String, dynamic>>[retiredGarozzo, garozzo]).first,
      'supplier:garozzo-shop',
    );
  });

  test('una ficha inactiva lo dice', () {
    expect(globalSearchSupplierEntry(transvayve).subtitle, contains('Inactivo'));
    expect(globalSearchSupplierEntry(vayve).subtitle, isNot(contains('Inactivo')));
  });

  test('sin alias, o con alias vacíos, la ficha sigue armándose', () {
    final entry = globalSearchSupplierEntry(
      row('plain', 'Pullman Cargo', aliases: <Object?>[null, '  ']),
    );
    expect(entry.title, 'Pullman Cargo');
    expect(ranked('pullman', <Map<String, dynamic>>[
      row('plain', 'Pullman Cargo'),
    ]), <String>['supplier:plain']);
  });
}
