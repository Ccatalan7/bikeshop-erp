import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_models.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_payment_workspace_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

const _voucherId = '10000000-0000-4000-8000-000000000001';
const _lineOneId = '10000000-0000-4000-8000-000000000101';
const _lineTwoId = '10000000-0000-4000-8000-000000000102';
const _employeeOneId = '10000000-0000-4000-8000-000000000201';
const _employeeTwoId = '10000000-0000-4000-8000-000000000202';
const _transferMethodId = '20000000-0000-4000-8000-000000000001';
const _cashMethodId = '20000000-0000-4000-8000-000000000002';
const _otherMethodId = '20000000-0000-4000-8000-000000000003';
const _bankAccountId = '30000000-0000-4000-8000-000000000001';
const _cashAccountId = '30000000-0000-4000-8000-000000000002';
const _otherAccountId = '30000000-0000-4000-8000-000000000003';
const _expenseAccountId = '40000000-0000-4000-8000-000000000001';
const _reclassificationId = '60000000-0000-4000-8000-000000000101';
const _reclassificationJournalEntryId = '60000000-0000-4000-8000-000000000102';
const _fileDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _accountFingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response('{}', 200),
      ),
    );
  });

  group('PayrollPaymentWorkspaceService', () {
    test('confirms an exact CAS set of draft weeks and reads live versions',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.handler = (functionName, params) {
        expect(functionName, 'confirm_payroll_vouchers_v1');
        expect(params['p_operation_key'], 'approve-weeks-batch-0001');
        expect(params['p_vouchers'], <Object>[
          <String, dynamic>{
            'voucher_id': _voucherId,
            'expected_reconciliation_version': 7,
          },
        ]);
        return <String, dynamic>{
          'operation': 'confirm_drafts_batch',
          'operation_key': 'approve-weeks-batch-0001',
          'payload_hash':
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          'replayed': false,
          'confirmed_vouchers': <Map<String, dynamic>>[
            <String, dynamic>{
              'voucher_id': _voucherId,
              'reconciliation_version': 8,
              'status': 'confirmed',
            },
          ],
        };
      };

      final results = await harness.service.approveWeeks(
        requests: const <PayrollPaymentWeekApprovalRequest>[
          PayrollPaymentWeekApprovalRequest(
            voucherId: _voucherId,
            expectedReconciliationVersion: 7,
          ),
        ],
        operationKey: 'approve-weeks-batch-0001',
      );

      expect(results, hasLength(1));
      expect(results.single.voucherId, _voucherId);
      expect(results.single.reconciliationVersion, 8);
      expect(harness.calls, hasLength(1));
    });

    test('serializes bank and cash salary legs from canonical method codes',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final command = _command(
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'bank-part',
            amountClp: 72000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'BANK-72',
          ),
          PayrollPaymentLeg.payment(
            legId: 'cash-part',
            amountClp: 28000,
            paymentMethodId: _cashMethodId,
            paymentAccountId: _cashAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'CASH-28',
          ),
        ],
      );

      final receipt = await harness.service.applyTarget(command: command);

      expect(receipt.operationKey, command.operationKey);
      final call = harness.calls.single;
      expect(call.functionName, 'apply_payroll_payment_workspace_v2');
      expect(call.params['p_operation_key'], command.operationKey);
      expect(call.params['p_expected_workspace_version'], 0);
      final payload = _map(call.params['p_payload']);
      final target = _maps(payload['salary_targets']).single;
      final legs = _maps(target['legs']);
      expect(legs.map((leg) => leg['funding_kind']), <String>['bank', 'cash']);
      expect(legs.map((leg) => leg['kind']), everyElement('payment'));
      expect(payload, isNot(contains('statement')));
      expect(payload, isNot(contains('rows')));
      expect(
        legs.map((leg) => leg['leg_id']).toSet(),
        hasLength(2),
      );
      expect(
        legs.every((leg) => _looksLikeUuid(leg['leg_id']?.toString())),
        isTrue,
      );
    });

    test('sends structured OCR evidence and never sends raw OCR page text',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final source = _ocrSource();
      final evidence = source.evidenceRows.first;
      final command = _command(
        salaryLegs: <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'ocr-bank-part',
            amountClp: 75000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: const PayrollCivilDate(2026, 8, 10),
            reference: 'BANK-75',
            ocrEvidence: evidence,
          ),
        ],
      );

      await harness.service.applyTarget(command: command, ocrSource: source);

      final payload = _map(harness.calls.single.params['p_payload']);
      final statement = _map(payload['statement']);
      expect(statement['account_id'], _bankAccountId);
      expect(statement['file_digest'], _fileDigest);
      final rows = _maps(payload['rows']);
      expect(rows, hasLength(2), reason: 'the reusable import is complete');
      expect(rows.first['source_row_id'], 'ocr-row-1');
      expect(rows.first['direction'], 'debit');
      expect(rows.first, isNot(contains('page')));
      expect(rows.first, isNot(contains('source_line_start')));
      expect(rows.first, isNot(contains('fingerprint')));
      expect(statement['source_type'], 'pdf_ocr');
      final salaryLeg =
          _maps(_maps(payload['salary_targets']).single['legs']).single;
      expect(
        _maps(salaryLeg['evidence']).single,
        <String, dynamic>{'source_row_id': 'ocr-row-1', 'amount': 75000},
      );
      final encoded = jsonEncode(payload);
      expect(encoded, isNot(contains('RAW OCR PAGE TEXT MUST NEVER LEAVE')));
      expect(encoded, isNot(contains(source.extractionKind)));
      expect(encoded, isNot(contains(source.operationKey)));
    });

    test('serializes two workers of one voucher at the same input version',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final first = _command(
        target: _target(
          targetId: 'worker-one',
          voucherLineId: _lineOneId,
          employeeId: _employeeOneId,
          reconciliationVersion: 7,
        ),
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'worker-one-bank',
            amountClp: 75000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 10),
          ),
        ],
      );
      final second = _command(
        target: _target(
          targetId: 'worker-two',
          voucherLineId: _lineTwoId,
          employeeId: _employeeTwoId,
          reconciliationVersion: 7,
        ),
        operationKey: 'ignored-per-target-key-0002',
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'worker-two-bank',
            amountClp: 20000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        ],
      );

      await harness.service.applyTargets(
        commands: <PayrollPaymentTargetSaveCommand>[first, second],
        operationKey: 'workspace-batch-workers-0001',
      );

      final call = harness.calls.single;
      expect(call.params['p_operation_key'], 'workspace-batch-workers-0001');
      final targets = _maps(_map(call.params['p_payload'])['salary_targets']);
      expect(targets, hasLength(2));
      expect(
        targets.map((target) => target['voucher_id']).toSet(),
        <String>{_voucherId},
      );
      expect(
        targets.map((target) => target['expected_reconciliation_version']),
        everyElement(7),
      );
      expect(
        targets.map((target) => target['target_id']).toSet(),
        hasLength(2),
      );
    });

    test('serializes one additive expense without payroll linkage', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final concept = PayrollAdditionalConcept(
        conceptId: 'plastic-boxes',
        type: PayrollAdditionalConceptType.expenseReimbursement,
        description: 'Reintegro cajas plásticas para el taller',
        amountClp: 15000,
        expenseAccountId: _expenseAccountId,
        disposition: PayrollAdditionalConceptDisposition.additional,
        evidenceReference: 'Comprobante entregado por el trabajador',
        paymentLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'concept-bank',
            amountClp: 10000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 10),
            reference: 'Reintegro cajas',
          ),
          PayrollPaymentLeg.payment(
            legId: 'concept-cash',
            amountClp: 5000,
            paymentMethodId: _cashMethodId,
            paymentAccountId: _cashAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 10),
          ),
        ],
      );
      final command = _command(
        salaryLegs: const <PayrollPaymentLeg>[],
        additionalConcepts: <PayrollAdditionalConcept>[concept],
      );

      final receipt = await harness.service.applyTarget(command: command);

      final call = harness.calls.single;
      expect(call.functionName, 'apply_payroll_payment_workspace_v2');
      final payload = _map(call.params['p_payload']);
      expect(_maps(payload['salary_targets']), isEmpty);
      final serialized = _maps(payload['additional_concepts']).single;
      expect(serialized['beneficiary_employee_id'], _employeeOneId);
      expect(serialized['disposition'], 'additional');
      expect(serialized, isNot(contains('voucher_id')));
      expect(serialized, isNot(contains('voucher_line_id')));
      expect(serialized, isNot(contains('expected_reconciliation_version')));
      expect(serialized['expense_account_id'], _expenseAccountId);
      expect(serialized['amount'], 15000);
      expect(serialized['notes'], 'Comprobante entregado por el trabajador');
      final legs = _maps(serialized['payment_legs']);
      expect(legs, hasLength(2));
      expect(legs.map((leg) => leg['funding_kind']), <String>['bank', 'cash']);
      expect(
        legs.fold<int>(0, (sum, leg) => sum + (leg['amount'] as int)),
        15000,
      );
      expect(legs.first['reference'], 'Reintegro cajas');

      final received = _maps(receipt.raw['additional_concepts']).single;
      expect(received['disposition'], 'additional');
      expect(received, isNot(contains('voucher_id')));
      expect(received, isNot(contains('voucher_line_id')));
      expect(received, isNot(contains('reclassification_id')));
      expect(received, isNot(contains('reclassification_journal_entry_id')));
    });

    test('serializes an included expense with payroll CAS linkage', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final command = _command(
        target: _target(salaryBalanceClp: 72000),
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'salary-bank-62',
            amountClp: 62000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 10),
            reference: 'Sueldo Fernando',
          ),
        ],
        additionalConcepts: <PayrollAdditionalConcept>[
          PayrollAdditionalConcept(
            conceptId: 'plastic-boxes-included',
            type: PayrollAdditionalConceptType.expenseReimbursement,
            description: 'Reintegro cajas plásticas para el taller',
            amountClp: 10000,
            expenseAccountId: _expenseAccountId,
            disposition:
                PayrollAdditionalConceptDisposition.includedInPayrollTotal,
            paymentLegs: const <PayrollPaymentLeg>[
              PayrollPaymentLeg.payment(
                legId: 'concept-bank-10',
                amountClp: 10000,
                paymentMethodId: _transferMethodId,
                paymentAccountId: _bankAccountId,
                paymentDate: PayrollCivilDate(2026, 8, 10),
                reference: 'Reintegro cajas',
              ),
            ],
          ),
        ],
      );

      final receipt = await harness.service.applyTarget(command: command);

      final call = harness.calls.single;
      expect(call.functionName, 'apply_payroll_payment_workspace_v2');
      final payload = _map(call.params['p_payload']);
      final serialized = _maps(payload['additional_concepts']).single;
      expect(serialized['disposition'], 'included_in_payroll_total');
      expect(_looksLikeUuid(serialized['target_id']?.toString()), isTrue);
      expect(serialized['voucher_id'], _voucherId);
      expect(serialized['voucher_line_id'], _lineOneId);
      expect(serialized['expected_reconciliation_version'], 7);
      expect(serialized['beneficiary_employee_id'], _employeeOneId);

      final received = _maps(receipt.raw['additional_concepts']).single;
      expect(received['disposition'], 'included_in_payroll_total');
      expect(received['voucher_id'], _voucherId);
      expect(received['voucher_line_id'], _lineOneId);
      expect(received['reclassification_id'], _reclassificationId);
      expect(
        received['reclassification_journal_entry_id'],
        _reclassificationJournalEntryId,
      );
    });

    test('keeps an empty salary target when an included concept covers it',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final command = _command(
        target: _target(salaryBalanceClp: 10000),
        salaryLegs: const <PayrollPaymentLeg>[],
        additionalConcepts: <PayrollAdditionalConcept>[
          PayrollAdditionalConcept(
            conceptId: 'included-only',
            type: PayrollAdditionalConceptType.expenseReimbursement,
            description: 'Compra cubierta por el trabajador',
            amountClp: 10000,
            expenseAccountId: _expenseAccountId,
            disposition:
                PayrollAdditionalConceptDisposition.includedInPayrollTotal,
            paymentLegs: const <PayrollPaymentLeg>[
              PayrollPaymentLeg.payment(
                legId: 'included-only-bank',
                amountClp: 10000,
                paymentMethodId: _transferMethodId,
                paymentAccountId: _bankAccountId,
                paymentDate: PayrollCivilDate(2026, 8, 10),
                reference: 'Reintegro compra',
              ),
            ],
          ),
        ],
      );

      await harness.service.applyTarget(command: command);

      final payload = _map(harness.calls.single.params['p_payload']);
      final salaryTarget = _maps(payload['salary_targets']).single;
      final concept = _maps(payload['additional_concepts']).single;
      expect(_maps(salaryTarget['legs']), isEmpty);
      expect(concept['target_id'], salaryTarget['target_id']);
      expect(concept['voucher_id'], salaryTarget['voucher_id']);
    });

    test('rejects a concept funding leg that omits a required reference',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final command = _command(
        salaryLegs: const <PayrollPaymentLeg>[],
        additionalConcepts: <PayrollAdditionalConcept>[
          PayrollAdditionalConcept(
            conceptId: 'unreferenced-expense',
            type: PayrollAdditionalConceptType.expenseReimbursement,
            description: 'Reintegro sin referencia',
            amountClp: 10000,
            expenseAccountId: _expenseAccountId,
            paymentLegs: <PayrollPaymentLeg>[
              const PayrollPaymentLeg.payment(
                legId: 'unreferenced-bank-leg',
                amountClp: 10000,
                paymentMethodId: _transferMethodId,
                paymentAccountId: _bankAccountId,
                paymentDate: PayrollCivilDate(2026, 8, 10),
              ),
            ],
          ),
        ],
      );

      await expectLater(
        harness.service.applyTarget(command: command),
        throwsA(
          isA<PayrollVoucherPreflightException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('referencia'),
          ),
        ),
      );
      expect(harness.calls, isEmpty);
    });

    test('ambiguous retry sends byte-equivalent params with the same IDs',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      var attempt = 0;
      harness.handler = (functionName, params) {
        attempt += 1;
        if (attempt == 1) {
          throw const PostgrestException(
            message: 'connection failed at private.invalid',
            code: 'PGRST000',
          );
        }
        return _receiptFor(params, replayed: true);
      };
      final command = _command(
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'stable-bank-leg',
            amountClp: 100000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        ],
      );

      await expectLater(
        harness.service.applyTarget(command: command),
        throwsA(isA<PostgrestException>()),
      );
      final recovered = await harness.service.applyTarget(command: command);

      expect(recovered.replayed, isTrue);
      expect(harness.calls, hasLength(2));
      expect(harness.calls.first.params, harness.calls.last.params);
      expect(
        harness.calls.first.params['p_operation_key'],
        command.operationKey,
      );
    });

    test('successful RPC with malformed receipt is committed but unverified',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.handler = (functionName, params) => <String, dynamic>{
            'workspace_id': params['p_workspace_id'],
            'operation_key': params['p_operation_key'],
            'status': 'applied',
            // A stale server receipt can omit fields required by the current
            // client even though the RPC transaction already committed.
          };
      final command = _command(
        operationKey: 'workspace-malformed-receipt-0001',
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'bank-leg',
            amountClp: 100000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        ],
      );

      await expectLater(
        harness.service.applyTarget(command: command),
        throwsA(
          isA<PayrollPaymentCommittedUnverifiedException>().having(
            (error) => error.operationKey,
            'operationKey',
            command.operationKey,
          ),
        ),
      );
      expect(harness.calls, hasLength(1));
    });

    test('cash or other method cannot fabricate statement-backed evidence',
        () async {
      for (final fixture in const <({String methodId, String accountId})>[
        (methodId: _cashMethodId, accountId: _cashAccountId),
        (methodId: _otherMethodId, accountId: _otherAccountId),
      ]) {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final source = _ocrSource();
        final command = _command(
          operationKey: 'workspace-invalid-evidence-${fixture.methodId}',
          salaryLegs: <PayrollPaymentLeg>[
            PayrollPaymentLeg.payment(
              legId: 'invalid-evidence',
              amountClp: 10000,
              paymentMethodId: fixture.methodId,
              paymentAccountId: fixture.accountId,
              paymentDate: const PayrollCivilDate(2026, 8, 10),
              ocrEvidence: source.evidenceRows.first,
            ),
          ],
        );

        await expectLater(
          harness.service.applyTarget(command: command, ocrSource: source),
          throwsA(
            isA<PayrollVoucherPreflightException>().having(
              (error) => error.kind,
              'kind',
              PayrollVoucherPreflightFailureKind.rejected,
            ),
          ),
        );
        expect(harness.calls, isEmpty);
      }
    });

    test('deterministic server rejection is typed and sanitized', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.handler = (functionName, params) {
        throw const PostgrestException(
          message: 'payroll_workspace_salary_exceeds_balance SECRET-INTERNAL',
          code: '23514',
        );
      };
      final command = _command(
        salaryLegs: const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'too-much',
            amountClp: 100000,
            paymentMethodId: _transferMethodId,
            paymentAccountId: _bankAccountId,
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        ],
      );

      Object? captured;
      try {
        await harness.service.applyTarget(command: command);
      } catch (error) {
        captured = error;
      }

      expect(captured, isA<PayrollVoucherPreflightException>());
      final typed = captured! as PayrollVoucherPreflightException;
      expect(typed.kind, PayrollVoucherPreflightFailureKind.rejected);
      expect(typed.userMessage, isNot(contains('SECRET-INTERNAL')));
      expect(harness.calls, hasLength(1));
    });
  });
}

