import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
  static final Map<String, Future<_TrimmedImageData>> _imageCache = {};

  late Future<_TrimmedImageData> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _load(widget.imageUrl, widget.maxCacheDimension);
  }

  @override
  void didUpdateWidget(covariant PosProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.maxCacheDimension != widget.maxCacheDimension) {
      _imageFuture = _load(widget.imageUrl, widget.maxCacheDimension);
    }
  }

  static Future<_TrimmedImageData> _load(String imageUrl, int maxDimension) {
    final cacheKey = '$imageUrl#$maxDimension';
    return _imageCache.putIfAbsent(
      cacheKey,
      () => _resolveAndTrimImage(imageUrl, maxDimension),
    );
  }

  static Future<_TrimmedImageData> _resolveAndTrimImage(
    String imageUrl,
    int maxDimension,
  ) async {
    final provider = CachedNetworkImageProvider(
      imageUrl,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(info);
        }
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    final imageInfo = await completer.future;
    final image = imageInfo.image;

    return _TrimmedImageData(
      image: image,
      sourceRect: await _findContentRect(image),
    );
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
    return FutureBuilder<_TrimmedImageData>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorWidget;
        }

        final data = snapshot.data;
        if (data == null) {
          return widget.placeholder;
        }

        return CustomPaint(
          painter: _TrimmedImagePainter(
            data: data,
            fit: widget.fit,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _TrimmedImageData {
  final ui.Image image;
  final Rect sourceRect;

  const _TrimmedImageData({
    required this.image,
    required this.sourceRect,
  });
}

class _TrimmedImagePainter extends CustomPainter {
  final _TrimmedImageData data;
  final BoxFit fit;

  const _TrimmedImagePainter({
    required this.data,
    required this.fit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final output = Offset.zero & size;
    final fitted = applyBoxFit(fit, data.sourceRect.size, output.size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      output,
    );

    canvas.drawImageRect(
      data.image,
      data.sourceRect,
      destination,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _TrimmedImagePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.fit != fit;
  }
}
