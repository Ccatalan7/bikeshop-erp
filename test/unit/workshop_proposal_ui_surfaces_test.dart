import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('table and PDF distinguish service budgets from standalone quotations',
      () {
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/shared/utils/invoice_pdf_generator.dart',
    ).readAsStringSync();
    final form = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final router = File(
      'lib/shared/routes/app_router.dart',
    ).readAsStringSync();

    expect(table, contains("child: const Text('Cotización')"));
    expect(table, contains("'Presupuestos', budgets"));
    expect(table, contains("'Cotizaciones', quotations"));
    expect(table, contains("? 'Presupuestado' : 'Cotizado'"));
    expect(table, contains('InvoicePdfGenerator.generateServiceBudgetPDF('));
    expect(table, contains('InvoicePdfGenerator.generateQuotationPDF('));
    expect(table, contains("? 'Facturar presupuesto'"));
    expect(table, contains(": 'Facturar o convertir cotización'"));
    expect(
      table,
      contains(
        'job.effectiveQuotationStatus == QuotationStatus.approved',
      ),
      reason:
          'The invoice-column shortcut must only offer conversion after the proposal is approved.',
    );
    expect(table, contains("value: 'download_proposal'"));
    expect(
      table,
      contains("'Descargar \${job.proposalDocumentLabelLower}'"),
    );
    expect(table, contains("value: 'convert_proposal'"));
    expect(table, contains("? 'Facturar presupuesto'"));
    expect(table, contains(": 'Facturar o convertir cotización'"));
    expect(
      table,
      contains('unawaited(_convertToService(job))'),
      reason:
          'The chip must reuse the audited idempotent conversion instead of creating a parallel invoice path.',
    );
    expect(
      table,
      contains('_openJobEditorAt(job, initialTab: \'products\')'),
      reason:
          'The main proposal-chip segment must open the canonical Products and Services editor.',
    );
    expect(
      table,
      contains("Icons.keyboard_arrow_down_rounded"),
      reason:
          'Every proposal state must expose a clearly visible secondary-actions affordance.',
    );
    expect(
      table,
      contains(
        'final proposalChip = SizedBox(\n'
        '              width: 84,\n'
        '              height: 24,',
      ),
      reason:
          'The split chip must have a bounded width that fits the invoice column instead of clipping its dropdown segment.',
    );
    expect(
      table,
      contains('fit: BoxFit.scaleDown'),
      reason:
          'Long proposal labels must yield space to the dropdown without overflowing the dense table cell.',
    );
    expect(
      table,
      contains("message: 'Descargar / más'"),
      reason: 'The dropdown hint must stay concise in the dense table.',
    );
    expect(
      table,
      contains("tooltip: ''"),
      reason:
          'The popup must suppress its long built-in tooltip; the concise delayed tooltip and semantics label own that guidance.',
    );
    expect(form, contains('final String? initialTab;'));
    expect(form, contains("'products' => _JobWorkbenchTab.products"));
    expect(
      router,
      contains("initialTab: state.uri.queryParameters['tab']"),
    );
    expect(table, contains('void _showReplacingQuotationSnackBar('));
    expect(table, contains('void _clearQuotationSnackBars()'));
    expect(table, contains('messenger.clearSnackBars();'));
    expect(table, contains('messenger.removeCurrentSnackBar();'));
    expect(
      table,
      contains(
        "_clearQuotationSnackBars();\n    _markNeedsRefresh();",
      ),
      reason:
          'Opening the linked invoice must remove workshop proposal feedback before route navigation.',
    );
    expect(
      table,
      contains(
        "if (jobId == null || jobId.isEmpty) return;\n    _clearQuotationSnackBars();",
      ),
      reason:
          'Starting conversion must immediately remove the obsolete approval action.',
    );
    expect(
      RegExp(r'_showReplacingQuotationSnackBar\(\s*SnackBar\(')
          .allMatches(table)
          .length,
      greaterThanOrEqualTo(4),
      reason:
          'Every quotation transition outcome must replace stale status feedback instead of queueing behind it.',
    );
    final invoiceAction = table.indexOf(
      'Future<void> _createInvoiceForJob(MechanicJob job)',
    );
    final guardedInvoiceRpc = table.indexOf(
      '_bikeshopService.createInvoiceFromJob(jobId)',
      invoiceAction,
    );
    expect(invoiceAction, greaterThanOrEqualTo(0));
    expect(guardedInvoiceRpc, greaterThan(invoiceAction));
    expect(
      table.substring(invoiceAction, guardedInvoiceRpc),
      contains('if (job.isQuotationWorkflow)'),
      reason:
          'No proposal may reach direct invoice creation before its audited conversion.',
    );

    expect(pdf, contains('serviceBudget,'));
    expect(pdf, contains("return 'Cotización';"));
    expect(pdf, contains("return 'Presupuesto';"));
    expect(pdf, contains("return 'cotizacion_\$documentNumber.pdf';"));
    expect(pdf, contains("return 'presupuesto_\$documentNumber.pdf';"));
    expect(
      pdf,
      contains(
        'if (documentKind == InvoicePdfDocumentKind.quotation) {',
      ),
      reason:
          'A standalone quotation PDF must ignore stale bicycle data instead of claiming physical custody.',
    );
    expect(pdf, contains("? 'Bicicletas recibidas'"));
    expect(pdf, contains("? 'Bicicleta recibida'"));
    expect(
      form,
      contains('jobType: mechanicJobPersistedJobType('),
      reason:
          'Editing a bike-backed service budget must keep the deployed quotation facade until audited conversion.',
    );
  });

  test('approved product quotation can become a linked product sale', () {
    final table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final coordinator = File(
      'lib/modules/bikeshop/services/mechanic_job_quotation_command_coordinator.dart',
    ).readAsStringSync();

    expect(table, contains('item.itemType == \'product\''));
    expect(table, contains('item.productId != null'));
    expect(table, contains('value: JobType.sale'));
    expect(table, contains("label: const Text('Venta')"));
    expect(table, contains("? 'Facturar como venta'"));
    expect(
      table,
      contains(
        'la factura será la única dueña del inventario, impuestos y contabilidad',
      ),
    );
    expect(
      service,
      contains("targetType == JobType.sale ? 'sale' : targetType.dbValue"),
      reason:
          'The legacy job_type facade must not erase the explicit sale RPC target.',
    );
    expect(coordinator, contains("'sale' => 'none'"));
    expect(coordinator, contains("'sale' => 'sale'"));
    expect(coordinator, contains("'sale' => 'service'"));
  });

  test('service-budget conversion bypasses object picker and preserves bikes',
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

    final budgetBranch = conversion.indexOf('if (job.isServiceBudget) {');
    final standaloneCatalog = conversion.indexOf('getJobSubjects()');
    expect(budgetBranch, greaterThanOrEqualTo(0));
    expect(standaloneCatalog, greaterThan(budgetBranch));
    expect(
      conversion.substring(budgetBranch, standaloneCatalog),
      contains('await _confirmServiceBudgetConversion(job);'),
      reason:
          'A service budget already owns its physical intake and must not open a replacement-object picker.',
    );
    expect(
      conversion,
      contains(
        'const _JobConversionChoice(targetType: JobType.service)',
      ),
    );
    expect(
      conversion,
      contains(
        'final convertedBikeId = choice.targetType == JobType.service',
      ),
    );
    expect(conversion, contains('? job.bikeId'));
    expect(conversion, contains('Bicicletas recibidas'));
    expect(
      conversion,
      contains(
        'No se cambiará ni se volverá a seleccionar la recepción física.',
      ),
    );
    expect(conversion, contains('getJobSubjects()'));
    expect(conversion, contains('customerBikes'));
    expect(conversion, contains("const sourceLabel = 'cotización';"));
  });

  test('secondary surfaces keep object truth and workshop capacity explicit',
      () {
    final detail = File(
      'lib/modules/bikeshop/widgets/pega_detail_view.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/modules/bikeshop/widgets/pegas_calendar_widget.dart',
    ).readAsStringSync();
    final logbook = File(
      'lib/modules/bikeshop/pages/client_logbook_page.dart',
    ).readAsStringSync();

    expect(detail, contains('if (widget.job.isStandaloneQuotation)'));
    expect(detail, contains('Cotización · Sin objeto recibido'));
    expect(detail, contains('Total presupuestado'));
    expect(detail, contains('Total cotizado'));
    expect(
      detail,
      contains('if (widget.job.isQuotationWorkflow)'),
      reason:
          'Proposal detail totals must use the authoritative discounted totalCost before the no-tax display fallback.',
    );
    expect(detail, contains('onProposalDocumentPressed'));
    expect(detail, contains('onProposalStatusPressed'));
    expect(detail, contains('onProposalConvertPressed'));

    expect(
      calendar,
      contains('job.isSaleWorkflow || job.isStandaloneQuotation'),
      reason:
          'Standalone quotations must not reserve diagnostic or delivery capacity.',
    );
    expect(calendar, contains('? _buildProposalSummaryTab(job)'));
    expect(
      calendar,
      contains('Este presupuesto aún no ha generado una factura.'),
    );

    expect(logbook, contains("? 'Cotización'"));
    expect(logbook, contains("'Sin objeto recibido'"));
    expect(logbook, contains('_buildStatusBadge(job)'));
    expect(logbook, contains('job.statusDisplayName'));
    expect(logbook, contains("? 'Total presupuestado'"));
    expect(logbook, contains(": 'Total cotizado'"));
    expect(
      logbook,
      contains('if (job.isQuotationWorkflow)'),
      reason:
          'Client history must not display the undiscounted no-tax subtotal for proposals.',
    );
  });
}
