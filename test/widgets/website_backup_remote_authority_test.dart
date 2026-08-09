import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_backup_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

WebsiteEditorCapabilitySnapshot _cap(String identity, {int epoch = 0}) {
  return WebsiteEditorCapabilitySnapshot(
    identity: identity,
    activeTenantId: 'tenant-a',
    storefrontTenantId: 'tenant-a',
    hasAuthority: true,
    authorityEpoch: epoch,
  );
}

WebsiteEditModeProvider _sessionA({bool dirty = false}) {
  final provider = WebsiteEditModeProvider();
  provider.adoptEditorEntryLease(0, _cap('user-a'));
  provider.applyRouteModeCommand(WebsiteEditorMode.edit);
  provider.activatePageDocument(
    const <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'block-a',
        'block_type': 'about',
        'block_data': <String, dynamic>{'title': 'Página A'},
        'order_index': 0,
        'is_visible': true,
      },
    ],
    const <String, dynamic>{},
    pageId: 'page-a',
    pageSlug: 'page-a',
  );
  if (dirty) provider.updateBlockData('block-a', 'title', 'Borrador A');
  return provider;
}

void _switchToB(WebsiteEditModeProvider provider) {
  provider.revokeEditorEntryLease();
  provider.adoptEditorEntryLease(
    provider.editorEntryLeaseGeneration,
    _cap('user-b', epoch: 1),
  );
  provider.applyRouteModeCommand(WebsiteEditorMode.edit);
  provider.activatePageDocument(
    const <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'block-b',
        'block_type': 'about',
        'block_data': <String, dynamic>{'title': 'Página B'},
        'order_index': 0,
        'is_visible': true,
      },
    ],
    const <String, dynamic>{},
    pageId: 'page-b',
    pageSlug: 'page-b',
  );
}

WebsiteBackup _backup(String id, String name) => WebsiteBackup(
      id: id,
      name: name,
      blockCount: 1,
      isAutoBackup: false,
      createdAt: DateTime.utc(2026, 8, 9),
    );

class _FakeBackupService extends WebsiteBackupService {
  _FakeBackupService()
      : super(
          supabase: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const <Map<String, dynamic>>[],
          ),
        );

  final List<Completer<List<WebsiteBackup>>> loadResults =
      <Completer<List<WebsiteBackup>>>[];
  int loadCalls = 0;
  int createCalls = 0;
  int restoreCalls = 0;
  int deleteCalls = 0;
  String? createdName;

  void enqueueLoad(List<WebsiteBackup> backups) {
    loadResults.add(Completer<List<WebsiteBackup>>()..complete(backups));
  }

  @override
  Future<List<WebsiteBackup>> loadBackups({
    required String tenantId,
    required WebsiteEditorWriteGuard readGuard,
  }) async {
    readGuard();
    final index = loadCalls++;
    final result = index < loadResults.length
        ? await loadResults[index].future
        : const <WebsiteBackup>[];
    readGuard();
    return result;
  }

  @override
  Future<String?> createBackup({
    required String name,
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
    String? description,
    bool isAutoBackup = false,
  }) async {
    writeGuard();
    createCalls++;
    createdName = name;
    return 'created';
  }

  @override
  Future<bool> restoreBackup(
    String backupId, {
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
    bool createSafetyBackup = true,
  }) async {
    writeGuard();
    restoreCalls++;
    return true;
  }

  @override
  Future<bool> deleteBackup(
    String backupId, {
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
  }) async {
    writeGuard();
    deleteCalls++;
    return true;
  }
}

WebsiteService _websiteService() => WebsiteService(
      supabase: SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      tenantService: TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      ),
    );

Widget _host(
  WebsiteEditModeProvider provider,
  WebsiteService websiteService,
  WebsiteBackupService backupService, {
  Future<void> Function()? onRestoreComplete,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WebsiteEditModeProvider>.value(value: provider),
      ChangeNotifierProvider<WebsiteService>.value(value: websiteService),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SizedBox(
          width: 430,
          height: 850,
          child: WebsiteEditorPanel(
            backupService: backupService,
            onRestoreComplete: onRestoreComplete,
          ),
        ),
      ),
    ),
  );
}

