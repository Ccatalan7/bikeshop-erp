import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_reconciliation_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_extraction_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
          },
          request: request,
        ),
      ),
    );
  });

  group('PayrollReconciliationService.prepare', () {
    test('translates extraction failures into a typed recoverable error',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await expectLater(
        harness.reconciliationService.prepare(
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
          filename: 'archivo-invalido.bin',
        ),
        throwsA(
          isA<PayrollReconciliationServiceException>()
              .having(
                (error) => error.message,
                'message',
                'El archivo no es un PDF, JPG, PNG o WebP válido.',
              )
              .having(
                (error) => error.recoveryAction,
                'recoveryAction',
                PayrollReconciliationRecoveryAction.selectAnotherFile,
              )
              .having(
                (error) => error.canRetrySameOperation,
                'canRetrySameOperation',
                isFalse,
              ),
        ),
      );
      expect(harness.database.selectCalls, isEmpty);
    });

    test(
      'keeps civil evidence and +250 proposal while gating legacy and cash',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        final draft = await harness.prepare();
        expect(
          draft.parseResult.rows.map((row) => row.debitAmountClp),
          <int?>[128000, 38000],
        );
        final transferResult = draft.reconciliation.lineResults.singleWhere(
          (result) => result.voucherLine.lineId == _transferLineId,
        );
        final proposal = transferResult.proposedMatch;

        expect(proposal, isNotNull);
        expect(proposal!.amountVarianceClp, 250);
        expect(
          proposal.statementRow.bookingDate,
          const PayrollCivilDate(2026, 7, 27),
        );
        expect(proposal.statementRow.bookingDate.toString(), '2026-07-27');
        expect(
          draft.rowFingerprintsBySourceRowId[proposal.statementRow.sourceRowId],
          matches(RegExp(r'^[0-9a-f]{64}$')),
        );

        expect(
          draft.missingCanonicalPaymentMethodEmployeeIds,
          contains(_transferEmployeeId),
        );
        expect(
          draft.missingCanonicalPaymentMethodEmployeeIds,
          isNot(contains(_cashEmployeeId)),
        );

        final cashResult = draft.reconciliation.lineResults.singleWhere(
          (result) => result.voucherLine.lineId == _cashLineId,
        );
        expect(cashResult.status, PayrollLineMatchStatus.ineligible);
        expect(cashResult.proposedMatch, isNull);
        expect(
          cashResult.reasons,
          [PayrollLineMatchReason.paymentMethodIsCash],
        );
        expect(draft.openAdvances, hasLength(1));
        expect(draft.openAdvances.single.id, _cashAdvanceId);
        expect(draft.openAdvances.single.employeeId, _cashEmployeeId);
        expect(draft.openAdvances.single.availableAmount, 36000);
      },
    );

    test(
      'excludes a previously reconciled row from matching and keeps its prior decision',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        final baseline = await harness.prepare();
        final transferRow = baseline.parseResult.rows.singleWhere(
          (row) => row.debitAmountClp == 128000,
        );
        final transferFingerprint =
            baseline.rowFingerprintsBySourceRowId[transferRow.sourceRowId]!;
        harness.database.payrollStatementDecisions = <Map<String, dynamic>>[
          _priorDecisionRow(rowFingerprint: transferFingerprint),
        ];

        final draft = await harness.prepare();
        final preparedTransferRow = draft.parseResult.rows.singleWhere(
          (row) => row.debitAmountClp == 128000,
        );
        final transferResult = draft.reconciliation.lineResults.singleWhere(
          (result) => result.voucherLine.lineId == _transferLineId,
        );

        expect(draft.parseResult.rows, hasLength(2));
        expect(
          draft.priorDecisionIdsBySourceRowId,
          <String, String>{
            preparedTransferRow.sourceRowId: _priorDecisionId,
          },
        );
        expect(transferResult.proposedMatch, isNull);
        expect(
          draft.reconciliation.proposedMatches
              .map((match) => match.statementRow.sourceRowId),
          isNot(contains(preparedTransferRow.sourceRowId)),
        );
        expect(
          draft.rowFingerprintsBySourceRowId[preparedTransferRow.sourceRowId],
          transferFingerprint,
        );

        final priorLookup = harness.database.selectCalls.lastWhere(
          (call) => call.table == 'payroll_statement_decisions',
        );
        expect(
          priorLookup.whereIn,
          containsAll(draft.rowFingerprintsBySourceRowId.values),
        );
      },
    );

    test(
      'prepare degrades to an empty prior-decision map when the '
      'reconciliation backend is absent',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollStatementDecisionSelectHandler = (_) {
          throw const PostgrestException(
            message: "Could not find the table "
                "'public.payroll_statement_decisions' in the schema cache",
            code: 'PGRST205',
          );
        };

        final draft = await harness.prepare();

        expect(draft.priorDecisionIdsBySourceRowId, isEmpty);
        expect(draft.reconciliation.lineResults, isNotEmpty);
        expect(draft.parseResult.rows, isNotEmpty);
      },
    );

    test(
      'prepare degrades to an empty alias map only when the alias table is '
      'absent',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollBeneficiaryAliasSelectHandler = (_) {
          throw const PostgrestException(
            message: "Could not find the table "
                "'public.payroll_beneficiary_aliases' in the schema cache",
            code: 'PGRST205',
          );
        };

        final draft = await harness.prepare();

        expect(draft.reconciliation.lineResults, isNotEmpty);
        expect(
          draft.reconciliation.lineResults.every(
            (result) => result.employee?.bankBeneficiaryAliases.isEmpty ?? true,
          ),
          isTrue,
        );
      },
    );

    test(
      'prepare keeps a non-schema alias failure visible',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollBeneficiaryAliasSelectHandler = (_) {
          throw const PostgrestException(
            message: 'permission denied for table payroll_beneficiary_aliases',
            code: '42501',
          );
        };

        await expectLater(
          harness.prepare(),
          throwsA(
            isA<PostgrestException>()
                .having((error) => error.code, 'code', '42501'),
          ),
        );
      },
    );

    test(
      'prepare keeps a non-schema prior-decision failure visible',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollStatementDecisionSelectHandler = (_) {
          throw const PostgrestException(
            message: 'permission denied for table payroll_statement_decisions',
            code: '42501',
          );
        };

        await expectLater(
          harness.prepare(),
          throwsA(
            isA<PostgrestException>()
                .having((error) => error.code, 'code', '42501'),
          ),
        );
      },
    );

    test(
      'a missing COLUMN on the decisions table never degrades to legacy',
      () async {
        // L-H4: «column payroll_statement_decisions.decided_at does not
        // exist» nombra la tabla Y dice «does not exist», así que un matcher
        // ingenuo lo confundiría con tabla ausente. Es deriva de contrato
        // (backend a medio migrar) y debe quedar visible.
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollStatementDecisionSelectHandler = (_) {
          throw const PostgrestException(
            message: 'column payroll_statement_decisions.decided_at '
                'does not exist',
            code: '42703',
          );
        };

        await expectLater(
          harness.prepare(),
          throwsA(
            isA<PostgrestException>()
                .having((error) => error.code, 'code', '42703'),
          ),
        );
      },
    );

    test(
      'a missing COLUMN on the alias table never degrades to legacy',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.payrollBeneficiaryAliasSelectHandler = (_) {
          throw const PostgrestException(
            message: 'column payroll_beneficiary_aliases.normalized_alias '
                'does not exist',
            code: '42703',
          );
        };

        await expectLater(
          harness.prepare(),
          throwsA(
            isA<PostgrestException>()
                .having((error) => error.code, 'code', '42703'),
          ),
        );
      },
    );

    test(
      'uses the voucher-line payment snapshot instead of the employee current method',
      () async {
        final baseVoucher = _voucher();
        final snapshotVoucher = baseVoucher.copyWith(
          lines: <PayrollVoucherLine>[
            baseVoucher.lines.first,
            baseVoucher.lines.last.copyWith(
              paymentMethodId: _transferMethodId,
            ),
          ],
        );
        final harness = _Harness(
          vouchers: <PayrollVoucher>[
            snapshotVoucher,
            _unrelatedOpenVoucher(),
          ],
        );
        addTearDown(harness.dispose);

        final draft = await harness.prepare();
        final cashEmployeeRow = draft.employeeRowsById[_cashEmployeeId]!;
        expect(
          cashEmployeeRow['preferred_payment_method_id'],
          _cashMethodId,
          reason: 'the current employee profile deliberately says cash',
        );

        final result = draft.reconciliation.lineResults.singleWhere(
          (value) => value.voucherLine.lineId == _cashLineId,
        );
        expect(
          result.voucherLine.paymentMethod,
          PayrollReconciliationPaymentMethod.transfer,
        );
        expect(result.voucherLine.paymentMethodId, _transferMethodId);
        expect(result.status, PayrollLineMatchStatus.suggested);
        expect(result.proposedMatch?.statementRow.debitAmountClp, 38000);
        expect(
          draft.missingCanonicalPaymentMethodEmployeeIds,
          isNot(contains(_cashEmployeeId)),
        );
      },
    );

    test(
      'refresh reuses parsed evidence and resolves a newly configured method',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        final original = await harness.prepare();
        expect(
          original.missingCanonicalPaymentMethodEmployeeIds,
          contains(_transferEmployeeId),
        );
        final employee = harness.database.employeeRows.singleWhere(
          (row) => row['id'] == _transferEmployeeId,
        );
        employee['preferred_payment_method_id'] = _transferMethodId;

        final refreshed =
            await harness.reconciliationService.refreshPreparedDraft(original);

        expect(refreshed.operationKey, original.operationKey);
        expect(refreshed.extraction, same(original.extraction));
        expect(refreshed.parseResult, same(original.parseResult));
        expect(
          refreshed.missingCanonicalPaymentMethodEmployeeIds,
          isNot(contains(_transferEmployeeId)),
        );
        final transfer = refreshed.reconciliation.lineResults.singleWhere(
          (result) => result.voucherLine.lineId == _transferLineId,
        );
        expect(
          transfer.voucherLine.paymentMethodId,
          _transferMethodId,
        );
        expect(transfer.proposedMatch?.amountVarianceClp, 250);
      },
    );

    test(
      'an invalid snapshot falls back only to a valid employee canonical method',
      () async {
        final baseVoucher = _voucher();
        final staleSnapshotVoucher = baseVoucher.copyWith(
          lines: <PayrollVoucherLine>[
            baseVoucher.lines.first.copyWith(
              paymentMethodId: '00000000-0000-4000-8000-000000000099',
            ),
            baseVoucher.lines.last,
          ],
        );
        final harness = _Harness(
          vouchers: <PayrollVoucher>[
            staleSnapshotVoucher,
            _unrelatedOpenVoucher(),
          ],
        );
        addTearDown(harness.dispose);
        harness.database.employeeRows
                .singleWhere((row) => row['id'] == _transferEmployeeId)[
            'preferred_payment_method_id'] = _transferMethodId;

        final prepared = await harness.prepare();
        final transfer = prepared.reconciliation.lineResults.singleWhere(
          (result) => result.voucherLine.lineId == _transferLineId,
        );

        expect(transfer.voucherLine.paymentMethodId, _transferMethodId);
        expect(
          prepared.missingCanonicalPaymentMethodEmployeeIds,
          isNot(contains(_transferEmployeeId)),
        );
      },
    );
  });

  test('apply receipt parses typed counts and voucher versions from RPC JSON',
      () {
    const receipt = PayrollStatementApplyReceipt(
      importId: _importId,
      operationKey: _explicitRetryKey,
      wasReplay: true,
      raw: <String, dynamic>{
        'status': 'applied',
        'decision_count': '4',
        'allocation_count': 3.0,
        'already_resolved_count': 1,
        'unresolved_variance_count': '2',
        'unresolved_variance_total': 500.0,
        'committed_voucher_ids': <String>[
          _unrelatedVoucherId,
          _voucherId,
          _voucherId,
        ],
        'voucher_versions': <String, dynamic>{
          _voucherId: '8',
          _unrelatedVoucherId: 10.0,
        },
      },
    );

    expect(receipt.status, 'applied');
    expect(receipt.decisionCount, 4);
    expect(receipt.allocationCount, 3);
    expect(receipt.alreadyResolvedCount, 1);
    expect(receipt.unresolvedVarianceCount, 2);
    expect(receipt.unresolvedVarianceAmountClp, 500);
    expect(
      receipt.committedVoucherIds,
      <String>[_voucherId, _unrelatedVoucherId],
    );
    expect(
      receipt.voucherVersions,
      <String, int>{
        _voucherId: 8,
        _unrelatedVoucherId: 10,
      },
    );
  });

  group('beneficiary alias learning', () {
    test(
      'writer keeps server normalization authoritative and is idempotent',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        var invocation = 0;
        harness.database.sensitiveRpcHandler = (functionName, params) {
          expect(functionName, 'learn_payroll_beneficiary_alias');
          expect(
            params,
            <String, dynamic>{
              'p_employee_id': _transferEmployeeId,
              'p_alias': 'Persona Úno',
            },
            reason: 'Tenant, actor, normalized alias and timestamps are '
                'server-owned and must never be supplied by the client.',
          );
          invocation++;
          return <String, dynamic>{
            'status': invocation == 1 ? 'created' : 'existing',
            'employee_id': _transferEmployeeId,
            'alias': 'Persona Úno',
            'normalized_alias': 'persona uno',
          };
        };

        final dynamic service = harness.reconciliationService;
        final dynamic created = await service.learnBeneficiaryAlias(
          employeeId: _transferEmployeeId,
          alias: 'Persona Úno',
        );
        final dynamic replay = await service.learnBeneficiaryAlias(
          employeeId: _transferEmployeeId,
          alias: 'Persona Úno',
        );

        expect(created.wasCreated, isTrue);
        expect(created.employeeId, _transferEmployeeId);
        expect(created.alias, 'Persona Úno');
        expect(created.normalizedAlias, 'persona uno');
        expect(replay.wasCreated, isFalse);
        expect(replay.employeeId, _transferEmployeeId);
        expect(replay.normalizedAlias, 'persona uno');
        expect(harness.database.sensitiveRpcCalls, hasLength(2));
        expect(harness.database.databaseRpcCalls, isEmpty);
      },
    );

    test(
      'writer rejects an alias owned by another employee without retrying',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        harness.database.sensitiveRpcHandler = (functionName, params) {
          expect(functionName, 'learn_payroll_beneficiary_alias');
          return <String, dynamic>{
            'status': 'conflict',
            'employee_id': _cashEmployeeId,
            'alias': 'Persona Úno',
            'normalized_alias': 'persona uno',
          };
        };

        final dynamic service = harness.reconciliationService;
        await expectLater(
          () => service.learnBeneficiaryAlias(
            employeeId: _transferEmployeeId,
            alias: 'Persona Úno',
          ),
          throwsA(
            isA<PayrollReconciliationServiceException>().having(
              (error) => error.message,
              'message',
              anyOf(contains('otra persona'), contains('otro trabajador')),
            ),
          ),
        );

        expect(
          harness.database.sensitiveRpcCalls,
          hasLength(1),
          reason:
              'A conflict must never be retried as an upsert or reassignment.',
        );
        expect(harness.database.databaseRpcCalls, isEmpty);
      },
    );
  });

  group('idempotent server commands', () {
    test('createImport serializes normalized rows and preserves replay receipt',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();
      harness.database.persistedStatementRows =
          _persistedStatementRowsFor(draft);
      harness.database.sensitiveRpcHandler = (functionName, params) {
        expect(functionName, 'create_payroll_statement_import');
        return _serverImportReceipt(draft);
      };

      final firstReceipt = await harness.reconciliationService.createImport(
        draft,
        erpAccountId: _erpAccountId,
      );
      final replayReceipt = await harness.reconciliationService.createImport(
        draft,
        erpAccountId: _erpAccountId,
      );

      expect(firstReceipt.importId, _importId);
      expect(firstReceipt.wasReplay, isFalse);
      expect(firstReceipt.erpAccountId, _erpAccountId);
      expect(firstReceipt.rowIdsBySourceRowId, hasLength(2));
      expect(firstReceipt.rowFingerprintsBySourceRowId, hasLength(2));
      expect(replayReceipt.importId, _importId);
      expect(replayReceipt.operationKey, draft.operationKey);
      expect(replayReceipt.wasReplay, isFalse);
      expect(replayReceipt.erpAccountId, _erpAccountId);
      expect(replayReceipt.raw, firstReceipt.raw);
      expect(
        replayReceipt.rowIdsBySourceRowId,
        firstReceipt.rowIdsBySourceRowId,
      );
      expect(
        replayReceipt.rowFingerprintsBySourceRowId,
        firstReceipt.rowFingerprintsBySourceRowId,
      );
      expect(harness.database.sensitiveRpcCalls, hasLength(2));
      expect(harness.database.databaseRpcCalls, isEmpty);

      final firstCall = harness.database.sensitiveRpcCalls.first;
      final replayCall = harness.database.sensitiveRpcCalls.last;
      expect(
        replayCall.params['p_operation_key'],
        firstCall.params['p_operation_key'],
      );
      expect(replayCall.params['p_file_sha256'], draft.extraction.fileSha256);
      expect(
        firstCall.params.keys,
        containsAll(<String>[
          'p_operation_key',
          'p_file_sha256',
          'p_source_metadata',
          'p_rows',
        ]),
      );

      final metadata =
          firstCall.params['p_source_metadata']! as Map<String, dynamic>;
      expect(metadata['parser_name'], 'banco_chile_statement');
      expect(metadata['parser_version'], 'banco_chile_v1');
      expect(metadata['source_type'], 'pdf_text');
      expect(metadata['statement_start'], '2026-07-27');
      expect(metadata['statement_end'], '2026-07-27');
      expect(metadata['account_fingerprint'], _expectedAccountFingerprint);
      expect(
        metadata['account_fingerprint'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(metadata['account_fingerprint'], draft.accountFingerprint);
      expect(metadata['erp_account_id'], _erpAccountId);
      expect(metadata.values, isNot(contains('cartola-redactada.pdf')));
      expect(metadata.toString(), isNot(contains(_rawAccountNumber)));
      expect(metadata.toString(), isNot(contains(_canonicalAccountNumber)));

      final rows = firstCall.params['p_rows']! as List<dynamic>;
      expect(rows, hasLength(2));
      final transferRow = rows
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row['amount'] == 128000);
      final sourceRow = draft.parseResult.rows.singleWhere(
        (row) => row.debitAmountClp == 128000,
      );
      expect(
        transferRow['beneficiary_observed'],
        'Persona Uno',
        reason: 'The bounded observed beneficiary must round-trip separately '
            'from the full bank description.',
      );
      expect(transferRow['ordinal'], sourceRow.evidence.sourceRowNumber);
      expect(transferRow['transaction_date'], '2026-07-27');
      expect(transferRow['direction'], 'debit');
      expect(transferRow['warnings'], isA<List<String>>());
      expect(
        transferRow['fingerprint'],
        draft.rowFingerprintsBySourceRowId[sourceRow.sourceRowId],
      );
      expect(
        firstReceipt.rowIdsBySourceRowId[sourceRow.sourceRowId],
        _transferStatementRowId,
      );
      expect(
        firstReceipt.rowFingerprintsBySourceRowId[sourceRow.sourceRowId],
        draft.rowFingerprintsBySourceRowId[sourceRow.sourceRowId],
      );
      expect(
        harness.database.selectCalls
            .where((call) => call.table == 'payroll_statement_rows'),
        hasLength(2),
      );
    });

    test('createImport records scanned PDF local OCR as pdf_ocr', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final prepared = await harness.prepare();
      final draft = _withExtraction(
        prepared,
        PayrollStatementExtractionResult(
          fileSha256: prepared.extraction.fileSha256,
          inputKind: PayrollStatementInputKind.pdf,
          method: PayrollStatementExtractionMethod.onDeviceImageOcr,
          pages: prepared.extraction.pages,
        ),
      );
      harness.database.persistedStatementRows =
          _persistedStatementRowsFor(draft);
      harness.database.sensitiveRpcHandler = (functionName, params) {
        expect(functionName, 'create_payroll_statement_import');
        return _serverImportReceipt(draft);
      };

      await harness.reconciliationService.createImport(
        draft,
        erpAccountId: _erpAccountId,
      );

      final metadata = harness.database.sensitiveRpcCalls.single
          .params['p_source_metadata']! as Map<String, dynamic>;
      expect(metadata['source_type'], 'pdf_ocr');
      expect(metadata['extraction_kind'], 'onDeviceImageOcr');
    });

    test(
      'createImport preserves a row after the declared close as review evidence',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final draft = await harness.prepare(documentClose: '26/07/2026');
        harness.database.persistedStatementRows =
            _persistedStatementRowsFor(draft);
        harness.database.sensitiveRpcHandler = (functionName, params) {
          expect(functionName, 'create_payroll_statement_import');
          return _serverImportReceipt(draft);
        };

        expect(
          draft.documentDate,
          const PayrollCivilDate(2026, 7, 26),
        );
        await harness.reconciliationService.createImport(
          draft,
          erpAccountId: _erpAccountId,
        );

        final rows = harness.database.sensitiveRpcCalls.single.params['p_rows']!
            as List<dynamic>;
        expect(
          rows.cast<Map<String, dynamic>>().every(
                (row) => (row['warnings'] as List<dynamic>)
                    .contains('out_of_statement_range'),
              ),
          isTrue,
        );
      },
    );

    test(
      'createImport preserves incomplete OCR evidence with null structured fields',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final prepared = await harness.prepare();
        final draft = _withIncompleteEvidence(prepared);
        final incompleteRow = draft.parseResult.rows.last;
        harness.database.persistedStatementRows = <Map<String, dynamic>>[
          ..._persistedStatementRowsFor(prepared),
          <String, dynamic>{
            'id': _incompleteStatementRowId,
            'row_ordinal': incompleteRow.evidence.sourceRowNumber,
            'fingerprint':
                draft.rowFingerprintsBySourceRowId[incompleteRow.sourceRowId],
          },
        ];
        harness.database.sensitiveRpcHandler = (functionName, params) {
          expect(functionName, 'create_payroll_statement_import');
          return <String, dynamic>{'import_id': _importId};
        };

        final receipt = await harness.reconciliationService.createImport(
          draft,
          erpAccountId: _erpAccountId,
        );

        final rows = harness.database.sensitiveRpcCalls.single.params['p_rows']!
            as List<dynamic>;
        expect(rows, hasLength(3));
        final serialized = rows.cast<Map<String, dynamic>>().last;
        expect(serialized['ordinal'], 3);
        expect(serialized['transaction_date'], isNull);
        expect(serialized['direction'], 'debit');
        expect(serialized['amount'], 22000);
        expect(serialized['description_observed'], 'TRANSFERENCIA OCR CORTADA');
        expect(
          serialized['warnings'],
          containsAll(<String>[
            'ocr_missing_date',
            'incomplete_evidence',
          ]),
        );
        expect(
          receipt.rowIdsBySourceRowId[incompleteRow.sourceRowId],
          _incompleteStatementRowId,
        );
      },
    );

    test('createImport rejects a prior-decision race after persisting rows',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();
      final transferRow = draft.parseResult.rows.singleWhere(
        (row) => row.debitAmountClp == 128000,
      );
      final transferFingerprint =
          draft.rowFingerprintsBySourceRowId[transferRow.sourceRowId]!;
      harness.database.persistedStatementRows =
          _persistedStatementRowsFor(draft);
      harness.database.payrollStatementDecisionSelectHandler = (call) {
        expect(call.whereIn, contains(transferFingerprint));
        return <Map<String, dynamic>>[
          _priorDecisionRow(rowFingerprint: transferFingerprint),
        ];
      };
      harness.database.sensitiveRpcHandler = (functionName, params) {
        expect(functionName, 'create_payroll_statement_import');
        return _serverImportReceipt(draft);
      };

      await expectLater(
        harness.reconciliationService.createImport(
          draft,
          erpAccountId: _erpAccountId,
        ),
        throwsA(
          isA<PayrollReconciliationServiceException>().having(
            (error) => error.message,
            'message',
            contains('Otra conciliación resolvió movimientos'),
          ),
        ),
      );

      expect(harness.database.sensitiveRpcCalls, hasLength(1));
      expect(
        harness.database.selectCalls
            .where((call) => call.table == 'payroll_statement_rows'),
        hasLength(1),
      );
      expect(
        harness.database.selectCalls
            .where((call) => call.table == 'payroll_statement_decisions'),
        hasLength(2),
      );
      expect(harness.payrollService.cacheInvalidationCount, 0);
    });

    test(
      'apply sends one reviewed batch and invalidates cache only after ACK',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final draft = await harness.prepare();
        final importReceipt = _importReceipt(draft);
        final proposal = draft.reconciliation.proposedMatches.single;
        final ack = Completer<Object?>();
        harness.database.sensitiveRpcHandler = (functionName, params) {
          expect(functionName, 'apply_payroll_statement_reconciliation');
          return ack.future;
        };

        expect(
          draft.expectedVoucherVersionsById,
          containsPair(_voucherId, 7),
        );
        expect(
          draft.expectedVoucherVersionsById,
          containsPair(_unrelatedVoucherId, 9),
        );

        final applyFuture = harness.reconciliationService.apply(
          draft: draft,
          importReceipt: importReceipt,
          operationKey: _explicitRetryKey,
          decisions: _reviewDecisions(draft),
          authorizedDraftVoucherIds: const {_voucherId},
        );
        await Future<void>.delayed(Duration.zero);

        expect(harness.database.sensitiveRpcCalls, hasLength(1));
        expect(harness.database.databaseRpcCalls, isEmpty);
        expect(harness.payrollService.cacheInvalidationCount, 0);
        expect(proposal.amountVarianceClp, 250);

        final call = harness.database.sensitiveRpcCalls.single;
        expect(call.params['p_operation_key'], _explicitRetryKey);
        expect(call.params['p_import_id'], _importId);
        expect(
          call.params['p_expected_voucher_versions'],
          <String, int>{_voucherId: 7},
        );
        expect(
          call.params['p_authorized_draft_voucher_ids'],
          <String>[_voucherId],
        );
        final decisions = call.params['p_decisions']! as List<dynamic>;
        expect(decisions, hasLength(2));
        final bankDecision = decisions.first as Map<String, dynamic>;
        expect(bankDecision['ordinal'], 1);
        expect(bankDecision['action'], 'bank_payment');
        expect(bankDecision['row_id'], _transferStatementRowId);
        expect(bankDecision['applied_amount'], 127750);
        expect(bankDecision['variance_disposition'], 'unresolved');
        expect(bankDecision['manual_confirmation'], isTrue);
        expect(bankDecision['payment_account_id'], _erpAccountId);
        expect(bankDecision['reason'], 'Diferencia visible para revisión');
        expect(
          importReceipt
              .rowFingerprintsBySourceRowId[proposal.statementRow.sourceRowId],
          draft.rowFingerprintsBySourceRowId[proposal.statementRow.sourceRowId],
        );

        final ignoredDecision = decisions.last as Map<String, dynamic>;
        expect(ignoredDecision['ordinal'], 2);
        expect(ignoredDecision['action'], 'ignore');
        expect(ignoredDecision['row_id'], _cashStatementRowId);
        expect(ignoredDecision['voucher_line_id'], isNull);
        expect(ignoredDecision['reason'], 'No corresponde a una nómina');

        ack.complete(<String, dynamic>{
          'import_id': _importId,
          'operation_key': _explicitRetryKey,
          'committed_voucher_ids': <String>[_voucherId],
        });
        final receipt = await applyFuture;

        expect(receipt.importId, _importId);
        expect(receipt.operationKey, _explicitRetryKey);
        expect(receipt.committedVoucherIds, <String>[_voucherId]);
        expect(harness.payrollService.cacheInvalidationCount, 1);
      },
    );

    test('apply rejects a missing or extra draft commitment authorization',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();
      final decisions = _reviewDecisions(draft);

      for (final authorization in const <Set<String>>[
        <String>{},
        <String>{_voucherId, _unrelatedVoucherId},
      ]) {
        await expectLater(
          harness.reconciliationService.apply(
            draft: draft,
            importReceipt: _importReceipt(draft),
            operationKey: _explicitRetryKey,
            decisions: decisions,
            authorizedDraftVoucherIds: authorization,
          ),
          throwsA(
            isA<PayrollReconciliationServiceException>()
                .having(
                  (error) => error.recoveryAction,
                  'recoveryAction',
                  PayrollReconciliationRecoveryAction.reload,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('semanas borrador'),
                ),
          ),
        );
      }

      expect(harness.database.sensitiveRpcCalls, isEmpty);
      expect(harness.payrollService.cacheInvalidationCount, 0);
    });

    test('apply rejects a receipt that omits the authorized commitment',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();
      harness.database.sensitiveRpcHandler = (functionName, params) {
        return <String, dynamic>{
          'import_id': _importId,
          'operation_key': _explicitRetryKey,
          'committed_voucher_ids': const <String>[],
        };
      };

      await expectLater(
        harness.reconciliationService.apply(
          draft: draft,
          importReceipt: _importReceipt(draft),
          operationKey: _explicitRetryKey,
          decisions: _reviewDecisions(draft),
          authorizedDraftVoucherIds: const {_voucherId},
        ),
        throwsA(
          isA<PayrollReconciliationServiceException>()
              .having(
                (error) => error.recoveryAction,
                'recoveryAction',
                PayrollReconciliationRecoveryAction.reload,
              )
              .having(
                (error) => error.message,
                'message',
                contains('comprobante del servidor'),
              ),
        ),
      );

      expect(harness.payrollService.cacheInvalidationCount, 0);
    });

    test(
      'apply requires and serializes an explicit already-resolved decision',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final draft = await harness.prepare();
        final transferSourceRowId = draft.parseResult.rows
            .singleWhere((row) => row.debitAmountClp == 128000)
            .sourceRowId;
        final cashSourceRowId = draft.parseResult.rows
            .singleWhere((row) => row.debitAmountClp == 38000)
            .sourceRowId;
        final importReceipt = _importReceipt(
          draft,
          priorDecisionIdsBySourceRowId: <String, String>{
            transferSourceRowId: _priorDecisionId,
          },
        );
        final cashDecision = PayrollStatementReviewDecision(
          kind: PayrollReviewDecisionKind.ignore,
          sourceRowId: cashSourceRowId,
          note: 'No corresponde a una nómina',
          manualConfirmation: true,
        );

        await expectLater(
          harness.reconciliationService.apply(
            draft: draft,
            importReceipt: importReceipt,
            operationKey: _explicitRetryKey,
            decisions: <PayrollStatementReviewDecision>[cashDecision],
            authorizedDraftVoucherIds: const <String>{},
          ),
          throwsA(
            isA<PayrollReconciliationServiceException>().having(
              (error) => error.message,
              'message',
              contains('decidir explícitamente'),
            ),
          ),
        );
        await expectLater(
          harness.reconciliationService.apply(
            draft: draft,
            importReceipt: importReceipt,
            operationKey: _explicitRetryKey,
            decisions: <PayrollStatementReviewDecision>[
              PayrollStatementReviewDecision(
                kind: PayrollReviewDecisionKind.alreadyResolved,
                sourceRowId: transferSourceRowId,
                note: 'Resuelta en una importación anterior',
                manualConfirmation: true,
              ),
              cashDecision,
            ],
            authorizedDraftVoucherIds: const <String>{},
          ),
          throwsA(
            isA<PayrollReconciliationServiceException>().having(
              (error) => error.message,
              'message',
              contains('referencia a una conciliación anterior cambió'),
            ),
          ),
        );
        expect(harness.database.sensitiveRpcCalls, isEmpty);

        harness.database.sensitiveRpcHandler = (functionName, params) async {
          expect(functionName, 'apply_payroll_statement_reconciliation');
          return <String, dynamic>{
            'import_id': _importId,
            'operation_key': _explicitRetryKey,
          };
        };
        await harness.reconciliationService.apply(
          draft: draft,
          importReceipt: importReceipt,
          operationKey: _explicitRetryKey,
          decisions: <PayrollStatementReviewDecision>[
            PayrollStatementReviewDecision(
              kind: PayrollReviewDecisionKind.alreadyResolved,
              sourceRowId: transferSourceRowId,
              priorDecisionId: _priorDecisionId,
              note: 'Resuelta en una importación anterior',
              manualConfirmation: true,
            ),
            cashDecision,
          ],
          authorizedDraftVoucherIds: const <String>{},
        );

        final call = harness.database.sensitiveRpcCalls.single;
        expect(call.params['p_expected_voucher_versions'], isEmpty);
        final serialized = (call.params['p_decisions']! as List<dynamic>).first
            as Map<String, dynamic>;
        expect(serialized['action'], 'already_resolved');
        expect(serialized['row_id'], _transferStatementRowId);
        expect(
          serialized['row_fingerprint'],
          importReceipt.rowFingerprintsBySourceRowId[transferSourceRowId],
        );
        expect(serialized['prior_decision_id'], _priorDecisionId);
        expect(serialized['voucher_line_id'], isNull);
        expect(serialized['applied_amount'], isNull);
        expect(serialized['payment_method_id'], isNull);
        expect(serialized['payment_account_id'], isNull);
        expect(serialized['reason'], 'Resuelta en una importación anterior');
        expect(harness.payrollService.cacheInvalidationCount, 1);
      },
    );

    test('apply RPC failure remains an error and preserves the prepared draft',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();
      final originalOperationKey = draft.operationKey;
      final originalProposal = draft.reconciliation.proposedMatches.single;
      final failure = StateError('synthetic RPC failure');
      harness.database.sensitiveRpcHandler =
          (functionName, params) => throw failure;

      await expectLater(
        harness.reconciliationService.apply(
          draft: draft,
          importReceipt: _importReceipt(draft),
          operationKey: _explicitRetryKey,
          decisions: _reviewDecisions(draft),
          authorizedDraftVoucherIds: const {_voucherId},
        ),
        throwsA(same(failure)),
      );

      expect(harness.database.sensitiveRpcCalls, hasLength(1));
      expect(harness.database.databaseRpcCalls, isEmpty);
      expect(harness.payrollService.cacheInvalidationCount, 0);
      expect(draft.operationKey, originalOperationKey);
      expect(
        draft.reconciliation.proposedMatches.single,
        same(originalProposal),
      );
      expect(originalProposal.amountVarianceClp, 250);
    });

    group('typed deterministic recovery', () {
      const scenarios = <({
        String name,
        PostgrestException failure,
        String recoveryAction,
        String copyFragment,
      })>[
        (
          name: 'voucher version conflict',
          failure: PostgrestException(
            message: 'payroll_statement_voucher_version_conflict',
            code: '40001',
            details: 'reload payroll liabilities before applying',
          ),
          recoveryAction: 'reload',
          copyFragment: 'Recarga',
        ),
        (
          name: 'already-applied bank row',
          failure: PostgrestException(
            message: 'payroll_statement_row_already_applied',
            code: 'P0001',
          ),
          recoveryAction: 'reload',
          copyFragment: 'Recarga',
        ),
        (
          name: 'invalid payment account configuration',
          failure: PostgrestException(
            message: 'Payroll payment account not found',
            code: '42501',
          ),
          recoveryAction: 'fixPaymentConfiguration',
          copyFragment: 'cuenta',
        ),
        (
          name: 'caller permission failure',
          failure: PostgrestException(
            message:
                'permission denied for function apply_payroll_statement_reconciliation',
            code: '42501',
          ),
          recoveryAction: 'reviewPermissions',
          copyFragment: 'permis',
        ),
      ];

      for (final scenario in scenarios) {
        test('${scenario.name} does not degrade into generic retry', () async {
          final harness = _Harness();
          addTearDown(harness.dispose);
          final draft = await harness.prepare();
          harness.database.sensitiveRpcHandler =
              (functionName, params) => throw scenario.failure;

          Object? captured;
          try {
            await harness.reconciliationService.apply(
              draft: draft,
              importReceipt: _importReceipt(draft),
              operationKey: _explicitRetryKey,
              decisions: _reviewDecisions(draft),
              authorizedDraftVoucherIds: const {_voucherId},
            );
          } catch (error) {
            captured = error;
          }

          if (captured is! PayrollReconciliationServiceException) {
            fail(
              'Expected a typed PayrollReconciliationServiceException for '
              '${scenario.name}, got $captured.',
            );
          }
          final dynamic typedFailure = captured;
          expect(
            typedFailure.recoveryAction.toString(),
            endsWith(scenario.recoveryAction),
          );
          expect(typedFailure.canRetrySameOperation, isFalse);
          expect(
            captured.message.toLowerCase(),
            contains(scenario.copyFragment.toLowerCase()),
          );
          expect(harness.payrollService.cacheInvalidationCount, 0);
        });
      }

      test('ambiguous network failure permits only same-operation retry',
          () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final draft = await harness.prepare();
        harness.database.sensitiveRpcHandler = (functionName, params) {
          throw const PostgrestException(
            message: 'connection failed at internal.example.invalid',
            code: 'PGRST000',
            details: 'private transport detail',
          );
        };

        Object? captured;
        try {
          await harness.reconciliationService.apply(
            draft: draft,
            importReceipt: _importReceipt(draft),
            operationKey: _explicitRetryKey,
            decisions: _reviewDecisions(draft),
            authorizedDraftVoucherIds: const {_voucherId},
          );
        } catch (error) {
          captured = error;
        }

        expect(captured, isA<PayrollReconciliationServiceException>());
        final typedFailure = captured! as PayrollReconciliationServiceException;
        expect(
          typedFailure.recoveryAction,
          PayrollReconciliationRecoveryAction.retry,
        );
        expect(typedFailure.canRetrySameOperation, isTrue);
        expect(
          typedFailure.message,
          isNot(contains('internal.example.invalid')),
        );
        expect(typedFailure.message, isNot(contains('private transport')));
        expect(harness.payrollService.cacheInvalidationCount, 0);
      });

      test('unclassified server rejection stays deterministic and sanitized',
          () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        final draft = await harness.prepare();
        harness.database.sensitiveRpcHandler = (functionName, params) {
          throw const PostgrestException(
            message: 'sensitive internal rejection detail',
            code: 'P0001',
          );
        };

        await expectLater(
          harness.reconciliationService.apply(
            draft: draft,
            importReceipt: _importReceipt(draft),
            operationKey: _explicitRetryKey,
            decisions: _reviewDecisions(draft),
            authorizedDraftVoucherIds: const {_voucherId},
          ),
          throwsA(
            isA<PayrollReconciliationServiceException>()
                .having(
                  (error) => error.recoveryAction,
                  'recoveryAction',
                  PayrollReconciliationRecoveryAction.none,
                )
                .having(
                  (error) => error.canRetrySameOperation,
                  'canRetrySameOperation',
                  isFalse,
                )
                .having(
                  (error) => error.message,
                  'message',
                  isNot(contains('sensitive internal')),
                ),
          ),
        );
      });
    });

    test('rejects an unresolved bank variance without ACK and reason locally',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();

      await expectLater(
        harness.reconciliationService.apply(
          draft: draft,
          importReceipt: _importReceipt(draft),
          operationKey: _explicitRetryKey,
          decisions: _reviewDecisions(
            draft,
            acknowledgeVariance: false,
            includeVarianceReason: false,
          ),
          authorizedDraftVoucherIds: const {_voucherId},
        ),
        throwsA(
          isA<PayrollReconciliationServiceException>().having(
            (error) => error.message,
            'message',
            contains('Confirma y explica'),
          ),
        ),
      );

      expect(harness.database.sensitiveRpcCalls, isEmpty);
      expect(harness.database.databaseRpcCalls, isEmpty);
      expect(harness.payrollService.cacheInvalidationCount, 0);
    });

    test('rejects a bank payment tied to a different ERP account locally',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final draft = await harness.prepare();

      await expectLater(
        harness.reconciliationService.apply(
          draft: draft,
          importReceipt: _importReceipt(draft),
          operationKey: _explicitRetryKey,
          decisions: _reviewDecisions(
            draft,
            bankPaymentAccountId: _otherErpAccountId,
          ),
          authorizedDraftVoucherIds: const {_voucherId},
        ),
        throwsA(
          isA<PayrollReconciliationServiceException>().having(
            (error) => error.message,
            'message',
            contains('misma cuenta ERP'),
          ),
        ),
      );

      expect(harness.database.sensitiveRpcCalls, isEmpty);
      expect(harness.database.databaseRpcCalls, isEmpty);
      expect(harness.payrollService.cacheInvalidationCount, 0);
    });
  });
}

