import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/storage/models/app_stored_file.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_advance_evidence_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_advance_registration_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';

/// La UI productiva de Nóminas **no** puede volver a la ruta legacy.
///
/// `registerEmployeeAdvance` (`register_employee_advance_v2`) no lleva motivo
/// estructurado ni comprobante inmutable. El contrato vigente es
/// **capability → evidencia confirmada → `register_employee_advance_v3`**, y lo
/// ordena `PayrollAdvanceRegistrationService`. Esta prueba vigila el orden y el
/// hecho de que la pantalla lo use: es barata y ataja una regresión que en
/// producción sólo se vería como un anticipo sin auditoría.
void main() {
  test('la página productiva no menciona la ruta legacy v2', () async {
    final source =
        await _read('lib/modules/hr/payroll/payroll_redesign_page.dart');
    // Se ignoran los comentarios: el archivo EXPLICA por qué no la usa.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      code.contains('registerEmployeeAdvance('),
      isFalse,
      reason: 'la UI productiva volvió a llamar la ruta legacy v2',
    );
    expect(
      code.contains('PayrollAdvanceRegistrationService('),
      isTrue,
      reason: 'la acción productiva debe instanciar el coordinador v3',
    );
  });

  test('sin capability no se sube NADA y no se registra dinero', () async {
    final writer = _RecordingWriter(supported: false);
    final store = _ExplodingStore();
    final service = PayrollAdvanceRegistrationService.withDependencies(
      writer: writer,
      evidenceService: PayrollAdvanceEvidenceService(store: store),
    );

    await expectLater(
      () => service.register(
        employeeId: 'e-1',
        employeeName: 'Rodrigo',
        amount: 30000,
        paymentMethodId: 'm-1',
        paymentAccountId: 'a-1',
        paidAt: DateTime(2026, 7, 30),
        reasonCode: PayrollAdvanceReasonCode.shortWorkweek,
        reasonExplanation: 'Se fue el miércoles',
        workEndedOn: DateTime(2026, 7, 29),
        originalReceipt: PayrollAdvanceOriginalReceiptDraft(
          bytes: Uint8List.fromList(
            const <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
          ),
          fileName: 'vale.pdf',
        ),
        operationKey: 'adv-0000-0001',
      ),
      throwsA(isA<PayrollVoucherPreflightException>()),
    );

    // El orden es el contrato: primero se pregunta, y sólo después se sube.
    expect(
      store.calls,
      0,
      reason: 'no se sube un comprobante antes de saber si v3 existe',
    );
    expect(writer.registered, 0, reason: 'no se registró dinero');
  });
}

Future<String> _read(String path) async {
  return await File(path).readAsString();
}

class _RecordingWriter implements PayrollAuditedAdvanceWriter {
  _RecordingWriter({required this.supported});
  final bool supported;
  int registered = 0;

  @override
  Future<bool> supportsStructuredEmployeeAdvanceAudit({
    required String employeeId,
  }) async =>
      supported;

  @override
  Future<PayrollAdvanceRegistrationReceipt> registerAuditedEmployeeAdvance({
    required String employeeId,
    required double amount,
    required String paymentMethodId,
    String? paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
    required PayrollAdvanceReasonCode reasonCode,
    required String reasonExplanation,
    DateTime? workEndedOn,
    PayrollAdvanceEvidenceReference? evidence,
    String? operationKey,
  }) async {
    registered++;
    return const PayrollAdvanceRegistrationReceipt(
      advanceId: 'adv-1',
      replayed: false,
    );
  }
}

class _ExplodingStore implements PayrollAdvanceEvidenceFileStore {
  int calls = 0;

  @override
  Future<AppStoredFile> saveImmutableEvidenceFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required AppFileContext context,
    required String operationKey,
    required String sha256Hex,
  }) async {
    calls++;
    throw StateError('no debería subirse nada sin capability');
  }
}
