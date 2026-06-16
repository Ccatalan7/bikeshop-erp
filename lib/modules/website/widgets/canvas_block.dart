import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import 'canvas_block_toolbar.dart';

// Conditional import for web video backgrounds (reuses the video banner platform implementation).
// Conditional import for web video backgrounds (reuses the video banner platform implementation).
import 'video_banner_io.dart' if (dart.library.html) 'video_banner_web.dart'
    as video_platform;
import 'premium_product_card.dart';
import 'snap_result.dart';

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
  final ValueChanged<Size>? onCanvasSizeChanged;
  final void Function(String route)? onNavigate;
  final String? tenantId;
  final String? bodyFont;
  final VoidCallback? onBackgroundTap;

  const CanvasBlock({
    super.key,
    required this.data,
    required this.editable,
    required this.accentColor,
    this.onElementsChanged,
    this.onActiveElementChanged,
    this.onCanvasSizeChanged,
    this.onNavigate,
    this.tenantId,
    this.bodyFont,
    this.onBackgroundTap,
  });

  @override
  State<CanvasBlock> createState() => _CanvasBlockState();
}

class _CanvasBlockState extends State<CanvasBlock> {
  final GlobalKey _canvasKey = GlobalKey();
  late List<Map<String, dynamic>> _elements;
  String? _activeElementIdLocal;

  bool _commitScheduled = false;
  List<Map<String, dynamic>>? _pendingElementsCommit;

  Size? _lastReportedCanvasSize;
  Size? _pendingCanvasSizeReport;
  bool _isCanvasSizeReportScheduled = false;

  String? _draggingElementId;
  String? _resizingElementId;

  // Drag anchor so the cursor stays "attached" to the element while moving.
  Offset? _dragAnchorInElement; // local offset inside the element at drag start
  Offset? _pointerCanvasPos; // pointer position in canvas coordinates
  _AxisLock _axisLock = _AxisLock.none;
  Size? _resizeStartSize;

  // Track pointer buttons to ignore trackpad scrolling (buttons == 0)
  int _lastPointerButtons = 0;

  // Product data cache for product/gallery elements
  final Map<String, Map<String, dynamic>> _productCache = {};
  // Cache for latest products queries to prevent FutureBuilder reset on rebuild
  final Map<int, Future<List<Map<String, dynamic>>>> _latestProductsCache = {};

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

    final missing =
        productIds.where((id) => !_productCache.containsKey(id)).toList();
    if (missing.isEmpty) return;

    _isLoadingProducts = true;
    try {
      var query = Supabase.instance.client
          .from('products')
          .select(
              'id,name,price,image_url,show_on_website,is_active,is_published')
          .eq('tenant_id', tenantId)
          .inFilter('id', missing);
      if (!widget.editable) {
        query = query
            .eq('show_on_website', true)
            .eq('is_published', true)
            .eq('is_active', true);
      }
      final response = await query.limit(50);
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
          .select(
              'id,name,price,image_url,show_on_website,is_active,is_published')
          .eq('tenant_id', tenantId)
          .eq('show_on_website', true)
          .eq('is_published', true)
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

  Future<List<Map<String, dynamic>>> _getCachedLatestProducts(int limit) {
    if (_latestProductsCache.containsKey(limit)) {
      return _latestProductsCache[limit]!;
    }
    final future = _loadLatestProducts(limit);
    _latestProductsCache[limit] = future;
    return future;
  }

  // Inline edit state (double click to edit)
  String? _editingElementId;
  final FocusNode _inlineFocusNode = FocusNode();
  TextEditingController? _inlineController;
  String? _inlineEditingField; // 'text' | 'label'

  // Simple alignment guides (canvas edges + center)
  double? _guideX;
  double? _guideY;

  // Hover state for visual feedback
  String? _hoveredElementId;

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

    // Clear caches if tenant changes
    if (oldWidget.tenantId != widget.tenantId) {
      _latestProductsCache.clear();
      _productCache.clear();
      _resolvedTenantId = null;
    }

    // If we are not actively interacting, accept provider updates.
    final isBusy = _draggingElementId != null ||
        _resizingElementId != null ||
        _editingElementId != null;
    if (isBusy) return;

    // Only update elements if the source list reference changed
    // This avoids rebuilding the internal list when other props change (like activeElementId)
    if (widget.data['elements'] != oldWidget.data['elements']) {
      _elements = _elementsFromData();
    }

    // Sync selection from provider so panel-driven selection reflects on canvas.
    _activeElementIdLocal = _activeElementIdFromData();
  }

  void _setActive(String? id) {
    if (_activeElementIdLocal == id) return;
    setState(() {
      _activeElementIdLocal = id;
    });
    widget.onActiveElementChanged?.call(id);
  }

