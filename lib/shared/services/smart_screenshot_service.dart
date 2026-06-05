import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';
import 'workspace_manager.dart';

enum SmartScreenshotMode {
  visibleApp,
  selectedArea,
  browserPage,
}

class BrowserScreenshotContext {
  final Future<Uint8List?> Function() capturePng;
  final String? Function() currentUrl;
  final String? Function() pageTitle;
  final Rect? Function() viewportGlobalRect;

  const BrowserScreenshotContext({
    required this.capturePng,
    required this.currentUrl,
    required this.pageTitle,
    required this.viewportGlobalRect,
  });
}

class SmartScreenshotService extends ChangeNotifier {
  final GlobalKey captureBoundaryKey = GlobalKey(debugLabel: 'app screenshot');
  final Map<String, BrowserScreenshotContext> _browserContexts = {};

  void registerBrowserContext(
    String workspaceId,
    BrowserScreenshotContext context,
  ) {
    _browserContexts[workspaceId] = context;
  }

  void unregisterBrowserContext(String workspaceId) {
    _browserContexts.remove(workspaceId);
  }

  bool hasBrowserContext(Workspace? workspace) {
    final id = workspace?.id;
    return id != null && _browserContexts.containsKey(id);
  }

  Future<AppStoredFile> captureVisibleApp({
    required Workspace? workspace,
  }) async {
    final bytes = await _captureBoundaryPng();
    return _saveScreenshot(
      bytes: bytes,
      workspace: workspace,
      mode: SmartScreenshotMode.visibleApp,
    );
  }

  Future<AppStoredFile> captureSelectedArea({
    required BuildContext context,
    required Workspace? workspace,
  }) async {
    final selection = await Navigator.of(context, rootNavigator: true)
        .push<Rect>(_ScreenshotSelectionRoute());
    if (selection == null) {
      throw const SmartScreenshotCancelledException();
    }

    await Future<void>.delayed(const Duration(milliseconds: 160));
    await WidgetsBinding.instance.endOfFrame;
    final browserBytes = await _captureBrowserAreaPng(workspace, selection);
    final bytes =
        browserBytes ?? await _captureBoundaryPng(globalCropRect: selection);
    return _saveScreenshot(
      bytes: bytes,
      workspace: workspace,
      mode: SmartScreenshotMode.selectedArea,
      selectedGlobalRect: selection,
    );
  }

