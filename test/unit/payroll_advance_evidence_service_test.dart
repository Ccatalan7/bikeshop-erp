import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_advance_evidence_service.dart';
import 'package:vinabike_erp/modules/storage/models/app_stored_file.dart';
import 'package:vinabike_erp/modules/storage/services/app_file_storage_service.dart';

void main() {
  test('receipt upload is scoped to the audited advance operation', () async {
    final store = _EvidenceStore();
    final service = PayrollAdvanceEvidenceService(store: store);

    final bytes = _receiptBytes('pdf');
    final upload = await service.uploadOriginalReceipt(
      bytes: bytes,
      fileName: ' comprobante.pdf ',
      mimeType: 'application/pdf',
      operationKey: 'advance-audit-upload-0001',
      employeeId: 'employee-1',
      employeeName: 'Rocío Maldonado',
    );

    final expectedDigest = sha256.convert(bytes).toString();
    expect(upload.appFileId, 'file-1');
    expect(upload.sha256, expectedDigest);
    expect(upload.fileName, 'comprobante.pdf');
    expect(store.calls, 1);
    expect(store.context?.sourceType, 'payroll_advance');
    expect(store.context?.sourceId, 'advance-audit-upload-0001');
    expect(store.context?.contextType, 'payroll_advance_operation');
    expect(store.context?.contextId, 'advance-audit-upload-0001');
    expect(store.context?.contextSubtitle, 'Rocío Maldonado');
    expect(
      store.context?.sourceRoute,
      '/hr/payroll?scope=advances&employee=employee-1',
    );
    expect(store.context?.metadata, <String, dynamic>{
      'sha256': expectedDigest,
      'employee_id': 'employee-1',
      'operation_key': 'advance-audit-upload-0001',
    });
  });

  test('invalid upload identity is rejected before storage', () async {
    final store = _EvidenceStore();
    final service = PayrollAdvanceEvidenceService(store: store);

    await expectLater(
      service.uploadOriginalReceipt(
        bytes: _receiptBytes('pdf'),
        fileName: 'receipt.pdf',
        operationKey: 'short',
        employeeId: 'employee-1',
        employeeName: 'Rocío Maldonado',
      ),
      throwsArgumentError,
    );
    expect(store.calls, 0);
  });

  test('a noncanonical operation key is rejected before storage', () async {
    final store = _EvidenceStore();
    final service = PayrollAdvanceEvidenceService(store: store);

    await expectLater(
      service.uploadOriginalReceipt(
        bytes: _receiptBytes('pdf'),
        fileName: 'receipt.pdf',
        operationKey: ' advance-audit-upload-0001 ',
        employeeId: 'employee-1',
        employeeName: 'Rocío Maldonado',
      ),
      throwsArgumentError,
    );
    expect(store.calls, 0);
  });

  test('receipt origin deep link round-trips an encoded employee identity',
      () async {
    final store = _EvidenceStore();
    final service = PayrollAdvanceEvidenceService(store: store);

    await service.uploadOriginalReceipt(
      bytes: _receiptBytes('pdf'),
      fileName: 'receipt.pdf',
      mimeType: 'application/pdf',
      operationKey: 'advance-audit-route-0001',
      employeeId: 'employee/one + two',
      employeeName: 'Rocio Maldonado',
    );

    final route = Uri.parse(store.context!.sourceRoute!);
    expect(route.path, '/hr/payroll');
    expect(route.queryParameters, <String, String>{
      'scope': 'advances',
      'employee': 'employee/one + two',
    });
  });

  test('a crossed storage acknowledgement is never exposed as evidence',
      () async {
    final store = _EvidenceStore()..crossReceipt = true;
    final service = PayrollAdvanceEvidenceService(store: store);

    await expectLater(
      service.uploadOriginalReceipt(
        bytes: _receiptBytes('pdf'),
        fileName: 'receipt.pdf',
        operationKey: 'advance-audit-upload-0002',
        employeeId: 'employee-1',
        employeeName: 'Rocío Maldonado',
      ),
      throwsStateError,
    );
  });

  for (final crossedMetadataKey in const <String>[
    'employee_id',
    'operation_key',
  ]) {
    test('crossed $crossedMetadataKey metadata is never exposed as evidence',
        () async {
      final store = _EvidenceStore()..crossedMetadataKey = crossedMetadataKey;
      final service = PayrollAdvanceEvidenceService(store: store);

      await expectLater(
        service.uploadOriginalReceipt(
          bytes: _receiptBytes('pdf'),
          fileName: 'receipt.pdf',
          operationKey: 'advance-audit-upload-0003',
          employeeId: 'employee-1',
          employeeName: 'Rocío Maldonado',
        ),
        throwsStateError,
      );
    });
  }

  for (final sample in const <(String, String, String)>[
    ('pdf', 'receipt.pdf', 'application/pdf'),
    ('jpeg', 'receipt.JPG', 'image/jpeg'),
    ('png', 'receipt.png', 'image/png'),
    ('webp', 'receipt.webp', 'image/webp'),
  ]) {
    test('accepts matching ${sample.$1} signature, extension and MIME',
        () async {
      final store = _EvidenceStore();
      final service = PayrollAdvanceEvidenceService(store: store);

      final upload = await service.uploadOriginalReceipt(
        bytes: _receiptBytes(sample.$1),
        fileName: sample.$2,
        mimeType: sample.$3,
        operationKey: 'advance-audit-format-${sample.$1}-0001',
        employeeId: 'employee-1',
        employeeName: 'Rocio Maldonado',
      );

      expect(upload.mimeType, sample.$3);
      expect(store.calls, 1);
    });
  }

  test('accepts exactly 12 MiB and canonicalizes MIME parameters', () async {
    final store = _EvidenceStore();
    final service = PayrollAdvanceEvidenceService(store: store);
    final bytes = _receiptBytes(
      'pdf',
      length: PayrollAdvanceReceiptPolicyV1.maxSizeBytes,
    );

    final upload = await service.uploadOriginalReceipt(
      bytes: bytes,
      fileName: 'receipt.PDF',
      mimeType: ' Application/PDF; charset=binary ',
      operationKey: 'advance-audit-boundary-0001',
      employeeId: 'employee-1',
      employeeName: 'Rocio Maldonado',
    );

    expect(upload.sizeBytes, PayrollAdvanceReceiptPolicyV1.maxSizeBytes);
    expect(upload.mimeType, 'application/pdf');
    expect(store.calls, 1);
  });

  for (final invalid in <(String, Uint8List, String, String?)>[
    ('empty', Uint8List(0), 'receipt.pdf', 'application/pdf'),
    (
      'one byte above 12 MiB',
      _receiptBytes(
        'pdf',
        length: PayrollAdvanceReceiptPolicyV1.maxSizeBytes + 1,
      ),
      'receipt.pdf',
      'application/pdf'
    ),
    ('GIF', _receiptBytes('gif'), 'receipt.gif', 'image/gif'),
    ('HEIC', _receiptBytes('heic'), 'receipt.heic', 'image/heic'),
    ('TXT', _receiptBytes('txt'), 'receipt.txt', 'text/plain'),
    (
      'crossed extension',
      _receiptBytes('pdf'),
      'receipt.png',
      'application/pdf'
    ),
    ('crossed MIME', _receiptBytes('pdf'), 'receipt.pdf', 'image/png'),
    (
      'crossed signature',
      _receiptBytes('jpeg'),
      'receipt.pdf',
      'application/pdf'
    ),
  ]) {
    test('rejects ${invalid.$1} before storage', () async {
      final store = _EvidenceStore();
      final service = PayrollAdvanceEvidenceService(store: store);

      await expectLater(
        service.uploadOriginalReceipt(
          bytes: invalid.$2,
          fileName: invalid.$3,
          mimeType: invalid.$4,
          operationKey: 'advance-audit-invalid-format-0001',
          employeeId: 'employee-1',
          employeeName: 'Rocio Maldonado',
        ),
        throwsArgumentError,
      );
      expect(store.calls, 0);
    });
  }

  test('payroll evidence rows and their storage namespace are write-once', () {
    final exactRow = _storedFile(
      sourceType: 'payroll_advance',
      contextType: 'payroll_advance_operation',
      storagePath: 'tenant-1/manual/receipt.pdf',
    );
    final namespaceOnly = _storedFile(
      sourceType: 'manual',
      contextType: 'manual',
      storagePath: 'tenant-1/evidence/payroll_advance/receipt.pdf',
    );
    final ordinary = _storedFile(
      sourceType: 'manual',
      contextType: 'manual',
      storagePath: 'tenant-1/manual/receipt.pdf',
    );

    expect(
      AppFileStorageService.isImmutablePayrollAdvanceEvidence(exactRow),
      isTrue,
    );
    expect(
      AppFileStorageService.isImmutablePayrollAdvanceEvidence(namespaceOnly),
      isTrue,
    );
    expect(
      AppFileStorageService.isImmutablePayrollAdvanceEvidence(ordinary),
      isFalse,
    );
  });
}