const _tenantId = '00000000-0000-4000-8000-000000000001';
const _voucherId = '00000000-0000-4000-8000-000000000010';
const _unrelatedVoucherId = '00000000-0000-4000-8000-000000000011';
const _transferLineId = '00000000-0000-4000-8000-000000000020';
const _cashLineId = '00000000-0000-4000-8000-000000000021';
const _unrelatedLineId = '00000000-0000-4000-8000-000000000022';
const _transferEmployeeId = '00000000-0000-4000-8000-000000000030';
const _cashEmployeeId = '00000000-0000-4000-8000-000000000031';
const _unrelatedEmployeeId = '00000000-0000-4000-8000-000000000032';
const _transferMethodId = '00000000-0000-4000-8000-000000000040';
const _cashMethodId = '00000000-0000-4000-8000-000000000041';
const _cashAdvanceId = '00000000-0000-4000-8000-000000000050';
const _importId = '00000000-0000-4000-8000-000000000060';
const _priorImportId = '00000000-0000-4000-8000-000000000063';
const _priorDecisionId = '00000000-0000-4000-8000-000000000064';
const _erpAccountId = '00000000-0000-4000-8000-000000000061';
const _otherErpAccountId = '00000000-0000-4000-8000-000000000062';
const _transferStatementRowId = '00000000-0000-4000-8000-000000000070';
const _cashStatementRowId = '00000000-0000-4000-8000-000000000071';
const _incompleteStatementRowId = '00000000-0000-4000-8000-000000000072';
const _rawAccountNumber = '123-456-789';
const _canonicalAccountNumber = '123456789';
const _expectedAccountFingerprint =
    'd435ff45fff1fb1117c716643e83e3b8b773592dd82b23a33c146411c650bc35';