Future<void> _openBackups(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Copias de seguridad'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a stale backup read cannot populate the replacement session',
      (tester) async {
    final provider = _sessionA();
    final websiteService = _websiteService();
    final backupService = _FakeBackupService();
    final loadA = Completer<List<WebsiteBackup>>();
    final loadB = Completer<List<WebsiteBackup>>();
    backupService.loadResults.addAll(<Completer<List<WebsiteBackup>>>[
      loadA,
      loadB,
    ]);
    addTearDown(provider.dispose);
    addTearDown(websiteService.dispose);
    addTearDown(backupService.dispose);

    await tester.pumpWidget(_host(provider, websiteService, backupService));
    await _openBackups(tester);
    expect(backupService.loadCalls, 1);

    _switchToB(provider);
    await tester.pump();
    await tester.pump();
    expect(backupService.loadCalls, 2);

    loadA.complete(<WebsiteBackup>[_backup('a', 'Copia A')]);
    await tester.pump();
    expect(find.text('Copia A'), findsNothing);
    loadB.complete(<WebsiteBackup>[_backup('b', 'Copia B')]);
    await tester.pumpAndSettle();
    expect(find.text('Copia A'), findsNothing);
    expect(find.text('Copia B'), findsOneWidget);
  });

  testWidgets('restore is blocked while the page has an unsaved draft',
      (tester) async {
    final provider = _sessionA(dirty: true);
    final websiteService = _websiteService();
    final backupService = _FakeBackupService()
      ..enqueueLoad(<WebsiteBackup>[_backup('a', 'Copia A')]);
    addTearDown(provider.dispose);
    addTearDown(websiteService.dispose);
    addTearDown(backupService.dispose);

    await tester.pumpWidget(_host(provider, websiteService, backupService));
    await _openBackups(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pump();

    expect(backupService.restoreCalls, 0);
    expect(
      find.text(
        'Guarda o descarta los cambios antes de administrar copias de seguridad.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a create draft from A is cleared before B can submit it',
      (tester) async {
    final provider = _sessionA();
    final websiteService = _websiteService();
    final backupService = _FakeBackupService()
      ..enqueueLoad(<WebsiteBackup>[_backup('a', 'Copia A')])
      ..enqueueLoad(<WebsiteBackup>[_backup('b', 'Copia B')]);
    addTearDown(provider.dispose);
    addTearDown(websiteService.dispose);
    addTearDown(backupService.dispose);

    await tester.pumpWidget(_host(provider, websiteService, backupService));
    await _openBackups(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Borrador de A');
    _switchToB(provider);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Borrador de A'), findsNothing);
    await tester.tap(find.text('Crear copia de seguridad'));
    await tester.pump();
    expect(backupService.createCalls, 0);
    expect(backupService.createdName, isNull);
    expect(find.text('El nombre es requerido'), findsOneWidget);
  });

  testWidgets('restore confirmation from A cannot issue an RPC after A to B',
      (tester) async {
    final provider = _sessionA();
    final websiteService = _websiteService();
    final backupService = _FakeBackupService()
      ..enqueueLoad(<WebsiteBackup>[_backup('a', 'Copia A')])
      ..enqueueLoad(<WebsiteBackup>[_backup('b', 'Copia B')]);
    addTearDown(provider.dispose);
    addTearDown(websiteService.dispose);
    addTearDown(backupService.dispose);

    await tester.pumpWidget(_host(provider, websiteService, backupService));
    await _openBackups(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    _switchToB(provider);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Restaurar'),
      ),
    );
    await tester.pump();

    expect(backupService.restoreCalls, 0);
    expect(find.text('La sesión del editor cambió. Vuelve a intentar.'),
        findsOneWidget);
  });

  testWidgets('a valid restore issues one RPC and one reopen callback',
      (tester) async {
    final provider = _sessionA();
    final websiteService = _websiteService();
    final backupService = _FakeBackupService()
      ..enqueueLoad(<WebsiteBackup>[_backup('a', 'Copia A')]);
    var restoreCompleteCalls = 0;
    addTearDown(provider.dispose);
    addTearDown(websiteService.dispose);
    addTearDown(backupService.dispose);

    await tester.pumpWidget(
      _host(
        provider,
        websiteService,
        backupService,
        onRestoreComplete: () async => restoreCompleteCalls++,
      ),
    );
    await _openBackups(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Restaurar'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Restaurar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(backupService.restoreCalls, 1);
    expect(restoreCompleteCalls, 1);
  });
}