PayrollPaymentTarget _target({
  String targetId = 'worker-one',
  String voucherLineId = _lineOneId,
  String employeeId = _employeeOneId,
  int reconciliationVersion = 7,
  int salaryBalanceClp = 200000,
}) {
  return PayrollPaymentTarget(
    targetId: targetId,
    voucherId: _voucherId,
    voucherLineId: voucherLineId,
    employeeId: employeeId,
    employeeName: targetId,
    periodStart: const PayrollCivilDate(2026, 8, 3),
    periodEnd: const PayrollCivilDate(2026, 8, 9),
    salaryBalanceClp: salaryBalanceClp,
    reconciliationVersion: reconciliationVersion,
  );
}

PayrollPaymentTargetSaveCommand _command({
  PayrollPaymentTarget? target,
  String operationKey = 'workspace-target-retry-0001',
  required List<PayrollPaymentLeg> salaryLegs,
  List<PayrollAdditionalConcept> additionalConcepts = const [],
}) {
  return PayrollPaymentTargetSaveCommand(
    target: target ?? _target(),
    operationKey: operationKey,
    salaryLegs: salaryLegs,
    salarySplits: const <Map<String, dynamic>>[],
    additionalConcepts: additionalConcepts,
  );
}

PayrollOcrStatementSource _ocrSource() {
  return PayrollOcrStatementSource(
    filename: 'cartola-agosto.pdf',
    fileSha256: _fileDigest,
    operationKey: 'RAW OCR PAGE TEXT MUST NEVER LEAVE',
    pageCount: 5,
    extractionKind: 'veryfiCloudOcr',
    sourceType: 'pdf',
    accountFingerprint: _accountFingerprint,
    statementStartDate: const PayrollCivilDate(2026, 8, 1),
    statementEndDate: const PayrollCivilDate(2026, 8, 11),
    evidenceRows: const <PayrollOcrStatementEvidence>[
      PayrollOcrStatementEvidence(
        sourceRowId: 'ocr-row-1',
        fingerprint: '',
        ordinal: 1,
        pageNumber: 1,
        lineStart: 20,
        lineEnd: 21,
        bookingDate: PayrollCivilDate(2026, 8, 10),
        direction: PayrollStatementMovementDirection.outgoing,
        amountClp: 85000,
        description: 'Transferencia a Fernando Tapia',
        beneficiaryObserved: 'Fernando Tapia',
        documentReference: 'BANK-ROW-1',
      ),
      PayrollOcrStatementEvidence(
        sourceRowId: 'ocr-row-2',
        fingerprint:
            '2222222222222222222222222222222222222222222222222222222222222222',
        ordinal: 2,
        pageNumber: 2,
        lineStart: 10,
        lineEnd: 10,
        bookingDate: PayrollCivilDate(2026, 8, 11),
        direction: PayrollStatementMovementDirection.incoming,
        amountClp: 5000,
        description: 'Abono no usado en nómina',
      ),
    ],
  );
}

