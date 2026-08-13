import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_controller.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_models.dart';

void main() {
  group('PayrollPaymentWorkspaceRequest', () {
    test('single has no OCR source and batch groups newest weeks first', () {
      final older = _target(
        id: 'older',
        voucherId: 'voucher-older',
        periodStart: const PayrollCivilDate(2026, 7, 20),
        periodEnd: const PayrollCivilDate(2026, 7, 26),
      );
      final newer = _target(
        id: 'newer',
        voucherId: 'voucher-newer',
        periodStart: const PayrollCivilDate(2026, 7, 27),
        periodEnd: const PayrollCivilDate(2026, 8, 2),
      );

      final single = PayrollPaymentWorkspaceRequest.single(target: older);
      final batch = PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[older, newer],
      );

      expect(single.mode, PayrollPaymentWorkspaceMode.single);
      expect(single.ocrSource, isNull);
      expect(batch.groups.map((group) => group.voucherId), <String>[
        'voucher-newer',
        'voucher-older',
      ]);
      expect(batch.targetById('newer'), same(newer));
      expect(batch.targetById('missing'), isNull);
    });
  });

  group('PayrollPaymentWorkspaceController', () {
    test('OCR selection only prefills a capped editable salary leg', () {
      final evidence = _evidence(amountClp: 133000);
      final target = _target(
        balanceClp: 125000,
        candidates: <PayrollOcrPaymentCandidate>[
          PayrollOcrPaymentCandidate(
            candidateId: 'candidate-1',
            evidence: evidence,
            selectedForPrefill: true,
            suggestedPaymentMethodId: 'transfer',
            suggestedPaymentAccountId: 'bank',
          ),
        ],
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
            targets: <PayrollPaymentTarget>[target]),
      );

      final draft = controller.draftFor(target.targetId);
      expect(draft.salaryLegs, hasLength(1));
      expect(draft.salaryLegs.single.amountClp, 125000);
      expect(draft.salaryLegs.single.ocrEvidence, same(evidence));
      expect(draft.remainingClp, 0);
      expect(controller.isDirty(target.targetId), isTrue);
      expect(controller.hasManualAdjustments(target.targetId), isFalse);

      controller.setOcrCandidateSelected(target.targetId, 'candidate-1', false);
      expect(controller.draftFor(target.targetId).salaryLegs, isEmpty);
      expect(controller.hasManualAdjustments(target.targetId), isTrue);
    });

    test('serializes multiple payments and an advance for the existing RPC',
        () {
      final target = _target(
        balanceClp: 100000,
        advances: const <PayrollAdvanceOption>[
          PayrollAdvanceOption(
            advanceId: 'advance-1',
            label: 'Anticipo efectivo',
            availableAmountClp: 20000,
          ),
        ],
      );
      final controller = _controller(target);
      controller.addPaymentLeg(
        target.targetId,
        const PayrollPaymentLeg.payment(
          legId: 'cash',
          amountClp: 50000,
          paymentMethodId: 'cash',
          paymentAccountId: 'cashbox',
          paymentDate: PayrollCivilDate(2026, 8, 11),
          notes: 'Retiro acordado',
        ),
      );
      controller.addPaymentLeg(
        target.targetId,
        const PayrollPaymentLeg.payment(
          legId: 'transfer',
          amountClp: 30000,
          paymentMethodId: 'transfer',
          paymentAccountId: 'bank',
          paymentDate: PayrollCivilDate(2026, 8, 11),
          reference: 'cartola-row-7',
        ),
      );
      controller.toggleAdvance(target.targetId, 'advance-1');

      expect(controller.validationFor(target.targetId).isValid, isTrue);
      expect(controller.draftFor(target.targetId).remainingClp, 0);
      expect(controller.serializeSalarySplits(target.targetId), <Object>[
        <String, dynamic>{
          'kind': 'payment',
          'payment_method_id': 'cash',
          'payment_account_id': 'cashbox',
          'amount': 50000,
          'payment_date': '2026-08-11T12:00:00.000Z',
          'notes': 'Retiro acordado',
        },
        <String, dynamic>{
          'kind': 'payment',
          'payment_method_id': 'transfer',
          'payment_account_id': 'bank',
          'amount': 30000,
          'payment_date': '2026-08-11T12:00:00.000Z',
          'reference': 'cartola-row-7',
        },
        <String, dynamic>{
          'kind': 'advance',
          'advance_id': 'advance-1',
          'amount': 20000,
        },
      ]);
    });

    test('allows a partial salary payment and records the remaining balance',
        () {
      final target = _target(balanceClp: 75000);
      final controller = _controller(target);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'partial', amountClp: 20000),
      );

      final draft = controller.draftFor(target.targetId);
      final validation = controller.validationFor(target.targetId);
      expect(validation.isValid, isTrue);
      expect(draft.salaryAppliedClp, 20000);
      expect(draft.remainingClp, 55000);
      expect(validation.payrollRemainingClp, 55000);
      expect(validation.remainingClp, 55000);
    });

    test('rejects non-positive parts and salary above the target balance', () {
      final target = _target(balanceClp: 50000);
      final controller = _controller(target);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'zero', amountClp: 0),
      );
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'too-much', amountClp: 60000),
      );

      final codes = controller
          .validationFor(target.targetId)
          .issues
          .map((issue) => issue.code);
      expect(codes, contains(PayrollPaymentValidationCode.amountNotPositive));
      expect(
          codes, contains(PayrollPaymentValidationCode.salaryBalanceExceeded));
    });

    test('prevents assigning the same bank evidence above its amount', () {
      final evidence = _evidence(amountClp: 100000);
      PayrollPaymentTarget withCandidate(String id) => _target(
            id: id,
            voucherId: 'voucher-$id',
            balanceClp: 80000,
            candidates: <PayrollOcrPaymentCandidate>[
              PayrollOcrPaymentCandidate(
                candidateId: 'candidate-$id',
                evidence: evidence,
                selectedForPrefill: true,
                suggestedPaymentMethodId: 'transfer',
                suggestedPaymentAccountId: 'bank',
              ),
            ],
          );
      final first = withCandidate('first');
      final second = withCandidate('second');
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[first, second],
        ),
      );

      for (final target in <PayrollPaymentTarget>[first, second]) {
        expect(
          controller
              .validationFor(target.targetId)
              .issues
              .map((issue) => issue.code),
          contains(PayrollPaymentValidationCode.evidenceAmountExceeded),
        );
      }
    });

    test('shares one statement movement between salary and a separate concept',
        () {
      final evidence = _evidence(amountClp: 80000);
      final target = _target(
        balanceClp: 70000,
        candidates: <PayrollOcrPaymentCandidate>[
          PayrollOcrPaymentCandidate(
            candidateId: 'salary-and-supplies',
            evidence: evidence,
            selectedForPrefill: true,
            suggestedPaymentMethodId: 'transfer',
            suggestedPaymentAccountId: 'bank',
          ),
        ],
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[target],
        ),
        additionalConceptsSupported: true,
      );

      expect(
        controller.availableEvidenceAmount(target.targetId, evidence),
        10000,
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'supplies',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Cajas para el taller',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          disposition: PayrollAdditionalConceptDisposition.additional,
          paymentLegs: <PayrollPaymentLeg>[
            PayrollPaymentLeg.payment(
              legId: 'supplies-payment',
              amountClp: 10000,
              paymentMethodId: 'transfer',
              paymentAccountId: 'bank',
              paymentDate: const PayrollCivilDate(2026, 8, 11),
              ocrEvidence: evidence,
            ),
          ],
        ),
      );

      expect(
        controller.availableEvidenceAmount(target.targetId, evidence),
        0,
      );
      expect(controller.validationFor(target.targetId).isValid, isTrue);

      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'over-allocation',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Monto duplicado',
          amountClp: 1,
          expenseAccountId: 'workshop-supplies',
          disposition: PayrollAdditionalConceptDisposition.additional,
          paymentLegs: <PayrollPaymentLeg>[
            PayrollPaymentLeg.payment(
              legId: 'over-allocation-payment',
              amountClp: 1,
              paymentMethodId: 'transfer',
              paymentAccountId: 'bank',
              paymentDate: const PayrollCivilDate(2026, 8, 11),
              ocrEvidence: evidence,
            ),
          ],
        ),
      );
      expect(
        controller
            .validationFor(target.targetId)
            .issues
            .map((issue) => issue.code),
        contains(PayrollPaymentValidationCode.evidenceAmountExceeded),
      );
    });

    test('bank statement evidence cannot be saved as a cash payment', () {
      final evidence = _evidence(amountClp: 50000);
      final target = _target(
        balanceClp: 50000,
        candidates: <PayrollOcrPaymentCandidate>[
          PayrollOcrPaymentCandidate(
            candidateId: 'cash-mismatch',
            evidence: evidence,
            selectedForPrefill: true,
            suggestedPaymentMethodId: 'cash',
            suggestedPaymentAccountId: 'cashbox',
          ),
        ],
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[target],
          paymentMethods: const <PayrollPaymentMethodOption>[
            PayrollPaymentMethodOption(
              methodId: 'cash',
              label: 'Efectivo',
              code: 'cash',
              accountId: 'cashbox',
            ),
          ],
        ),
      );

      expect(
        controller
            .validationFor(target.targetId)
            .issues
            .map((issue) => issue.code),
        contains(
          PayrollPaymentValidationCode.statementEvidenceRequiresTransfer,
        ),
      );
    });

    test('keeps additional concepts separate and blocks unsupported writes',
        () {
      final target = _target(balanceClp: 70000);
      final controller = _controller(target);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'salary', amountClp: 70000),
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'supplies',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Cajas para el taller',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          disposition: PayrollAdditionalConceptDisposition.additional,
          paymentLegs: <PayrollPaymentLeg>[
            _paymentLeg(id: 'supplies-payment', amountClp: 10000),
          ],
        ),
      );

      final draft = controller.draftFor(target.targetId);
      expect(draft.salaryAppliedClp, 70000);
      expect(draft.additionalConceptsTotalClp, 10000);
      expect(draft.coverageTotalClp, 80000);
      expect(draft.hasUnsupportedConcepts, isTrue);
      expect(
        controller
            .validationFor(target.targetId)
            .issues
            .map((issue) => issue.code),
        contains(PayrollPaymentValidationCode.unsupportedAdditionalConcepts),
      );
      expect(controller.serializeSalarySplits(target.targetId), hasLength(1));
    });

    test(
        'an included concept reclassifies part of payroll without leaving a balance',
        () {
      final target = _target(balanceClp: 72000);
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(target: target),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'salary', amountClp: 62000),
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'boxes-reimbursement',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Reembolso por cajas plásticas',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          paymentLegs: <PayrollPaymentLeg>[
            _paymentLeg(id: 'boxes-payment', amountClp: 10000),
          ],
        ),
      );

      final draft = controller.draftFor(target.targetId);
      final validation = controller.validationFor(target.targetId);
      expect(
        draft.additionalConcepts.single.disposition,
        PayrollAdditionalConceptDisposition.includedInPayrollTotal,
      );
      expect(draft.salaryAppliedClp, 62000);
      expect(draft.includedConceptsTotalClp, 10000);
      expect(draft.additionalConceptsAdditiveTotalClp, 0);
      expect(draft.additionalConceptsFundedClp, 10000);
      expect(draft.payrollCoverageClp, 72000);
      expect(draft.totalObligationClp, 72000);
      expect(draft.appliedTotalClp, 72000);
      expect(draft.remainingClp, 0);
      expect(validation.salaryAppliedClp, 62000);
      expect(validation.payrollCoverageClp, 72000);
      expect(validation.totalObligationClp, 72000);
      expect(validation.appliedTotalClp, 72000);
      expect(validation.payrollRemainingClp, 0);
      expect(validation.remainingClp, 0);
      expect(validation.isValid, isTrue);
    });

    test('an additional concept extends the worker total', () {
      final target = _target(balanceClp: 72000);
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(target: target),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'salary', amountClp: 72000),
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'bonus',
          type: PayrollAdditionalConceptType.workCompensation,
          description: 'Bono extraordinario',
          amountClp: 10000,
          expenseAccountId: 'bonus-expense',
          disposition: PayrollAdditionalConceptDisposition.additional,
          paymentLegs: <PayrollPaymentLeg>[
            _paymentLeg(id: 'bonus-payment', amountClp: 10000),
          ],
        ),
      );

      final draft = controller.draftFor(target.targetId);
      expect(draft.includedConceptsTotalClp, 0);
      expect(draft.additionalConceptsAdditiveTotalClp, 10000);
      expect(draft.totalObligationClp, 82000);
      expect(draft.appliedTotalClp, 82000);
      expect(draft.remainingClp, 0);
      expect(controller.validationFor(target.targetId).isValid, isTrue);
    });

    test('an unfunded additive concept never reopens the payroll balance', () {
      final target = _target(balanceClp: 72000);
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(target: target),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'salary', amountClp: 72000),
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'unfunded-additional',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Gasto que se suma aparte',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          disposition: PayrollAdditionalConceptDisposition.additional,
        ),
      );

      final validation = controller.validationFor(target.targetId);
      expect(validation.payrollRemainingClp, 0);
      expect(validation.remainingClp, 10000);
      expect(
        validation.issues.map((issue) => issue.code),
        contains(PayrollPaymentValidationCode.conceptFundingMismatch),
      );
    });

    test('included concepts cannot exceed the original payroll balance', () {
      final target = _target(balanceClp: 72000);
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(target: target),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);
      controller.addPaymentLeg(
        target.targetId,
        _paymentLeg(id: 'salary', amountClp: 70000),
      );
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'boxes-reimbursement',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Reembolso por cajas plásticas',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          paymentLegs: <PayrollPaymentLeg>[
            _paymentLeg(id: 'boxes-payment', amountClp: 10000),
          ],
        ),
      );

      expect(
        controller
            .validationFor(target.targetId)
            .issues
            .map((issue) => issue.code),
        contains(PayrollPaymentValidationCode.salaryBalanceExceeded),
      );
    });

    test(
        'batch omite una referencia bancaria inexistente y deja que el servidor genere la interna',
        () async {
      final target = _target(
        id: 'default-transfer',
        voucherId: 'voucher-confirmed',
        balanceClp: 72000,
      );
      final saved = <PayrollPaymentTargetSaveCommand>[];
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[target],
          paymentMethods: const <PayrollPaymentMethodOption>[
            PayrollPaymentMethodOption(
              methodId: 'transfer',
              label: 'Transferencia',
              code: 'transfer',
              accountId: 'bank',
              requiresReference: true,
            ),
          ],
        ),
        onSaveBatch: (commands, _) async => saved.addAll(commands),
      );
      addTearDown(controller.dispose);

      final leg = controller.draftFor(target.targetId).salaryLegs.single;
      expect(leg.amountClp, target.salaryBalanceClp);
      expect(leg.reference, isNull);
      expect(controller.validationFor(target.targetId).isValid, isTrue);
      expect(
        controller.serializeSalarySplits(target.targetId).single,
        isNot(contains('reference')),
      );
      expect(controller.canSaveBatch, isTrue);

      await controller.saveBatch();

      expect(saved, hasLength(1));
      expect(saved.single.salaryLegs.single.reference, isNull);
      expect(saved.single.salarySplits.single, isNot(contains('reference')));
    });

    test('un concepto mantiene la referencia exigida por su método', () {
      final target = _target(balanceClp: 0);
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(
          target: target,
          paymentMethods: const <PayrollPaymentMethodOption>[
            PayrollPaymentMethodOption(
              methodId: 'transfer',
              label: 'Transferencia',
              code: 'transfer',
              accountId: 'bank',
              requiresReference: true,
            ),
          ],
        ),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);
      controller.addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'supplies',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Cajas para el taller',
          amountClp: 10000,
          expenseAccountId: 'workshop-supplies',
          disposition: PayrollAdditionalConceptDisposition.additional,
          paymentLegs: <PayrollPaymentLeg>[
            _paymentLeg(id: 'supplies-transfer', amountClp: 10000),
          ],
        ),
      );

      expect(
        controller
            .validationFor(target.targetId)
            .issues
            .map((issue) => issue.code),
        contains(PayrollPaymentValidationCode.paymentReferenceRequired),
      );
    });

    test(
        'aprueba sólo semanas pendientes con CAS y conserva los borradores preparados',
        () async {
      final draftTarget = _target(
        id: 'draft-worker',
        voucherId: 'voucher-draft',
        voucherStatus: 'draft',
        reconciliationVersion: 7,
      );
      final confirmedTarget = _target(
        id: 'confirmed-worker',
        voucherId: 'voucher-confirmed',
        voucherStatus: 'confirmed',
        reconciliationVersion: 4,
      );
      final approvalCalls =
          <({List<PayrollPaymentWeekApprovalRequest> requests, String key})>[];
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[draftTarget, confirmedTarget],
          paymentMethods: const <PayrollPaymentMethodOption>[
            PayrollPaymentMethodOption(
              methodId: 'cash',
              label: 'Efectivo',
              code: 'cash',
              accountId: 'cashbox',
            ),
          ],
        ),
        operationKeyFactory: () => 'approval-operation-key',
        onApproveWeeks: (requests, operationKey) async {
          approvalCalls.add((requests: requests, key: operationKey));
          return const <PayrollPaymentWeekApprovalResult>[
            PayrollPaymentWeekApprovalResult(
              voucherId: 'voucher-draft',
              reconciliationVersion: 8,
            ),
          ];
        },
      );
      addTearDown(controller.dispose);
      final salaryLegsBefore = <String, List<PayrollPaymentLeg>>{
        for (final target in controller.request.targets)
          target.targetId: controller.draftFor(target.targetId).salaryLegs,
      };

      expect(controller.unapprovedWeekCount, 1);
      expect(controller.canSaveBatch, isFalse);
      expect(controller.approvalOperationKey, 'approval-operation-key');
      await expectLater(
        controller.saveBatch(),
        throwsA(isA<PayrollPaymentWeeksApprovalRequiredException>()),
      );

      await controller.approveRemainingWeeks();

      expect(approvalCalls, hasLength(1));
      expect(approvalCalls.single.key, controller.approvalOperationKey);
      expect(approvalCalls.single.requests, hasLength(1));
      expect(
        approvalCalls.single.requests.single.voucherId,
        'voucher-draft',
      );
      expect(
        approvalCalls.single.requests.single.expectedReconciliationVersion,
        7,
      );
      expect(controller.unapprovedWeekCount, 0);
      expect(controller.canSaveBatch, isTrue);
      expect(
        controller.targetById(draftTarget.targetId).voucherStatus,
        'confirmed',
      );
      expect(
        controller.targetById(draftTarget.targetId).reconciliationVersion,
        8,
      );
      for (final entry in salaryLegsBefore.entries) {
        expect(
          controller.draftFor(entry.key).salaryLegs,
          entry.value,
          reason: 'aprobar la semana no debe reconstruir el pago preparado',
        );
      }
    });

    test('saves targets independently and locks a confirmed target', () async {
      final first = _target(id: 'first', voucherId: 'voucher-first');
      final second = _target(id: 'second', voucherId: 'voucher-second');
      final saved = <PayrollPaymentTargetSaveCommand>[];
      var nextKey = 0;
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[first, second],
        ),
        operationKeyFactory: () => 'operation-${++nextKey}',
        onSaveTarget: (command) async => saved.add(command),
      );
      controller.addPaymentLeg(
        first.targetId,
        _paymentLeg(id: 'first-payment', amountClp: 100000),
      );
      controller.addPaymentLeg(
        second.targetId,
        _paymentLeg(id: 'second-payment', amountClp: 100000),
      );

      final firstKey = controller.draftFor(first.targetId).operationKey;
      await controller.saveTarget(first.targetId);
      expect(saved, hasLength(1));
      expect(saved.single.target, same(first));
      expect(saved.single.operationKey, firstKey);
      expect(controller.isSaved(first.targetId), isTrue);
      expect(controller.isDirty(first.targetId), isFalse);
      expect(controller.isDirty(second.targetId), isTrue);

      expect(
        () => controller.updatePaymentLeg(
          first.targetId,
          _paymentLeg(id: 'first-payment', amountClp: 90000),
        ),
        throwsStateError,
      );
      await expectLater(
        controller.saveTarget(first.targetId),
        throwsStateError,
      );
      expect(saved, hasLength(1));
      expect(controller.isSaved(first.targetId), isTrue);
      expect(controller.isDirty(first.targetId), isFalse);
      expect(controller.draftFor(first.targetId).operationKey, firstKey);

      await controller.saveTarget(second.targetId);
      expect(saved, hasLength(2));
      expect(saved.last.target, same(second));
    });

    test('preserves or rotates an operation key according to retry policy',
        () async {
      Future<void> check(
        PayrollPaymentSaveRetryPolicy policy,
        Matcher keyMatcher,
      ) async {
        final target = _target();
        var nextKey = 0;
        final controller = PayrollPaymentWorkspaceController(
          request: PayrollPaymentWorkspaceRequest.single(target: target),
          operationKeyFactory: () => 'operation-${++nextKey}',
          onSaveTarget: (_) async => throw PayrollPaymentWorkspaceSaveException(
            'save failed',
            retryPolicy: policy,
          ),
        );
        controller.addPaymentLeg(
          target.targetId,
          _paymentLeg(id: 'payment', amountClp: 100000),
        );
        final before = controller.draftFor(target.targetId).operationKey;

        await expectLater(
          controller.saveTarget(target.targetId),
          throwsA(isA<PayrollPaymentWorkspaceSaveException>()),
        );
        expect(controller.draftFor(target.targetId).operationKey, keyMatcher);
        if (policy == PayrollPaymentSaveRetryPolicy.sameOperation) {
          expect(controller.draftFor(target.targetId).operationKey, before);
        }
      }

      await check(
        PayrollPaymentSaveRetryPolicy.sameOperation,
        equals('operation-1'),
      );
      await check(
        PayrollPaymentSaveRetryPolicy.newOperation,
        equals('operation-2'),
      );
    });

    test('committed unverified batch is fenced as saved and cannot retry',
        () async {
      final first = _target(id: 'first', voucherId: 'voucher-first');
      final second = _target(id: 'second', voucherId: 'voucher-second');
      var saveCalls = 0;
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[first, second],
        ),
        operationKeyFactory: () => 'stable-operation-key',
        onSaveBatch: (_, operationKey) async {
          saveCalls += 1;
          throw PayrollPaymentCommittedUnverifiedException(
            operationKey: operationKey,
          );
        },
      );
      addTearDown(controller.dispose);
      controller
        ..addPaymentLeg(
          first.targetId,
          _paymentLeg(id: 'first-payment', amountClp: 100000),
        )
        ..addPaymentLeg(
          second.targetId,
          _paymentLeg(id: 'second-payment', amountClp: 100000),
        );

      await expectLater(
        controller.saveBatch(),
        throwsA(isA<PayrollPaymentCommittedUnverifiedException>()),
      );

      expect(saveCalls, 1);
      expect(controller.isBatchSaved, isTrue);
      expect(controller.isBatchCommittedUnverified, isTrue);
      expect(controller.hasDirtyTargets, isFalse);
      expect(controller.batchOperationKey, 'stable-operation-key');
      await expectLater(controller.saveBatch(), throwsStateError);
      expect(saveCalls, 1);
    });
  });
}