const _incompleteFingerprint =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _explicitRetryKey = 'retry-payroll-redacted-0001';

class _Harness {
  _Harness({
    List<PayrollVoucher>? vouchers,
  }) : database = _FakeDatabaseService(
          employeeRows: _employeeRows(),
        ) {
    payrollService = _FakePayrollVoucherService(
      database,
      vouchers: vouchers ??
          <PayrollVoucher>[
            _voucher(),
            _unrelatedOpenVoucher(),
          ],
      paymentMethods: _paymentMethods(),
      advances: <EmployeeAdvance>[_openCashAdvance()],
    );
    reconciliationService = PayrollReconciliationService(
      database: database,
      payrollService: payrollService,
      sensitiveRpc: database.callSensitiveRpc,
    );
  }

  final _FakeDatabaseService database;
  late final _FakePayrollVoucherService payrollService;
  late final PayrollReconciliationService reconciliationService;

  Future<PayrollStatementPreparedDraft> prepare({
    String? documentClose,
  }) {
    return reconciliationService.prepare(
      bytes: _syntheticStatementPdf(documentClose: documentClose),
      filename: 'cartola-redactada.pdf',
      statementYear: 2026,
    );
  }

  void dispose() {
    payrollService.dispose();
    database.dispose();
  }
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic> params;
}

