import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/services/memory_hygiene.dart';

/// Imagen de producto del POS con recorte automático del fondo blanco.
///
/// Los píxeles decodificados viven en el `ImageCache` del framework (con tope
/// y evicción propios). Antes este widget guardaba cada `ui.Image` decodificada
/// en un mapa estático sin tope y la memoria nativa crecía sin retorno —
/// hallazgo del incidente de 41 GB del 2026-08-05. Lo único que se cachea
/// estáticamente ahora es el `Rect` de recorte por URL: 32 bytes por entrada,
/// con tope y evicción.
class PosProductImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;
  final int maxCacheDimension;

  const PosProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    required this.placeholder,
    required this.errorWidget,
    this.maxCacheDimension = 700,
  });

  @override
  State<PosProductImage> createState() => _PosProductImageState();
}

class _PosProductImageState extends State<PosProductImage> {
  static final LinkedHashMap<String, Rect> _contentRectCache =
      LinkedHashMap<String, Rect>();
  static const int _contentRectCacheCap = 1024;
  static bool _hygieneRegistered = false;

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ImageInfo? _imageInfo;
  Rect? _sourceRect;
  bool _hasError = false;
  int _rectComputationEpoch = 0;

  String get _cacheKey => '${widget.imageUrl}#${widget.maxCacheDimension}';

  @override
  void initState() {
    super.initState();
    if (!_hygieneRegistered) {
      _hygieneRegistered = true;
      MemoryHygiene.registerTransientCache(_contentRectCache.clear);
    }
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant PosProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.maxCacheDimension != widget.maxCacheDimension) {
      _sourceRect = null;
      _hasError = false;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _detachListener();
    _imageInfo?.dispose();
    _imageInfo = null;
    super.dispose();
  }

  void _detachListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }

  void _resolveImage() {
    final provider = CachedNetworkImageProvider(
      widget.imageUrl,
      maxWidth: widget.maxCacheDimension,
      maxHeight: widget.maxCacheDimension,
    );
    final newStream = provider.resolve(ImageConfiguration.empty);
    if (newStream.key == _imageStream?.key) return;
    _detachListener();
    _imageStream = newStream;
    final listener = ImageStreamListener(
      _handleImageFrame,
      onError: _handleImageError,
    );
    _imageListener = listener;
    newStream.addListener(listener);
  }

  void _handleImageFrame(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    _imageInfo?.dispose();
    _imageInfo = info;
    _hasError = false;

    final key = _cacheKey;
    final cached = _contentRectCache.remove(key);
    if (cached != null) {
      // Re-insertar la entrada la marca como recién usada (evicción LRU).
      _contentRectCache[key] = cached;
      _sourceRect = cached;
      if (!synchronousCall) setState(() {});
      return;
    }

    final epoch = ++_rectComputationEpoch;
    // Clon propio para el análisis: el frame puede reemplazarse (y disponerse)
    // mientras el cálculo asíncrono sigue leyendo los píxeles.
    final analysisImage = info.image.clone();
    unawaited(_computeAndStoreRect(analysisImage, key, epoch));
  }

  Future<void> _computeAndStoreRect(
    ui.Image analysisImage,
    String key,
    int epoch,
  ) async {
    try {
      final rect = await _findContentRect(analysisImage);
      _contentRectCache[key] = rect;
      while (_contentRectCache.length > _contentRectCacheCap) {
        _contentRectCache.remove(_contentRectCache.keys.first);
      }
      if (!mounted || epoch != _rectComputationEpoch) return;
      setState(() => _sourceRect = rect);
    } finally {
      analysisImage.dispose();
    }
  }

  void _handleImageError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    setState(() => _hasError = true);
  }

  static Future<Rect> _findContentRect(ui.Image image) async {
    final width = image.width;
    final height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null || width <= 0 || height <= 0) {
      return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    }

    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    final bytes = byteData.buffer.asUint8List();
    final step = math.max(1, math.min(width, height) ~/ 240);

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
        final index = (y * width + x) * 4;
        final red = bytes[index];
        final green = bytes[index + 1];
        final blue = bytes[index + 2];
        final alpha = bytes[index + 3];

        if (alpha > 18 && !(red > 245 && green > 245 && blue > 245)) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    }

    final marginX = math.max(8, ((maxX - minX + 1) * 0.06).round());
    final marginY = math.max(8, ((maxY - minY + 1) * 0.06).round());
    final left = math.max(0, minX - marginX).toDouble();
    final top = math.max(0, minY - marginY).toDouble();
    final right = math.min(width, maxX + marginX + 1).toDouble();
    final bottom = math.min(height, maxY + marginY + 1).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return widget.errorWidget;

    final imageInfo = _imageInfo;
    final sourceRect = _sourceRect;
    if (imageInfo == null || sourceRect == null) {
      return widget.placeholder;
    }

    return CustomPaint(
      painter: _TrimmedImagePainter(
        image: imageInfo.image,
        sourceRect: sourceRect,
        fit: widget.fit,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TrimmedImagePainter extends CustomPainter {
  final ui.Image image;
  final Rect sourceRect;
  final BoxFit fit;

  const _TrimmedImagePainter({
    required this.image,
    required this.sourceRect,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final output = Offset.zero & size;
    final fitted = applyBoxFit(fit, sourceRect.size, output.size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      output,
    );

    canvas.drawImageRect(
      image,
      sourceRect,
      destination,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _TrimmedImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.sourceRect != sourceRect ||
        oldDelegate.fit != fit;
  }
}
