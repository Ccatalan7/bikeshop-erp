import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';

import '../models/website_catalog_canvas.dart';
import '../models/website_product_canvas.dart';
import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_html_draft_client.dart';
import '../services/website_html_draft_picks.dart';
import '../services/website_service.dart';
import '../../../shared/services/window_zoom_service.dart';
import 'website_editor_chrome_geometry.dart';

/// The «Vista HTML» of the editor (phase 5c of the move to HTML): the page
/// on screen (the home, a page, the catalog, a category, a product page) as
/// the store's HTML server draws it from the unsaved draft, redrawn a moment
/// after each change of the panel or of the route. A click on a block, the
/// header, the footer or a catalog or product page section selects it in
/// the panel, as on the Flutter canvas; links and forms do nothing.
///
/// It sits over the Flutter canvas, which stays mounted underneath, so the
/// panel, the history and the selection keep their one owner
/// ([WebsiteEditModeProvider]).
class WebsiteHtmlDraftView extends StatefulWidget {
  const WebsiteHtmlDraftView({super.key, this.client});

  @visibleForTesting
  final WebsiteHtmlDraftClient? client;

  @override
  State<WebsiteHtmlDraftView> createState() => _WebsiteHtmlDraftViewState();
}

class _WebsiteHtmlDraftViewState extends State<WebsiteHtmlDraftView> {
  late final WebsiteHtmlDraftClient _client =
      widget.client ?? WebsiteHtmlDraftClient();
  WebsiteEditModeProvider? _provider;

  /// Tells when the page on screen changes; [GoRouter.state] names it.
  GoRouter? _router;
  InAppWebViewController? _web;
  Timer? _debounce;

  /// The body of the page on screen, and of the one on its way.
  String? _shownBody;
  String? _pendingBody;
  int _sequence = 0;
  String? _selected;
  bool _loading = false;
  String? _message;
  String? _html;

  /// The route on screen has a page the server draws.
  bool _supported = true;

  /// How long the view waits after a change before asking again: typing in
  /// a field sends one request when the operator pauses, not one per key.
  static const _settle = Duration(milliseconds: 350);

