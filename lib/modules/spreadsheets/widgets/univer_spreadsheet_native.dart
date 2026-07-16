import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/window_zoom_service.dart';

const _hostAssetPath = 'web/spreadsheet_engine/univer_desktop_host.html';
const _bridgeHandlerName = 'vinabikeUniverEvent';

abstract interface class _UniverSpreadsheetControllerDelegate {
  Future<Map<String, dynamic>?> requestSnapshot();

  void focus();
}

/// Imperative access to a mounted [UniverSpreadsheetView].
class UniverSpreadsheetController {
  _UniverSpreadsheetControllerDelegate? _delegate;

  /// Requests and decodes the current Univer workbook snapshot.
  ///
  /// Returns `null` when no view is attached or the JavaScript bridge reports
  /// an error.
  Future<Map<String, dynamic>?> requestSnapshot() {
    return _delegate?.requestSnapshot() ??
        Future<Map<String, dynamic>?>.value();
  }

  /// Gives keyboard focus to the mounted Univer workbook.
  void focus() => _delegate?.focus();

  void _attach(_UniverSpreadsheetControllerDelegate delegate) {
    _delegate = delegate;
  }

  void _detach(_UniverSpreadsheetControllerDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }
}

/// Embeds the packaged Univer engine in a native WKWebView/WebView2 surface.
///
/// macOS is the primary desktop target. Windows, iOS, and Android use the same
/// bridge when their native WebView implementation is available.
class UniverSpreadsheetView extends StatefulWidget {
  const UniverSpreadsheetView({
    super.key,
    required this.initialSnapshot,
    this.onSnapshotChanged,
    this.onReady,
    this.onError,
    this.controller,
  });

  final Map<String, dynamic> initialSnapshot;
  final ValueChanged<Map<String, dynamic>>? onSnapshotChanged;
  final VoidCallback? onReady;
  final ValueChanged<String>? onError;
  final UniverSpreadsheetController? controller;

  @override
  State<UniverSpreadsheetView> createState() => _UniverSpreadsheetViewState();
}

