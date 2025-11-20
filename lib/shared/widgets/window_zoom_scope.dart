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

  static Map<ShortcutActivator, Intent> get _shortcuts => const {
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

    final mediaQuery = MediaQuery.of(context);
    
    // "Safe Zoom": We only scale the text.
    // This keeps the layout bounds intact but makes content readable.
    // Flutter's widgets are designed to handle text scaling gracefully.
    final scaledMedia = mediaQuery.copyWith(
      textScaler: TextScaler.linear(scale),
    );

    return MediaQuery(
      data: scaledMedia,
      child: child,
    );
  }
}
