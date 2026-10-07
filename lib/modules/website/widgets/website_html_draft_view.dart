import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../public_store/widgets/page_composition.dart'
    show websiteReorderSeamMove;
import '../../../public_store/widgets/website_insertion_host.dart';
import '../models/website_editor_drag_payload.dart';
import '../models/website_block_catalog.dart';
import '../models/website_block_geometry.dart';
import 'block_action_bar.dart';
import 'website_inline_action_editor.dart';
import 'website_block_content_presenters.dart';
import 'website_inline_field_binding.dart';
import 'website_editor_host_theme.dart';
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

  /// The draft on screen and the one wanted.
  final _queue = WebsiteHtmlDraftQueue();
  String? _selected;
  bool _loading = false;
  String? _message;
  String? _html;

  /// The route on screen has a page the server draws.
  bool _supported = true;

  /// How long the view waits after a change before asking again: typing in
  /// a field sends one request when the operator pauses, not one per key.
  static const _settle = Duration(milliseconds: 350);

  /// On the ERP on the web, the page's clicks arrive as messages, signed
  /// with this view's [_nonce].
  StreamSubscription<WebsiteHtmlDraftMessage>? _webPicks;
  final String _nonce = [
    for (var i = 0; i < 16; i++)
      Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// The store's HTML server ([websiteHtmlDraftServer]).
  final Uri? _server = websiteHtmlDraftServer();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webPicks = websiteHtmlDraftPicks(_nonce).listen(_received);
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
    _stopWriting();
    _stopSizing();
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
    final layer = _layerOf(provider, provider.selectedBlockId);
    final layerKey = layer == null ? null : '${layer.slide}/${layer.id}';
    if (provider.selectedBlockId != _selected) {
      _selected = provider.selectedBlockId;
      _markedLayer = layerKey;
      _bring = true;
      _markSelection();
    } else if (layerKey != _markedLayer) {
      // A layer picked in the panel (or in the page) is marked where it is.
      _markedLayer = layerKey;
      _markSelection();
    }
    _showSlides();
    // The operator is writing in the page or dragging a block's height: a
    // redraw would take it from under them, so the view draws what is
    // wanted once they are done; unless the page or the block is gone.
    if (_writing case final writing?
        when writing.path != path ||
            provider.getBlock(writing.blockId) == null) {
      _stopWriting();
    }
    if (_sizing case final sizing?
        when sizing.path != path || provider.getBlock(sizing.blockId) == null) {
      _stopSizing();
    }
    if (path == null || _writing != null || _sizing != null) return;
    final body = websiteHtmlDraftBody(
      path: path,
      pageId: document.pageId,
      pageSlug: document.pageSlug,
      blocks: document.blocks,
      settings: _draftSettings(provider),
      footerNavigation: provider.hasFooterChanges
          ? websiteHtmlDraftNavigationRows(
              provider.draftedFooterNavigation(
                context.read<WebsiteService>().footerNavigation,
              ),
            )
          : null,
    );
    switch (_queue.want(body)) {
      case WebsiteHtmlDraftNeed.waiting:
        return;
      case WebsiteHtmlDraftNeed.onScreen:
        // What was scheduled or on its way is not wanted any more.
        _debounce?.cancel();
        if (_loading) setState(() => _loading = false);
      case WebsiteHtmlDraftNeed.ask:
        _debounce?.cancel();
        if (immediately) {
          unawaited(_draw(body));
        } else {
          _debounce = Timer(_settle, () => _draw(body));
        }
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
    final ticket = _queue.send();
    final origin = _server;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (origin == null) {
      _queue.failed();
      setState(() {
        _message = 'Esta versión del ERP no tiene una dirección segura del '
            'servidor de la tienda para dibujar la vista HTML.';
      });
      return;
    }
    if (token == null) {
      _queue.failed();
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
    // The draft changed meanwhile: this answer is old.
    if (!mounted || !_queue.wanted(ticket)) return;
    final html = answer.html;
    if (html == null) {
      _queue.failed();
      setState(() {
        _loading = false;
        _message = answer.message;
      });
      return;
    }
    _queue.shown(body);
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
    // (A frame of another origin, on the web, keeps no place to read.)
    _restoreScroll = kIsWeb ? 0 : await web.getScrollY() ?? 0;
    await web.loadData(
      // In a frame (the ERP on the web) the base URL does not reach the
      // page: its fonts, logo and photos are found through `<base>`, which
      // the server leaves out because a public page's anchors need it out.
      data: kIsWeb ? _withBase(html, origin, _nonce) : html,
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
    _shownSlides = null;
    _showSlides(instant: true);
  }

  /// The slide picked in the panel for each carousel of the open page, as
  /// last told to the page.
  String? _shownSlides;

  /// Turns the page's carousels to the slides picked in the panel, as the
  /// canvas shows them (`carouselSlideSelection`); at once when the page
  /// has just been drawn.
  void _showSlides({bool instant = false}) {
    final provider = _provider;
    if (provider == null) return;
    final slides = <String, int>{
      for (final block in provider.blocks)
        if ((block['block_type'] ?? block['type']) == 'carousel' &&
            block['id'] is String)
          block['id'] as String: provider.carouselSlideSelection(
            block['id'] as String,
            _slideCount(block),
          ),
    };
    final encoded = jsonEncode(slides);
    if (encoded == _shownSlides) return;
    _shownSlides = encoded;
    unawaited(_tell('vbDraftSlides', [slides, instant]));
  }

  /// How many slides a carousel block has, counted as the canvas counts
  /// them.
  static int _slideCount(Map<String, dynamic>? block) {
    final data = block?['block_data'];
    final slides = data is Map ? data['slides'] : null;
    return slides is List ? slides.whereType<Map>().length : 0;
  }

  /// A selection the page has not shown yet: the page brings it into sight
  /// once it has it (a block picked in the panel, or one just added, which
  /// only the next drawing has). A click in the page is in sight already;
  /// a redraw keeps the operator's place.
  bool _bring = false;

  Future<void> _markSelection() async {
    final web = _web;
    if (web == null || !mounted) return;
    if (kIsWeb) {
      // The page answers what it found as a message (`WebsiteHtmlDraftShown`).
      websiteHtmlDraftTell(
        _nonce,
        'vbDraftPicked',
        [_selected, _selectionInfo(), _bring],
      );
      return;
    }
    try {
      final found = await web.evaluateJavascript(
        source: 'window.vbDraftPicked && '
            'window.vbDraftPicked(${jsonEncode(_selected)}, '
            '${jsonEncode(_selectionInfo())}, $_bring);',
      );
      if (found == true) _bring = false;
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

  /// The canvas layer marked in the page: `slide/id`, or none.
  String? _markedLayer;

  /// The canvas layer picked for block [id]: the shown slide's (or -1 for a
  /// canvas block's own canvas) and its id; `null` without one.
  ({int slide, String id})? _layerOf(
    WebsiteEditModeProvider provider,
    String? id,
  ) {
    final block = id == null ? null : provider.getBlock(id);
    if (id == null || block == null) return null;
    switch ((block['block_type'] ?? block['type'] ?? '').toString()) {
      case 'carousel':
        final count = _slideCount(block);
        if (count <= 0) return null;
        final slide = provider.carouselSlideSelection(id, count);
        final layer = provider.canvasElementSelection(id, slideIndex: slide);
        return layer == null ? null : (slide: slide, id: layer);
      case 'canvas':
        final layer = provider.canvasElementSelection(id);
        return layer == null ? null : (slide: -1, id: layer);
    }
    return null;
  }

  /// A click on a canvas layer of the picked block in the page: the layer
  /// picked in the panel, as a click on it on the Flutter canvas
  /// (`selectCanvasElement`); a layer the slide or the canvas does not have
  /// is not one.
  void _pickLayer(WebsiteHtmlDraftLayer press) {
    final provider = _provider;
    final block = provider?.getBlock(press.id);
    if (provider == null ||
        block == null ||
        provider.selectedBlockId != press.id) {
      return;
    }
    final place = websiteHtmlDraftLayerPlace(block, press);
    if (place == null) return;
    provider.selectCanvasElement(
      press.id,
      press.layer,
      slideIndex: place.slide,
      slideCount: place.slide == null ? null : place.count,
    );
  }

  /// What the page needs to draw the picked part's marks: for a block of
  /// the open page, its bar (`BlockActionBar`: which moves apply, whether it
  /// is shown) in the ERP's selection colours; nothing for any other part.
  Map<String, Object?>? _selectionInfo() {
    final provider = _provider;
    final id = _selected;
    if (provider == null || id == null || provider.getBlock(id) == null) {
      return null;
    }
    final blocks = provider.blocks;
    final index = blocks.indexWhere((block) => block['id'] == id);
    if (index < 0) return null;
    final host = WebsiteEditorHostTheme.maybeOf(context);
    final theme = host?.theme ?? Theme.of(context);
    final roles = host?.roles ?? VinabikeThemeRoles.maybeOf(context);
    String css(Color color) => 'rgb(${(color.r * 255).round()} '
        '${(color.g * 255).round()} ${(color.b * 255).round()} '
        '/ ${color.a.toStringAsFixed(3)})';
    final fields = WebsiteInlineFieldBinding(
      provider: provider,
      blockId: id,
      blockType: (blocks[index]['block_type'] ?? blocks[index]['type'] ?? '')
          .toString(),
    );
    final behavior = fields.heightBehavior;
    return {
      // The height handle, for a block whose height is authored.
      if (behavior != WebsitePageBlockHeightBehavior.intrinsic)
        'height': {
          'min': fields.heightRange.min,
          'max': fields.heightRange.max,
          'exact': behavior == WebsitePageBlockHeightBehavior.exact,
        },
      // The canvas layer picked in the panel, marked in the page.
      if (_layerOf(provider, id) case final layer?)
        'layer': {'slide': layer.slide, 'id': layer.id},
      'bar': {
        'first': index == 0,
        'last': index == blocks.length - 1,
        'visible': blocks[index]['is_visible'] != false,
        'copy': true,
      },
      'fill': css(
        roles?.selectionContainer ?? theme.colorScheme.primaryContainer,
      ),
      'onFill': css(
        roles?.onSelectionContainer ?? theme.colorScheme.onPrimaryContainer,
      ),
      'danger': css(roles?.danger.accent ?? theme.colorScheme.error),
      // «Agregar aquí» as the canvas paints it (`WebsiteInsertBlockAffordance`).
      'accent': css(roles?.info.accent ?? theme.colorScheme.primary),
      'onAccent': css(roles?.info.onAccent ?? theme.colorScheme.onPrimary),
    };
  }

  void _received(WebsiteHtmlDraftMessage message) {
    switch (message) {
      case WebsiteHtmlDraftReady():
        // The page on the web is drawn and can be told things now.
        _shownSlides = null;
        unawaited(_markSelection());
        _showSlides(instant: true);
      case WebsiteHtmlDraftShown(:final found):
        if (found) _bring = false;
      case WebsiteHtmlDraftPick(:final id):
        _picked(id);
      case WebsiteHtmlDraftAction(:final id, :final action):
        _acted(id, action);
      case final WebsiteHtmlDraftEdit edit:
        _edit(edit);
      case final WebsiteHtmlDraftHeight height:
        _height(height);
      case WebsiteHtmlDraftMove(:final id, :final anchor, :final side):
        _move(id, anchor, side);
      case final WebsiteHtmlDraftButton press:
        unawaited(_button(press));
      case final WebsiteHtmlDraftLayer press:
        _pickLayer(press);
      case WebsiteHtmlDraftSlide(:final id, :final index):
        final provider = _provider;
        final count = _slideCount(provider?.getBlock(id));
        // Only the picked carousel turns with its arrows in the page.
        if (provider != null && count > 0 && provider.selectedBlockId == id) {
          provider.selectCarouselSlide(id, index, count);
        }
    }
  }

  /// A web view handler for the page's [name] message.
  JavaScriptHandlerCallback _handler(String name) => (arguments) {
        final message = WebsiteHtmlDraftMessage.fromHandler(name, arguments);
        if (message != null) _received(message);
      };

  /// A press on the picked block's bar in the page: the same actions as the
  /// bar on the Flutter canvas.
  void _acted(String id, String action) {
    final provider = _provider;
    final block = provider?.getBlock(id);
    // The bar is the picked block's: a press for any other is not one.
    if (provider == null || block == null || provider.selectedBlockId != id) {
      return;
    }
    switch (action) {
      case 'up':
        provider.moveBlockUp(id);
      case 'down':
        provider.moveBlockDown(id);
      case 'visibility':
        provider.toggleBlockVisibility(id);
      case 'duplicate':
        provider.duplicateBlock(id);
      case 'copy':
        copyWebsiteBlockForPaste(
          context,
          blockId: id,
          blockType: (block['block_type'] ?? block['type'] ?? '').toString(),
        );
      case 'delete':
        unawaited(confirmWebsiteBlockDelete(context, id));
      case 'insert-before' || 'insert-after':
        unawaited(_insert(provider, id, action));
    }
  }

  /// One button card at a time.
  bool _buttonOpen = false;

  /// The page as the editor draws it: where a button the page names is.
  final GlobalKey _pageKey = GlobalKey(debugLabel: 'editor-html-view-page');

  /// A press on one of the picked block's buttons in the page: its label,
  /// destination and look in the button's card under it
  /// ([showWebsiteButtonCard], the canvas's action fields), written as the
  /// canvas's action slot writes them ([WebsiteInlineFieldBinding.beginButton])
  /// — one step of the history, guarded from when the card opens, so a
  /// draft that changed meanwhile refuses it.
  Future<void> _button(WebsiteHtmlDraftButton press) async {
    final provider = _provider;
    final block = provider?.getBlock(press.id);
    // The buttons are the picked block's: a press for another is not one.
    if (_buttonOpen ||
        provider == null ||
        block == null ||
        provider.selectedBlockId != press.id) {
      return;
    }
    final write = WebsiteInlineFieldBinding(
      provider: provider,
      blockId: press.id,
      blockType: (block['block_type'] ?? block['type'] ?? '').toString(),
    ).beginButton(press.fields, press.index);
    if (write == null) return;
    _buttonOpen = true;
    try {
      final edited = await showWebsiteButtonCard(
        context,
        action: write.value,
        anchor: _buttonRect(press.where),
        destinationHelp: write.destinationHelp,
      );
      if (!mounted || edited == null) return;
      if (write.commit(edited)) _changed();
    } finally {
      _buttonOpen = false;
    }
  }

  /// A box the page gave as fractions of its window, in the root overlay's
  /// coordinates (the button card's), or `null`.
  Rect? _buttonRect(
    ({double left, double top, double width, double height})? where,
  ) {
    final page = _pageKey.currentContext?.findRenderObject();
    final overlay = Navigator.of(context, rootNavigator: true)
        .overlay
        ?.context
        .findRenderObject();
    if (where == null ||
        page is! RenderBox ||
        !page.hasSize ||
        overlay is! RenderBox) {
      return null;
    }
    final size = page.size;
    Offset at(double fx, double fy) => page.localToGlobal(
          Offset(fx * size.width, fy * size.height),
          ancestor: overlay,
        );
    return Rect.fromPoints(
      at(where.left, where.top),
      at(where.left + where.width, where.top + where.height),
    );
  }

  /// The picked block dropped on a seam in the page: the canvas's own move
  /// (`websiteReorderSeamMove`), re-checked against the page as it is now;
  /// the next drawing brings the block into sight where it landed.
  void _move(String id, String anchor, WebsiteHtmlDraftSide side) {
    final provider = _provider;
    if (provider == null ||
        provider.selectedBlockId != id ||
        provider.getBlock(anchor) == null) {
      return;
    }
    final document = provider.document;
    final moved = websiteReorderSeamMove(
      context,
      ExistingWebsiteBlockDragPayload(
        blockId: id,
        sessionRevision: document.sessionRevision,
        pageId: document.pageId,
        pageSlug: document.pageSlug,
      ),
      websiteBlockInsertionIntent(
        provider,
        anchor,
        side == WebsiteHtmlDraftSide.before
            ? WebsiteBlockInsertSide.before
            : WebsiteBlockInsertSide.after,
      ),
    );
    if (moved) _bring = true;
  }

  /// One catalog at a time, as the canvas's insertion host.
  bool _inserting = false;

  /// «Agregar aquí» on a seam of the picked block: the canvas's insertion
  /// (`commitWebsiteInsertion`), the catalog opened at that seam and the
  /// place re-checked against the page when it closes.
  Future<void> _insert(
    WebsiteEditModeProvider provider,
    String id,
    String action,
  ) async {
    if (_inserting || !provider.hasBlockCanvas) return;
    _inserting = true;
    try {
      await commitWebsiteInsertion(
        context: context,
        intent: websiteBlockInsertionIntent(
          provider,
          id,
          action == 'insert-before'
              ? WebsiteBlockInsertSide.before
              : WebsiteBlockInsertSide.after,
        ),
        onAddBlock: provider.addBlock,
      );
    } finally {
      _inserting = false;
    }
  }

  void _picked(String? id) {
    final provider = _provider;
    if (provider == null) return;
    if (id == null) {
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

  /// The text the operator is writing in the page, while they write it.
  _Writing? _writing;

  /// One of the page's texts written where it is drawn
  /// (`data-edit-text`), through the same transaction as the canvas's
  /// `InlineEditableTextV2`: the start leases the field (the block picked,
  /// in the band it is drawn in) and answers the page with the text as the
  /// draft holds it for that band (`vbDraftEditing`; `null` refuses); the
  /// end writes the text as one step of the history, or lets the lease go.
  /// The page puts its text back if the write is refused (`vbDraftEdited`).
  void _edit(WebsiteHtmlDraftEdit edit) {
    final provider = _provider;
    if (provider == null) return;
    switch (edit.step) {
      case WebsiteHtmlDraftEditStep.begin:
        _stopWriting();
        final writing = _beginWriting(provider, edit);
        _writing = writing;
        unawaited(_tell('vbDraftEditing', [
          writing?.write.text,
          writing == null ? null : edit.field.spec,
          edit.token,
          // The toolbar starts from the formatting the text has.
          writing?.write.formatting,
        ]));
      case WebsiteHtmlDraftEditStep.commit:
        final writing = _writing;
        _writing = null;
        final matches = writing != null &&
            writing.blockId == edit.id &&
            writing.field == edit.field.spec &&
            writing.token == edit.token;
        final changes = edit.formatting ?? const <String, Object?>{};
        final written = matches &&
            WebsiteInlineTextWrite.acceptsFormattingChanges(changes) &&
            writing.write.commit(
              edit.text!,
              formatting: writing.write.formattingWith(changes),
            );
        // Whatever was not written lets its lease go (a no-op once used).
        if (!written) writing?.write.cancel();
        unawaited(_tell('vbDraftEdited', [written, edit.token]));
        _changed();
      case WebsiteHtmlDraftEditStep.cancel:
        if (_writing?.token == edit.token) _stopWriting();
        _changed();
    }
  }

  _Writing? _beginWriting(
    WebsiteEditModeProvider provider,
    WebsiteHtmlDraftEdit edit,
  ) {
    final block = provider.getBlock(edit.id);
    final path = _path(provider.document.pageId, provider.document.pageSlug);
    // Only a text of the picked block: the page asks for no other, and a
    // message for another one is not the operator's.
    if (block == null || path == null || provider.selectedBlockId != edit.id) {
      return null;
    }
    final fields = WebsiteInlineFieldBinding(
      provider: provider,
      blockId: edit.id,
      blockType: (block['block_type'] ?? block['type'] ?? '').toString(),
    );
    final field = edit.field;
    final write = fields.beginText(
      field.collectionKeys.isEmpty
          ? null
          : WebsiteInlineRepeaterTarget(
              collectionKeys: field.collectionKeys,
              itemIndex: field.index,
            ),
      field.keys,
    );
    if (write == null) return null;
    return _Writing(
      blockId: edit.id,
      field: field.spec,
      token: edit.token,
      path: path,
      write: write,
    );
  }

  /// The height handle being dragged in the page, while it is.
  ({
    String blockId,
    String path,
    WebsiteInlineManipulationLease lease
  })? _sizing;

  /// Lets the height being dragged go, as it was.
  void _stopSizing() {
    final sizing = _sizing;
    _sizing = null;
    if (sizing != null) _provider?.cancelInlineManipulation(sizing.lease);
  }

  /// The picked block's height handle in the page, through the canvas's own
  /// height transaction (`WebsiteInlineFieldBinding.beginHeight`): leased
  /// when the drag starts, written once when it ends, as one step of the
  /// history; a reset gives the content its own height back. The page puts
  /// the block back as it was if the write is refused (`vbDraftSized`).
  void _height(WebsiteHtmlDraftHeight message) {
    final provider = _provider;
    final block = provider?.getBlock(message.id);
    if (provider == null || block == null) return;
    final fields = WebsiteInlineFieldBinding(
      provider: provider,
      blockId: message.id,
      blockType: (block['block_type'] ?? block['type'] ?? '').toString(),
    );
    final sizing = _sizing;
    switch (message.step) {
      case WebsiteHtmlDraftHeightStep.begin:
        _stopSizing();
        final path = _path(
          provider.document.pageId,
          provider.document.pageSlug,
        );
        final lease = path == null ? null : fields.beginHeight();
        _sizing = lease == null
            ? null
            : (blockId: message.id, path: path!, lease: lease);
        if (lease == null) unawaited(_tell('vbDraftSized', [false]));
      case WebsiteHtmlDraftHeightStep.commit:
        _sizing = null;
        final range = fields.heightRange;
        final written = sizing != null &&
            sizing.blockId == message.id &&
            fields.commitHeight(
              sizing.lease,
              ((message.value! / 10).round() * 10)
                  .clamp(range.min, range.max)
                  .toDouble(),
            );
        if (sizing != null && sizing.blockId != message.id) {
          provider.cancelInlineManipulation(sizing.lease);
        }
        unawaited(_tell('vbDraftSized', [written]));
        _changed();
      case WebsiteHtmlDraftHeightStep.cancel:
        _sizing = null;
        if (sizing != null) provider.cancelInlineManipulation(sizing.lease);
        _changed();
      case WebsiteHtmlDraftHeightStep.reset:
        if (sizing != null) provider.cancelInlineManipulation(sizing.lease);
        _sizing = null;
        final lease = fields.beginHeight();
        if (lease != null) fields.commitHeight(lease, null);
    }
  }

  /// Lets the text being written go, as it was.
  void _stopWriting() {
    final writing = _writing;
    _writing = null;
    writing?.write.cancel();
  }

  /// Calls the page's [function] with [arguments], if the page has it.
  Future<void> _tell(String function, List<Object?> arguments) async {
    final web = _web;
    if (web == null || !mounted) return;
    // On the web the page is a frame of another origin: it is told by
    // message, once it said it is ready.
    if (kIsWeb) {
      websiteHtmlDraftTell(_nonce, function, arguments);
      return;
    }
    try {
      await web.evaluateJavascript(
        source: 'window.$function && window.$function('
            '${arguments.map(jsonEncode).join(', ')});',
      );
    } on Object {
      // The page is between loads: the new one starts without the edit.
    }
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
                        key: _pageKey,
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
                              pageZoom: 1,
                              supportZoom: false,
                              transparentBackground: false,
                            ),
                            onWebViewCreated: (controller) {
                              _web = controller;
                              // On the web the page speaks by message
                              // (`websiteHtmlDraftPicks`); a frame has no
                              // handlers.
                              for (final name in kIsWeb
                                  ? const <String>[]
                                  : const [
                                      'vbDraftPick',
                                      'vbDraftAction',
                                      'vbDraftEdit',
                                      'vbDraftSlide',
                                      'vbDraftHeight',
                                      'vbDraftMove',
                                      'vbDraftButton',
                                      'vbDraftLayer',
                                    ]) {
                                controller.addJavaScriptHandler(
                                  handlerName: name,
                                  callback: _handler(name),
                                );
                              }
                              final html = _html;
                              final origin = _server;
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

/// Lays a native web view out so it is hit where it is drawn under the ERP's
/// window zoom, which scales the Flutter scene by [zoom].
///
/// Measured on macOS (2026-10-07, zoom 0.8), reading the page's own click
/// coordinates: AppKit hit-tests the native view by its frame, without the
/// scale Flutter draws it with. Under the plain window zoom a click on the
/// second section landed on the first. Under a net scale of 1/zoom (laid out
/// at width × zoom², the first fix) the drawing was right but the frame for
/// clicks was 80 % of it: a click lit 1,32 CSS px per point less than the
/// page showed, and nothing on the right or the bottom fifth reached the
/// page (the block bar's buttons never answered). Laid out at width × zoom
/// and drawn back with 1/zoom, the net scale is 1: the frame is the drawing,
/// clicks land on what is under them (1,32 CSS px per point, both), and with
/// `pageZoom` 1 the page takes the canvas's own width (1247 CSS px). Other
/// platforms keep the zoom as is: Windows is not measured yet, phones have
/// no window zoom.
class _ZoomedNativeView extends StatelessWidget {
  const _ZoomedNativeView({required this.zoom, required this.child});

  final double zoom;
  final Widget child;

  // The structure is measured too: under an `OverflowBox` the page took
  // 1948 CSS px instead of 1247.
  @override
  Widget build(BuildContext context) {
    if ((zoom - 1).abs() < 0.001 ||
        defaultTargetPlatform != TargetPlatform.macOS) {
      return child;
    }
    final factor = zoom;
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

/// [html] with a `<base>` at the store's [origin], first in its `<head>`,
/// and the [nonce] its picks are signed with (`window.vbDraftNonce`).
String _withBase(String html, Uri origin, String nonce) {
  final base = '<base href="${origin.replace(path: '/')}">'
      '<script>window.vbDraftNonce=${jsonEncode(nonce)};</script>';
  final head = RegExp('<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head == null) return '$base$html';
  return html.replaceRange(head.end, head.end, base);
}

/// The text the operator is writing in the page: which block and field, on
/// which page, and the write that holds it.
class _Writing {
  const _Writing({
    required this.blockId,
    required this.field,
    required this.token,
    required this.path,
    required this.write,
  });

  final String blockId;
  final String field;
  final String? token;
  final String path;
  final WebsiteInlineTextWrite write;
}