  void _commitElements() {
    final callback = widget.onElementsChanged;
    if (callback == null) return;

    _pendingElementsCommit = _elements
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    if (_commitScheduled) return;
    _commitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commitScheduled = false;
      final pending = _pendingElementsCommit;
      _pendingElementsCommit = null;
      if (!mounted || pending == null) return;
      callback(pending);
    });
  }

  void _reportCanvasSizeIfNeeded(double canvasW, double canvasH) {
    final callback = widget.onCanvasSizeChanged;
    if (!widget.editable || callback == null) return;

    final size = Size(canvasW, canvasH);
    final last = _lastReportedCanvasSize;
    if (last != null) {
      final dw = (last.width - size.width).abs();
      final dh = (last.height - size.height).abs();
      if (dw < 1.0 && dh < 1.0) return;
    }

    // IMPORTANT: this is called during build (LayoutBuilder). We must not notify
    // listeners synchronously here, or Provider will throw
    // "setState() or markNeedsBuild() called during build".
    _lastReportedCanvasSize = size;
    _pendingCanvasSizeReport = size;

    if (_isCanvasSizeReportScheduled) return;
    _isCanvasSizeReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isCanvasSizeReportScheduled = false;
      final pending = _pendingCanvasSizeReport;
      _pendingCanvasSizeReport = null;
      if (!mounted || pending == null) return;
      callback(pending);
    });
  }

  /// Fixed reference width for consistent WYSIWYG between edit and preview.
  /// Both modes scale to/from this, so element positions stay consistent.
  static const double _kReferenceWidth = 1200.0;

  double _computeDesignWidth(double canvasW) {
    final raw = widget.data['designWidth'];
    final explicit = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (explicit != null && explicit > 0) return explicit;

    // Use fixed reference width so edit and preview use same coordinate system
    return _kReferenceWidth;
  }

  double _calculateScale(double canvasW) {
    final designW = _computeDesignWidth(canvasW);
    if (designW <= 0) return 1.0;
    // Clamp to 1.0 so we don't scale UP on wide screens (we center instead)
    return (canvasW / designW).clamp(0.0, 1.0);
  }

  double _calculateOffsetX(double canvasW) {
    final designW = _computeDesignWidth(canvasW);
    final scale = _calculateScale(canvasW);
    // Center the content if canvas is wider than scaled design
    return math.max(0.0, (canvasW - designW * scale) / 2);
  }

  double _effectiveLeft({
    required double x,
    required double w,
    required double canvasW,
  }) {
    final scale = _calculateScale(canvasW);
    final offsetX = _calculateOffsetX(canvasW);
    return x * scale + offsetX;
  }

  double _effectiveTop({
    required double y,
    required double h,
    required double canvasW,
    required double canvasH,
  }) {
    final scale = _calculateScale(canvasW);
    return y * scale;
  }

  double _effectiveWidth({
    required String type,
    required double w,
    required double canvasW,
  }) {
    final scale = _calculateScale(canvasW);
    return w * scale;
  }

  double _effectiveHeight({
    required String type,
    required double h,
    required double canvasW,
    required double canvasH,
  }) {
    final scale = _calculateScale(canvasW);
    return h * scale;
  }

  double _designToRenderX({required double x, required double canvasW}) {
    final scale = _calculateScale(canvasW);
    final offsetX = _calculateOffsetX(canvasW);
    return x * scale + offsetX;
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
          'layout': 'grid', // grid|carousel
          'columns': 3,
          'cardWidth': 300,
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

  void _addElementAtCanvasOffset(
      String type, Offset localPos, Size canvasSize) {
    final el = _defaultElement(type);
    final w = (el['w'] as num?)?.toDouble() ?? 200;
    final h = (el['h'] as num?)?.toDouble() ?? 56;

    // Place so cursor lands near top-left but keep within bounds.
    final x = (localPos.dx).clamp(0.0, math.max(0.0, canvasSize.width - w));
    final y = (localPos.dy).clamp(0.0, math.max(0.0, canvasSize.height - h));
    // Use _calculateScale for consistency
    final scaleX = _calculateScale(canvasSize.width);
    final offsetX = _calculateOffsetX(canvasSize.width);

    el['x'] = (x - offsetX) / scaleX;
    el['y'] = y / scaleX;

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
    setState(() {
      _elements[idx] = {
        ..._elements[idx],
        ...patch,
      };
    });
    _commitElements();
  }

  void _updateElementPosition(
      String elementId, double x, double y, double maxW, double maxH,
      {bool applySnap = true}) {
    final idx = _elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;

    final w = (_elements[idx]['w'] as num?)?.toDouble() ?? 200;
    final h = (_elements[idx]['h'] as num?)?.toDouble() ?? 56;

    // NOTE: x/y are provided in *render space* (after any preview scaling).
    // We clamp/snap in render space, then store x back in design space.
    // Use _calculateScale to match rendering logic (clamped to 1.0)
    final scaleX = _calculateScale(maxW);
    final offsetX = _calculateOffsetX(maxW);

    var nextX = x;
    var nextY = y;
    if (applySnap && _snapEnabled()) {
      nextX = _snapToGrid(nextX);
      nextY = _snapToGrid(nextY);
    }

    // Clamp to canvas bounds (in render space, accounting for scaled element size)
    final scaledW = w * scaleX;
    final scaledH = h * scaleX;
    // Allow dragging a bit outside if needed, but for now clamp to safe area (0..max)
    // Note: offsetX is the visual start of the "centered" canvas.
    nextX = nextX.clamp(0.0, math.max(0.0, maxW - scaledW));
    nextY = nextY.clamp(0.0, math.max(0.0, maxH - scaledH));

    // Convert back to design space: subtract offset, then divide by scale
    final designX = (nextX - offsetX) / scaleX;
    final designY = nextY / scaleX;

    _elements[idx] = {
      ..._elements[idx],
      'x': designX,
      'y': designY,
    };
  }

  void _updateElementSize(
      String elementId, double w, double h, double maxW, double maxH,
      {bool applySnap = true}) {
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

    // Use _calculateScale to match rendering logic (clamped to 1.0)
    final scaleX = _calculateScale(maxW);

    final xRender = _designToRenderX(x: x, canvasW: maxW);
    // Use effective top for clamping height. yRender = y * scale
    final yRender = y * scaleX;

    nextW = nextW.clamp(minW, math.max(minW, maxW - xRender));
    nextH = nextH.clamp(minH, math.max(minH, maxH - yRender));

    _elements[idx] = {
      ..._elements[idx],
      'w': nextW / scaleX,
      'h': nextH / scaleX,
    };
  }

  SnapResult _calculateSnappedPosition({
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

    // Priorities keys:
    // 0: Center-Center
    // 1: Edge-Edge (L-L, R-R, T-T, B-B)
    // 2: Edge-Center or Cross-Edge (L-R, L-C, etc) - excluded for noise reduction if desired

    double bestDX = snapD + 1;
    double? finalSnapX; // New top-left X
    double? guideX;

    // Collect Targets
    final canvasTargetsX = [0.0, canvasW / 2, canvasW];
    final xTargets = <double>[...canvasTargetsX];

    for (final e in _elements) {
      final id = e['id']?.toString();
      if (id == null || id == elementId) continue;
      final ex = (e['x'] as num?)?.toDouble() ?? 0;
      final ew = (e['w'] as num?)?.toDouble() ?? 0;

      final exRender = _effectiveLeft(x: ex, w: ew, canvasW: canvasW);
      final ewRender =
          _effectiveWidth(type: e['type'].toString(), w: ew, canvasW: canvasW);

      xTargets.addAll([exRender, exRender + ewRender / 2, exRender + ewRender]);
    }

    // Check X Axis
    // Drag Center -> Target Center/Edges
    final centerX = x + w / 2;
    for (final t in xTargets) {
      final d = (centerX - t).abs();
      if (d <= snapD && d < bestDX) {
        bestDX = d;
        finalSnapX = t - w / 2;
        guideX = t;
      }
    }

    // Drag Left -> Target Left/Right/Center
    for (final t in xTargets) {
      final d = (x - t).abs();
      if (d <= snapD && d < bestDX) {
        bestDX = d;
        finalSnapX = t;
        guideX = t;
      }
    }

    // Drag Right -> Target Left/Right/Center
    for (final t in xTargets) {
      final d = ((x + w) - t).abs();
      if (d <= snapD && d < bestDX) {
        bestDX = d;
        finalSnapX = t - w;
        guideX = t;
      }
    }

    bool snappedX = false;
    if (finalSnapX != null) {
      nextX = finalSnapX;
      snappedX = true;
    }

    // Y Axis
    double bestDY = snapD + 1;
    double? finalSnapY;
    double? guideY;

    final canvasTargetsY = [0.0, canvasH / 2, canvasH];
    final yTargets = <double>[...canvasTargetsY];

    for (final e in _elements) {
      final id = e['id']?.toString();
      if (id == null || id == elementId) continue;
      final ey = (e['y'] as num?)?.toDouble() ?? 0;
      final eh = (e['h'] as num?)?.toDouble() ?? 0;

      final eyRender =
          _effectiveTop(y: ey, h: eh, canvasW: canvasW, canvasH: canvasH);
      final ehRender = _effectiveHeight(
          type: e['type'].toString(),
          h: eh,
          canvasW: canvasW,
          canvasH: canvasH);

      yTargets.addAll([eyRender, eyRender + ehRender / 2, eyRender + ehRender]);
    }

    // Drag Center Y
    final centerY = y + h / 2;
    for (final t in yTargets) {
      final d = (centerY - t).abs();
      if (d <= snapD && d < bestDY) {
        bestDY = d;
        finalSnapY = t - h / 2;
        guideY = t;
      }
    }

    // Drag Top
    for (final t in yTargets) {
      final d = (y - t).abs();
      if (d <= snapD && d < bestDY) {
        bestDY = d;
        finalSnapY = t;
        guideY = t;
      }
    }

    // Drag Bottom
    for (final t in yTargets) {
      final d = ((y + h) - t).abs();
      if (d <= snapD && d < bestDY) {
        bestDY = d;
        finalSnapY = t - h;
        guideY = t;
      }
    }

    bool snappedY = false;
    if (finalSnapY != null) {
      nextY = finalSnapY;
      snappedY = true;
    }

    // Secondary grid snap (mutually exclusive)
    if (_snapEnabled()) {
      if (!snappedX) {
        final gx = _snapToGrid(nextX);
        if (gx != nextX) {
          nextX = gx;
          snappedX = true; // Implicitly snapped
        }
      }
      if (!snappedY) {
        final gy = _snapToGrid(nextY);
        if (gy != nextY) {
          nextY = gy;
          snappedY = true;
        }
      }
    }

    // Clamp
    final offsetX = _calculateOffsetX(canvasW); // Render space offset
    // Clamp needs to know Scaled Width if nextX is top-left
    // But wait, w/h passed here are already scaled?
    // Callers pass effectiveW/effectiveH.
    nextX = nextX.clamp(offsetX, math.max(offsetX, canvasW - w - offsetX));
    // wait, canvasW is usually full width. if offsetX > 0, right limit is canvasW - w - offsetX?
    // Actually simpler: clamp within available centered column.
    // Or just clamp to Safe Area?
    // Let's stick to simple safe clamp:
    nextX = nextX.clamp(offsetX, math.max(offsetX, canvasW - w));
    nextY = nextY.clamp(0.0, math.max(0.0, canvasH - h));

    return SnapResult(
      x: nextX,
      y: nextY,
      guideX: guideX,
      guideY: guideY,
    );
  }

  Widget _buildToolbarOverlay(
    BuildContext context,
    double canvasW,
    double canvasH,
  ) {
    if (!widget.editable) return const SizedBox.shrink();
    final id = _activeElementIdLocal;
    // Hide toolbar during inline editing or dragging (optional but cleaner)
    // The previous implementation didn't hide during drag (it moved), but DID hide during inline edit.
    // Also check for null id.
    if (id == null ||
        (id == _editingElementId && _inlineController != null) ||
        _draggingElementId == id) {
      return const SizedBox.shrink();
    }

    final el = _elements.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (el.isEmpty) return const SizedBox.shrink();

    final type = (el['type'] ?? 'text').toString();
    final x = (el['x'] as num?)?.toDouble() ?? 20.0;
    final y = (el['y'] as num?)?.toDouble() ?? 20.0;
    final w = (el['w'] as num?)?.toDouble() ?? 240.0;
    // Heights for toolbar positioning rely on TOP, so height isn't strictly needed for positioning,
    // but useful if we ever want to position below. We position ABOVE.

    final effectiveW = _effectiveWidth(type: type, w: w, canvasW: canvasW);
    final effectiveX = _effectiveLeft(x: x, w: effectiveW, canvasW: canvasW);
    // We only need top-left for the toolbar.
    // NOTE: In _buildElement we used _effectiveTop which is just y * scale.
    // but let's stick to the same method for consistency.
    // Pass 0 for h/canvasH since it doesn't affect top (it's y * scale).
    final effectiveY =
        _effectiveTop(y: y, h: 0, canvasW: canvasW, canvasH: canvasH);

    return Positioned(
      key: ValueKey('toolbar_$id'), // Ensure clean removal on delete
      top: effectiveY - 48, // 48px above the element
      left: effectiveX,
      child: CanvasElementToolbar(
        key: ValueKey('toolbar_content_$id'),
        type: type,
        properties: el,
        onDelete: () => _deleteElement(id),
        onDuplicate: () => _duplicateElement(id),
        onBringToFront: () => _bringToFront(id),
        onSendToBack: () => _sendToBack(id),
        onUpdate: (k, v) => _patchElement(id, {k: v}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heightMode = (widget.data['heightMode'] ?? 'fixed').toString();
    final vhPct = (widget.data['vhPct'] as num?)?.toDouble() ?? 0.7;
    final rawBlockHeight = heightMode == 'viewport'
        ? (MediaQuery.sizeOf(context).height * vhPct.clamp(0.2, 1.0).toDouble())
        : (widget.data['blockHeight'] as num?)?.toDouble() ??
            (widget.data['height'] as num?)?.toDouble() ??
            420.0;
    final bg =
        _parseHexColor(widget.data['backgroundColor'] as String?, Colors.white);
    final showGrid = (widget.data['showGrid'] as bool?) ?? true;
    final elements = _elements;

    final backgroundImageUrl =
        (widget.data['backgroundImageUrl'] ?? '').toString().trim();
    final backgroundVideoUrl =
        (widget.data['backgroundVideoUrl'] ?? '').toString().trim();
    final backgroundYoutubeId =
        (widget.data['backgroundYoutubeId'] ?? '').toString().trim();
    final overlayEnabled = (widget.data['overlayEnabled'] as bool?) ?? false;
    final overlayOpacity =
        (widget.data['overlayOpacity'] as num?)?.toDouble() ?? 0.35;
    final overlayColor = _parseHexColor(
      (widget.data['overlayColor'] ?? '#000000').toString(),
      Colors.black,
    );
    final backgroundFit =
        (widget.data['backgroundFit'] ?? 'cover').toString().toLowerCase();
    final fit = backgroundFit == 'contain' ? BoxFit.contain : BoxFit.cover;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final focalX =
        (widget.data[isMobile ? 'mobileFocalPointX' : 'focalPointX'] as num?)
                ?.toDouble() ??
            (widget.data['focalPointX'] as num?)?.toDouble() ??
            0.5;
    final focalY =
        (widget.data[isMobile ? 'mobileFocalPointY' : 'focalPointY'] as num?)
                ?.toDouble() ??
            (widget.data['focalPointY'] as num?)?.toDouble() ??
            0.5;
    final focalAlignment = Alignment(
      (focalX.clamp(0.0, 1.0) * 2) - 1,
      (focalY.clamp(0.0, 1.0) * 2) - 1,
    );

    // Use ConstraintLayoutBuilder OUTSIDE SizedBox to get actual available width first
    // Then scale the block height proportionally
    return ConstraintLayoutBuilder(
      builder: (context, outerConstraints) {
        final availableWidth = outerConstraints.maxWidth;
        final designW = _computeDesignWidth(availableWidth);
        final scaleX = designW > 0 ? availableWidth / designW : 1.0;

        // Scale the block height proportionally when width changes (zoom in/out)
        // This ensures the canvas maintains aspect ratio
        final blockHeight = heightMode == 'viewport'
            ? rawBlockHeight // Viewport mode: don't scale, use viewport percentage
            : rawBlockHeight *
                scaleX.clamp(0.5, 2.0); // Fixed mode: scale with width

        return SizedBox(
          height: blockHeight,
          child: Builder(
            builder: (context) {
              final canvasW = availableWidth;
              final canvasH = blockHeight;
              _reportCanvasSizeIfNeeded(canvasW, canvasH);
              // Don't use ClipRect - let content overflow if needed (especially galleries)
              // The Stack still clips but overflow is visible during editing
              return SizedBox(
                key: _canvasKey,
                width: canvasW,
                height: canvasH,
                child: Stack(
                  clipBehavior: Clip
                      .none, // Allow overflow so galleries don't get cut off
                  children: [
                    // Background tap detector - deselects active element AND selects the block
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Deselect any active element
                          final currentActive = _activeElementIdFromData();
                          if (currentActive != null &&
                              currentActive.isNotEmpty) {
                            _setActive(null);
                          }
                          // Also trigger block selection (so it works like other blocks)
                          widget.onBackgroundTap?.call();
                        },
                      ),
                    ),
                    // Background (color + image/video + overlay) + grid
                    Positioned.fill(
                      child: IgnorePointer(
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
                                  videoFileUrl: backgroundVideoUrl.isNotEmpty
                                      ? backgroundVideoUrl
                                      : null,
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
                                  alignment: focalAlignment,
                                  semanticLabel: widget
                                      .data['backgroundImageAltText']
                                      ?.toString(),
                                  errorBuilder: (context, _, __) =>
                                      const SizedBox.shrink(),
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
                                  gridColor:
                                      Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Drop target for editor panel canvas elements (drag from "Canvas (arrastrable)" section)
                    // MUST be above the background so it can receive hit tests.
                    if (widget.editable)
                      Positioned.fill(
                        child: DragTarget<String>(
                          onWillAcceptWithDetails: (data) =>
                              data.data.startsWith('canvas_el:'),
                          onAcceptWithDetails: (details) {
                            final payload = details.data;
                            if (!payload.startsWith('canvas_el:')) return;
                            final type = payload.replaceFirst('canvas_el:', '');

                            final ctx = _canvasKey.currentContext;
                            final box = ctx?.findRenderObject() as RenderBox?;
                            if (box == null || !box.attached || !box.hasSize) {
                              return;
                            }
                            final local = box.globalToLocal(details.offset);
                            _addElementAtCanvasOffset(
                                type, local, Size(canvasW, canvasH));
                          },
                          builder: (context, candidate, rejected) {
                            // Keep the DragTarget active without blocking normal interactions:
                            // only paint the overlay when dragging a compatible payload.
                            if (candidate.isEmpty) {
                              return const SizedBox.expand();
                            }
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color:
                                      widget.accentColor.withValues(alpha: 0.9),
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
                        isActive: _activeElementIdLocal != null &&
                            el['id'] == _activeElementIdLocal,
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

                    // Toolbar overlay (top-most layer)
                    _buildToolbarOverlay(context, canvasW, canvasH),
                  ],
                ), // Stack
              ); // Inner SizedBox
            },
          ), // Builder
        ); // Outer SizedBox
      },
    ); // LayoutBuilder
  }

  void _deleteElement(String id) {
    final shouldClearActive = _activeElementIdLocal == id;
    setState(() {
      _elements.removeWhere((e) => e['id'] == id);
      if (shouldClearActive) {
        _activeElementIdLocal = null;
      }
    });
    if (shouldClearActive) {
      widget.onActiveElementChanged?.call(null);
    }
    _commitElements();
  }

  void _duplicateElement(String id) {
    final original =
        _elements.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (original.isEmpty) return;

    final newId = _newElementId();
    final newEl = Map<String, dynamic>.from(original);
    newEl['id'] = newId;
    newEl['x'] = (newEl['x'] as double) + 20;
    newEl['y'] = (newEl['y'] as double) + 20;

    setState(() {
      _elements.add(newEl);
      _activeElementIdLocal = newId;
    });
    widget.onActiveElementChanged?.call(newId);
    _commitElements();
  }

  void _bringToFront(String id) {
    final idx = _elements.indexWhere((e) => e['id'] == id);
    if (idx == -1 || idx == _elements.length - 1) return;
    setState(() {
      final el = _elements.removeAt(idx);
      _elements.add(el);
    });
    _commitElements();
  }

  void _sendToBack(String id) {
    final idx = _elements.indexWhere((e) => e['id'] == id);
    if (idx == -1 || idx == 0) return;
    setState(() {
      final el = _elements.removeAt(idx);
      _elements.insert(0, el);
    });
    _commitElements();
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
    final scale = _calculateScale(canvasW);

    // Scale width and height proportionally for gallery elements so they fill properly
    final effectiveW = _effectiveWidth(type: type, w: w, canvasW: canvasW);
    final effectiveH =
        _effectiveHeight(type: type, h: h, canvasW: canvasW, canvasH: canvasH);

    final effectiveX = _effectiveLeft(x: x, w: effectiveW, canvasW: canvasW);

    // Element is active if it's the selected one OR if we are currently dragging/resizing it locally
    final isActive = (_activeElementIdLocal == id) ||
        (_draggingElementId == id) ||
        (_resizingElementId == id);
    final isHovered = _hoveredElementId == id;

    final isInlineEditing = widget.editable &&
        isActive &&
        _editingElementId == id &&
        _inlineController != null;

    Widget content;
    double?
        overrideHeight; // Allow dynamic height (e.g., products gallery) when content drives size
    switch (type) {
      case 'button':
        final label = (el['label'] ?? 'Botón').toString();
        final style =
            (el['style'] ?? 'filled').toString(); // filled|outline|text
        final link = (el['link'] ?? '/').toString();
        final fontSize = ((el['fontSize'] as num?)?.toDouble() ?? 14) * scale;
        final radius = ((el['radius'] as num?)?.toDouble() ?? 10) * scale;
        final bgColor =
            _parseHexColor(el['bgColor'] as String?, widget.accentColor);
        final fgColor = _parseHexColor(el['fgColor'] as String?, Colors.white);
        final letterSpacing = (el['letterSpacing'] as num?)?.toDouble() ?? 0.0;
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
            'text' => TextButton(
                onPressed: onPressed, style: buttonStyle, child: child),
            _ => ElevatedButton(
                onPressed: onPressed, style: buttonStyle, child: child),
          };
        }
        break;
      case 'image':
        final imageUrl = (el['imageUrl'] ?? '').toString().trim();
        final fitRaw = (el['fit'] ?? 'cover').toString();
        final fit = fitRaw == 'contain' ? BoxFit.contain : BoxFit.cover;
        final radius = ((el['radius'] as num?)?.toDouble() ?? 12) * scale;
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
            productSku: product['sku']?.toString(),
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
        final layout = (el['layout'] ?? 'grid').toString();
        final columns = (el['columns'] as num?)?.toInt() ?? 3;
        final cardWidth = (el['cardWidth'] as num?)?.toDouble() ?? 300.0;
        final rawIds = el['productIds'];
        final ids = rawIds is List
            ? rawIds
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];

        if (mode == 'manual' && ids.isNotEmpty) {
          _ensureProductsLoaded(ids.toSet());
        }

        // Pre-compute height target based on expected items (maxProducts) so it resizes with canvas
        final cols = columns.clamp(1, 4);
        final spacing = 20.0 * scale;
        final plannedCount = maxProducts.clamp(1, 50);
        final plannedRows = (plannedCount / cols).ceil().clamp(1, 50);
        final availableW = effectiveW;
        // Don't clamp max width, allow it to shrink with canvas
        final cardW = ((availableW - (cols - 1) * spacing) / cols)
            .clamp(10.0, double.infinity);
        const aspect = 0.75;
        final cardH = cardW / aspect;
        final galleryH = plannedRows * cardH + (plannedRows - 1) * spacing;

        // Save dynamic height so Positioned uses it (even before data loads)
        overrideHeight = galleryH;

        Widget buildGallery(List<Map<String, dynamic>> products) {
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
          if (layout == 'carousel') {
            final items = products.take(maxProducts).toList(growable: false);
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: widget.editable
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final p = items[index];
                final id = p['id']?.toString() ?? '';
                final name = p['name']?.toString() ?? 'Producto';
                final priceRaw = p['price'];
                final price = priceRaw is num
                    ? priceRaw.toDouble()
                    : double.tryParse('$priceRaw') ?? 0.0;
                final imageUrl = p['image_url']?.toString();
                return SizedBox(
                  width: cardWidth.clamp(220, 380),
                  child: PremiumProductCard(
                    productId: id,
                    productSku: p['sku']?.toString(),
                    name: name,
                    price: price,
                    imageUrl: imageUrl,
                    bodyFont: widget.bodyFont,
                    previewMode: widget.editable,
                    onNavigate: widget.onNavigate,
                  ),
                );
              },
            );
          }

          final itemCount = products.take(maxProducts).length;

          return SizedBox(
            height: galleryH,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: aspect,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: itemCount,
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
                  productSku: p['sku']?.toString(),
                  name: name,
                  price: price,
                  imageUrl: imageUrl,
                  bodyFont: widget.bodyFont,
                  previewMode: widget.editable,
                  onNavigate: widget.onNavigate,
                );
              },
            ),
          );
        }

        if (mode == 'latest') {
          content = FutureBuilder<List<Map<String, dynamic>>>(
            future: _getCachedLatestProducts(maxProducts),
            builder: (context, snap) => buildGallery(snap.data ?? []),
          );
        } else {
          final manualProducts = ids
              .map((id) => _productCache[id])
              .whereType<Map<String, dynamic>>()
              .toList();
          content = buildGallery(manualProducts);
        }
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
        final fontStyle =
            (el['fontStyle'] == 'italic') ? FontStyle.italic : FontStyle.normal;
        final decoration = (el['decoration'] == 'underline')
            ? TextDecoration.underline
            : TextDecoration.none;

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
                fontStyle: fontStyle,
                decoration: decoration,
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
                fontStyle: fontStyle,
                decoration: decoration,
                color: color,
                height: 1.1,
              ),
            ),
          );
        }
    }

    // Show resize handle if editable, active, and not inline editing
    final showResizeHandle = widget.editable && isActive && !isInlineEditing;

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

    // Determine border/bg color based on state
    final borderColor = widget.editable
        ? (isActive
            ? widget.accentColor
            : isHovered
                ? widget.accentColor.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.08))
        : null;

    final borderWidth = widget.editable && isActive ? 2.0 : 1.0;

    final bgColor = widget.editable
        ? (isActive
            ? Colors.white.withValues(alpha: 0.14)
            : isHovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.06))
        : null;

    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
        color: bgColor,
      ),
      child: SizedBox.expand(child: content),
    );

    // Always use a Stack in edit mode to maintain widget tree stability for gestures
    final decoratedWithHandles = widget.editable
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: decorated),
              if (showResizeHandle)
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

    final resolvedHeight = overrideHeight ?? effectiveH;
    final effectiveY = _effectiveTop(
        y: y, h: resolvedHeight, canvasW: canvasW, canvasH: canvasH);

    return Positioned(
      key: ValueKey('canvas_el_$id'),
      left: effectiveX,
      top: effectiveY,
      width: effectiveW,
      height: resolvedHeight,
      child: widget.editable
          ? MouseRegion(
              onEnter: (_) => setState(() => _hoveredElementId = id),
              onExit: (_) => setState(() {
                if (_hoveredElementId == id) _hoveredElementId = null;
              }),
              child: Listener(
                onPointerDown: (e) {
                  _lastPointerButtons = e.buttons;
                },
                onPointerUp: (_) => _lastPointerButtons = 0,
                onPointerCancel: (_) => _lastPointerButtons = 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setActive(id),
                  onDoubleTap: () => _startInlineEdit(type: type, el: el),
                  onPanStart: (d) {
                    // Ignore trackpad scroll/pan (usually has 0 buttons pressed)
                    // Only allow drag if a button is pressed (primary, secondary, etc)
                    if (_lastPointerButtons == 0) return;

                    if (_resizingElementId == id) return;
                    if (_editingElementId == id) return;
                    setState(() {
                      _draggingElementId = id;
                      _dragAnchorInElement = d.localPosition;
                      _pointerCanvasPos =
                          Offset(effectiveX, effectiveY) + d.localPosition;
                      _axisLock = _AxisLock.none;
                    });
                    // DO NOT call _setActive(id) here.
                    // It triggers parent rebuilds which can cancel the drag gesture.
                    // We rely on visual feedback via _draggingElementId and commit selection on DragEnd.
                  },
                  onPanUpdate: (d) {
                    if (_resizingElementId == id) return;
                    if (_editingElementId == id) return;
                    if (_draggingElementId != id) return;
                    if (_dragAnchorInElement == null ||
                        _pointerCanvasPos == null) {
                      // Fallback: delta-based movement (should be rare)
                      final current = _elements.firstWhere(
                        (e) => e['id']?.toString() == id,
                        orElse: () => el,
                      );
                      final cx = (current['x'] as num?)?.toDouble() ?? x;
                      final cy = (current['y'] as num?)?.toDouble() ?? y;
                      final cxRender =
                          _effectiveLeft(x: cx, w: w, canvasW: canvasW);
                      final nextX = cxRender + d.delta.dx;
                      final nextY = cy + d.delta.dy;
                      setState(() {
                        _updateElementPosition(
                            id, nextX, nextY, canvasW, canvasH,
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
                    final desiredTopLeft =
                        _pointerCanvasPos! - _dragAnchorInElement!;
                    final nextX = desiredTopLeft.dx;
                    final nextY = desiredTopLeft.dy;

                    // Live Snapping: calculate position AND guides
                    final snapResult = _calculateSnappedPosition(
                      elementId: id,
                      x: nextX,
                      y: nextY,
                      w: effectiveW,
                      h: resolvedHeight,
                      canvasW: canvasW,
                      canvasH: canvasH,
                    );

                    if (_guideX == snapResult.guideX &&
                        _guideY == snapResult.guideY) {
                      // no guide change, but position might change if snapped
                    } else {
                      // Only update guides if changed
                      // can't do setState here because we are in onPanUpdate which is a callback
                      // actually onPanUpdate is called frequently.
                      // We need to setState anyway to move the element.
                    }

                    setState(() {
                      // Move element to SNAPPED position immediately = Magnetic Feel
                      _updateElementPosition(
                          id, snapResult.x, snapResult.y, canvasW, canvasH,
                          applySnap: false); // applied in calc!

                      _guideX = snapResult.guideX;
                      _guideY = snapResult.guideY;
                    });
                  },
                  onPanEnd: (_) {
                    // Commit selection now that drag is done
                    _setActive(id);

                    setState(() {
                      _draggingElementId = null;
                      _dragAnchorInElement = null;
                      _pointerCanvasPos = null;
                      _axisLock = _AxisLock.none;
                      _guideX = null;
                      _guideY = null;
                      // No need to update position here, it's already snapped by onPanUpdate
                    });
                    _commitElements();
                  },
                  child: decoratedWithHandles,
                ),
              ),
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
    final initial =
        (el[field] ?? (type == 'button' ? 'Botón' : 'Texto')).toString();

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
      // _patchElement already calls setState() and schedules a commit.
      _patchElement(id, {field: next});
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
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    if (widget.type == 'fadeUp') {
      final offset =
          Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
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
