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

class _ForegroundComponent {
  _ForegroundComponent({
    required this.indices,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final List<int> indices;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  int get area => indices.length;
}

class _ForegroundMask {
  const _ForegroundMask({
    required this.cells,
    required this.size,
    required this.aspectRatio,
    required this.density,
    required this.componentCount,
  });

  final List<bool> cells;
  final int size;
  final double aspectRatio;
  final double density;
  final int componentCount;
}

class ProductImageSimilarityDebug {
  const ProductImageSimilarityDebug({
    required this.score,
    required this.fullGridScore,
    required this.centerGridScore,
    required this.edgeScore,
    required this.silhouetteScore,
    required this.radialShapeScore,
    required this.contourShapeScore,
    required this.foregroundShapeScore,
    required this.overlapShapeScore,
    required this.colorLayoutScore,
    required this.foregroundColorScore,
    required this.aspectScore,
    required this.shapeBoostApplied,
    required this.shapeMismatchCapApplied,
  });

  final double score;
  final double fullGridScore;
  final double centerGridScore;
  final double edgeScore;
  final double silhouetteScore;
  final double radialShapeScore;
  final double contourShapeScore;
  final double foregroundShapeScore;
  final double overlapShapeScore;
  final double colorLayoutScore;
  final double foregroundColorScore;
  final double aspectScore;
  final bool shapeBoostApplied;
  final bool shapeMismatchCapApplied;
}

class _ShapeSimilarityBreakdown {
  const _ShapeSimilarityBreakdown({
    required this.score,
    required this.radialScore,
    required this.contourScore,
    required this.foregroundScore,
    required this.overlapScore,
  });

  final double score;
  final double radialScore;
  final double contourScore;
  final double foregroundScore;
  final double overlapScore;
}

class _RadialShapeProfile {
  const _RadialShapeProfile({
    required this.radius,
    required this.mass,
  });

  final List<double> radius;
  final List<double> mass;
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
    return detailedSimilarityDebugFromBytes(leftBytes, rightBytes)?.score ?? 0;
  }

  static ProductImageSimilarityDebug? detailedSimilarityDebugFromBytes(
    Uint8List leftBytes,
    Uint8List rightBytes,
  ) {
    final leftImage = img.decodeImage(leftBytes);
    final rightImage = img.decodeImage(rightBytes);
    if (leftImage == null || rightImage == null) return null;
    if (leftImage.width == 0 || leftImage.height == 0) return null;
    if (rightImage.width == 0 || rightImage.height == 0) return null;

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
    // Higher-resolution silhouette: 48x48 cells over an 88% crop. The
    // earlier 24x24 grid collapsed thin parts (chain links, derailleur
    // hangers) into a single dark blob, hiding obvious shape mismatches.
    final shapeBreakdown = _silhouetteSimilarity(
      leftImage,
      rightImage,
      size: 48,
      cropFraction: 0.88,
    );
    final silhouetteScore = shapeBreakdown.score;
    final colorLayoutScore = _colorLayoutSimilarity(
      leftImage,
      rightImage,
      divisions: 3,
      cropFraction: 0.85,
    );
    final foregroundColorScore = _foregroundColorSimilarity(
      leftImage,
      rightImage,
    );
    final aspectScore = _rawAspectSimilarity(
      leftImage.width / leftImage.height,
      rightImage.width / rightImage.height,
    );

    // Shape-first weighting:
    //   * Silhouette is the only signal that actually answers "is this the
    //     same physical outline?" — it must dominate, otherwise centered
    //     objects on white background all look alike to luma grids.
    //   * Edge layout backs that up: same outline → similar edge map.
    //   * Foreground color catches "silver vs black" without letting the
    //     shared white studio background wash the score upward.
    //   * Luma grids stay only as a tiebreaker when shape + color agree.
    var detailedScore = silhouetteScore * 0.48 +
        edgeScore * 0.20 +
        foregroundColorScore * 0.14 +
        colorLayoutScore * 0.06 +
        centerGridScore * 0.06 +
        fullGridScore * 0.03 +
        aspectScore * 0.03;

    // Strong-shape boost: silhouette IoU + edges agree → very likely the
    // same physical part regardless of luma grid noise.
    var shapeBoostApplied = false;
    var shapeMismatchCapApplied = false;
    if (silhouetteScore >= 0.78 && edgeScore >= 0.75) {
      shapeBoostApplied = true;
      detailedScore = math.max(
        detailedScore,
        0.85 + foregroundColorScore * 0.10,
      );
    }
    // Hard shape mismatch suppresses everything: if silhouettes/contours do
    // not agree, the parts are not the same physical thing even if luma,
    // edge, or background-heavy color grids coincidentally match.
    if (silhouetteScore < 0.45) {
      shapeMismatchCapApplied = true;
      detailedScore = math.min(detailedScore, 0.36);
    } else if (silhouetteScore < 0.58 && shapeBreakdown.overlapScore < 0.20) {
      shapeMismatchCapApplied = true;
      detailedScore = math.min(detailedScore, 0.44);
    } else if (shapeBreakdown.contourScore < 0.42 &&
        shapeBreakdown.overlapScore < 0.24) {
      shapeMismatchCapApplied = true;
      detailedScore = math.min(detailedScore, 0.46);
    } else if (foregroundColorScore < 0.55 && silhouetteScore < 0.72) {
      shapeMismatchCapApplied = true;
      detailedScore = math.min(detailedScore, 0.50);
    }

    return ProductImageSimilarityDebug(
      score: detailedScore.clamp(0, 1).toDouble(),
      fullGridScore: fullGridScore,
      centerGridScore: centerGridScore,
      edgeScore: edgeScore,
      silhouetteScore: silhouetteScore,
      radialShapeScore: shapeBreakdown.radialScore,
      contourShapeScore: shapeBreakdown.contourScore,
      foregroundShapeScore: shapeBreakdown.foregroundScore,
      overlapShapeScore: shapeBreakdown.overlapScore,
      colorLayoutScore: colorLayoutScore,
      foregroundColorScore: foregroundColorScore,
      aspectScore: aspectScore,
      shapeBoostApplied: shapeBoostApplied,
      shapeMismatchCapApplied: shapeMismatchCapApplied,
    );
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

  static double _foregroundColorSimilarity(img.Image left, img.Image right) {
    final leftSignature = _foregroundColorSignature(left);
    final rightSignature = _foregroundColorSignature(right);
    if (leftSignature == null && rightSignature == null) return 1;
    if (leftSignature == null || rightSignature == null) return 0;

    final redDiff = (leftSignature.red - rightSignature.red).abs() / 255;
    final greenDiff = (leftSignature.green - rightSignature.green).abs() / 255;
    final blueDiff = (leftSignature.blue - rightSignature.blue).abs() / 255;
    final rgbDiff = math.sqrt(
      (redDiff * redDiff + greenDiff * greenDiff + blueDiff * blueDiff) / 3,
    );
    final lumaDiff = (leftSignature.luma - rightSignature.luma).abs() / 255;
    final saturationDiff =
        (leftSignature.saturation - rightSignature.saturation).abs();

    return (1 - (rgbDiff * 0.65 + lumaDiff * 0.20 + saturationDiff * 0.15))
        .clamp(0, 1)
        .toDouble();
  }

  static ({
    double red,
    double green,
    double blue,
    double luma,
    double saturation,
  })? _foregroundColorSignature(img.Image source) {
    final working = _resizeForShapeAnalysis(source);
    final background = _estimateBackgroundColor(working);
    final backgroundLuma = _rgbLuminance(
      background.$1,
      background.$2,
      background.$3,
    );

    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var count = 0;

    for (var y = 0; y < working.height; y++) {
      for (var x = 0; x < working.width; x++) {
        final pixel = working.getPixel(x, y);
        if (pixel.a <= 24) continue;

        final redDiff = pixel.r.toDouble() - background.$1;
        final greenDiff = pixel.g.toDouble() - background.$2;
        final blueDiff = pixel.b.toDouble() - background.$3;
        final colorDistance = math.sqrt(
          redDiff * redDiff + greenDiff * greenDiff + blueDiff * blueDiff,
        );
        final lumaDiff = (_pixelLuminance(pixel) - backgroundLuma).abs();
        if (colorDistance < 34 && lumaDiff < 26) continue;

        red += pixel.r.toDouble();
        green += pixel.g.toDouble();
        blue += pixel.b.toDouble();
        count++;
      }
    }

    if (count < 12) return null;
    red /= count;
    green /= count;
    blue /= count;
    final luma = _rgbLuminance(red, green, blue);
    final maxChannel = math.max(red, math.max(green, blue));
    final minChannel = math.min(red, math.min(green, blue));
    final saturation =
        maxChannel <= 0 ? 0.0 : (maxChannel - minChannel) / maxChannel;

    return (
      red: red,
      green: green,
      blue: blue,
      luma: luma,
      saturation: saturation,
    );
  }

  /// Silhouette (shape) similarity: binarizes both images into foreground /
  /// background using adaptive thresholding, then compares the binary masks
  /// using Intersection-over-Union (IoU / Jaccard index).
  ///
  /// This captures actual shape: a circular rotor mask will differ
  /// dramatically from an L-shaped adapter mask, even when their luminance
  /// distributions are similar at low resolution.
  static _ShapeSimilarityBreakdown _silhouetteSimilarity(
    img.Image left,
    img.Image right, {
    required int size,
    required double cropFraction,
  }) {
    final leftMask = _normalizedForegroundMask(left, size: size);
    final rightMask = _normalizedForegroundMask(right, size: size);

    if (leftMask == null && rightMask == null) {
      return const _ShapeSimilarityBreakdown(
        score: 1,
        radialScore: 1,
        contourScore: 1,
        foregroundScore: 1,
        overlapScore: 1,
      );
    }
    if (leftMask == null || rightMask == null) {
      return const _ShapeSimilarityBreakdown(
        score: 0,
        radialScore: 0,
        contourScore: 0,
        foregroundScore: 0,
        overlapScore: 0,
      );
    }

    final shapeBreakdown = _bestMaskShapeSimilarity(
      leftMask.cells,
      rightMask.cells,
      size,
    );
    final aspectScore = _rawAspectSimilarity(
      leftMask.aspectRatio,
      rightMask.aspectRatio,
    );
    final densityScore =
        (1 - (leftMask.density - rightMask.density).abs()).clamp(0, 1);
    final componentScore =
        math.min(leftMask.componentCount, rightMask.componentCount) /
            math.max(leftMask.componentCount, rightMask.componentCount);

    final score = (shapeBreakdown.score * 0.84 +
            aspectScore * 0.07 +
            densityScore * 0.04 +
            componentScore * 0.05)
        .clamp(0.0, 1.0)
        .toDouble();

    return _ShapeSimilarityBreakdown(
      score: score,
      radialScore: shapeBreakdown.radialScore,
      contourScore: shapeBreakdown.contourScore,
      foregroundScore: shapeBreakdown.foregroundScore,
      overlapScore: shapeBreakdown.overlapScore,
    );
  }

  static _ForegroundMask? _normalizedForegroundMask(
    img.Image source, {
    required int size,
  }) {
    final working = _resizeForShapeAnalysis(source);
    final width = working.width;
    final height = working.height;
    if (width == 0 || height == 0) return null;

    final background = _estimateBackgroundColor(working);
    final backgroundLuma = _rgbLuminance(
      background.$1,
      background.$2,
      background.$3,
    );
    final foreground = List<bool>.filled(width * height, false);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = working.getPixel(x, y);
        final alpha = pixel.a.toDouble();
        if (alpha <= 24) continue;

        final redDiff = pixel.r.toDouble() - background.$1;
        final greenDiff = pixel.g.toDouble() - background.$2;
        final blueDiff = pixel.b.toDouble() - background.$3;
        final colorDistance = math.sqrt(
          redDiff * redDiff + greenDiff * greenDiff + blueDiff * blueDiff,
        );
        final lumaDiff = (_pixelLuminance(pixel) - backgroundLuma).abs();
        foreground[y * width + x] = colorDistance >= 34 || lumaDiff >= 26;
      }
    }

    final components = _foregroundComponents(foreground, width, height)
      ..sort((a, b) => b.area.compareTo(a.area));
    if (components.isEmpty) return null;

    final largestArea = components.first.area;
    if (largestArea < 12) return null;

    final minKeptArea = math.max(12, (largestArea * 0.10).round());
    final kept = List<bool>.filled(width * height, false);
    var minX = width - 1;
    var minY = height - 1;
    var maxX = 0;
    var maxY = 0;
    var keptArea = 0;
    var keptComponentCount = 0;

    for (final component in components) {
      if (component.area < minKeptArea) continue;
      keptComponentCount++;
      keptArea += component.area;
      minX = math.min(minX, component.minX);
      minY = math.min(minY, component.minY);
      maxX = math.max(maxX, component.maxX);
      maxY = math.max(maxY, component.maxY);
      for (final index in component.indices) {
        kept[index] = true;
      }
    }

    if (keptArea < 12 || maxX <= minX || maxY <= minY) return null;

    final bboxWidth = maxX - minX + 1;
    final bboxHeight = maxY - minY + 1;
    final padX = math.max(1, (bboxWidth * 0.08).round());
    final padY = math.max(1, (bboxHeight * 0.08).round());
    minX = math.max(0, minX - padX);
    minY = math.max(0, minY - padY);
    maxX = math.min(width - 1, maxX + padX);
    maxY = math.min(height - 1, maxY + padY);

    final normalizedCells = <bool>[];
    for (var cellY = 0; cellY < size; cellY++) {
      for (var cellX = 0; cellX < size; cellX++) {
        var hits = 0;
        for (var sampleY = 0; sampleY < 3; sampleY++) {
          final sourceY = minY +
              (((cellY + (sampleY + 0.5) / 3) * (maxY - minY + 1)) / size)
                  .floor();
          for (var sampleX = 0; sampleX < 3; sampleX++) {
            final sourceX = minX +
                (((cellX + (sampleX + 0.5) / 3) * (maxX - minX + 1)) / size)
                    .floor();
            final index = sourceY.clamp(0, height - 1) * width +
                sourceX.clamp(0, width - 1);
            if (kept[index]) hits++;
          }
        }
        // Require at least two of the nine sub-samples so tiny text/noise and
        // one-pixel threshold specks don't fatten the normalized silhouette
        // into a generic blob.
        normalizedCells.add(hits >= 2);
      }
    }

    final normalizedArea = normalizedCells.where((cell) => cell).length;
    if (normalizedArea == 0) return null;

    return _ForegroundMask(
      cells: normalizedCells,
      size: size,
      aspectRatio: (maxX - minX + 1) / (maxY - minY + 1),
      density: normalizedArea / normalizedCells.length,
      componentCount: math.max(1, keptComponentCount),
    );
  }

