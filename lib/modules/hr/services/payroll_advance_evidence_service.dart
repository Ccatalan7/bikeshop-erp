import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';

@immutable
class PayrollAdvanceEvidenceUpload {
  const PayrollAdvanceEvidenceUpload({
    required this.appFileId,
    required this.sha256,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String appFileId;
  final String sha256;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
}

abstract interface class PayrollAdvanceEvidenceFileStore {
  Future<AppStoredFile> saveImmutableEvidenceFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required AppFileContext context,
    required String operationKey,
    required String sha256Hex,
  });
}

class PayrollAdvanceEvidenceService {
  PayrollAdvanceEvidenceService({PayrollAdvanceEvidenceFileStore? store})
      : _store = store ?? _AppFileStorageEvidenceStore();

  final PayrollAdvanceEvidenceFileStore _store;

  /// Uploads the original receipt under the exact operation identity that the
  /// v3 money command will later verify. Upload and money registration remain
  /// separate on purpose: callers keep the bytes in memory until submit and
  /// must not delete an uploaded file after an ambiguous network result.
  Future<PayrollAdvanceEvidenceUpload> uploadOriginalReceipt({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required String operationKey,
    required String employeeId,
    required String employeeName,
  }) async {
    final receipt = PayrollAdvanceReceiptPolicyV1.validate(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final cleanFileName = receipt.fileName;
    final cleanOperationKey = operationKey.trim();
    final cleanEmployeeId = employeeId.trim();
    final cleanEmployeeName = employeeName.trim();
    if (operationKey != cleanOperationKey ||
        !RegExp(r'^[A-Za-z0-9:_-]{8,200}$').hasMatch(cleanOperationKey) ||
        cleanEmployeeId.isEmpty ||
        cleanEmployeeName.isEmpty) {
      throw ArgumentError('Invalid payroll advance receipt upload');
    }

    final digest = sha256.convert(bytes).toString();
    final saved = await _store.saveImmutableEvidenceFile(
      bytes: bytes,
      fileName: cleanFileName,
      mimeType: receipt.mimeType,
      operationKey: cleanOperationKey,
      sha256Hex: digest,
      context: AppFileContext(
        sourceType: 'payroll_advance',
        sourceId: cleanOperationKey,
        sourceRoute: Uri(
          path: '/hr/payroll',
          queryParameters: <String, String>{
            'scope': 'advances',
            'employee': cleanEmployeeId,
          },
        ).toString(),
        contextType: 'payroll_advance_operation',
        contextId: cleanOperationKey,
        contextTitle: 'Comprobante de anticipo',
        contextSubtitle: cleanEmployeeName,
        tags: const <String>['payroll', 'advance', 'receipt'],
        metadata: <String, dynamic>{
          'sha256': digest,
          'employee_id': cleanEmployeeId,
          'operation_key': cleanOperationKey,
        },
      ),
    );

    final savedDigest = saved.metadata['sha256']?.toString().toLowerCase();
    final savedEmployeeId = saved.metadata['employee_id']?.toString();
    final savedOperationKey = saved.metadata['operation_key']?.toString();
    final receiptMatches = saved.id.trim().isNotEmpty &&
        saved.sizeBytes == bytes.length &&
        saved.sourceType == 'payroll_advance' &&
        saved.sourceId == cleanOperationKey &&
        saved.contextType == 'payroll_advance_operation' &&
        saved.contextId == cleanOperationKey &&
        savedEmployeeId == cleanEmployeeId &&
        savedOperationKey == cleanOperationKey &&
        savedDigest == digest;
    if (!receiptMatches) {
      throw StateError(
        'El almacenamiento no confirmó íntegramente el comprobante.',
      );
    }

    return PayrollAdvanceEvidenceUpload(
      appFileId: saved.id,
      sha256: digest,
      fileName: saved.fileName,
      mimeType: saved.mimeType,
      sizeBytes: saved.sizeBytes,
    );
  }
}

class _AppFileStorageEvidenceStore implements PayrollAdvanceEvidenceFileStore {
  @override
  Future<AppStoredFile> saveImmutableEvidenceFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required AppFileContext context,
    required String operationKey,
    required String sha256Hex,
  }) {
    return AppFileStorageService.instance.saveImmutableEvidenceFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      context: context,
      operationKey: operationKey,
      sha256Hex: sha256Hex,
    );
  }
}
