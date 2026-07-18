import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'website_background_removal_result.dart';

class WebsiteBackgroundRemovalProcessor {
  const WebsiteBackgroundRemovalProcessor._();

  /// Browser implementation backed by the native Canvas API. Keeping the
  /// general-purpose Dart image codec out of the storefront entry point avoids
  /// charging every visitor the download cost of an editor-only dependency.
  static Future<WebsiteBackgroundRemovalResult> process(
    Uint8List bytes, {
    int tolerance = 34,
  }) async {
    final decoded = await _decode(bytes);
    final width = decoded.width;
    final height = decoded.height;
    if (width < 2 || height < 2) {
      throw const FormatException('La imagen es demasiado pequeña.');
    }
    if (width * height > 8 * 1000 * 1000) {
      throw const FormatException(
        'La imagen supera 8 megapíxeles. Redúcela antes de procesarla.',
      );
    }

    final pixels = decoded.imageData.data.toDart;
    if (_transparentPixelRatio(pixels, width, height) >= 0.015) {
      return WebsiteBackgroundRemovalResult(
        pngBytes: bytes,
        removedRatio: 0,
        borderAgreement: 1,
        width: width,
        height: height,
        alreadyTransparent: true,
      );
    }

    final safeTolerance = tolerance.clamp(8, 96);
    final references = _cornerReferences(pixels, width, height);
    final borderAgreement = _borderAgreement(
      pixels,
      width,
      height,
      references,
      safeTolerance,
    );
    final visited = Uint8List(width * height);
    final queue = Uint32List(width * height);
    var head = 0;
    var tail = 0;

    void enqueue(int x, int y) {
      final index = y * width + x;
      if (visited[index] != 0) return;
      visited[index] = 1;
      if (!_matchesReference(
        pixels,
        index,
        references,
        safeTolerance,
      )) {
        return;
      }
      visited[index] = 2;
      queue[tail++] = index;
    }

    for (var x = 0; x < width; x++) {
      enqueue(x, 0);
      enqueue(x, height - 1);
    }
    for (var y = 1; y < height - 1; y++) {
      enqueue(0, y);
      enqueue(width - 1, y);
    }

    while (head < tail) {
      final index = queue[head++];
      final x = index % width;
      final y = index ~/ width;
      if (x > 0) enqueue(x - 1, y);
      if (x + 1 < width) enqueue(x + 1, y);
      if (y > 0) enqueue(x, y - 1);
      if (y + 1 < height) enqueue(x, y + 1);
    }

    for (var index = 0; index < visited.length; index++) {
      if (visited[index] == 2) pixels[(index * 4) + 3] = 0;
    }
    decoded.context.putImageData(decoded.imageData, 0, 0);

    return WebsiteBackgroundRemovalResult(
      pngBytes: _canvasPng(decoded.canvas),
      removedRatio: tail / (width * height),
      borderAgreement: borderAgreement,
      width: width,
      height: height,
    );
  }

  static Future<_DecodedCanvas> _decode(Uint8List bytes) async {
    final blob = web.Blob([bytes.toJS].toJS);
    final objectUrl = web.URL.createObjectURL(blob);
    final image = web.HTMLImageElement();
    try {
      final loaded = image.onLoad.first;
      final failed = image.onError.first.then<void>((_) {
        throw const FormatException('No se pudo decodificar la imagen.');
      });
      image.src = objectUrl;
      await Future.any<void>([loaded.then<void>((_) {}), failed]);

      final width = image.naturalWidth;
      final height = image.naturalHeight;
      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = height;
      final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
      context.drawImage(image, 0, 0, width, height);
      return _DecodedCanvas(
        canvas: canvas,
        context: context,
        imageData: context.getImageData(0, 0, width, height),
        width: width,
        height: height,
      );
    } finally {
      web.URL.revokeObjectURL(objectUrl);
    }
  }

  static Uint8List _canvasPng(web.HTMLCanvasElement canvas) {
    final dataUrl = canvas.toDataURL('image/png');
    final separator = dataUrl.indexOf(',');
    if (separator < 0) {
      throw const FormatException('No se pudo generar el PNG transparente.');
    }
    return base64Decode(dataUrl.substring(separator + 1));
  }

  static double _transparentPixelRatio(
    Uint8ClampedList pixels,
    int width,
    int height,
  ) {
    final stepX = (width / 120).ceil().clamp(1, width);
    final stepY = (height / 120).ceil().clamp(1, height);
    var transparent = 0;
    var sampled = 0;
    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        sampled++;
        if (pixels[((y * width + x) * 4) + 3] < 250) transparent++;
      }
    }
    return sampled == 0 ? 0 : transparent / sampled;
  }

  static List<(int, int, int)> _cornerReferences(
    Uint8ClampedList pixels,
    int width,
    int height,
  ) {
    const inset = 2;
    final maxX = width - 1;
    final maxY = height - 1;
    final points = <(int, int)>[
      (0, 0),
      (maxX, 0),
      (0, maxY),
      (maxX, maxY),
      (inset.clamp(0, maxX), inset.clamp(0, maxY)),
      ((maxX - inset).clamp(0, maxX), inset.clamp(0, maxY)),
      (inset.clamp(0, maxX), (maxY - inset).clamp(0, maxY)),
      ((maxX - inset).clamp(0, maxX), (maxY - inset).clamp(0, maxY)),
    ];
    return points.map((point) {
      final offset = ((point.$2 * width) + point.$1) * 4;
      return (pixels[offset], pixels[offset + 1], pixels[offset + 2]);
    }).toList(growable: false);
  }

  static double _borderAgreement(
    Uint8ClampedList pixels,
    int width,
    int height,
    List<(int, int, int)> references,
    int tolerance,
  ) {
    final step = ((width + height) / 180).ceil().clamp(1, 32);
    var matching = 0;
    var sampled = 0;

    void sample(int x, int y) {
      sampled++;
      if (_matchesReference(
        pixels,
        y * width + x,
        references,
        tolerance,
      )) {
        matching++;
      }
    }

    for (var x = 0; x < width; x += step) {
      sample(x, 0);
      sample(x, height - 1);
    }
    for (var y = step; y < height - 1; y += step) {
      sample(0, y);
      sample(width - 1, y);
    }
    return sampled == 0 ? 0 : matching / sampled;
  }

  static bool _matchesReference(
    Uint8ClampedList pixels,
    int pixelIndex,
    List<(int, int, int)> references,
    int tolerance,
  ) {
    final offset = pixelIndex * 4;
    if (pixels[offset + 3] == 0) return true;
    final r = pixels[offset];
    final g = pixels[offset + 1];
    final b = pixels[offset + 2];
    final limit = tolerance * tolerance * 3;
    for (final reference in references) {
      final dr = r - reference.$1;
      final dg = g - reference.$2;
      final db = b - reference.$3;
      if ((dr * dr) + (dg * dg) + (db * db) <= limit) return true;
    }
    return false;
  }
}

class _DecodedCanvas {
  final web.HTMLCanvasElement canvas;
  final web.CanvasRenderingContext2D context;
  final web.ImageData imageData;
  final int width;
  final int height;

  const _DecodedCanvas({
    required this.canvas,
    required this.context,
    required this.imageData,
    required this.width,
    required this.height,
  });
}
