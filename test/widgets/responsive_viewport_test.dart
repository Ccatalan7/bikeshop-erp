import 'package:vinabike_erp/shared/services/window_zoom_service.dart';
import 'package:vinabike_erp/shared/utils/responsive_viewport.dart';
import 'package:vinabike_erp/shared/widgets/window_zoom_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'compact keeps unzoomed scale while desktop preserves the zoom preference',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, left: 8);
      tester.view.viewPadding = const FakeViewPadding(top: 24, left: 8);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.view.systemGestureInsets = const FakeViewPadding(bottom: 16);
      addTearDown(tester.view.reset);

      for (final viewportWidth in <double>[384, 599, 600, 899, 900, 1440]) {
        final zoomService = WindowZoomService();
        double? recoveredWidth;
        double? logicalMediaQueryWidth;
        double? appliedScale;
        bool? compact;
        EdgeInsets? logicalPadding;
        EdgeInsets? logicalViewPadding;
        EdgeInsets? logicalViewInsets;
        EdgeInsets? logicalGestureInsets;

        tester.view.physicalSize = Size(viewportWidth, 824);
        await tester.pumpWidget(
          ChangeNotifierProvider<WindowZoomService>.value(
            value: zoomService,
            child: MaterialApp(
              builder: (context, child) => WindowZoomScope(
                child: child ?? const SizedBox.shrink(),
              ),
              home: Builder(
                builder: (context) {
                  recoveredWidth = ResponsiveViewport.widthOf(context);
                  logicalMediaQueryWidth = MediaQuery.sizeOf(context).width;
                  appliedScale =
                      WindowViewportMetrics.maybeOf(context)?.appliedScale;
                  compact = ResponsiveViewport.usesCompactShell(context);
                  final media = MediaQuery.of(context);
                  logicalPadding = media.padding;
                  logicalViewPadding = media.viewPadding;
                  logicalViewInsets = media.viewInsets;
                  logicalGestureInsets = media.systemGestureInsets;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pump();

        final expectedScale = viewportWidth < ResponsiveViewport.desktopMin
            ? 1.0
            : zoomService.scale;
        expect(recoveredWidth, closeTo(viewportWidth, 0.001));
        expect(appliedScale, expectedScale);
        expect(
          logicalMediaQueryWidth,
          closeTo(viewportWidth / expectedScale, 0.001),
        );
        expect(
          compact,
          viewportWidth < ResponsiveViewport.desktopMin,
          reason: 'viewport width $viewportWidth must keep its composition',
        );
        expect(logicalPadding!.top * expectedScale, closeTo(24, 0.001));
        expect(logicalPadding!.left * expectedScale, closeTo(8, 0.001));
        expect(logicalViewPadding!.top * expectedScale, closeTo(24, 0.001));
        expect(logicalViewInsets!.bottom * expectedScale, closeTo(280, 0.001));
        expect(
            logicalGestureInsets!.bottom * expectedScale, closeTo(16, 0.001));

        await tester.pumpWidget(const SizedBox.shrink());
        zoomService.dispose();
      }
    },
  );

  testWidgets(
    'high-density phone panel still classifies its 384 logical pixels',
    (tester) async {
      tester.view.devicePixelRatio = 3.75;
      tester.view.physicalSize = const Size(1440, 3090);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final zoomService = WindowZoomService();
      addTearDown(zoomService.dispose);
      double? viewportWidth;
      double? appliedScale;
      bool? compact;

      await tester.pumpWidget(
        ChangeNotifierProvider<WindowZoomService>.value(
          value: zoomService,
          child: MaterialApp(
            builder: (context, child) => WindowZoomScope(
              child: child ?? const SizedBox.shrink(),
            ),
            home: Builder(
              builder: (context) {
                viewportWidth = ResponsiveViewport.widthOf(context);
                appliedScale =
                    WindowViewportMetrics.maybeOf(context)?.appliedScale;
                compact = ResponsiveViewport.usesCompactShell(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(viewportWidth, 384);
      expect(appliedScale, 1);
      expect(compact, isTrue);
    },
  );

  testWidgets(
    'crossing 899 and 900 keeps the zoom subtree mounted',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(899, 824);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final zoomService = WindowZoomService();
      addTearDown(zoomService.dispose);
      var mountCount = 0;
      var disposeCount = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<WindowZoomService>.value(
          value: zoomService,
          child: MaterialApp(
            builder: (context, child) => WindowZoomScope(
              child: child ?? const SizedBox.shrink(),
            ),
            home: _LifecycleProbe(
              onMount: () => mountCount += 1,
              onDispose: () => disposeCount += 1,
            ),
          ),
        ),
      );
      expect(mountCount, 1);
      expect(disposeCount, 0);

      tester.view.physicalSize = const Size(900, 824);
      await tester.pump();
      expect(mountCount, 1);
      expect(disposeCount, 0);

      tester.view.physicalSize = const Size(899, 824);
      await tester.pump();
      expect(mountCount, 1);
      expect(disposeCount, 0);
    },
  );
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({
    required this.onMount,
    required this.onDispose,
  });

  final VoidCallback onMount;
  final VoidCallback onDispose;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
