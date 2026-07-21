import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/spreadsheets/pages/spreadsheet_editor_page.dart';

void main() {
  test('route exit guard targets the active workbook registration', () async {
    final firstOwner = Object();
    final secondOwner = Object();
    SpreadsheetEditorExitGuard.register(
        'sheet-a', firstOwner, () async => false);
    SpreadsheetEditorExitGuard.register(
        'sheet-b', secondOwner, () async => true);

    expect(await SpreadsheetEditorExitGuard.canExit('sheet-a'), isFalse);
    expect(await SpreadsheetEditorExitGuard.canExit('sheet-b'), isTrue);
    expect(await SpreadsheetEditorExitGuard.canExit('unmounted'), isTrue);

    SpreadsheetEditorExitGuard.unregister('sheet-a', Object());
    expect(await SpreadsheetEditorExitGuard.canExit('sheet-a'), isFalse);

    SpreadsheetEditorExitGuard.unregister('sheet-a', firstOwner);
    SpreadsheetEditorExitGuard.unregister('sheet-b', secondOwner);
    expect(await SpreadsheetEditorExitGuard.canExit('sheet-a'), isTrue);
  });

  test('spreadsheet routes use the canonical dashboard and Univer editor', () {
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    final barrel =
        File('lib/shared/routes/erp_routes_barrel.dart').readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
    final workspaceManager = File(
      'lib/shared/services/workspace_manager.dart',
    ).readAsStringSync();

    expect(router, contains("path: '/tools/spreadsheets'"));
    expect(router, contains("path: '/tools/spreadsheets/:id'"));
    expect(
      router,
      contains('erp.SpreadsheetEditorExitGuard.canExit('),
    );
    expect(router, contains('erp.SpreadsheetDashboardPage()'));
    expect(router, contains('erp.SpreadsheetEditorPage(spreadsheetId: id)'));
    expect(
      barrel,
      contains("spreadsheets/pages/spreadsheet_dashboard_page.dart"),
    );
    expect(
      barrel,
      contains("spreadsheets/pages/spreadsheet_editor_page.dart"),
    );
    expect(registry, contains('## Spreadsheet Workspace Surfaces'));
    expect(registry, contains('`SpreadsheetStore`'));
    expect(registry, contains('`UniverSpreadsheetView`'));
    expect(registry, contains('WKWebView/WebView2'));
    expect(registry, contains('automatic retry-on-edit requests'));
    expect(registry, contains('Stored workbook import'));
    expect(registry, contains('`SpreadsheetFileHandoffService`'));
    expect(workspaceManager, contains("'/tools',"));
    expect(workspaceManager, contains('resolveInitialWorkspaceRoute'));
  });

  test('packaged Univer engine is hosted natively on macOS and Windows', () {
    final conditionalExport = File(
      'lib/modules/spreadsheets/widgets/univer_spreadsheet.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'lib/modules/spreadsheets/widgets/univer_spreadsheet_native.dart',
    ).readAsStringSync();
    final nativeHost = File(
      'web/spreadsheet_engine/univer_desktop_host.html',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final macosBootstrap =
        File('scripts/bootstrap/bootstrap_macos.sh').readAsStringSync();
    final windowsBootstrap =
        File('scripts/bootstrap/bootstrap_windows.ps1').readAsStringSync();
    final integrityWorkflow =
        File('.github/workflows/erp-integrity-gate.yml').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(
      conditionalExport,
      contains("if (dart.library.io) 'univer_spreadsheet_native.dart'"),
    );
    expect(nativeBridge, contains('InAppWebView('));
    expect(nativeBridge, contains('initialFile: _hostAssetPath'));
    expect(nativeBridge, contains('callAsyncJavaScript('));
    expect(nativeBridge, contains('handlerName: _bridgeHandlerName'));
    expect(nativeBridge, contains('unawaited(_focusEngine(controller))'));
    expect(nativeBridge, contains('WindowZoomService'));
    expect(nativeBridge, contains('Transform.scale('));
    expect(nativeBridge, contains('scale: 1 / appScale'));
    expect(nativeHost, contains('vinabike-univer-root'));
    expect(nativeHost, contains('window.flutter_inappwebview'));
    expect(nativeHost, contains('bridge.callHandler(handlerName, payload)'));
    expect(nativeHost, contains('univer.bundle.js'));
    expect(
      pubspec,
      contains('- web/spreadsheet_engine/univer_desktop_host.html'),
    );
    expect(pubspec, contains('- web/spreadsheet_engine/univer.bundle.js'));
    expect(pubspec, contains('- web/spreadsheet_engine/univer.bundle.css'));
    expect(macosBootstrap, contains('npm run build:spreadsheet-engine'));
    expect(windowsBootstrap, contains('npm run build:spreadsheet-engine'));
    expect(
      File('web/spreadsheet_engine/univer.bundle.js').existsSync(),
      isTrue,
    );
    expect(
      File('web/spreadsheet_engine/univer.bundle.css').existsSync(),
      isTrue,
    );
    expect(
      gitignore,
      isNot(contains('/web/spreadsheet_engine/univer.bundle.js')),
    );
    expect(
      gitignore,
      isNot(contains('/web/spreadsheet_engine/univer.bundle.css')),
    );
    expect(
      integrityWorkflow,
      contains('Verify packaged spreadsheet assets are committed'),
    );
    expect(integrityWorkflow, contains('git diff --exit-code --'));
  });

  test('editor delegates workbook behavior to Univer and persists snapshots',
      () {
    final editor = File(
      'lib/modules/spreadsheets/pages/spreadsheet_editor_page.dart',
    ).readAsStringSync();
    final adapter = File(
      'lib/modules/spreadsheets/services/univer_workbook_adapter.dart',
    ).readAsStringSync();
    final bridge = File(
      'lib/modules/spreadsheets/widgets/univer_spreadsheet_web.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/spreadsheets/services/spreadsheet_service.dart',
    ).readAsStringSync();
    final packageManifest = File('package.json').readAsStringSync();

    expect(editor, contains('UniverSpreadsheetView('));
    expect(editor, contains('UniverWorkbookAdapter.createSnapshot('));
    expect(editor, contains('_univerController.requestSnapshot()'));
    expect(editor, contains('_latestPendingSnapshot'));
    expect(editor, contains('_runSaveCycle'));
    expect(editor, contains('_store.saveWorkbookData('));
    expect(editor, contains('SpreadsheetEditorExitGuard.register('));
    expect(editor, contains('Future<bool> _guardRouteExit()'));
    expect(editor, contains('Cambios pendientes'));
    expect(editor, contains('Error · Reintentar'));
    expect(editor, contains('Base de datos · Reintentar'));
    expect(adapter, contains('legacyCells'));
    expect(adapter, contains('spreadsheet.workbookData'));
    expect(adapter, contains('static bool isValidSnapshot('));
    expect(bridge, contains('Future<Map<String, dynamic>?> requestSnapshot()'));
    expect(service, contains('abstract interface class SpreadsheetStore'));
    expect(service, contains('Future<void> saveWorkbookData('));
    expect(service, contains('SpreadsheetSnapshotSchemaException'));
    expect(packageManifest, contains('"@univerjs/presets": "0.25.1"'));
    expect(
      packageManifest,
      contains('"@univerjs/preset-sheets-core": "0.25.1"'),
    );
    expect(
      File(
        'lib/modules/spreadsheets/widgets/native_spreadsheet_grid.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/modules/spreadsheets/services/formula_engine.dart',
      ).existsSync(),
      isFalse,
    );

    for (final forbidden in [
      'NativeSpreadsheetGrid',
      'FormulaEngine',
      '_buildToolbar',
      '_buildFormulaBar',
      'spreadsheet-formula-bar',
      'WebViewWidget',
      'WebviewController',
      'x_spreadsheet',
      'jsdelivr',
      '_spreadsheetShellHtml',
      'MouseEvent.offsetX',
    ]) {
      expect(editor, isNot(contains(forbidden)));
    }
  });

  test('dashboard exposes search and honest load failure handling', () {
    final dashboard = File(
      'lib/modules/spreadsheets/pages/spreadsheet_dashboard_page.dart',
    ).readAsStringSync();

    expect(dashboard, contains('spreadsheet-search-field'));
    expect(dashboard, contains('No se pudieron cargar las planillas'));
    expect(dashboard, contains("'TAMAÑO'"));
    expect(dashboard, contains("'ÚLTIMA ACTUALIZACIÓN'"));
    expect(dashboard, contains('import-spreadsheet-action'));
    expect(dashboard, contains('SpreadsheetFileHandoffService.instance'));
    expect(dashboard, isNot(contains('SliverGrid')));
  });

  test('Archivos, Correo, and Planillas share one workbook import workflow',
      () {
    final filesPanel = File(
      'lib/modules/storage/widgets/app_files_panel.dart',
    ).readAsStringSync();
    final mailDetail = File(
      'lib/modules/mail/widgets/email_detail_view_unified.dart',
    ).readAsStringSync();
    final handoff = File(
      'lib/shared/services/spreadsheet_file_handoff_service.dart',
    ).readAsStringSync();
    final importer = File(
      'lib/modules/spreadsheets/services/spreadsheet_file_importer.dart',
    ).readAsStringSync();

    expect(filesPanel, contains('Abrir en Planillas'));
    expect(filesPanel, contains('SpreadsheetFileHandoffService.instance'));
    expect(mailDetail, contains('Abrir en Planillas'));
    expect(mailDetail, contains('SpreadsheetFileHandoffService.instance'));
    expect(mailDetail, contains('.importBytes('));
    expect(handoff, contains('_backgroundDecodeThresholdBytes'));
    expect(handoff, contains('_decodeStoredSpreadsheetToJson'));
    expect(handoff, contains('return jsonEncode('));
    expect(handoff, contains('return store.createSpreadsheet('));
    expect(importer, contains("supportedExtensions = <String>{'xlsx', 'csv'}"));
    expect(importer, contains("'mergeData': mergeData"));
    expect(importer, contains("output['f']"));
  });
}
