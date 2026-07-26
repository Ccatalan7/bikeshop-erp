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
  test('compact invoice close behavior remains host-aware and single-flight',
      () {
    final editor = File(
      'lib/modules/sales/widgets/sales_invoice_editor.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/modules/bikeshop/widgets/pegas_calendar_widget.dart',
    ).readAsStringSync();

    final closeFlow = _section(
      editor,
      'Future<void> _requestClose() async',
      'void _startEditing()',
    );
    expect(closeFlow, contains('_isSaving || _isDiscardPromptOpen'));
    expect(closeFlow, contains('_isDiscardPromptOpen = true'));
    expect(closeFlow, contains('finally {'));
    expect(closeFlow, contains('_isDiscardPromptOpen = false'));

    final actions = _section(
      editor,
      'List<Widget> _buildActionButtons()',
      'Widget _buildForm(ThemeData theme)',
    );
    expect(
      actions,
      contains("ValueKey('invoice-editor-compact-cancel')"),
    );
    expect(actions, contains('widget.onCloseRequested != null'));
    expect(actions, contains('() => unawaited(_requestClose())'));
    expect(actions, contains(': _cancelEditing'));

    final calendarInvoiceHost = _section(
      calendar,
      'Widget _buildInvoiceTab(MechanicJob job)',
      'Widget _buildProposalSummaryTab(MechanicJob job)',
    );
    expect(calendarInvoiceHost, contains('SalesInvoiceEditor('));
    expect(calendarInvoiceHost, contains('isCompact: true'));
    expect(
      calendarInvoiceHost,
      isNot(contains('onCloseRequested:')),
      reason:
          'The calendar tab must cancel editing locally, not close a host route.',
    );
  });
}
