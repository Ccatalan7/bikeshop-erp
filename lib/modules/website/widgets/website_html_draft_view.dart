import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_html_draft_client.dart';
import '../services/website_service.dart';
import 'website_editor_chrome_geometry.dart';

/// The «Vista HTML» of the editor (phase 5c of the move to HTML): the open
/// page as the store's HTML server draws it from the unsaved draft, redrawn
/// a moment after each change of the panel. A click on a block selects it
/// in the panel, as on the Flutter canvas; links and forms do nothing.
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
  bool _supported = true;

  /// How long the view waits after a change before asking again: typing in
  /// a field sends one request when the operator pauses, not one per key.
  static const _settle = Duration(milliseconds: 350);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<WebsiteEditModeProvider>();
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_changed);
      _provider = provider..addListener(_changed);
      _changed(immediately: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _provider?.removeListener(_changed);
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _changed({bool immediately = false}) {
    final provider = _provider;
    if (provider == null || !mounted) return;
    final document = provider.document;
    final supported = websiteHtmlDraftSupports(
      pageId: document.pageId,
      pageSlug: document.pageSlug,
      catalogCanvas: provider.catalogCanvas != null,
    );
    if (supported != _supported) setState(() => _supported = supported);
    if (provider.selectedBlockId != _selected) {
      _selected = provider.selectedBlockId;
      _markSelection();
    }
    if (!supported) return;
    final body = websiteHtmlDraftBody(
      pageId: document.pageId,
      pageSlug: document.pageSlug,
      blocks: document.blocks,
      settings: {
        ...provider.pendingSiteSettings,
        ...provider.pendingHeaderSettings,
        ...provider.pendingThemeSettings,
        ...provider.pendingFooterSettings,
      },
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
      data: html,
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

  void _picked(List<dynamic> arguments) {
    final provider = _provider;
    if (provider == null) return;
    final id = arguments.isEmpty ? null : arguments.first?.toString();
    if (id == null || id.isEmpty) {
      provider.selectBlock(null);
    } else if (provider.getBlock(id) != null) {
      provider.selectBlock(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = context.select<WebsiteEditModeProvider, DevicePreviewMode>(
      (provider) => provider.devicePreviewMode,
    );
    return ColoredBox(
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
                      'La vista HTML todavía no dibuja las páginas del '
                      'catálogo ni la ficha de producto. Usa el lienzo para '
                      'esta página.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Center(
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: InAppWebView(
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        isInspectable: kDebugMode,
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
    );
  }
}