class _SelectCall {
  const _SelectCall({
    required this.table,
    required this.where,
    required this.whereIn,
  });

  final String table;
  final String? where;
  final List<String>? whereIn;
}

typedef _RpcHandler = FutureOr<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);
typedef _StatementDecisionSelectHandler = List<Map<String, dynamic>> Function(
  _SelectCall call,
);

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService({
    required List<Map<String, dynamic>> employeeRows,
  }) : employeeRows = employeeRows
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: true);

  final List<Map<String, dynamic>> employeeRows;
  final List<_RpcCall> sensitiveRpcCalls = <_RpcCall>[];
  final List<_RpcCall> databaseRpcCalls = <_RpcCall>[];
  final List<_SelectCall> selectCalls = <_SelectCall>[];
  List<Map<String, dynamic>> persistedStatementRows =
      const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> payrollStatementDecisions =
      const <Map<String, dynamic>>[];
  _StatementDecisionSelectHandler? payrollStatementDecisionSelectHandler;
  List<Map<String, dynamic>> Function(_SelectCall call)?
      payrollBeneficiaryAliasSelectHandler;
  _RpcHandler? sensitiveRpcHandler;

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
    final call = _SelectCall(
      table: table,
      where: where,
      whereIn: whereIn == null ? null : List<String>.unmodifiable(whereIn),
    );
    selectCalls.add(call);
    return switch (table) {
      'employees' => employeeRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
      'payroll_beneficiary_aliases' =>
        payrollBeneficiaryAliasSelectHandler?.call(call) ??
            const <Map<String, dynamic>>[],
      'payroll_statement_decisions' => _selectPayrollStatementDecisions(call),
      'payroll_statement_rows' => persistedStatementRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
      _ => throw StateError('Unexpected synthetic select: $table'),
    };
  }

  List<Map<String, dynamic>> _selectPayrollStatementDecisions(
    _SelectCall call,
  ) {
    final configured = payrollStatementDecisionSelectHandler?.call(call) ??
        payrollStatementDecisions;
    final requestedFingerprints = call.whereIn?.toSet();
    return configured
        .where(
          (row) =>
              requestedFingerprints == null ||
              requestedFingerprints.contains(row['row_fingerprint']),
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<dynamic> callSensitiveRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    final safeParams = Map<String, dynamic>.from(params);
    sensitiveRpcCalls.add(_RpcCall(functionName, safeParams));
    final handler = sensitiveRpcHandler;
    if (handler == null) {
      throw StateError('Unexpected sensitive synthetic RPC: $functionName');
    }
    return handler(functionName, safeParams);
  }

  @override
  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final safeParams = Map<String, dynamic>.from(
      params ?? const <String, dynamic>{},
    );
    databaseRpcCalls.add(_RpcCall(functionName, safeParams));
    throw StateError('Sensitive RPC used DatabaseService: $functionName');
  }
}

