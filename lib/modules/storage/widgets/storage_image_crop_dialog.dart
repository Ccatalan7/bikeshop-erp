import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/app_stored_file.dart';
import '../services/app_file_storage_service.dart';

enum _CropHandle {
  create,
  move,
  north,
  south,
  east,
  west,
  northWest,
  northEast,
  southWest,
  southEast,
}

class StorageImageCropDialog extends StatefulWidget {
  final AppStoredFile file;
  final Uint8List bytes;

  const StorageImageCropDialog({
    super.key,
    required this.file,
    required this.bytes,
  });

  static Future<AppStoredFile?> show(
    BuildContext context, {
    required AppStoredFile file,
    required Uint8List bytes,
  }) {
    return showDialog<AppStoredFile>(
      context: context,
      builder: (_) => StorageImageCropDialog(file: file, bytes: bytes),
    );
  }

  @override
  State<StorageImageCropDialog> createState() => _StorageImageCropDialogState();
}

class _StorageImageCropDialogState extends State<StorageImageCropDialog> {
  static const double _minCropSize = 24;

  img.Image? _decoded;
  Rect? _cropRect;
  Rect? _dragStartCrop;
  Offset? _dragStartImagePoint;
  _CropHandle? _activeHandle;
  bool _isSaving = false;
  String? _error;

  Size get _imageSize {
    final decoded = _decoded;
    if (decoded == null) return Size.zero;
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  @override
  void initState() {
    super.initState();
    _decoded = img.decodeImage(widget.bytes);
    _resetCrop();
  }

  void _resetCrop() {
    final decoded = _decoded;
    if (decoded == null) return;

    final width = decoded.width.toDouble();
    final height = decoded.height.toDouble();
    setState(() {
      _cropRect = Rect.fromLTWH(
        width * 0.08,
        height * 0.08,
        width * 0.84,
        height * 0.84,
      );
      _error = null;
    });
  }

  Rect _containRect(Size source, Size box) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        box.width <= 0 ||
        box.height <= 0) {
      return Offset.zero & box;
    }