Uint8List _receiptBytes(String format, {int? length}) {
  final signature = switch (format) {
    'pdf' => const <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
    'jpeg' => const <int>[0xFF, 0xD8, 0xFF, 0xE0],
    'png' => const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    'webp' => const <int>[
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
      ],
    'gif' => const <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
    'heic' => const <int>[
        0,
        0,
        0,
        0x18,
        0x66,
        0x74,
        0x79,
        0x70,
        0x68,
        0x65,
        0x69,
        0x63
      ],
    'txt' => const <int>[0x68, 0x6F, 0x6C, 0x61],
    _ => throw ArgumentError.value(format),
  };
  final bytes = Uint8List(length ?? signature.length);
  bytes.setRange(0, signature.length, signature);
  return bytes;
}

AppStoredFile _storedFile({
  required String sourceType,
  required String contextType,
  required String storagePath,
}) {
  final now = DateTime.utc(2026, 8, 1);
  return AppStoredFile(
    id: 'file-test',
    tenantId: 'tenant-1',
    uploadedBy: 'actor-1',
    fileName: 'receipt.pdf',
    storageBucket: 'vinabike-files',
    storagePath: storagePath,
    mimeType: 'application/pdf',
    sizeBytes: 3,
    sourceType: sourceType,
    sourceId: 'advance-audit-upload-test',
    sourceProvider: null,
    sourceRoute: '/hr/payroll',
    contextType: contextType,
    contextId: 'advance-audit-upload-test',
    contextTitle: 'Comprobante',
    contextSubtitle: 'Persona',
    tags: const <String>[],
    metadata: const <String, dynamic>{},
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

class _EvidenceStore implements PayrollAdvanceEvidenceFileStore {
  int calls = 0;
  bool crossReceipt = false;
  String? crossedMetadataKey;
  AppFileContext? context;

  @override
  Future<AppStoredFile> saveImmutableEvidenceFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required AppFileContext context,
    required String operationKey,
    required String sha256Hex,
  }) async {
    calls += 1;
    this.context = context;
    final now = DateTime.utc(2026, 8, 1);
    return AppStoredFile(
      id: 'file-1',
      tenantId: 'tenant-1',
      uploadedBy: 'actor-1',
      fileName: fileName,
      storageBucket: 'vinabike-files',
      storagePath: 'tenant-1/file-1-$fileName',
      mimeType: mimeType ?? 'application/octet-stream',
      sizeBytes: bytes.length,
      sourceType: context.sourceType,
      sourceId: context.sourceId,
      sourceProvider: context.sourceProvider,
      sourceRoute: context.sourceRoute,
      contextType: context.contextType,
      contextId: crossReceipt ? 'another-operation' : context.contextId,
      contextTitle: context.contextTitle,
      contextSubtitle: context.contextSubtitle,
      tags: context.tags,
      metadata: <String, dynamic>{
        ...context.metadata,
        if (crossedMetadataKey == 'employee_id')
          'employee_id': 'employee-crossed',
        if (crossedMetadataKey == 'operation_key')
          'operation_key': 'advance-audit-upload-crossed',
      },
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
  }
}
