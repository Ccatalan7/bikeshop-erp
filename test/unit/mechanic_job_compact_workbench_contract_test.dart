import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String section(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  expect(end, greaterThan(start), reason: 'Missing $endMarker');
  return source.substring(start, end);
}

void main() {
  final source = File(
    'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
  ).readAsStringSync();

  test('job workbench inherits one root compact boundary', () {
    final policy = section(
      source,
      'abstract final class MechanicJobResponsivePolicy',
      'class MechanicJobCompactWorkbenchNavigation',
    );
    expect(policy, contains('viewportWidth < ResponsiveViewport.desktopMin'));

    final header = section(
      source,
      'Widget _buildHeader',
      'Widget _buildInlineWorkspaceHeader',
    );
    expect(
      header,
      contains('MechanicJobResponsivePolicy.usesCompactComposition'),
    );
    expect(header, contains('ResponsiveViewport.widthOf(context)'));
    expect(header, contains('if (isCompact)'));
    expect(header, isNot(contains('constraints.maxWidth < 600')));

    final products = section(
      source,
      'Widget _buildPartsSection',
      'Widget _buildMobilePartsSection',
    );
    expect(
      products,
      contains('MechanicJobResponsivePolicy.usesCompactComposition'),
    );
    expect(products, contains('return _buildMobilePartsSection(theme)'));
    expect(products, isNot(contains('constraints.maxWidth < 600')));

    final bikeContext = section(
      source,
      'class _MechanicJobBikeContextCardState',
      'class MechanicJobFormPage',
    );
    expect(
      bikeContext,
      contains('MechanicJobResponsivePolicy.usesCompactComposition'),
    );
    expect(
      bikeContext,
      isNot(contains('ResponsiveViewport.phoneMaxExclusive')),
    );
  });

  test('compact navigation has complete labels and resets inherited scroll',
      () {
    final tabs = section(
      source,
      'Widget _buildWorkbenchTabs',
      'void _updateCurrentDiagnosisSheet',
    );
    expect(tabs, contains('MechanicJobCompactWorkbenchNavigation('));
    expect(tabs, contains("productsLabel: _jobType == JobType.sale"));
    expect(tabs, contains("'Cobro' : 'Ítems'"));
    expect(tabs, contains('void _selectWorkbenchTab'));
    expect(tabs, contains('Scrollable.ensureVisible('));
    expect(tabs, contains('_workbenchSectionKey.currentContext'));

    final form = section(
      source,
      'Widget _buildForm',
      'Widget _lockFormContent',
    );
    expect(form, contains('widget.isInlineWorkspace && widget.jobId != null'));
    expect(form, contains('key: _workbenchSectionKey'));
    expect(form, contains('key: _customerSectionKey'));
    expect(form, contains('key: _costSummarySectionKey'));
  });

  test('compact diagnosis prioritizes one inspector and defers the map', () {
    final workspace = section(
      source,
      'Widget _buildDiagnosisWorkspace',
      'Widget _buildDiagnosisSection',
    );
    expect(workspace, contains('Aún no hay sistemas revisados.'));
    expect(workspace, contains('alerta crítica'));
    expect(workspace, isNot(contains('storage model')));
    expect(workspace, isNot(contains('Template ')));
    expect(workspace, isNot(contains("'Sync ")));

    final structured = section(
      source,
      'Widget _buildStructuredDiagnosisPanel',
      'String _resolveStructuredDiagnosisSystemKey',
    );
    expect(structured, contains('MechanicJobCompactChoiceMenu('));
    expect(
      structured,
      contains("'mechanic-job-diagnosis-map-disclosure'"),
    );
    final compactBranch = section(
      structured,
      'if (isCompact)',
      'if (wideLayout)',
    );
    expect(
      compactBranch.indexOf('inspectorPanel'),
      lessThan(
        compactBranch.indexOf(
          '_buildDiagnosisMapDisclosure(',
        ),
      ),
      reason: 'The editable inspector must precede the optional map.',
    );

    final componentSelector = section(
      source,
      'Widget _buildDiagnosisComponentSelector',
      'Widget _buildDrivetrainComponentEditor',
    );
    expect(componentSelector, contains("controlLabel: 'Componente'"));
    expect(componentSelector, contains('MechanicJobCompactChoiceMenu('));
    expect(source, isNot(contains('Headset y direccion anclados en cockpit')));
    expect(source, isNot(contains('Haz clic en un sistema')));
  });

  test('draft guard and validation return users to the owning surface', () {
    final cancel = section(
      source,
      'void _handleCancel',
      'String _buildInlineDraftFingerprint',
    );
    expect(cancel, contains('_inlineDraftHasUnsavedChanges'));
    expect(cancel, contains('const MechanicJobDiscardDialog()'));
    expect(cancel, contains('await _completeCancelNavigation()'));
    expect(cancel, contains('widget.onCanceled?.call()'));
    expect(cancel, contains('await _leaveRoutedForm()'));
    expect(cancel, isNot(contains('if (widget.isInlineWorkspace)')));

    final build = section(
      source,
      'final content = Form(',
      'Widget _buildExistingJobLoadFailure',
    );
    expect(build, contains('return PopScope('));
    expect(build, contains('canPop: _allowRoutePop'));

    final validation = section(
      source,
      'void _revealFormIssue',
      'var protectPaymentCommercialSnapshot',
    );
    expect(validation, contains('_MechanicJobFormIssueOwner.customer'));
    expect(validation, contains('_MechanicJobFormIssueOwner.general'));
    expect(validation, contains('_MechanicJobFormIssueOwner.products'));
    expect(validation, contains('_MechanicJobFormIssueOwner.costSummary'));
    expect(validation, contains('Scrollable.ensureVisible('));
    expect(validation, contains('_partAutocompleteFocus.requestFocus()'));
    expect(validation, contains('_discountFocusNode.requestFocus()'));
  });
}