class _FakePayrollVoucherService extends PayrollVoucherService {
  _FakePayrollVoucherService(
    super.database, {
    required this.vouchers,
    required this.paymentMethods,
    required this.advances,
  });

  final List<PayrollVoucher> vouchers;
  final List<Map<String, dynamic>> paymentMethods;
  final List<EmployeeAdvance> advances;
  int cacheInvalidationCount = 0;

  @override
  Future<List<PayrollVoucher>> fetchVouchers({
    bool forceRefresh = false,
  }) async {
    expect(forceRefresh, isTrue);
    return List<PayrollVoucher>.from(vouchers);
  }

  @override
  Future<PayrollVoucher> hydrateVoucherSettlements(
    PayrollVoucher voucher,
  ) async {
    return voucher;
  }

  @override
  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    return paymentMethods
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  @override
  Future<List<EmployeeAdvance>> getOpenEmployeeAdvances() async {
    return List<EmployeeAdvance>.from(advances);
  }

  @override
  void invalidateVouchersCache() {
    cacheInvalidationCount += 1;
  }
}

List<Map<String, dynamic>> _employeeRows() {
  return const <Map<String, dynamic>>[
    <String, dynamic>{
      'id': _transferEmployeeId,
      'first_name': 'Persona',
      'last_name': 'Uno',
      'status': 'active',
      'preferred_payment_method': 'transfer',
      'preferred_payment_method_id': null,
    },
    <String, dynamic>{
      'id': _cashEmployeeId,
      'first_name': 'Persona',
      'last_name': 'Caja',
      'status': 'active',
      'preferred_payment_method': 'cash',
      'preferred_payment_method_id': _cashMethodId,
    },
    <String, dynamic>{
      'id': _unrelatedEmployeeId,
      'first_name': 'Persona',
      'last_name': 'Sin Movimiento',
      'status': 'active',
      'preferred_payment_method': 'transfer',
      'preferred_payment_method_id': _transferMethodId,
    },
  ];
}

