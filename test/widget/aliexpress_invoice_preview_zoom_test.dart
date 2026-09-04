import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:vinabike_erp/shared/widgets/webview_module_page.dart';

/// The owner could see the invoice preview but not enlarge it (2026-09-04).
/// The fix is only proven by mounting the preview and tapping a page: a source
/// assertion proves the code was typed, not that the gesture reaches anything.
void main() {
  // A 1x1 PNG: the test is about the gesture and the route, not the raster.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==',
  );

  List<PdfPreviewPageData> pages(int count) => <PdfPreviewPageData>[
        for (var index = 0; index < count; index++)
          PdfPreviewPageData(
            image: MemoryImage(pixel),
            width: 816,
            height: 1056,
          ),
      ];

  Widget host(int pageCount) => MaterialApp(
        home: Scaffold(body: InvoicePreviewPages(pages: pages(pageCount))),
      );

  /// A letter page keeps its aspect ratio, so two of them need a tall
  /// surface; on the default 800x600 the second one is never built and the
  /// test would be asserting the ListView's laziness, not the preview.
  Future<void> pumpPreview(WidgetTester tester, int pageCount) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(pageCount));
  }

  testWidgets('every page is announced as its own button to enlarge',
      (tester) async {
    await pumpPreview(tester, 2);

    expect(find.bySemanticsLabel('Ampliar página 1 de 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Ampliar página 2 de 2'), findsOneWidget);
  });

  testWidgets('a single tap opens the zoom over that page', (tester) async {
    await pumpPreview(tester, 3);

    expect(find.byType(InteractiveViewer), findsNothing);

    await tester.tap(find.bySemanticsLabel('Ampliar página 2 de 3'));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Página 2 de 3'), findsOneWidget,
        reason: 'the zoom says which sheet is open');

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.maxScale, greaterThan(1),
        reason: 'the whole point is that it enlarges');
    expect(viewer.minScale, lessThanOrEqualTo(1));
  });

  testWidgets('the zoom closes and returns to the preview', (tester) async {
    await pumpPreview(tester, 1);

    await tester.tap(find.bySemanticsLabel('Ampliar página 1 de 1'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.bySemanticsLabel('Ampliar página 1 de 1'), findsOneWidget);
  });
}
