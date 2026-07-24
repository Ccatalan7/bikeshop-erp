import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

class WebsitePreparedImage {
  const WebsitePreparedImage({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.originalByteLength,
    required this.hasTransparency,
    required this.wasNormalized,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final int originalByteLength;
  final bool hasTransparency;
  final bool wasNormalized;

  double get sourceReductionRatio =>
      originalByteLength <= 0 ? 0 : 1 - (bytes.length / originalByteLength);
}

/// Prepares a bounded source object before the authenticated WebP optimizer.
///
/// This is intentionally not the public derivative. It prevents very large
/// phone/camera files from exhausting the Edge Function while keeping enough
/// source quality for a 1920 px website derivative and future reprocessing.
class WebsiteImageUploadProcessor {
  const WebsiteImageUploadProcessor._();

  static const int maxInputBytes = 15 * 1024 * 1024;
  static const int maxSourceBytes = 4600 * 1024;
  static const int maxSourceLongEdge = 2500;

  static Future<WebsitePreparedImage> prepare({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('La imagen está vacía.');
    }
    if (bytes.length > maxInputBytes) {
      throw const FormatException(
        'La imagen supera 15 MB. Elige el archivo original, no una exportación '
        'sin comprimir.',
      );
    }

    final payload = await compute(
      _prepareWebsiteImage,
      <String, Object>{
        'bytes': bytes,
        'fileName': fileName,
      },
    );
    return WebsitePreparedImage(
      bytes: payload['bytes']! as Uint8List,
      fileName: payload['fileName']! as String,
      contentType: payload['contentType']! as String,
      width: payload['width']! as int,
      height: payload['height']! as int,
      originalWidth: payload['originalWidth']! as int,
      originalHeight: payload['originalHeight']! as int,
      originalByteLength: payload['originalByteLength']! as int,
      hasTransparency: payload['hasTransparency']! as bool,
      wasNormalized: payload['wasNormalized']! as bool,
    );
  }
}

Map<String, Object> _prepareWebsiteImage(Map<String, Object> request) {
  final bytes = request['bytes']! as Uint8List;
  final fileName = request['fileName']! as String;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException(
      'No se pudo leer la imagen. Usa JPG, PNG o WebP.',
    );
  }
  if (decoded.numFrames > 1) {
    throw const FormatException(
      'Los GIF animados no se publican como imagen. Usa un bloque de video '
      'para evitar archivos pesados.',
    );
  }

  final originalWidth = decoded.width;
  final originalHeight = decoded.height;
  var prepared = img.bakeOrientation(decoded);
  var wasNormalized =
      prepared.width != originalWidth || prepared.height != originalHeight;

  if (_longEdge(prepared) > WebsiteImageUploadProcessor.maxSourceLongEdge) {
    prepared = _resizeToLongEdge(
      prepared,
      WebsiteImageUploadProcessor.maxSourceLongEdge,
    );
    wasNormalized = true;
  }

  final hasTransparency = _hasMeaningfulTransparency(prepared);
  final inputType =
      lookupMimeType(fileName, headerBytes: bytes)?.toLowerCase() ?? '';
  final inputIsReusable = inputType == 'image/jpeg' ||
      inputType == 'image/png' ||
      inputType == 'image/webp';
  Uint8List preparedBytes = bytes;
  var preparedName = fileName;
  var contentType = inputType;

  if (wasNormalized ||
      !inputIsReusable ||
      bytes.length > WebsiteImageUploadProcessor.maxSourceBytes) {
    final encoded = _encodeBoundedSource(
      prepared,
      hasTransparency: hasTransparency,
    );
    prepared = encoded.$1;
    preparedBytes = encoded.$2;
    final base = _baseName(fileName);
    if (hasTransparency) {
      preparedName = '$base-source.png';
      contentType = 'image/png';
    } else {
      preparedName = '$base-source.jpg';
      contentType = 'image/jpeg';
    }
    wasNormalized = true;
  }

  return <String, Object>{
    'bytes': preparedBytes,
    'fileName': preparedName,
    'contentType':
        contentType.isEmpty ? 'application/octet-stream' : contentType,
    'width': prepared.width,
    'height': prepared.height,
    'originalWidth': originalWidth,
    'originalHeight': originalHeight,
    'originalByteLength': bytes.length,
    'hasTransparency': hasTransparency,
    'wasNormalized': wasNormalized,
  };
}

(img.Image, Uint8List) _encodeBoundedSource(
  img.Image source, {
  required bool hasTransparency,
}) {
  var image = source;
  var quality = 92;
  for (var attempt = 0; attempt < 5; attempt++) {
    final encoded = Uint8List.fromList(
      hasTransparency
          ? img.encodePng(image, level: 9)
          : img.encodeJpg(image, quality: quality),
    );
    if (encoded.length <= WebsiteImageUploadProcessor.maxSourceBytes) {
      return (image, encoded);
    }

    final ratio = WebsiteImageUploadProcessor.maxSourceBytes / encoded.length;
    final nextEdge = (_longEdge(image) * math.sqrt(ratio.clamp(.16, .94)) * .94)
        .round()
        .clamp(720, _longEdge(image) - 1);
    image = _resizeToLongEdge(image, nextEdge);
    quality = (quality - 5).clamp(78, 92);
  }

  final encoded = Uint8List.fromList(
    hasTransparency
        ? img.encodePng(image, level: 9)
        : img.encodeJpg(image, quality: 78),
  );
  if (encoded.length > WebsiteImageUploadProcessor.maxSourceBytes) {
    throw const FormatException(
      'No se pudo preparar una versión web segura de esta imagen.',
    );
  }
  return (image, encoded);
}

bool _hasMeaningfulTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  final stepX = (image.width / 180).ceil().clamp(1, image.width);
  final stepY = (image.height / 180).ceil().clamp(1, image.height);
  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      if (image.getPixel(x, y).a < 250) return true;
    }
  }
  return false;
}

img.Image _resizeToLongEdge(img.Image image, int maxEdge) {
  if (image.width >= image.height) {
    return img.copyResize(
      image,
      width: maxEdge,
      interpolation: img.Interpolation.cubic,
    );
  }
  return img.copyResize(
    image,
    height: maxEdge,
    interpolation: img.Interpolation.cubic,
  );
}

int _longEdge(img.Image image) =>
    image.width >= image.height ? image.width : image.height;

String _baseName(String fileName) {
  final clean = fileName.trim().replaceAll(RegExp(r'\.[^.]+$'), '');
  return clean.isEmpty ? 'website-image' : clean;
}
