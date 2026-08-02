import 'package:flutter/foundation.dart';

import '../models/payroll_audit_read_models.dart';
import '../../storage/services/app_file_storage_service.dart';
import 'payroll_advance_evidence_service.dart';
import 'payroll_voucher_service.dart';

@immutable
class PayrollAdvanceOriginalReceiptDraft {
  const PayrollAdvanceOriginalReceiptDraft({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

abstract interface class PayrollAuditedAdvanceWriter {
  Future<bool> supportsStructuredEmployeeAdvanceAudit({
    required String employeeId,
  });

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
  });
}

/// Orders the audited-advance command so no immutable receipt is uploaded
/// before the exact v3 backend bundle is known to exist.
class PayrollAdvanceRegistrationService {
  PayrollAdvanceRegistrationService({
    required PayrollVoucherService voucherService,
    PayrollAdvanceEvidenceService? evidenceService,
  }) : this.withDependencies(
          writer: _PayrollVoucherAuditedAdvanceWriter(voucherService),
          evidenceService: evidenceService ?? PayrollAdvanceEvidenceService(),
        );

  @visibleForTesting
  PayrollAdvanceRegistrationService.withDependencies({
    required PayrollAuditedAdvanceWriter writer,
    required PayrollAdvanceEvidenceService evidenceService,
  })  : _writer = writer,
        _evidenceService = evidenceService;

  final PayrollAuditedAdvanceWriter _writer;
  final PayrollAdvanceEvidenceService _evidenceService;

  Future<PayrollAdvanceRegistrationReceipt> register({
    required String employeeId,
    required String employeeName,
    required double amount,
    required String paymentMethodId,
    required String paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
    required PayrollAdvanceReasonCode reasonCode,
    required String reasonExplanation,
    DateTime? workEndedOn,
    PayrollAdvanceOriginalReceiptDraft? originalReceipt,
    required String operationKey,
  }) async {
    final cleanEmployeeId = employeeId.trim();
    final cleanEmployeeName = employeeName.trim();
    final cleanOperationKey = operationKey.trim();
    final explanation = reasonExplanation.trim();
    PayrollAdvanceReceiptValidation? validatedReceipt;
    if (originalReceipt != null) {
      try {
        validatedReceipt = PayrollAdvanceReceiptPolicyV1.validate(
          bytes: originalReceipt.bytes,
          fileName: originalReceipt.fileName,
          mimeType: originalReceipt.mimeType,
        );
      } on ArgumentError catch (error) {
        throw PayrollVoucherPreflightException.rejected(
          error.message?.toString() ?? 'El comprobante no es válido.',
        );
      }
    }
    final inputIsValid = cleanEmployeeId.isNotEmpty &&
        cleanEmployeeName.isNotEmpty &&
        amount > 0 &&
        paymentMethodId.trim().isNotEmpty &&
        paymentAccountId.trim().isNotEmpty &&
        operationKey == cleanOperationKey &&
        RegExp(r'^[A-Za-z0-9:_-]{8,200}$').hasMatch(cleanOperationKey) &&
        explanation.isNotEmpty &&
        explanation.length <= 1000 &&
        ((reasonCode == PayrollAdvanceReasonCode.shortWorkweek) ==
            (workEndedOn != null));
    if (!inputIsValid) {
      throw const PayrollVoucherPreflightException.rejected(
        'Completa el motivo y los datos del anticipo antes de registrarlo.',
      );
    }

    final supported = await _writer.supportsStructuredEmployeeAdvanceAudit(
      employeeId: cleanEmployeeId,
    );
    if (!supported) {
      throw const PayrollVoucherPreflightException.unavailable(
        'La actualización de anticipos auditados aún no está instalada. '
        'No se subió ningún comprobante ni se registró dinero.',
      );
    }

    PayrollAdvanceEvidenceReference? evidence;
    if (originalReceipt != null) {
      try {
        final upload = await _evidenceService.uploadOriginalReceipt(
          bytes: originalReceipt.bytes,
          fileName: validatedReceipt!.fileName,
          mimeType: validatedReceipt.mimeType,
          operationKey: cleanOperationKey,
          employeeId: cleanEmployeeId,
          employeeName: cleanEmployeeName,
        );
        evidence = PayrollAdvanceEvidenceReference(
          appFileId: upload.appFileId,
          sha256: upload.sha256,
        );
      } catch (error) {
        debugPrint(
          '❌ [PayrollAdvanceRegistration] evidence preflight: $error',
        );
        throw const PayrollVoucherPreflightException.unavailable(
          'No pudimos confirmar el comprobante original. No se registró '
          'dinero; vuelve a intentarlo con el mismo archivo.',
        );
      }
    }

    return _writer.registerAuditedEmployeeAdvance(
      employeeId: cleanEmployeeId,
      amount: amount,
      paymentMethodId: paymentMethodId,
      paymentAccountId: paymentAccountId,
      paidAt: paidAt,
      reference: reference,
      notes: notes,
      reasonCode: reasonCode,
      reasonExplanation: explanation,
      workEndedOn: workEndedOn,
      evidence: evidence,
      operationKey: cleanOperationKey,
    );
  }
}

class _PayrollVoucherAuditedAdvanceWriter
    implements PayrollAuditedAdvanceWriter {
  const _PayrollVoucherAuditedAdvanceWriter(this._service);

  final PayrollVoucherService _service;

  @override
  Future<bool> supportsStructuredEmployeeAdvanceAudit({
    required String employeeId,
  }) {
    return _service.supportsStructuredEmployeeAdvanceAudit(
      employeeId: employeeId,
    );
  }

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
  }) {
    return _service.registerAuditedEmployeeAdvance(
      employeeId: employeeId,
      amount: amount,
      paymentMethodId: paymentMethodId,
      paymentAccountId: paymentAccountId,
      paidAt: paidAt,
      reference: reference,
      notes: notes,
      reasonCode: reasonCode,
      reasonExplanation: reasonExplanation,
      workEndedOn: workEndedOn,
      evidence: evidence,
      operationKey: operationKey,
    );
  }
}
