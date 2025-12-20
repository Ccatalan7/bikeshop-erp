import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';

// Conditional import for web video backgrounds (reuses the video banner platform implementation).
import 'video_banner_stub.dart' if (dart.library.html) 'video_banner_web.dart'
    as video_platform;
import 'premium_product_card.dart';

/// A free-position "canvas" section that can contain multiple elements (text/button/etc.)
/// positioned absolutely within the block.
///
/// Data schema (block_data):
/// - blockHeight: number (px)
/// - backgroundColor: "#RRGGBB" | "#AARRGGBB" (optional)
/// - showGrid: bool (optional)
/// - gridSize: number (px, optional)
/// - snap: bool (optional)
/// - snapDistance: number (px, optional)
/// - activeElementId: string? (optional)
/// - elements: List<Map> where each element has:
///   - id: string
///   - type: "text" | "button"
///   - x, y, w, h: numbers (px)
///   - ... type-specific fields
class CanvasBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool editable;
  final Color accentColor;
  final ValueChanged<List<Map<String, dynamic>>>? onElementsChanged;
  final ValueChanged<String?>? onActiveElementChanged;
  final void Function(String route)? onNavigate;
  final String? tenantId;
  final String? bodyFont;

  const CanvasBlock({
    super.key,
    required this.data,
    required this.editable,
    required this.accentColor,
    this.onElementsChanged,
    this.onActiveElementChanged,
    this.onNavigate,
    this.tenantId,
    this.bodyFont,
  });

  @override
  State<CanvasBlock> createState() => _CanvasBlockState();
}

class _CanvasBlockState extends State<CanvasBlock> {
  final GlobalKey _canvasKey = GlobalKey();
  late List<Map<String, dynamic>> _elements;
  String? _activeElementIdLocal;

  String? _draggingElementId;
  String? _resizingElementId;

  // Drag anchor so the cursor stays "attached" to the element while moving.
  Offset? _dragAnchorInElement; // local offset inside the element at drag start
  Offset? _pointerCanvasPos; // pointer position in canvas coordinates
  _AxisLock _axisLock = _AxisLock.none;
  Size? _resizeStartSize;

  // Product data cache for product/gallery elements
  final Map<String, Map<String, dynamic>> _productCache = {};
  bool _isLoadingProducts = false;
  String? _resolvedTenantId;
  bool _isResolvingTenantId = false;

  Future<String?> _effectiveTenantId() async {
    final explicit = widget.tenantId;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (_resolvedTenantId != null && _resolvedTenantId!.isNotEmpty) {
      return _resolvedTenantId;
    }
    if (_isResolvingTenantId) return null;
    _isResolvingTenantId = true;
    try {
      final id = await TenantService().getTenantId();
      if (id != null && id.isNotEmpty) {
        _resolvedTenantId = id;
      }
      return _resolvedTenantId;
    } finally {
      _isResolvingTenantId = false;
    }
  }

  Future<void> _ensureProductsLoaded(Set<String> productIds) async {
    if (productIds.isEmpty) return;
    final tenantId = await _effectiveTenantId();
    if (tenantId == null || tenantId.isEmpty) return;
    if (_isLoadingProducts) return;

    final missing = productIds.where((id) => !_productCache.containsKey(id)).toList();
    if (missing.isEmpty) return;

    _isLoadingProducts = true;
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select('id,name,price,image_url,show_on_website,is_active')
          .eq('tenant_id', tenantId)
          .inFilter('id', missing)
          .limit(50);
      for (final row in response as List) {
        final m = Map<String, dynamic>.from(row as Map);
        final id = m['id']?.toString();
        if (id != null) _productCache[id] = m;
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Silent: keep placeholders
    } finally {
      _isLoadingProducts = false;
    }
  }