class _UniverSpreadsheetViewState extends State<UniverSpreadsheetView>
    implements _UniverSpreadsheetControllerDelegate {
  static int _nextViewId = 0;

  late final String _viewId = 'vinabike-univer-native-${_nextViewId++}';

  InAppWebViewController? _webViewController;
  double? _lastAppliedBrowserZoom;
  double? _pendingBrowserZoom;
  double _currentBrowserZoom = 1.0;
  bool _engineMounting = false;
  bool _engineMounted = false;
  bool _reportedReady = false;
  bool _disposed = false;
  bool _reportedUnsupported = false;

  bool get _supportsNativeWebView {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);

    if (!_supportsNativeWebView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportUnsupported();
      });
    }
  }

  @override
  void didUpdateWidget(covariant UniverSpreadsheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  double _browserZoom(BuildContext context) {
    if (!WindowZoomService.isDesktop) return 1.0;
    try {
      final scale = context.watch<WindowZoomService>().scale;
      return scale.clamp(0.5, 3.0).toDouble();
    } on ProviderNotFoundException {
      return 1.0;
    }
  }

  InAppWebViewSettings _browserSettings(double browserZoom) {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      isInspectable: kDebugMode,
      needInitialFocus: true,
      initialScale: (browserZoom * 100).round(),
      pageZoom: browserZoom,
      textZoom: (browserZoom * 100).round(),
      transparentBackground: false,
      horizontalScrollBarEnabled: false,
      verticalScrollBarEnabled: false,
      disableHorizontalScroll: true,
      disableVerticalScroll: true,
      useWideViewPort: true,
    );
  }

  void _scheduleBrowserZoom(double browserZoom) {
    if (_webViewController == null) return;
    if (_pendingBrowserZoom != null &&
        (_pendingBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }
    if (_lastAppliedBrowserZoom != null &&
        (_lastAppliedBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }

    _pendingBrowserZoom = browserZoom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingBrowserZoom;
      _pendingBrowserZoom = null;
      if (pending != null) {
        unawaited(_applyBrowserZoom(pending));
      }
    });
  }

  Future<void> _applyBrowserZoom(double browserZoom) async {
    final controller = _webViewController;
    if (controller == null || _disposed) return;
    if (_lastAppliedBrowserZoom != null &&
        (_lastAppliedBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }

    final previousZoom = _lastAppliedBrowserZoom ?? 1.0;
    try {
      final settings =
          await controller.getSettings() ?? _browserSettings(browserZoom);
      settings
        ..initialScale = (browserZoom * 100).round()
        ..pageZoom = browserZoom
        ..textZoom = (browserZoom * 100).round();
      await controller.setSettings(settings: settings);

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final relativeZoom = browserZoom / previousZoom;
        if (relativeZoom.isFinite && (relativeZoom - 1.0).abs() > 0.001) {
          await controller.zoomBy(zoomFactor: relativeZoom);
        }
      }

      _lastAppliedBrowserZoom = browserZoom;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spreadsheet WebView zoom sync skipped: $error');
      }
    }
  }

  void _handleWebViewCreated(InAppWebViewController controller) {
    if (!identical(_webViewController, controller)) {
      // A native platform view can be recreated when its Flutter layout is
      // reparented (for example, while crossing the 100% app-zoom boundary).
      // The new page must mount its own Univer instance instead of inheriting
      // the disposed WebView's mounted flag.
      _engineMounting = false;
      _engineMounted = false;
      _reportedReady = false;
      _lastAppliedBrowserZoom = null;
    }
    _webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: _bridgeHandlerName,
      callback: _handleBridgeEvent,
    );
  }

  Future<dynamic> _handleBridgeEvent(List<dynamic> arguments) async {
    if (_disposed || arguments.isEmpty) return null;

    final rawPayload = arguments.first;
    Map<String, dynamic> payload;
    if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else if (rawPayload is String) {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
            'The native Univer event is not an object.');
      }
      payload = decoded;
    } else {
      _reportError('The native Univer event payload is invalid.');
      return null;
    }

    final type = payload['type'] as String?;
    final eventViewId = payload['viewId'] as String?;
    final isHostError = type == 'vinabike-univer-host-error';
    if (!isHostError && eventViewId != _viewId) return null;

    switch (type) {
      case 'vinabike-univer-ready':
        _engineMounted = true;
        if (!_reportedReady) {
          _reportedReady = true;
          widget.onReady?.call();
          final controller = _webViewController;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                controller != null &&
                identical(_webViewController, controller)) {
              // Prime Univer's layout/input focus once after rendering. Without
              // this, WKWebView can select the first inserted character while
              // activating its editor, causing the second character to replace
              // it on the first edit after mount.
              unawaited(_focusEngine(controller));
            }
          });
        }
        return null;
      case 'vinabike-univer-changed':
        final snapshotJson = payload['snapshotJson'] as String?;
        if (snapshotJson == null) {
          _reportError(
            'vinabike-univer-changed did not include snapshotJson.',
          );
          return null;
        }
        try {
          widget.onSnapshotChanged?.call(
            _decodeSnapshotJson(
              snapshotJson,
              source: 'vinabike-univer-changed',
            ),
          );
        } catch (error) {
          _reportError('Could not decode the changed Univer snapshot: $error');
        }
        return null;
      case 'vinabike-univer-error':
      case 'vinabike-univer-host-error':
        _reportError(
          payload['message'] as String? ??
              'The native Univer spreadsheet reported an error.',
        );
        return null;
    }
    return null;
  }

  Future<void> _handleLoadStop(
    InAppWebViewController controller,
    WebUri? _,
  ) async {
    await _applyBrowserZoom(_currentBrowserZoom);
    await _mountEngine(controller);
  }

  Future<void> _mountEngine(InAppWebViewController controller) async {
    if (_engineMounting || _engineMounted || _disposed) return;
    _engineMounting = true;

    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          const bridge = globalThis.vinabikeUniver;
          const root = document.getElementById('vinabike-univer-root');
          if (!bridge) {
            throw new Error('The packaged Univer bundle did not load.');
          }
          if (!root) {
            throw new Error('The native Univer host element is missing.');
          }
          bridge.mount(viewId, root, snapshotJson);
          return true;
        ''',
        arguments: <String, dynamic>{
          'viewId': _viewId,
          'snapshotJson': jsonEncode(widget.initialSnapshot),
        },
      );
      _throwForJavaScriptFailure(result, action: 'mount Univer');
      _engineMounted = true;
    } catch (error) {
      _reportError('Could not mount the native Univer spreadsheet: $error');
    } finally {
      _engineMounting = false;
    }
  }

  @override
  Future<Map<String, dynamic>?> requestSnapshot() async {
    final controller = _webViewController;
    if (!_engineMounted || controller == null) {
      _reportError('The native Univer spreadsheet is not mounted.');
      return null;
    }

    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          return await Promise.resolve(
            globalThis.vinabikeUniver.snapshot(viewId)
          );
        ''',
        arguments: <String, dynamic>{'viewId': _viewId},
      );
      _throwForJavaScriptFailure(result, action: 'read the Univer snapshot');

      final snapshotJson = result?.value;
      if (snapshotJson is! String) {
        throw const FormatException('snapshot() returned a non-string value.');
      }
      return _decodeSnapshotJson(snapshotJson, source: 'snapshot()');
    } catch (error) {
      _reportError('Could not read the native Univer snapshot: $error');
      return null;
    }
  }

  @override
  void focus() {
    final controller = _webViewController;
    if (!_engineMounted || controller == null) {
      _reportError('The native Univer spreadsheet is not mounted.');
      return;
    }
    unawaited(_focusEngine(controller));
  }

  Future<void> _focusEngine(InAppWebViewController controller) async {
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          globalThis.vinabikeUniver.focus(viewId);
          return true;
        ''',
        arguments: <String, dynamic>{'viewId': _viewId},
      );
      _throwForJavaScriptFailure(result, action: 'focus Univer');
    } catch (error) {
      _reportError('Could not focus the native Univer spreadsheet: $error');
    }
  }

  Map<String, dynamic> _decodeSnapshotJson(
    String snapshotJson, {
    required String source,
  }) {
    final decoded = jsonDecode(snapshotJson);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$source must contain a JSON object.');
    }
    return decoded;
  }

  void _throwForJavaScriptFailure(
    CallAsyncJavaScriptResult? result, {
    required String action,
  }) {
    if (result == null) {
      throw StateError('WKWebView returned no result while trying to $action.');
    }
    if (result.error != null) {
      throw StateError(result.error!);
    }
  }

  void _reportUnsupported() {
    if (_reportedUnsupported) return;
    _reportedUnsupported = true;
    widget.onError?.call(
      'The packaged spreadsheet engine does not have a native WebView host '
      'for ${defaultTargetPlatform.name}.',
    );
  }

  void _reportError(String message) {
    if (!_disposed) widget.onError?.call(message);
  }

  Future<void> _disposeEngine(InAppWebViewController controller) async {
    try {
      await controller.callAsyncJavaScript(
        functionBody: '''
          globalThis.vinabikeUniver?.dispose(viewId);
          return true;
        ''',
        arguments: <String, dynamic>{'viewId': _viewId},
      );
    } catch (_) {
      // The native platform view may already be tearing down.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller?._detach(this);
    final controller = _webViewController;
    if (_engineMounted && controller != null) {
      unawaited(_disposeEngine(controller));
    }
    _webViewController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsNativeWebView) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'The packaged spreadsheet engine is unavailable on '
            '${defaultTargetPlatform.name}.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final browserZoom = _browserZoom(context);
    _currentBrowserZoom = browserZoom;
    _scheduleBrowserZoom(browserZoom);

    return _NativeSpreadsheetZoomBoundary(
      appScale: browserZoom,
      child: InAppWebView(
        key: ValueKey<String>('univer-spreadsheet-view-$_viewId'),
        initialFile: _hostAssetPath,
        initialSettings: _browserSettings(browserZoom),
        onWebViewCreated: (controller) {
          _handleWebViewCreated(controller);
          unawaited(_applyBrowserZoom(browserZoom));
        },
        onLoadStop: _handleLoadStop,
      ),
    );
  }
}

/// Native platform views do not inherit the app-level desktop transform.
/// Lay the WebView out in the scaled coordinate space, then compensate so
/// Flutter hit testing and the WKWebView's pixels continue to line up.
class _NativeSpreadsheetZoomBoundary extends StatelessWidget {
  const _NativeSpreadsheetZoomBoundary({
    required this.appScale,
    required this.child,
  });

  final double appScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowZoomService.isDesktop) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }

        final nativeWidth = constraints.maxWidth * appScale;
        final nativeHeight = constraints.maxHeight * appScale;

        return ClipRect(
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 1 / appScale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: nativeWidth,
                  height: nativeHeight,
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
