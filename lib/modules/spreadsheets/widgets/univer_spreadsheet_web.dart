import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('globalThis.vinabikeUniver')
external _UniverBridge? get _univerBridge;

@JS('Promise.resolve')
external JSPromise<JSAny?> _resolvePromise(JSAny? value);

const _univerStylesheetPath = 'spreadsheet_engine/univer.bundle.css';
const _univerScriptPath = 'spreadsheet_engine/univer.bundle.js';
const _univerStylesheetElementId = 'vinabike-univer-bundle-css';
const _univerScriptElementId = 'vinabike-univer-bundle-js';

Future<void>? _univerAssetsLoadFuture;

Future<void> _ensureUniverAssetsLoaded() {
  if (_univerBridge != null) return Future<void>.value();
  final inFlight = _univerAssetsLoadFuture;
  if (inFlight != null) return inFlight;

  final loadFuture = _loadUniverAssets();
  _univerAssetsLoadFuture = loadFuture;
  return loadFuture.whenComplete(() {
    // A transient missing/chunk/network failure must not poison every later
    // view mount with the first failed Future.
    if (_univerBridge == null &&
        identical(_univerAssetsLoadFuture, loadFuture)) {
      _univerAssetsLoadFuture = null;
    }
  });
}

Future<void> _loadUniverAssets() async {
  await Future.wait<void>([
    _loadUniverStylesheet(),
    _loadUniverScript(),
  ]);

  if (_univerBridge == null) {
    throw StateError(
      'Loaded $_univerScriptPath, but the bundle did not define '
      'globalThis.vinabikeUniver. Verify the engine bundle global export.',
    );
  }
}

Future<void> _loadUniverStylesheet() {
  web.document.getElementById(_univerStylesheetElementId)?.remove();

  final link = web.document.createElement('link') as web.HTMLLinkElement;
  link
    ..id = _univerStylesheetElementId
    ..rel = 'stylesheet'
    ..href = _univerStylesheetPath;

  return _appendAssetAndWait(
    element: link,
    missingAssetMessage:
        'Could not load the Univer stylesheet at "${link.href}". '
        'Confirm web/$_univerStylesheetPath is included in the web build.',
  );
}

Future<void> _loadUniverScript() {
  web.document.getElementById(_univerScriptElementId)?.remove();

  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script
    ..id = _univerScriptElementId
    ..src = _univerScriptPath
    ..async = true;

  return _appendAssetAndWait(
    element: script,
    missingAssetMessage: 'Could not load the Univer engine at "${script.src}". '
        'Confirm web/$_univerScriptPath is included in the web build.',
  );
}

