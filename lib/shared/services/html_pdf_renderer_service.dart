import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

typedef HtmlPdfFallbackRenderer = Future<Uint8List> Function(
  String html,
  PdfPageFormat format,
);

/// Runs a JavaScript-rendered template and returns the finished document as
/// static HTML.
typedef HtmlPrintablePreparer = Future<String> Function(
  String html, {
  String? readySelector,
  String? readyFlag,
  Duration timeout,
});

/// Converts the shared browser HTML document into PDF bytes.
///
/// macOS and Android deliberately use an app-owned native renderer, and for
/// the same reason on each side: the `printing` plugin's deprecated HTML
/// converter is not reliable enough to file an invoice with.
///
/// * On macOS it builds a detached, zero-sized WKWebView and asks WebKit for a
///   PDF after a fixed one-second delay. Whether that succeeds varies by
///   WebKit version and machine.
/// * On Android it holds no reference to the WebView it converts with, and its
///   PDF helper overrides neither `onLayoutFailed` nor `onWriteFailed`, so a
///   conversion that is collected or that fails never calls back and the
///   future is never completed. Measured 2026-09-04: the same document in the
///   same process returned 200 kB in 2.2 s on one run and hung on the next.
///
/// The app-owned hosts keep the job alive, wait for the document, images and
/// the renderer's explicit ready flag, and always answer.
class HtmlPdfRendererService {
  HtmlPdfRendererService({
    MethodChannel? channel,
    bool? useNativeHostOverride,
    bool? preRenderBeforeConversionOverride,
    HtmlPdfFallbackRenderer? fallbackRenderer,
    HtmlPrintablePreparer? printablePreparer,
    Duration nativeTimeout = const Duration(seconds: 30),
  })  : _channel = channel ?? const MethodChannel(channelName),
        _useNativeHostOverride = useNativeHostOverride,
        _preRenderBeforeConversionOverride = preRenderBeforeConversionOverride,
        _fallbackRenderer = fallbackRenderer ?? _renderWithPrinting,
        _printablePreparer = printablePreparer ?? prepareWithHeadlessWebView,
        _nativeTimeout = nativeTimeout;

  static const channelName = 'com.vinabike.erp/html_pdf_renderer';
  static const renderMethod = 'renderHtml';

  final MethodChannel _channel;
  final bool? _useNativeHostOverride;
  final bool? _preRenderBeforeConversionOverride;
  final HtmlPdfFallbackRenderer _fallbackRenderer;
  final HtmlPrintablePreparer _printablePreparer;
  final Duration _nativeTimeout;