  Future<AppStoredFile> captureBrowserPage({
    required Workspace? workspace,
  }) async {
    final browser = _browserContextFor(workspace);
    if (browser == null) {
      throw StateError('No hay navegador activo para capturar.');
    }
    final bytes = await browser.capturePng();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('No se pudo capturar la pagina del navegador.');
    }
    return _saveScreenshot(
      bytes: bytes,
      workspace: workspace,
      mode: SmartScreenshotMode.browserPage,
    );
  }

  Future<Uint8List> _captureBoundaryPng({Rect? globalCropRect}) async {
    final context = captureBoundaryKey.currentContext;
    final boundary = context?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('No se encontro la superficie de captura.');
    }

    await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(
      pixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('La captura no produjo imagen.');
    }

    if (globalCropRect == null) return bytes;

    final topLeft = boundary.globalToLocal(globalCropRect.topLeft);
    final bottomRight = boundary.globalToLocal(globalCropRect.bottomRight);
    final localRect = Rect.fromPoints(topLeft, bottomRight).intersect(
      Offset.zero & boundary.size,
    );
    return _cropPngBytes(bytes, localRect, boundary.size);
  }

  Future<Uint8List?> _captureBrowserAreaPng(
    Workspace? workspace,
    Rect globalSelection,
  ) async {
    final browser = _browserContextFor(workspace);
    final viewportRect = browser?.viewportGlobalRect();
    if (browser == null ||
        viewportRect == null ||
        !viewportRect.overlaps(globalSelection)) {
      return null;
    }

    final intersection = viewportRect.intersect(globalSelection);
    final selectedArea = globalSelection.width * globalSelection.height;
    final browserArea = intersection.width * intersection.height;
    if (selectedArea <= 0 || browserArea / selectedArea < 0.72) {
      return null;
    }

    final bytes = await browser.capturePng();
    if (bytes == null || bytes.isEmpty) return null;

    final localRect = Rect.fromLTWH(
      intersection.left - viewportRect.left,
      intersection.top - viewportRect.top,
      intersection.width,
      intersection.height,
    );
    return _cropPngBytes(bytes, localRect, viewportRect.size);
  }

  Future<Uint8List> _cropPngBytes(
    Uint8List bytes,
    Rect logicalRect,
    Size logicalSourceSize,
  ) async {
    final decoded = img.decodePng(bytes);
    if (decoded == null) return bytes;

    final scaleX = decoded.width / logicalSourceSize.width;
    final scaleY = decoded.height / logicalSourceSize.height;
    final x = (logicalRect.left * scaleX).round().clamp(0, decoded.width - 1);
    final y = (logicalRect.top * scaleY).round().clamp(0, decoded.height - 1);
    final right =
        (logicalRect.right * scaleX).round().clamp(x + 1, decoded.width);
    final bottom =
        (logicalRect.bottom * scaleY).round().clamp(y + 1, decoded.height);

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: right - x,
      height: bottom - y,
    );
    return Uint8List.fromList(img.encodePng(cropped));
  }

  Future<AppStoredFile> _saveScreenshot({
    required Uint8List bytes,
    required Workspace? workspace,
    required SmartScreenshotMode mode,
    Rect? selectedGlobalRect,
  }) async {
    final now = DateTime.now();
    final route = workspace?.currentRoute;
    final browser = _browserContextFor(workspace);
    final browserUrl =
        _browserUrlFromContext(browser) ?? _browserUrlFromRoute(route);
    final browserUri = browserUrl == null ? null : Uri.tryParse(browserUrl);
    final title = _browserTitleFromContext(browser) ??
        workspace?.title.trim() ??
        browserUri?.host ??
        'Captura';
    final supplierMatch = browserUrl == null
        ? null
        : await AppFileStorageService.instance.matchSupplierForUrl(browserUrl);
    final modeLabel = switch (mode) {
      SmartScreenshotMode.visibleApp => 'visible',
      SmartScreenshotMode.selectedArea => 'seleccion',
      SmartScreenshotMode.browserPage => 'navegador',
    };

    return AppFileStorageService.instance.saveFile(
      bytes: bytes,
      fileName: 'captura-$modeLabel-${_dateStamp(now)}-${_timeStamp(now)}.png',
      mimeType: 'image/png',
      context: AppFileContext(
        sourceType: 'screenshot_$modeLabel',
        sourceId: supplierMatch?.id,
        sourceProvider: browserUri?.host ?? workspace?.moduleRoot,
        sourceRoute: route,
        contextType: supplierMatch == null ? 'screenshot' : 'supplier',
        contextId: supplierMatch?.id,
        contextTitle: supplierMatch?.name ?? title,
        contextSubtitle:
            supplierMatch == null ? (browserUrl ?? route) : 'Portal proveedor',
        tags: [
          'captura',
          'screenshot',
          modeLabel,
          if (browserUrl != null) 'navegador',
          if (supplierMatch != null) 'proveedor',
        ],
        metadata: {
          'capture_mode': modeLabel,
          'workspace_id': workspace?.id,
          'workspace_title': workspace?.title,
          'route': route,
          if (browserUrl != null) 'url': browserUrl,
          if (browser?.pageTitle()?.trim().isNotEmpty == true)
            'page_title': browser!.pageTitle()!.trim(),
          if (selectedGlobalRect != null)
            'selection': {
              'left': selectedGlobalRect.left,
              'top': selectedGlobalRect.top,
              'width': selectedGlobalRect.width,
              'height': selectedGlobalRect.height,
            },
          if (supplierMatch != null) ...{
            'supplier_id': supplierMatch.id,
            'supplier_name': supplierMatch.name,
            'supplier_website': supplierMatch.website,
            'smart_folder': 'supplier:${supplierMatch.id}',
          },
        },
      ),
    );
  }

  BrowserScreenshotContext? _browserContextFor(Workspace? workspace) {
    final id = workspace?.id;
    return id == null ? null : _browserContexts[id];
  }

  String? _browserUrlFromContext(BrowserScreenshotContext? context) {
    final value = context?.currentUrl()?.trim();
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  String? _browserTitleFromContext(BrowserScreenshotContext? context) {
    final value = context?.pageTitle()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _browserUrlFromRoute(String? route) {
    if (route == null || route.trim().isEmpty) return null;
    final uri = Uri.tryParse(route);
    if (uri?.path != '/tools/web') return null;
    final value = uri?.queryParameters['url']?.trim();
    if (value == null || value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      return null;
    }
    return parsed.toString();
  }

  String _dateStamp(DateTime date) =>
      '${date.year}${_two(date.month)}${_two(date.day)}';

  String _timeStamp(DateTime date) =>
      '${_two(date.hour)}${_two(date.minute)}${_two(date.second)}';

  String _two(int value) => value.toString().padLeft(2, '0');
}

class SmartScreenshotCancelledException implements Exception {
  const SmartScreenshotCancelledException();
}

class _ScreenshotSelectionRoute extends PopupRoute<Rect> {
  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.18);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Cancelar captura';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 80);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: const _ScreenshotSelectionOverlay(),
    );
  }
}

class _ScreenshotSelectionOverlay extends StatefulWidget {
  const _ScreenshotSelectionOverlay();

  @override
  State<_ScreenshotSelectionOverlay> createState() =>
      _ScreenshotSelectionOverlayState();
}

class _ScreenshotSelectionOverlayState
    extends State<_ScreenshotSelectionOverlay> {
  Offset? _start;
  Offset? _current;

  Rect? get _rect {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          setState(() {
            _start = details.localPosition;
            _current = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() => _current = details.localPosition);
        },
        onPanEnd: (_) {
          final selected = _rect;
          if (selected == null ||
              selected.width.abs() < 12 ||
              selected.height.abs() < 12) {
            Navigator.of(context).maybePop();
            return;
          }
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) {
            Navigator.of(context).maybePop();
            return;
          }

          final normalized = Rect.fromLTRB(
            selected.left.clamp(0, box.size.width).toDouble(),
            selected.top.clamp(0, box.size.height).toDouble(),
            selected.right.clamp(0, box.size.width).toDouble(),
            selected.bottom.clamp(0, box.size.height).toDouble(),
          );
          final globalSelection = Rect.fromPoints(
            box.localToGlobal(normalized.topLeft),
            box.localToGlobal(normalized.bottomRight),
          );
          Navigator.of(context).pop(globalSelection);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.transparent),
            if (rect != null) _SelectionPaint(rect: rect),
            Positioned(
              left: 24,
              bottom: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Text(
                    'Arrastra para seleccionar area',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionPaint extends StatelessWidget {
  const _SelectionPaint({required this.rect});

  final Rect rect;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SelectionPainter(rect),
      size: Size.infinite,
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.34);
    final clearPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(clearPath, overlay);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF38BDF8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
