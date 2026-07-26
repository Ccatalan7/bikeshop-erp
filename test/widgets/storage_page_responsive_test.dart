import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/storage/models/app_stored_file.dart';
import 'package:vinabike_erp/modules/storage/pages/storage_page.dart';
import 'package:vinabike_erp/modules/storage/widgets/app_files_panel.dart';

void main() {
  testWidgets(
    'Storage uses compact phone/tablet composition and desktop two-pane layout',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final requestedLimits = <int>[];
      final loader = _loader(requestedLimits);

      for (final size in <Size>[
        const Size(384, 824),
        const Size(599, 824),
        const Size(600, 824),
        const Size(899, 824),
        const Size(900, 900),
        const Size(1440, 900),
      ]) {
        await _pumpStorage(
          tester,
          size: size,
          filesLoader: loader,
        );

        final compact = size.width < 900;
        final panel = tester.widget<AppFilesPanel>(
          find.byType(AppFilesPanel),
        );
        expect(
          panel.compact,
          compact,
          reason: '${size.width} must use the canonical composition',
        );
        expect(
          find.byKey(
            ValueKey(
              compact ? 'storage-panel-compact' : 'storage-panel-desktop',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('storage-compact-tabs')),
          compact ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('storage-desktop-folder-sidebar')),
          compact ? findsNothing : findsOneWidget,
        );

        _expectInsideViewport(
          tester,
          find.byKey(const ValueKey('storage-search')),
          size,
        );
        _expectInsideViewport(
          tester,
          find.byKey(const ValueKey('storage-sort')),
          size,
        );
        _expectInsideViewport(
          tester,
          compact
              ? find.byKey(const ValueKey('storage-compact-tabs'))
              : find.byKey(
                  const ValueKey('storage-desktop-folder-sidebar'),
                ),
          size,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${size.width} must not overflow or clip',
        );
      }

      expect(requestedLimits, contains(120));
      expect(requestedLimits, contains(360));
    },
  );

  testWidgets(
    'compact Storage keeps 48px targets and supports in-panel navigation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(384, 824);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final semanticsHandle = tester.ensureSemantics();

      await _pumpStorage(
        tester,
        size: const Size(384, 824),
        textScale: 1.3,
        filesLoader: _loader(<int>[]),
      );

      for (final key in <String>[
        'storage-search',
        'storage-sort',
        'storage-tab-carpetas',
        'storage-tab-recientes',
        'storage-tab-capturas',
        'storage-preview-file-manual',
        'storage-more-file-manual',
      ]) {
        _expectMinimumTouchTarget(
          tester,
          find.byKey(ValueKey(key)),
          reason: key,
        );
      }

      final foldersTab = find.byKey(const ValueKey('storage-tab-carpetas'));
      final foldersSemantics = tester.widget<Semantics>(foldersTab);
      expect(foldersSemantics.properties.label, 'Carpetas');
      expect(foldersSemantics.properties.button, isTrue);
      expect(find.byTooltip('Ordenar archivos'), findsOneWidget);
      await tester.tap(foldersTab);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('storage-compact-folder-tree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('storage-file-list')),
        findsNothing,
      );
      _expectMinimumTouchTarget(
        tester,
        find.byKey(const ValueKey('storage-folder-all')),
        reason: 'compact folder',
      );

      await tester.tap(find.byKey(const ValueKey('storage-tab-capturas')));
      await tester.pump();
      expect(find.text('captura-taller.png'), findsOneWidget);
      expect(find.text('orden-taller.pdf'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('storage-tab-recientes')));
      await tester.pump();
      expect(find.text('captura-taller.png'), findsOneWidget);
      expect(find.text('orden-taller.pdf'), findsOneWidget);

      final search = find.byKey(const ValueKey('storage-search'));
      await tester.tap(search);
      await tester.enterText(search, 'orden');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(search.hitTestable(), findsOneWidget);
      expect(find.text('orden-taller.pdf'), findsOneWidget);
      expect(find.text('captura-taller.png'), findsNothing);
      expect(tester.takeException(), isNull);
      semanticsHandle.dispose();
    },
  );
}

Future<void> _pumpStorage(
  WidgetTester tester, {
  required Size size,
  required AppFilesLoader filesLoader,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: StorageResponsiveSurface(filesLoader: filesLoader),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

AppFilesLoader _loader(List<int> requestedLimits) {
  final files = _files();
  return ({required String query, required int limit}) async {
    requestedLimits.add(limit);
    final normalizedQuery = query.trim().toLowerCase();
    return files
        .where(
          (file) =>
              normalizedQuery.isEmpty ||
              file.fileName.toLowerCase().contains(normalizedQuery),
        )
        .take(limit)
        .toList(growable: false);
  };
}

List<AppStoredFile> _files() {
  final now = DateTime.utc(2026, 7, 25, 12);
  return [
    AppStoredFile(
      id: 'file-screenshot',
      tenantId: 'tenant-test',
      uploadedBy: 'user-test',
      fileName: 'captura-taller.png',
      storageBucket: 'test-files',
      storagePath: 'tenant-test/captura-taller.png',
      mimeType: 'image/png',
      sizeBytes: 2048,
      sourceType: 'screenshot',
      sourceId: null,
      sourceProvider: 'Captura',
      sourceRoute: null,
      contextType: 'workshop',
      contextId: 'job-2',
      contextTitle: 'PG-00482',
      contextSubtitle: 'Diagnóstico',
      tags: const ['taller'],
      metadata: const {},
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    ),
    AppStoredFile(
      id: 'file-manual',
      tenantId: 'tenant-test',
      uploadedBy: 'user-test',
      fileName: 'orden-taller.pdf',
      storageBucket: 'test-files',
      storagePath: 'tenant-test/orden-taller.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 4096,
      sourceType: 'manual',
      sourceId: null,
      sourceProvider: 'Carga manual',
      sourceRoute: null,
      contextType: 'workshop',
      contextId: 'job-1',
      contextTitle: 'PG-00481',
      contextSubtitle: 'Orden de trabajo',
      tags: const ['taller'],
      metadata: const {},
      createdAt: now.subtract(const Duration(minutes: 5)),
      updatedAt: now.subtract(const Duration(minutes: 5)),
      deletedAt: null,
    ),
  ];
}

void _expectMinimumTouchTarget(
  WidgetTester tester,
  Finder finder, {
  required String reason,
}) {
  expect(finder, findsOneWidget, reason: reason);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48), reason: reason);
  expect(size.height, greaterThanOrEqualTo(48), reason: reason);
}

void _expectInsideViewport(
  WidgetTester tester,
  Finder finder,
  Size viewport,
) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}