  bool get _useNativeHost =>
      _useNativeHostOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.android));

  /// macOS runs the template inside its own renderer, so it prints the live
  /// document. Every other target draws the template in a headless view first
  /// and prints the finished, script-free copy: the phone's print pipeline
  /// lays the page out itself, and a static document removes the question of
  /// whether it ran the script at all.
  bool get _preRendersBeforeConversion =>
      _preRenderBeforeConversionOverride ??
      (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS);

  Future<Uint8List> render({
    required String html,
    PdfPageFormat format = PdfPageFormat.standard,
    String? readySelector,
    String? readyFlag,
  }) async {
    if (html.trim().isEmpty) {
      throw ArgumentError.value(html, 'html', 'El documento está vacío.');
    }

    final preRender = _preRendersBeforeConversion;
    // The platform converter prints a plain WebView with JavaScript OFF on
    // Android, and this template draws its whole body from JavaScript, so the
    // phone filed an empty page as the invoice (owner, 2026-09-03; the OCR
    // review still looked right because the handoff also carries the parsed
    // data). Run the template first, print the finished document.
    final String printable;
    if (preRender) {
      try {
        printable = await _printablePreparer(
          html,
          readySelector: readySelector,
          readyFlag: readyFlag,
          timeout: _nativeTimeout,
        ).timeout(_nativeTimeout * 2);
      } catch (error) {
        throw StateError(
          'No se pudo preparar la plantilla antes de convertirla a PDF. '
          'Detalle: $error',
        );
      }
    } else {
      printable = html;
    }

    debugPrint(
      '🖨️ [HtmlPdfRenderer] converting ${printable.length} chars to PDF on '
      '${kIsWeb ? 'web' : defaultTargetPlatform.name} '
      '(${_useNativeHost ? 'app host' : 'platform converter'}, '
      'pre-rendered: $preRender)',
    );

    final Uint8List bytes;
    if (_useNativeHost) {
      bytes = await _renderOnNativeHost(
        printable,
        format,
        // A pre-rendered document has no scripts left to set the flag; the
        // filled element is what proves it is the drawn invoice and not the
        // empty shell.
        readySelector: readySelector,
        readyFlag: preRender ? null : readyFlag,
      );
    } else {
      bytes = await _fallbackRenderer(printable, format)
          .timeout(_nativeTimeout * 2);
    }
    debugPrint('🖨️ [HtmlPdfRenderer] converted ${bytes.length} bytes');

    if (!hasPdfHeader(bytes)) {
      throw const FormatException(
        'El renderizador devolvió un archivo que no es un PDF válido.',
      );
    }
    return bytes;
  }

  Future<Uint8List> _renderOnNativeHost(
    String html,
    PdfPageFormat format, {
    String? readySelector,
    String? readyFlag,
  }) async {
    try {
      final rendered = await _channel.invokeMethod<Uint8List>(
        renderMethod,
        <String, Object?>{
          'html': html,
          'viewportWidth': format.width,
          'viewportHeight': format.height,
          'readySelector': readySelector,
          'readyFlag': readyFlag,
          'timeoutMillis': _nativeTimeout.inMilliseconds,
        },
        // The host carries the same deadline and answers with the stage it
        // was stuck on; give it room to do that before giving up blind.
      ).timeout(_nativeTimeout + const Duration(seconds: 5));
      if (rendered == null) {
        throw StateError('El renderizador nativo no devolvió un PDF.');
      }
      return rendered;
    } on MissingPluginException {
      throw StateError(
        'El renderizador PDF de esta aplicación no está disponible en esta '
        'versión instalada.',
      );
    } on TimeoutException {
      throw TimeoutException(
        'El equipo tardó demasiado en preparar la plantilla para PDF.',
        _nativeTimeout,
      );
    }
  }

  @visibleForTesting
  static bool hasPdfHeader(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D;

  /// Renders [html] in a headless web view with JavaScript enabled, waits for
  /// the same readiness contract the macOS host honours, and returns the
  /// finished DOM as static HTML with its scripts removed.
  ///
  /// Static output is what makes the result identical on every printer path:
  /// nothing is left to run, or to fail to run, inside the converter.
  @visibleForTesting
  static Future<String> prepareWithHeadlessWebView(
    String html, {
    String? readySelector,
    String? readyFlag,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startedAt = DateTime.now();
    void trace(String phase, [Object? detail]) {
      debugPrint(
        '🖨️ [HtmlPdfRenderer] $phase '
        '+${DateTime.now().difference(startedAt).inMilliseconds}ms'
        '${detail == null ? '' : ' $detail'}',
      );
    }

    final loaded = Completer<void>();
    HeadlessInAppWebView? webView;
    try {
      trace('headless.create');
      webView = HeadlessInAppWebView(
        initialSize: const Size(816, 1056), // Letter at 96 dpi.
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          incognito: true,
        ),
        initialData: InAppWebViewInitialData(
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        onLoadStop: (_, __) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedError: (_, __, ___) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedHttpError: (_, __, ___) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      // Every await here talks to a platform view. A call that never answers
      // used to hang the whole invoice with the progress dialog spinning
      // forever (owner, 2026-09-04), so each one carries its own deadline and
      // the caller wraps the lot in a hard timeout.
      trace('headless.run');
      await webView.run().timeout(timeout);
      trace('headless.awaiting-load');
      await loaded.future.timeout(timeout);
      trace('headless.loaded');
      final controller = webView.webViewController;
      if (controller == null) {
        throw StateError('El renderizador oculto no expuso su controlador.');
      }

      final probe = readinessProbeSource(
        readySelector: readySelector,
        readyFlag: readyFlag,
      );
      final deadline = DateTime.now().add(timeout);
      var polls = 0;
      while (true) {
        polls++;
        final ready = await controller
            .evaluateJavascript(source: probe)
            .timeout(const Duration(seconds: 5));
        if (ready == true || ready == 1 || ready.toString() == 'true') break;
        if (!DateTime.now().isBefore(deadline)) {
          throw TimeoutException(
            'La plantilla no terminó de dibujarse antes de imprimirla.',
            timeout,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      trace('headless.ready', 'polls=$polls');

      final serialized = await controller
          .evaluateJavascript(source: serializeDocumentSource)
          .timeout(const Duration(seconds: 10));
      final printable = serialized?.toString().trim() ?? '';
      if (printable.isEmpty) {
        throw StateError('El renderizador oculto devolvió un documento vacío.');
      }
      trace('headless.serialized', 'chars=${printable.length}');
      return printable;
    } finally {
      // Never awaited: on Android tearing the offscreen view down can outlive
      // the work it was created for, and the finished document must not wait
      // for it.
      final disposing = webView?.dispose();
      if (disposing != null) {
        unawaited(disposing.catchError((Object error) {
          debugPrint('🖨️ [HtmlPdfRenderer] headless.dispose failed: $error');
        }));
      }
      trace('headless.released');
    }
  }

  /// True once the template says it is done: its ready flag is set, the ready
  /// element exists **and holds content**, and every image has finished.
  @visibleForTesting
  static String readinessProbeSource({
    String? readySelector,
    String? readyFlag,
  }) {
    final flagCheck = readyFlag == null
        ? 'true'
        : 'Boolean(globalThis[${jsonEncode(readyFlag)}])';
    final selectorCheck = readySelector == null
        ? 'true'
        : 'Boolean((document.querySelector(${jsonEncode(readySelector)}) || {})'
            '.childElementCount)';
    return '''
(function () {
  try {
    var images = Array.prototype.slice.call(document.images || []);
    return Boolean(
      $flagCheck &&
      $selectorCheck &&
      images.every(function (image) { return image.complete; })
    );
  } catch (error) {
    return false;
  }
})()
''';
  }

  /// The finished DOM, without scripts: what the converter prints is exactly
  /// what the template already drew.
  @visibleForTesting
  static const String serializeDocumentSource = '''
(function () {
  var clone = document.documentElement.cloneNode(true);
  var scripts = clone.querySelectorAll('script');
  for (var index = 0; index < scripts.length; index++) {
    scripts[index].parentNode.removeChild(scripts[index]);
  }
  return '<!doctype html>\\n' + clone.outerHTML;
})()
''';

  /// Android and iOS convert through the platform WebView print pipeline.
  ///
  /// `Printing.info().canConvertHtml` is not the gate: the Android plugin
  /// implements `convertHtml` but never reports that key, so the flag read as
  /// `false` on every phone and the owner saw «Este equipo no puede convertir
  /// la plantilla» on a device that could (2026-09-03). The attempt itself is
  /// the capability check; only a missing implementation is "cannot".
  static Future<Uint8List> _renderWithPrinting(
    String html,
    PdfPageFormat format,
  ) async {
    try {
      // The template carries its own page padding and the macOS host prints
      // it edge to edge; printer margins on top would shrink the phone copy.
      final edgeToEdge = format.copyWith(
        marginLeft: 0,
        marginTop: 0,
        marginRight: 0,
        marginBottom: 0,
      );
      // Non-macOS targets keep their platform implementation. macOS never
      // reaches this deprecated API.
      // ignore: deprecated_member_use
      return await Printing.convertHtml(html: html, format: edgeToEdge);
    } on MissingPluginException {
      throw UnsupportedError(
        'Este equipo no puede convertir la plantilla HTML de AliExpress.',
      );
    } on UnimplementedError {
      throw UnsupportedError(
        'Este equipo no puede convertir la plantilla HTML de AliExpress.',
      );
    } on PlatformException catch (error) {
      if (error.code.toLowerCase().contains('unimplemented') ||
          error.code.toLowerCase().contains('unsupported')) {
        throw UnsupportedError(
          'Este equipo no puede convertir la plantilla HTML de AliExpress.',
        );
      }
      rethrow;
    }
  }
}