  Future<List<Map<String, dynamic>>> _loadLatestProducts(int limit) async {
    final tenantId = await _effectiveTenantId();
    if (tenantId == null || tenantId.isEmpty) return const [];
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select('id,name,price,image_url,show_on_website,is_active')
          .eq('tenant_id', tenantId)
          .eq('show_on_website', true)
          .eq('is_active', true)
          .order('updated_at', ascending: false)
          .limit(limit.clamp(1, 24));
      return (response as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // Inline edit state (double click to edit)
  String? _editingElementId;
  final FocusNode _inlineFocusNode = FocusNode();
  TextEditingController? _inlineController;
  String? _inlineEditingField; // 'text' | 'label'

  // Simple alignment guides (canvas edges + center)
  double? _guideX;
  double? _guideY;

  Color _parseHexColor(String? raw, Color fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    var hex = raw.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return fallback;
    return Color(value);
  }

  List<Map<String, dynamic>> _elementsFromData() {
    final raw = widget.data['elements'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  String? _activeElementIdFromData() {
    final raw = widget.data['activeElementId'];
    final id = raw?.toString();
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  bool _snapEnabled() => (widget.data['snap'] as bool?) ?? true;

  double _gridSize() => (widget.data['gridSize'] as num?)?.toDouble() ?? 8.0;

  double _snapDistance() =>
      (widget.data['snapDistance'] as num?)?.toDouble() ?? 6.0;

  bool _isShiftPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  double _snapToGrid(double value) {
    final grid = _gridSize();
    if (grid <= 0) return value;
    final nearest = (value / grid).roundToDouble() * grid;
    if ((nearest - value).abs() <= _snapDistance()) return nearest;
    return value;
  }

  @override
  void initState() {
    super.initState();
    _elements = _elementsFromData();
    _activeElementIdLocal = _activeElementIdFromData();
    _inlineFocusNode.addListener(() {
      // Commit on blur (common Wix behavior)
      if (!_inlineFocusNode.hasFocus && _editingElementId != null) {
        _finishInlineEdit(commit: true);
      }
    });
  }

  @override
  void dispose() {
    _inlineController?.dispose();
    _inlineFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CanvasBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If we are not actively interacting, accept provider updates.
    final isBusy = _draggingElementId != null ||
        _resizingElementId != null ||
        _editingElementId != null;
    if (isBusy) return;

    final nextElements = _elementsFromData();
    final nextActive = _activeElementIdFromData();
    _elements = nextElements;
    _activeElementIdLocal = nextActive;
  }

  void _setActive(String? id) {
    if (_activeElementIdLocal == id) return;
    setState(() {
      _activeElementIdLocal = id;
    });
    widget.onActiveElementChanged?.call(id);
  }

  void _commitElements() {
    widget.onElementsChanged?.call(_elements
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false));
  }

  String _newElementId() => 'el_${DateTime.now().microsecondsSinceEpoch}';

  Map<String, dynamic> _defaultElement(String type) {
    final id = _newElementId();
    final base = <String, dynamic>{
      'id': id,
      'type': type,
      'x': 24.0,
      'y': 24.0,
      'anim': 'none', // none | fade | fadeUp
    };
    switch (type) {
      case 'button':
        return {
          ...base,
          'w': 220.0,
          'h': 56.0,
          'label': 'Botón',
          'style': 'filled',
          'bgColor': '#00A09D',
          'fgColor': '#FFFFFF',
          'radius': 12.0,
          'fontSize': 14.0,
          'letterSpacing': 0.0,
          'uppercase': false,
          'shadow': false,
          'link': '/',
        };
      case 'image':
        return {
          ...base,
          'w': 320.0,
          'h': 200.0,
          'imageUrl': '',
          'fit': 'cover', // cover|contain
          'radius': 12.0,
        };
      case 'product':
        return {
          ...base,
          'w': 280.0,
          'h': 320.0,
          'productId': '',
          'showPrice': true,
        };
      case 'productsGallery':
        return {
          ...base,
          'w': 560.0,
          'h': 360.0,
          'mode': 'latest', // latest|manual
          'productIds': <String>[],
          'maxProducts': 6,
          'columns': 3,
          'showPrice': true,
        };
      case 'text':
      default:
        return {
          ...base,
          'w': 360.0,
          'h': 72.0,
          'text': 'Texto',
          'fontSize': 28.0,
          'fontWeight': 'w700',
          'color': '#111111',
          'align': 'left',
        };
    }
  }

  void _addElementAtCanvasOffset(String type, Offset localPos, Size canvasSize) {
    final el = _defaultElement(type);
    final w = (el['w'] as num?)?.toDouble() ?? 200;
    final h = (el['h'] as num?)?.toDouble() ?? 56;

    // Place so cursor lands near top-left but keep within bounds.
    final x = (localPos.dx).clamp(0.0, math.max(0.0, canvasSize.width - w));
    final y = (localPos.dy).clamp(0.0, math.max(0.0, canvasSize.height - h));
    el['x'] = x;
    el['y'] = y;

    setState(() {
      _elements.add(el);
      _activeElementIdLocal = el['id']?.toString();
    });
    widget.onActiveElementChanged?.call(_activeElementIdLocal);
    _commitElements();
  }

  void _patchElement(String elementId, Map<String, dynamic> patch) {
    final idx = _elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;
    _elements[idx] = {
      ..._elements[idx],
      ...patch,
    };
  }

  void _updateElementPosition(
    String elementId,
    double x,
    double y,
    double maxW,
    double maxH,
    {bool applySnap = true}
  ) {
    final idx = _elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;

    final w = (_elements[idx]['w'] as num?)?.toDouble() ?? 200;
    final h = (_elements[idx]['h'] as num?)?.toDouble() ?? 56;

    var nextX = x;
    var nextY = y;
    if (applySnap && _snapEnabled()) {
      nextX = _snapToGrid(nextX);
      nextY = _snapToGrid(nextY);
    }

    // Clamp to canvas bounds
    nextX = nextX.clamp(0.0, math.max(0.0, maxW - w));
    nextY = nextY.clamp(0.0, math.max(0.0, maxH - h));

    _elements[idx] = {
      ..._elements[idx],
      'x': nextX,
      'y': nextY,
    };
  }

  void _updateElementSize(
    String elementId,
    double w,
    double h,
    double maxW,
    double maxH,
    {bool applySnap = true}
  ) {
    final idx = _elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;

    final x = (_elements[idx]['x'] as num?)?.toDouble() ?? 0.0;
    final y = (_elements[idx]['y'] as num?)?.toDouble() ?? 0.0;

    var nextW = w;
    var nextH = h;
    if (applySnap && _snapEnabled()) {
      nextW = _snapToGrid(nextW);
      nextH = _snapToGrid(nextH);
    }

    // Minimum sizes by type
    final type = (_elements[idx]['type'] ?? 'text').toString();
    final minW = type == 'button' ? 120.0 : 80.0;
    final minH = type == 'button' ? 44.0 : 40.0;

    nextW = nextW.clamp(minW, math.max(minW, maxW - x));
    nextH = nextH.clamp(minH, math.max(minH, maxH - y));

    _elements[idx] = {
      ..._elements[idx],
      'w': nextW,
      'h': nextH,
    };
  }

  (double?, double?) _nearestGuideForMove({
    required String elementId,
    required double x,
    required double y,
    required double w,
    required double h,
    required double canvasW,
    required double canvasH,
  }) {
    final snapD = _snapDistance();
    final centerX = x + w / 2;
    final centerY = y + h / 2;

    double? bestGX;
    double bestDX = snapD + 1;
    double? bestGY;
    double bestDY = snapD + 1;

    // Canvas edges/center
    for (final c in <double>[0, canvasW / 2, canvasW]) {
      final d = (centerX - c).abs();
      if (d <= snapD && d < bestDX) {
        bestDX = d;
        bestGX = c;
      }
    }
    for (final c in <double>[0, canvasH / 2, canvasH]) {
      final d = (centerY - c).abs();
      if (d <= snapD && d < bestDY) {
        bestDY = d;
        bestGY = c;
      }
    }

    // Other elements (left/center/right, top/middle/bottom)
    for (final e in _elements) {
      final id = e['id']?.toString();
      if (id == null || id == elementId) continue;
      final ex = (e['x'] as num?)?.toDouble() ?? 0;
      final ey = (e['y'] as num?)?.toDouble() ?? 0;
      final ew = (e['w'] as num?)?.toDouble() ?? 0;
      final eh = (e['h'] as num?)?.toDouble() ?? 0;

      for (final c in <double>[ex, ex + ew / 2, ex + ew]) {
        final d = (centerX - c).abs();
        if (d <= snapD && d < bestDX) {
          bestDX = d;
          bestGX = c;
        }
      }
      for (final c in <double>[ey, ey + eh / 2, ey + eh]) {
        final d = (centerY - c).abs();
        if (d <= snapD && d < bestDY) {
          bestDY = d;
          bestGY = c;
        }
      }
    }

    return (bestGX, bestGY);
  }

  Offset _snapOnDropPosition({
    required String elementId,
    required double x,
    required double y,
    required double w,
    required double h,
    required double canvasW,
    required double canvasH,
  }) {
    var nextX = x;
    var nextY = y;
    final snapD = _snapDistance();

    final centerX = x + w / 2;
    final centerY = y + h / 2;

    double? bestTargetCX;
    double bestDX = snapD + 1;
    double? bestTargetCY;
    double bestDY = snapD + 1;

    final xTargets = <double>[0, canvasW / 2, canvasW];
    final yTargets = <double>[0, canvasH / 2, canvasH];
    for (final e in _elements) {
      final id = e['id']?.toString();
      if (id == null || id == elementId) continue;
      final ex = (e['x'] as num?)?.toDouble() ?? 0;
      final ey = (e['y'] as num?)?.toDouble() ?? 0;
      final ew = (e['w'] as num?)?.toDouble() ?? 0;
      final eh = (e['h'] as num?)?.toDouble() ?? 0;
      xTargets.addAll([ex, ex + ew / 2, ex + ew]);
      yTargets.addAll([ey, ey + eh / 2, ey + eh]);
    }

    for (final t in xTargets) {
      final d = (centerX - t).abs();
      if (d <= snapD && d < bestDX) {
        bestDX = d;
        bestTargetCX = t;
      }
    }
    for (final t in yTargets) {
      final d = (centerY - t).abs();
      if (d <= snapD && d < bestDY) {
        bestDY = d;
        bestTargetCY = t;
      }
    }

    if (bestTargetCX != null) nextX = bestTargetCX - w / 2;
    if (bestTargetCY != null) nextY = bestTargetCY - h / 2;

    // Secondary grid snap
    if (_snapEnabled()) {
      nextX = _snapToGrid(nextX);
      nextY = _snapToGrid(nextY);
    }

    // Clamp
    nextX = nextX.clamp(0.0, math.max(0.0, canvasW - w));
    nextY = nextY.clamp(0.0, math.max(0.0, canvasH - h));
    return Offset(nextX, nextY);
  }

  void _updateGuides({
    required double x,
    required double y,
    required double w,
    required double h,
    required double canvasW,
    required double canvasH,
  }) {
    final (gx, gy) = _nearestGuideForMove(
      elementId: _draggingElementId ?? '',
      x: x,
      y: y,
      w: w,
      h: h,
      canvasW: canvasW,
      canvasH: canvasH,
    );

    if (_guideX == gx && _guideY == gy) return;
    setState(() {
      _guideX = gx;
      _guideY = gy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final heightMode = (widget.data['heightMode'] ?? 'fixed').toString();
    final vhPct = (widget.data['vhPct'] as num?)?.toDouble() ?? 0.7;
    final blockHeight = heightMode == 'viewport'
        ? (MediaQuery.sizeOf(context).height *
            vhPct.clamp(0.2, 1.0).toDouble())
        : (widget.data['blockHeight'] as num?)?.toDouble() ??
            (widget.data['height'] as num?)?.toDouble() ??
            420.0;
    final bg = _parseHexColor(widget.data['backgroundColor'] as String?, Colors.white);
    final showGrid = (widget.data['showGrid'] as bool?) ?? true;
    final activeId = _activeElementIdLocal;
    final elements = _elements;

    final backgroundImageUrl =
        (widget.data['backgroundImageUrl'] ?? '').toString().trim();
    final backgroundVideoUrl =
        (widget.data['backgroundVideoUrl'] ?? '').toString().trim();
    final backgroundYoutubeId =
        (widget.data['backgroundYoutubeId'] ?? '').toString().trim();
    final overlayEnabled = (widget.data['overlayEnabled'] as bool?) ?? false;
    final overlayOpacity = (widget.data['overlayOpacity'] as num?)?.toDouble() ?? 0.35;
    final overlayColor = _parseHexColor(
      (widget.data['overlayColor'] ?? '#000000').toString(),
      Colors.black,
    );
    final backgroundFit =
        (widget.data['backgroundFit'] ?? 'cover').toString().toLowerCase();
    final fit = backgroundFit == 'contain' ? BoxFit.contain : BoxFit.cover;

    return SizedBox(
      height: blockHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasW = constraints.maxWidth;
          final canvasH = constraints.maxHeight;
          return Stack(
            key: _canvasKey,
            children: [
              // Background (color + image/video + overlay) + grid
              Positioned.fill(
                child: Stack(
                  children: [
                    // Solid background color
                    Positioned.fill(child: ColoredBox(color: bg)),

                    // Video background (web only)
                    if (backgroundYoutubeId.isNotEmpty ||
                        backgroundVideoUrl.isNotEmpty)
                      Positioned.fill(
                        child: video_platform.VideoBannerPlatform
                            .buildVideoBackground(
                          youtubeVideoId: backgroundYoutubeId.isNotEmpty
                              ? backgroundYoutubeId
                              : null,
                          videoFileUrl:
                              backgroundVideoUrl.isNotEmpty ? backgroundVideoUrl : null,
                          width: canvasW,
                          height: canvasH,
                        ),
                      ),

                    // Image background (shown on all platforms; can be used as fallback for video)
                    if (backgroundImageUrl.isNotEmpty)
                      Positioned.fill(
                        child: Image.network(
                          backgroundImageUrl,
                          fit: fit,
                          errorBuilder: (context, _, __) => const SizedBox.shrink(),
                        ),
                      ),

                    // Overlay
                    if (overlayEnabled)
                      Positioned.fill(
                        child: ColoredBox(
                          color: overlayColor.withValues(
                            alpha: overlayOpacity.clamp(0.0, 0.9),
                          ),
                        ),
                      ),

                    // Grid (edit mode only)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CanvasBackgroundPainter(
                          background: Colors.transparent,
                          showGrid: showGrid && widget.editable,
                          gridSize: _gridSize(),
                          gridColor: Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Drop target for editor panel canvas elements (drag from "Canvas (arrastrable)" section)
              // MUST be above the background so it can receive hit tests.
              if (widget.editable)
                Positioned.fill(
                  child: DragTarget<String>(
                    onWillAccept: (data) =>
                        data != null && data.startsWith('canvas_el:'),
                    onAcceptWithDetails: (details) {
                      final payload = details.data;
                      if (!payload.startsWith('canvas_el:')) return;
                      final type = payload.replaceFirst('canvas_el:', '');

                      final ctx = _canvasKey.currentContext;
                      final box = ctx?.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(details.offset);
                      _addElementAtCanvasOffset(
                          type, local, Size(canvasW, canvasH));
                    },
                    builder: (context, candidate, rejected) {
                      // Keep the DragTarget active without blocking normal interactions:
                      // only paint the overlay when dragging a compatible payload.
                      if (candidate.isEmpty) return const SizedBox.expand();
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: 0.9),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Elements
              for (final el in elements)
                _buildElement(
                  context: context,
                  el: el,
                  isActive: activeId != null && el['id'] == activeId,
                  canvasW: canvasW,
                  canvasH: canvasH,
                ),

              // Guides
              if (widget.editable && _guideX != null)
                Positioned(
                  left: (_guideX!).clamp(0.0, canvasW),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: widget.accentColor.withValues(alpha: 0.6),
                  ),
                ),
              if (widget.editable && _guideY != null)
                Positioned(
                  top: (_guideY!).clamp(0.0, canvasH),
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    color: widget.accentColor.withValues(alpha: 0.6),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildElement({
    required BuildContext context,
    required Map<String, dynamic> el,
    required bool isActive,
    required double canvasW,
    required double canvasH,
  }) {
    final id = (el['id'] ?? '').toString();
    final type = (el['type'] ?? 'text').toString();
    final x = (el['x'] as num?)?.toDouble() ?? 20.0;
    final y = (el['y'] as num?)?.toDouble() ?? 20.0;
    final w = (el['w'] as num?)?.toDouble() ?? 240.0;
    final h = (el['h'] as num?)?.toDouble() ?? 56.0;

    final isInlineEditing = widget.editable &&
        isActive &&
        _editingElementId == id &&
        _inlineController != null;

    Widget content;
    switch (type) {
      case 'button':
        final label = (el['label'] ?? 'Botón').toString();
        final style = (el['style'] ?? 'filled').toString(); // filled|outline|text
        final link = (el['link'] ?? '/').toString();
        final fontSize = (el['fontSize'] as num?)?.toDouble() ?? 14;
        final radius = (el['radius'] as num?)?.toDouble() ?? 10;
        final bgColor =
            _parseHexColor(el['bgColor'] as String?, widget.accentColor);
        final fgColor = _parseHexColor(el['fgColor'] as String?, Colors.white);
        final letterSpacing =
            (el['letterSpacing'] as num?)?.toDouble() ?? 0.0;
        final uppercase = (el['uppercase'] as bool?) ?? false;
        final shadow = (el['shadow'] as bool?) ?? false;

        final buttonStyle = switch (style) {
          'outline' => OutlinedButton.styleFrom(
              side: BorderSide(color: bgColor),
              foregroundColor: bgColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius))),
          'text' => TextButton.styleFrom(
              foregroundColor: bgColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius))),
          _ => ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius))),
        };

        void onPressed() {
          if (widget.editable) return;
          widget.onNavigate?.call(link);
        }

        final labelText = uppercase ? label.toUpperCase() : label;
        final labelStyle = TextStyle(
          fontSize: fontSize,
          letterSpacing: letterSpacing,
          color: style == 'filled' ? fgColor : bgColor,
          fontWeight: FontWeight.w600,
        );

        if (widget.editable) {
          // In edit mode, render a button-like container (no real button to avoid stealing gestures).
          content = DecoratedBox(
            decoration: BoxDecoration(
              color: style == 'filled' ? bgColor : Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              border: style == 'outline'
                  ? Border.all(color: bgColor, width: 1.5)
                  : null,
              boxShadow: shadow && style == 'filled'
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: Text(labelText, style: labelStyle),
            ),
          );
        } else {
          final child = Text(labelText, style: labelStyle);
          content = switch (style) {
            'outline' => OutlinedButton(
                onPressed: onPressed, style: buttonStyle, child: child),
            'text' =>
              TextButton(onPressed: onPressed, style: buttonStyle, child: child),
            _ => ElevatedButton(
                onPressed: onPressed, style: buttonStyle, child: child),
          };
        }
        break;
      case 'image':
        final imageUrl = (el['imageUrl'] ?? '').toString().trim();
        final fitRaw = (el['fit'] ?? 'cover').toString();
        final fit = fitRaw == 'contain' ? BoxFit.contain : BoxFit.cover;
        final radius = (el['radius'] as num?)?.toDouble() ?? 12;
        content = ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: imageUrl.isEmpty
              ? Container(
                  color: Colors.black.withValues(alpha: 0.04),
                  child: Center(
                    child: Text(
                      'Imagen',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : Image.network(
                  imageUrl,
                  fit: fit,
                  errorBuilder: (context, _, __) => Container(
                    color: Colors.black.withValues(alpha: 0.04),
                    child: Center(
                      child: Text(
                        'Imagen inválida',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
        );
        break;
      case 'product':
        final productId = (el['productId'] ?? '').toString().trim();
        if (productId.isNotEmpty) {
          _ensureProductsLoaded({productId});
        }
        final product = productId.isNotEmpty ? _productCache[productId] : null;
        if (product == null || product.isEmpty) {
          content = Container(
            color: Colors.black.withValues(alpha: 0.03),
            child: Center(
              child: Text(
                'Producto',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        } else {
          final id = product['id']?.toString() ?? '';
          final name = product['name']?.toString() ?? 'Producto';
          final priceRaw = product['price'];
          final price = priceRaw is num
              ? priceRaw.toDouble()
              : double.tryParse('$priceRaw') ?? 0.0;
          final imageUrl = product['image_url']?.toString();
          content = PremiumProductCard(
            productId: id,
            name: name,
            price: price,
            imageUrl: imageUrl,
            bodyFont: widget.bodyFont,
            previewMode: widget.editable,
            onNavigate: widget.onNavigate,
          );
        }
        break;
      case 'productsGallery':
        final mode = (el['mode'] ?? 'latest').toString();
        final maxProducts = (el['maxProducts'] as num?)?.toInt() ?? 6;
        final columns = (el['columns'] as num?)?.toInt() ?? 3;
        final rawIds = el['productIds'];
        final ids = rawIds is List
            ? rawIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : <String>[];

        if (mode == 'manual' && ids.isNotEmpty) {
          _ensureProductsLoaded(ids.toSet());
        }

        content = FutureBuilder<List<Map<String, dynamic>>>(
          future: mode == 'latest'
              ? _loadLatestProducts(maxProducts)
              : Future.value(ids.map((id) => _productCache[id]).whereType<Map<String, dynamic>>().toList()),
          builder: (context, snap) {
            final products = snap.data ?? const [];
            if (products.isEmpty) {
              return Container(
                color: Colors.black.withValues(alpha: 0.03),
                child: Center(
                  child: Text(
                    'Galería de productos',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            final cols = columns.clamp(1, 4);
            return GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.75,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: products.take(maxProducts).length,
              itemBuilder: (context, index) {
                final p = products.take(maxProducts).elementAt(index);
                final id = p['id']?.toString() ?? '';
                final name = p['name']?.toString() ?? 'Producto';
                final priceRaw = p['price'];
                final price = priceRaw is num
                    ? priceRaw.toDouble()
                    : double.tryParse('$priceRaw') ?? 0.0;
                final imageUrl = p['image_url']?.toString();
                return PremiumProductCard(
                  productId: id,
                  name: name,
                  price: price,
                  imageUrl: imageUrl,
                  bodyFont: widget.bodyFont,
                  previewMode: widget.editable,
                  onNavigate: widget.onNavigate,
                );
              },
            );
          },
        );
        break;
      case 'text':
      default:
        final text = (el['text'] ?? 'Texto').toString();
        final fontSize = (el['fontSize'] as num?)?.toDouble() ?? 24;
        final weight = (el['fontWeight'] as String?) ?? 'w600';
        final color = _parseHexColor(el['color'] as String?, Colors.black87);
        final align = (el['align'] as String?) ?? 'left'; // left|center|right
        final textAlign = switch (align) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        };
        final fw = switch (weight) {
          'w400' => FontWeight.w400,
          'w500' => FontWeight.w500,
          'w600' => FontWeight.w600,
          'w700' => FontWeight.w700,
          _ => FontWeight.w600,
        };

        if (isInlineEditing && _inlineEditingField == 'text') {
          content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: TextField(
              controller: _inlineController,
              focusNode: _inlineFocusNode,
              maxLines: null,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fw,
                color: color,
                height: 1.1,
              ),
              textAlign: textAlign,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _finishInlineEdit(commit: true),
              onEditingComplete: () => _finishInlineEdit(commit: true),
            ),
          );
        } else {
          content = Align(
            alignment: switch (align) {
              'center' => Alignment.center,
              'right' => Alignment.centerRight,
              _ => Alignment.centerLeft,
            },
            child: Text(
              text,
              textAlign: textAlign,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fw,
                color: color,
                height: 1.1,
              ),
            ),
          );
        }
    }

    // Basic element animation (view mode only)
    final anim = (el['anim'] ?? 'none').toString();
    if (!widget.editable && anim != 'none') {
      final durationMs = (el['animDurationMs'] as num?)?.toInt() ?? 420;
      content = _EntranceAnimation(
        key: ValueKey('anim_${id}_$anim'),
        type: anim,
        duration: Duration(milliseconds: durationMs.clamp(120, 2000)),
        child: content,
      );
    }

    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: widget.editable && isActive
            ? Border.all(color: widget.accentColor, width: 2)
            : widget.editable
                ? Border.all(color: Colors.black.withValues(alpha: 0.08))
                : null,
        color: widget.editable
            ? Colors.white.withValues(alpha: isActive ? 0.14 : 0.06)
            : null,
      ),
      child: SizedBox.expand(child: content),
    );

    final decoratedWithHandles = widget.editable && isActive && !isInlineEditing
        ? Stack(
            children: [
              Positioned.fill(child: decorated),
              Positioned(
                right: 2,
                bottom: 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    setState(() {
                      _resizingElementId = id;
                      _resizeStartSize = Size(w, h);
                      _guideX = null;
                      _guideY = null;
                    });
                    _setActive(id);
                  },
                  onPanUpdate: (d) {
                    if (_resizingElementId != id) return;

                    final current = _elements.firstWhere(
                      (e) => e['id']?.toString() == id,
                      orElse: () => el,
                    );
                    final cw = (current['w'] as num?)?.toDouble() ?? w;
                    final ch = (current['h'] as num?)?.toDouble() ?? h;
                    var nextW = cw + d.delta.dx;
                    var nextH = ch + d.delta.dy;

                    // Hold Shift to keep aspect ratio while resizing.
                    if (_isShiftPressed() && _resizeStartSize != null) {
                      final ratio = _resizeStartSize!.width /
                          math.max(1.0, _resizeStartSize!.height);
                      if (d.delta.dx.abs() >= d.delta.dy.abs()) {
                        nextH = nextW / ratio;
                      } else {
                        nextW = nextH * ratio;
                      }
                    }
                    setState(() {
                      // During resize, don't snap live (prevents "lag behind cursor").
                      _updateElementSize(id, nextW, nextH, canvasW, canvasH,
                          applySnap: false);
                    });
                  },
                  onPanEnd: (_) {
                    setState(() {
                      _resizingElementId = null;
                      _resizeStartSize = null;
                    });
                    // Snap-on-drop for resize (clean final alignment without magnetic lag).
                    final current = _elements.firstWhere(
                      (e) => e['id']?.toString() == id,
                      orElse: () => el,
                    );
                    final cw = (current['w'] as num?)?.toDouble() ?? w;
                    final ch = (current['h'] as num?)?.toDouble() ?? h;
                    setState(() {
                      _updateElementSize(id, cw, ch, canvasW, canvasH,
                          applySnap: true);
                    });
                    _commitElements();
                  },
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(
                      Icons.open_in_full_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          )
        : decorated;

    return Positioned(
      left: x,
      top: y,
      width: w,
      height: h,
      child: widget.editable
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setActive(id),
              onDoubleTap: () => _startInlineEdit(type: type, el: el),
              onPanStart: (d) {
                if (_resizingElementId == id) return;
                if (_editingElementId == id) return;
                setState(() {
                  _draggingElementId = id;
                  _dragAnchorInElement = d.localPosition;
                  _pointerCanvasPos = Offset(x, y) + d.localPosition;
                  _axisLock = _AxisLock.none;
                });
                _setActive(id);
              },
              onPanUpdate: (d) {
                if (_resizingElementId == id) return;
                if (_editingElementId == id) return;
                if (_draggingElementId != id) return;
                if (_dragAnchorInElement == null || _pointerCanvasPos == null) {
                  // Fallback: delta-based movement (should be rare)
                  final current = _elements.firstWhere(
                    (e) => e['id']?.toString() == id,
                    orElse: () => el,
                  );
                  final cx = (current['x'] as num?)?.toDouble() ?? x;
                  final cy = (current['y'] as num?)?.toDouble() ?? y;
                  final nextX = cx + d.delta.dx;
                  final nextY = cy + d.delta.dy;
                  setState(() {
                    _updateElementPosition(id, nextX, nextY, canvasW, canvasH,
                        applySnap: false);
                  });
                  return;
                }

                // Hold Shift to lock axis (horizontal/vertical).
                final shift = _isShiftPressed();
                if (shift && _axisLock == _AxisLock.none) {
                  _axisLock = d.delta.dx.abs() >= d.delta.dy.abs()
                      ? _AxisLock.horizontal
                      : _AxisLock.vertical;
                }
                if (!shift) {
                  _axisLock = _AxisLock.none;
                }

                var delta = d.delta;
                if (_axisLock == _AxisLock.horizontal) {
                  delta = Offset(delta.dx, 0);
                } else if (_axisLock == _AxisLock.vertical) {
                  delta = Offset(0, delta.dy);
                }

                // Keep pointer in canvas coords, then derive top-left using the drag anchor.
                _pointerCanvasPos = _pointerCanvasPos! + delta;
                final desiredTopLeft = _pointerCanvasPos! - _dragAnchorInElement!;
                final nextX = desiredTopLeft.dx;
                final nextY = desiredTopLeft.dy;

                _updateGuides(
                  x: nextX,
                  y: nextY,
                  w: w,
                  h: h,
                  canvasW: canvasW,
                  canvasH: canvasH,
                );
                setState(() {
                  // During drag, guides are visual only; snap on drop.
                  _updateElementPosition(id, nextX, nextY, canvasW, canvasH,
                      applySnap: false);
                });
              },
              onPanEnd: (_) {
                // Snap-on-drop: final tidy alignment without affecting cursor feel.
                final current = _elements.firstWhere(
                  (e) => e['id']?.toString() == id,
                  orElse: () => el,
                );
                final cx = (current['x'] as num?)?.toDouble() ?? x;
                final cy = (current['y'] as num?)?.toDouble() ?? y;
                final cw = (current['w'] as num?)?.toDouble() ?? w;
                final ch = (current['h'] as num?)?.toDouble() ?? h;
                final snapped = _snapOnDropPosition(
                  elementId: id,
                  x: cx,
                  y: cy,
                  w: cw,
                  h: ch,
                  canvasW: canvasW,
                  canvasH: canvasH,
                );
                setState(() {
                  _draggingElementId = null;
                  _dragAnchorInElement = null;
                  _pointerCanvasPos = null;
                  _axisLock = _AxisLock.none;
                  _guideX = null;
                  _guideY = null;
                  _updateElementPosition(
                    id,
                    snapped.dx,
                    snapped.dy,
                    canvasW,
                    canvasH,
                    applySnap: false,
                  );
                });
                _commitElements();
              },
              child: decoratedWithHandles,
            )
          : SizedBox.expand(child: content),
    );
  }

  void _startInlineEdit({
    required String type,
    required Map<String, dynamic> el,
  }) {
    if (!widget.editable) return;
    final id = el['id']?.toString();
    if (id == null || id.isEmpty) return;

    // Choose which field to edit.
    final field = type == 'button' ? 'label' : 'text';
    final initial = (el[field] ?? (type == 'button' ? 'Botón' : 'Texto')).toString();

    setState(() {
      _editingElementId = id;
      _inlineEditingField = field;
      _inlineController?.dispose();
      _inlineController = TextEditingController(text: initial);
      _draggingElementId = null;
      _resizingElementId = null;
      _guideX = null;
      _guideY = null;
    });
    _setActive(id);

    // Focus next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineFocusNode.requestFocus();
      _inlineController?.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineController?.text.length ?? 0,
      );
    });
  }

  void _finishInlineEdit({required bool commit}) {
    final id = _editingElementId;
    final field = _inlineEditingField;
    final controller = _inlineController;
    if (id == null || field == null) return;

    if (commit && controller != null) {
      final next = controller.text;
      setState(() {
        _patchElement(id, {field: next});
      });
      _commitElements();
    }

    setState(() {
      _editingElementId = null;
      _inlineEditingField = null;
    });
  }
}

class _CanvasBackgroundPainter extends CustomPainter {
  final Color background;
  final bool showGrid;
  final double gridSize;
  final Color gridColor;

  _CanvasBackgroundPainter({
    required this.background,
    required this.showGrid,
    required this.gridSize,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (!showGrid || gridSize <= 2) return;

    final p = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Dots grid (cheap and readable)
    for (double y = 0; y < size.height; y += gridSize) {
      for (double x = 0; x < size.width; x += gridSize) {
        canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasBackgroundPainter oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.gridColor != gridColor;
  }
}

enum _AxisLock { none, horizontal, vertical }

class _EntranceAnimation extends StatefulWidget {
  final String type; // fade | fadeUp
  final Duration duration;
  final Widget child;

  const _EntranceAnimation({
    super.key,
    required this.type,
    required this.duration,
    required this.child,
  });

  @override
  State<_EntranceAnimation> createState() => _EntranceAnimationState();
}

class _EntranceAnimationState extends State<_EntranceAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    if (widget.type == 'fadeUp') {
      final offset = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
          .animate(curved);
      return FadeTransition(
        opacity: opacity,
        child: SlideTransition(position: offset, child: widget.child),
      );
    }
    return FadeTransition(opacity: opacity, child: widget.child);
  }
}

// Canvas now reuses `PremiumProductCard` (same design as Products banner).


