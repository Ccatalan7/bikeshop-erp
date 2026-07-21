import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workshop modes keep one table and use guarded commercial actions', () {
    final form = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final operationalStatusBadge = File(
      'lib/shared/widgets/operational_status_badge.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final quotationCoordinator = File(
      'lib/modules/bikeshop/services/mechanic_job_quotation_command_coordinator.dart',
    ).readAsStringSync();
    final formPersistencePolicy = File(
      'lib/modules/bikeshop/services/mechanic_job_form_persistence_policy.dart',
    ).readAsStringSync();
    final visibilityPolicy = File(
      'lib/modules/bikeshop/services/mechanic_job_visibility_policy.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(
      form,
      contains(
        'Cotización sin bicicleta ni componente recibido: genera PDF, pero no factura, stock ni contabilidad hasta aprobarla.',
      ),
    );
    expect(
      form,
      contains(
        'El cliente deja solo un componente. No aumenta el contador de bicicletas.',
      ),
    );
    expect(
      form,
      contains(
        'Puedes cotizar sin recibir una bicicleta. Registra la evaluación previa en Diagnóstico; no se crea ficha técnica, factura, stock ni contabilidad hasta convertir la cotización.',
      ),
    );
    expect(
      form,
      contains(
        'La garantía puede corresponder a una bicicleta completa o a un componente suelto. Elige primero el trabajo original para cargar el diagnóstico correcto.',
      ),
    );
    expect(
      form,
      contains(
        'Este trabajo recibe solo el componente. Registra sus hallazgos en Diagnóstico; no se crea ni se exige una bicicleta ficticia.',
      ),
    );
    expect(form, contains('_clearSelectedBikeObject('));
    expect(form, contains('_warrantySourceSelectionEpoch'));
    expect(form, contains('_warrantySourceObjectMatchesForm('));
    expect(form, contains('mechanicJobStandaloneItemsForForm('));
    expect(form, contains('_warrantySaveCheckpoint.requiresSourceSelection'));
    expect(form, contains('_warrantyCoverageNeedsReason('));
    expect(form, contains('WarrantyEligibility.withinWindow'));
    expect(form, contains('_warrantyCoverageNeedsFinancialReview'));
    expect(
      form,
      contains(
        'La factura tiene pagos vigentes. “Cubierto” queda bloqueado',
      ),
    );
    expect(form, contains('getServiceWarrantySourceByJobId('));
    expect(form, contains('_existingJobLoadError'));
    expect(
      form,
      contains(
        'final existingItemsForSave = await bikeshopService.getJobItems(jobId);',
      ),
      reason:
          'A new bike warranty must re-read the canonical job-bike row created by registration before saving its aggregate.',
    );
    expect(
      form,
      isNot(contains('final existingItemsForSave = widget.jobId == null')),
    );
    expect(
      form,
      isNot(contains('_persistHydratedServiceLocationBackfill')),
      reason:
          'Opening a bicycle/job must hydrate in memory without silently writing a backfill.',
    );
    final exactWarrantyGuard = form.indexOf(
      'if (!_warrantySourceObjectMatchesForm(warrantySource))',
    );
    final firstPersistence = form.indexOf(
      'await _persistPendingBikeProfileOverrides(bikeshopService);',
    );
    expect(exactWarrantyGuard, greaterThanOrEqualTo(0));
    expect(firstPersistence, greaterThan(exactWarrantyGuard));
    expect(
      form.indexOf(
        'if (_jobType == JobType.warranty) {',
        form.indexOf('Widget _buildDiagnosisSection'),
      ),
      lessThan(
        form.indexOf(
          'if (currentTab == null) {',
          form.indexOf('Widget _buildDiagnosisSection'),
        ),
      ),
      reason:
          'Warranty source truth must gate diagnosis before any stale bike tab.',
    );
    expect(form, contains('final shouldCreateInvoice ='));
    expect(form, contains('workflowKind: _existingJob?.workflowKind ??'));
    expect(form, contains('intakeKind: _existingJob?.intakeKind ??'));
    expect(form, contains('modeNeedsReview: _existingJob?.modeNeedsReview,'));
    expect(
      form,
      contains('modeReviewReason: _existingJob?.modeReviewReason,'),
    );
    expect(
      form,
      contains(
        'var requestedDiscountAmount = protectPaymentCommercialSnapshot',
      ),
    );
    expect(
      form,
      contains('discountAmount: protectPaymentCommercialSnapshot'),
    );
    expect(form, contains('bikeshopService.updateJobDiscount('));
    expect(form, contains('El descuento no puede superar el subtotal.'));
    expect(form, contains('bikeshopService.createInvoiceFromJob(jobId)'));
    expect(form, isNot(contains('Aprobar Presupuesto')));
    expect(form, contains('bool get _isFinalQuotationReadOnly'));
    expect(
      form,
      contains('_existingJob?.hasFinalProposalDecision ?? false'),
      reason:
          'A derived expiry must not trap a still-pending quote; staff can extend its validity before a customer decision.',
    );
    expect(form, contains('bool get _isCommercialSnapshotLocked'));
    expect(
      form,
      contains(
        '_isPaymentProtectedCommercialSnapshotLocked',
      ),
      reason:
          'Final quotations and every linked invoice with financial evidence protect their commercial snapshot.',
    );
    expect(form, contains(".from('sales_payments')"));
    expect(form, contains(".isFilter('deleted_at', null)"));
    expect(form, contains(".gt('amount', 0)"));
    expect(form, contains('protectPaymentCommercialSnapshot'));
    expect(
      form,
      contains(
        'status: protectPaymentCommercialSnapshot',
      ),
      reason:
          'The in-memory mirror remains stable while the protected update payload omits lifecycle columns entirely.',
    );
    expect(
      form,
      contains(
        'statusId: protectPaymentCommercialSnapshot',
      ),
    );
    expect(
      form,
      isNot(contains('DropdownButtonFormField<JobStatus>')),
      reason:
          'Operational lifecycle belongs to the table chip; the form must not expose a parallel status selector.',
    );
    expect(
      form,
      contains(
        'if (protectPaymentCommercialSnapshot)',
      ),
      reason:
          'A paid job must run the invoice-authoritative reconciliation branch rather than mutable job-to-invoice projection.',
    );
    expect(
      form,
      contains('} else if (!warrantyDecisionManagedDocument) {'),
    );
    expect(
      form,
      contains('Historial financiero protegido'),
      reason:
          'Staff must understand why commercial fields are locked while diagnosis remains editable.',
    );
    expect(
      form,
      contains('La factura de este trabajo tiene pagos vigentes.'),
      reason: 'Financial lock guidance must apply to normal services too.',
    );
    expect(
      form,
      contains('La factura cambió mientras editabas'),
      reason:
          'A payment discovered at save time must never silently discard commercial edits.',
    );
    expect(
      form,
      contains(
        'protectCommercialSnapshot: protectPaymentCommercialSnapshot',
      ),
      reason:
          'A protected form save must ask the service for a narrow diagnosis-only update.',
    );
    expect(service, contains('bool protectCommercialSnapshot = false'));
    expect(
      service,
      contains('mechanicJobPaymentProtectedUpdatePayload(fullPayload)'),
    );
    for (final protectedColumn in [
      "'status'",
      "'status_id'",
      "'diagnostic_sent_at'",
      "'started_at'",
      "'completed_at'",
      "'delivered_at'",
    ]) {
      expect(
        formPersistencePolicy,
        contains(protectedColumn),
        reason:
            '$protectedColumn must be omitted so UPDATE OF lifecycle triggers cannot fire.',
      );
    }
    expect(
      form,
      contains(
          'if (protectPaymentCommercialSnapshot && existingJobBike == null)'),
      reason:
          'A payment race must not attach a newly selected physical object to the paid job.',
    );
    expect(
      form,
      contains('_hydrateFirstBikeNarrativeFromStandalone(newTab);'),
      reason:
          'Quote/component narrative must follow the first bicycle when an unsaved draft becomes a service.',
    );
    expect(
      form,
      contains('_confirmWarrantySourceContextReplacement()'),
      reason:
          'Changing a warranty source must explicitly acknowledge source-scoped diagnosis loss.',
    );
    expect(
      form,
      contains('mechanicJobWarrantySourceChangeNeedsConfirmation('),
    );
    expect(form, contains('_confirmModeSwitchRemovesBikeContext('));
    expect(form, contains('_moveBikeTabLinesToStandalone();'));
    expect(form, contains('_moveStandaloneLinesToGeneralTab();'));
    expect(form, contains('if (job.convertedAt != null) {'));
    expect(form, contains('mechanicJobConvertedBikeNarrativeValue('));
    expect(
      form,
      contains(
        'Los productos y servicios se conservarán en General para que no tengas que ingresarlos otra vez.',
      ),
      reason:
          'Changing creation mode must explain the diagnosis loss and line preservation before it occurs.',
    );
    expect(form, contains('bool get _hasConvertedQuotationHistory'));
    expect(form, contains('onPressed: _canSaveJob ? _saveJob : null'));
    expect(form, contains('_lockFormContent(content, locked: contentLocked)'));
    expect(form, contains('enabled: !_isCommercialSnapshotLocked'));
    expect(
      form.indexOf('bikeshopService.syncBikeMemoryFromJob(jobId)'),
      greaterThan(
        form.indexOf('await bikeshopService.syncJobToInvoice(jobId);'),
      ),
      reason:
          'Bike memory must reconcile only after the authoritative warranty/invoice phase.',
    );
    expect(
      form,
      contains('_reconcileConfirmedPaymentRaceAfterSaveFailure('),
      reason:
          'A confirmed payment race after partial writes must restore invoice truth before reporting the failure.',
    );
    expect(
      form,
      contains('state.paymentStateUnknown || !state.hasActivePayments'),
      reason: 'Unpaid or uncertain partial saves must not be auto-reconciled.',
    );
    expect(
      form,
      contains(
        'Las conversiones válidas se realizan mediante acciones auditadas de la tabla.',
      ),
    );

    expect(table, contains('InvoicePdfGenerator.generateQuotationPDF('));
    expect(table, contains('final updatedJob = job.copyWith('));
    expect(table, contains('transitionJobStatusByLegacyStatus('));
    expect(table, contains('transitionJobStatus('));
    expect(table, contains('await _loadData();'));
    expect(
      table,
      isNot(contains('_jobs[index] = updatedJob.copyWith(')),
      reason:
          'Status actions must reload server truth instead of inventing lifecycle timestamps in the table.',
    );
    expect(table, isNot(contains('_bikeshopService.updateJobStatus(')));
    expect(table, isNot(contains('_jobStatusService.updateJobStatus(')));
    expect(
      table,
      contains('return isMechanicJobCurrentlyDelivered(job);'),
      reason:
          'The table must delegate delivery classification to the shared visibility policy.',
    );
    expect(
      table,
      contains('final isDelivered = _isJobCurrentlyDelivered(job);'),
      reason:
          'Active/completed filters must use the shared current-delivery classification.',
    );
    expect(
      visibilityPolicy,
      contains('job.customStatus?.triggersDelivery == true'),
      reason:
          'The shared visibility policy must honor tenant delivery statuses, not only the legacy enum.',
    );
    expect(form, contains('bool get _isStatusTransitionLocked'));
    expect(
      form,
      contains('widget.jobId != null && !_isStatusTransitionLocked'),
    );
    expect(
      table,
      contains('OperationalStatusBadge('),
      reason:
          'Paid normal services remain operational through the canonical table action instead of a second form selector.',
    );
    expect(
      operationalStatusBadge,
      contains("tooltip ?? 'Cambiar estado y ver acciones'"),
      reason:
          'The shared operational badge must preserve the canonical table action tooltip.',
    );
    expect(table, contains('discountAmount: job.discountAmount'));
    expect(table, contains('_bikeshopService.convertToBillableJob('));
    expect(
      table,
      contains('job.effectiveQuotationStatus == QuotationStatus.approved'),
    );
    expect(table, contains("value: 'quotation_status'"));
    expect(table, contains('job.proposalDocumentLabelLower'));
    expect(
      table,
      contains("final article = job.isServiceBudget ? 'el' : 'la';"),
    );
    expect(table, contains('await _confirmServiceBudgetConversion(job);'));
    expect(
      table,
      contains('const _JobConversionChoice(targetType: JobType.service)'),
    );
    expect(table, contains("'Clasificación pendiente'"));
    expect(table, contains("'EN EVALUACIÓN'"));
    expect(
      table,
      contains('outcome == WarrantyOutcome.pending &&'),
      reason: 'Pending warranty UI must not hide a linked historical invoice.',
    );
    expect(table, contains('_pendingWarrantyDecisionAttempts'));
    expect(table, contains('operationKey: attempt.operationKey'));
    expect(table, contains('_pendingQuotationTransitionAttempts'));
    expect(table, contains('_pendingQuotationConversionAttempts'));
    expect(table, contains('Future<void> _submitQuotationTransition('));
    expect(table, contains('Future<void> _submitQuotationConversion('));
    expect(
      table,
      contains(
        'if (!identical(_pendingQuotationConversionAttempts[jobId], attempt))',
      ),
      reason:
          'A stale conversion retry must not override a newer bicycle/component choice.',
    );
    expect(
      table,
      contains(
        'if (!identical(_pendingQuotationTransitionAttempts[jobId], attempt))',
      ),
      reason:
          'A stale status retry must not revert a newer quotation decision.',
    );
    expect(
      table,
      contains('MechanicJobQuotationCommandOutcomeUnknown'),
      reason:
          'Unknown quotation outcomes must retain and replay the same semantic attempt.',
    );
    expect(
      table,
      contains('but table refresh failed'),
      reason:
          'A projection refresh failure must not be presented as a rejected command.',
    );
    expect(table, contains('bool rethrowErrors = false'));
    expect(table, contains('if (rethrowErrors) rethrow;'));
    expect(table, contains('forceInvoiceRefresh: true'));
    expect(table, contains('if (outcome == currentOutcome) return;'));
    expect(table, contains('_hasWarrantyPaymentEvidence(job)'));
    expect(table, contains('warrantyPaymentReviewRequired:'));
    expect(
      table,
      contains(
        'Esta garantía tiene pagos vigentes. Primero revisa, revierte o reembolsa el pago desde la factura',
      ),
      reason:
          'A paid historical warranty must expose its invoice and require financial review before becoming covered.',
    );
    expect(
      table,
      contains('MechanicJobWarrantyCommandOutcomeUnknown'),
      reason:
          'Lost acknowledgements must retain the exact warranty operation key.',
    );
    expect(table, contains("'Cotizado: "));
    expect(table, contains('JobIntakeKind.bike'));
    expect(table, contains('_bikeshopService.createInvoiceFromJob(jobId)'));
    expect(
      table,
      isNot(contains("'/sales/invoices/new?job_id=")),
      reason:
          'Workshop invoice creation must pass through the guarded job RPC.',
    );

    expect(service, contains("'create_billable_invoice_from_mechanic_job'"));
    expect(
      quotationCoordinator,
      contains("'transition_mechanic_job_quotation'"),
    );
    expect(
      quotationCoordinator,
      contains("'convert_mechanic_job_to_billable'"),
    );
    expect(
      quotationCoordinator,
      contains(
          'MechanicJobQuotationCommandConfirmation.reconciledFromInvariant'),
      reason:
          'A lost same-state no-event acknowledgement needs a truthful invariant fallback.',
    );
    expect(
      quotationCoordinator,
      contains('request.kind != MechanicJobQuotationCommandKind.transition'),
      reason:
          'Conversion must never be confirmed from a mutable row projection alone.',
    );
    expect(service, contains(".from('mechanic_job_mode_events')"));
    expect(service, contains(".eq('tenant_id', tenantId)"));
    expect(service, contains(".eq('job_id', jobId)"));
    expect(
      service,
      contains(
        'Future<MechanicJobServiceWarranty?> getServiceWarrantySourceByJobId(',
      ),
    );
    expect(service, contains('Future<MechanicJob> updateJobDiscount('));
    expect(registry, contains('Workshop job create/edit'));
    expect(registry, contains('Workshop list actions'));
    expect(registry, contains('downloads a PRESUPUESTO PDF'));
    expect(registry, contains('downloads a COTIZACIÓN PDF'));
  });

  test('ambiguous intake is resolved from the table by an audited command', () {
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/modules/bikeshop/services/mechanic_job_intake_classification_coordinator.dart',
    ).readAsStringSync();

    expect(
      service,
      contains(
        'Future<MechanicJobIntakeClassificationResult> classifyMechanicJobIntake(',
      ),
    );
    expect(service, contains("'classify_mechanic_job_intake'"));
    expect(service, contains('required String operationKey'));
    expect(service, contains('operationKey: operationKey'));
    expect(
      service,
      contains('MechanicJobIntakeClassificationCoordinator('),
    );
    expect(service, contains('invalidateJobBikesCache();'));

    expect(coordinator, contains("'p_operation_key': operationKey"));
    expect(coordinator, contains('request.toRpcParams()'));
    expect(
      coordinator,
      contains(
          'The first request may have committed after its response was lost.'),
    );
    expect(coordinator, contains('reconciledFromReadback'));
    expect(
      coordinator,
      contains('MechanicJobIntakeClassificationOutcomeUnknown'),
    );

    expect(table, contains('Future<void> _classifyJobIntake('));
    expect(table, contains('Future<void> _submitJobIntakeClassification('));
    expect(table, contains('_pendingIntakeClassificationAttempts'));
    expect(table, contains('operationKey: const Uuid().v4()'));
    expect(table, contains('operationKey: attempt.operationKey'));
    expect(table, contains("value: 'classify_intake'"));
    expect(table, contains("Text('Clasificar recepción')"));
    expect(table, contains("Text('Bicicleta completa')"));
    expect(table, contains("Text('Solo componente')"));
    expect(table, contains('bike.customerId == job.customerId'));
    expect(table, contains('bike.isActive'));
    expect(table, contains('subject.isActive'));
    expect(table, contains('_bikeshopService.getJobSubjects()'));
    expect(
      table,
      contains('Selecciona un componente o escribe una descripción clara.'),
    );
    expect(
      table,
      contains('await _bikeshopService.classifyMechanicJobIntake('),
    );
    expect(
      table,
      contains(
        'La clasificación puede haberse guardado; Reintentar reutiliza exactamente la misma operación',
      ),
    );
    expect(
      table,
      isNot(
        contains(
          'No se pudo guardar la clasificación; no se aplicaron cambios',
        ),
      ),
    );

    final reviewActionStart = table.indexOf('if (job.modeNeedsReview) {');
    final reviewActionEnd = table.indexOf(
      '// Warranty job: show its operational meaning',
      reviewActionStart,
    );
    expect(reviewActionStart, greaterThanOrEqualTo(0));
    expect(reviewActionEnd, greaterThan(reviewActionStart));
    final reviewAction = table.substring(reviewActionStart, reviewActionEnd);
    expect(reviewAction, contains('onTap: () => _classifyJobIntake(job)'));
    expect(reviewAction, isNot(contains('_openJobEditor(job)')));
  });

  test('conversion pickers tolerate catalog failure and stale inactive values',
      () {
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();

    final conversionStart = table.indexOf(
      'Future<void> _convertToService(MechanicJob job)',
    );
    final conversionEnd = table.indexOf(
      'Future<void> _markJobAsComplete(',
      conversionStart,
    );
    expect(conversionStart, greaterThanOrEqualTo(0));
    expect(conversionEnd, greaterThan(conversionStart));
    final conversion = table.substring(conversionStart, conversionEnd);

    expect(conversion, contains('try {'));
    expect(conversion, contains('getJobSubjects()'));
    expect(conversion, contains('Error loading conversion subjects'));
    expect(conversion, contains('subjectCatalogError'));
    expect(conversion, contains('subject.isActive'));
    expect(conversion, contains('activeSubjectIds.contains(job.subjectId)'));
    expect(
      conversion,
      contains(
        'job.subjectId == null && existingSubjectDescription?.isNotEmpty == true',
      ),
    );
    expect(conversion, contains('bike.isActive'));
    expect(conversion, contains('customerBikeIds.contains(job.bikeId)'));
    expect(conversion, contains('existingDescriptionSubjectValue'));
    expect(
      conversion,
      contains(r'Usar descripción: $existingSubjectDescription'),
    );
    expect(
      conversion,
      contains(
        'Puedes continuar con una bicicleta o con la descripción manual ya guardada',
      ),
    );
    expect(
      conversion,
      contains(
        'No es seguro convertir como componente sin catálogo ni una descripción ya guardada.',
      ),
    );
  });

  test('canonical schema contains every workshop hardening migration', () {
    final schema = File('supabase/sql/core_schema.sql').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260716010000_redesign_mechanic_job_modes.sql',
    ).readAsStringSync();
    final quotationHardening = File(
      'supabase/migrations/20260716030000_harden_quotation_approval_contract.sql',
    ).readAsStringSync();

    for (final path in const [
      r'\ir ../migrations/20260716010000_redesign_mechanic_job_modes.sql',
      r'\ir ../migrations/20260716020000_repair_nested_invoice_trace_context.sql',
      r'\ir ../migrations/20260716030000_harden_quotation_approval_contract.sql',
      r'\ir ../migrations/20260716040000_add_mechanic_job_intake_classification_command.sql',
      r'\ir ../migrations/20260716070000_harden_warranty_source_object_contract.sql',
      r'\ir ../migrations/20260716080000_add_canonical_mechanic_job_status_transition.sql',
    ]) {
      expect(schema, contains(path));
    }
    expect(migration, contains('mechanic_job_mode_events'));
    expect(migration, contains('workflow_kind'));
    expect(migration, contains('intake_kind'));
    expect(migration, contains('create_billable_invoice_from_mechanic_job'));
    expect(migration, contains('convert_mechanic_job_to_billable'));
    expect(migration, contains('trg_mechanic_jobs_guard_quotation_invoice'));
    expect(
      quotationHardening,
      contains('mechanic_job_quotation_content_snapshot'),
    );
    expect(
      quotationHardening,
      contains('quotation_non_posting_normalized'),
    );
    expect(
      quotationHardening,
      contains('trg_mechanic_job_items_guard_approved_quotation'),
    );
  });

  test(
    'non-bike narratives survive edit and compact deadlines do not overflow',
    () {
      final form = File(
        'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
      ).readAsStringSync();
      final table = File(
        'lib/modules/bikeshop/pages/pegas_table_page.dart',
      ).readAsStringSync();

      final jobHydration = form.indexOf(
        "_clientRequestController.text = job.clientRequest ?? '';",
      );
      final bikeOverride = form.indexOf(
        'if (loadedBikeTabs.isNotEmpty)',
        jobHydration,
      );

      expect(jobHydration, greaterThanOrEqualTo(0));
      expect(
        form.substring(jobHydration, bikeOverride),
        allOf(
          contains("_diagnosisController.text = job.diagnosis ?? '';"),
          contains("_workSummaryController.text = job.workPerformed ?? '';"),
          contains("_technicianNotesController.text = job.notes ?? '';"),
        ),
        reason:
            'Component/quotation jobs have no bike tab, so their narrative must hydrate before the bike-only override.',
      );
      expect(
        table,
        contains("'deadline' || 'state' || 'kpi' || 'priority'"),
        reason:
            'The compact deadline cell needs the same reduced horizontal padding as the other table chips.',
      );
    },
  );
}
