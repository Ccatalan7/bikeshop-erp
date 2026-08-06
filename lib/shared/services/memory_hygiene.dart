import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Respuesta central a la presión de memoria (2026-08-05).
///
/// El 2026-08-05 el proceso de la app llegó a 41 GB de RSS y macOS pausó
/// todas las aplicaciones del sistema. Las causas de fondo se corrigieron
/// (cachés sin tope que retenían imágenes decodificadas), pero la app además
/// debe defenderse sola: cuando el sistema avisa presión de memoria —o cuando
/// el RSS supera el umbral en escritorio, donde macOS no siempre avisa a
/// tiempo— se liberan las cachés transitorias recuperables. Todo lo que se
/// libera aquí se puede volver a calcular o descargar; nunca estado de negocio.
class MemoryHygiene {
  MemoryHygiene._();

  static const _watchdogInterval = Duration(minutes: 2);
  static const _minRunInterval = Duration(minutes: 5);

  /// Umbral del watchdog de escritorio. La app en uso normal ronda
  /// 0.5–1.5 GB; superar 4 GB indica acumulación, no uso legítimo.
  static const _rssThresholdBytes = 4 * 1024 * 1024 * 1024;

  static final List<VoidCallback> _transientCaches = <VoidCallback>[];
  static Timer? _watchdog;
  static DateTime? _lastRun;

  static int get _rssBytes => kIsWeb ? 0 : ProcessInfo.currentRss;

  /// Un dueño de caché transitoria registra aquí cómo vaciarse.
  /// Registrar una sola vez por dueño; el registro no deduplica.
  static void registerTransientCache(VoidCallback clear) {
    _transientCaches.add(clear);
  }

  /// Vigila el RSS en plataformas nativas. En móvil el sistema avisa vía
  /// [WidgetsBindingObserver.didHaveMemoryPressure]; en macOS ese aviso puede
  /// llegar tarde o no llegar, así que el umbral local es la red de seguridad.
  static void startWatchdog() {
    if (kIsWeb) return;
    _watchdog ??= Timer.periodic(_watchdogInterval, (_) {
      if (_rssBytes >= _rssThresholdBytes) {
        unawaited(releaseTransientMemory(reason: 'RSS sobre umbral'));
      }
    });
  }

  static void stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  static Future<void> onSystemMemoryPressure() =>
      releaseTransientMemory(reason: 'aviso del sistema');

  @visibleForTesting
  static void debugResetForTest() {
    _transientCaches.clear();
    _lastRun = null;
    stopWatchdog();
  }

  /// Libera cachés recuperables: las registradas, el ImageCache del framework
  /// y la caché en memoria de los WebView (recursos, no cookies ni sesiones).
  /// Con antirrebote: correrla en ráfaga no gana nada y sí cuesta redescargas.
  static Future<void> releaseTransientMemory({required String reason}) async {
    final now = DateTime.now();
    final last = _lastRun;
    if (last != null && now.difference(last) < _minRunInterval) return;
    _lastRun = now;

    final beforeMb = _rssBytes ~/ (1024 * 1024);
    for (final clear in List<VoidCallback>.of(_transientCaches)) {
      try {
        clear();
      } catch (error) {
        debugPrint('MemoryHygiene: caché registrada falló al vaciarse: $error');
      }
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!kIsWeb) {
      try {
        await InAppWebViewController.clearAllCache(includeDiskFiles: false);
      } catch (error) {
        debugPrint('MemoryHygiene: clearAllCache de WebView falló: $error');
      }
    }
    final afterMb = _rssBytes ~/ (1024 * 1024);
    debugPrint('🧹 MemoryHygiene ($reason): RSS ${beforeMb}MB → ${afterMb}MB');
  }
}