  static img.Image _resizeForShapeAnalysis(img.Image source) {
    final longestSide = math.max(source.width, source.height);
    if (longestSide <= 320) return source;
    final scale = 320 / longestSide;
    return img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
    );
  }

  static (double, double, double) _estimateBackgroundColor(img.Image source) {
    final sampleWidth = math.max(2, (source.width * 0.08).round());
    final sampleHeight = math.max(2, (source.height * 0.08).round());
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var count = 0;

    void sampleRect(int startX, int startY) {
      final endX = math.min(source.width, startX + sampleWidth);
      final endY = math.min(source.height, startY + sampleHeight);
      for (var y = startY; y < endY; y++) {
        for (var x = startX; x < endX; x++) {
          final pixel = source.getPixel(x, y);
          if (pixel.a <= 24) continue;
          red += pixel.r;
          green += pixel.g;
          blue += pixel.b;
          count++;
        }
      }
    }

    sampleRect(0, 0);
    sampleRect(math.max(0, source.width - sampleWidth), 0);
    sampleRect(0, math.max(0, source.height - sampleHeight));
    sampleRect(
      math.max(0, source.width - sampleWidth),
      math.max(0, source.height - sampleHeight),
    );

    if (count == 0) return (255, 255, 255);
    return (red / count, green / count, blue / count);
  }

  static List<_ForegroundComponent> _foregroundComponents(
    List<bool> foreground,
    int width,
    int height,
  ) {
    final visited = List<bool>.filled(foreground.length, false);
    final components = <_ForegroundComponent>[];

    for (var startIndex = 0; startIndex < foreground.length; startIndex++) {
      if (!foreground[startIndex] || visited[startIndex]) continue;

      final stack = <int>[startIndex];
      final indices = <int>[];
      var minX = width - 1;
      var minY = height - 1;
      var maxX = 0;
      var maxY = 0;
      visited[startIndex] = true;

      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        indices.add(index);
        final x = index % width;
        final y = index ~/ width;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);

        for (var offsetY = -1; offsetY <= 1; offsetY++) {
          for (var offsetX = -1; offsetX <= 1; offsetX++) {
            if (offsetX == 0 && offsetY == 0) continue;
            final nextX = x + offsetX;
            final nextY = y + offsetY;
            if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height) {
              continue;
            }
            final nextIndex = nextY * width + nextX;
            if (!foreground[nextIndex] || visited[nextIndex]) continue;
            visited[nextIndex] = true;
            stack.add(nextIndex);
          }
        }
      }

      components.add(_ForegroundComponent(
        indices: indices,
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
      ));
    }

    return components;
  }

  static double _maskIntersectionOverUnion(
    List<bool> left,
    List<bool> right,
    int size,
  ) {
    var intersection = 0;
    var union = 0;
    for (var index = 0; index < size * size; index++) {
      final leftValue = left[index];
      final rightValue = right[index];
      if (leftValue || rightValue) union++;
      if (leftValue && rightValue) intersection++;
    }
    if (union == 0) return 1.0;
    return (intersection / union).clamp(0.0, 1.0).toDouble();
  }

  static _ShapeSimilarityBreakdown _bestMaskShapeSimilarity(
    List<bool> left,
    List<bool> right,
    int size,
  ) {
    final variants = <List<bool>>[
      right,
      _flipMaskHorizontally(right, size),
      _flipMaskVertically(right, size),
      _rotateMask180(right, size),
      _rotateMask90(right, size),
      _rotateMask270(right, size),
    ];

    var best = const _ShapeSimilarityBreakdown(
      score: 0,
      radialScore: 0,
      contourScore: 0,
      foregroundScore: 0,
      overlapScore: 0,
    );
    for (final variant in variants) {
      final score = _maskShapeSimilarity(left, variant, size);
      if (score.score > best.score) best = score;
    }
    return best;
  }

  static _ShapeSimilarityBreakdown _maskShapeSimilarity(
    List<bool> left,
    List<bool> right,
    int size,
  ) {
    final iou = _maskIntersectionOverUnion(left, right, size);
    final leftForeground = _maskForegroundIndices(left);
    final rightForeground = _maskForegroundIndices(right);
    final leftContour = _maskContourIndices(left, size);
    final rightContour = _maskContourIndices(right, size);

    final foregroundChamfer = _bidirectionalChamferScore(
      leftForeground,
      rightForeground,
      size,
    );
    final contourChamfer = _bidirectionalChamferScore(
      leftContour.isEmpty ? leftForeground : leftContour,
      rightContour.isEmpty ? rightForeground : rightContour,
      size,
    );
    final radialScore = _radialShapeProfileSimilarity(
      left,
      right,
      size,
      bins: 48,
    );

    // IoU is only a small sanity signal. The main signals are:
    //   - radial profile: translation/scale/rotation-tolerant outline shape
    //   - contour Chamfer: every edge should be close to the other edge
    //   - foreground Chamfer: fill/holes should still broadly agree
    final score = (radialScore * 0.50 +
            contourChamfer * 0.35 +
            foregroundChamfer * 0.10 +
            iou * 0.05)
        .clamp(0.0, 1.0)
        .toDouble();

    return _ShapeSimilarityBreakdown(
      score: score,
      radialScore: radialScore,
      contourScore: contourChamfer,
      foregroundScore: foregroundChamfer,
      overlapScore: iou,
    );
  }

  static double _radialShapeProfileSimilarity(
    List<bool> left,
    List<bool> right,
    int size, {
    required int bins,
  }) {
    final leftProfile = _radialShapeProfile(left, size, bins: bins);
    final rightProfile = _radialShapeProfile(right, size, bins: bins);
    if (leftProfile == null && rightProfile == null) return 1;
    if (leftProfile == null || rightProfile == null) return 0;

    var best = 0.0;
    for (var shift = 0; shift < bins; shift++) {
      best = math.max(
        best,
        _radialProfileSimilarity(leftProfile, rightProfile, shift: shift),
      );
      best = math.max(
        best,
        _radialProfileSimilarity(
          leftProfile,
          _reverseRadialProfile(rightProfile),
          shift: shift,
        ),
      );
    }
    return best.clamp(0.0, 1.0).toDouble();
  }

  static _RadialShapeProfile? _radialShapeProfile(
    List<bool> cells,
    int size, {
    required int bins,
  }) {
    var count = 0;
    var centerX = 0.0;
    var centerY = 0.0;
    for (var index = 0; index < cells.length; index++) {
      if (!cells[index]) continue;
      centerX += index % size;
      centerY += index ~/ size;
      count++;
    }
    if (count == 0) return null;
    centerX /= count;
    centerY /= count;

    var maxRadius = 0.0;
    final radius = List<double>.filled(bins, 0);
    final mass = List<double>.filled(bins, 0);
    for (var index = 0; index < cells.length; index++) {
      if (!cells[index]) continue;
      final x = (index % size).toDouble();
      final y = (index ~/ size).toDouble();
      final dx = x - centerX;
      final dy = y - centerY;
      final distance = math.sqrt(dx * dx + dy * dy);
      maxRadius = math.max(maxRadius, distance);
    }
    if (maxRadius <= 0) return null;

    for (var index = 0; index < cells.length; index++) {
      if (!cells[index]) continue;
      final x = (index % size).toDouble();
      final y = (index ~/ size).toDouble();
      final dx = x - centerX;
      final dy = y - centerY;
      final distance = math.sqrt(dx * dx + dy * dy) / maxRadius;
      final angle = math.atan2(dy, dx);
      final normalizedAngle = angle < 0 ? angle + math.pi * 2 : angle;
      final bin = ((normalizedAngle / (math.pi * 2)) * bins).floor() % bins;
      radius[bin] = math.max(radius[bin], distance);
      mass[bin] += 1;
    }

    final maxMass = mass.fold<double>(0, math.max);
    if (maxMass > 0) {
      for (var index = 0; index < mass.length; index++) {
        mass[index] /= maxMass;
      }
    }

    return _RadialShapeProfile(radius: radius, mass: mass);
  }

  static _RadialShapeProfile _reverseRadialProfile(
    _RadialShapeProfile profile,
  ) {
    final bins = profile.radius.length;
    final radius = List<double>.filled(bins, 0);
    final mass = List<double>.filled(bins, 0);
    for (var index = 0; index < bins; index++) {
      final reversedIndex = (bins - index) % bins;
      radius[index] = profile.radius[reversedIndex];
      mass[index] = profile.mass[reversedIndex];
    }
    return _RadialShapeProfile(radius: radius, mass: mass);
  }

  static double _radialProfileSimilarity(
    _RadialShapeProfile left,
    _RadialShapeProfile right, {
    required int shift,
  }) {
    final bins = left.radius.length;
    var radiusDiff = 0.0;
    var massDiff = 0.0;
    for (var index = 0; index < bins; index++) {
      final shiftedIndex = (index + shift) % bins;
      radiusDiff += (left.radius[index] - right.radius[shiftedIndex]).abs();
      massDiff += (left.mass[index] - right.mass[shiftedIndex]).abs();
    }
    final meanRadiusDiff = radiusDiff / bins;
    final meanMassDiff = massDiff / bins;
    return (1 - (meanRadiusDiff * 0.72 + meanMassDiff * 0.28))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static List<int> _maskForegroundIndices(List<bool> cells) {
    final indices = <int>[];
    for (var index = 0; index < cells.length; index++) {
      if (cells[index]) indices.add(index);
    }
    return indices;
  }

  static List<int> _maskContourIndices(List<bool> cells, int size) {
    final indices = <int>[];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final index = y * size + x;
        if (!cells[index]) continue;
        var isContour = false;
        for (var offsetY = -1; offsetY <= 1 && !isContour; offsetY++) {
          for (var offsetX = -1; offsetX <= 1; offsetX++) {
            if (offsetX == 0 && offsetY == 0) continue;
            final nextX = x + offsetX;
            final nextY = y + offsetY;
            if (nextX < 0 || nextX >= size || nextY < 0 || nextY >= size) {
              isContour = true;
              break;
            }
            if (!cells[nextY * size + nextX]) {
              isContour = true;
              break;
            }
          }
        }
        if (isContour) indices.add(index);
      }
    }
    return indices;
  }

  static double _bidirectionalChamferScore(
    List<int> left,
    List<int> right,
    int size,
  ) {
    if (left.isEmpty && right.isEmpty) return 1.0;
    if (left.isEmpty || right.isEmpty) return 0.0;
    final leftToRight = _directedChamferScore(left, right, size);
    final rightToLeft = _directedChamferScore(right, left, size);
    return ((leftToRight + rightToLeft) / 2).clamp(0.0, 1.0).toDouble();
  }

  static double _directedChamferScore(
    List<int> source,
    List<int> target,
    int size,
  ) {
    var totalDistance = 0.0;
    for (final sourceIndex in source) {
      final sourceX = sourceIndex % size;
      final sourceY = sourceIndex ~/ size;
      var bestSquaredDistance = double.infinity;
      for (final targetIndex in target) {
        final targetX = targetIndex % size;
        final targetY = targetIndex ~/ size;
        final dx = sourceX - targetX;
        final dy = sourceY - targetY;
        final squaredDistance = (dx * dx + dy * dy).toDouble();
        if (squaredDistance < bestSquaredDistance) {
          bestSquaredDistance = squaredDistance;
          if (bestSquaredDistance == 0) break;
        }
      }
      totalDistance += math.sqrt(bestSquaredDistance);
    }

    final averageDistance = totalDistance / source.length;
    // Roughly 10% of the normalized mask width is tolerated for photo crop,
    // antialiasing, and thickness differences. Same physical parts should be
    // close to 1; truly different outlines fall off quickly.
    final tolerance = math.max(1.0, size * 0.10);
    return (1 - averageDistance / tolerance).clamp(0.0, 1.0).toDouble();
  }

  static List<bool> _flipMaskHorizontally(List<bool> cells, int size) {
    final flipped = List<bool>.filled(cells.length, false);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        flipped[y * size + x] = cells[y * size + (size - x - 1)];
      }
    }
    return flipped;
  }

  static List<bool> _flipMaskVertically(List<bool> cells, int size) {
    final flipped = List<bool>.filled(cells.length, false);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        flipped[y * size + x] = cells[(size - y - 1) * size + x];
      }
    }
    return flipped;
  }

  static List<bool> _rotateMask180(List<bool> cells, int size) {
    final rotated = List<bool>.filled(cells.length, false);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        rotated[y * size + x] = cells[(size - y - 1) * size + (size - x - 1)];
      }
    }
    return rotated;
  }

  static List<bool> _rotateMask90(List<bool> cells, int size) {
    final rotated = List<bool>.filled(cells.length, false);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        rotated[y * size + x] = cells[(size - x - 1) * size + y];
      }
    }
    return rotated;
  }

  static List<bool> _rotateMask270(List<bool> cells, int size) {
    final rotated = List<bool>.filled(cells.length, false);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        rotated[y * size + x] = cells[x * size + (size - y - 1)];
      }
    }
    return rotated;
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

  static double _rgbLuminance(double red, double green, double blue) {
    return red * 0.299 + green * 0.587 + blue * 0.114;
  }
}
