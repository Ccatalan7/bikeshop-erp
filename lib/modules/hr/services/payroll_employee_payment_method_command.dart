import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/database_service.dart';
import '../models/hr_models.dart';

/// **5g · cómo se le paga a un trabajador, escrito sin pisar a nadie.**
///
/// Existe porque la alternativa disponible —`HRService.updateEmployee`—
/// serializa la **fila entera** del trabajador: guardar el banco desde Nóminas
/// reescribiría de paso sueldo, contrato, estado y todo lo demás con los
/// valores que el cliente tuviera cargados, pisando lo que otro haya cambiado
/// mientras tanto. Para una pantalla que sólo toca la configuración de pago eso
/// es un riesgo sin contrapartida.
///
/// Este comando delega el cambio a
/// `set_employee_payroll_payment_method`: una única transacción bloquea la
/// ficha y el método, comprueba la versión y deriva el código legacy desde el
/// catálogo del tenant. El cliente nunca puede enviar un código competidor.
///
/// **Las dos columnas de preferencia se escriben juntas, siempre.**
/// `employees` tiene `preferred_payment_method_id` (FK, la autoridad que
/// `payroll_redesign_page` lee) y `preferred_payment_method` (texto legacy).
/// **Nada en la base las sincroniza** —no hay trigger que las ate— y por eso
/// hoy divergen en producción: medido el 2026-08-01, de 7 trabajadores 4 están
/// coherentes, 2 tienen el FK nulo con texto `transfer`, y **uno dice `transfer`
/// en texto mientras su FK apunta a `check`**. Escribir sólo el id dejaría esa
/// contradicción viva para siempre, así que el texto se deriva del `code` del
/// método bloqueado por el servidor y se escribe en la misma sentencia.
class PayrollEmployeePaymentMethodCommand {
  PayrollEmployeePaymentMethodCommand({DatabaseService? database})
      : _store = _SupabaseEmployeePaymentStore(database ?? DatabaseService());

  /// Con un adaptador propio, para poder probar la conducta —el payload, los
  /// filtros, cada desenlace— sin una base detrás.
  PayrollEmployeePaymentMethodCommand.forTesting(this._store);

  final PayrollEmployeePaymentStore _store;

  /// Techo de gastos que este conteo puede abarcar **en una sola lectura**.
  ///
  /// No es una página: es el límite hasta donde el número se puede afirmar. Por
  /// encima, el desenlace es `unavailable`, nunca un total parcial disfrazado
  /// de exacto.
  ///
  /// **150 tiene dos razones medidas.** Por arriba, el `in` de PostgREST viaja
  /// en la URL: 150 UUID son ~5,5 KB, cómodos bajo los 8 KB que suele aceptar
  /// un proxy. Por abajo, en producción el trabajador con más líneas tiene
  /// **30** (medido el 2026-08-01), así que hay cinco veces de holgura.
  static const int _expenseIdCeiling = 150;

  /// Lee la fila del trabajador **justo antes de escribir**.
  ///
  /// Se lee acá, y no de la proyección de la lista, por dos razones: la lista
  /// de Nóminas no trae `updated_at` ni los campos bancarios —y ampliarla
  /// tocaría un archivo de otro dueño—, y sobre todo porque una versión leída
  /// hace rato **no sirve como guard**: cuanto más fresca, más honesto el
  /// conflicto que detecta.
  Future<PayrollEmployeePaymentReadOutcome> read(String employeeId) async {
    final id = employeeId.trim();
    if (id.isEmpty) {
      return const PayrollEmployeePaymentReadOutcome(
        status: PayrollEmployeePaymentReadStatus.missing,
      );
    }
    try {
      final rows = await _store.readEmployee(id);
      if (rows.isEmpty) {
        // Sin fila: o no existe, o RLS no deja verla. Desde acá no se
        // distinguen y no se finge que sí.
        return const PayrollEmployeePaymentReadOutcome(
          status: PayrollEmployeePaymentReadStatus.missing,
        );
      }
      final snapshot = PayrollEmployeePaymentSnapshot.fromRow(rows.first);
      if (!snapshot.hasCompleteRow ||
          snapshot.employeeId != id ||
          snapshot.tenantId.isEmpty ||
          snapshot.updatedAtRaw.isEmpty) {
        return const PayrollEmployeePaymentReadOutcome(
          status: PayrollEmployeePaymentReadStatus.unavailable,
        );
      }
      return PayrollEmployeePaymentReadOutcome(
        status: PayrollEmployeePaymentReadStatus.loaded,
        snapshot: snapshot,
      );
    } catch (_) {
      // La lectura también puede fallar, y sin esto el error subía sin nadie
      // que lo contara. El texto del servidor no se propaga.
      return const PayrollEmployeePaymentReadOutcome(
        status: PayrollEmployeePaymentReadStatus.unavailable,
      );
    }
  }

