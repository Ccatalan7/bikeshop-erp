import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../../../shared/widgets/main_layout.dart';
import '../models/spreadsheet_model.dart';
import '../services/spreadsheet_service.dart';

class SpreadsheetEditorPage extends StatefulWidget {
  final String spreadsheetId;

  const SpreadsheetEditorPage({super.key, required this.spreadsheetId});

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage> {
  static const int _defaultRows = 100;
  static const int _defaultCols = 26;
  static const Duration _saveDebounce = Duration(milliseconds: 700);

  SpreadsheetModel? _sheet;
  final Map<String, CellData> _cells = <String, CellData>{};
  final Map<String, CellData> _pendingDirtyCells = <String, CellData>{};
  final List<StreamSubscription<dynamic>> _windowsSubscriptions =
      <StreamSubscription<dynamic>>[];

  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  Timer? _saveTimer;
  Timer? _pointerSyncTimer;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasUnsaved = false;
  bool _webViewReady = false;
  bool _sheetLoaded = false;
  String? _platformMessage;
  int? _pendingRowCount;
  int? _pendingColCount;
  String? _pendingName;
  Offset? _pendingPointerOffset;

  bool get _usesFlutterWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get _usesWindowsWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  bool get _supportsEmbeddedEditor =>
      _usesFlutterWebView || _usesWindowsWebView;

  bool get _supportsPointerSync {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeEditor());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _pointerSyncTimer?.cancel();
    for (final subscription in _windowsSubscriptions) {
      subscription.cancel();
    }
    if (_windowsController != null) {
      unawaited(_windowsController!.dispose());
    }
    super.dispose();
  }

