import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar separates operational and proposal lifecycle semantics', () {
    final calendar = File(
      'lib/modules/bikeshop/widgets/pegas_calendar_widget.dart',
    ).readAsStringSync();

    final colorStart = calendar.indexOf('Color _getJobColor(MechanicJob job)');
    final colorEnd =
        calendar.indexOf('Color _getProposalStatusColor', colorStart);
    final colorContract = calendar.substring(colorStart, colorEnd);
    expect(colorContract, contains('job.isStandaloneQuotation'));
    expect(colorContract, isNot(contains('job.isQuotationWorkflow')));

    expect(calendar, contains('job.proposalStatusDisplayName'));
    expect(calendar, contains('if (job.isServiceBudget)'));
    expect(
      calendar,
      contains('!job.isStandaloneQuotation && job.statusUpdatedAt != null'),
      reason:
          'The operational timestamp must not be presented as a quotation-event timestamp.',
    );
    expect(
      calendar,
      contains('readOnly: job.hasFinalProposalDecision'),
    );
    expect(calendar, contains('readOnly: proposalIsFinal'));
    expect(calendar, contains("? 'Entregar Componente'"));
  });

  test('detail keeps service-budget operations and component intake truthful',
      () {
    final detail = File(
      'lib/modules/bikeshop/widgets/pega_detail_view.dart',
    ).readAsStringSync();

    expect(detail, contains("'Estado operativo'"));
    expect(detail, contains("'Estado comercial'"));
    expect(detail, contains('widget.job.proposalStatusDisplayName'));
    expect(detail, contains("'Cambiar estado operativo'"));
    expect(detail, contains("? 'Componente recibido'"));
    expect(detail, contains('widget.job.subjectDisplayName'));
    expect(detail, contains('readOnly: proposalIsFinal'));
    expect(
      detail,
      contains('job.hasFinalProposalDecision ? null : widget.onEdit'),
    );
  });

  test('shared job details editor enforces an actual read-only mode', () {
    final editor = File(
      'lib/modules/bikeshop/widgets/smart_job_details_editor.dart',
    ).readAsStringSync();

    expect(editor, contains('final bool readOnly;'));
    expect(editor, contains('this.readOnly = false'));
    expect(editor, contains('readOnly: widget.readOnly'));
    expect(editor, contains('if (widget.readOnly) return;'));
    expect(editor, contains('Solo lectura · decisión comercial cerrada'));
  });
}