  /// Pagos ya registrados de una persona, para el aviso de «cambio seguro».
  ///
  /// **Dos lecturas acotadas, no N+1 y sin hidratar el historial.** La fuente
  /// es `expense_payments` a través del `expense_id` de sus líneas: es donde
  /// vive el pago de verdad.
  ///
  /// Reemplaza un conteo anterior que sumaba `settlementEvidence` sobre
  /// `_data.vouchers`. Ése **daba siempre 0**, porque las semanas del historial
  /// entran como cabeceras **sin líneas**: el aviso central del frame existía
  /// en el código y no se mostraba nunca. Hoy en producción hay personas con
  /// 27, 24 y 17 pagos, así que el estado es perfectamente alcanzable.
  ///
  /// **Devuelve tres desenlaces, no un número.** La versión anterior devolvía
  /// `0` cuando la lectura fallaba, y en pantalla «0 pagos» se lee como *«no
  /// tiene pagos»* — que es una afirmación distinta de *«no pude contarlos»*, y
  /// justo la que no se puede hacer sobre el historial de sueldos de alguien.
  ///
  /// **Y es exacto o es `unavailable`; no hay término medio.** Una versión
  /// anterior paginaba los gastos con `order('id')` + `range`, y afirmaba en
  /// el comentario y en el registro de superficies que eso evitaba saltos y
  /// duplicados. **Era falso**: un `INSERT` o un `DELETE` entre dos páginas
  /// corre la frontera igual, y `payroll_voucher_lines.id` es un UUID
  /// **aleatorio**, así que ni siquiera ordena por antigüedad. Desde el cliente
  /// no hay forma de leer varias páginas de forma consistente sin una consulta
  /// atómica del servidor, y **no existe una**. Así que el conteo se hace con
  /// **una lectura acotada y un solo `count(exact)`**, y por encima del techo
  /// dice que no sabe.
  Future<PayrollRecordedPaymentCount> countRecordedPayments(
    String employeeId,
  ) async {
    final id = employeeId.trim();
    if (id.isEmpty) return const PayrollRecordedPaymentCount.known(0);
    try {
      final page =
          await _store.readLineExpenseIds(id, limit: _expenseIdCeiling);
      // **Por encima del techo no se afirma nada.** Antes esto paginaba con
      // `range`, y eso NO evita saltos ni duplicados: entre una página y la
      // siguiente el conjunto puede cambiar, y `id` es un UUID aleatorio, así
      // que ordenar por él tampoco da una frontera estable. Una lectura y un
      // conteo, o `unavailable`.
      if (page.exceededLimit) {
        return const PayrollRecordedPaymentCount.unavailable();
      }
      final expenseIds = <String>{...page.ids}
        ..removeWhere((value) => value.trim().isEmpty);
      if (expenseIds.isEmpty) return const PayrollRecordedPaymentCount.known(0);
      // **Un solo `count(exact)` del servidor**, sin lotes ni sumas: el número
      // que devuelve es de un instante, no la suma de varios. Sumar dos
      // conteos tomados en momentos distintos habría sido otra exactitud
      // fingida.
      final total = await _store.countPaymentsForExpenses(
        expenseIds.toList(growable: false)..sort(),
      );
      return PayrollRecordedPaymentCount.known(total);
    } catch (_) {
      // Es un aviso, no una decisión: si no se puede contar, no se inventa un
      // número. Se dice que no se sabe, y quien pinta decide qué callar.
      return const PayrollRecordedPaymentCount.unavailable();
    }
  }

