import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/shared/models/desktop_release_notes.dart';
import 'package:vinabike_erp/shared/services/desktop_update_service.dart';
import 'package:vinabike_erp/shared/widgets/desktop_update_prompt.dart';

void main() {
  const commit = '2222222222222222222222222222222222222222';

  DesktopReleaseNotes notes() {
    return DesktopReleaseNotes(
      schemaVersion: 1,
      locale: 'es-CL',
      source: 'ai',
      fromCommit: '1111111111111111111111111111111111111111',
      toCommit: commit,
      title: 'Novedades de esta actualización',
      summary: 'Mejoramos varias tareas para que el trabajo sea más simple.',
      modules: [
        DesktopReleaseNotesModule(
          id: 'workshop',
          label: 'Taller',
          items: [
            'Ahora es más fácil revisar y descargar presupuestos.',
            'La información importante se entiende más rápido.',
          ],
          evidencePaths: [
            'lib/modules/bikeshop/pages/pegas_table_page.dart',
          ],
        ),
        DesktopReleaseNotesModule(
          id: 'inventory',
          label: 'Inventario',
          items: ['Mejoramos la revisión de disponibilidad.'],
          evidencePaths: [
            'lib/modules/inventory/pages/product_list_page.dart',
          ],
        ),
      ],
    );
  }

  DesktopUpdateInfo update({DesktopReleaseNotes? releaseNotes}) {
    return DesktopUpdateInfo(
      tag: 'macos-v1.0.1-42',
      releaseName: 'Vinabike ERP macos-v1.0.1-42',
      assetName: 'vinabike_erp_macos_1.0.1-42.zip',
      installerDownloadUrl: 'https://example.invalid/installer',
      commit: commit,
      releaseNotes: releaseNotes,
    );
  }

  Future<void> pumpPrompt(
    WidgetTester tester,
    _FakeDesktopUpdateService service,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DesktopUpdateService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                DesktopUpdatePrompt(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows Novedades beside the primary restart action', (
    tester,
  ) async {
    final service = _FakeDesktopUpdateService(update(releaseNotes: notes()));
    addTearDown(service.dispose);
    await pumpPrompt(tester, service);

    expect(
      find.byKey(const ValueKey('desktop-update-whats-new-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-update-primary-button')),
      findsOneWidget,
    );
    expect(find.text('Reiniciar'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop-update-whats-new-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-release-notes-dialog')),
      findsOneWidget,
    );
    expect(find.text('Novedades de esta actualización'), findsOneWidget);
    expect(find.text('Taller'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);
    expect(
      find.text('Ahora es más fácil revisar y descargar presupuestos.'),
      findsOneWidget,
    );
    expect(
      find.text('lib/modules/bikeshop/pages/pegas_table_page.dart'),
      findsNothing,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    final dialogSize = tester.getSize(
      find.byKey(const ValueKey('desktop-release-notes-dialog')),
    );
    expect(dialogSize.width, lessThanOrEqualTo(520));
  });

  testWidgets('hides Novedades when validated notes are absent', (
    tester,
  ) async {
    final service = _FakeDesktopUpdateService(update());
    addTearDown(service.dispose);
    await pumpPrompt(tester, service);

    expect(
      find.byKey(const ValueKey('desktop-update-whats-new-button')),
      findsNothing,
    );
    expect(find.text('Reiniciar'), findsOneWidget);
  });
}

class _FakeDesktopUpdateService extends DesktopUpdateService {
  final DesktopUpdateInfo update;

  _FakeDesktopUpdateService(this.update);

  @override
  bool get isSupported => true;

  @override
  bool get isChecking => false;

  @override
  bool get isPreparing => false;

  @override
  bool get isUpdating => false;

  @override
  bool get isUpdateReady => true;

  @override
  bool get hasDismissedReadyUpdate => false;

  @override
  DesktopUpdateInfo? get availableUpdate => update;

  @override
  String? get errorMessage => null;

  @override
  Future<void> checkForUpdate({
    bool force = false,
    bool revealDismissed = true,
  }) async {}

  @override
  Future<void> startUpdate() async {}

  @override
  void dismissAvailableUpdate() {}
}