List<Map<String, dynamic>> _paymentMethods() {
  return const <Map<String, dynamic>>[
    <String, dynamic>{
      'id': _transferMethodId,
      'code': 'transfer',
      'name': 'Transferencia',
      'account_id': _erpAccountId,
      'is_active': true,
    },
    <String, dynamic>{
      'id': _cashMethodId,
      'code': 'cash',
      'name': 'Efectivo',
      'account_id': _otherErpAccountId,
      'is_active': true,
    },
  ];
}

PayrollVoucher _voucher() {
  return PayrollVoucher(
    id: _voucherId,
    tenantId: _tenantId,
    voucherNumber: 'NOM-TEST-0030',
    periodStart: DateTime(2026, 7, 20),
    periodEnd: DateTime(2026, 7, 26),
    periodLabel: 'Semana sintética 30',
    totalHours: 47.5,
    totalAmount: 165750,
    employeeCount: 2,
    status: PayrollVoucherStatus.draft,
    createdAt: DateTime.utc(2026, 7, 26, 20),
    updatedAt: DateTime.utc(2026, 7, 26, 21),
    reconciliationVersion: 7,
    lines: const <PayrollVoucherLine>[
      PayrollVoucherLine(
        id: _transferLineId,
        voucherId: _voucherId,
        employeeId: _transferEmployeeId,
        employeeName: 'Persona Uno',
        totalAmount: 127750,
        balance: 127750,
        paymentMethod: 'transfer',
      ),
      PayrollVoucherLine(
        id: _cashLineId,
        voucherId: _voucherId,
        employeeId: _cashEmployeeId,
        employeeName: 'Persona Caja',
        totalAmount: 38000,
        balance: 38000,
        paymentMethod: 'transfer',
      ),
    ],
  );
}