  /// Aplica el cambio con guard optimista sobre `updated_at`.
  ///
  /// **`expectedUpdatedAt` viaja como el texto exacto que devolvió la lectura**,
  /// sin pasar por `DateTime`: convertir y volver a serializar pierde
  /// microsegundos y el guard dejaría de calzar consigo mismo.
  Future<PayrollEmployeePaymentWriteOutcome> apply({
    required PayrollEmployeePaymentSnapshot expected,
    required String methodId,
    required String methodCode,
    // **Sin valor por defecto, a propósito.** Con `= true`, un llamador que lo
    // omitiera **borraba los tres campos bancarios** — exactamente el defecto
    // destructivo que este comando vino a cerrar, reintroducido como
    // comodidad. Exigirlo convierte ese olvido en un error de compilación, y
    // quien decide es `PayrollMethodDraft.touchesBankAccount`, que lo deriva
    // del método elegido.
    required bool touchesBankAccount,
    String? bankName,
    BankAccountType? bankAccountType,
    String? bankAccountNumber,
  }) async {
    String? clean(String? value) {
      final trimmed = value?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    final cleanMethodId = methodId.trim();
    final cleanMethodCode = methodCode.trim().toLowerCase();
    if (expected.employeeId.trim().isEmpty ||
        expected.tenantId.trim().isEmpty ||
        expected.updatedAtRaw.trim().isEmpty ||
        !expected.hasCompleteRow ||
        cleanMethodId.isEmpty ||
        (cleanMethodCode != 'cash' && cleanMethodCode != 'transfer') ||
        (cleanMethodCode == 'transfer') != touchesBankAccount) {
      return const PayrollEmployeePaymentWriteOutcome(
        status: PayrollEmployeePaymentWriteStatus.rejected,
      );
    }

    // `methodCode` no viaja al RPC ni compite con el catálogo: el servidor
    // sigue siendo quien deriva el código desde el método bloqueado. Sí expresa
    // la intención visible de la hoja, por lo que debe ser coherente con los
    // campos enviados y coincidir con el recibo antes de anunciar «guardado».

    final Map<String, dynamic> row;
    try {
      row = await _store.setPaymentMethod(
        employeeId: expected.employeeId,
        expectedUpdatedAt: expected.updatedAtRaw,
        methodId: cleanMethodId,
        bankName: touchesBankAccount ? clean(bankName) : null,
        bankAccountType:
            touchesBankAccount ? BankAccountType.encode(bankAccountType) : null,
        bankAccountNumber: touchesBankAccount ? clean(bankAccountNumber) : null,
      );
    } on PayrollEmployeePaymentStoreException catch (error) {
      // **Nunca se propaga el texto crudo del servidor**: dice nombres de
      // tablas y constraints que no significan nada para quien opera.
      final status = classifyStoreFailure(error.code);
      if (status == PayrollEmployeePaymentWriteStatus.versionConflict) {
        // El RPC ya garantizó que no escribió. La relectura sólo enriquece el
        // desenlace con la versión vigente; que falle no vuelve ambiguo el
        // rechazo 40001 del servidor.
        final reread = await read(expected.employeeId);
        return PayrollEmployeePaymentWriteOutcome(
          status: status,
          snapshot: reread.snapshot,
        );
      }
      return PayrollEmployeePaymentWriteOutcome(
        status: status,
      );
    } catch (_) {
      // Transporte: no se sabe si el servidor alcanzó a escribir. Se dice así.
      return const PayrollEmployeePaymentWriteOutcome(
        status: PayrollEmployeePaymentWriteStatus.unreachable,
      );
    }

    final snapshot = PayrollEmployeePaymentSnapshot.fromRow(row);
    final expectedBankName = touchesBankAccount ? clean(bankName) : null;
    final expectedBankType =
        touchesBankAccount ? BankAccountType.encode(bankAccountType) : null;
    final expectedBankNumber =
        touchesBankAccount ? clean(bankAccountNumber) : null;
    final receiptMatchesIdentity = snapshot.hasCompleteRow &&
        snapshot.employeeId == expected.employeeId &&
        snapshot.tenantId == expected.tenantId &&
        snapshot.updatedAtRaw.isNotEmpty &&
        snapshot.updatedAtRaw != expected.updatedAtRaw &&
        snapshot.preferredMethodId == cleanMethodId;
    final receiptMatchesMethod =
        snapshot.preferredMethodLegacy == cleanMethodCode &&
            switch (cleanMethodCode) {
              'cash' => snapshot.bankName == expected.bankName &&
                  snapshot.bankAccountType == expected.bankAccountType &&
                  snapshot.bankAccountNumber == expected.bankAccountNumber,
              'transfer' => snapshot.bankName == expectedBankName &&
                  snapshot.bankAccountType == expectedBankType &&
                  snapshot.bankAccountNumber == expectedBankNumber,
              _ => false,
            };
    if (!receiptMatchesIdentity || !receiptMatchesMethod) {
      // El servidor pudo haber escrito pero no devolvió el comprobante exacto
      // que permite afirmarlo. Igual que un ACK perdido, exige releer antes de
      // repetir; jamás se anuncia como guardado.
      return const PayrollEmployeePaymentWriteOutcome(
        status: PayrollEmployeePaymentWriteStatus.unreachable,
      );
    }

    return PayrollEmployeePaymentWriteOutcome(
      status: PayrollEmployeePaymentWriteStatus.applied,
      snapshot: snapshot,
    );
  }
}

/// Traduce el `SQLSTATE` del servidor al desenlace que la pantalla puede
/// afirmar sin mentir.
///
/// **Antes, todo lo que no fuera `42501` caía en `rejected`**, y la pantalla
/// decía «el tipo de cuenta o el método no son válidos». Para un timeout, un
/// corte de red o un 500 eso es un **diagnóstico falso sobre el dato del
/// operador**: lo manda a corregir algo que estaba bien.
///
/// Las familias que sí hablan del dato son la **clase 22** (argumento o
/// representación inválida) y la **clase 23** de PostgreSQL —
/// *integrity constraint violation*: `not_null`, `foreign_key`, `unique`,
/// `check`, `exclusion`—. Ahí vive `employees_bank_account_type_check`, que es
/// el rechazo real que esta hoja puede provocar.
///
/// `42501` es *insufficient_privilege*. `40001` es el guard de versión del RPC
/// y `P0002` su desenlace opaco de ficha ausente o fuera del tenant.
///
/// Todo lo demás —transporte, disponibilidad, errores del servidor— es «no se
/// sabe si escribió», que es lo que significa
/// [PayrollEmployeePaymentWriteStatus.unreachable].
@visibleForTesting
PayrollEmployeePaymentWriteStatus classifyStoreFailure(String? code) {
  final normalized = code?.trim().toUpperCase() ?? '';
  if (normalized == '42501') {
    return PayrollEmployeePaymentWriteStatus.notAuthorized;
  }
  if (normalized == '40001') {
    return PayrollEmployeePaymentWriteStatus.versionConflict;
  }
  if (normalized == 'P0002') {
    return PayrollEmployeePaymentWriteStatus.missing;
  }
  if (normalized.length == 5 &&
      (normalized.startsWith('22') || normalized.startsWith('23'))) {
    return PayrollEmployeePaymentWriteStatus.rejected;
  }
  return PayrollEmployeePaymentWriteStatus.unreachable;
}

/// Cuántos pagos ya registrados tiene la persona — o que no se pudo saber.
///
/// Existe porque `0` y «falló la lectura» **no son el mismo hecho**, y sobre
/// dinero ya pagado la diferencia importa: una dice que no le han pagado nunca,
/// la otra no dice nada.
@immutable
class PayrollRecordedPaymentCount {
  const PayrollRecordedPaymentCount._(this.value);

