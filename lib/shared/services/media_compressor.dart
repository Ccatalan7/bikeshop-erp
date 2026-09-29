import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// Un video ya comprimido, dentro de las carpetas de la app.
class CompressedVideo {
  const CompressedVideo({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}

/// Por qué no se pudo comprimir, dicho para el operador.
class MediaCompressionException implements Exception {
  const MediaCompressionException(this.code, this.message);

  /// `too_long`, `too_large`, `failed`, `unreadable`, `unsupported`.
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Achica fotos y videos que pasan los topes de WhatsApp Cloud API (5 MB la
/// foto, 16 MB el video) en vez de rechazarlos.
///
/// - **Fotos:** en Dart, en cualquier plataforma, en un isolate. JPEG ≤ 5 MB,
///   lado largo ≤ 2560 px, orientación EXIF aplicada y fondo blanco donde había
///   transparencia. (El menú Compartir de Android ya lo hace nativo antes de
///   llegar acá, y además convierte HEIC.)
/// - **Videos:** sólo Android, con Media3 (`VideoCompressor.kt`): H.264 con la
///   tasa que cabe según la duración. Un PDF no se comprime: se rehace con
///   pérdida y sin garantía, así que conserva su tope.
class MediaCompressor {
  MediaCompressor({MethodChannel? channel, bool? videoSupported})
      : _channel = channel ?? const MethodChannel(channelName),
        _videoSupported = videoSupported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (_videoSupported) _channel.setMethodCallHandler(_handleCall);
  }

  static const String channelName = 'com.vinabike.erp/media_compressor';

  static final MediaCompressor instance = MediaCompressor();

  final MethodChannel _channel;
  final bool _videoSupported;
  final Map<String, void Function(int percent)> _progress = {};
  int _serial = 0;

  bool get canCompressVideo => _videoSupported;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'compressProgress') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final percent = arguments['percent'];
    _progress[arguments['id']]?.call(percent is num ? percent.toInt() : 0);
  }

  /// Comprime el video en [path] hasta [maxBytes]. [path] tiene que estar en
  /// las carpetas de la app (lote compartido o copia del selector de archivos).
  Future<CompressedVideo> compressVideo({
    required String path,
    required int maxBytes,
    String? id,
    void Function(int percent)? onProgress,
  }) async {
    if (!_videoSupported) {
      throw const MediaCompressionException(
        'unsupported',
        'Este equipo no comprime videos.',
      );
    }
    final jobId =
        id ?? 'video-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
    if (onProgress != null) _progress[jobId] = onProgress;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'compressVideo',
        {'id': jobId, 'path': path, 'maxBytes': maxBytes},
      );
      final outputPath = result?['path'];
      final size = result?['sizeBytes'];
      if (outputPath is! String || size is! num) {
        throw const MediaCompressionException(
          'failed',
          'El teléfono no pudo comprimir este video.',
        );
      }
      return CompressedVideo(path: outputPath, sizeBytes: size.toInt());
    } on PlatformException catch (error) {
      throw MediaCompressionException(
        error.code,
        error.message ?? 'El teléfono no pudo comprimir este video.',
      );
    } finally {
      _progress.remove(jobId);
    }
  }

  /// Corta una compresión en curso (la pantalla se cerró).
  Future<void> cancel(String id) async {
    if (!_videoSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } catch (_) {}
  }

  /// JPEG ≤ [maxBytes], o `null` si la imagen no se puede leer (por ejemplo
  /// HEIC en escritorio).
  static Future<Uint8List?> compressImage(
    Uint8List bytes, {
    required int maxBytes,
  }) =>
      compute(_compressImage, (bytes, maxBytes));
}

/// Nombre del archivo ya comprimido: misma base, extensión nueva.
String compressedFileName(String name, String extension) {
  final base =
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  return '${base.isEmpty ? 'archivo' : base}.$extension';
}

Uint8List? _compressImage((Uint8List, int) arguments) {
  final (bytes, maxBytes) = arguments;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (image.hasAlpha) {
    // JPEG no tiene transparencia: sin fondo, lo transparente sale negro.
    final background = img.Image(width: image.width, height: image.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(background, image);
  }
  for (final longest in const [2560, 2048, 1600, 1280]) {
    final candidate = image.width >= image.height
        ? (image.width > longest
            ? img.copyResize(image, width: longest)
            : image)
        : (image.height > longest
            ? img.copyResize(image, height: longest)
            : image);
    for (final quality in const [86, 74, 62]) {
      final encoded = img.encodeJpg(candidate, quality: quality);
      if (encoded.length <= maxBytes) return encoded;
    }
  }
  return null;
}
