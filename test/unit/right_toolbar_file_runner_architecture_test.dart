import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('right toolbar exposes the docked file runner', () {
    final service = File(
      'lib/shared/services/right_toolbar_service.dart',
    ).readAsStringSync();
    final toolbar = File(
      'lib/shared/widgets/right_toolbar.dart',
    ).readAsStringSync();
    final presentationCatalog = File(
      'lib/shared/widgets/toolbar_tool_presentation.dart',
    ).readAsStringSync();
    final filesPanel = File(
      'lib/modules/storage/widgets/app_files_panel.dart',
    ).readAsStringSync();
    final spreadsheetRunner = File(
      'lib/modules/spreadsheets/widgets/stored_spreadsheet_runner.dart',
    ).readAsStringSync();
    final exporter = File(
      'lib/modules/spreadsheets/services/spreadsheet_file_exporter.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(service, contains('fileRunner,'));
    expect(presentationCatalog, contains("title: 'Ejecutar archivos'"));
    expect(presentationCatalog, contains('Icons.play_circle_outline'));
    expect(toolbar, contains('runnerMode: true'));
    expect(
      toolbar,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
    expect(toolbar, contains('SingleChildScrollView('));
    expect(toolbar, contains('_absoluteMaxWidth = 1600.0'));
    expect(toolbar, contains('_maxWindowFraction = 0.82'));
    expect(toolbar, contains('MediaQuery.sizeOf(context).width'));
    expect(filesPanel, contains('class _InlineStorageFileRunner'));
    expect(filesPanel, contains("ValueKey('file-runner-"));
    expect(filesPanel, contains('AppFileStorageService.instance.downloadFile'));
    expect(filesPanel, contains('replaceFileBytes('));
    expect(filesPanel, contains('StorageImageCropDialog.show('));
    expect(filesPanel, contains('PdfPreview('));
    expect(filesPanel, contains('StoredSpreadsheetRunner('));
    expect(filesPanel, contains('Imprimir PDF'));
    expect(filesPanel, contains('Descargar PDF'));
    expect(filesPanel, contains('_RunnerPdfPagesCanvas'));
    expect(spreadsheetRunner, contains('UniverSpreadsheetView('));
    expect(spreadsheetRunner, contains('replaceFileBytes('));
    expect(spreadsheetRunner, contains('.encodeBytes('));
    expect(spreadsheetRunner, contains('Guardado en el archivo'));
    expect(exporter, contains('class SpreadsheetFileExporter'));
    expect(exporter, contains('Excel.createExcel()'));
    expect(registry, contains('Docked file runner'));
    expect(registry, contains('`AppFilesPanel(runnerMode: true)`'));
    expect(registry, contains('PDF exposes zoom/print/download/reload'));
    expect(registry, contains('encode back through `replaceFileBytes`'));
  });
}