  /// `int` y no `int?`: «conocido» no puede construirse sin número.
  const PayrollRecordedPaymentCount.known(int count) : this._(count);
  const PayrollRecordedPaymentCount.unavailable() : this._(null);

  /// `null` cuando no se pudo contar. No es cero.
  final int? value;

  bool get isKnown => value != null;

  /// Sólo `true` con un conteo **conocido y mayor que cero**: es la condición
  /// para afirmar algo sobre pagos anteriores.
  bool get hasRecordedPayments => (value ?? 0) > 0;

  @override
  bool operator ==(Object other) =>
      other is PayrollRecordedPaymentCount && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value == null
      ? 'PayrollRecordedPaymentCount.unavailable'
      : 'known($value)';
}

enum PayrollEmployeePaymentWriteStatus {
  applied,

  /// El servidor rechazó el dato (por ejemplo, un `CHECK` violado).
  rejected,

  /// No se pudo hablar con el servidor: **no se sabe** si escribió.
  unreachable,

  /// Otro guardó primero. El operador tiene que volver a mirar antes de decidir.
  versionConflict,

  /// Puede leer la ficha, no editarla. No es un error: es el permiso real.
  notAuthorized,

  /// La ficha ya no está.
  missing,
}

class PayrollEmployeePaymentWriteOutcome {
  const PayrollEmployeePaymentWriteOutcome({
    required this.status,
    this.snapshot,
  });

