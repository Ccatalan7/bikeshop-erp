import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Debug-only input channel so an agent can drive the app **without touching
/// the owner's cursor**.
///
/// The previous path posted real `CGEvent`s to the window server, which moves
/// the actual pointer and steals focus — so the owner and the agent fought over
/// one mouse, and either could invalidate the other's action mid-gesture.
///
/// These extensions instead hand synthetic [PointerEvent]s straight to
/// [GestureBinding], which is the same thing `WidgetController` does in widget
/// tests. Consequences:
///
/// - the system cursor never moves, so the owner keeps using the Mac normally;
/// - the window does not need focus, or even to be visible;
/// - coordinates are deterministic instead of racing window position;
/// - an installed build can no longer steal the click, because the event is
///   delivered inside this process rather than aimed at a screen coordinate.
///
/// The trade-off is honest: this bypasses the OS event path, so it cannot catch
/// a defect that lives *in* that path (a window that never receives events at
/// all). For that case the CGEvent driver stays available in `app_control.sh`.
///
/// Never registered outside debug: [kDebugMode] gates the whole thing, so no
/// release build exposes an input channel.
void registerAgentInputExtensions() {
  if (!kDebugMode) return;
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.vinabike.input.info', (_, __) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    return _ok({
      'devicePixelRatio': view?.devicePixelRatio,
      'logicalWidth':
          view == null ? null : view.physicalSize.width / view.devicePixelRatio,
      'logicalHeight': view == null
          ? null
          : view.physicalSize.height / view.devicePixelRatio,
      'physicalWidth': view?.physicalSize.width,
      'physicalHeight': view?.physicalSize.height,
    });
  });

  developer.registerExtension('ext.vinabike.input.tap', (_, params) async {
    final at = _offset(params);
    if (at == null) return _err('x and y are required');
    await _tap(at);
    return _ok({
      'tapped': [at.dx, at.dy]
    });
  });

  developer.registerExtension('ext.vinabike.input.scroll', (_, params) async {
    final at = _offset(params);
    if (at == null) return _err('x and y are required');
    final dy = double.tryParse(params['dy'] ?? '') ?? 0;
    final dx = double.tryParse(params['dx'] ?? '') ?? 0;
    _dispatch(PointerScrollEvent(
      position: at,
      scrollDelta: Offset(dx, dy),
      viewId: _viewId,
    ));
    return _ok({
      'scrolled': [dx, dy]
    });
  });

  developer.registerExtension('ext.vinabike.input.drag', (_, params) async {
    final from = _offset(params);
    final toX = double.tryParse(params['x2'] ?? '');
    final toY = double.tryParse(params['y2'] ?? '');
    if (from == null || toX == null || toY == null) {
      return _err('x, y, x2 and y2 are required');
    }
    await _drag(from, Offset(toX, toY),
        steps: int.tryParse(params['steps'] ?? '') ?? 12);
    return _ok({
      'dragged': [from.dx, from.dy, toX, toY]
    });
  });
}

bool _registered = false;
int _pointer = 7000;

int get _viewId =>
    WidgetsBinding.instance.platformDispatcher.implicitView?.viewId ?? 0;

Offset? _offset(Map<String, String> params) {
  final x = double.tryParse(params['x'] ?? '');
  final y = double.tryParse(params['y'] ?? '');
  if (x == null || y == null) return null;
  return Offset(x, y);
}

void _dispatch(PointerEvent event) =>
    GestureBinding.instance.handlePointerEvent(event);

Future<void> _tap(Offset at) async {
  final id = _pointer++;
  // A hover first, so widgets that only arm on enter (menus, hover rows) see
  // the pointer arrive instead of a down event materialising out of nowhere.
  _dispatch(PointerHoverEvent(position: at, viewId: _viewId));
  _dispatch(PointerDownEvent(pointer: id, position: at, viewId: _viewId));
  await Future<void>.delayed(const Duration(milliseconds: 40));
  _dispatch(PointerUpEvent(pointer: id, position: at, viewId: _viewId));
  // Let the tap settle before the caller screenshots it.
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

Future<void> _drag(Offset from, Offset to, {int steps = 12}) async {
  final id = _pointer++;
  _dispatch(PointerDownEvent(pointer: id, position: from, viewId: _viewId));
  var previous = from;
  for (var i = 1; i <= steps; i++) {
    final at = Offset.lerp(from, to, i / steps)!;
    _dispatch(PointerMoveEvent(
      pointer: id,
      position: at,
      delta: at - previous,
      viewId: _viewId,
    ));
    previous = at;
    await Future<void>.delayed(const Duration(milliseconds: 12));
  }
  _dispatch(PointerUpEvent(pointer: id, position: to, viewId: _viewId));
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

developer.ServiceExtensionResponse _ok(Map<String, Object?> body) =>
    developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true, ...body}));

developer.ServiceExtensionResponse _err(String message) =>
    developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      jsonEncode({'ok': false, 'error': message}),
    );
