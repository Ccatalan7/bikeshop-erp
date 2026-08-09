import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/public_store/widgets/website_header_overlay_boundary.dart';

void main() {
  testWidgets(
      'sticky conserva el inset cuando cambia sólo su apariencia al hacer scroll',
      (tester) async {
    final boundary = ValueNotifier<WebsiteHeaderOverlayGeometry>(
      const WebsiteHeaderOverlayGeometry(),
    );
    addTearDown(boundary.dispose);
    late StateSetter updateHeader;
    var visualOverlay = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: WebsiteHeaderOverlayBoundary(
            boundary: boundary,
            child: StatefulBuilder(
              builder: (context, setState) {
                updateHeader = setState;
                return WebsiteMeasuredOverlayHeader(
                  overlaysDocument: true,
                  visualOverlay: visualOverlay,
                  child: const SizedBox(height: 64),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(boundary.value.overlaysDocument, isTrue);
    expect(boundary.value.visualOverlay, isTrue);
    expect(boundary.value.height, 64);
    expect(boundary.value.documentInset, 64);

    updateHeader(() => visualOverlay = false);
    await tester.pump();
    await tester.pump();

    expect(boundary.value.overlaysDocument, isTrue);
    expect(boundary.value.visualOverlay, isFalse);
    expect(boundary.value.documentInset, 64);
  });

  testWidgets('inline mide el header pero nunca crea un spacer de editor',
      (tester) async {
    final boundary = ValueNotifier<WebsiteHeaderOverlayGeometry>(
      const WebsiteHeaderOverlayGeometry(),
    );
    addTearDown(boundary.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: WebsiteHeaderOverlayBoundary(
            boundary: boundary,
            child: const WebsiteMeasuredOverlayHeader(
              overlaysDocument: false,
              visualOverlay: false,
              child: SizedBox(height: 88),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(boundary.value.height, 88);
    expect(boundary.value.overlaysDocument, isFalse);
    expect(boundary.value.documentInset, 0);
  });

  testWidgets('un banner que cambia de alto vuelve a publicar la medida real',
      (tester) async {
    final boundary = ValueNotifier<WebsiteHeaderOverlayGeometry>(
      const WebsiteHeaderOverlayGeometry(),
    );
    addTearDown(boundary.dispose);
    late StateSetter resizeHeader;
    var headerHeight = 64.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: WebsiteHeaderOverlayBoundary(
            boundary: boundary,
            child: StatefulBuilder(
              builder: (context, setState) {
                resizeHeader = setState;
                return WebsiteMeasuredOverlayHeader(
                  overlaysDocument: true,
                  visualOverlay: true,
                  child: SizedBox(height: headerHeight),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(boundary.value.documentInset, 64);

    resizeHeader(() => headerHeight = 96);
    await tester.pump();
    await tester.pump();

    expect(boundary.value.height, 96);
    expect(boundary.value.documentInset, 96);
  });
}
