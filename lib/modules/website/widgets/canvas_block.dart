import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_action.dart';
import '../models/canvas_element_factory.dart';
import '../models/website_editor_drag_payload.dart';
import '../services/website_background_removal_service.dart';
import 'canvas_block_toolbar.dart';
import 'website_background_removal_dialog.dart';
import 'website_action_button.dart';
import 'website_media_picker.dart';

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
///   - type: "text" | "button" | "image" | "shape" | "product" |
///     "productsGallery"
///   - x, y, w, h: numbers (px)
///   - hideOnMobile/showOnMobile: responsive visibility (optional)
///   - rotation: degrees (-180..180)
///   - image layers: fit, focalPointX/focalPointY (0..1)
///   - ... type-specific fields
/// - constrainElementsToSafeArea: bool (defaults true; false permits bleed)
class CanvasBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool editable;
  final Color accentColor;
  final ValueChanged<List<Map<String, dynamic>>>? onElementsChanged;
  final ValueChanged<String?>? onActiveElementChanged;
  final ValueChanged<Size>? onCanvasSizeChanged;
  final void Function(String route)? onNavigate;
  final String? tenantId;
  final String? headingFont;
  final String? bodyFont;
  final VoidCallback? onBackgroundTap;
  final bool fillAvailableHeight;
  final bool clipContentToBounds;

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
    this.headingFont,
    this.bodyFont,
    this.onBackgroundTap,
    this.fillAvailableHeight = false,
    this.clipContentToBounds = false,
  });

  @override
  State<CanvasBlock> createState() => _CanvasBlockState();
}