    final scale =
        math.min(box.width / source.width, box.height / source.height);
    final width = source.width * scale;
    final height = source.height * scale;
    return Rect.fromLTWH(
      (box.width - width) / 2,
      (box.height - height) / 2,
      width,
      height,
    );
  }

  Rect _cropToView(Rect crop, Rect imageRect) {
    final imageSize = _imageSize;
    return Rect.fromLTRB(
      imageRect.left + (crop.left / imageSize.width) * imageRect.width,
      imageRect.top + (crop.top / imageSize.height) * imageRect.height,
      imageRect.left + (crop.right / imageSize.width) * imageRect.width,
      imageRect.top + (crop.bottom / imageSize.height) * imageRect.height,
    );
  }

  Offset _viewToImagePoint(Offset point, Rect imageRect) {
    final imageSize = _imageSize;
    final x = ((point.dx - imageRect.left) / imageRect.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = ((point.dy - imageRect.top) / imageRect.height)
        .clamp(0.0, 1.0)
        .toDouble();
    return Offset(x * imageSize.width, y * imageSize.height);
  }

  Offset _viewDeltaToImageDelta(Offset delta, Rect imageRect) {
    final imageSize = _imageSize;
    return Offset(
      delta.dx / imageRect.width * imageSize.width,
      delta.dy / imageRect.height * imageSize.height,
    );
  }

  void _startDrag(Offset point, Rect imageRect) {
    if (!imageRect.contains(point)) {
      return;
    }

    final crop = _cropRect;
    if (crop == null) return;

    final cropView = _cropToView(crop, imageRect);
    final handle = _hitTestHandle(point, cropView) ??
        (cropView.contains(point) ? _CropHandle.move : _CropHandle.create);
    final imagePoint = _viewToImagePoint(point, imageRect);

    setState(() {
      _activeHandle = handle;
      _dragStartCrop = handle == _CropHandle.create
          ? Rect.fromPoints(imagePoint, imagePoint)
          : crop;
      _dragStartImagePoint = imagePoint;
      if (handle == _CropHandle.create) {
        _cropRect = Rect.fromPoints(imagePoint, imagePoint);
      }
      _error = null;
    });
  }

  void _updateDrag(DragUpdateDetails details, Rect imageRect) {
    final handle = _activeHandle;
    final startCrop = _dragStartCrop;
    final startPoint = _dragStartImagePoint;
    if (handle == null || startCrop == null || startPoint == null) return;

    final imagePoint = _viewToImagePoint(details.localPosition, imageRect);
    final delta = handle == _CropHandle.move
        ? _viewDeltaToImageDelta(details.delta, imageRect)
        : imagePoint - startPoint;

    Rect next;
    if (handle == _CropHandle.create) {
      next = Rect.fromPoints(startPoint, imagePoint);
    } else if (handle == _CropHandle.move) {
      next = _clampMoved(startCrop.shift(delta));
    } else {
      next = _resizeCrop(startCrop, handle, delta);
    }

    setState(() => _cropRect = _normalizeCrop(next));
  }

  void _endDrag() {
    setState(() {
      _activeHandle = null;
      _dragStartCrop = null;
      _dragStartImagePoint = null;
    });
  }

  Rect _resizeCrop(Rect crop, _CropHandle handle, Offset delta) {
    var left = crop.left;
    var top = crop.top;
    var right = crop.right;
    var bottom = crop.bottom;

    switch (handle) {
      case _CropHandle.north:
        top += delta.dy;
        break;
      case _CropHandle.south:
        bottom += delta.dy;
        break;
      case _CropHandle.east:
        right += delta.dx;
        break;
      case _CropHandle.west:
        left += delta.dx;
        break;
      case _CropHandle.northWest:
        left += delta.dx;
        top += delta.dy;
        break;
      case _CropHandle.northEast:
        right += delta.dx;
        top += delta.dy;
        break;
      case _CropHandle.southWest:
        left += delta.dx;
        bottom += delta.dy;
        break;
      case _CropHandle.southEast:
        right += delta.dx;
        bottom += delta.dy;
        break;
      case _CropHandle.create:
      case _CropHandle.move:
        break;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _normalizeCrop(Rect rect) {
    final imageSize = _imageSize;
    final left = math.min(rect.left, rect.right).clamp(0.0, imageSize.width);
    final right = math.max(rect.left, rect.right).clamp(0.0, imageSize.width);
    final top = math.min(rect.top, rect.bottom).clamp(0.0, imageSize.height);
    final bottom = math.max(rect.top, rect.bottom).clamp(0.0, imageSize.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _clampMoved(Rect rect) {
    final imageSize = _imageSize;
    var dx = 0.0;
    var dy = 0.0;
    if (rect.left < 0) dx = -rect.left;
    if (rect.right > imageSize.width) dx = imageSize.width - rect.right;
    if (rect.top < 0) dy = -rect.top;
    if (rect.bottom > imageSize.height) dy = imageSize.height - rect.bottom;
    return rect.shift(Offset(dx, dy));
  }

  _CropHandle? _hitTestHandle(Offset point, Rect cropView) {
    const handleSize = 18.0;
    bool near(Offset handlePoint) =>
        (point - handlePoint).distance <= handleSize;

    if (near(cropView.topLeft)) return _CropHandle.northWest;
    if (near(cropView.topRight)) return _CropHandle.northEast;
    if (near(cropView.bottomLeft)) return _CropHandle.southWest;
    if (near(cropView.bottomRight)) return _CropHandle.southEast;
    if ((point.dy - cropView.top).abs() <= handleSize &&
        point.dx >= cropView.left &&
        point.dx <= cropView.right) {
      return _CropHandle.north;
    }
    if ((point.dy - cropView.bottom).abs() <= handleSize &&
        point.dx >= cropView.left &&
        point.dx <= cropView.right) {
      return _CropHandle.south;
    }
    if ((point.dx - cropView.left).abs() <= handleSize &&
        point.dy >= cropView.top &&
        point.dy <= cropView.bottom) {
      return _CropHandle.west;
    }
    if ((point.dx - cropView.right).abs() <= handleSize &&
        point.dy >= cropView.top &&
        point.dy <= cropView.bottom) {
      return _CropHandle.east;
    }
    return null;
  }

  Future<void> _saveCrop() async {
    final decoded = _decoded;
    final crop = _cropRect;
    if (decoded == null || crop == null) return;

    final normalized = _normalizeCrop(crop);
    if (normalized.width < _minCropSize || normalized.height < _minCropSize) {
      setState(() => _error = 'Selecciona un area mas grande.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final x = normalized.left.round().clamp(0, decoded.width - 1);
      final y = normalized.top.round().clamp(0, decoded.height - 1);
      final right = normalized.right.round().clamp(x + 1, decoded.width);
      final bottom = normalized.bottom.round().clamp(y + 1, decoded.height);
      final cropped = img.copyCrop(
        decoded,
        x: x,
        y: y,
        width: right - x,
        height: bottom - y,
      );
      final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
      final updatedFile = await AppFileStorageService.instance.replaceFileBytes(
        file: widget.file,
        bytes: croppedBytes,
        mimeType: 'image/png',
        addTags: const ['recorte', 'crop', 'ocr-ready'],
        metadataPatch: _cropMetadata(
          widget.file,
          normalized,
          croppedBytes.length,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(updatedFile);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'No se pudo guardar el recorte: $error';
      });
    }
  }

  Map<String, dynamic> _cropMetadata(
    AppStoredFile file,
    Rect crop,
    int croppedSize,
  ) {
    return {
      'edited': true,
      'edit_type': 'crop',
      'edited_at': DateTime.now().toUtc().toIso8601String(),
      'crop_original_size_bytes': file.sizeBytes,
      'crop_current_size_bytes': croppedSize,
      'crop_rect': {
        'left': crop.left.round(),
        'top': crop.top.round(),
        'width': crop.width.round(),
        'height': crop.height.round(),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decoded;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width - 56).clamp(360.0, 1120.0);
    final dialogHeight = (screenSize.height - 56).clamp(420.0, 860.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: decoded == null ? _buildDecodeError(context) : _buildEditor(),
      ),
    );
  }

  Widget _buildDecodeError(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No se pudo editar esta imagen',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'El archivo no se pudo leer como imagen compatible.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final theme = Theme.of(context);
    final crop = _cropRect;
    final imageSize = _imageSize;

    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.crop_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recortar captura',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isSaving ? null : _resetCrop,
                icon: const Icon(Icons.restart_alt_outlined, size: 18),
                label: const Text('Restablecer'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF0F172A),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = constraints.biggest;
                final imageRect = _containRect(imageSize, canvasSize);
                final cropView =
                    crop == null ? null : _cropToView(crop, imageRect);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) =>
                      _startDrag(details.localPosition, imageRect),
                  onPanUpdate: (details) => _updateDrag(details, imageRect),
                  onPanEnd: (_) => _endDrag(),
                  onPanCancel: _endDrag,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                      CustomPaint(
                        painter: _ImageCropPainter(
                          imageRect: imageRect,
                          cropRect: cropView,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _error ??
                      'Arrastra dentro de la imagen para crear un recorte, o mueve los bordes para ajustarlo.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _error == null
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveCrop,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Guardar recorte'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageCropPainter extends CustomPainter {
  final Rect imageRect;
  final Rect? cropRect;
  final Color color;

  const _ImageCropPainter({
    required this.imageRect,
    required this.cropRect,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final crop = cropRect;
    final outsideImage = Paint()..color = Colors.black.withValues(alpha: 0.18);
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.46);

    final fullPath = Path()..addRect(Offset.zero & size);
    final imagePath = Path()..addRect(imageRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, imagePath),
      outsideImage,
    );

    if (crop == null || crop.width <= 0 || crop.height <= 0) return;

    final dimPath = Path()
      ..addRect(imageRect)
      ..addRRect(RRect.fromRectAndRadius(crop, const Radius.circular(4)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, overlay);

    final border = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(crop, const Radius.circular(4)),
      border,
    );

    final thirdX = crop.width / 3;
    final thirdY = crop.height / 3;
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        Offset(crop.left + thirdX, crop.top),
        Offset(crop.left + thirdX, crop.bottom),
        guide,
      )
      ..drawLine(
        Offset(crop.left + thirdX * 2, crop.top),
        Offset(crop.left + thirdX * 2, crop.bottom),
        guide,
      )
      ..drawLine(
        Offset(crop.left, crop.top + thirdY),
        Offset(crop.right, crop.top + thirdY),
        guide,
      )
      ..drawLine(
        Offset(crop.left, crop.top + thirdY * 2),
        Offset(crop.right, crop.top + thirdY * 2),
        guide,
      );

    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final point in [
      crop.topLeft,
      crop.topCenter,
      crop.topRight,
      crop.centerLeft,
      crop.centerRight,
      crop.bottomLeft,
      crop.bottomCenter,
      crop.bottomRight,
    ]) {
      final handleRect = Rect.fromCenter(center: point, width: 10, height: 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(handleRect, const Radius.circular(3)),
        handleFill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(handleRect, const Radius.circular(3)),
        handleStroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ImageCropPainter oldDelegate) {
    return oldDelegate.imageRect != imageRect ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.color != color;
  }
}
