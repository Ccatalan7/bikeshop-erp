import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:vinabike_erp/shared/services/supplier_availability_service.dart';

/// Distinguir «no se pudo escribir» de «no sabemos si se escribió».
///
/// **El error real, medido en producción el 2026-08-30.** Cada `504 Gateway
/// Timeout` de esta corrida era en realidad:
///
///     PostgrestException(code: PGRST003,
///       message: 'Timed out acquiring connection from connection pool.')
///
/// PostgREST no consiguió conexión, así que la sentencia **nunca llegó** a
/// Postgres — medido: `pg_stat_statements` no incrementó y la RPC responde en
/// 7 ms cuando sí corre. El clasificador buscaba la palabra `timeout` y el
/// mensaje dice `Timed out`: **nunca coincidió**, el reintento jamás se
/// ejecutó, y por fuera se veía como «el segundo intento también falla».

PostgrestException _error({String? code, String message = ''}) =>
    PostgrestException(message: message, code: code);

void main() {
  group('el error que estuvo escondido detrás de cada 504', () {
    final poolAgotado = _error(
      code: 'PGRST003',
      message: 'Timed out acquiring connection from connection pool.',
    );

    test('un pool agotado se reintenta', () {
      expect(SupplierAvailabilityService.isUnknownOutcome(poolAgotado), isTrue);
    });

    test('y se sabe que la escritura NO ocurrió', () {
      // Sin conexión la sentencia no corrió: no hay recibo que resolver, y
      // preguntar sólo gastaría otra conexión del pool que está saturado.
      expect(
        SupplierAvailabilityService.connectionNeverAcquired(poolAgotado),
        isTrue,
      );
    });

    test('«Timed out» cuenta aunque no diga «timeout»', () {
      // La trampa exacta que dejó el camino muerto.
      expect(
        SupplierAvailabilityService.isUnknownOutcome(
          _error(message: 'Timed out acquiring connection from pool.'),
        ),
        isTrue,
      );
    });
  });

  group('un pool agotado no se aprieta dos veces', () {
    test('PGRST003 no se resuelve por clave: la sentencia no corrió', () {
      // Preguntar por la clave gastaría OTRA conexión del pool que acaba de
      // negarla. Y como no corrió, no hay recibo que resolver.
      final poolAgotado = _error(
        code: 'PGRST003',
        message: 'Timed out acquiring connection from connection pool.',
      );
      expect(
        SupplierAvailabilityService.connectionNeverAcquired(poolAgotado),
        isTrue,
      );
    });

    test('un 504 sí deja el resultado desconocido y hay que resolverlo', () {
      // Acá la sentencia PUDO haber corrido: reintentar a ciegas duplicaría.
      final gateway = _error(code: '504', message: 'upstream request timeout');
      expect(
        SupplierAvailabilityService.connectionNeverAcquired(gateway),
        isFalse,
      );
      expect(SupplierAvailabilityService.isUnknownOutcome(gateway), isTrue);
    });
  });

  group('un rechazo del negocio no se reintenta', () {
    test('una clave reusada con otra petición es una respuesta', () {
      // `23505` lo lanza el recibo a propósito. Reintentarlo escribiría dos
      // veces la misma lectura o pisaría un recibo ajeno.
      expect(
        SupplierAvailabilityService.isUnknownOutcome(
          _error(
              code: '23505',
              message: 'La clave de operación pertenece a '
                  'otra búsqueda.'),
        ),
        isFalse,
      );
    });

    test('una cobertura inválida es una respuesta', () {
      expect(
        SupplierAvailabilityService.isUnknownOutcome(
          _error(code: '22023', message: 'Invalid need portal coverage'),
        ),
        isFalse,
      );
    });

    test('una necesidad inexistente es una respuesta', () {
      expect(
        SupplierAvailabilityService.isUnknownOutcome(
          _error(code: 'P0002', message: 'Supply need not found'),
        ),
        isFalse,
      );
    });
  });

  group('un rechazo definitivo no vuelve a la cola', () {
    // **Medido el 2026-09-15.** El guardián de alcance rechazaba una estampa
    // vieja con `40001`; un cliente lo reintentó ~900 veces por segundo
    // durante 16 días (1.14 mil millones de transacciones abortadas). Hoy
    // rechaza con `23514`, y el cliente tiene que leerlo como «no vuelvas a
    // mandarlo»: recargar la necesidad, no esperar y repetir.
    final necesidadCambio = _error(
      code: '23514',
      message: 'La necesidad cambió mientras se consultaba al proveedor; '
          'esa lectura ya no responde lo que se está preguntando.',
    );

    test('23514 es un rechazo, no un transporte caído', () {
      expect(
        SupplierAvailabilityService.isDefinitiveRejection(necesidadCambio),
        isTrue,
      );
      expect(
        SupplierAvailabilityService.isUnknownOutcome(necesidadCambio),
        isFalse,
      );
      expect(
        SupplierAvailabilityService.connectionNeverAcquired(necesidadCambio),
        isFalse,
      );
    });

    test('y el tipo que sale dice qué recargar', () {
      final rejected = SupplierNeedSearchRejected(
        PostgrestException(
          message: necesidadCambio.message,
          code: '23514',
          details: 'supply_need=n1 expected version 5 revision 2, '
              'current version 6 revision 3',
          hint: 'Vuelve a leer la necesidad y repite la búsqueda contra su '
              'interpretación vigente.',
        ),
      );
      expect(rejected.needChanged, isTrue);
      expect(rejected.hint, contains('Vuelve a leer la necesidad'));
      expect(rejected.details, contains('current version 6 revision 3'));
      expect(rejected.message, contains('La necesidad cambió'));
    });

    test('toda la clase 22/23 y P0001 se niegan; 40001 sigue siendo otra cosa',
        () {
      for (final code in <String>['23505', '23514', '22023', 'P0001']) {
        expect(
          SupplierAvailabilityService.isDefinitiveRejection(_error(code: code)),
          isTrue,
          reason: '$code es una respuesta del servidor',
        );
      }
      // `40001` no es un rechazo definitivo: es la instrucción «reintenta la
      // misma transacción», y por eso el guardián dejó de emitirlo.
      expect(
        SupplierAvailabilityService.isDefinitiveRejection(
            _error(code: '40001')),
        isFalse,
      );
    });

    test('el transporte no se confunde con un rechazo', () {
      for (final code in <String>['PGRST003', '502', '503', '504', '408']) {
        expect(
          SupplierAvailabilityService.isDefinitiveRejection(_error(code: code)),
          isFalse,
          reason: '$code no dice que el servidor haya leído el recibo',
        );
      }
      expect(
        SupplierAvailabilityService.isDefinitiveRejection(_error(code: null)),
        isFalse,
      );
    });
  });

  group('el transporte que sí deja el resultado desconocido', () {
    test('502, 503, 504, 408 y 429 se resuelven por clave antes de reintentar',
        () {
      for (final code in <String>['502', '503', '504', '408', '429']) {
        expect(
          SupplierAvailabilityService.isUnknownOutcome(_error(code: code)),
          isTrue,
          reason: 'el código $code no dice si la escritura entró',
        );
        // Y como pudo haber entrado, NO se puede reintentar a ciegas.
        expect(
          SupplierAvailabilityService.connectionNeverAcquired(
              _error(code: code)),
          isFalse,
        );
      }
    });
  });
}
