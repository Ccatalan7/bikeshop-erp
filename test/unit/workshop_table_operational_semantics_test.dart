import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String table;
  late String form;
  late String logbook;
  late String operationalBadge;
  late String visibilityPolicy;

  setUpAll(() {
    table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    form = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    logbook = File(
      'lib/modules/bikeshop/pages/client_logbook_page.dart',
    ).readAsStringSync();
    operationalBadge = File(
      'lib/shared/widgets/operational_status_badge.dart',
    ).readAsStringSync();
    visibilityPolicy = File(
      'lib/modules/bikeshop/services/mechanic_job_visibility_policy.dart',
    ).readAsStringSync();
  });

  test('service budgets retain operational state and commercial sublabel', () {
    expect(table, contains('job.proposalStatusDisplayName'));
    expect(table, contains('_operationalStatusColor(job)'));
    expect(
      table,
      contains("? 'Estado operativo y presupuesto'"),
      reason:
          'The same status dialog must expose both independent axes for a bike-backed budget.',
    );
    expect(
      table,
      contains('if (!widget.job.isStandaloneQuotation)'),
      reason:
          'A service budget remains eligible for the operational status list.',
    );
    expect(
      form,
      contains(
        'El estado operativo y las decisiones de presupuesto o garantía se cambian desde el chip Estado de la tabla.',
      ),
      reason:
          'The form must explain the single lifecycle owner instead of rendering a second status editor.',
    );
    expect(table, contains('OperationalStatusBadge('));
    expect(
      operationalBadge,
      contains("tooltip ?? 'Cambiar estado y ver acciones'"),
    );
    expect(operationalBadge, contains('Icons.keyboard_arrow_down_rounded'));
    expect(logbook, contains('if (job.isServiceBudget)'));
    expect(logbook, contains('job.proposalStatusDisplayName'));
  });

  test('commercial-only rows cannot enter the operational lifecycle', () {
    expect(
      table,
      contains(
        'bool _usesOperationalLifecycle(MechanicJob job) =>\n      !job.isSaleWorkflow && !job.isStandaloneQuotation;',
      ),
    );
    expect(
      table,
      contains('requestedJobs.where(_usesOperationalLifecycle).toList()'),
      reason:
          'Bulk status changes must skip both standalone quotations and sales.',
    );
    expect(
      table,
      contains('_filteredJobs.where(_usesOperationalLifecycle).toList()'),
      reason:
          'The operational board must not create fake lanes for commercial-only rows.',
    );
    expect(form, isNot(contains('DropdownButtonFormField<JobStatus>')));
    expect(form, isNot(contains('DropdownButtonFormField<JobStatusCustom>')));
    final mobileStatusAction = _section(
      table,
      start: 'Widget _buildMobileStatusAction({',
      end: 'Widget _buildMobileFinancialSummary({',
    );
    final saleBranch = _section(
      mobileStatusAction,
      start: '} else if (job.isSaleWorkflow) {',
      end: '} else if (job.isStandaloneQuotation) {',
    );
    expect(saleBranch, isNot(contains('_showStatusMenu(job)')));
    expect(saleBranch, contains('_MobileWorkshopSurface.invoice'));
    expect(
      _occurrences(mobileStatusAction, '_showStatusMenu(job)'),
      2,
      reason:
          'Only standalone quotations and operational jobs expose the status menu.',
    );
  });

  test('job form keeps intake content and removes duplicate controls', () {
    for (final duplicateLabel in const [
      'Duración estimada (horas)',
      'Trabajos a realizar',
      'Notas del técnico',
      'Requiere aprobación del cliente',
      'Trabajo de garantía',
      'Propuesta técnica',
      'Notas internas del técnico',
    ]) {
      expect(form, isNot(contains(duplicateLabel)));
    }
    expect(form, contains("labelText: 'Solicitud del cliente'"));
    expect(form, contains("'Recepción y compromiso'"));
    expect(form, contains("'Vigente hasta \${DateFormat('dd/MM/yyyy')"));
    expect(
      form,
      contains("'Se cambia desde Estado en la tabla'"),
    );
  });

  test('derived proposal expiry is not offered as a fake pending transition',
      () {
    expect(
      table,
      contains(
        'stored == QuotationStatus.pending && current == QuotationStatus.expired',
      ),
    );
    expect(table, contains('final isDisabled = qStatus == stored ||'));
    expect(
      table,
      contains('abre la ficha y extiende “Válido hasta”'),
      reason:
          'A date-derived expiry is resolved by extending validity, not by recording pending->pending.',
    );
  });

  test('counts and object labels reflect physical intake truth', () {
    final breakdownStart = table.indexOf(
      'List<_BicycleStatusBreakdownEntry> _buildBicycleStatusBreakdown()',
    );
    final breakdownEnd = table.indexOf(
      'Widget _buildDataTable()',
      breakdownStart,
    );
    expect(breakdownStart, greaterThanOrEqualTo(0));
    expect(breakdownEnd, greaterThan(breakdownStart));
    final breakdown = table.substring(breakdownStart, breakdownEnd);
    expect(breakdown, contains("_jobBikesMap[job.id ?? ''] ?? const []"));
    expect(
      breakdown,
      isNot(contains('job.bikeId')),
      reason:
          'Only canonical mechanic_job_bikes rows may increase the bicycle counter.',
    );

    expect(table, contains("'Ventas / cobros', sales"));
    expect(table, contains("'quotations_closed'"));
    expect(table, contains("return 'Cotizaciones cerradas';"));
    expect(
      visibilityPolicy,
      contains(
        'job.isStandaloneQuotation &&\n      (job.effectiveQuotationStatus == QuotationStatus.rejected',
      ),
      reason:
          'The canonical active-job policy excludes rejected or expired standalone quotations.',
    );
    expect(table, contains('isMechanicJobOperationallyActive('));
    expect(table, contains("return 'Componente recibido';"));
    expect(table, contains('_componentObjectLabel(job)'));
    expect(logbook, contains('job.isComponentIntake'));
    expect(logbook, contains("'Componente recibido'"));
  });

  test('standalone quotation history uses its requested description', () {
    expect(
      logbook,
      contains(
        'final requestSummary = job.isStandaloneQuotation\n        ? job.subjectNotes?.trim()',
      ),
    );
    expect(
      logbook,
      contains("requestSummary?.isNotEmpty == true ? requestSummary! : '—'"),
    );
  });
}

String _section(
  String source, {
  required String start,
  required String end,
}) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

int _occurrences(String source, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(source).length;
