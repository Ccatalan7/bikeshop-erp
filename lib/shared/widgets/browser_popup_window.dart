import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../utils/browser_passkey_policy.dart';

/// Calidad de las señales que entrega la plataforma para una ventana nueva.
///
/// Android sólo garantiza el [CreateWindowAction.windowId] y el transporte al
/// WebView hijo. La URL puede ser `null`, `about:blank` o incluso la imagen que
/// estaba bajo el dedo, y no entrega de forma fiable navigationType/features.
/// Tratar esos campos como intención de navegación separa el popup de su
/// `window.opener` y rompe los inicios de sesión.
enum BrowserPopupDispositionSupport {
  androidTransportOnly,
  reliableHints,
}

const browserPopupOpenCaptureMaxUrlLength = 8192;
const browserPopupOpenCaptureMaxQueueLength = 8;
const browserPopupOpenCaptureMaxAgeMilliseconds = 30000;
const browserPopupExplicitLoadFallbackDelay = Duration(milliseconds: 750);
const browserPopupExplicitLoadFallbackProbeAttempts = 2;

const browserPopupRuntimeIsBlankJavaScriptSource =
    "location.href === '' || location.href === 'about:blank'";

enum BrowserPopupExplicitLoadFallbackOutcome {
  loaded,
  notNeeded,
  inactive,
  probeFailed,
}

/// Ejecuta como máximo una carga de rescate y deja las esperas/sondas
/// inyectables para probar la carrera sin construir un WebView nativo.
Future<BrowserPopupExplicitLoadFallbackOutcome>
    runBrowserPopupExplicitLoadFallback({
  required Future<void> Function(Duration delay) wait,
  required bool Function() isActive,
  required Future<Object?> Function() probeRuntimeIsBlank,
  required Future<void> Function() load,
  Duration delay = browserPopupExplicitLoadFallbackDelay,
  int probeAttempts = browserPopupExplicitLoadFallbackProbeAttempts,
}) async {
  for (var attempt = 0; attempt < probeAttempts; attempt++) {
    await wait(delay);
    if (!isActive()) return BrowserPopupExplicitLoadFallbackOutcome.inactive;

    Object? runtimeIsBlank;
    try {
      runtimeIsBlank = await probeRuntimeIsBlank();
    } catch (_) {
      continue;
    }
    if (!isActive()) return BrowserPopupExplicitLoadFallbackOutcome.inactive;
    if (runtimeIsBlank == false) {
      return BrowserPopupExplicitLoadFallbackOutcome.notNeeded;
    }
    if (runtimeIsBlank != true) continue;

    await load();
    return BrowserPopupExplicitLoadFallbackOutcome.loaded;
  }
  return BrowserPopupExplicitLoadFallbackOutcome.probeFailed;
}

/// Script mínimo que conserva la semántica de `window.open` y recuerda sólo
/// su destino HTTP(S) real.
///
/// Android construye [CreateWindowAction.request] desde el hit-test bajo el
/// dedo, no desde el primer argumento de `window.open`; por eso puede entregar
/// una imagen de la página en lugar del login. La cola vive únicamente dentro
/// del documento, está acotada y nunca cruza un JavaScript handler: el plugin
/// imprime los argumentos de esos handlers en builds debug y podría filtrar
/// query params OAuth. El callback nativo consume la cola mediante una
/// expresión constante antes de hospedar la ventana hija.
String get browserPopupOpenCaptureUserScriptSource => '''
(() => {
  const takeName = '__vinabikeTakeBrowserPopupOpenUrl';
  if (typeof window[takeName] === 'function') return;

  const nativeOpen = window.open;
  if (typeof nativeOpen !== 'function') return;

  const queue = [];
  const maxUrlLength = $browserPopupOpenCaptureMaxUrlLength;
  const maxQueueLength = $browserPopupOpenCaptureMaxQueueLength;
  const maxAgeMilliseconds = $browserPopupOpenCaptureMaxAgeMilliseconds;

  Object.defineProperty(window, takeName, {
    configurable: false,
    enumerable: false,
    writable: false,
    value: () => {
      const now = Date.now();
      const entry = queue.shift();
      if (!entry ||
          !Number.isFinite(entry.capturedAt) ||
          now - entry.capturedAt > maxAgeMilliseconds) return null;
      return typeof entry.url === 'string' ? entry.url : null;
    },
  });

  window.open = function(...args) {
    const rawUrl = args[0];
    const entry = {url: null, capturedAt: Date.now()};
    if (typeof rawUrl === 'string' &&
        rawUrl.trim().length > 0 &&
        rawUrl.length <= maxUrlLength) {
      try {
        const resolved = new URL(rawUrl, document.baseURI);
        if ((resolved.protocol === 'http:' || resolved.protocol === 'https:') &&
            resolved.host &&
            resolved.href.length <= maxUrlLength) {
          entry.url = resolved.href;
        }
      } catch (_) {}
    }
    if (queue.length >= maxQueueLength) queue.shift();
    queue.push(entry);

    const removePendingEntry = () => {
      const index = queue.indexOf(entry);
      if (index >= 0) queue.splice(index, 1);
    };
    try {
      const openedWindow = Reflect.apply(nativeOpen, this, args);
      if (openedWindow === null) removePendingEntry();
      return openedWindow;
    } catch (error) {
      removePendingEntry();
      throw error;
    }
  };
})();
''';

