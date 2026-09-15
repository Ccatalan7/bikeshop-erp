import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// Una corrida ya hecha se recupera, y no se guarda dos veces.
///
/// **El caso real (2026-08-30).** Con el gateway de Supabase degradado, cuatro
/// corridas seguidas contra RBX terminaron bien —portal recorrido, filas
/// leídas, veredicto calculado— y murieron en el guardado con `504 upstream
/// request timeout`. El RPC responde en 7 ms: lo que falla es el transporte,
/// así que **el resultado queda desconocido**: la escritura pudo haber entrado.
///
/// Sin clave estable hay dos salidas y las dos son malas: reintentar a ciegas
/// duplica el recibo, o no reintentar y perder minutos de navegación real.

SupplierNeedPortalSearchSnapshot _corrida({String? key}) =>
    SupplierNeedPortalSearchSnapshot(
      query: 'camara',
      status: SupplierNeedPortalSearchStatus.completed,
      checkedAt: DateTime.utc(2026, 8, 30, 3, 18),
      sourceUrl: 'https://rbx/cat?Clasificacion2=171',
      matches: <SupplierNeedPortalMatch>[
        const SupplierNeedPortalMatch(
          candidate: SupplierPortalCatalogCandidate(
            code: '10663',
            name: 'CAMARA 700 X 28/38C V/AUTO 48MM',
          ),
          state: SupplierNeedMatchState.exact,
          provenFields: <String>['product_family', 'valve_type'],
          missingFields: <String>[],
          conflictingFields: <String>[],
          observedFacts: <String, Object?>{'valve_type': 'schrader'},
        ),
      ],
      coverage: const SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: true,
        limit: SupplierNeedCoverageLimit.enumerated,
        nodeLabels: <String>['CAMARAS RUTA'],
        nodesAvailable: 1,
        nodesPlanned: 1,
        nodesCompleted: 1,
        rowsObserved: 35,
        rowsUnique: 35,
        rowsPersisted: 35,
      ),
      searchRevisionNo: 4,
      currentRevisionNo: 4,
      operationKey: key,
    );

void main() {
  group('la identidad de la corrida', () {
    test('una corrida sin sellar no tiene clave', () {
      expect(_corrida().operationKey, isNull);
    });

    test('sellarla conserva TODA la evidencia', () {
      // El sello es identidad, no una corrida nueva: si perdiera las filas, la
      // cobertura o la marca de tiempo, reintentar guardaría algo distinto de
      // lo que se leyó.
      final original = _corrida();
      final sellada = original.withOperationKey('portal-search:s:n:abc');

      expect(sellada.operationKey, 'portal-search:s:n:abc');
      expect(sellada.query, original.query);
      expect(sellada.status, original.status);
      expect(sellada.checkedAt, original.checkedAt);
      expect(sellada.sourceUrl, original.sourceUrl);
      expect(sellada.matches, original.matches);
      expect(sellada.coverage.rowsUnique, 35);
      expect(sellada.coverage.isComplete, isTrue);
      expect(sellada.searchRevisionNo, 4);
      expect(sellada.currentRevisionNo, 4);
    });

    test('la clave cabe en el recibo', () {
      // El servidor la rechaza sobre 160 bytes. Dos uuid más el prefijo caben,
      // pero la cuenta se fija acá para que nadie la alargue sin darse cuenta.
      const supplierId = 'b33660dc-c38a-4a2d-833f-607bc2b0c2ae';
      const needId = 'd6214c93-8405-4039-b0ae-4e36d1949ce2';
      const uuid = '5ce8b362-6961-478a-981a-dfdb8954cf1d';
      const key = 'portal-search:$supplierId:$needId:$uuid';

      expect(key.length, lessThanOrEqualTo(160));
      expect(key.trim(), key, reason: 'el servidor exige la clave sin bordes');
    });

    test('el veredicto sellado sigue siendo el mismo', () {
      // Re-juzgar una corrida recuperada tiene que dar lo mismo que antes de
      // sellarla: la clave no participa del calce.
      final sellada = _corrida().withOperationKey('k');
      final tally = tallySupplierNeedMatchesUnder(
        matches: sellada.matches,
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['schrader'],
          ),
        ],
      );
      expect(tally.confirmed, 1);
      expect(tally.unverified, 0);
    });
  });
}
