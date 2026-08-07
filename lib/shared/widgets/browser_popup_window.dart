import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
}) {
  final target = url?.trim() ?? '';
  if (target.isEmpty || target == 'about:blank') return true;
  if (isDialog == true) return true;
  if ((width ?? 0) > 0 || (height ?? 0) > 0) return true;
  if (toolbarsVisibility == false || menuBarVisibility == false) return true;
  return navigationType != 'LINK_ACTIVATED';
}

class BrowserPopupWindow extends StatefulWidget {
  const BrowserPopupWindow({
    super.key,
    required this.windowId,
    required this.settings,
    this.initialHost,
  });

  final int windowId;
  final InAppWebViewSettings settings;
  final String? initialHost;

  @override
  State<BrowserPopupWindow> createState() => _BrowserPopupWindowState();
}

class _BrowserPopupWindowState extends State<BrowserPopupWindow> {
  late String _host = widget.initialHost ?? '';
  bool _isLoading = true;

  void _close() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  void _adoptUrl(WebUri? url) {
    final host = url?.host ?? '';
    if (host.isEmpty || host == _host || !mounted) return;
    setState(() => _host = host);
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