  final PayrollEmployeePaymentWriteStatus status;
  final PayrollEmployeePaymentSnapshot? snapshot;

  bool get isApplied => status == PayrollEmployeePaymentWriteStatus.applied;
}

class PayrollEmployeePaymentSnapshot {
  const PayrollEmployeePaymentSnapshot({
    required this.employeeId,
    required this.tenantId,
    required this.updatedAtRaw,
    required this.hasCompleteRow,
    this.preferredMethodId,
    this.preferredMethodLegacy,
    this.bankName,
    this.bankAccountType,
    this.bankAccountNumber,
  });

  static const Set<String> _requiredRowKeys = <String>{
    'id',
    'tenant_id',
    'updated_at',
    'preferred_payment_method',
    'preferred_payment_method_id',
    'bank_name',
    'bank_account_type',
    'bank_account_number',
  };

  factory PayrollEmployeePaymentSnapshot.fromRow(Map<String, dynamic> row) {
    String? text(String key) {
      final value = row[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return PayrollEmployeePaymentSnapshot(
      employeeId: row['id']?.toString() ?? '',
      tenantId: row['tenant_id']?.toString() ?? '',
      // Texto crudo a propósito: es la versión del guard, no una fecha que se
      // muestre.
      updatedAtRaw: row['updated_at']?.toString() ?? '',
      hasCompleteRow: _requiredRowKeys.every(row.containsKey),
      preferredMethodId: text('preferred_payment_method_id'),
      preferredMethodLegacy: text('preferred_payment_method'),
      bankName: text('bank_name'),
      bankAccountType: text('bank_account_type'),
      bankAccountNumber: text('bank_account_number'),
    );
  }

  final String employeeId;
  final String tenantId;
  final String updatedAtRaw;

  /// `NULL` es un valor conocido; una clave ausente es un recibo truncado.
  /// El snapshot conserva esa diferencia aunque ambos se representen como
  /// `null` en los campos opcionales.
  final bool hasCompleteRow;
  final String? preferredMethodId;
  final String? preferredMethodLegacy;
  final String? bankName;
  final String? bankAccountType;
  final String? bankAccountNumber;

  /// Las dos columnas de preferencia dicen cosas distintas.
  ///
  /// No se corrige sola ni se oculta: la pantalla la muestra, porque el
  /// trabajador con `transfer` en texto y `check` en el FK existe hoy en
  /// producción y es justamente el que Nóminas manda a configurar.
  bool disagreesWith(String? methodCodeOfPreferredId) {
    if (preferredMethodId == null) return preferredMethodLegacy != null;
    if (methodCodeOfPreferredId == null) return true;
    return preferredMethodLegacy != null &&
        preferredMethodLegacy != methodCodeOfPreferredId;
  }
}

enum PayrollEmployeePaymentReadStatus {
  loaded,

  /// No existe, o no se puede ver. Desde el cliente no se distinguen.
  missing,

  /// La lectura falló. No se sabe qué hay.
  unavailable,
}

class PayrollEmployeePaymentReadOutcome {
  const PayrollEmployeePaymentReadOutcome({
    required this.status,
    this.snapshot,
  });

  final PayrollEmployeePaymentReadStatus status;
  final PayrollEmployeePaymentSnapshot? snapshot;
}

/// Lo único que el comando necesita de la base.
///
/// Existe para que la conducta —qué parámetros viajan al RPC y qué pasa ante
/// cada error— se pueda probar sin una base detrás. Antes eso se
/// verificaba leyendo el **texto fuente** del comando, que es un contrato que
/// se rompe en cuanto alguien escribe lo mismo de otra forma.
abstract class PayrollEmployeePaymentStore {
  Future<List<Map<String, dynamic>>> readEmployee(String employeeId);

  Future<Map<String, dynamic>> setPaymentMethod({
    required String employeeId,
    required String expectedUpdatedAt,
    required String methodId,
    String? bankName,
    String? bankAccountType,
    String? bankAccountNumber,
  });

  /// Los `expense_id` de las líneas del trabajador, **en una sola lectura
  /// acotada**.
  ///
  /// Devuelve además si el conjunto real supera [limit]. No pagina: paginar
  /// desde el cliente sin una consulta atómica del servidor no puede garantizar
  /// que no se salte ni duplique una fila, y afirmar lo contrario fue
  /// exactamente el defecto que este contrato vino a cerrar.
  Future<PayrollLineExpenseIds> readLineExpenseIds(
    String employeeId, {
    required int limit,
  });

  Future<int> countPaymentsForExpenses(List<String> expenseIds);
}

/// Resultado de la lectura acotada de gastos.
@immutable
class PayrollLineExpenseIds {
  const PayrollLineExpenseIds({
    required this.ids,
    required this.exceededLimit,
  });

  final List<String> ids;

  /// `true` cuando el trabajador tiene **más** líneas de las que el techo
  /// admite. Con esto puesto, [ids] está incompleto y no se puede contar.
  final bool exceededLimit;
}

/// Error del servidor, ya despojado de su texto crudo.
///
/// El mensaje del servidor nombra tablas y constraints que no significan nada
/// para quien opera; se conserva para el registro, nunca para la pantalla.
class PayrollEmployeePaymentStoreException implements Exception {
  const PayrollEmployeePaymentStoreException({
    required this.code,
    required this.message,
  });

  final String? code;
  final String message;

  @override
  String toString() => 'PayrollEmployeePaymentStoreException($code)';
}

class _SupabaseEmployeePaymentStore implements PayrollEmployeePaymentStore {
  _SupabaseEmployeePaymentStore(this._db);

  final DatabaseService _db;

  SupabaseClient get _client => _db.supabase;

  static const String _columns = 'id,tenant_id,updated_at,'
      'preferred_payment_method,preferred_payment_method_id,'
      'bank_name,bank_account_type,bank_account_number';

  @override
  Future<List<Map<String, dynamic>>> readEmployee(String employeeId) async {
    return _guard(
      () => _client.from('employees').select(_columns).eq('id', employeeId),
    );
  }

  @override
  Future<Map<String, dynamic>> setPaymentMethod({
    required String employeeId,
    required String expectedUpdatedAt,
    required String methodId,
    String? bankName,
    String? bankAccountType,
    String? bankAccountNumber,
  }) async {
    try {
      final response = await _client.rpc(
        'set_employee_payroll_payment_method',
        params: <String, dynamic>{
          'p_employee_id': employeeId,
          'p_expected_updated_at': expectedUpdatedAt,
          'p_method_id': methodId,
          'p_bank_name': bankName,
          'p_bank_account_type': bankAccountType,
          'p_bank_account_number': bankAccountNumber,
        },
      );
      if (response is Map<String, dynamic>) return response;
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      throw const PayrollEmployeePaymentStoreException(
        code: null,
        message: 'invalid_payment_method_receipt',
      );
    } on PostgrestException catch (error) {
      throw PayrollEmployeePaymentStoreException(
        code: error.code,
        message: error.message,
      );
    }
  }

  @override
  Future<PayrollLineExpenseIds> readLineExpenseIds(
    String employeeId, {
    required int limit,
  }) async {
    try {
      // **`count(exact)` junto al `select`, y el techo lo decide ese conteo —
      // no el largo de lo que llegó.** PostgREST aplica su propio `max-rows`,
      // así que medir el desborde por `rows.length` se puede engañar solo: si
      // el servidor recorta antes del límite, el cliente creería que cupo.
      // `count` viene de la cabecera `Content-Range` y es el total real.
      final response = await _client
          .from('payroll_voucher_lines')
          .select('expense_id')
          .eq('employee_id', employeeId)
          .limit(limit)
          .count(CountOption.exact);
      final ids = <String>[];
      for (final row in response.data) {
        if (row['expense_id']?.toString() case final value?) ids.add(value);
      }
      return PayrollLineExpenseIds(
        ids: ids,
        exceededLimit: response.count > limit || ids.length < response.count,
      );
    } on PostgrestException catch (error) {
      throw PayrollEmployeePaymentStoreException(
        code: error.code,
        message: error.message,
      );
    }
  }

  @override
  Future<int> countPaymentsForExpenses(List<String> expenseIds) async {
    // `count(exact)` lo resuelve el servidor: no devuelve filas, así que
    // ningún tope de paginación puede recortarlo.
    try {
      return await _client
          .from('expense_payments')
          .count(CountOption.exact)
          .inFilter('expense_id', expenseIds);
    } on PostgrestException catch (error) {
      throw PayrollEmployeePaymentStoreException(
        code: error.code,
        message: error.message,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _guard(
    Future<List<Map<String, dynamic>>> Function() run,
  ) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw PayrollEmployeePaymentStoreException(
        code: error.code,
        message: error.message,
      );
    }
  }
}