String get browserPopupOpenDequeueJavaScriptSource => '''
(() => {
  const take = window.__vinabikeTakeBrowserPopupOpenUrl;
  return typeof take === 'function' ? take() : null;
})()
''';

UserScript browserPopupOpenCaptureUserScript() => UserScript(
      groupName: 'VinabikeBrowserPopupOpenCapture',
      source: browserPopupOpenCaptureUserScriptSource,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    );

WebUri? browserPopupOpenUrlFromEvaluation(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > browserPopupOpenCaptureMaxUrlLength) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return WebUri(uri.toString());
}

Future<WebUri?> takeCapturedBrowserPopupOpenUrl(
  InAppWebViewController controller,
) async {
  try {
    final value = await controller.evaluateJavascript(
      source: browserPopupOpenDequeueJavaScriptSource,
    );
    return browserPopupOpenUrlFromEvaluation(value);
  } catch (_) {
    return null;
  }
}

/// El plugin imprime URLs y payloads de handlers por defecto en debug. El
/// navegador embebido registra sus propios eventos seguros, así que su logger
/// interno se apaga antes de crear cualquier WebView que pueda manejar OAuth o
/// credenciales.
void disableBrowserWebViewPluginDebugLogging() {
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
}

BrowserPopupDispositionSupport get currentBrowserPopupDispositionSupport =>
    defaultTargetPlatform == TargetPlatform.android
        ? BrowserPopupDispositionSupport.androidTransportOnly
        : BrowserPopupDispositionSupport.reliableHints;

/// Ventana emergente que conserva su ventana madre.
///
/// Un `window.open` no es sólo «otra página»: la ventana hija le responde a
/// quien la abrió (`window.opener.postMessage`, y después `window.close()`).
/// Los inicios de sesión —AliExpress entre ellos— se apoyan en eso. Volver a
/// pedir esa URL en otra pestaña rompe el vínculo: la sesión nunca vuelve al
/// origen y lo que queda a la vista es la página suelta del popup, sin
/// encabezado ni navegación. Hospedar la ventana con su `windowId` mantiene el
/// vínculo intacto (2026-08-07).
/// Decide si una ventana nueva es un popup —que debe conservar su ventana
/// madre— o un simple `target="_blank"`, que se abre mejor como otra pestaña.
///
/// Toda ventana nueva trae `windowId`, así que ese dato no distingue nada.
///
/// La regla es por defecto conservadora, y esa dirección importa: **se hospeda
/// salvo que sea un enlace que la persona tocó**. Exigir que el popup declare
/// tamaño o esconda barras —como se intentó primero— deja fuera al caso más
/// común de todos, `window.open(url)` a secas, que es justamente como abren su
/// ventana los inicios de sesión. Perder ese caso es perder el login entero,
/// mientras que hospedar de más sólo cambia dónde se ve una página.
///
/// Una ventana sin URL sólo puede ser conducida por quien la abrió
/// (`window.open('')` y después `win.location = …`), así que se hospeda
/// siempre: reabrirla por su cuenta es imposible.
bool shouldHostPopupWindow({
  String? url,
  String? navigationType,
  bool? isDialog,
  double? width,
  double? height,
  bool? toolbarsVisibility,
  bool? menuBarVisibility,
  BrowserPopupDispositionSupport dispositionSupport =
      BrowserPopupDispositionSupport.reliableHints,
}) {
  if (dispositionSupport ==
      BrowserPopupDispositionSupport.androidTransportOnly) {
    return true;
  }

  final target = url?.trim() ?? '';
  if (target.isEmpty || target == 'about:blank') return true;
  if (isDialog == true) return true;
  if ((width ?? 0) > 0 || (height ?? 0) > 0) return true;
  if (toolbarsVisibility == false || menuBarVisibility == false) return true;
  return navigationType != 'LINK_ACTIVATED';
}

