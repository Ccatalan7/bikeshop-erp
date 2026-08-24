import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'supplier_availability_service.dart';
import 'supplier_portal_probe_service.dart';
import 'supplier_portal_reading.dart';

/// Confirma disponibilidad **sin ventana y sin operador**.
///
/// Corre en un `HeadlessInAppWebView`: un navegador real, con la misma sesión y
/// las mismas cookies que la pestaña visible —en macOS el almacén de datos del
/// webview es del proceso, y la app no usa modo incógnito— pero sin ocupar
/// pantalla ni robarle el foco a nadie.
///
/// **No inicia sesión.** El inicio de sesión tiene su propio camino, con sus
/// comprobaciones de autoridad, y duplicarlo acá crearía un segundo lugar donde
/// se manejan credenciales. Este corredor usa la sesión que ya existe y, si no
/// hay, lo dice: `session_expired` es un resultado, no un fallo escondido.
class SupplierPortalHeadlessRunner {
  SupplierPortalHeadlessRunner(this._service);

  final SupplierAvailabilityService _service;

  static String? _probeSource;

  /// Cada consulta es una navegación real. Ir más rápido no sirve: el portal
  /// de RBX es de los noventa y responde cuando responde.
  static const Duration _settleDelay = Duration(milliseconds: 2200);
  static const Duration _loadTimeout = Duration(seconds: 25);

  /// Devuelve cuántas quedaron confirmadas y por qué se detuvo, si se detuvo.
  Future<SupplierPortalRunSummary> run({
    required String supplierId,
    required SupplierPortalProbe probe,
    required List<SupplierAvailabilityTarget> targets,
    void Function(int done, int total, String name)? onProgress,
  }) async {
    if (targets.isEmpty) {
      return const SupplierPortalRunSummary(checked: 0, stoppedBecause: null);
    }
    _probeSource ??= await rootBundle.loadString(
      'assets/browser/supplier_portal_probe.js',
    );

    Completer<void>? loaded;
    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        // La misma sesión que la pestaña visible: sin esto el chequeo entraría
        // siempre deslogueado y no confirmaría nada.
        incognito: false,
        cacheEnabled: true,
        clearCache: false,
        javaScriptEnabled: true,
        // Nada de ventanas emergentes ni descargas en un contexto que el
        // operador no está mirando.
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
      ),
      onLoadStop: (_, __) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedHttpError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
    );

    var checked = 0;
    String? stoppedBecause;
    try {
      await webView.run();
      final controller = webView.webViewController;
      if (controller == null) {
        return const SupplierPortalRunSummary(
          checked: 0,
          stoppedBecause: 'no_webview',
        );
      }

      for (var index = 0; index < targets.length; index++) {
        final target = targets[index];
        onProgress?.call(index, targets.length, target.name);
        final url = probe.urlForCode(target.supplierCode);

        final pending = Completer<void>();
        loaded = pending;
        await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        try {
          await pending.future.timeout(_loadTimeout);
        } on TimeoutException {
          // Una página que no termina de cargar no es un cero: se anota como
          // ilegible y se sigue con la siguiente.
          await _record(supplierId, target, url,
              const SupplierPortalReading(
                status: SupplierAvailabilityStatus.unreadable,
              ),
              '');
          checked++;
          continue;
        }
        await Future<void>.delayed(_settleDelay);

        await controller.evaluateJavascript(source: _probeSource!);
        final raw = await controller.evaluateJavascript(
          source: 'JSON.stringify(globalThis.__vinabikeSupplierProbe.probe('
              '${jsonEncode(target.supplierCode)}))',
        );
        final report = SupplierPortalProbeService.decodeReport(raw);
        if (report == null) {
          await _record(supplierId, target, url,
              const SupplierPortalReading(
                status: SupplierAvailabilityStatus.unreadable,
              ),
              '');
          checked++;
          continue;
        }
        final body = report['bodySample']?.toString() ?? '';
        final session = report['session'];
        final reading = readSupplierPortal(
          SupplierPortalObservation(
            code: target.supplierCode,
            url: url,
            bodyText: body,
            hasPasswordField:
                session is Map && session['hasPasswordField'] == true,
          ),
          probe,
        );
        await _record(supplierId, target, url, reading, body);
        checked++;

        // **Sin sesión, seguir es escribir basura.** Cada consulta siguiente
        // devolvería la misma pantalla de login, y anotarlas todas llenaría el
        // historial de falsos «no encontrado».
        if (reading.status == SupplierAvailabilityStatus.sessionExpired) {
          stoppedBecause = 'session_expired';
          break;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🛒 Chequeo de disponibilidad interrumpido: $error');
      }
      stoppedBecause ??= 'error';
    } finally {
      await webView.dispose();
    }
    return SupplierPortalRunSummary(
      checked: checked,
      stoppedBecause: stoppedBecause,
    );
  }

  Future<void> _record(
    String supplierId,
    SupplierAvailabilityTarget target,
    String url,
    SupplierPortalReading reading,
    String body,
  ) async {
    try {
      await _service.record(
        supplierId: supplierId,
        target: target,
        reading: reading,
        sourceUrl: url,
        evidenceSample: body,
      );
    } catch (error) {
      // Perder una fila no puede tumbar el recorrido completo: las demás
      // consultas siguen siendo información válida.
      if (kDebugMode) {
        debugPrint('🛒 No se pudo anotar un chequeo: ${error.runtimeType}');
      }
    }
  }
}

class SupplierPortalRunSummary {
  const SupplierPortalRunSummary({
    required this.checked,
    required this.stoppedBecause,
  });

  final int checked;

  /// `session_expired` · `error` · `no_webview` · nulo si terminó entero.
  final String? stoppedBecause;

  bool get needsLogin => stoppedBecause == 'session_expired';
}