Future<void> _appendAssetAndWait({
  required web.HTMLElement element,
  required String missingAssetMessage,
}) {
  final completer = Completer<void>();
  late final web.EventListener loadListener;
  late final web.EventListener errorListener;

  void removeListeners() {
    element.removeEventListener('load', loadListener);
    element.removeEventListener('error', errorListener);
  }

  loadListener = ((web.Event _) {
    removeListeners();
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  errorListener = ((web.Event _) {
    removeListeners();
    if (!completer.isCompleted) {
      completer.completeError(StateError(missingAssetMessage));
    }
  }).toJS;

  element.addEventListener('load', loadListener);
  element.addEventListener('error', errorListener);

  final head = web.document.head;
  if (head == null) {
    removeListeners();
    return Future<void>.error(
      StateError('Could not load Univer because document.head is unavailable.'),
    );
  }
  head.append(element);
  return completer.future;
}

extension type _UniverBridge(JSObject _) implements JSObject {
  external void mount(
    JSString viewId,
    web.HTMLElement element,
    JSString snapshotJson,
  );

  external JSAny? snapshot(JSString viewId);

  external void dispose(JSString viewId);

  external void focus(JSString viewId);
}

extension type _UniverEventDetail(JSObject _) implements JSObject {
  external JSString? get viewId;

  external JSString? get snapshotJson;

  external JSString? get message;
}

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

/// Embeds the preconfigured Univer spreadsheet engine provided by the host
/// page through `globalThis.vinabikeUniver`.
class UniverSpreadsheetView extends StatefulWidget {
  const UniverSpreadsheetView({
    super.key,
    required this.initialSnapshot,
    this.onSnapshotChanged,
    this.onReady,
    this.onError,
    this.controller,
  });

  /// Snapshot passed as JSON to `vinabikeUniver.mount`.
  final Map<String, dynamic> initialSnapshot;

  /// Called for matching `vinabike-univer-changed` browser events.
  final ValueChanged<Map<String, dynamic>>? onSnapshotChanged;

  /// Called for the matching `vinabike-univer-ready` browser event.
  final VoidCallback? onReady;

  /// Called for bridge, event, or snapshot decoding failures.
  final ValueChanged<String>? onError;

  final UniverSpreadsheetController? controller;

  @override
  State<UniverSpreadsheetView> createState() => _UniverSpreadsheetViewState();
}

class _UniverSpreadsheetViewState extends State<UniverSpreadsheetView>
    implements _UniverSpreadsheetControllerDelegate {
  static int _nextViewId = 0;

  late final String _viewId = 'vinabike-univer-${_nextViewId++}';
  late final web.EventListener _readyListener = _handleReady.toJS;
  late final web.EventListener _changedListener = _handleChanged.toJS;
  late final web.EventListener _errorListener = _handleError.toJS;

  web.HTMLDivElement? _hostElement;
  bool _engineMounting = false;
  bool _engineMounted = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _listenForBridgeEvents();

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) {
      final element = web.document.createElement('div') as web.HTMLDivElement;
      element.id = _viewId;
      element.setAttribute('data-vinabike-univer-view-id', _viewId);
      element.style
        ..display = 'block'
        ..position = 'relative'
        ..width = '100%'
        ..height = '100%'
        ..overflow = 'hidden';
      _hostElement = element;
      return element;
    });
  }

  @override
  void didUpdateWidget(covariant UniverSpreadsheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  void _listenForBridgeEvents() {
    web.window.addEventListener('vinabike-univer-ready', _readyListener);
    web.window.addEventListener('vinabike-univer-changed', _changedListener);
    web.window.addEventListener('vinabike-univer-error', _errorListener);
  }

  void _stopListeningForBridgeEvents() {
    web.window.removeEventListener('vinabike-univer-ready', _readyListener);
    web.window.removeEventListener('vinabike-univer-changed', _changedListener);
    web.window.removeEventListener('vinabike-univer-error', _errorListener);
  }

  void _handlePlatformViewCreated(int _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mountEngine();
      }
    });
  }

  Future<void> _mountEngine() async {
    if (_engineMounting || _engineMounted || _disposed) return;
    _engineMounting = true;

    final hostElement = _hostElement;
    if (hostElement == null) {
      _reportError('Could not create the Univer HTML host element.');
      _engineMounting = false;
      return;
    }

    try {
      await _ensureUniverAssetsLoaded();
      if (_disposed) return;

      final bridge = _univerBridge;
      if (bridge == null) {
        throw StateError(
          'The Univer engine assets loaded without exposing '
          'globalThis.vinabikeUniver.',
        );
      }
      bridge.mount(
        _viewId.toJS,
        hostElement,
        jsonEncode(widget.initialSnapshot).toJS,
      );
      _engineMounted = true;
    } catch (error) {
      _reportError('Could not mount the Univer spreadsheet: $error');
    } finally {
      _engineMounting = false;
    }
  }

  @override
  Future<Map<String, dynamic>?> requestSnapshot() async {
    final bridge = _univerBridge;
    if (!_engineMounted || bridge == null) {
      _reportError('The Univer spreadsheet is not mounted.');
      return null;
    }

    try {
      final result = await _resolvePromise(
        bridge.snapshot(_viewId.toJS),
      ).toDart;
      return _decodeSnapshot(result, source: 'snapshot()');
    } catch (error) {
      _reportError('Could not read the Univer snapshot: $error');
      return null;
    }
  }

  @override
  void focus() {
    final bridge = _univerBridge;
    if (!_engineMounted || bridge == null) {
      _reportError('The Univer spreadsheet is not mounted.');
      return;
    }

    try {
      bridge.focus(_viewId.toJS);
    } catch (error) {
      _reportError('Could not focus the Univer spreadsheet: $error');
    }
  }

  void _handleReady(web.Event event) {
    final detail = _detailForThisView(event);
    if (detail == null || _disposed) return;
    widget.onReady?.call();
  }

  void _handleChanged(web.Event event) {
    final detail = _detailForThisView(event);
    if (detail == null || _disposed) return;

    final snapshotJson = detail.snapshotJson?.toDart;
    if (snapshotJson == null) {
      _reportError(
        'vinabike-univer-changed did not include detail.snapshotJson.',
      );
      return;
    }

    try {
      final snapshot = _decodeSnapshotJson(
        snapshotJson,
        source: 'vinabike-univer-changed',
      );
      widget.onSnapshotChanged?.call(snapshot);
    } catch (error) {
      _reportError('Could not decode the changed Univer snapshot: $error');
    }
  }

  void _handleError(web.Event event) {
    final detail = _detailForThisView(event);
    if (detail == null || _disposed) return;
    _reportError(
      detail.message?.toDart ?? 'The Univer spreadsheet reported an error.',
    );
  }

  _UniverEventDetail? _detailForThisView(web.Event event) {
    final detailValue = (event as web.CustomEvent).detail;
    if (detailValue == null || !detailValue.typeofEquals('object')) return null;

    final detail = _UniverEventDetail(detailValue as JSObject);
    return detail.viewId?.toDart == _viewId ? detail : null;
  }

  Map<String, dynamic>? _decodeSnapshot(
    JSAny? value, {
    required String source,
  }) {
    if (value == null) return null;
    if (!value.typeofEquals('string')) {
      throw FormatException('$source returned a non-string snapshot.');
    }
    return _decodeSnapshotJson((value as JSString).toDart, source: source);
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

  void _reportError(String message) {
    if (!_disposed) {
      widget.onError?.call(message);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller?._detach(this);
    _stopListeningForBridgeEvents();

    if (_engineMounted) {
      try {
        _univerBridge?.dispose(_viewId.toJS);
      } catch (_) {
        // The view is already being removed; disposal is best-effort.
      }
    }

    _hostElement = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: ValueKey<String>('univer-spreadsheet-view-$_viewId'),
      viewType: _viewId,
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }
}