PayrollPaymentWorkspaceController _controller(PayrollPaymentTarget target) {
  return PayrollPaymentWorkspaceController(
    request: PayrollPaymentWorkspaceRequest.single(target: target),
  );
}

PayrollPaymentTarget _target({
  String id = 'target',
  String voucherId = 'voucher',
  int balanceClp = 100000,
  PayrollCivilDate periodStart = const PayrollCivilDate(2026, 7, 27),
  PayrollCivilDate periodEnd = const PayrollCivilDate(2026, 8, 2),
  List<PayrollOcrPaymentCandidate> candidates = const [],
  List<PayrollAdvanceOption> advances = const [],
  String voucherStatus = 'confirmed',
  int reconciliationVersion = 1,
}) {
  return PayrollPaymentTarget(
    targetId: id,
    voucherId: voucherId,
    voucherLineId: 'line-$id',
    employeeId: 'employee-$id',
    employeeName: 'Employee $id',
    periodStart: periodStart,
    periodEnd: periodEnd,
    salaryBalanceClp: balanceClp,
    reconciliationVersion: reconciliationVersion,
    voucherStatus: voucherStatus,
    ocrCandidates: candidates,
    availableAdvances: advances,
  );
}

PayrollPaymentLeg _paymentLeg({required String id, required int amountClp}) {
  return PayrollPaymentLeg.payment(
    legId: id,
    amountClp: amountClp,
    paymentMethodId: 'transfer',
    paymentAccountId: 'bank',
    paymentDate: const PayrollCivilDate(2026, 8, 11),
  );
}

PayrollOcrStatementEvidence _evidence({required int amountClp}) {
  return PayrollOcrStatementEvidence(
    sourceRowId: 'row-1',
    fingerprint: 'fingerprint-1',
    ordinal: 1,
    bookingDate: const PayrollCivilDate(2026, 8, 11),
    direction: PayrollStatementMovementDirection.outgoing,
    amountClp: amountClp,
    description: 'Transferencia a trabajador',
    suggestedErpAccountId: 'bank',
  );
}
