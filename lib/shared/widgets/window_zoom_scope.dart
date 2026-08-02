import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/window_zoom_service.dart';
import '../utils/responsive_breakpoints.dart';

enum ZoomCommand { zoomIn, zoomOut, reset }

class ZoomIntent extends Intent {
  const ZoomIntent(this.command);
  final ZoomCommand command;
}

class WindowZoomScope extends StatelessWidget {
  const WindowZoomScope({super.key, required this.child});

  final Widget child;

  /// Windows uses Ctrl, macOS uses Cmd (meta)
  static Map<ShortcutActivator, Intent> get _shortcuts {
    if (WindowZoomService.isMacOS) {
      // macOS: Cmd+Plus, Cmd+Minus, Cmd+0
      return const {
        SingleActivator(LogicalKeyboardKey.equal, meta: true):
            ZoomIntent(ZoomCommand.zoomIn),
        SingleActivator(LogicalKeyboardKey.add, meta: true):
            ZoomIntent(ZoomCommand.zoomIn),
        SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
            ZoomIntent(ZoomCommand.zoomIn),
        SingleActivator(LogicalKeyboardKey.minus, meta: true):
            ZoomIntent(ZoomCommand.zoomOut),
        SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true):
            ZoomIntent(ZoomCommand.zoomOut),
        SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            ZoomIntent(ZoomCommand.reset),
        SingleActivator(LogicalKeyboardKey.numpad0, meta: true):
            ZoomIntent(ZoomCommand.reset),
      };
    } else {
      // Windows/Linux: Ctrl+Plus, Ctrl+Minus, Ctrl+0
      return const {
        SingleActivator(LogicalKeyboardKey.equal, control: true):
            ZoomIntent(ZoomCommand.zoomIn),
        SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            ZoomIntent(ZoomCommand.zoomIn),
        SingleActivator(LogicalKeyboardKey.minus, control: true):
            ZoomIntent(ZoomCommand.zoomOut),
        SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            ZoomIntent(ZoomCommand.zoomOut),
        SingleActivator(LogicalKeyboardKey.digit0, control: true):
            ZoomIntent(ZoomCommand.reset),
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowZoomService.isSupportedPlatform) {
      return child;
    }

    final zoomService = context.watch<WindowZoomService>();
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: {
            ZoomIntent: CallbackAction<ZoomIntent>(
              onInvoke: (intent) {
                final controller = context.read<WindowZoomService>();
                switch (intent.command) {
                  case ZoomCommand.zoomIn:
                    controller.zoomIn();
                    break;
                  case ZoomCommand.zoomOut:
                    controller.zoomOut();
                    break;
                  case ZoomCommand.reset:
                    controller.reset();
                    break;
                }
                return null;
              },
            ),
          },
          child: _ZoomContent(
            scale: zoomService.scale,
            child: child,
          ),
        ),
      ),
    );
  }
}

class WindowViewportMetrics extends InheritedWidget {
  const WindowViewportMetrics({
    super.key,
    required this.unzoomedViewportSize,
    required this.appliedScale,
    required super.child,
  });

  final Size unzoomedViewportSize;
  final double appliedScale;

  static WindowViewportMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowViewportMetrics>();

  @override
  bool updateShouldNotify(WindowViewportMetrics oldWidget) =>
      unzoomedViewportSize != oldWidget.unzoomedViewportSize ||
      appliedScale != oldWidget.appliedScale;
}

class _ZoomContent extends StatelessWidget {
  const _ZoomContent({required this.scale, required this.child});

  final double scale;
  final Widget child;

  EdgeInsets _toZoomedLogicalInsets(
    EdgeInsets physicalLogicalInsets,
    double appliedScale,
  ) {
    if (appliedScale == 1) return physicalLogicalInsets;
    return EdgeInsets.fromLTRB(
      physicalLogicalInsets.left / appliedScale,
      physicalLogicalInsets.top / appliedScale,
      physicalLogicalInsets.right / appliedScale,
      physicalLogicalInsets.bottom / appliedScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final unzoomedViewportSize = constraints.biggest;
        final appliedScale =
            constraints.maxWidth < ResponsiveBreakpoints.desktopMin
                ? 1.0
                : scale;
        final rootMediaQuery = MediaQuery.of(context);

        // Keep this wrapper topology stable at both sides of 899/900. Swapping
        // the compact branch to [child] directly would recreate the navigator
        // and every stateful scope below it when the window crosses the
        // breakpoint.
        final content = ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.scale(
              scale: appliedScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: constraints.maxWidth / appliedScale,
                height: constraints.maxHeight / appliedScale,
                child: MediaQuery(
                  // The child lives in pre-transform logical coordinates.
                  // View/system insets arrive in viewport coordinates, so
                  // leaving them unchanged would scale a 24px safe boundary
                  // to 19.2px at the default 0.8 desktop zoom. Normalize all
                  // physical inset families here; descendants can keep using
                  // ordinary SafeArea/viewPadding and still land on the real
                  // status bar, keyboard, and system-gesture boundaries.
                  data: rootMediaQuery.copyWith(
                    size: Size(
                      constraints.maxWidth / appliedScale,
                      constraints.maxHeight / appliedScale,
                    ),
                    padding: _toZoomedLogicalInsets(
                      rootMediaQuery.padding,
                      appliedScale,
                    ),
                    viewPadding: _toZoomedLogicalInsets(
                      rootMediaQuery.viewPadding,
                      appliedScale,
                    ),
                    viewInsets: _toZoomedLogicalInsets(
                      rootMediaQuery.viewInsets,
                      appliedScale,
                    ),
                    systemGestureInsets: _toZoomedLogicalInsets(
                      rootMediaQuery.systemGestureInsets,
                      appliedScale,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );

        return WindowViewportMetrics(
          unzoomedViewportSize: unzoomedViewportSize,
          appliedScale: appliedScale,
          child: content,
        );
      },
    );
  }
}