class _CanvasBlockState extends State<CanvasBlock> {
  final GlobalKey _canvasKey = GlobalKey();
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'Canvas editor');
  late List<Map<String, dynamic>> _elements;
  String? _activeElementIdLocal;
  String? _backgroundRemovalElementId;

  bool _commitScheduled = false;
  List<Map<String, dynamic>>? _pendingElementsCommit;

  Size? _lastReportedCanvasSize;
  Size? _pendingCanvasSizeReport;
  bool _isCanvasSizeReportScheduled = false;

  String? _draggingElementId;
  String? _resizingElementId;
  String? _rotatingElementId;
  String? _croppingElementId;
  String? _reframingElementId;

  _CanvasFrameHandle? _activeFrameHandle;
  Rect? _frameStartRect;
  Offset? _frameStartPointer;
  double? _frameStartRotation;
  Offset? _rotationCenter;
  double? _rotationStartPointerAngle;
  double? _rotationStartDegrees;

  // Drag anchor so the cursor stays "attached" to the element while moving.
  Offset? _dragAnchorInElement; // local offset inside the element at drag start
  Offset? _pointerCanvasPos; // pointer position in canvas coordinates
  _AxisLock _axisLock = _AxisLock.none;

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
    _canvasFocusNode.dispose();
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
        _rotatingElementId != null ||
        _reframingElementId != null ||
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
    if (_activeElementIdLocal == id) {
      // Re-emit the selection so an already-active element can restore its
      // parent block/inspector context after another surface cleared it.
      widget.onActiveElementChanged?.call(id);
      if (id != null && widget.editable) {
        _canvasFocusNode.requestFocus();
      }
      return;
    }
    setState(() {
      _activeElementIdLocal = id;
      if (_croppingElementId != id) {
        _croppingElementId = null;
      }
    });
    widget.onActiveElementChanged?.call(id);
    if (id != null && widget.editable) {
      _canvasFocusNode.requestFocus();
    }
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
    final raw = canvasW < 600 && widget.data['mobileDesignWidth'] != null
        ? widget.data['mobileDesignWidth']
        : widget.data['designWidth'];
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
    return createCanvasElement(id: _newElementId(), type: type);
  }

  void _addElementAtCanvasOffset(
      String type, Offset localPos, Size canvasSize) {
    final el = _defaultElement(type);
    final w = (el['w'] as num?)?.toDouble() ?? 200;
    final h = (el['h'] as num?)?.toDouble() ?? 56;
    final scale = math.max(_calculateScale(canvasSize.width), 0.0001);
    final offsetX = _calculateOffsetX(canvasSize.width);
    final designWidth = _computeDesignWidth(canvasSize.width);
    final designHeight = canvasSize.height / scale;

    // Convert the pointer to design coordinates before applying design-space
    // element bounds. Mixing rendered pixels with design-unit widths creates
    // an artificial right/bottom limit whenever the Canvas is scaled.
    final pointerX = (localPos.dx - offsetX) / scale;
    final pointerY = localPos.dy / scale;
    final constrain = widget.data['constrainElementsToSafeArea'] != false;
    final maxX = constrain
        ? math.max(0.0, designWidth - w)
        : math.max(0.0, designWidth - 32.0);
    final maxY = constrain
        ? math.max(0.0, designHeight - h)
        : math.max(0.0, designHeight - 32.0);

    el['x'] = pointerX.clamp(0.0, maxX);
    el['y'] = pointerY.clamp(0.0, maxY);

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

  double _normalizedRotation(double degrees) {
    var value = degrees % 360;
    if (value > 180) value -= 360;
    if (value <= -180) value += 360;
    return value;
  }

  void _rotateQuarterTurn(String elementId) {
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == elementId,
      orElse: () => <String, dynamic>{},
    );
    if (element.isEmpty || element['locked'] == true) return;
    final current = (element['rotation'] as num?)?.toDouble() ?? 0;
    _patchElement(elementId, {
      'rotation': _normalizedRotation(current + 90),
    });
  }

  void _toggleCropMode(String elementId) {
    final index =
        _elements.indexWhere((item) => item['id']?.toString() == elementId);
    if (index == -1 || _elements[index]['type'] != 'image') return;
    if (_elements[index]['locked'] == true) return;
    final enabling = _croppingElementId != elementId;
    setState(() {
      _croppingElementId = enabling ? elementId : null;
      _reframingElementId = null;
      if (enabling) {
        _elements[index] = {
          ..._elements[index],
          'fit': 'cover',
          'focalPointX':
              (_elements[index]['focalPointX'] as num?)?.toDouble() ?? 0.5,
          'focalPointY':
              (_elements[index]['focalPointY'] as num?)?.toDouble() ?? 0.5,
        };
      }
    });
    _setActive(elementId);
    if (enabling) _commitElements();
  }

  void _resetImageFrame(String elementId) {
    _patchElement(elementId, {
      'fit': 'cover',
      'focalPointX': 0.5,
      'focalPointY': 0.5,
    });
  }

  Future<void> _replaceImage(String elementId) async {
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == elementId,
      orElse: () => <String, dynamic>{},
    );
    if (element.isEmpty || element['locked'] == true) return;
    final selection = await showWebsiteMediaPicker(
      context: context,
      currentUrl: element['imageUrl']?.toString(),
    );
    if (!mounted || selection == null) return;
    _patchElement(elementId, {
      'imageUrl': selection.publicUrl,
      'imageSource': 'manual',
      'backgroundRemovalActive': false,
      'fit': element['fit'] ?? 'contain',
    });
  }

  Future<void> _removeImageBackground(String elementId) async {
    final index =
        _elements.indexWhere((item) => item['id']?.toString() == elementId);
    if (index == -1 || _elements[index]['type'] != 'image') return;
    final element = _elements[index];
    if (element['locked'] == true) return;
    final imageUrl = (element['imageUrl'] ?? '').toString().trim();
    if (imageUrl.isEmpty || _backgroundRemovalElementId != null) return;

    setState(() => _backgroundRemovalElementId = elementId);
    try {
      final selection = await showWebsiteBackgroundRemovalDialog(
        context: context,
        imageUrl: imageUrl,
        tenantId: widget.tenantId,
      );
      if (!mounted || selection == null) return;

      final service = WebsiteBackgroundRemovalService();
      final resultUrl = selection.imageUrl ??
          await service.uploadTransparentPng(
            selection.pngBytes!,
            prefix: 'canvas-no-bg',
          );
      if (!mounted) return;

      final originalUrl =
          (element['backgroundRemovalOriginalUrl'] ?? '').toString().trim();
      _patchElement(elementId, {
        'imageUrl': resultUrl,
        'imageSource': 'manual',
        'backgroundRemovalOriginalUrl':
            originalUrl.isEmpty ? imageUrl : originalUrl,
        'backgroundRemovalMethod': selection.method,
        'backgroundRemovalActive': true,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fondo eliminado y PNG guardado en la biblioteca.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backgroundRemovalElementId = null);
      }
    }
  }

  void _restoreImageBeforeBackgroundRemoval(String elementId) {
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == elementId,
      orElse: () => <String, dynamic>{},
    );
    final originalUrl =
        (element['backgroundRemovalOriginalUrl'] ?? '').toString().trim();
    if (originalUrl.isEmpty) return;
    _patchElement(elementId, {
      'imageUrl': originalUrl,
      'imageSource': 'manual',
      'backgroundRemovalActive': false,
    });
  }

  void _moveForward(String id) {
    final index = _elements.indexWhere((element) => element['id'] == id);
    if (index == -1 || index >= _elements.length - 1) return;
    setState(() {
      final element = _elements.removeAt(index);
      _elements.insert(index + 1, element);
    });
    _commitElements();
  }

  void _moveBackward(String id) {
    final index = _elements.indexWhere((element) => element['id'] == id);
    if (index <= 0) return;
    setState(() {
      final element = _elements.removeAt(index);
      _elements.insert(index - 1, element);
    });
    _commitElements();
  }

  void _alignElement(
    String id,
    CanvasElementAlignment alignment,
    double canvasW,
    double canvasH,
  ) {
    final index =
        _elements.indexWhere((element) => element['id']?.toString() == id);
    if (index == -1 || _elements[index]['locked'] == true) return;
    final element = _elements[index];
    final width = (element['w'] as num?)?.toDouble() ?? 200;
    final height = (element['h'] as num?)?.toDouble() ?? 56;
    final scale = _calculateScale(canvasW);
    final designWidth = _computeDesignWidth(canvasW);
    final designHeight = canvasH / math.max(scale, 0.0001);
    var x = (element['x'] as num?)?.toDouble() ?? 0;
    var y = (element['y'] as num?)?.toDouble() ?? 0;

    switch (alignment) {
      case CanvasElementAlignment.left:
        x = 0;
        break;
      case CanvasElementAlignment.horizontalCenter:
        x = (designWidth - width) / 2;
        break;
      case CanvasElementAlignment.right:
        x = designWidth - width;
        break;
      case CanvasElementAlignment.top:
        y = 0;
        break;
      case CanvasElementAlignment.verticalCenter:
        y = (designHeight - height) / 2;
        break;
      case CanvasElementAlignment.bottom:
        y = designHeight - height;
        break;
    }

    _patchElement(id, {'x': x, 'y': y});
  }

  Offset? _canvasPointer(Offset globalPosition) {
    final renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
      return null;
    }
    return renderBox.globalToLocal(globalPosition);
  }

  void _startFrameGesture(
    String id,
    _CanvasFrameHandle handle,
    Offset globalPosition,
  ) {
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    final pointer = _canvasPointer(globalPosition);
    if (element.isEmpty || pointer == null || element['locked'] == true) return;
    setState(() {
      _resizingElementId = id;
      _activeFrameHandle = handle;
      _frameStartRect = Rect.fromLTWH(
        (element['x'] as num?)?.toDouble() ?? 0,
        (element['y'] as num?)?.toDouble() ?? 0,
        (element['w'] as num?)?.toDouble() ?? 200,
        (element['h'] as num?)?.toDouble() ?? 56,
      );
      _frameStartPointer = pointer;
      _frameStartRotation = (element['rotation'] as num?)?.toDouble() ?? 0;
      _guideX = null;
      _guideY = null;
    });
    _canvasFocusNode.requestFocus();
  }

  void _updateFrameGesture(
    String id,
    String type,
    Offset globalPosition,
    double canvasW,
    double canvasH, {
    required bool cropMode,
  }) {
    if (_resizingElementId != id ||
        _activeFrameHandle == null ||
        _frameStartRect == null ||
        _frameStartPointer == null) {
      return;
    }
    final pointer = _canvasPointer(globalPosition);
    if (pointer == null) return;
    final scale = _calculateScale(canvasW);
    final rawDelta = pointer - _frameStartPointer!;
    final radians = -((_frameStartRotation ?? 0) * math.pi / 180);
    final localDelta = Offset(
          rawDelta.dx * math.cos(radians) - rawDelta.dy * math.sin(radians),
          rawDelta.dx * math.sin(radians) + rawDelta.dy * math.cos(radians),
        ) /
        math.max(scale, 0.0001);
    final start = _frameStartRect!;
    final handle = _activeFrameHandle!;
    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;

    if (handle.affectsLeft) left += localDelta.dx;
    if (handle.affectsRight) right += localDelta.dx;
    if (handle.affectsTop) top += localDelta.dy;
    if (handle.affectsBottom) bottom += localDelta.dy;

    final minWidth = type == 'button' ? 120.0 : 40.0;
    final minHeight = type == 'button' ? 44.0 : 32.0;
    if (right - left < minWidth) {
      if (handle.affectsLeft) {
        left = right - minWidth;
      } else {
        right = left + minWidth;
      }
    }
    if (bottom - top < minHeight) {
      if (handle.affectsTop) {
        top = bottom - minHeight;
      } else {
        bottom = top + minHeight;
      }
    }

    if (!cropMode && handle.isCorner && _isShiftPressed()) {
      final ratio = start.width / math.max(start.height, 1);
      if ((right - left - start.width).abs() >=
          (bottom - top - start.height).abs()) {
        final targetHeight = (right - left) / ratio;
        if (handle.affectsTop) {
          top = bottom - targetHeight;
        } else {
          bottom = top + targetHeight;
        }
      } else {
        final targetWidth = (bottom - top) * ratio;
        if (handle.affectsLeft) {
          left = right - targetWidth;
        } else {
          right = left + targetWidth;
        }
      }
    }

    final localFrame = Rect.fromLTRB(left, top, right, bottom);
    final localCenterShift = localFrame.center - start.center;
    final rotationRadians = (_frameStartRotation ?? 0) * math.pi / 180;
    final rotatedCenterShift = Offset(
      localCenterShift.dx * math.cos(rotationRadians) -
          localCenterShift.dy * math.sin(rotationRadians),
      localCenterShift.dx * math.sin(rotationRadians) +
          localCenterShift.dy * math.cos(rotationRadians),
    );
    final nextCenter = start.center + rotatedCenterShift;
    final nextWidth = localFrame.width;
    final nextHeight = localFrame.height;
    var nextX = nextCenter.dx - nextWidth / 2;
    var nextY = nextCenter.dy - nextHeight / 2;

    if (widget.data['constrainElementsToSafeArea'] != false) {
      final designWidth = _computeDesignWidth(canvasW);
      final designHeight = canvasH / math.max(scale, 0.0001);
      nextX = nextX.clamp(0.0, math.max(0.0, designWidth - nextWidth));
      nextY = nextY.clamp(0.0, math.max(0.0, designHeight - nextHeight));
    }

    setState(() {
      final index =
          _elements.indexWhere((item) => item['id']?.toString() == id);
      if (index == -1) return;
      _elements[index] = {
        ..._elements[index],
        'x': nextX,
        'y': nextY,
        'w': nextWidth,
        'h': nextHeight,
      };
    });
  }

  void _endFrameGesture() {
    if (_resizingElementId == null) return;
    setState(() {
      _resizingElementId = null;
      _activeFrameHandle = null;
      _frameStartRect = null;
      _frameStartPointer = null;
      _frameStartRotation = null;
    });
    _commitElements();
  }

  void _startRotation(
    String id,
    Offset globalPosition,
    double canvasW,
    double canvasH,
  ) {
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    final pointer = _canvasPointer(globalPosition);
    if (element.isEmpty || pointer == null || element['locked'] == true) return;
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final width = (element['w'] as num?)?.toDouble() ?? 200;
    final height = (element['h'] as num?)?.toDouble() ?? 56;
    final center = Offset(
      _effectiveLeft(x: x, w: width, canvasW: canvasW) +
          _effectiveWidth(
                  type: element['type']?.toString() ?? 'text',
                  w: width,
                  canvasW: canvasW) /
              2,
      _effectiveTop(y: y, h: height, canvasW: canvasW, canvasH: canvasH) +
          _effectiveHeight(
                  type: element['type']?.toString() ?? 'text',
                  h: height,
                  canvasW: canvasW,
                  canvasH: canvasH) /
              2,
    );
    setState(() {
      _rotatingElementId = id;
      _rotationCenter = center;
      _rotationStartPointerAngle =
          math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
      _rotationStartDegrees = (element['rotation'] as num?)?.toDouble() ?? 0;
    });
    _canvasFocusNode.requestFocus();
  }

  void _updateRotation(String id, Offset globalPosition) {
    if (_rotatingElementId != id ||
        _rotationCenter == null ||
        _rotationStartPointerAngle == null ||
        _rotationStartDegrees == null) {
      return;
    }
    final pointer = _canvasPointer(globalPosition);
    if (pointer == null) return;
    final currentAngle = math.atan2(
      pointer.dy - _rotationCenter!.dy,
      pointer.dx - _rotationCenter!.dx,
    );
    var degrees = _normalizedRotation(
      _rotationStartDegrees! +
          (currentAngle - _rotationStartPointerAngle!) * 180 / math.pi,
    );
    if (_isShiftPressed()) {
      degrees = (degrees / 15).round() * 15.0;
    }
    setState(() {
      final index =
          _elements.indexWhere((item) => item['id']?.toString() == id);
      if (index == -1) return;
      _elements[index] = {..._elements[index], 'rotation': degrees};
    });
  }

  void _endRotation() {
    if (_rotatingElementId == null) return;
    setState(() {
      _rotatingElementId = null;
      _rotationCenter = null;
      _rotationStartPointerAngle = null;
      _rotationStartDegrees = null;
    });
    _commitElements();
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.editable || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final activeId = _activeElementIdLocal;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_croppingElementId != null) {
        setState(() => _croppingElementId = null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (activeId == null || _editingElementId != null) {
      return KeyEventResult.ignored;
    }
    if (_croppingElementId == activeId &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      setState(() => _croppingElementId = null);
      return KeyEventResult.handled;
    }

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final commandPressed = keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (commandPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      _duplicateElement(activeId);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteElement(activeId);
      return KeyEventResult.handled;
    }

    final dx = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1.0,
      LogicalKeyboardKey.arrowRight => 1.0,
      _ => 0.0,
    };
    final dy = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1.0,
      LogicalKeyboardKey.arrowDown => 1.0,
      _ => 0.0,
    };
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    final index = _elements
        .indexWhere((element) => element['id']?.toString() == activeId);
    if (index == -1 || _elements[index]['locked'] == true) {
      return KeyEventResult.handled;
    }
    final renderBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return KeyEventResult.ignored;
    }
    final step = _isShiftPressed() ? 10.0 : 1.0;
    final element = _elements[index];
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final scale = _calculateScale(renderBox.size.width);
    setState(() {
      _updateElementPosition(
        activeId,
        _designToRenderX(
          x: x + dx * step,
          canvasW: renderBox.size.width,
        ),
        (y + dy * step) * scale,
        renderBox.size.width,
        renderBox.size.height,
        applySnap: false,
      );
    });
    _commitElements();
    return KeyEventResult.handled;
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

    // Clamp in render space. Constrained layers stay inside the visible safe
    // area; unconstrained layers may bleed beyond it while keeping a grab
    // target visible so they cannot be lost completely off-canvas.
    final scaledW = w * scaleX;
    final scaledH = h * scaleX;
    final constrainToCanvas =
        widget.data['constrainElementsToSafeArea'] != false;
    if (constrainToCanvas) {
      nextX = nextX.clamp(
        offsetX,
        math.max(offsetX, maxW - offsetX - scaledW),
      );
      nextY = nextY.clamp(0.0, math.max(0.0, maxH - scaledH));
    } else {
      final visibleX = math.min(32.0, math.max(12.0, scaledW));
      final visibleY = math.min(32.0, math.max(12.0, scaledH));
      nextX = nextX.clamp(-scaledW + visibleX, maxW - visibleX);
      nextY = nextY.clamp(-scaledH + visibleY, maxH - visibleY);
    }

    // Convert back to design space: subtract offset, then divide by scale
    final designX = (nextX - offsetX) / scaleX;
    final designY = nextY / scaleX;

    _elements[idx] = {
      ..._elements[idx],
      'x': designX,
      'y': designY,
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
    final safeOffsetX = _calculateOffsetX(canvasW);
    final canvasTargetsX = [
      safeOffsetX,
      canvasW / 2,
      canvasW - safeOffsetX,
    ];
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

    final constrainToCanvas =
        widget.data['constrainElementsToSafeArea'] != false;
    if (constrainToCanvas) {
      nextX = nextX.clamp(
        safeOffsetX,
        math.max(safeOffsetX, canvasW - safeOffsetX - w),
      );
      nextY = nextY.clamp(0.0, math.max(0.0, canvasH - h));
    } else {
      final visibleX = math.min(32.0, math.max(12.0, w));
      final visibleY = math.min(32.0, math.max(12.0, h));
      nextX = nextX.clamp(-w + visibleX, canvasW - visibleX);
      nextY = nextY.clamp(-h + visibleY, canvasH - visibleY);
    }

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
        _draggingElementId == id ||
        _resizingElementId == id ||
        _rotatingElementId == id ||
        _reframingElementId == id) {
      return const SizedBox.shrink();
    }

    final el = _elements.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (el.isEmpty) return const SizedBox.shrink();

    final type = (el['type'] ?? 'text').toString();
    final x = (el['x'] as num?)?.toDouble() ?? 20.0;
    final y = (el['y'] as num?)?.toDouble() ?? 20.0;
    final w = (el['w'] as num?)?.toDouble() ?? 240.0;
    final h = (el['h'] as num?)?.toDouble() ?? 56.0;

    final effectiveW = _effectiveWidth(type: type, w: w, canvasW: canvasW);
    final effectiveH = _effectiveHeight(
      type: type,
      h: h,
      canvasW: canvasW,
      canvasH: canvasH,
    );
    final effectiveX = _effectiveLeft(x: x, w: effectiveW, canvasW: canvasW);
    // We only need top-left for the toolbar.
    // NOTE: In _buildElement we used _effectiveTop which is just y * scale.
    // but let's stick to the same method for consistency.
    // Pass 0 for h/canvasH since it doesn't affect top (it's y * scale).
    final effectiveY =
        _effectiveTop(y: y, h: 0, canvasW: canvasW, canvasH: canvasH);

    final toolbarTop = effectiveY >= 68
        ? effectiveY - 60
        : math.min(canvasH - 44, effectiveY + effectiveH + 12);
    // Every contextual palette (including the alignment drill-in) shares this
    // maximum. The toolbar itself becomes horizontally scrollable below this
    // width instead of escaping the canvas or creating a popup overlay.
    final estimatedToolbarWidth = math.min(
      424.0,
      math.max(120.0, canvasW - 16),
    );
    final toolbarLeft = effectiveX
        .clamp(
          8.0,
          math.max(8.0, canvasW - estimatedToolbarWidth - 8),
        )
        .toDouble();

    return Positioned(
      key: ValueKey('toolbar_$id'), // Ensure clean removal on delete
      top: toolbarTop,
      left: toolbarLeft,
      child: CanvasElementToolbar(
        key: ValueKey('toolbar_content_$id'),
        type: type,
        properties: el,
        onDelete: () => _deleteElement(id),
        onDuplicate: () => _duplicateElement(id),
        onBringToFront: () => _bringToFront(id),
        onSendToBack: () => _sendToBack(id),
        onMoveForward: () => _moveForward(id),
        onMoveBackward: () => _moveBackward(id),
        onRotateQuarterTurn: () => _rotateQuarterTurn(id),
        onAlign: (alignment) => _alignElement(id, alignment, canvasW, canvasH),
        cropActive: _croppingElementId == id,
        maxWidth: math.max(120.0, canvasW - 16),
        hoverLabelBelow: toolbarTop + 68 <= canvasH,
        onToggleCrop: type == 'image' && el['locked'] != true
            ? () => _toggleCropMode(id)
            : null,
        onReplaceImage: type == 'image' && el['locked'] != true
            ? () => _replaceImage(id)
            : null,
        onResetImageFrame: type == 'image' ? () => _resetImageFrame(id) : null,
        onRemoveBackground: type == 'image' &&
                el['locked'] != true &&
                (el['imageUrl'] ?? '').toString().trim().isNotEmpty
            ? () => _removeImageBackground(id)
            : null,
        onRestoreOriginalImage: type == 'image' &&
                el['backgroundRemovalActive'] == true &&
                (el['backgroundRemovalOriginalUrl'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty
            ? () => _restoreImageBeforeBackgroundRemoval(id)
            : null,
        backgroundRemovalBusy: _backgroundRemovalElementId == id,
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
    return Focus(
      focusNode: _canvasFocusNode,
      onKeyEvent: _handleCanvasKeyEvent,
      child: ConstraintLayoutBuilder(
        builder: (context, outerConstraints) {
          final availableWidth = outerConstraints.maxWidth;
          final designW = _computeDesignWidth(availableWidth);
          final scaleX = designW > 0 ? availableWidth / designW : 1.0;

          // Scale the block height proportionally when width changes (zoom in/out)
          // This ensures the canvas maintains aspect ratio
          final blockHeight = widget.fillAvailableHeight &&
                  outerConstraints.maxHeight.isFinite
              ? outerConstraints.maxHeight
              : heightMode == 'viewport'
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
                                    youtubeVideoId:
                                        backgroundYoutubeId.isNotEmpty
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

                      // The fixed design coordinate system is narrower than a
                      // very wide editor viewport so editor and public rendering
                      // remain aligned. Show that boundary instead of enforcing
                      // an invisible drag limit.
                      if (widget.editable && _calculateOffsetX(canvasW) > 0.5)
                        Positioned(
                          left: _calculateOffsetX(canvasW),
                          top: 0,
                          bottom: 0,
                          width: canvasW - (_calculateOffsetX(canvasW) * 2),
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.symmetric(
                                  vertical: BorderSide(
                                    color: widget.accentColor
                                        .withValues(alpha: 0.34),
                                  ),
                                ),
                              ),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(top: 6, right: 8),
                              child: Text(
                                'ÁREA SEGURA',
                                style: TextStyle(
                                  color: widget.accentColor
                                      .withValues(alpha: 0.65),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Drop target for editor panel canvas elements (drag from "Canvas (arrastrable)" section)
                      // MUST be above the background so it can receive hit tests.
                      if (widget.editable)
                        Positioned.fill(
                          child: DragTarget<WebsiteEditorDragPayload>(
                            onWillAcceptWithDetails: (data) =>
                                data.data is CanvasElementDragPayload,
                            onAcceptWithDetails: (details) {
                              final payload = details.data;
                              if (payload is! CanvasElementDragPayload) return;
                              final type = payload.elementType;

                              final ctx = _canvasKey.currentContext;
                              final box = ctx?.findRenderObject() as RenderBox?;
                              if (box == null ||
                                  !box.attached ||
                                  !box.hasSize) {
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
                                    color: widget.accentColor
                                        .withValues(alpha: 0.9),
                                    width: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      // Elements use their own clipping boundary so transformed
                      // content can be contained by carousel slides without
                      // clipping editor toolbars or standalone Canvas blocks.
                      Positioned.fill(
                        child: Stack(
                          clipBehavior: widget.clipContentToBounds
                              ? Clip.hardEdge
                              : Clip.none,
                          children: [
                            for (final el in elements)
                              if (!((canvasW < 600 &&
                                      el['hideOnMobile'] == true) ||
                                  (canvasW >= 600 &&
                                      el['showOnMobile'] == true)))
                                _buildElement(
                                  context: context,
                                  el: el,
                                  isActive: _activeElementIdLocal != null &&
                                      el['id'] == _activeElementIdLocal,
                                  canvasW: canvasW,
                                  canvasH: canvasH,
                                ),
                          ],
                        ),
                      ),

                      // Selection chrome is intentionally above the bounded
                      // content clip. Rotated content stays inside the slide,
                      // while edge/corner handles remain reachable at all four
                      // canvas boundaries.
                      _buildActiveElementChrome(canvasW, canvasH),

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
      ),
    );
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

  Widget _buildFrameHandle({
    required String id,
    required String type,
    required _CanvasFrameHandle handle,
    required double canvasW,
    required double canvasH,
    required bool cropMode,
  }) {
    final isHorizontalEdge =
        handle == _CanvasFrameHandle.top || handle == _CanvasFrameHandle.bottom;
    final isVerticalEdge =
        handle == _CanvasFrameHandle.left || handle == _CanvasFrameHandle.right;
    final visualWidth = isVerticalEdge ? 5.0 : (isHorizontalEdge ? 18.0 : 10.0);
    final visualHeight =
        isHorizontalEdge ? 5.0 : (isVerticalEdge ? 18.0 : 10.0);
    return Align(
      alignment: handle.alignment,
      child: Transform.translate(
        offset: handle.outwardOffset,
        child: MouseRegion(
          cursor: handle.cursor,
          child: GestureDetector(
            key: ValueKey('${cropMode ? 'crop' : 'resize'}_${handle.name}_$id'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) =>
                _startFrameGesture(id, handle, details.globalPosition),
            onPanUpdate: (details) => _updateFrameGesture(
              id,
              type,
              details.globalPosition,
              canvasW,
              canvasH,
              cropMode: cropMode,
            ),
            onPanEnd: (_) => _endFrameGesture(),
            onPanCancel: _endFrameGesture,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Align(
                alignment: handle.alignment,
                child: Container(
                  width: visualWidth,
                  height: visualHeight,
                  decoration: BoxDecoration(
                    color: cropMode ? Colors.white : widget.accentColor,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: cropMode ? widget.accentColor : Colors.white,
                      width: cropMode ? 2 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRotationHandle({
    required String id,
    required double canvasW,
    required double canvasH,
    required double elementWidth,
    required double elementHeight,
  }) {
    // Tall layers get the familiar top-center rotation affordance. Compact
    // layers (buttons and short text rows) use an inset right-side handle so
    // the entire 24px hit target remains inside their render bounds.
    final placeAtTop = elementHeight >= 96;
    final compactInset = math.min(28.0, math.max(0.0, elementWidth - 24));
    return Align(
      alignment: placeAtTop ? Alignment.topCenter : Alignment.centerRight,
      child: Transform.translate(
        offset: placeAtTop ? const Offset(0, 28) : Offset(-compactInset, 0),
        child: Semantics(
          button: true,
          label: 'Arrastra para rotar. Shift ajusta a 15 grados.',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('rotation_handle_$id'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _startRotation(
                id,
                details.globalPosition,
                canvasW,
                canvasH,
              ),
              onPanUpdate: (details) =>
                  _updateRotation(id, details.globalPosition),
              onPanEnd: (_) => _endRotation(),
              onPanCancel: _endRotation,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.accentColor, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Icon(
                  Icons.rotate_right_rounded,
                  size: 15,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveElementChrome(double canvasW, double canvasH) {
    if (!widget.editable || _activeElementIdLocal == null) {
      return const SizedBox.shrink();
    }
    final id = _activeElementIdLocal!;
    final element = _elements.firstWhere(
      (item) => item['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    if (element.isEmpty || _editingElementId == id) {
      return const SizedBox.shrink();
    }
    final type = (element['type'] ?? 'text').toString();
    final x = (element['x'] as num?)?.toDouble() ?? 0;
    final y = (element['y'] as num?)?.toDouble() ?? 0;
    final width = (element['w'] as num?)?.toDouble() ?? 200;
    final height = (element['h'] as num?)?.toDouble() ?? 56;
    final effectiveX = _effectiveLeft(x: x, w: width, canvasW: canvasW);
    final effectiveY =
        _effectiveTop(y: y, h: height, canvasW: canvasW, canvasH: canvasH);
    final effectiveW = _effectiveWidth(type: type, w: width, canvasW: canvasW);
    final effectiveH = _effectiveHeight(
      type: type,
      h: height,
      canvasW: canvasW,
      canvasH: canvasH,
    );
    final rotation = (element['rotation'] as num?)?.toDouble() ?? 0;
    final locked = element['locked'] == true;
    final cropMode = type == 'image' && _croppingElementId == id;

    Widget chrome = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: widget.accentColor, width: 2),
              ),
            ),
          ),
        ),
        if (cropMode)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CanvasCropGridPainter(
                  color: widget.accentColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        if (cropMode)
          Positioned(
            left: 8,
            top: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RECORTE · ARRASTRA LA IMAGEN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        if (locked)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: widget.accentColor,
                ),
              ),
            ),
          ),
        if (!locked)
          for (final handle in _CanvasFrameHandle.values)
            _buildFrameHandle(
              id: id,
              type: type,
              handle: handle,
              canvasW: canvasW,
              canvasH: canvasH,
              cropMode: cropMode,
            ),
        if (!locked && !cropMode)
          _buildRotationHandle(
            id: id,
            canvasW: canvasW,
            canvasH: canvasH,
            elementWidth: effectiveW,
            elementHeight: effectiveH,
          ),
      ],
    );
    if (rotation.abs() > 0.01) {
      chrome = Transform.rotate(
        angle: rotation * math.pi / 180,
        child: chrome,
      );
    }
    return Positioned(
      key: ValueKey('canvas_chrome_$id'),
      left: effectiveX,
      top: effectiveY,
      width: effectiveW,
      height: effectiveH,
      child: chrome,
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
        final action = WebsiteActionValue.resolvePrimary(
              el,
              labelKeys: const ['label'],
              hrefKeys: const ['link'],
              defaultLabel: 'Botón',
              defaultHref: '/',
              defaultVariant: WebsiteActionVariant.fromStorage(
                el['style']?.toString(),
              ),
            ) ??
            const WebsiteActionValue(label: 'Botón', href: '/');
        final label = action.label;
        final style = action.variant.storageValue;
        final link = action.href;
        final inheritTheme = el['inheritTheme'] != false;
        final fontSize = ((el['fontSize'] as num?)?.toDouble() ?? 14) * scale;
        final radius = ((el['radius'] as num?)?.toDouble() ?? 10) * scale;
        final bgColor =
            _parseHexColor(el['bgColor'] as String?, widget.accentColor);
        final fgColor = _parseHexColor(el['fgColor'] as String?, Colors.white);
        final letterSpacing = (el['letterSpacing'] as num?)?.toDouble() ?? 0.0;
        final uppercase = (el['uppercase'] as bool?) ?? false;
        final shadow = (el['shadow'] as bool?) ?? false;

        final ButtonStyle? buttonStyle = inheritTheme
            ? null
            : switch (style) {
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
                    elevation: shadow ? 6 : 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radius))),
              };

        void onPressed() {
          if (widget.editable) return;
          widget.onNavigate?.call(link);
        }

        final labelText =
            inheritTheme || !uppercase ? label : label.toUpperCase();
        final labelStyle = inheritTheme
            ? null
            : TextStyle(
                fontSize: fontSize,
                letterSpacing: letterSpacing,
                color: style == 'filled' ? fgColor : bgColor,
                fontWeight: FontWeight.w600,
              );
        final button = WebsiteActionButton(
          action: action.copyWith(label: labelText),
          onPressed: onPressed,
          textStyle: labelStyle,
          style: buttonStyle,
        );
        content = widget.editable ? IgnorePointer(child: button) : button;
        break;
      case 'image':
        final sourceProductId = (el['productId'] ?? '').toString().trim();
        final imageSource = (el['imageSource'] ??
                (sourceProductId.isNotEmpty ? 'product' : 'manual'))
            .toString();
        final useProductImage =
            sourceProductId.isNotEmpty && imageSource != 'manual';
        if (useProductImage) {
          _ensureProductsLoaded({sourceProductId});
        }
        final sourceProduct =
            useProductImage ? _productCache[sourceProductId] : null;
        final productImageUrl = sourceProduct?['image_url']?.toString().trim();
        final imageUrl = useProductImage &&
                productImageUrl != null &&
                productImageUrl.isNotEmpty
            ? productImageUrl
            : (el['imageUrl'] ?? '').toString().trim();
        final fitRaw = (el['fit'] ?? 'cover').toString();
        final fit = fitRaw == 'contain' ? BoxFit.contain : BoxFit.cover;
        final focalPointX =
            ((el['focalPointX'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
        final focalPointY =
            ((el['focalPointY'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
        final imageAlignment = Alignment(
          focalPointX * 2 - 1,
          focalPointY * 2 - 1,
        );
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
                  alignment: imageAlignment,
                  semanticLabel: el['altText']?.toString(),
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
      case 'shape':
        final shape = (el['shape'] ?? 'rectangle').toString();
        final fillColor = _parseHexColor(
          el['fillColor']?.toString(),
          const Color(0xFF1F2937),
        );
        final borderColor = _parseHexColor(
          el['borderColor']?.toString(),
          fillColor,
        );
        final borderWidth =
            ((el['borderWidth'] as num?)?.toDouble() ?? 0) * scale;
        final radius = ((el['radius'] as num?)?.toDouble() ?? 0) * scale;
        content = DecoratedBox(
          decoration: BoxDecoration(
            color: fillColor,
            shape: shape == 'ellipse' ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: shape == 'ellipse'
                ? null
                : BorderRadius.circular(radius.clamp(0, 999)),
            border: borderWidth > 0
                ? Border.all(color: borderColor, width: borderWidth)
                : null,
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
        final sourceText = (el['text'] ?? 'Texto').toString();
        final text =
            el['uppercase'] == true ? sourceText.toUpperCase() : sourceText;
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
        final fontRole = (el['fontRole'] ?? 'heading').toString();
        final explicitFontFamily = el['fontFamily']?.toString().trim();
        final fontFamily =
            explicitFontFamily != null && explicitFontFamily.isNotEmpty
                ? explicitFontFamily
                : fontRole == 'body'
                    ? widget.bodyFont
                    : widget.headingFont ?? widget.bodyFont;
        final letterSpacing = (el['letterSpacing'] as num?)?.toDouble() ?? 0.0;
        final lineHeight =
            ((el['lineHeight'] as num?)?.toDouble() ?? 1.1).clamp(0.8, 2.0);

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
                fontFamily: fontFamily,
                letterSpacing: letterSpacing,
                height: lineHeight,
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
                fontFamily: fontFamily,
                letterSpacing: letterSpacing,
                height: lineHeight,
              ),
            ),
          );
        }
    }

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

    final resolvedHeight = overrideHeight ?? effectiveH;
    final rotationDegrees = (el['rotation'] as num?)?.toDouble() ?? 0.0;
    Widget applyRotation(Widget child) => rotationDegrees == 0
        ? child
        : Transform.rotate(
            angle: rotationDegrees * math.pi / 180,
            child: child,
          );
    final publicTransformed = applyRotation(SizedBox.expand(child: content));
    final locked = el['locked'] == true;
    final cropMode = type == 'image' && _croppingElementId == id;
    final editableFrame = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: content),
        if (isHovered && !isActive)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final editorTransformed = applyRotation(editableFrame);

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
                  onDoubleTap: () {
                    if (type == 'image') {
                      _toggleCropMode(id);
                    } else {
                      _startInlineEdit(type: type, el: el);
                    }
                  },
                  onPanStart: (d) {
                    // Ignore trackpad scroll/pan (usually has 0 buttons pressed)
                    // Only allow drag if a button is pressed (primary, secondary, etc)
                    if (_lastPointerButtons == 0) return;

                    if (_resizingElementId == id) return;
                    if (_rotatingElementId == id) return;
                    if (_editingElementId == id) return;
                    if (locked) return;
                    if (cropMode) {
                      setState(() {
                        _reframingElementId = id;
                        _draggingElementId = null;
                      });
                      return;
                    }
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
                    if (_rotatingElementId == id) return;
                    if (_editingElementId == id) return;
                    if (_reframingElementId == id) {
                      final radians = -(rotationDegrees * math.pi / 180);
                      final localDelta = Offset(
                        d.delta.dx * math.cos(radians) -
                            d.delta.dy * math.sin(radians),
                        d.delta.dx * math.sin(radians) +
                            d.delta.dy * math.cos(radians),
                      );
                      setState(() {
                        final index = _elements.indexWhere(
                          (item) => item['id']?.toString() == id,
                        );
                        if (index == -1) return;
                        final currentX =
                            (_elements[index]['focalPointX'] as num?)
                                    ?.toDouble() ??
                                0.5;
                        final currentY =
                            (_elements[index]['focalPointY'] as num?)
                                    ?.toDouble() ??
                                0.5;
                        _elements[index] = {
                          ..._elements[index],
                          'focalPointX': (currentX - localDelta.dx / effectiveW)
                              .clamp(0.0, 1.0),
                          'focalPointY':
                              (currentY - localDelta.dy / resolvedHeight)
                                  .clamp(0.0, 1.0),
                        };
                      });
                      return;
                    }
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
                    if (_reframingElementId == id) {
                      setState(() => _reframingElementId = null);
                      _commitElements();
                      return;
                    }
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
                  onPanCancel: () {
                    if (_reframingElementId == id) {
                      setState(() => _reframingElementId = null);
                      _commitElements();
                    } else if (_draggingElementId == id) {
                      setState(() {
                        _draggingElementId = null;
                        _dragAnchorInElement = null;
                        _pointerCanvasPos = null;
                        _axisLock = _AxisLock.none;
                        _guideX = null;
                        _guideY = null;
                      });
                      _commitElements();
                    }
                  },
                  child: editorTransformed,
                ),
              ),
            )
          : publicTransformed,
    );
  }

  void _startInlineEdit({
    required String type,
    required Map<String, dynamic> el,
  }) {
    if (!widget.editable) return;
    final id = el['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (type != 'text' && type != 'button') return;

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

class _CanvasCropGridPainter extends CustomPainter {
  final Color color;

  const _CanvasCropGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, paint..strokeWidth = 2);
    paint.strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasCropGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

enum _CanvasFrameHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get affectsLeft => this == topLeft || this == bottomLeft || this == left;

  bool get affectsRight =>
      this == topRight || this == bottomRight || this == right;

  bool get affectsTop => this == topLeft || this == topRight || this == top;

  bool get affectsBottom =>
      this == bottomLeft || this == bottomRight || this == bottom;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  Alignment get alignment => switch (this) {
        topLeft => Alignment.topLeft,
        top => Alignment.topCenter,
        topRight => Alignment.topRight,
        right => Alignment.centerRight,
        bottomRight => Alignment.bottomRight,
        bottom => Alignment.bottomCenter,
        bottomLeft => Alignment.bottomLeft,
        left => Alignment.centerLeft,
      };

  Offset get outwardOffset => switch (this) {
        topLeft => Offset.zero,
        top => Offset.zero,
        topRight => Offset.zero,
        right => Offset.zero,
        bottomRight => Offset.zero,
        bottom => Offset.zero,
        bottomLeft => Offset.zero,
        left => Offset.zero,
      };

  MouseCursor get cursor => switch (this) {
        topLeft || bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        topRight || bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
        top || bottom => SystemMouseCursors.resizeUpDown,
        left || right => SystemMouseCursors.resizeLeftRight,
      };
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