typedef _RpcHandler = FutureOr<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

class _Harness {
  _Harness() {
    service = PayrollPaymentWorkspaceService(
      database: database,
      sensitiveRpc: (functionName, params) async {
        final safeParams = _deepMap(params);
        calls.add(_RpcCall(functionName, safeParams));
        return handler(functionName, safeParams);
      },
    );
  }

  final _FakeDatabaseService database = _FakeDatabaseService();
  final List<_RpcCall> calls = <_RpcCall>[];
  late final PayrollPaymentWorkspaceService service;
  _RpcHandler handler = (functionName, params) => _receiptFor(params);

  void dispose() => database.dispose();
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic> params;
}

class _FakeDatabaseService extends DatabaseService {
  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool fetchAll = false,
  }) async {
    if (table != 'payment_methods') {
      throw StateError('Unexpected table: $table');
    }
    final rows = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': _transferMethodId,
        'name': 'Transferencia',
        'code': 'transfer',
        'account_id': _bankAccountId,
        'is_active': true,
        'requires_reference': true,
      },
      <String, dynamic>{
        'id': _cashMethodId,
        'name': 'Efectivo',
        'code': 'cash',
        'account_id': _cashAccountId,
        'is_active': true,
        'requires_reference': false,
      },
      <String, dynamic>{
        'id': _otherMethodId,
        'name': 'Tarjeta',
        'code': 'card',
        'account_id': _otherAccountId,
        'is_active': true,
        'requires_reference': false,
      },
    ];
    final requested = whereIn?.toSet();
    return rows
        .where((row) => requested == null || requested.contains(row['id']))
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }
}

