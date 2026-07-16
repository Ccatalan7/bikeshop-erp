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
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(
      form,
      contains(
        'Propuesta para enviar al cliente: genera PDF, pero no factura, stock ni contabilidad hasta aprobarla.',
      ),
    );
    expect(
      form,
      contains(
        'El cliente deja solo un componente. No aumenta el contador de bicicletas.',
      ),
    );
    expect(form, contains('final shouldCreateInvoice ='));
    expect(form, contains('final requestedDiscountAmount = _discountAmount;'));
    expect(form, contains('discountAmount: 0,'));
    expect(form, contains('bikeshopService.updateJobDiscount('));
    expect(form, contains('El descuento no puede superar el subtotal.'));
    expect(form, contains('bikeshopService.createInvoiceFromJob(jobId)'));
    expect(form, isNot(contains('Aprobar Presupuesto')));
    expect(form, contains('bool get _isFinalQuotationReadOnly'));
    expect(
      form,
      contains(
        '_existingJob?.quotationStatus ?? QuotationStatus.pending',
      ),
      reason:
          'A derived expiry must not trap a still-pending quote; staff can extend its validity before a customer decision.',
    );
    expect(form, contains('bool get _isCommercialSnapshotLocked'));
    expect(
      form,
      contains(
        'bool get _isCommercialSnapshotLocked => _isFinalQuotationReadOnly;',
      ),
      reason:
          'The approved quotation is immutable, but its converted service must remain operationally editable.',
    );
    expect(form, contains('bool get _hasConvertedQuotationHistory'));
    expect(form, contains('onPressed: _canSaveJob ? _saveJob : null'));
    expect(
      form,
      contains('_lockFormContent(content, locked: contentLocked)'),
    );
    expect(
      form,
      contains('enabled: !_isCommercialSnapshotLocked'),
    );
    expect(
      form,
      contains(
          'Las conversiones válidas se realizan mediante acciones auditadas de la tabla.'),
    );

    expect(table, contains('InvoicePdfGenerator.generateQuotationPDF('));
    expect(table, contains('discountAmount: job.discountAmount'));
    expect(table, contains('_bikeshopService.convertToBillableJob('));
    expect(
      table,
      contains(
        'job.effectiveQuotationStatus == QuotationStatus.approved',
      ),
    );
    expect(table, contains("value: 'quotation_status'"));
    expect(table, contains("'Aprobar o rechazar'"));
    expect(
      table,
      contains('Primero aprueba el presupuesto desde la acción de estado.'),
    );
    expect(table, contains("'Clasificación pendiente'"));
    expect(table, contains("'EN EVALUACIÓN'"));
    expect(table, contains("'Cotizado: "));
    expect(table, contains('JobIntakeKind.bike'));
    expect(table, contains('_bikeshopService.createInvoiceFromJob(jobId)'));
    expect(
      table,
      isNot(contains("'/sales/invoices/new?job_id=")),
      reason:
          'Workshop invoice creation must pass through the guarded job RPC.',
    );

    expect(
      service,
      contains("'create_billable_invoice_from_mechanic_job'"),
    );
    expect(service, contains("'transition_mechanic_job_quotation'"));
    expect(service, contains("'convert_mechanic_job_to_billable'"));
    expect(service, contains('Future<MechanicJob> updateJobDiscount('));
    expect(registry, contains('Workshop job create/edit'));
    expect(registry, contains('Workshop list actions'));
    expect(registry, contains('quotation PDF/status/conversion'));
  });

  test('ambiguous intake is resolved from the table by an audited command', () {
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();

    expect(service, contains('Future<MechanicJob> classifyMechanicJobIntake('));
    expect(service, contains("'classify_mechanic_job_intake'"));
    expect(service, contains("'p_intake_kind': intakeKind.dbValue"));
    expect(service, contains("'p_bike_id':"));
    expect(service, contains("'p_subject_id':"));
    expect(service, contains("'p_subject_notes':"));
    expect(service, contains("'p_reason': _nonBlankOrNull(reason)"));
    expect(service, contains("'p_operation_key': normalizedOperationKey"));
    expect(service, contains('invalidateJobBikesCache();'));

    expect(table, contains('Future<void> _classifyJobIntake('));
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

  test('canonical schema contains every workshop hardening migration', () {
    final schema = File('supabase/sql/core_schema.sql').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260716010000_redesign_mechanic_job_modes.sql',
    ).readAsStringSync();
    final quotationHardening = File(
      'supabase/migrations/20260716030000_harden_quotation_approval_contract.sql',
    ).readAsStringSync();

    expect(
      schema,
      contains(
        r'\ir ../migrations/20260716010000_redesign_mechanic_job_modes.sql',
      ),
    );
    expect(
      schema,
      contains(
        r'\ir ../migrations/20260716020000_repair_nested_invoice_trace_context.sql',
      ),
    );
    expect(
      schema,
      contains(
        r'\ir ../migrations/20260716030000_harden_quotation_approval_contract.sql',
      ),
    );
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

  test('non-bike narratives survive edit and compact deadlines do not overflow',
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
  });
}