PayrollVoucher _unrelatedOpenVoucher() {
  return PayrollVoucher(
    id: _unrelatedVoucherId,
    tenantId: _tenantId,
    voucherNumber: 'NOM-TEST-0028',
    periodStart: DateTime(2026, 7, 6),
    periodEnd: DateTime(2026, 7, 12),
    periodLabel: 'Semana sintética sin movimiento',
    totalHours: 10,
    totalAmount: 50000,
    employeeCount: 1,
    status: PayrollVoucherStatus.draft,
    createdAt: DateTime.utc(2026, 7, 12, 20),
    updatedAt: DateTime.utc(2026, 7, 12, 21),
    reconciliationVersion: 9,
    lines: const <PayrollVoucherLine>[
      PayrollVoucherLine(
        id: _unrelatedLineId,
        voucherId: _unrelatedVoucherId,
        employeeId: _unrelatedEmployeeId,
        employeeName: 'Persona Sin Movimiento',
        totalAmount: 50000,
        balance: 50000,
        paymentMethod: 'transfer',
        paymentMethodId: _transferMethodId,
      ),
    ],
  );
}

EmployeeAdvance _openCashAdvance() {
  return EmployeeAdvance(
    id: _cashAdvanceId,
    employeeId: _cashEmployeeId,
    amount: 36000,
    amountApplied: 0,
    paidAt: DateTime(2026, 7, 11),
    status: 'open',
    paymentMethodId: _cashMethodId,
    reference: 'ANTICIPO-TEST',
  );
}

PayrollStatementImportReceipt _importReceipt(
  PayrollStatementPreparedDraft draft, {
  Map<String, String>? priorDecisionIdsBySourceRowId,
}) {
  final transferSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 128000)
      .sourceRowId;
  final cashSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 38000)
      .sourceRowId;
  return PayrollStatementImportReceipt(
    importId: _importId,
    operationKey: draft.operationKey,
    wasReplay: false,
    erpAccountId: _erpAccountId,
    rowIdsBySourceRowId: <String, String>{
      transferSourceRowId: _transferStatementRowId,
      cashSourceRowId: _cashStatementRowId,
    },
    rowFingerprintsBySourceRowId: <String, String>{
      transferSourceRowId:
          draft.rowFingerprintsBySourceRowId[transferSourceRowId]!,
      cashSourceRowId: draft.rowFingerprintsBySourceRowId[cashSourceRowId]!,
    },
    priorDecisionIdsBySourceRowId:
        priorDecisionIdsBySourceRowId ?? draft.priorDecisionIdsBySourceRowId,
    raw: _serverImportReceipt(draft),
  );
}