Map<String, dynamic> _receiptFor(
  Map<String, dynamic> params, {
  bool replayed = false,
}) {
  final payload = _map(params['p_payload']);
  final salaryTargets = _maps(payload['salary_targets']);
  final concepts = _maps(payload['additional_concepts']);
  final evidenceLegIds = <String>[];
  for (final target in salaryTargets) {
    for (final leg in _maps(target['legs'])) {
      if (_mapsOrEmpty(leg['evidence']).isNotEmpty) {
        evidenceLegIds.add(leg['leg_id'].toString());
      }
    }
  }
  for (final concept in concepts) {
    for (final leg in _maps(concept['payment_legs'])) {
      if (_mapsOrEmpty(leg['evidence']).isNotEmpty) {
        evidenceLegIds.add(leg['leg_id'].toString());
      }
    }
  }
  return <String, dynamic>{
    'workspace_id': params['p_workspace_id'],
    'operation_key': params['p_operation_key'],
    'payload_hash':
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'status': 'applied',
    'version': 1,
    'replayed': replayed,
    'statement': payload['statement'] == null
        ? null
        : <String, dynamic>{
            'import_id': '50000000-0000-4000-8000-000000000001',
            'file_digest': _map(payload['statement'])['file_digest'],
            'account_id': _map(payload['statement'])['account_id'],
            'created': true,
          },
    'targets': <Map<String, dynamic>>[
      for (final target in salaryTargets)
        <String, dynamic>{
          'target_id': target['target_id'],
          'voucher_id': target['voucher_id'],
          'status': 'partial',
          'reconciliation_version':
              (target['expected_reconciliation_version'] as int) + 1,
          'legs': <Map<String, dynamic>>[
            for (final leg in _maps(target['legs']))
              <String, dynamic>{
                'leg_id': leg['leg_id'],
                'kind': leg['kind'],
                'amount': leg['amount'],
                'receipt': <String, dynamic>{'status': 'partial'},
              },
          ],
        },
    ],
    'additional_concepts': <Map<String, dynamic>>[
      for (final concept in concepts)
        <String, dynamic>{
          'concept_id': concept['concept_id'],
          'disposition': concept['disposition'],
          if (concept['disposition'] == 'included_in_payroll_total') ...{
            'target_id': concept['target_id'],
            'voucher_id': concept['voucher_id'],
            'voucher_line_id': concept['voucher_line_id'],
            'reclassification_id': _reclassificationId,
            'reclassification_journal_entry_id':
                _reclassificationJournalEntryId,
          },
          'amount': concept['amount'],
          'expense_account_id': concept['expense_account_id'],
          'expense_id': '60000000-0000-4000-8000-000000000001',
          'expense_number': 'G-1',
          'payment_legs': <Map<String, dynamic>>[
            for (final leg in _maps(concept['payment_legs']))
              <String, dynamic>{
                'leg_id': leg['leg_id'],
                'amount': leg['amount'],
                'funding_kind': leg['funding_kind'],
              },
          ],
        },
    ],
    'statement_allocations': <Map<String, dynamic>>[
      for (var index = 0; index < evidenceLegIds.length; index += 1)
        <String, dynamic>{
          'allocation_id':
              '70000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
          'leg_id': evidenceLegIds[index],
          'import_id': '50000000-0000-4000-8000-000000000001',
          'row_id':
              '80000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
          'allocated_amount': 1,
        },
    ],
  };
}

Map<String, dynamic> _deepMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Map<String, dynamic> _map(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

List<Map<String, dynamic>> _maps(dynamic value) => (value as List)
    .map((entry) => Map<String, dynamic>.from(entry as Map))
    .toList(growable: false);

List<Map<String, dynamic>> _mapsOrEmpty(dynamic value) =>
    value == null ? const <Map<String, dynamic>>[] : _maps(value);

bool _looksLikeUuid(String? value) =>
    value != null &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value);
