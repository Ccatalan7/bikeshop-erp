import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_advance_evidence_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_advance_registration_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/modules/storage/models/app_stored_file.dart';
import 'package:vinabike_erp/modules/storage/services/app_file_storage_service.dart';

void main() {
  test('missing v3 bundle creates neither evidence nor money', () async {
    final writer = _Writer()..supported = false;
    final store = _EvidenceStore();
    final service = _service(writer: writer, store: store);

    await expectLater(
      _register(service),
      throwsA(
        isA<PayrollVoucherPreflightException>().having(
          (error) => error.kind,
          'kind',
          PayrollVoucherPreflightFailureKind.unavailable,
        ),
      ),
    );

    expect(writer.capabilityCalls, 1);
    expect(store.calls, 0);
    expect(writer.writeCalls, 0);
  });

  test('invalid reason is rejected before capability or evidence', () async {
    final writer = _Writer();
    final store = _EvidenceStore();
    final service = _service(writer: writer, store: store);

    await expectLater(
      _register(service, reasonExplanation: '  '),
      throwsA(
        isA<PayrollVoucherPreflightException>().having(
          (error) => error.kind,
          'kind',
          PayrollVoucherPreflightFailureKind.rejected,
        ),
      ),
    );

    expect(writer.capabilityCalls, 0);
    expect(store.calls, 0);
    expect(writer.writeCalls, 0);
  });

  test('capability, immutable upload and v3 execute in that order', () async {
    final events = <String>[];
    final writer = _Writer(events: events);
    final store = _EvidenceStore(events: events);
    final service = _service(writer: writer, store: store);

    final receipt = await _register(service);

    expect(receipt.advanceId, 'advance-1');
    expect(events, <String>['capability', 'upload', 'write']);
    expect(writer.evidence?.appFileId, 'file-1');
    expect(
      writer.evidence?.sha256,
      '21af8e71c8703196df7fe1ff901869a88fe64c07bbaa83d838efb45a52b4f303',
    );
    expect(writer.reasonCode, PayrollAdvanceReasonCode.requestedAdvance);
    expect(writer.reasonExplanation, 'Solicitud para locomoción');
  });

  test('an unconfirmed upload never reaches the money writer', () async {
    final writer = _Writer();
    final store = _EvidenceStore()..fail = true;
    final service = _service(writer: writer, store: store);

    await expectLater(
      _register(service),
      throwsA(
        isA<PayrollVoucherPreflightException>().having(
          (error) => error.kind,
          'kind',
          PayrollVoucherPreflightFailureKind.unavailable,
        ),
      ),
    );

    expect(store.calls, 1);
    expect(writer.writeCalls, 0);
  });

  for (final invalid in <(String, Uint8List, String, String?)>[
    ('empty', Uint8List(0), 'receipt.pdf', 'application/pdf'),
    (
      'one byte above 12 MiB',
      _pdfBytes(PayrollAdvanceReceiptPolicyV1.maxSizeBytes + 1),
      'receipt.pdf',
      'application/pdf'
    ),
    (
      'GIF',
      Uint8List.fromList(const <int>[0x47, 0x49, 0x46]),
      'receipt.gif',
      'image/gif'
    ),
    (
      'HEIC',
      Uint8List.fromList(const <int>[0x66, 0x74, 0x79, 0x70]),
      'receipt.heic',
      'image/heic'
    ),
    (
      'TXT',
      Uint8List.fromList(const <int>[0x68, 0x6F, 0x6C, 0x61]),
      'receipt.txt',
      'text/plain'
    ),
    ('crossed extension', _pdfBytes(), 'receipt.png', 'application/pdf'),
    ('crossed MIME', _pdfBytes(), 'receipt.pdf', 'image/png'),
  ]) {
    test('invalid ${invalid.$1} receipt reaches neither upload nor money',
        () async {
      final writer = _Writer();
      final store = _EvidenceStore();
      final service = _service(writer: writer, store: store);

      await expectLater(
        _register(
          service,
          receipt: PayrollAdvanceOriginalReceiptDraft(
            bytes: invalid.$2,
            fileName: invalid.$3,
            mimeType: invalid.$4,
          ),
        ),
        throwsA(
          isA<PayrollVoucherPreflightException>().having(
            (error) => error.kind,
            'kind',
            PayrollVoucherPreflightFailureKind.rejected,
          ),
        ),
      );

      expect(writer.capabilityCalls, 0);
      expect(store.calls, 0);
      expect(writer.writeCalls, 0);
    });
  }
}