/// Host inicial que es seguro mostrar antes de que el WebView hijo navegue.
///
/// En Android la URL de la solicitud no identifica necesariamente la ventana
/// hija. El título se adopta de `onLoadStart/onLoadStop`, cuando ya pertenece
/// al WebView correcto.
String? browserPopupInitialHost({
  required String? requestUrl,
  BrowserPopupDispositionSupport dispositionSupport =
      BrowserPopupDispositionSupport.reliableHints,
}) {
  if (dispositionSupport ==
      BrowserPopupDispositionSupport.androidTransportOnly) {
    return null;
  }
  final uri = Uri.tryParse(requestUrl?.trim() ?? '');
  return uri?.host.isNotEmpty == true ? uri!.host : null;
}

/// Único owner que hospeda una ventana hija preservando su `windowId`.
bool hostBrowserPopupWindow({
  required BuildContext context,
  required CreateWindowAction action,
  required InAppWebViewSettings settings,
  BrowserPopupDispositionSupport? dispositionSupport,
  WebUri? explicitInitialUrl,
}) {
  final support = dispositionSupport ?? currentBrowserPopupDispositionSupport;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BrowserPopupWindow(
          windowId: action.windowId,
          settings: settings,
          explicitInitialUrl: explicitInitialUrl,
          initialHost: browserPopupInitialHost(
            requestUrl: action.request.url?.toString(),
            dispositionSupport: support,
          ),
        ),
      ),
    ),
  );
  return true;
}

/// Retira la ruta que posee el WebView que solicitó el cierre.
///
/// Un popup padre puede recibir `onCloseWindow` mientras una hija anidada está
/// arriba. Hacer un `pop` ciego cerraría la hija equivocada y dejaría vivo al
/// padre que el sitio ya cerró.
void closeBrowserPopupRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null) return;
  final navigator = Navigator.of(context);
  if (route.isCurrent) {
    navigator.pop();
  } else {
    navigator.removeRoute(route);
  }
}

class BrowserPopupWindow extends StatefulWidget {
  const BrowserPopupWindow({
    super.key,
    required this.windowId,
    required this.settings,
    this.initialHost,
    this.explicitInitialUrl,
  });

  final int windowId;
  final InAppWebViewSettings settings;
  final String? initialHost;
  final WebUri? explicitInitialUrl;

  @override
  State<BrowserPopupWindow> createState() => _BrowserPopupWindowState();
}

class _BrowserPopupWindowState extends State<BrowserPopupWindow> {
  static final _popupInitialUserScripts = UnmodifiableListView<UserScript>([
    browserPopupOpenCaptureUserScript(),
    browserPasskeyUnavailableUserScript(),
  ]);

  late String _host = widget.initialHost ?? '';
  bool _isLoading = true;

  void _close() {
    if (!mounted) return;
    closeBrowserPopupRoute(context);
  }

  void _adoptUrl(WebUri? url) {
    final host = url?.host ?? '';
    if (host.isEmpty || host == _host || !mounted) return;
    setState(() => _host = host);
  }

