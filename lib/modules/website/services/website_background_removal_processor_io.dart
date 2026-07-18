import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'website_background_removal_result.dart';

class WebsiteBackgroundRemovalProcessor {
  const WebsiteBackgroundRemovalProcessor._();

  /// Removes a contiguous, near-uniform background without sending the image
  /// to a provider. Only pixels connected to the outer edge are removed, so
  /// similarly coloured details enclosed by the subject remain intact.
  static WebsiteBackgroundRemovalResult process(
    Uint8List bytes, {
    int tolerance = 34,
  }) {
    final source = img.decodeImage(bytes);
    if (source == null) {
      throw const FormatException('No se pudo decodificar la imagen.');
    }

    final width = source.width;
    final height = source.height;
    if (width < 2 || height < 2) {
      throw const FormatException('La imagen es demasiado pequeña.');
    }
    if (width * height > 8 * 1000 * 1000) {
      throw const FormatException(
        'La imagen supera 8 megapíxeles. Redúcela antes de procesarla.',
      );
    }

    final safeTolerance = tolerance.clamp(8, 96);
    final transparentRatio = _transparentPixelRatio(source);
    if (transparentRatio >= 0.015) {
      return WebsiteBackgroundRemovalResult(
        pngBytes: bytes,
        removedRatio: 0,
        borderAgreement: 1,
        width: width,
        height: height,
        alreadyTransparent: true,
      );
    }

    final references = _cornerReferences(source);
    final borderAgreement = _borderAgreement(
      source,
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
      final pixel = source.getPixel(x, y);
      if (!_matchesReference(pixel, references, safeTolerance)) return;
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

    final output = source.convert(numChannels: 4);
    for (var index = 0; index < visited.length; index++) {
      if (visited[index] != 2) continue;
      final x = index % width;
      final y = index ~/ width;
      final pixel = output.getPixel(x, y);
      output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, 0);
    }

    return WebsiteBackgroundRemovalResult(
      pngBytes: Uint8List.fromList(img.encodePng(output, level: 6)),
      removedRatio: tail / (width * height),
      borderAgreement: borderAgreement,
      width: width,
      height: height,
    );
  }

  static double _transparentPixelRatio(img.Image image) {
    if (!image.hasAlpha) return 0;
    final stepX = (image.width / 120).ceil().clamp(1, image.width);
    final stepY = (image.height / 120).ceil().clamp(1, image.height);
    var transparent = 0;
    var sampled = 0;
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        sampled++;
        if (image.getPixel(x, y).a < 250) transparent++;
      }
    }
    return sampled == 0 ? 0 : transparent / sampled;
  }

  static List<_Rgb> _cornerReferences(img.Image image) {
    const inset = 2;
    final maxX = image.width - 1;
    final maxY = image.height - 1;
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
    return points
        .map((point) => _Rgb.fromPixel(image.getPixel(point.$1, point.$2)))
        .toList(growable: false);
  }

  static double _borderAgreement(
    img.Image image,
    List<_Rgb> references,
    int tolerance,
  ) {
    final step = ((image.width + image.height) / 180).ceil().clamp(1, 32);
    var matching = 0;
    var sampled = 0;

    void sample(int x, int y) {
      sampled++;
      if (_matchesReference(image.getPixel(x, y), references, tolerance)) {
        matching++;
      }
    }

    for (var x = 0; x < image.width; x += step) {
      sample(x, 0);
      sample(x, image.height - 1);
    }
    for (var y = step; y < image.height - 1; y += step) {
      sample(0, y);
      sample(image.width - 1, y);
    }
    return sampled == 0 ? 0 : matching / sampled;
  }

  static bool _matchesReference(
    img.Pixel pixel,
    List<_Rgb> references,
    int tolerance,
  ) {
    if (pixel.a == 0) return true;
    final current = _Rgb.fromPixel(pixel);
    final limit = tolerance * tolerance * 3;
    for (final reference in references) {
      final dr = current.r - reference.r;
      final dg = current.g - reference.g;
      final db = current.b - reference.b;
      if ((dr * dr) + (dg * dg) + (db * db) <= limit) {
        return true;
      }
    }
    return false;
  }
}

class _Rgb {
  final int r;
  final int g;
  final int b;

  const _Rgb(this.r, this.g, this.b);

  factory _Rgb.fromPixel(img.Pixel pixel) => _Rgb(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
}
