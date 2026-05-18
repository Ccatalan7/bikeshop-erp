import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/window_zoom_service.dart';

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

class _ZoomContent extends StatelessWidget {
  const _ZoomContent({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowZoomService.isSupportedPlatform || scale == 1.0) {
      return child;
    }

    // Browser-style zoom: Scale the entire UI uniformly
    // We use FittedBox with a scaled child to achieve true zoom behavior
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the scaled dimensions
        final scaledWidth = constraints.maxWidth / scale;
        final scaledHeight = constraints.maxHeight / scale;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: scaledWidth,
                height: scaledHeight,
                child: MediaQuery(
                  // Also adjust media query so widgets know the "logical" size
                  data: MediaQuery.of(context).copyWith(
                    size: Size(scaledWidth, scaledHeight),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
