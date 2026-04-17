import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProductImageFingerprint {
  const ProductImageFingerprint({
    required this.averageHash,
    required this.differenceHash,
    required this.meanRed,
    required this.meanGreen,
    required this.meanBlue,
    required this.aspectRatio,
  });

  final BigInt averageHash;
  final BigInt differenceHash;
  final double meanRed;
  final double meanGreen;
  final double meanBlue;
  final double aspectRatio;

  Map<String, dynamic> toStorageJson() {
    return {
      'ah': averageHash.toRadixString(16),
      'dh': differenceHash.toRadixString(16),
      'r': meanRed,
      'g': meanGreen,
      'b': meanBlue,
      'ar': aspectRatio,
    };
  }

  static ProductImageFingerprint? fromStorageJson(dynamic value) {
    if (value is! Map) return null;

    try {
      final averageHash =
          BigInt.parse((value['ah'] ?? '').toString(), radix: 16);
      final differenceHash =
          BigInt.parse((value['dh'] ?? '').toString(), radix: 16);

      return ProductImageFingerprint(
        averageHash: averageHash,
        differenceHash: differenceHash,
        meanRed: ((value['r'] as num?)?.toDouble() ?? 0),
        meanGreen: ((value['g'] as num?)?.toDouble() ?? 0),
        meanBlue: ((value['b'] as num?)?.toDouble() ?? 0),
        aspectRatio: ((value['ar'] as num?)?.toDouble() ?? 1),
      );
    } catch (_) {
      return null;
    }
  }
}

