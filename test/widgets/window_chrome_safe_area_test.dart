import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/services/window_chrome_layout_region_service.dart';
import 'package:vinabike_erp/shared/widgets/window_chrome_layout_region_scope.dart';
import 'package:vinabike_erp/shared/widgets/window_zoom_scope.dart';

Widget _host({
  required EdgeInsets safe,
  required EdgeInsets adapted,
  required Widget child,
  TextDirection direction = TextDirection.ltr,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(200, 300),
          padding: safe,
          viewPadding: safe,
        ),
        child: WindowChromeLayoutRegionScope(
          margins: adapted,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void main() {
  test('stale native geometry fails closed until viewport sizes match', () {
    const snapshot = WindowChromeLayoutSnapshot(
      viewSize: Size(1024, 768),
      margins: EdgeInsets.only(left: 80, right: 40),
      revision: 2,
    );

    expect(
      WindowZoomScope.validatedLayoutRegion(
        snapshot,
        const Size(768, 1024),
      ),
      EdgeInsets.zero,
    );
    expect(
      WindowZoomScope.validatedLayoutRegion(
        snapshot,
        const Size(1024.5, 767.5),
      ),
      snapshot.margins,
    );
  });

  test('zoom normalization preserves the native physical distance', () {
    const physicalMargin = EdgeInsets.only(left: 80, right: 40);
    final logical = WindowZoomScope.toZoomedLogicalInsets(
      physicalMargin,
      0.8,
    );

    expect(logical.left * 0.8, closeTo(physicalMargin.left, 0.001));
    expect(logical.right * 0.8, closeTo(physicalMargin.right, 0.001));
  });

  testWidgets('uses max of safe adapted and design instead of adding them',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 300);
    addTearDown(tester.view.reset);
    const canvasKey = Key('canvas');
    const rowKey = Key('row');
    await tester.pumpWidget(
      _host(
        safe: const EdgeInsets.only(left: 12, right: 18),
        adapted: const EdgeInsets.only(left: 80, right: 40),
        child: SizedBox.expand(
          key: canvasKey,
          child: WindowChromeSafeArea(
            minimumPadding: const EdgeInsets.symmetric(horizontal: 4),
            top: false,
            bottom: false,
            child: Container(key: rowKey),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(canvasKey)).width, 200);
    expect(tester.getTopLeft(find.byKey(rowKey)).dx, 80);
    expect(tester.getSize(find.byKey(rowKey)).width, 80);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested wrappers consume adaptive and safe edges once',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 300);
    addTearDown(tester.view.reset);
    const innerKey = Key('inner');
    await tester.pumpWidget(
      _host(
        safe: const EdgeInsets.only(left: 12),
        adapted: const EdgeInsets.only(left: 80),
        child: WindowChromeSafeArea(
          top: false,
          right: false,
          bottom: false,
          child: WindowChromeSafeArea(
            top: false,
            right: false,
            bottom: false,
            child: Container(key: innerKey),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(innerKey)).dx, 80);
  });

  testWidgets('dynamic and directional design margins do not remount child',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 300);
    addTearDown(tester.view.reset);
    const childKey = Key('stable-child');
    Future<void> pump(double adaptedLeft) => tester.pumpWidget(
          _host(
            safe: EdgeInsets.zero,
            adapted: EdgeInsets.only(left: adaptedLeft),
            direction: TextDirection.rtl,
            child: const WindowChromeSafeArea(
              minimumPadding: EdgeInsetsDirectional.only(start: 16, end: 4),
              top: false,
              bottom: false,
              child: SizedBox(key: childKey, height: 40),
            ),
          ),
        );

    await pump(0);
    final first = tester.element(find.byKey(childKey));
    expect(tester.getTopLeft(find.byKey(childKey)).dx, 4);

    await pump(80);
    expect(tester.element(find.byKey(childKey)), same(first));
    expect(tester.getTopLeft(find.byKey(childKey)).dx, 80);

    await pump(0);
    expect(tester.element(find.byKey(childKey)), same(first));
    expect(tester.getTopLeft(find.byKey(childKey)).dx, 4);
  });
}