  /// On the ERP on the web, the page's clicks arrive as messages.
  StreamSubscription<String?>? _webPicks;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webPicks = websiteHtmlDraftPicks().listen((id) => _picked([id]));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<WebsiteEditModeProvider>();
    final router = GoRouter.maybeOf(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_changed);
      _router = router?..routerDelegate.addListener(_changed);
    }
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_changed);
      _provider = provider..addListener(_changed);
      _changed(immediately: true);
    }
  }

  @override
  void dispose() {
    _webPicks?.cancel();
    _debounce?.cancel();
    _provider?.removeListener(_changed);
    _router?.routerDelegate.removeListener(_changed);
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _changed({bool immediately = false}) {
    final provider = _provider;
    if (provider == null || !mounted) return;
    final document = provider.document;
    final path = _path(document.pageId, document.pageSlug);
    final supported = path != null;
    if (supported != _supported) setState(() => _supported = supported);
    if (provider.selectedBlockId != _selected) {
      _selected = provider.selectedBlockId;
      _markSelection();
    }
    if (path == null) return;
    final body = websiteHtmlDraftBody(
      path: path,
      pageId: document.pageId,
      pageSlug: document.pageSlug,
      blocks: document.blocks,
      settings: _draftSettings(provider),
    );
    if (body == _shownBody || body == _pendingBody) return;
    _pendingBody = body;
    _debounce?.cancel();
    if (immediately) {
      unawaited(_draw(body));
    } else {
      _debounce = Timer(_settle, () => _draw(body));
    }
  }

  /// The public path on screen; without a router (a test), the open
  /// document's own.
  ///
  /// Measured 2026-10-07: a category entered from the catalog is pushed over
  /// it, and only [GoRouter.state] names it; the delegate's configuration and
  /// the route information still said `/tienda/productos`.
  String? _path(String? pageId, String? pageSlug) {
    final router = _router;
    if (router != null) {
      return websiteHtmlDraftPath(router.state.uri);
    }
    if (pageId == null) return '/';
    final slug = (pageSlug ?? '').trim().toLowerCase();
    return slug.isEmpty ? null : '/pagina/$slug';
  }

  /// Every unsaved setting the site's pages read: the site's (the product
  /// page template among them), the header's, the theme's and the footer's,
  /// and the catalog presentations as the registry will hold them once the
  /// draft is saved.
  Map<String, String> _draftSettings(WebsiteEditModeProvider provider) {
    final presentations = provider.pendingCatalogPresentations;
    var registry = presentations.isEmpty
        ? null
        : context.read<WebsiteService>().catalogPresentationRegistry;
    for (final presentation in presentations.values) {
      registry = registry!.put(registry.prepareForSave(presentation));
    }
    return {
      ...provider.pendingSiteSettings,
      ...provider.pendingHeaderSettings,
      ...provider.pendingThemeSettings,
      ...provider.pendingFooterSettings,
      if (registry != null)
        websiteCatalogPresentationsSettingKey: registry.encode(),
    };
  }

  Future<void> _draw(String body) async {
    final sequence = ++_sequence;
    final origin = Uri.tryParse(
      context.read<WebsiteService>().getSetting('store_url', '').trim(),
    );
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (origin == null || !origin.hasScheme || origin.host.isEmpty) {
      setState(() {
        _message = 'Falta la dirección de la tienda (Ajustes del sitio > '
            'Dominio) para dibujar la vista HTML.';
      });
      return;
    }
    if (token == null) {
      setState(() => _message = const WebsiteHtmlDraftAnswer.state(
            WebsiteHtmlDraftState.expired,
          ).message);
      return;
    }
    setState(() => _loading = true);
    final answer = await _client.draw(
      storeOrigin: origin,
      accessToken: token,
      body: body,
    );
    // A later change already asked again: this answer is old.
    if (!mounted || sequence != _sequence) return;
    _pendingBody = null;
    final html = answer.html;
    if (html == null) {
      setState(() {
        _loading = false;
        _message = answer.message;
      });
      return;
    }
    _shownBody = body;
    setState(() {
      _loading = false;
      _message = null;
      _html = html;
    });
    await _show(html, origin);
  }

  Future<void> _show(String html, Uri origin) async {
    final web = _web;
    if (web == null) return; // Shown by `onWebViewCreated`.
    // The operator keeps their place on the page across redraws.
    final y = await web.getScrollY() ?? 0;
    _restoreScroll = y;
    await web.loadData(
      // In a frame (the ERP on the web) the base URL does not reach the
      // page: its fonts, logo and photos are found through `<base>`, which
      // the server leaves out because a public page's anchors need it out.
      data: kIsWeb ? _withBase(html, origin) : html,
      mimeType: 'text/html',
      encoding: 'utf-8',
      // Relative photos, fonts and icons come from the store itself.
      baseUrl: WebUri(origin.replace(path: '/').toString()),
    );
  }

  int _restoreScroll = 0;

  Future<void> _loaded(InAppWebViewController web) async {
    if (_restoreScroll > 0) {
      await web.scrollTo(x: 0, y: _restoreScroll);
    }
    await _markSelection();
  }

  Future<void> _markSelection() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.evaluateJavascript(
        source: 'window.vbDraftPicked && '
            'window.vbDraftPicked(${jsonEncode(_selected)});',
      );
    } on Object {
      // The page is between loads; the next load marks it.
    }
  }

  /// The pointer at [position] of a page of [size], or gone (null): told to
  /// the page as fractions of its window, whatever the zoom. One call at a
  /// time; a move while one is on its way waits for it, and only the last
  /// position is sent.
  void _hover(Offset? position, Size size) {
    _hoverAt = position == null || size.isEmpty
        ? null
        : Offset(position.dx / size.width, position.dy / size.height);
    _hoverQueued = true;
    if (_hoverSending) return;
    unawaited(_sendHover());
  }

  Offset? _hoverAt;
  bool _hoverQueued = false;
  bool _hoverSending = false;

  Future<void> _sendHover() async {
    _hoverSending = true;
    while (_hoverQueued && mounted) {
      _hoverQueued = false;
      final at = _hoverAt;
      try {
        await _web?.evaluateJavascript(
          source: 'window.vbDraftHover && window.vbDraftHover('
              '${at?.dx.toStringAsFixed(4) ?? '-1'}, '
              '${at?.dy.toStringAsFixed(4) ?? '-1'});',
        );
      } on Object {
        // The page is between loads; the next move tells the new one.
      }
    }
    _hoverSending = false;
  }

  void _picked(List<dynamic> arguments) {
    final provider = _provider;
    if (provider == null) return;
    final id = arguments.isEmpty ? null : arguments.first?.toString();
    if (id == null || id.isEmpty) {
      provider.selectBlock(null);
      return;
    }
    final catalog = WebsiteCatalogSectionTarget.parse(id);
    final selectable = provider.getBlock(id) != null ||
        WebsiteEditorChromeTarget.forSelection(id) != null ||
        (catalog != null && provider.isCatalogSectionAvailable(catalog)) ||
        (WebsiteProductSectionTarget.parse(id) != null &&
            provider.productCanvas != null);
    if (selectable) provider.selectBlock(id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = context.select<WebsiteEditModeProvider, DevicePreviewMode>(
      (provider) => provider.devicePreviewMode,
    );
    final zoom = _windowZoom(context);
    // Opaque to the pointer: a click on the view never reaches the Flutter
    // canvas mounted underneath, which would select its own block there.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        key: const ValueKey('editor-html-view'),
        color: scheme.surfaceContainerHighest,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = mode == DevicePreviewMode.desktop
                ? constraints.maxWidth
                : WebsiteEditorChromeGeometry.frameWidthFor(
                    mode == DevicePreviewMode.tablet
                        ? WebsiteViewport.tablet
                        : WebsiteViewport.mobile,
                    availableWidth: constraints.maxWidth,
                  );
            return Stack(
              children: [
                if (!_supported)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'El carrito, el pago, los pedidos y la cuenta del '
                        'cliente no tienen vista HTML: se ven en el lienzo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Container(
                      width: width,
                      height: constraints.maxHeight,
                      // Framed like the canvas's tablet and phone previews.
                      decoration: mode == DevicePreviewMode.desktop
                          ? null
                          : BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                      // The native view gets no pointer moves on the desktop
                      // (measured on macOS, 2026-10-07): the page's hover
                      // mark follows the pointer as Flutter sees it. In a
                      // frame (the ERP on the web) the page sees it itself.
                      child: MouseRegion(
                        onHover: kIsWeb
                            ? null
                            : (event) => _hover(
                                  event.localPosition,
                                  Size(width, constraints.maxHeight),
                                ),
                        onExit: kIsWeb ? null : (_) => _hover(null, Size.zero),
                        // Under the ERP's window zoom the page is laid out
                        // at the width it is drawn at, so a click lands where
                        // it is seen and the page takes the canvas's band.
                        child: _ZoomedNativeView(
                          zoom: zoom,
                          child: InAppWebView(
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              isInspectable: kDebugMode,
                              pageZoom: zoom,
                              supportZoom: false,
                              transparentBackground: false,
                            ),
                            onWebViewCreated: (controller) {
                              _web = controller;
                              controller.addJavaScriptHandler(
                                handlerName: 'vbDraftPick',
                                callback: _picked,
                              );
                              final html = _html;
                              final origin = Uri.tryParse(
                                context
                                    .read<WebsiteService>()
                                    .getSetting('store_url', '')
                                    .trim(),
                              );
                              if (html != null && origin != null) {
                                unawaited(_show(html, origin));
                              }
                            },
                            onLoadStop: (controller, _) => _loaded(controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_loading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_message case final message?)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Center(
                      child: Material(
                        color: scheme.inverseSurface,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            message,
                            key: const ValueKey('editor-html-view-message'),
                            style: TextStyle(color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The ERP's window zoom ([WindowZoomService], 0.8 by default on the
/// desktop), or 1 where it does not apply.
double _windowZoom(BuildContext context) {
  if (!WindowZoomService.isDesktop) return 1.0;
  try {
    return context.watch<WindowZoomService>().scale.clamp(0.5, 3.0).toDouble();
  } on ProviderNotFoundException {
    return 1.0;
  }
}

/// Lays a native web view out so it is drawn where it is hit under the ERP's
/// window zoom, which scales the Flutter scene by [zoom].
///
/// Measured on macOS (2026-10-07, zoom 0.8): the web view's native frame
/// comes out as its logical size divided by the zoom, and the engine shrinks
/// it back to fit only in the drawing. Laid out at the canvas width (1248),
/// the page took 1559 CSS px and was drawn into 998 points, and a click on
/// the second section landed on the first. Laid out at width × zoom² and
/// drawn back with the inverse scale, the native frame is exactly the drawn
/// size, and `pageZoom = zoom` gives the page the canvas's own width (1247
/// CSS px, the same band as the Flutter canvas). Other platforms keep the
/// zoom as is: Windows is not measured yet, phones have no window zoom.
class _ZoomedNativeView extends StatelessWidget {
  const _ZoomedNativeView({required this.zoom, required this.child});

  final double zoom;
  final Widget child;

  // The structure is measured too: the same sizes under an `OverflowBox`
  // gave the page 1948 CSS px instead of 1247.
  @override
  Widget build(BuildContext context) {
    if ((zoom - 1).abs() < 0.001 ||
        defaultTargetPlatform != TargetPlatform.macOS) {
      return child;
    }
    final factor = zoom * zoom;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: SizedBox.expand(
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: 1 / factor,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: constraints.maxWidth * factor,
                height: constraints.maxHeight * factor,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [html] with a `<base>` at the store's [origin], first in its `<head>`.
String _withBase(String html, Uri origin) {
  final base = '<base href="${origin.replace(path: '/')}">';
  final head = RegExp('<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head == null) return '$base$html';
  return html.replaceRange(head.end, head.end, base);
}