class ProductImageFingerprintService {
  static ProductImageFingerprint? fromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }

    final averageHash = _computeAverageHashFromImage(decoded);
    final differenceHash = _computeDifferenceHashFromImage(decoded);
    if (averageHash == null || differenceHash == null) return null;

    final sample = img.copyResize(decoded, width: 8, height: 8);
    var totalRed = 0.0;
    var totalGreen = 0.0;
    var totalBlue = 0.0;

    for (var y = 0; y < sample.height; y++) {
      for (var x = 0; x < sample.width; x++) {
        final pixel = sample.getPixel(x, y);
        totalRed += pixel.r;
        totalGreen += pixel.g;
        totalBlue += pixel.b;
      }
    }

    final sampleCount = (sample.width * sample.height).toDouble();

    return ProductImageFingerprint(
      averageHash: averageHash,
      differenceHash: differenceHash,
      meanRed: totalRed / sampleCount,
      meanGreen: totalGreen / sampleCount,
      meanBlue: totalBlue / sampleCount,
      aspectRatio: decoded.width / decoded.height,
    );
  }

  static Map<String, dynamic>? computeStorageJson(Uint8List bytes) {
    return fromBytes(bytes)?.toStorageJson();
  }

  static double detailedSimilarityFromBytes(
    Uint8List leftBytes,
    Uint8List rightBytes,
  ) {
    final leftImage = img.decodeImage(leftBytes);
    final rightImage = img.decodeImage(rightBytes);
    if (leftImage == null || rightImage == null) return 0;
    if (leftImage.width == 0 || leftImage.height == 0) return 0;
    if (rightImage.width == 0 || rightImage.height == 0) return 0;

    final fullGridScore = _gridLumaSimilarity(
      leftImage,
      rightImage,
      size: 18,
      cropFraction: 1.0,
    );
    final centerGridScore = _gridLumaSimilarity(
      leftImage,
      rightImage,
      size: 18,
      cropFraction: 0.72,
    );
    final edgeScore = _edgeGridSimilarity(
      leftImage,
      rightImage,
      size: 18,
      cropFraction: 0.86,
    );
    final silhouetteScore = _silhouetteSimilarity(
      leftImage,
      rightImage,
      size: 24,
      cropFraction: 0.78,
    );
    final colorLayoutScore = _colorLayoutSimilarity(
      leftImage,
      rightImage,
      divisions: 3,
      cropFraction: 0.85,
    );
    final aspectScore = _rawAspectSimilarity(
      leftImage.width / leftImage.height,
      rightImage.width / rightImage.height,
    );

    // Silhouette IoU captures actual shape (circle vs L-bracket),
    // which luma grids miss because they only compare brightness.
    var detailedScore = centerGridScore * 0.28 +
        silhouetteScore * 0.22 +
        edgeScore * 0.22 +
        fullGridScore * 0.15 +
        colorLayoutScore * 0.08 +
        aspectScore * 0.05;

    if (centerGridScore >= 0.92 && edgeScore >= 0.88) {
      detailedScore = math.max(
        detailedScore,
        0.90 + colorLayoutScore * 0.05,
      );
    }

    return detailedScore.clamp(0, 1).toDouble();
  }

  static double similarity(
    ProductImageFingerprint left,
    ProductImageFingerprint right,
  ) {
    final averageHashScore = _bitHashSimilarity(
      left.averageHash,
      right.averageHash,
      64,
    );
    final differenceHashScore = _bitHashSimilarity(
      left.differenceHash,
      right.differenceHash,
      64,
    );
    final colorScore = _colorSimilarity(left, right);
    final aspectScore = _aspectSimilarity(left, right);

    // Weights: heavily favor structural hashes over global color
    // (white-background product photos inflate color similarity to 0.85-0.95)
    final imageScore = differenceHashScore * 0.50 +
        averageHashScore * 0.30 +
        colorScore * 0.12 +
        aspectScore * 0.08;

    // No boost floors — they artificially inflate scores for unrelated
    // white-background product photos that coincidentally share hash bits.

    return imageScore.clamp(0, 1).toDouble();
  }

  static BigInt? _computeAverageHashFromImage(img.Image source) {
    final resized = img.copyResize(source, width: 8, height: 8);
    final grayscale = img.grayscale(resized);

    final luminances = <int>[];
    var total = 0;

    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final pixel = grayscale.getPixel(x, y);
        final value = pixel.r.toInt();
        luminances.add(value);
        total += value;
      }
    }

    final average = total / luminances.length;
    var hash = BigInt.zero;

    for (final value in luminances) {
      hash <<= 1;
      if (value >= average) {
        hash |= BigInt.one;
      }
    }

    return hash;
  }

  static BigInt? _computeDifferenceHashFromImage(img.Image source) {
    final resized = img.copyResize(source, width: 9, height: 8);
    final grayscale = img.grayscale(resized);
    var hash = BigInt.zero;

    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = grayscale.getPixel(x, y).r.toInt();
        final right = grayscale.getPixel(x + 1, y).r.toInt();
        hash <<= 1;
        if (left > right) {
          hash |= BigInt.one;
        }
      }
    }

    return hash;
  }

  static double _bitHashSimilarity(BigInt left, BigInt right, int bitCount) {
    final xor = left ^ right;
    var distance = 0;
    var bits = xor;
    while (bits > BigInt.zero) {
      if ((bits & BigInt.one) == BigInt.one) {
        distance++;
      }
      bits >>= 1;
    }

    return (1 - (distance / bitCount)).clamp(0, 1).toDouble();
  }

  static double _colorSimilarity(
    ProductImageFingerprint left,
    ProductImageFingerprint right,
  ) {
    final redDiff = (left.meanRed - right.meanRed).abs() / 255;
    final greenDiff = (left.meanGreen - right.meanGreen).abs() / 255;
    final blueDiff = (left.meanBlue - right.meanBlue).abs() / 255;
    final meanDiff = (redDiff + greenDiff + blueDiff) / 3;
    return (1 - meanDiff).clamp(0, 1).toDouble();
  }

  static double _aspectSimilarity(
    ProductImageFingerprint left,
    ProductImageFingerprint right,
  ) {
    return _rawAspectSimilarity(left.aspectRatio, right.aspectRatio);
  }

  static double _rawAspectSimilarity(double leftRatio, double rightRatio) {
    final minRatio = math.min(leftRatio, rightRatio);
    final maxRatio = math.max(leftRatio, rightRatio);
    if (maxRatio <= 0) return 0;
    return (minRatio / maxRatio).clamp(0, 1).toDouble();
  }

  static double _gridLumaSimilarity(
    img.Image left,
    img.Image right, {
    required int size,
    required double cropFraction,
  }) {
    final leftGrid = _sampleLumaGrid(
      left,
      size: size,
      cropFraction: cropFraction,
    );
    final rightGrid = _sampleLumaGrid(
      right,
      size: size,
      cropFraction: cropFraction,
    );

    var totalDiff = 0.0;
    for (var index = 0; index < leftGrid.length; index++) {
      totalDiff += (leftGrid[index] - rightGrid[index]).abs() / 255.0;
    }

    final meanDiff = totalDiff / leftGrid.length;
    return (1 - meanDiff).clamp(0, 1).toDouble();
  }

  static double _edgeGridSimilarity(
    img.Image left,
    img.Image right, {
    required int size,
    required double cropFraction,
  }) {
    final leftGrid = _sampleLumaGrid(
      left,
      size: size,
      cropFraction: cropFraction,
    );
    final rightGrid = _sampleLumaGrid(
      right,
      size: size,
      cropFraction: cropFraction,
    );
    final leftEdges = _buildEdgeGrid(leftGrid, size);
    final rightEdges = _buildEdgeGrid(rightGrid, size);

    var totalDiff = 0.0;
    for (var index = 0; index < leftEdges.length; index++) {
      totalDiff += (leftEdges[index] - rightEdges[index]).abs();
    }

    final meanDiff = totalDiff / leftEdges.length;
    return (1 - meanDiff).clamp(0, 1).toDouble();
  }

  static double _colorLayoutSimilarity(
    img.Image left,
    img.Image right, {
    required int divisions,
    required double cropFraction,
  }) {
    final leftGrid = _sampleColorGrid(
      left,
      divisions: divisions,
      cropFraction: cropFraction,
    );
    final rightGrid = _sampleColorGrid(
      right,
      divisions: divisions,
      cropFraction: cropFraction,
    );

    var totalDiff = 0.0;
    for (var index = 0; index < leftGrid.length; index++) {
      totalDiff += (leftGrid[index] - rightGrid[index]).abs() / 255.0;
    }

    final meanDiff = totalDiff / leftGrid.length;
    return (1 - meanDiff).clamp(0, 1).toDouble();
  }

  /// Silhouette (shape) similarity: binarizes both images into foreground /
  /// background using adaptive thresholding, then compares the binary masks
  /// using Intersection-over-Union (IoU / Jaccard index).
  ///
  /// This captures actual shape: a circular rotor mask will differ
  /// dramatically from an L-shaped adapter mask, even when their luminance
  /// distributions are similar at low resolution.
  static double _silhouetteSimilarity(
    img.Image left,
    img.Image right, {
    required int size,
    required double cropFraction,
  }) {
    final leftGrid = _sampleLumaGrid(
      left,
      size: size,
      cropFraction: cropFraction,
    );
    final rightGrid = _sampleLumaGrid(
      right,
      size: size,
      cropFraction: cropFraction,
    );

    // Adaptive threshold: mean luminance of each image
    final leftMean = leftGrid.reduce((a, b) => a + b) / leftGrid.length;
    final rightMean = rightGrid.reduce((a, b) => a + b) / rightGrid.length;

    // Binarize: foreground = pixels darker than the mean (product on white bg)
    var intersection = 0;
    var union = 0;
    for (var i = 0; i < leftGrid.length; i++) {
      final leftFg = leftGrid[i] < leftMean;
      final rightFg = rightGrid[i] < rightMean;
      if (leftFg || rightFg) union++;
      if (leftFg && rightFg) intersection++;
    }

    // Both images entirely white / no foreground → treat as match
    if (union == 0) return 1.0;

    return (intersection / union).clamp(0.0, 1.0);
  }

  static List<double> _sampleLumaGrid(
    img.Image source, {
    required int size,
    required double cropFraction,
  }) {
    final values = <double>[];
    final region = _sampleRegion(source, cropFraction);
    final width = region.$3;
    final height = region.$4;

    for (var y = 0; y < size; y++) {
      final sampleY =
          _sampleCoordinate(region.$2, height, size, y, source.height);
      for (var x = 0; x < size; x++) {
        final sampleX =
            _sampleCoordinate(region.$1, width, size, x, source.width);
        final pixel = source.getPixel(sampleX, sampleY);
        values.add(_pixelLuminance(pixel));
      }
    }

    return values;
  }

  static List<double> _sampleColorGrid(
    img.Image source, {
    required int divisions,
    required double cropFraction,
  }) {
    final values = <double>[];
    final region = _sampleRegion(source, cropFraction);
    final width = region.$3;
    final height = region.$4;

    for (var y = 0; y < divisions; y++) {
      final sampleY = _sampleCoordinate(
        region.$2,
        height,
        divisions,
        y,
        source.height,
      );
      for (var x = 0; x < divisions; x++) {
        final sampleX = _sampleCoordinate(
          region.$1,
          width,
          divisions,
          x,
          source.width,
        );
        final pixel = source.getPixel(sampleX, sampleY);
        values.add(pixel.r.toDouble());
        values.add(pixel.g.toDouble());
        values.add(pixel.b.toDouble());
      }
    }

    return values;
  }

  static List<double> _buildEdgeGrid(List<double> lumaGrid, int size) {
    final values = <double>[];

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final index = y * size + x;
        final current = lumaGrid[index];
        final right = x + 1 < size ? lumaGrid[index + 1] : current;
        final down = y + 1 < size ? lumaGrid[index + size] : current;
        values.add(((current - right).abs() + (current - down).abs()) / 510.0);
      }
    }

    return values;
  }

  static (int, int, double, double) _sampleRegion(
    img.Image source,
    double cropFraction,
  ) {
    final normalizedFraction = cropFraction.clamp(0.1, 1.0);
    final regionWidth = source.width * normalizedFraction;
    final regionHeight = source.height * normalizedFraction;
    final startX =
        ((source.width - regionWidth) / 2).round().clamp(0, source.width - 1);
    final startY = ((source.height - regionHeight) / 2)
        .round()
        .clamp(0, source.height - 1);

    return (startX, startY, regionWidth, regionHeight);
  }

  static int _sampleCoordinate(
    int start,
    double span,
    int divisions,
    int index,
    int max,
  ) {
    final coordinate = start + (((index + 0.5) * span) / divisions).floor();
    return coordinate.clamp(0, max - 1);
  }

  static double _pixelLuminance(img.Pixel pixel) {
    return pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
  }
}