  Future<void> _initializeEditor() async {
    await _loadSpreadsheet();
    if (!mounted || _sheet == null) return;

    if (_usesFlutterWebView) {
      _initializeFlutterWebView();
      return;
    }

    if (_usesWindowsWebView) {
      await _initializeWindowsWebView();
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _platformMessage =
            'El editor embebido de planillas no esta disponible en esta plataforma.';
      });
    }
  }

  Future<void> _loadSpreadsheet() async {
    final service = context.read<SpreadsheetService>();

    await service.fetchSpreadsheets();
    SpreadsheetModel? sheet;
    for (final entry in service.spreadsheets) {
      if (entry.id == widget.spreadsheetId) {
        sheet = entry;
        break;
      }
    }

    if (sheet == null) {
      if (mounted) {
        context.go('/tools/spreadsheets');
      }
      return;
    }

    final cellModels = await service.loadCells(widget.spreadsheetId);
    _cells.clear();
    for (final cell in cellModels) {
      final rawValue = cell.rawValue ?? '';
      if (rawValue.isEmpty) continue;
      _cells[_cellKey(cell.row, cell.col)] = CellData(
        rawValue: rawValue,
        displayValue: cell.displayValue ?? rawValue,
        cellType: cell.cellType,
        bold: cell.bold,
        italic: cell.italic,
        textAlign: cell.textAlign,
      );
    }

    if (mounted) {
      setState(() {
        _sheet = sheet;
        _sheetLoaded = true;
      });
    }

    await _maybeBootstrapEditor();
  }

  void _initializeFlutterWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'SpreadsheetBridge',
        onMessageReceived: (message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _platformMessage = null;
            });
          },
          onWebResourceError: (error) {
            debugPrint('Spreadsheet WebView error: ${error.description}');
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..loadHtmlString(_spreadsheetShellHtml);

    setState(() {
      _controller = controller;
    });
  }

  Future<void> _initializeWindowsWebView() async {
    try {
      final runtimeVersion =
          await windows_webview.WebviewController.getWebViewVersion();
      if (!mounted) return;

      if (runtimeVersion == null) {
        setState(() {
          _isLoading = false;
          _platformMessage =
              'Microsoft Edge WebView2 Runtime no esta instalado.';
        });
        return;
      }

      final controller = windows_webview.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.sameWindow,
      );

      _windowsSubscriptions.addAll([
        controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() {
            _isLoading = state == windows_webview.LoadingState.loading;
          });
        }),
        controller.webMessage.listen(_handleBridgeMessage),
        controller.onLoadError.listen((error) {
          debugPrint('Spreadsheet Windows WebView error: $error');
        }),
      ]);

      await controller.loadStringContent(_spreadsheetShellHtml);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _windowsController = controller;
        _platformMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _platformMessage =
            'No se pudo inicializar el editor de planillas: $error';
      });
    }
  }

  String _cellKey(int row, int col) => '$row,$col';

  CellData _cellDataFromRaw(String rawValue) {
    if (rawValue.startsWith('=')) {
      return CellData(
        rawValue: rawValue,
        displayValue: rawValue,
        cellType: 'formula',
      );
    }

    final numericValue = double.tryParse(rawValue.replaceAll(',', '.'));
    if (numericValue != null) {
      return CellData(
        rawValue: rawValue,
        displayValue: rawValue,
        cellType: 'number',
      );
    }

    return CellData(
      rawValue: rawValue,
      displayValue: rawValue,
      cellType: 'text',
    );
  }

  int _effectiveRowCount() {
    int maxRow = (_sheet?.rowCount ?? _defaultRows) - 1;
    for (final key in _cells.keys) {
      final row = int.tryParse(key.split(',').first) ?? 0;
      if (row > maxRow) maxRow = row;
    }
    return (maxRow + 21).clamp(_defaultRows, 5000);
  }

  int _effectiveColCount() {
    int maxCol = (_sheet?.colCount ?? _defaultCols) - 1;
    for (final key in _cells.keys) {
      final parts = key.split(',');
      final col = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      if (col > maxCol) maxCol = col;
    }
    return (maxCol + 6).clamp(_defaultCols, 500);
  }

  Map<String, dynamic> _buildBootstrapPayload() {
    final cells = <Map<String, dynamic>>[];
    for (final entry in _cells.entries) {
      if (entry.value.rawValue.isEmpty) continue;
      final parts = entry.key.split(',');
      cells.add({
        'row': int.tryParse(parts[0]) ?? 0,
        'col': parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        'rawValue': entry.value.rawValue,
      });
    }

    return {
      'name': _sheet?.name ?? 'Planilla sin titulo',
      'rowCount': _effectiveRowCount(),
      'colCount': _effectiveColCount(),
      'cells': cells,
    };
  }

  Future<void> _maybeBootstrapEditor() async {
    if (!_sheetLoaded || !_webViewReady || _sheet == null) return;

    final payload = jsonEncode(_buildBootstrapPayload());
    final script = 'window.bootstrapSpreadsheet($payload);';

    try {
      if (_usesFlutterWebView && _controller != null) {
        await _controller!.runJavaScript(script);
      } else if (_usesWindowsWebView && _windowsController != null) {
        await _windowsController!.executeScript(script);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Spreadsheet bootstrap error: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _platformMessage = 'No se pudo cargar la planilla embebida.';
        });
      }
    }
  }

  void _onEditorHover(PointerHoverEvent event) {
    _syncPointerIfSupported(event.localPosition);
  }

  void _onEditorMove(PointerMoveEvent event) {
    _syncPointerIfSupported(event.localPosition);
  }

  void _onEditorDown(PointerDownEvent event) {
    _syncPointerIfSupported(event.localPosition);
  }

  void _syncPointerIfSupported(Offset position) {
    if (!_supportsPointerSync || !_webViewReady) return;
    _queuePointerSync(position);
  }

  void _queuePointerSync(Offset position) {
    _pendingPointerOffset = position;
    if (_pointerSyncTimer != null) return;

    _pointerSyncTimer = Timer(const Duration(milliseconds: 16), () {
      _pointerSyncTimer = null;
      final pointer = _pendingPointerOffset;
      _pendingPointerOffset = null;
      if (pointer == null) return;
      unawaited(_sendPointerToEmbeddedEditor(pointer));
    });
  }

  Future<void> _sendPointerToEmbeddedEditor(Offset position) async {
    final dx = position.dx.toStringAsFixed(2);
    final dy = position.dy.toStringAsFixed(2);
    final script =
        'window.__setFlutterPointer && window.__setFlutterPointer($dx, $dy);';

    try {
      if (_usesFlutterWebView && _controller != null) {
        await _controller!.runJavaScript(script);
      } else if (_usesWindowsWebView && _windowsController != null) {
        await _windowsController!.executeScript(script);
      }
    } catch (_) {
      // Ignore transient pointer sync failures while the WebView is loading.
    }
  }

  void _handleBridgeMessage(dynamic rawMessage) {
    Map<String, dynamic>? message;
    if (rawMessage is String) {
      try {
        message = jsonDecode(rawMessage) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
    } else if (rawMessage is Map) {
      message = Map<String, dynamic>.from(rawMessage);
    }

    if (message == null) return;

    final type = message['type']?.toString() ?? '';
    switch (type) {
      case 'ready':
        _webViewReady = true;
        unawaited(_maybeBootstrapEditor());
        break;
      case 'change':
        final payload = message['payload'];
        if (payload is Map) {
          _handleSpreadsheetChange(Map<String, dynamic>.from(payload));
        }
        break;
      case 'error':
        final description = message['message']?.toString();
        if (mounted) {
          setState(() {
            _platformMessage = description ?? 'Error cargando la planilla.';
            _isLoading = false;
          });
        }
        break;
    }
  }

  void _handleSpreadsheetChange(Map<String, dynamic> payload) {
    final nextCells = <String, CellData>{};
    final rawCells = payload['cells'];
    if (rawCells is List) {
      for (final entry in rawCells) {
        if (entry is! Map) continue;
        final row = (entry['row'] as num?)?.toInt();
        final col = (entry['col'] as num?)?.toInt();
        final rawValue = entry['rawValue']?.toString() ?? '';
        if (row == null || col == null || rawValue.isEmpty) continue;
        nextCells[_cellKey(row, col)] = _cellDataFromRaw(rawValue);
      }
    }

    final dirty = <String, CellData>{};
    final allKeys = <String>{..._cells.keys, ...nextCells.keys};
    for (final key in allKeys) {
      final previous = _cells[key];
      final next = nextCells[key];

      if (next == null) {
        if (previous != null) {
          dirty[key] = CellData(dirty: true);
        }
        continue;
      }

      if (previous == null ||
          previous.rawValue != next.rawValue ||
          previous.cellType != next.cellType) {
        next.dirty = true;
        dirty[key] = next;
      }
    }

    _cells
      ..clear()
      ..addAll(nextCells);

    _pendingDirtyCells.addAll(dirty);
    _pendingRowCount = (payload['rowCount'] as num?)?.toInt();
    _pendingColCount = (payload['colCount'] as num?)?.toInt();
    _pendingName = payload['name']?.toString();

    if (dirty.isEmpty &&
        _pendingRowCount == (_sheet?.rowCount) &&
        _pendingColCount == (_sheet?.colCount) &&
        _pendingName == (_sheet?.name)) {
      return;
    }

    if (mounted) {
      setState(() {
        _hasUnsaved = true;
      });
    }
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(_saveNow());
    });
  }

  Future<void> _saveNow() async {
    if (_sheet == null) return;

    final dirtySnapshot = Map<String, CellData>.from(_pendingDirtyCells);
    final hasMetadataChanges = _pendingRowCount != null ||
        _pendingColCount != null ||
        (_pendingName != null && _pendingName != _sheet!.name);
    if (dirtySnapshot.isEmpty && !hasMetadataChanges) {
      if (mounted) {
        setState(() {
          _hasUnsaved = false;
          _isSaving = false;
        });
      }
      return;
    }

    _pendingDirtyCells.clear();

    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    final service = context.read<SpreadsheetService>();

    try {
      if (dirtySnapshot.isNotEmpty) {
        await service.saveCells(widget.spreadsheetId, dirtySnapshot);
      }

      if (hasMetadataChanges) {
        await service.updateSpreadsheetMetadata(
          widget.spreadsheetId,
          name: _pendingName != _sheet!.name ? _pendingName : null,
          rowCount: _pendingRowCount,
          colCount: _pendingColCount,
        );
        _sheet = _sheet!.copyWith(
          name: _pendingName ?? _sheet!.name,
          rowCount: _pendingRowCount ?? _sheet!.rowCount,
          colCount: _pendingColCount ?? _sheet!.colCount,
        );
      }

      _pendingRowCount = null;
      _pendingColCount = null;
      _pendingName = null;

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasUnsaved = false;
        });
      }
    } catch (error) {
      debugPrint('Spreadsheet save error: $error');
      _pendingDirtyCells.addAll(dirtySnapshot);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasUnsaved = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la planilla.')),
        );
      }
    }
  }

  Future<void> _renameSheet() async {
    if (_sheet == null) return;

    final controller = TextEditingController(text: _sheet!.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar planilla'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || result == null) return;

    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed == _sheet!.name) return;

    await context
        .read<SpreadsheetService>()
        .renameSpreadsheet(widget.spreadsheetId, trimmed);

    if (!mounted) return;
    setState(() {
      _sheet = _sheet!.copyWith(name: trimmed);
    });

    if (_webViewReady) {
      unawaited(_maybeBootstrapEditor());
    }
  }

  Widget _buildEmbeddedEditor() {
    final editor = () {
      if (_usesFlutterWebView) {
        if (_controller == null) {
          return const SizedBox.shrink();
        }
        return WebViewWidget(controller: _controller!);
      }

      if (_usesWindowsWebView) {
        if (_windowsController == null) {
          return const SizedBox.shrink();
        }
        return windows_webview.Webview(_windowsController!);
      }

      return _buildUnsupportedView();
    }();

    if (_supportsPointerSync) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _onEditorHover,
        onPointerMove: _onEditorMove,
        onPointerDown: _onEditorDown,
        child: editor,
      );
    }

    return editor;
  }

  Widget _buildUnsupportedView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 42),
              const SizedBox(height: 12),
              const Text(
                'Editor no disponible',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _platformMessage ??
                    'Esta plataforma no soporta el editor embebido de planillas.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () {
                      unawaited(_saveNow());
                      context.go('/tools/spreadsheets');
                    },
                    tooltip: 'Volver',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: _renameSheet,
                      child: Text(
                        _sheet?.name ?? 'Planilla sin titulo',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_isSaving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_hasUnsaved)
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 16,
                      color: Colors.orange.shade600,
                    )
                  else
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 16,
                      color: Colors.green.shade600,
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _supportsEmbeddedEditor
                        ? _buildEmbeddedEditor()
                        : _buildUnsupportedView(),
                  ),
                  if (_platformMessage != null && _supportsEmbeddedEditor)
                    Positioned.fill(child: _buildUnsupportedView()),
                  if (_isLoading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _spreadsheetShellHtml = '''
<!DOCTYPE html>
<html lang="es">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Planillas</title>
    <link
      rel="stylesheet"
      href="https://cdn.jsdelivr.net/npm/x-data-spreadsheet@1.1.5/dist/xspreadsheet.css"
    />
    <style>
      *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
      html, body {
        width: 100vw;
        height: 100vh;
        overflow: hidden;
        background: #fff;
      }
      #spreadsheet {
        width: 100vw;
        height: 100vh;
      }
      #status {
        position: absolute;
        top: 0; left: 0; right: 0; bottom: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #334155;
        background: #fff;
        z-index: 9999;
        font-size: 14px;
      }
      #debug-overlay {
        position: fixed;
        bottom: 4px;
        right: 4px;
        background: rgba(0,0,0,0.75);
        color: #0f0;
        font: 11px/1.3 monospace;
        padding: 4px 8px;
        border-radius: 4px;
        z-index: 99999;
        pointer-events: none;
        white-space: pre;
      }
    </style>
  </head>
  <body>
    <div id="status">Cargando editor de planillas...</div>
    <div id="spreadsheet"></div>
    <div id="debug-overlay"></div>

    <script>
      // ──────────────────────────────────────────────────────────
      // FORCE devicePixelRatio = 1 at every level we can reach.
      // On macOS Retina WKWebView, the native DPR is 2.
      // The spreadsheet library scales its canvas by DPR, which
      // causes a coordinate mismatch with CSS-pixel mouse events.
      // ──────────────────────────────────────────────────────────
      (function() {
        var realDpr = window.devicePixelRatio || 1;

        function forceDpr(obj) {
          try {
            Object.defineProperty(obj, 'devicePixelRatio', {
              get: function() { return 1; },
              configurable: true
            });
          } catch(e) {}
        }

        forceDpr(window);
        forceDpr(Window.prototype);

        // Some engines read from screen
        try {
          if (window.screen) {
            forceDpr(window.screen);
          }
        } catch(e) {}

        // Show debug info
        var dbg = document.getElementById('debug-overlay');
        if (dbg) {
          dbg.textContent = 'realDPR=' + realDpr + ' forcedDPR=' + (window.devicePixelRatio);
        }

        // x-data-spreadsheet uses raw MouseEvent.offsetX/offsetY for hit testing.
        // In embedded desktop WebViews those values can be relative to a nested child
        // instead of the spreadsheet overlay, which shifts selection left/up.
        var nativeOffsetX = Object.getOwnPropertyDescriptor(MouseEvent.prototype, 'offsetX');
        var nativeOffsetY = Object.getOwnPropertyDescriptor(MouseEvent.prototype, 'offsetY');
        window.__flutterPointer = { x: null, y: null, ts: 0 };

        window.__setFlutterPointer = function(x, y) {
          window.__flutterPointer = {
            x: Number(x),
            y: Number(y),
            ts: Date.now(),
          };
        };

        function spreadsheetCoordRoot(target) {
          if (target && target.closest) {
            var closestRoot = target.closest('.x-spreadsheet-overlayer') ||
              target.closest('.x-spreadsheet') ||
              target.closest('#spreadsheet');
            if (closestRoot) return closestRoot;
          }

          return document.querySelector('.x-spreadsheet-overlayer') ||
            document.querySelector('.x-spreadsheet') ||
            document.getElementById('spreadsheet');
        }

        function normalizedOffset(event, axis) {
          var root = spreadsheetCoordRoot(event.target);
          if (!root) {
            if (axis === 'x' && nativeOffsetX && nativeOffsetX.get) return nativeOffsetX.get.call(event);
            if (axis === 'y' && nativeOffsetY && nativeOffsetY.get) return nativeOffsetY.get.call(event);
            return axis === 'x' ? event.clientX : event.clientY;
          }

          var rect = root.getBoundingClientRect();
          var flutterPointer = window.__flutterPointer || {};
          var shouldUseFlutterPointer =
            event && typeof event.type === 'string' &&
            (event.type === 'mousedown' ||
              event.type === 'mouseup' ||
              event.type === 'click');
          var hasFreshFlutterPointer =
            Number.isFinite(flutterPointer.x) &&
            Number.isFinite(flutterPointer.y) &&
            typeof flutterPointer.ts === 'number' &&
            Date.now() - flutterPointer.ts < 250;
          var baseX = shouldUseFlutterPointer && hasFreshFlutterPointer
            ? flutterPointer.x
            : event.clientX;
          var baseY = shouldUseFlutterPointer && hasFreshFlutterPointer
            ? flutterPointer.y
            : event.clientY;
          var value = axis === 'x' ? baseX - rect.left : baseY - rect.top;
          return Math.max(0, value);
        }

        try {
          Object.defineProperty(MouseEvent.prototype, 'offsetX', {
            get: function() { return normalizedOffset(this, 'x'); },
            configurable: true
          });
          Object.defineProperty(MouseEvent.prototype, 'offsetY', {
            get: function() { return normalizedOffset(this, 'y'); },
            configurable: true
          });
        } catch (e) {}
      })();
    </script>
    <script src="https://cdn.jsdelivr.net/npm/x-data-spreadsheet@1.1.5/dist/xspreadsheet.js"></script>
    <script>
      (function () {
        let spreadsheet = null;
        let isBootstrapping = false;
        let changeTimer = null;

        // ── Debug click logger ──────────────────────────────
        document.addEventListener('mousedown', function(e) {
          var dbg = document.getElementById('debug-overlay');
          if (dbg) {
            var host = document.getElementById('spreadsheet');
            var rect = host ? host.getBoundingClientRect() : {};
            var target = e.target;
            var coordRoot = target && target.closest
              ? (target.closest('.x-spreadsheet-overlayer') ||
                  target.closest('.x-spreadsheet') ||
                  target.closest('#spreadsheet'))
              : null;
            var rootRect = coordRoot ? coordRoot.getBoundingClientRect() : null;
            dbg.textContent =
              'click: (' + e.clientX + ',' + e.clientY + ')' +
              '  offset: (' + e.offsetX + ',' + e.offsetY + ')' +
              '\\nhost rect: (' + Math.round(rect.left||0) + ',' + Math.round(rect.top||0) +
              ') ' + Math.round(rect.width||0) + 'x' + Math.round(rect.height||0) +
              '\\ncoord root: ' + (coordRoot ? coordRoot.className : 'none') +
              ' @ (' + Math.round(rootRect && rootRect.left || 0) + ',' + Math.round(rootRect && rootRect.top || 0) + ')' +
              '\\nflutter ptr: (' + (window.__flutterPointer && window.__flutterPointer.x) + ',' +
                (window.__flutterPointer && window.__flutterPointer.y) + ') age=' +
                (window.__flutterPointer ? (Date.now() - window.__flutterPointer.ts) : 'na') +
              '\\ndpr(now): ' + window.devicePixelRatio +
              '  inner: ' + window.innerWidth + 'x' + window.innerHeight;
          }
        }, true);

        function sendMessage(message) {
          if (window.SpreadsheetBridge && window.SpreadsheetBridge.postMessage) {
            window.SpreadsheetBridge.postMessage(JSON.stringify(message));
            return;
          }
          if (window.chrome && window.chrome.webview) {
            window.chrome.webview.postMessage(message);
          }
        }

        function showStatus(text) {
          var s = document.getElementById('status');
          if (s) { s.textContent = text; s.style.display = 'flex'; }
        }

        function hideStatus() {
          var s = document.getElementById('status');
          if (s) { s.style.display = 'none'; }
        }

        function flattenSheets(rawData) {
          var sheets = Array.isArray(rawData) ? rawData : [rawData];
          var sheet = sheets[0] || {};
          var rows = sheet.rows || {};
          var cells = [];

          Object.keys(rows).forEach(function(rowKey) {
            if (rowKey === 'len') return;
            var row = rows[rowKey];
            if (!row || !row.cells) return;

            Object.keys(row.cells).forEach(function(colKey) {
              var cell = row.cells[colKey] || {};
              var text = cell.text == null ? '' : String(cell.text);
              if (!text) return;
              cells.push({ row: Number(rowKey), col: Number(colKey), rawValue: text });
            });
          });

          return {
            name: sheet.name || 'Planilla',
            rowCount: (sheet.rows && sheet.rows.len) || 100,
            colCount: (sheet.cols && sheet.cols.len) || 26,
            cells: cells,
          };
        }

        function scheduleEmitChange() {
          if (isBootstrapping || !spreadsheet) return;
          if (changeTimer) window.clearTimeout(changeTimer);

          changeTimer = window.setTimeout(function() {
            try {
              sendMessage({ type: 'change', payload: flattenSheets(spreadsheet.getData()) });
            } catch (error) {
              sendMessage({ type: 'error', message: String(error) });
            }
          }, 120);
        }

        function ensureSpreadsheet() {
          if (!window.x_spreadsheet) {
            showStatus('No se pudo cargar el motor de planillas.');
            sendMessage({ type: 'error', message: 'x-data-spreadsheet no se cargo correctamente.' });
            return;
          }

          spreadsheet = window.x_spreadsheet('#spreadsheet', {
            mode: 'edit',
            showToolbar: true,
            showGrid: true,
            showContextmenu: true,
            showBottomBar: false,
            row: { len: 100, height: 28 },
            col: { len: 26, width: 120, minWidth: 72, indexWidth: 56 },
          }).change(function() {
            scheduleEmitChange();
          });

          window.addEventListener('resize', function() {
            if (spreadsheet && typeof spreadsheet.resize === 'function') {
              spreadsheet.resize();
            }
          });

          hideStatus();
          sendMessage({ type: 'ready' });
        }

        window.bootstrapSpreadsheet = function (payload) {
          if (!spreadsheet) return;

          var data = typeof payload === 'string' ? JSON.parse(payload) : payload;
          var rows = { len: data.rowCount || 100 };
          var cols = { len: data.colCount || 26 };
          var sourceCells = Array.isArray(data.cells) ? data.cells : [];

          sourceCells.forEach(function(entry) {
            var rowIndex = Number(entry.row);
            var colIndex = Number(entry.col);
            var rawValue = entry.rawValue == null ? '' : String(entry.rawValue);
            if (!rawValue) return;

            var rowKey = String(rowIndex);
            var colKey = String(colIndex);
            rows[rowKey] = rows[rowKey] || { cells: {} };
            rows[rowKey].cells = rows[rowKey].cells || {};
            rows[rowKey].cells[colKey] = { text: rawValue };
          });

          isBootstrapping = true;
          spreadsheet.loadData([{ name: data.name || 'Planilla', rows: rows, cols: cols }]);
          window.setTimeout(function() {
            isBootstrapping = false;
            if (spreadsheet && typeof spreadsheet.resize === 'function') {
              spreadsheet.resize();
            }
            hideStatus();
          }, 0);
        };

        window.addEventListener('load', ensureSpreadsheet);
      })();
    </script>
  </body>
</html>
''';