  void _handleWebViewCreated(InAppWebViewController controller) {
    final explicitInitialUrl = widget.explicitInitialUrl;
    if (explicitInitialUrl == null) return;
    unawaited(
      _loadExplicitInitialUrlIfStillBlank(controller, explicitInitialUrl),
    );
  }

  Future<void> _loadExplicitInitialUrlIfStillBlank(
    InAppWebViewController controller,
    WebUri explicitInitialUrl,
  ) async {
    // Chromium ya trae una navegación pendiente dentro del windowId. Hay que
    // darle tiempo para reanudarla: cargar de inmediato repite el handshake
    // OAuth y puede invalidar su state. Sólo se usa la URL capturada como
    // rescate si el documento hijo sigue siendo realmente about:blank.
    try {
      final outcome = await runBrowserPopupExplicitLoadFallback(
        wait: (delay) => Future<void>.delayed(delay),
        isActive: () => mounted,
        probeRuntimeIsBlank: () => controller.evaluateJavascript(
          source: browserPopupRuntimeIsBlankJavaScriptSource,
        ),
        load: () async {
          // FlutterWebView.makeInitialLoad adjunta el WebView hijo al
          // WebViewTransport antes de onWebViewCreated. Este fallback conserva
          // ese browsing context y, por tanto, window.opener.
          await controller.loadUrl(
            urlRequest: URLRequest(url: explicitInitialUrl),
          );
        },
      );
      if (outcome == BrowserPopupExplicitLoadFallbackOutcome.probeFailed &&
          mounted &&
          _isLoading) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  Future<bool> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    final support = currentBrowserPopupDispositionSupport;
    final explicitInitialUrl =
        support == BrowserPopupDispositionSupport.androidTransportOnly
            ? await takeCapturedBrowserPopupOpenUrl(controller)
            : null;
    if (!mounted) return false;
    return hostBrowserPopupWindow(
      context: context,
      action: action,
      settings: widget.settings,
      dispositionSupport: support,
      explicitInitialUrl: explicitInitialUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar',
          onPressed: _close,
        ),
        title: Text(
          _host.isEmpty ? 'Ventana del sitio' : _host,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: InAppWebView(
        windowId: widget.windowId,
        initialSettings: widget.settings,
        initialUserScripts:
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? _popupInitialUserScripts
                : null,
        onWebViewCreated: _handleWebViewCreated,
        // Un proveedor de identidad puede encadenar más de una ventana. Cada
        // hija conserva el opener de la anterior en vez de convertirse en una
        // pestaña independiente del ERP.
        onCreateWindow: _handleCreateWindow,
        // Android drives a transported child window only when the navigation
        // callback is declared.
        //
        // The parent WebView has always had `shouldOverrideUrlLoading`; the
        // popup it hosts never did, and that asymmetry is what broke the
        // AliExpress sign-in. Declaring the callback flips
        // `useShouldOverrideUrlLoading` on in the native layer, and with it the
        // pending OAuth navigation inherited through the `windowId` is actually
        // performed. Without it the child stayed on its blank document forever
        // — the white popup with nothing in it (2026-08-10).
        //
        // Measured on a release build of this exact commit: without this line
        // the popup is blank; with it, Google's sign-in page renders. It is not
        // a debug-only difference — a debug build hid the bug because it never
        // reached this state.
        shouldOverrideUrlLoading: (_, __) async => NavigationActionPolicy.ALLOW,
        onLoadStart: (_, url) {
          _adoptUrl(url);
          if (mounted && !_isLoading) setState(() => _isLoading = true);
        },
        onLoadStop: (_, url) {
          _adoptUrl(url);
          if (mounted && _isLoading) setState(() => _isLoading = false);
        },
        onReceivedError: (_, __, ___) {
          if (mounted && _isLoading) setState(() => _isLoading = false);
        },
        // El sitio cierra su propia ventana cuando termina de autenticar; si
        // la superficie no se va con ella, el usuario queda mirando una página
        // en blanco creyendo que falló.
        onCloseWindow: (_) => _close(),
      ),
    );
  }
}