Map<String, dynamic> _priorDecisionRow({
  required String rowFingerprint,
}) {
  return <String, dynamic>{
    'id': _priorDecisionId,
    'row_fingerprint': rowFingerprint,
    'import_id': _priorImportId,
    'action': 'bank_payment',
    'outcome': 'applied',
    'decided_at': '2026-07-27T18:00:00Z',
  };
}

List<PayrollStatementReviewDecision> _reviewDecisions(
  PayrollStatementPreparedDraft draft, {
  bool acknowledgeVariance = true,
  bool includeVarianceReason = true,
  String bankPaymentAccountId = _erpAccountId,
}) {
  final transferSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 128000)
      .sourceRowId;
  final cashSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 38000)
      .sourceRowId;
  return <PayrollStatementReviewDecision>[
    PayrollStatementReviewDecision(
      kind: PayrollReviewDecisionKind.bankPayment,
      sourceRowId: transferSourceRowId,
      voucherLineId: _transferLineId,
      voucherId: _voucherId,
      employeeId: _transferEmployeeId,
      amountClp: 127750,
      paymentDate: const PayrollCivilDate(2026, 7, 27),
      paymentMethodId: _transferMethodId,
      paymentAccountId: bankPaymentAccountId,
      varianceDisposition: PayrollVarianceDisposition.unresolved,
      manualConfirmation: acknowledgeVariance,
      note: includeVarianceReason ? 'Diferencia visible para revisión' : null,
    ),
    PayrollStatementReviewDecision(
      kind: PayrollReviewDecisionKind.ignore,
      sourceRowId: cashSourceRowId,
      note: 'No corresponde a una nómina',
      manualConfirmation: true,
    ),
  ];
}

PayrollStatementPreparedDraft _withIncompleteEvidence(
  PayrollStatementPreparedDraft draft,
) {
  final incompleteRow = PayrollStatementRow(
    bookingDate: null,
    description: 'TRANSFERENCIA OCR CORTADA',
    documentNumber: 'OCR-003',
    debitAmountClp: 22000,
    creditAmountClp: null,
    balanceAmountClp: null,
    direction: PayrollStatementMovementDirection.outgoing,
    evidence: const PayrollStatementRowEvidence(
      sourceRowNumber: 3,
      startPageNumber: 1,
      startLineNumber: 3,
      endPageNumber: 1,
      endLineNumber: 3,
    ),
    parseWarningCodes: const <String>['ocr_missing_date'],
  );
  final rows = <PayrollStatementRow>[
    ...draft.parseResult.rows,
    incompleteRow,
  ];
  return PayrollStatementPreparedDraft(
    operationKey: draft.operationKey,
    filename: draft.filename,
    extraction: draft.extraction,
    parseResult: PayrollBankStatementParseResult(
      rows: rows,
      warnings: draft.parseResult.warnings,
    ),
    reconciliation: PayrollStatementReconciliationResult(
      statementRows: <PayrollStatementRow>[
        ...draft.reconciliation.statementRows,
        incompleteRow,
      ],
      lineResults: draft.reconciliation.lineResults,
    ),
    vouchersById: draft.vouchersById,
    employeeRowsById: draft.employeeRowsById,
    paymentMethods: draft.paymentMethods,
    openAdvances: draft.openAdvances,
    missingCanonicalPaymentMethodEmployeeIds:
        draft.missingCanonicalPaymentMethodEmployeeIds,
    rowFingerprintsBySourceRowId: <String, String>{
      ...draft.rowFingerprintsBySourceRowId,
      incompleteRow.sourceRowId: _incompleteFingerprint,
    },
    expectedVoucherVersionsById: draft.expectedVoucherVersionsById,
    accountFingerprint: draft.accountFingerprint,
    priorDecisionIdsBySourceRowId: draft.priorDecisionIdsBySourceRowId,
    statementYear: draft.statementYear,
    documentDate: draft.documentDate,
  );
}

PayrollStatementPreparedDraft _withExtraction(
  PayrollStatementPreparedDraft draft,
  PayrollStatementExtractionResult extraction,
) {
  return PayrollStatementPreparedDraft(
    operationKey: draft.operationKey,
    filename: draft.filename,
    extraction: extraction,
    parseResult: draft.parseResult,
    reconciliation: draft.reconciliation,
    vouchersById: draft.vouchersById,
    employeeRowsById: draft.employeeRowsById,
    paymentMethods: draft.paymentMethods,
    openAdvances: draft.openAdvances,
    missingCanonicalPaymentMethodEmployeeIds:
        draft.missingCanonicalPaymentMethodEmployeeIds,
    rowFingerprintsBySourceRowId: draft.rowFingerprintsBySourceRowId,
    expectedVoucherVersionsById: draft.expectedVoucherVersionsById,
    accountFingerprint: draft.accountFingerprint,
    priorDecisionIdsBySourceRowId: draft.priorDecisionIdsBySourceRowId,
    statementYear: draft.statementYear,
    documentDate: draft.documentDate,
  );
}

List<Map<String, dynamic>> _persistedStatementRowsFor(
  PayrollStatementPreparedDraft draft,
) {
  expect(draft.parseResult.rows, hasLength(2));
  final transferSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 128000)
      .sourceRowId;
  final cashSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 38000)
      .sourceRowId;
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'id': _transferStatementRowId,
      'row_ordinal': 1,
      'fingerprint': draft.rowFingerprintsBySourceRowId[transferSourceRowId],
    },
    <String, dynamic>{
      'id': _cashStatementRowId,
      'row_ordinal': 2,
      'fingerprint': draft.rowFingerprintsBySourceRowId[cashSourceRowId],
    },
  ];
}

Map<String, dynamic> _serverImportReceipt(
  PayrollStatementPreparedDraft draft,
) {
  final transferSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 128000)
      .sourceRowId;
  final cashSourceRowId = draft.parseResult.rows
      .singleWhere((row) => row.debitAmountClp == 38000)
      .sourceRowId;
  return <String, dynamic>{
    'import_id': _importId,
    'status': 'review',
    'row_count': 2,
    'rows': <Map<String, dynamic>>[
      <String, dynamic>{
        'row_id': _transferStatementRowId,
        'fingerprint': draft.rowFingerprintsBySourceRowId[transferSourceRowId],
        'ordinal': 1,
      },
      <String, dynamic>{
        'row_id': _cashStatementRowId,
        'fingerprint': draft.rowFingerprintsBySourceRowId[cashSourceRowId],
        'ordinal': 2,
      },
    ],
    'file_sha256':
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    'payload_hash':
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  };
}

Uint8List _syntheticStatementPdf({
  String? documentClose,
}) {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    'Cuenta N°: $_rawAccountNumber',
    PdfStandardFont(PdfFontFamily.helvetica, 9),
    bounds: const Rect.fromLTWH(18, 18, 300, 20),
  );
  if (documentClose != null) {
    page.graphics.drawString(
      'Movimientos al $documentClose',
      PdfStandardFont(PdfFontFamily.helvetica, 9),
      bounds: const Rect.fromLTWH(18, 30, 300, 20),
    );
  }
  page.graphics.drawString(
    '27/07/2026 App-traspaso A: Persona Uno '
    r'000101 $128.000 $900.000'
    '\n'
    '27/07/2026 App-traspaso A: Persona Caja '
    r'000102 $38.000 $862.000',
    PdfStandardFont(PdfFontFamily.helvetica, 9),
    bounds: Rect.fromLTWH(18, documentClose == null ? 42 : 54, 560, 680),
  );
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}
