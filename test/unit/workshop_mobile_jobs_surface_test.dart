import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);

  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(end, greaterThan(start), reason: 'Missing $endMarker');
  return source.substring(start, end);
}

void main() {
  late String table;
  late String detail;
  late String jobForm;
  late String invoiceEditor;
  late String mainLayout;

  setUpAll(() {
    table = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    detail = File(
      'lib/modules/bikeshop/widgets/pega_detail_view.dart',
    ).readAsStringSync();
    jobForm = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    invoiceEditor = File(
      'lib/modules/sales/widgets/sales_invoice_editor.dart',
    ).readAsStringSync();
    mainLayout = File(
      'lib/shared/widgets/main_layout.dart',
    ).readAsStringSync();
  });

  test('compact jobs surface follows constraints and preserves list context',
      () {
    expect(table, contains('child: LayoutBuilder('));
    expect(
      table,
      contains(
        'final screenWidth = '
        'ResponsiveViewport.widthOf(context);',
      ),
    );
    expect(
      table,
      contains(
        'final useCompactWorkspace =\n'
        '              screenWidth < ResponsiveViewport.desktopMin;',
      ),
      reason: 'Zoom must not move the logical 899/900 boundary.',
    );
    expect(
      table,
      contains(
        'if (useCompactWorkspace || _mobileWorkshopWorkspace != null)',
      ),
      reason:
          'An open compact editor must stay mounted while a breakpoint changes.',
    );
    expect(table, isNot(contains('_usesCompactWorkshopComposition')));
    expect(
      table,
      isNot(
        contains(
          'screenWidth < 1100 ||\n'
          '        (!kIsWeb && (Platform.isAndroid || Platform.isIOS))',
        ),
      ),
    );
    expect(
      table,
      contains(
        "final ScrollController _mobileJobsScrollController = "
        'ScrollController();',
      ),
    );
    expect(table, contains("PageStorageKey('workshop-jobs-mobile')"));
    expect(table, contains('controller: _mobileJobsScrollController'));
    expect(table, contains('final jobs = _filteredJobs;'));
    expect(table, isNot(contains('_mobileVisibleJobs')));
    expect(table, isNot(contains('_mobileStatusFilter')));

    final compactLayout = _section(
      table,
      'Widget _buildMobileLayout()',
      'Widget _buildMobileInlineWorkspace',
    );
    expect(compactLayout, contains('SafeArea('));
    expect(
      compactLayout,
      contains("ValueKey('workshop-mobile-bottom-safe-area')"),
    );
    expect(compactLayout, contains('top: false'));
    expect(compactLayout, contains('maintainBottomViewPadding: true'));

    final filterStart = table.indexOf('void _applyFiltersAndSort()');
    final filterEnd = table.indexOf(
      'bool _jobMatchesTestFilter',
      filterStart,
    );
    expect(filterStart, greaterThanOrEqualTo(0));
    expect(filterEnd, greaterThan(filterStart));
    expect(
      table.substring(filterStart, filterEnd),
      isNot(contains('_mobileStatusFilter')),
      reason:
          'A compact-only chip must not remain as an invisible desktop filter.',
    );
  });

  test('mobile application chrome labels every icon-only action', () {
    final mobileChrome = _section(
      mainLayout,
      'class _MainLayoutState extends State<MainLayout>',
      'Future<void> _handleLogout',
    );

    for (final tooltip in const [
      "tooltip: 'Volver'",
      "tooltip: 'Abrir menú principal'",
    ]) {
      expect(
        mobileChrome,
        contains(tooltip),
        reason:
            'Icon-only mobile chrome controls need a tooltip and semantics label.',
      );
    }
    for (final tooltip in const [
      "tooltip: 'Buscar trabajos'",
      "tooltip: 'Cerrar búsqueda'",
      "tooltip: 'Limpiar búsqueda'",
      "tooltip: 'Más acciones'",
    ]) {
      expect(
        table,
        contains(tooltip),
        reason:
            'Icon-only Jobs app bar controls need a tooltip and semantics label.',
      );
    }
  });

  test('compact jobs chrome follows the canonical responsive width matrix', () {
    const jobsDesktopWidth = 900;
    const shellDesktopWidth = 900;
    expect(
      table,
      contains('screenWidth < ResponsiveViewport.desktopMin'),
      reason: 'Jobs must consume the shared compact breakpoint owner.',
    );
    expect(
      mainLayout,
      contains('screenWidth >= ResponsiveViewport.desktopMin'),
      reason: 'MainLayout must consume the same breakpoint owner.',
    );
    expect(
      table,
      matches(
        RegExp(
          r'compactHeader:\s*'
          r'screenWidth < ResponsiveViewport\.desktopMin\s*'
          r'\?\s*_buildMobileMainLayoutHeader\(\)\s*:\s*null',
        ),
      ),
      reason:
          'The Jobs header and body must cross the compact boundary together.',
    );

    for (final expectation in const <(double, bool)>[
      (384, true),
      (599, true),
      (600, true),
      (899, true),
      (900, false),
    ]) {
      final (width, shouldUseCompactChrome) = expectation;
      expect(
        width < jobsDesktopWidth,
        shouldUseCompactChrome,
        reason: 'Unexpected Jobs composition at ${width.toInt()} px.',
      );
      expect(
        width < shellDesktopWidth,
        shouldUseCompactChrome,
        reason: 'Unexpected MainLayout composition at ${width.toInt()} px.',
      );
    }
  });

  test('compact Jobs keeps only app bar and one persistent command surface',
      () {
    expect(mainLayout, contains('class MainLayoutCompactHeader'));
    expect(
        mainLayout, contains('final MainLayoutCompactHeader? compactHeader;'));
    expect(mainLayout, contains('this.compactHeader,'));
    expect(table, contains('compactHeader:'));
    expect(table, contains('_buildMobileMainLayoutHeader()'));
    expect(
      table,
      isNot(contains('Widget _buildMobileHeader(')),
      reason:
          'The retired page-local header must not survive beside MainLayout.',
    );

    final compactLayout = _section(
      table,
      'Widget _buildMobileLayout()',
      'Widget _buildMobileInlineWorkspace',
    );
    expect(
      compactLayout,
      isNot(contains('_buildMobileHeader(')),
      reason:
          'The page-local Trabajos header would create a third persistent row.',
    );
    expect(
      compactLayout,
      contains("if (_viewMode != 'tasks') _buildMobileFilterTabs(theme)"),
      reason:
          'Tasks owns its filters and must not inherit the Jobs command row.',
    );

    final commandDock = _section(
      table,
      'Widget _buildMobileFilterTabs(ThemeData theme)',
      'Widget _buildMobileControlField',
    );
    expect(
      RegExp(r'\bRow\(').allMatches(commandDock),
      hasLength(1),
      reason: 'Scope, view, workload, and filters must share one command row.',
    );
    expect(
      commandDock,
      isNot(contains('TextField(')),
      reason:
          'Search belongs in the existing app bar, not in another body row.',
    );
    expect(commandDock, isNot(contains('if (_isSearchExpanded)')));

    for (final hook in const [
      'workshop-mobile-scope',
      'workshop-mobile-view',
    ]) {
      expect(
        commandDock,
        contains(hook),
        reason: 'The single compact command row lost $hook.',
      );
    }
    expect(commandDock, contains('_buildMobileWorkloadSummary(theme)'));
    expect(commandDock, contains('_buildMobileFiltersButton(theme)'));
    expect(table, contains('workshop-mobile-workload-summary'));
    expect(table, contains('workshop-mobile-filters'));
  });

  test('wide tablet recomposes Jobs into two scannable columns', () {
    final mobileList = _section(
      table,
      'Widget _buildMobileJobsList()',
      'Future<void> _updateJobStatus',
    );

    expect(
      table,
      contains(
        'static const double _mobileJobsTabletGridMinWidth = 720;',
      ),
    );
    expect(mobileList, contains('final usesTabletGrid ='));
    expect(
      mobileList,
      contains(
        'constraints.maxWidth >= _mobileJobsTabletGridMinWidth;',
      ),
    );
    expect(
      mobileList,
      contains('usesTabletGrid ? (jobs.length / 2).ceil() : jobs.length'),
    );
    expect(
      RegExp(r'Expanded\(child: _buildMobileJobCard\(').allMatches(mobileList),
      hasLength(2),
    );
    expect(
      mobileList,
      contains("PageStorageKey('workshop-jobs-mobile')"),
      reason: 'Phone and tablet must retain the same scroll owner.',
    );

    for (final expectation in const <(double, bool)>[
      (600, false),
      (719, false),
      (720, true),
      (899, true),
    ]) {
      expect(
        expectation.$1 >= 720,
        expectation.$2,
        reason: 'Unexpected tablet Jobs grid at ${expectation.$1}px.',
      );
    }
  });

  test('compact search replaces the app bar title without adding a body row',
      () {
    final compactHeaderContract = _section(
      mainLayout,
      'class MainLayoutCompactHeader',
      'class MainLayout extends StatefulWidget',
    );
    expect(compactHeaderContract, contains('required this.title'));
    expect(compactHeaderContract, contains('this.actions = const <Widget>[]'));
    expect(compactHeaderContract, contains('final Widget title;'));
    expect(compactHeaderContract, contains('final List<Widget> actions;'));
    expect(mainLayout, contains('title: widget.compactHeader?.title ??'));
    expect(
      mainLayout,
      contains('actions: widget.compactHeader?.actions ?? const <Widget>[]'),
    );

    final jobsHeader = _section(
      table,
      'MainLayoutCompactHeader _buildMobileMainLayoutHeader()',
      'void _updateMobileSearch',
    );
    expect(jobsHeader, contains('if (_isSearchExpanded)'));
    expect(
      RegExp(r'return MainLayoutCompactHeader\(').allMatches(jobsHeader),
      hasLength(3),
      reason: 'Tasks, normal Jobs, and search must replace the same app bar.',
    );
    expect(jobsHeader, contains("if (_viewMode == 'tasks')"));
    expect(
      jobsHeader,
      contains("ValueKey('workshop-mobile-tasks-view')"),
    );
    expect(jobsHeader, contains("'Planificación operativa'"));
    expect(jobsHeader, contains("tooltip: 'Cambiar vista del taller'"));
    expect(jobsHeader, contains('title: TextField('));
    expect(jobsHeader, contains("ValueKey('workshop-mobile-search-field')"));
    expect(jobsHeader, contains('controller: _mobileSearchController'));
    expect(jobsHeader, contains('onChanged: _updateMobileSearch'));
    expect(jobsHeader, contains("ValueKey('workshop-mobile-search-close')"));
    expect(jobsHeader, contains("tooltip: 'Cerrar búsqueda'"));
    expect(
      jobsHeader,
      contains(
        'onPressed: () => setState(() => _isSearchExpanded = false)',
      ),
      reason: 'Closing search must preserve the current query and list state.',
    );

    final clearSearch = _section(
      table,
      'void _clearMobileSearch()',
      'Widget _buildMobileFilterTabs',
    );
    expect(clearSearch, contains('_mobileSearchController.clear();'));
    expect(clearSearch, contains("_updateMobileSearch('');"));
    expect(table, contains('_mobileSearchController.text = _searchTerm;'));
    expect(table, contains('_mobileSearchController.dispose();'));
  });

  test('mobile job cards enter the inline canonical workspace', () {
    for (final hook in const [
      'workshop-job-status-',
      'workshop-job-customer-',
      'workshop-job-bike-',
      'workshop-job-open-',
      'workshop-job-expand-',
      'workshop-job-expanded-',
      'workshop-job-time-',
      'workshop-job-items-',
      'workshop-job-invoice-',
      'workshop-job-more-',
    ]) {
      expect(table, contains(hook), reason: 'Missing mobile hook $hook');
    }

    expect(table, isNot(contains('_openMobileJobDetail')));
    expect(table, contains('onTap = () => _showStatusMenu(job);'));
    expect(table, contains('_registerInvoicePayment(invoiceId!)'));
    expect(table, contains('_showBikeProfileDialog(job, customer)'));
    expect(
        table, contains('_openInvoicePreview(invoiceId!, invoice: invoice)'));
    expect(table, contains('_buildMobileFinancialSummary('));
    expect(table, contains('invoice.total - invoice.paidAmount > 0.01'));
    expect(table, contains('_expandedMobileJobKeys'));
    expect(table, contains('AnimatedSize('));

    final mobileActions = _section(
      table,
      'Widget _buildMobileJobActionBar',
      'Widget _buildMobileCardAction',
    );
    expect(mobileActions, contains('_openMobileInlineSurface('));
    for (final surface in const [
      '_MobileWorkshopSurface.job',
      '_MobileWorkshopSurface.items',
      '_MobileWorkshopSurface.invoice',
      '_MobileWorkshopSurface.proposalPdf',
    ]) {
      expect(
        mobileActions,
        contains(surface),
        reason: 'Missing compact inline destination $surface',
      );
    }
    expect(
      mobileActions,
      isNot(contains('_openJobEditor(job)')),
      reason: 'Compact Trabajo must not push the routed editor.',
    );
    expect(
      mobileActions,
      isNot(contains('_openJobProductsAndServices(job)')),
      reason: 'Compact Ítems must remain in the Jobs workspace.',
    );
    expect(
      mobileActions,
      isNot(contains('_openInvoice(invoiceId)')),
      reason: 'Compact Factura must use the embedded canonical editor.',
    );
    expect(
      mobileActions,
      isNot(contains('_downloadQuotationPdf(job)')),
      reason: 'Compact PDF must preview before an explicit export.',
    );
  });

  test('inline host reuses job, invoice, and PDF owners then returns to list',
      () {
    for (final hook in const [
      'workshop-mobile-inline-host',
      'workshop-mobile-inline-job',
      'workshop-mobile-inline-items',
      'workshop-mobile-inline-invoice',
      'workshop-mobile-inline-pdf',
      'workshop-mobile-inline-back',
      'workshop-mobile-inline-loading',
      'workshop-mobile-inline-error',
    ]) {
      expect(table, contains(hook), reason: 'Missing inline hook $hook');
    }

    final inlineWorkspace = _section(
      table,
      'Widget _buildMobileInlineWorkspace',
      'Widget _buildMobileInlineUnavailable',
    );
    expect(table, contains('final GlobalKey childKey;'));
    expect(
      RegExp(r'key: workspace\.childKey').allMatches(inlineWorkspace),
      hasLength(3),
      reason:
          'Mutable inline children need a stable identity across shell breakpoints.',
    );
    expect(inlineWorkspace, contains('MechanicJobFormPage('));
    expect(inlineWorkspace, contains("initialTab: 'general'"));
    expect(inlineWorkspace, contains("initialTab: 'products'"));
    expect(
      RegExp(r'isEmbedded: true').allMatches(inlineWorkspace),
      hasLength(2),
    );
    expect(
      RegExp(r'isInlineWorkspace: true').allMatches(inlineWorkspace),
      hasLength(2),
    );
    expect(
      RegExp(r'onSaved: _handleMobileInlineSave').allMatches(inlineWorkspace),
      hasLength(3),
    );
    expect(
      RegExp(r'onCanceled: _closeMobileInlineSurface')
          .allMatches(inlineWorkspace),
      hasLength(2),
    );

    expect(inlineWorkspace, contains('SalesInvoiceEditor('));
    expect(inlineWorkspace, contains('invoiceId: job.invoiceId'));
    expect(inlineWorkspace, contains('preselectedJobId: jobId'));
    expect(inlineWorkspace, contains('isCompact: true'));
    expect(inlineWorkspace, contains('allowFullScreenExpansion: false'));
    expect(
      inlineWorkspace,
      contains('onCloseRequested: _closeMobileInlineSurface'),
    );

    expect(jobForm, contains('final bool isInlineWorkspace;'));
    expect(jobForm, contains("'isInlineWorkspace requires isEmbedded.'"));
    expect(jobForm, contains("ValueKey('mechanic-job-inline-back')"));
    expect(jobForm, contains("ValueKey('mechanic-job-inline-save')"));
    expect(jobForm, contains('widget.onCanceled!()'));
    expect(jobForm, contains('widget.onSaved!()'));
    final inlineHeader = _section(
      jobForm,
      'Widget _buildInlineWorkspaceHeader',
      'Widget _buildInlineBikeTabs',
    );
    expect(inlineHeader, contains('minimumSize: const Size(0, 48)'));

    expect(invoiceEditor, contains('final VoidCallback? onCloseRequested;'));
    expect(invoiceEditor, contains('final bool allowFullScreenExpansion;'));
    expect(invoiceEditor, contains("ValueKey('invoice-editor-inline-back')"));
    expect(
      invoiceEditor,
      contains('widget.isCompact && widget.allowFullScreenExpansion'),
    );
    expect(
      invoiceEditor,
      contains('_bikeshopService.createInvoiceFromJob('),
      reason: 'A missing linked invoice must use the guarded workshop command.',
    );

    final closeFlow = _section(
      table,
      'void _closeMobileInlineSurface()',
      'void _handleMobileInlineSave()',
    );
    expect(closeFlow, contains('_mobileWorkshopWorkspace = null'));
    for (final owner in const [
      '_mobileJobsScrollController',
      '_statusFilter',
      '_searchTerm',
      '_customStatusFilter',
      '_priorityFilter',
      '_viewMode',
      '_expandedMobileJobKeys',
    ]) {
      expect(
        closeFlow,
        isNot(contains('$owner =')),
        reason: '$owner must survive an inline round trip.',
      );
    }

    final saveFlow = _section(
      table,
      'void _handleMobileInlineSave()',
      'MechanicJob _currentMobileWorkspaceJob',
    );
    expect(saveFlow, contains('_mobileWorkshopWorkspace = null'));
    expect(saveFlow, contains('_loadData(forceInvoiceRefresh: true)'));
  });

  test('inline job editor confirms only real unsaved draft disposal', () {
    final cancelFlow = _section(
      jobForm,
      'void _handleCancel()',
      'Future<bool> _confirmDiagnosisOnlyAfterFinancialStateChange()',
    );

    expect(cancelFlow, contains('if (_isSaving) return;'));
    expect(cancelFlow, contains('if (widget.isInlineWorkspace)'));
    expect(cancelFlow, contains('_inlineDraftHasUnsavedChanges'));
    expect(cancelFlow, contains('showDialog<bool>('));
    expect(
      cancelFlow,
      contains("ValueKey('mechanic-job-inline-discard-dialog')"),
    );
    expect(
      cancelFlow,
      contains("'mechanic-job-inline-discard-cancel'"),
    );
    expect(
      cancelFlow,
      contains("'mechanic-job-inline-discard-confirm'"),
    );
    expect(cancelFlow, contains('_buildInlineDraftFingerprint()'));
    expect(cancelFlow, contains("'bike_tabs'"));
    expect(cancelFlow, contains("'standalone_items'"));
    expect(cancelFlow, contains("'wizard_answers'"));
    expect(cancelFlow, contains('widget.onCanceled?.call();'));
    expect(
      RegExp(r'_captureInlineDraftBaseline\(\);').allMatches(jobForm),
      hasLength(2),
      reason: 'Load and successful save must each establish a clean baseline.',
    );

    final embeddedHost = _section(
      jobForm,
      'if (widget.isEmbedded) {',
      'return MainLayout(child: content);',
    );
    expect(embeddedHost, contains('if (!widget.isInlineWorkspace)'));
    expect(embeddedHost, contains('return PopScope('));
    expect(embeddedHost, contains('canPop: false'));
    expect(embeddedHost, contains('_handleCancel();'));
  });

  test('inline proposal preview builds a pure artifact and exports explicitly',
      () {
    final pdfWorkspace = _section(
      table,
      'Widget _buildMobileProposalPdfWorkspace',
      'Widget _buildMobileProposalPdfError',
    );
    expect(pdfWorkspace, contains('PdfPreview('));
    expect(pdfWorkspace, contains('artifact.bytes'));
    expect(
      pdfWorkspace,
      contains('_exportQuotationPdfArtifact(snapshot.data!)'),
    );

    final artifactBuilder = _section(
      table,
      'Future<_WorkshopProposalPdfArtifact> _buildQuotationPdfArtifact',
      'Future<void> _exportQuotationPdfArtifact',
    );
    expect(artifactBuilder, contains('getJobItems(jobId)'));
    expect(artifactBuilder, contains('generateServiceBudgetPDF('));
    expect(artifactBuilder, contains('generateQuotationPDF('));
    expect(artifactBuilder, contains('final bytes = await pdf.save();'));
    expect(
      artifactBuilder,
      contains('return _WorkshopProposalPdfArtifact('),
    );
    expect(
      artifactBuilder,
      isNot(contains('FilePicker.platform.saveFile')),
      reason: 'Preparing an inline preview must not open a native save dialog.',
    );
    expect(
      artifactBuilder,
      isNot(contains('Printing.sharePdf')),
      reason: 'Preparing an inline preview must not trigger sharing.',
    );

    final exporter = _section(
      table,
      'Future<void> _exportQuotationPdfArtifact',
      'Future<void> _convertToService',
    );
    expect(exporter, contains('FilePicker.platform.saveFile'));
    expect(exporter, contains('Printing.sharePdf'));
  });

  test('desktop split and routed deep links keep their established owners', () {
    final tableOpenFlow = _section(
      table,
      'void _openJobFromTable(MechanicJob job)',
      'Future<void> _loadColumnOrder()',
    );
    expect(
      tableOpenFlow,
      contains('if (ResponsiveViewport.usesCompactShell(context))'),
    );
    expect(
      tableOpenFlow,
      isNot(contains('MediaQuery.sizeOf(context).width')),
      reason: 'Desktop zoom must not select the compact inline owner.',
    );
    expect(
      tableOpenFlow,
      contains(
        '_openMobileInlineSurface(job, _MobileWorkshopSurface.job);',
      ),
    );
    expect(
        tableOpenFlow, contains('final useSplitPane = _isSplitPaneEnabled;'));
    expect(tableOpenFlow, contains('unawaited(_openJobEditor(job));'));
    expect(table, contains('await context.push(route);'));
    expect(table, contains("path: '/taller/pegas/\$jobId'"));
    expect(table, contains('_openJobEditorAt(job, initialTab: \'products\')'));
    expect(detail, contains('class PegaDetailView extends StatefulWidget'));

    final desktopTable = _section(
      table,
      'Widget _buildDataTable()',
      'Widget _buildMobileJobCard(MechanicJob job)',
    );
    expect(
      desktopTable,
      isNot(contains('constraints.maxWidth < 800')),
      reason: 'Desktop must not fall back to a stretched mobile-card hybrid.',
    );
    expect(desktopTable, contains('SingleChildScrollView('));
    expect(desktopTable, contains('scrollDirection: Axis.horizontal'));
    expect(desktopTable, contains('_buildTableRow('));
  });

  test('compact controls share desktop scope, view, and filter owners', () {
    for (final hook in const [
      'workshop-mobile-scope',
      'workshop-mobile-view',
      'workshop-mobile-filters',
      'workshop-mobile-workload-summary',
    ]) {
      expect(table, contains(hook), reason: 'Missing compact control $hook');
    }

    expect(table, contains('Future<void> _selectJobsScope(String selected)'));
    expect(table, contains('void _selectJobsView(String selected)'));
    expect(table, contains('await _selectJobsScope(selected);'));
    expect(table, contains('_selectJobsView(selected);'));
    expect(table, contains("const options = ['table', 'board', 'calendar',"));
    expect(table, contains("value == 'table' ? 'Lista'"));
    expect(table, contains('Future<void> _showMobileFilters()'));
    expect(table, contains('_customStatusFilter'));
    expect(table, contains('_priorityFilter'));
    expect(table, contains('_showOnlyOverdue'));
    expect(table, contains('_showOnlyUnpaid'));
    for (final section in <(String, String)>[
      ('Widget _buildMobileControlField', 'String _mobileViewModeLabel'),
      (
        'Widget _buildMobileFiltersButton',
        'Widget _buildMobileWorkloadSummary'
      ),
      (
        'Widget _buildMobileWorkloadSummary',
        'Future<void> _showMobileScopePicker'
      ),
    ]) {
      expect(
        _section(table, section.$1, section.$2),
        contains('height: 52'),
        reason: '${section.$1} must preserve a touch target above 48 px.',
      );
    }
  });

  test('compact Gantt controls stack before the desktop row can overflow', () {
    final controlsStart = table.indexOf('Widget _buildTimelineControls()');
    final controlsEnd = table.indexOf(
      'Widget _buildTimelineScaleSelector',
      controlsStart,
    );
    expect(controlsStart, greaterThanOrEqualTo(0));
    expect(controlsEnd, greaterThan(controlsStart));

    final controls = table.substring(controlsStart, controlsEnd);
    expect(controls, contains('return LayoutBuilder('));
    expect(
      controls,
      contains('constraints.maxWidth < ResponsiveViewport.desktopMin'),
    );
    expect(controls, contains('child: compact'));
    expect(controls, contains('Column('));
    expect(controls, contains('_buildTimelineScaleSelector(expanded: true)'));
    expect(
        table, contains('expandedInsets: expanded ? EdgeInsets.zero : null'));
    expect(table, contains('workshop-gantt-compact-controls'));
    expect(table, contains('workshop-gantt-horizontal-scroll'));
    expect(table, contains('height: compact ? 52 : 36'));
    expect(table, contains('minimumSize: const Size(48, 48)'));
    expect(
      table,
      contains('minimumSize: WidgetStatePropertyAll(Size(48, 48))'),
    );
  });

  test('compact visual hierarchy is neutral and uses textual row actions', () {
    expect(table, contains('surfaceContainerLow'));
    expect(table, contains('gradient: LinearGradient('));
    expect(
        table, contains('theme.colorScheme.primary.withValues(alpha: 0.025)'));
    expect(table, contains("label: 'Trabajo'"));
    expect(table, contains("label: 'Ítems'"));
    expect(table, contains("label: 'Más'"));

    for (final section in <(String, String)>[
      ('Widget _buildMobileJobCard', 'Widget _buildMobileJobObject'),
      ('Widget _buildMobileJobObject', 'Widget _buildMobileStatusAction'),
      (
        'Widget _buildMobileStatusAction',
        'Widget _buildMobileFinancialSummary'
      ),
      (
        'Widget _buildMobileJobDisclosure',
        'Widget _buildMobileExpandedJobDetails'
      ),
    ]) {
      expect(
        _section(table, section.$1, section.$2),
        contains('BoxConstraints(minHeight: 48'),
        reason: '${section.$1} must keep a 48 px touch target.',
      );
    }

    final actionStart = table.indexOf('Widget _buildMobileCardAction');
    final actionEnd =
        table.indexOf('Widget _buildMobileTimeSummary', actionStart);
    expect(actionStart, greaterThanOrEqualTo(0));
    expect(actionEnd, greaterThan(actionStart));
    expect(
      table.substring(actionStart, actionEnd),
      isNot(contains('Icon(')),
      reason:
          'The compact row action rail should be text-first, not icon-heavy.',
    );
    expect(
      table.substring(actionStart, actionEnd),
      contains('height: 48'),
      reason: 'Every compact row action needs a 48 px touch target.',
    );
  });

  test('mobile disclosure keeps request and diagnosis semantically distinct',
      () {
    final card = _section(
      table,
      'Widget _buildMobileJobCard',
      'Widget _buildMobileJobObject',
    );
    final expanded = _section(
      table,
      'Widget _buildMobileExpandedJobDetails',
      'Widget _buildMobileTimeSummary',
    );

    expect(card, contains(': job.clientRequest'));
    expect(card, contains('final diagnosis = job.diagnosis?.trim();'));
    expect(card, isNot(contains('job.diagnosis ?? job.clientRequest')));
    expect(expanded, contains("'Solicitud'"));
    expect(expanded, contains("'Diagnóstico'"));
    expect(expanded, contains('required String? diagnosis'));
  });

  test('mobile status selector separates selection from management', () {
    final statusManager = _section(
      table,
      'class _StatusManagerDialogState',
      'class _StatusListItem',
    );

    expect(
      statusManager,
      contains("ValueKey('workshop-status-manager-dialog')"),
    );
    expect(
      statusManager,
      contains("ValueKey('workshop-status-compact-list')"),
    );
    expect(statusManager, contains('BoxConstraints(minHeight: 56)'));
    expect(statusManager, contains("'Cambiar estado a \${status.name}'"));
    expect(statusManager, contains("'Gestionar \${status.name}'"));
    expect(statusManager, contains('Size.square(usesCompactLayout ? 48 : 24)'));
    expect(statusManager, contains("Text('Editar estado')"));
    expect(statusManager, contains("'Eliminar estado'"));
  });

  test('mobile board recomposes columns into an in-place status list', () {
    final board = _section(
      table,
      'Widget _buildBoardView',
      '/// Board column for custom status',
    );

    expect(
      board,
      contains('ResponsiveViewport.usesCompactShell(context)'),
    );
    expect(board, contains('WorkshopBoardCompactView(groups: compactGroups)'));
    expect(board, contains('_buildCompactBoardCard('));
    expect(board, contains("const Text('Cambiar estado')"));
    expect(
      board,
      contains('_showStatusMenu(job)'),
      reason: 'The compact board must retain the canonical status command.',
    );

    final desktopColumn = _section(
      table,
      'Widget _buildCustomBoardColumn',
      'Widget _buildLegacyBoardColumn',
    );
    expect(
      desktopColumn,
      contains('width: 320'),
      reason: 'The established desktop kanban column remains unchanged.',
    );
  });

  test('mobile detail delegates status and document work to shared owners', () {
    for (final hook in const [
      'workshop-detail-action-status',
      'workshop-detail-action-items',
      'workshop-detail-action-invoice',
      'workshop-detail-action-payment',
      'workshop-detail-action-bike',
      'workshop-detail-action-customer',
    ]) {
      expect(detail, contains(hook), reason: 'Missing detail hook $hook');
    }
    expect(detail, contains('final canonicalAction = widget.onStatusPressed;'));
    expect(detail, contains('canonicalAction();'));
    expect(detail, contains('minimumSize: const Size(0, 48)'));
  });
}
