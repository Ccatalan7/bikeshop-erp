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
/// Lo que sí distingue es cómo la pidió el sitio: un `window.open` con tamaño
/// o sin barras es una ventana de trabajo —inicios de sesión, pagos,
/// verificaciones— que le responde a quien la abrió. Un enlace con
/// `target="_blank"` no declara nada de eso.
bool shouldHostPopupWindow({
  bool? isDialog,
  bool? androidIsDialog,
  double? width,
  double? height,
  bool? toolbarsVisibility,
  bool? menuBarVisibility,
}) {
  if (isDialog == true || androidIsDialog == true) return true;
  if ((width ?? 0) > 0 || (height ?? 0) > 0) return true;
  return toolbarsVisibility == false || menuBarVisibility == false;
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
