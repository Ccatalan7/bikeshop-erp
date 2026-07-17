import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

Map<String, dynamic> _baseJobJson({
  String jobType = 'service',
  String? bikeId,
  String? subjectId,
  String? subjectNotes,
}) {
  return {
    'id': 'job-1',
    'tenant_id': 'tenant-1',
    'customer_id': 'customer-1',
    'job_type': jobType,
    'bike_id': bikeId,
    'subject_id': subjectId,
    'subject_notes': subjectNotes,
    'arrival_date': '2026-07-15T12:00:00Z',
    'created_at': '2026-07-15T12:00:00Z',
    'updated_at': '2026-07-15T12:00:00Z',
  };
}

void main() {
  group('canonical workshop mode axes', () {
    test('bike-backed quotation is presented as a service budget', () {
      final job = MechanicJob.fromJson({
        ..._baseJobJson(jobType: 'quotation', bikeId: 'bike-1'),
        'workflow_kind': 'quotation',
        'intake_kind': 'bike',
        'mode_needs_review': false,
        'quotation_status': 'pending',
      });

      expect(job.jobType, JobType.quotation);
      expect(job.isServiceBudget, isTrue);
      expect(job.isStandaloneQuotation, isFalse);
      expect(job.proposalDocumentLabel, 'Presupuesto');
      expect(job.statusDisplayName, 'Pendiente');
      expect(job.proposalStatusDisplayName, 'Presupuesto Pendiente');
      expect(job.modeNeedsReview, isFalse);
    });

    test('quotation without bike custody is presented as Cotización', () {
      final job = MechanicJob.fromJson({
        ..._baseJobJson(
          jobType: 'quotation',
          subjectNotes: 'Instalar una horquilla Fox 34',
        ),
        'workflow_kind': 'quotation',
        'intake_kind': 'unspecified',
        'mode_needs_review': false,
        'quotation_status': 'pending',
      });

      expect(job.isServiceBudget, isFalse);
      expect(job.isStandaloneQuotation, isTrue);
      expect(job.proposalDocumentLabel, 'Cotización');
      expect(job.statusDisplayName, 'Cotización Pendiente');
    });

    test(
        'stored proposal decisions lock content but clock expiry alone does not',
        () {
      final approved = MechanicJob.fromJson({
        ..._baseJobJson(jobType: 'quotation', bikeId: 'bike-1'),
        'workflow_kind': 'quotation',
        'intake_kind': 'bike',
        'quotation_status': 'approved',
      });
      final overduePending = MechanicJob.fromJson({
        ..._baseJobJson(jobType: 'quotation', bikeId: 'bike-1'),
        'workflow_kind': 'quotation',
        'intake_kind': 'bike',
        'quotation_status': 'pending',
        'quotation_valid_until': '2020-01-01T00:00:00Z',
      });

      expect(approved.hasFinalProposalDecision, isTrue);
      expect(overduePending.effectiveQuotationStatus, QuotationStatus.expired);
      expect(overduePending.hasFinalProposalDecision, isFalse);
    });

    test('sale uses canonical axes while keeping the legacy service facade',
        () {
      final job = MechanicJob.fromJson({
        ..._baseJobJson(jobType: 'service'),
        'workflow_kind': 'sale',
        'intake_kind': 'none',
        'mode_needs_review': false,
      });

      expect(job.jobType, JobType.sale);
      expect(job.workflowKind, JobWorkflowKind.sale);
      expect(job.intakeKind, JobIntakeKind.none);
      expect(job.requiresBike, isFalse);
      expect(job.modeNeedsReview, isFalse);
      expect(job.toJson(forUpdate: true)['job_type'], 'service');
      expect(job.toJson(forUpdate: true)['workflow_kind'], 'sale');
      expect(job.toJson(forUpdate: true)['intake_kind'], 'none');
      expect(JobType.fromDbValue('sale'), JobType.sale);
    });

    test('component repair is a service workflow without bicycle intake', () {
      final job = MechanicJob.fromJson({
        ..._baseJobJson(jobType: 'item_service', subjectId: 'subject-wheel'),
        'workflow_kind': 'service',
        'intake_kind': 'component',
        'mode_needs_review': false,
      });

      expect(job.jobType, JobType.itemService);
      expect(job.workflowKind, JobWorkflowKind.service);
      expect(job.intakeKind, JobIntakeKind.component);
      expect(job.isBillableServiceWorkflow, isTrue);
      expect(job.isComponentIntake, isTrue);
      expect(job.requiresBike, isFalse);
      expect(job.modeNeedsReview, isFalse);
    });

    test('legacy values infer only durable intake evidence', () {
      final bikeService = MechanicJob.fromJson(_baseJobJson(bikeId: 'bike-1'));
      final incompleteService = MechanicJob.fromJson(_baseJobJson());
      final walkInQuotation = MechanicJob.fromJson(
        _baseJobJson(
          jobType: 'quotation',
          subjectNotes: 'Cotizar cambio de transmisión completa',
        ),
      );

      expect(bikeService.workflowKind, JobWorkflowKind.service);
      expect(bikeService.intakeKind, JobIntakeKind.bike);
      expect(bikeService.modeNeedsReview, isFalse);

      expect(incompleteService.intakeKind, JobIntakeKind.unspecified);
      expect(incompleteService.modeNeedsReview, isTrue);
      expect(incompleteService.modeReviewReason, contains('confirmar'));

      expect(walkInQuotation.workflowKind, JobWorkflowKind.quotation);
      expect(walkInQuotation.intakeKind, JobIntakeKind.unspecified);
      expect(walkInQuotation.modeNeedsReview, isFalse);
    });

    test('canonical axes and review metadata round-trip in job payload', () {
      final job = MechanicJob(
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobType: JobType.itemService,
        workflowKind: JobWorkflowKind.service,
        intakeKind: JobIntakeKind.component,
        modeNeedsReview: true,
        modeReviewReason: 'Falta identificar la rueda recibida',
        subjectNotes: 'Rueda trasera suelta',
      );

      final payload = job.toJson(forUpdate: true);
      expect(payload['job_type'], 'item_service');
      expect(payload['workflow_kind'], 'service');
      expect(payload['intake_kind'], 'component');
      expect(payload['mode_needs_review'], isTrue);
      expect(
        payload['mode_review_reason'],
        'Falta identificar la rueda recibida',
      );

      final reviewed = job.copyWith(
        modeNeedsReview: false,
        modeReviewReason: null,
      );
      expect(reviewed.modeNeedsReview, isFalse);
      expect(reviewed.modeReviewReason, isNull);
    });

    test('copyWith preserves canonical mode and derived warranty projection',
        () {
      const serviceWarranty = MechanicJobServiceWarranty(
        jobId: 'job-1',
        customerId: 'customer-1',
        jobType: JobType.itemService,
        state: ServiceWarrantyState.active,
        daysRemaining: 9,
      );
      final job = MechanicJob(
        id: 'job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobType: JobType.itemService,
        workflowKind: JobWorkflowKind.service,
        intakeKind: JobIntakeKind.component,
        modeNeedsReview: true,
        modeReviewReason: 'Confirmar componente recibido',
        clientRequest: 'Enrayar rueda',
        serviceWarranty: serviceWarranty,
      );

      final updated = job.copyWith(
        priority: JobPriority.alta,
        clearClientRequest: true,
      );

      expect(updated.workflowKind, JobWorkflowKind.service);
      expect(updated.intakeKind, JobIntakeKind.component);
      expect(updated.modeNeedsReview, isTrue);
      expect(updated.modeReviewReason, 'Confirmar componente recibido');
      expect(updated.serviceWarranty, same(serviceWarranty));
      expect(updated.clientRequest, isNull);
    });
  });

  group('quotation validity', () {
    final beforeExpiry = DateTime.utc(2026, 7, 20, 11, 59);
    final atExpiry = DateTime.utc(2026, 7, 20, 12);

    test(
      'pending quotation expires from the clock without mutating storage',
      () {
        final quotation = MechanicJob(
          tenantId: 'tenant-1',
          customerId: 'customer-1',
          jobType: JobType.quotation,
          quotationStatus: QuotationStatus.pending,
          quotationValidUntil: atExpiry,
        );

        expect(
          quotation.effectiveQuotationStatusAt(beforeExpiry),
          QuotationStatus.pending,
        );
        expect(
          quotation.effectiveQuotationStatusAt(atExpiry),
          QuotationStatus.expired,
        );
        expect(quotation.quotationStatus, QuotationStatus.pending);
      },
    );

    test('an audited approval remains convertible after validity passes', () {
      final quotation = MechanicJob(
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobType: JobType.quotation,
        quotationStatus: QuotationStatus.approved,
        quotationValidUntil: atExpiry,
      );

      expect(quotation.canConvertQuotationAt(beforeExpiry), isTrue);
      expect(quotation.canConvertQuotationAt(atExpiry), isTrue);
      expect(
        quotation.effectiveQuotationStatusAt(atExpiry),
        QuotationStatus.approved,
      );
    });
  });

  test(
    'service mutations use audited commands instead of direct row writes',
    () {
      final source = File(
        'lib/modules/bikeshop/services/bikeshop_service.dart',
      ).readAsStringSync();
      final quotationCoordinator = File(
        'lib/modules/bikeshop/services/mechanic_job_quotation_command_coordinator.dart',
      ).readAsStringSync();

      final invoiceStart = source.indexOf(
        'Future<String> createInvoiceFromJob',
      );
      final invoiceEnd = source.indexOf(
        'Future<void> syncJobToInvoice',
        invoiceStart,
      );
      final conversionStart = source.indexOf(
        'Future<MechanicJobQuotationCommandResult> convertToBillableJob',
      );
      final conversionEnd = source.indexOf(
        '/// Updates quotation state',
        conversionStart,
      );
      final quotationStart = source.indexOf(
        'Future<MechanicJobQuotationCommandResult> updateQuotationStatus',
      );
      final quotationEnd = source.indexOf('@override', quotationStart);

      expect(invoiceStart, greaterThanOrEqualTo(0));
      expect(conversionStart, greaterThanOrEqualTo(0));
      expect(quotationStart, greaterThanOrEqualTo(0));

      final invoiceCommand = source.substring(invoiceStart, invoiceEnd);
      final conversionCommand = source.substring(
        conversionStart,
        conversionEnd,
      );
      final quotationCommand = source.substring(quotationStart, quotationEnd);

      expect(
        invoiceCommand,
        contains("'create_billable_invoice_from_mechanic_job'"),
      );
      expect(
        quotationCoordinator,
        contains("'convert_mechanic_job_to_billable'"),
      );
      expect(
        conversionCommand,
        contains('required String operationKey'),
      );
      expect(conversionCommand, contains('operationKey: operationKey'));
      expect(conversionCommand, isNot(contains("from('mechanic_jobs')")));
      expect(
        source,
        isNot(contains('Future<void> updateWarrantyOutcome(')),
        reason:
            'Warranty decisions must receive a durable caller-owned operation key.',
      );
      expect(
        quotationCoordinator,
        contains("'transition_mechanic_job_quotation'"),
      );
      expect(
        quotationCommand,
        contains('required String operationKey'),
      );
      expect(quotationCommand, contains('operationKey: operationKey'));
      expect(
        source,
        contains(".from('mechanic_job_mode_events')"),
      );
      expect(source, contains(".eq('job_id', jobId)"));
      expect(source, contains(".eq('tenant_id', tenantId)"));
      expect(
        quotationCommand,
        contains('_quotationCommandCoordinator.execute(request)'),
      );
      expect(
        quotationCommand,
        isNot(contains(".update({'quotation_status'")),
      );
    },
  );
}
