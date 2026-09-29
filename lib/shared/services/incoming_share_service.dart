import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Un archivo que otra app del teléfono compartió con el ERP, ya copiado a la
/// caché de la app por el receptor nativo (`IncomingShareStore.kt`).
class IncomingSharedFile {
  const IncomingSharedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  bool get isImage => mimeType.startsWith('image/');

  static IncomingSharedFile? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final name = raw['name'];
    final mimeType = raw['mimeType'];
    final size = raw['sizeBytes'];
    if (path is! String || path.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return IncomingSharedFile(
      path: path,
      name: name,
      mimeType: mimeType is String && mimeType.isNotEmpty
          ? mimeType
          : 'application/octet-stream',
      sizeBytes: size is num ? size.toInt() : 0,
    );
  }
}

/// Lo que el receptor no pudo traer, dicho como lo lee el operador.
class IncomingShareSkip {
  const IncomingShareSkip({required this.name, required this.reason});

  final String name;

  /// `limit`, `too_large` o `unreadable` (ver `IncomingShareStore.kt`).
  final String reason;

  String get explanation => switch (reason) {
        'limit' => 'Se comparten hasta 8 archivos por vez.',
        'too_large' => 'Es demasiado grande para enviarlo.',
        _ => 'El teléfono no dejó leerlo.',
      };

  static IncomingShareSkip? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final reason = raw['reason'];
    if (name is! String || reason is! String) return null;
    return IncomingShareSkip(name: name, reason: reason);
  }
}

class IncomingShareBatch {
  const IncomingShareBatch({
    required this.id,
    required this.files,
    required this.skipped,
  });

  final String id;
  final List<IncomingSharedFile> files;
  final List<IncomingShareSkip> skipped;

  bool get isEmpty => files.isEmpty && skipped.isEmpty;

  static IncomingShareBatch? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final files = <IncomingSharedFile>[
      for (final item in (raw['files'] as List?) ?? const [])
        if (IncomingSharedFile.fromChannel(item) case final file?) file,
    ];
    final skipped = <IncomingShareSkip>[
      for (final item in (raw['skipped'] as List?) ?? const [])
        if (IncomingShareSkip.fromChannel(item) case final skip?) skip,
    ];
    final batch = IncomingShareBatch(id: id, files: files, skipped: skipped);
    return batch.isEmpty ? null : batch;
  }
}

/// Recibe lo que llega desde el menú «Compartir» del teléfono.
///
/// Sólo Android tiene hoy la entrada «vb-ERP» en ese menú. El lote espera acá
/// —aunque nadie haya iniciado sesión todavía— hasta que el host global
/// (`IncomingSharePrompt`) lo toma y lo muestra una sola vez.
class IncomingShareService extends ChangeNotifier {
  IncomingShareService({MethodChannel? channel, bool? enabled})
      : _channel = channel ?? const MethodChannel(channelName),
        _enabled = enabled ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const String channelName = 'com.vinabike.erp/incoming_share';

  static final IncomingShareService instance = IncomingShareService();

  final MethodChannel _channel;
  final bool _enabled;
  bool _initialized = false;
  IncomingShareBatch? _pending;

  bool get isSupported => _enabled;
  IncomingShareBatch? get pending => _pending;

  /// Idempotente. Pide lo que haya quedado del arranque (la app se abrió desde
  /// el menú Compartir) y escucha los envíos siguientes.
  Future<void> initialize() async {
    if (!_enabled || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') await _fetchPending();
    });
    await _fetchPending();
  }

  Future<void> _fetchPending() async {
    Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('takePendingShare');
    } on PlatformException catch (error) {
      debugPrint('📥 [IncomingShare] No se pudo leer el envío: ${error.code}');
      return;
    } on MissingPluginException {
      return;
    }
    final batch = IncomingShareBatch.fromChannel(raw);
    if (batch == null) return;
    final replaced = _pending;
    _pending = batch;
    // Un envío nuevo reemplaza al que nadie alcanzó a abrir.
    if (replaced != null && replaced.id != batch.id) {
      unawaited(release(replaced));
    }
    notifyListeners();
  }

  /// Lo entrega UNA vez.
  IncomingShareBatch? take() {
    final batch = _pending;
    _pending = null;
    return batch;
  }

  /// Borra la copia en caché. Se llama al enviar, guardar o descartar.
  Future<void> release(IncomingShareBatch batch) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>('releaseShare', {'id': batch.id});
    } catch (error) {
      debugPrint('📥 [IncomingShare] No se pudo liberar ${batch.id}: $error');
    }
  }
}
