import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **5j paso 4 · lo que el resumen promete contra lo que `apply` garantiza.**
///
/// El paso 4 es el **único punto de escritura** del flujo de conciliación, así
/// que una frase de más acá no es un detalle de copy: es una pantalla de dinero
/// afirmando un movimiento que no ocurre. Estas pruebas no miran píxeles —eso
/// lo hacen las de composición— sino que atan cada promesa de la pantalla a la
/// fuente que la cumple, que es siempre el servicio o la migración, **nunca el
/// frame que la dibuja**.
///
/// Los pasos 1 y 2 dejaron siete afirmaciones falsas por copiar el frame sin
/// leer el servicio. Este archivo existe para que el paso 4 no agregue la
/// octava.
void main() {
  const applyMigration =
      'supabase/migrations/20260728213000_add_payroll_statement_reconciliation.sql';
  const servicePath =
      'lib/modules/hr/services/payroll_reconciliation_service.dart';
  const pagePath = 'lib/modules/hr/pages/payroll_reconciliation_page.dart';

  /// El fuente de Dart **sin comentarios**.
  ///
  /// Hace falta porque este mismo archivo prohíbe frases que sus propios
  /// comentarios tienen que citar para explicar por qué están prohibidas. Sin
  /// esto, documentar la regla la rompe — y la salida es peor: dejar de citar
  /// el frame, que es justo lo que hace revisable la decisión.
  String withoutComments(String source) {
    return source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  }

  /// El cuerpo de `apply_payroll_statement_reconciliation`, desde su `create`
  /// hasta el `create` siguiente. Recortarlo importa: la migración entera sí
  /// menciona gastos y gatillos que **no** pertenecen a esta función, y buscar
  /// sobre el archivo completo daría verdes y rojos por texto ajeno.
  String applyFunctionBody() {
    final sql = File(applyMigration).readAsStringSync();
    final start = sql.indexOf(
      'create or replace function public.apply_payroll_statement_reconciliation',
    );
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: 'la migración ya no declara la función de aplicar',
    );
    final next = sql.indexOf('create or replace function', start + 40);
    return next < 0 ? sql.substring(start) : sql.substring(start, next);
  }

  group('5j paso 4 · el resumen no puede prometer lo que apply no hace', () {
    test(
      'no existe ninguna acción que cree un gasto en Contabilidad',
      () {
        // El frame dibuja «Gasto a Contabilidad · 1 · $22.000», y el paso 3
        // ofrece «gasto de manager (a Contabilidad, no toca semanas)». El
        // modelo admite SIETE acciones y ninguna es ésa: mostrarlo afirmaría un
        // asiento que nunca se escribe.
        final sql = File(applyMigration).readAsStringSync();
        expect(
          sql,
          contains(
            'add constraint payroll_statement_decisions_action_check\n'
            '  check (\n'
            '    action in (\n'
            "      'bank_payment',\n"
            "      'cash_payment',\n"
            "      'advance_allocation',\n"
            "      'not_paid',\n"
            "      'ignore',\n"
            "      'hold',\n"
            "      'already_resolved'\n"
            '    )\n'
            '  );',
          ),
          reason: 'si el CHECK cambió, la lista de acciones de esta prueba y '
              'la fila descartada del resumen hay que revisarlas juntas',
        );

        // Y la pantalla no la nombra.
        final page = withoutComments(File(pagePath).readAsStringSync());
        expect(
          page,
          isNot(contains('Gasto a Contabilidad')),
          reason: 'ninguna acción de conciliación crea un gasto contable',
        );
      },
    );

    test(
      'el recibo de aplicar NO trae desglose de replay, así que la pantalla no '
      'lo promete',
      () {
        // El frame promete, literal, que una segunda aplicación hará que «el
        // resumen diga "0 nuevos, 4 ya aplicados"». El recibo que construye la
        // función no tiene de dónde sacar ese desglose: devuelve los mismos
        // conteos totales, y en un reintento devuelve el recibo guardado tal
        // cual (`return import_row.apply_receipt;`).
        final body = applyFunctionBody();
        expect(body, contains('return import_row.apply_receipt;'));
        for (final field in const <String>[
          "'decision_count'",
          "'allocation_count'",
          "'already_resolved_count'",
          "'committed_voucher_ids'",
        ]) {
          expect(
            body,
            contains(field),
            reason: 'el recibo perdió un campo que el resumen usa',
          );
        }

        final page = withoutComments(File(pagePath).readAsStringSync());
        expect(
          page,
          isNot(contains('0 nuevos')),
          reason: 'ese desglose no existe en el recibo',
        );
        expect(
          page,
          isNot(contains('ya aplicados')),
          reason: 'ese desglose no existe en el recibo',
        );
      },
    );

    test(
      'DEFECTO VIGENTE · `wasReplay` está muerto: el RPC no manda `replayed` '
      'ni `was_replay`',
      () {
        // Esto es una prueba de **caracterización**: fija el estado real de
        // hoy, no el deseado. El cliente calcula
        // `wasReplay: response['replayed'] == true || response['was_replay']
        // == true`, y la función desplegada no emite ninguna de las dos claves
        // —comprobado el 2026-08-01 sobre producción con
        // `pg_get_functiondef`, y acá sobre la migración que la define—. La
        // consecuencia es que el mensaje «Esta conciliación ya estaba
        // registrada» **no se puede alcanzar en producción**: un reintento se
        // anuncia igual que un primer intento.
        //
        // **Si esta prueba se pone roja, es una buena noticia**: significa que
        // el backend empezó a declarar el replay y que la rama de la UI ya se
        // puede creer. Entonces hay que borrar esta prueba y escribir la que
        // verifica el mensaje de verdad. La corrección nace en la migración,
        // no en la UI, y desplegar migraciones necesita la autorización del
        // dueño.
        final body = applyFunctionBody();
        expect(
          body.contains("'replayed'") || body.contains("'was_replay'"),
          isFalse,
          reason: 'el RPC de aplicar empezó a declarar el replay: revisa el '
              'mensaje de reintento de la UI, que hoy es inalcanzable',
        );

        final service = File(servicePath).readAsStringSync();
        expect(
          service,
          contains(
            "wasReplay: response['replayed'] == true || "
            "response['was_replay'] == true",
          ),
          reason: 'si el cliente cambió de fuente para `wasReplay`, esta '
              'caracterización dejó de describir el defecto',
        );
      },
    );

    test(
      'el encabezado no afirma «nada se escribió» cuando la importación ya '
      'existe',
      () {
        // `_apply()` llama `createImport` ANTES que `apply`, y ese RPC inserta
        // la importación y sus filas. Si el apply falla, los pagos no se
        // crearon —es una sola transacción— pero la cartola sí quedó
        // registrada. El frame rotula «Nada se escribió todavía» siempre; la
        // pantalla sólo puede decirlo mientras sea cierto.
        final sql = File(applyMigration).readAsStringSync();
        expect(
          sql,
          contains('insert into public.payroll_statement_imports'),
          reason: 'crear la importación es una escritura, y por eso el '
              'encabezado del paso 4 depende de si ya ocurrió',
        );

        final page = File(pagePath).readAsStringSync();
        expect(
          page,
          contains('_importReceipt == null'),
          reason: 'el encabezado tiene que mirar si la importación ya existe',
        );
        expect(
          page,
          contains('Nada se escribió todavía. Este es el último punto de '
              'retorno.'),
        );
        expect(
          page,
          contains('La cartola ya quedó registrada por el intento anterior.'),
        );
      },
    );

    test(
      '«imputar» no aparece en la conciliación: Design lo derogó en el turno 7',
      () {
        // `handoff-t9/CHANGELOG.md`, sección «Decisiones de producto respetadas
        // (ya en la app)»: «"Imputar" → "Aplicar"». El frame del turno 5 rotula
        // «Total a imputar» porque es anterior a esa corrección.
        final page = withoutComments(File(pagePath).readAsStringSync());
        expect(
          page.toLowerCase(),
          isNot(contains('imputar')),
          reason: 'la palabra está derogada por el propio Design',
        );
        expect(page, contains('Total a aplicar'));
      },
    );
  });
}