PayrollAdvanceRegistrationService _service({
  required _Writer writer,
  required _EvidenceStore store,
}) {
  return PayrollAdvanceRegistrationService.withDependencies(
    writer: writer,
    evidenceService: PayrollAdvanceEvidenceService(store: store),
  );
}

Future<PayrollAdvanceRegistrationReceipt> _register(
  PayrollAdvanceRegistrationService service, {
  String reasonExplanation = 'Solicitud para locomoción',
  PayrollAdvanceOriginalReceiptDraft? receipt,
}) {
  return service.register(
    employeeId: 'employee-1',
    employeeName: 'Rocío Maldonado',
    amount: 25000,
    paymentMethodId: 'method-1',
    paymentAccountId: 'account-1',
    paidAt: DateTime.utc(2026, 8, 1),
    reasonCode: PayrollAdvanceReasonCode.requestedAdvance,
    reasonExplanation: reasonExplanation,
    operationKey: 'advance-audit-register-0001',
    originalReceipt: receipt ??
        PayrollAdvanceOriginalReceiptDraft(
          bytes: _pdfBytes(),
          fileName: 'receipt.pdf',
          mimeType: 'application/pdf',
        ),
  );
}

Uint8List _pdfBytes([int length = 6]) {
  const signature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D, 0x31];
  final bytes = Uint8List(length);
  bytes.setRange(0, signature.length, signature);
  return bytes;
}

class _Writer implements PayrollAuditedAdvanceWriter {
  _Writer({List<String>? events}) : events = events ?? <String>[];

  final List<String> events;
  bool supported = true;
  int capabilityCalls = 0;
  int writeCalls = 0;
  PayrollAdvanceEvidenceReference? evidence;
  PayrollAdvanceReasonCode? reasonCode;
  String? reasonExplanation;

  @override
  Future<bool> supportsStructuredEmployeeAdvanceAudit({
    required String employeeId,
  }) async {
    capabilityCalls += 1;
    events.add('capability');
    return supported;
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
  }) async {
    writeCalls += 1;
    events.add('write');
    this.evidence = evidence;
    this.reasonCode = reasonCode;
    this.reasonExplanation = reasonExplanation;
    return const PayrollAdvanceRegistrationReceipt(
      advanceId: 'advance-1',
      replayed: false,
    );
  }
}

class _EvidenceStore implements PayrollAdvanceEvidenceFileStore {
  _EvidenceStore({List<String>? events}) : events = events ?? <String>[];

  final List<String> events;
  int calls = 0;
  bool fail = false;

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
    events.add('upload');
    if (fail) throw StateError('upload unconfirmed');
    final now = DateTime.utc(2026, 8, 1);
    return AppStoredFile(
      id: 'file-1',
      tenantId: 'tenant-1',
      uploadedBy: 'actor-1',
      fileName: fileName,
      storageBucket: 'vinabike-files',
      storagePath: 'tenant-1/evidence/payroll_advance/receipt.pdf',
      mimeType: mimeType ?? 'application/octet-stream',
      sizeBytes: bytes.length,
      sourceType: context.sourceType,
      sourceId: context.sourceId,
      sourceProvider: context.sourceProvider,
      sourceRoute: context.sourceRoute,
      contextType: context.contextType,
      contextId: context.contextId,
      contextTitle: context.contextTitle,
      contextSubtitle: context.contextSubtitle,
      tags: context.tags,
      metadata: context.metadata,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
  }
}
