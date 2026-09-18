import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/global_search/global_search_controller.dart';
import '../../services/global_search/global_search_entry.dart';
import '../../services/global_search/global_search_previews.dart';
import '../../services/global_search/global_search_index.dart';
import '../../services/global_search/global_search_menu_source.dart';
import '../../../modules/messaging/services/messaging_attachment_service.dart';
import '../../../modules/messaging/widgets/chat_attachment_viewer.dart';
import '../../services/right_toolbar_service.dart';
import '../../services/workspace_manager.dart';
import '../../themes/vinabike_theme_roles.dart';
import '../../utils/responsive_breakpoints.dart';
import '../main_layout.dart';
import 'global_search_result_views.dart';

/// Buscador global del ERP.
///
/// **Qué resuelve.** Llegar a cualquier cosa —una pantalla, un cliente, una
/// pega, una factura, un producto— escribiendo, sin recordar en qué módulo
/// vive. Es una sola caja: no hay que elegir antes qué se está buscando.
///
/// **Por qué es una superficie centrada y con velo, y no un popover anclado.**
/// La guía reserva el popover para «una elección breve que pertenece a un
/// disparador visible» y prohíbe el modal centrado *para ese caso*. Éste no
/// tiene disparador: se abre con `⌘K` desde cualquier pantalla y su tarea es
/// pedir atención exclusiva por dos segundos. Ahí el velo es correcto — es,
/// dice la guía, «la firma del modal centrado» — y anclar no significaría nada.
///
/// **Valores.** Todos leídos: la superficie es la anatomía `O-02`
/// (`radius.panel 10`, borde `divider`, relleno `surface`) con el escalón
/// `overlay` de la escalera de profundidad `F-05`
/// (`0 12px 40px rgba(12,37,55,.22)`, teñida con el navy del shell, nunca con
/// negro). El movimiento es el único del ERP: `cubic-bezier(.22,1,.36,1)`,
/// `base 200` al entrar, `fast 120` al salir y en los cambios de estado, y con
/// `reduce-motion` sólo opacidad. Alto de campo y de fila, 48, es el objetivo
/// táctil que publica `F-06`; el radio de fila, 6, es el de la opción de
/// `S-05`.
///
/// Ningún hex entra a este archivo: cada valor va atado al rol que lo resuelve.
class GlobalSearchOverlay {
  const GlobalSearchOverlay._();

  static bool _isOpen = false;

  /// Abre el buscador. Si ya está abierto no apila un segundo: `⌘K` con el
  /// buscador arriba es «cerrar», no «abrir otro».
  ///
  /// [sharedText] es el buffer de quien lo abrió —`GlobalSearchShortcut`, que
  /// está montado siempre—. El panel lo adopta sin destruirlo, y por eso una
  /// tecla escrita durante los 200 ms de la transición no se pierde: cae en ese
  /// mismo texto aunque el campo todavía no exista. Sin él, escribir «felipe»
  /// de corrido llegaba como «feli» (medido en la app, 2026-09-17).
  static Future<void> open(
    BuildContext context, {
    TextEditingController? sharedText,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_isOpen) {
      navigator.maybePop();
      return;
    }
    _isOpen = true;
    try {
      await navigator.push(
        _GlobalSearchRoute(sharedText: sharedText, host: context),
      );
    } finally {
      _isOpen = false;
      sharedText?.clear();
    }
  }

  static bool get isOpen => _isOpen;
}

class _GlobalSearchRoute extends PopupRoute<void> {
  _GlobalSearchRoute({required this.sharedText, required this.host});

  final TextEditingController? sharedText;
  final BuildContext host;

  @override
  Color? get barrierColor =>
      VinabikeThemeRoles.maybeOf(host)?.scrim ??
      Theme.of(host).colorScheme.scrim.withValues(alpha: 0.45);

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Cerrar el buscador';

  /// `F-05` · `base 200` al entrar.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  /// `F-05` · `fast 120` al salir.
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _GlobalSearchPanel(sharedText: sharedText);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      // `F-05`: la única curva del ERP.
      curve: const Cubic(0.22, 1, 0.36, 1),
      reverseCurve: Curves.easeOutCubic,
    );
    // `F-05`: con `reduce-motion` nada se traslada.
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _GlobalSearchPanel extends StatefulWidget {
  const _GlobalSearchPanel({required this.sharedText});

  /// El buffer de quien abrió. El panel lo adopta; no lo crea ni lo destruye.
  final TextEditingController? sharedText;

  @override
  State<_GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<_GlobalSearchPanel> {
  /// `O-02` · `radius.panel`.
  static const double _panelRadius = 10;

  /// `S-05` · radio de la opción.
  static const double _rowRadius = 6;

  /// `F-06` · bajo 900 px el objetivo es 48 sin importar la preferencia. Se usa
  /// el mismo valor en escritorio: una fila de dos líneas no cabe en los 30 de
  /// la opción de `S-05`, y un segundo alto sin fuente legible sería inventado.
  static const double _rowHeight = 48;

  /// `F-05` · `fast 120` para hover y selección.
  static const Duration _fast = Duration(milliseconds: 120);

  /// Ancho de la columna en escritorio. **Sin fuente en la guía**: el archivo
  /// se corta antes de cualquier medida de una superficie centrada, así que
  /// queda declarado acá como no leído. Es el ancho de lectura cómoda para una
  /// fila de título + contexto, y se reemplaza cuando Design publique `O-01`.
  static const double _desktopWidth = 640;

  late final TextEditingController _text;
  late final bool _ownsText;

  /// El manejo de teclas cuelga del nodo **del campo**, no de un `Focus`
  /// ancestro.
  ///
  /// **Causa medida (2026-09-17, reportada por el dueño):** había un
  /// `Focus(autofocus: true)` envolviendo todo el panel *y* el `autofocus` del
  /// campo. Gana el ancestro, así que el campo nunca tomaba el foco: las letras
  /// igual aparecían —las ponía el buffer global— pero **borrar no hacía
  /// nada**, porque no había ningún `EditableText` enfocado que procesara el
  /// retroceso. Colgando el manejo acá, el campo conserva el foco y las flechas
  /// y Enter se atienden *antes* que los atajos de edición de texto de Flutter,
  /// que son ancestros y consumirían ↑/↓.
  late final FocusNode _fieldFocus = FocusNode(onKeyEvent: _onKey);

  /// Las miniaturas de los archivos recibidos. Vive con el panel: sus
  /// autorizaciones duran minutos y no tiene sentido guardarlas más allá.
  final GlobalSearchPreviews _previews = GlobalSearchPreviews();
  final ScrollController _scroll = ScrollController();
  late final GlobalSearchController _controller;

  @override
  void initState() {
    super.initState();
    _ownsText = widget.sharedText == null;
    _text = widget.sharedText ?? TextEditingController();
    _controller = GlobalSearchController();
    _controller.addListener(_onControllerChanged);
    if (_text.text.isNotEmpty) _controller.updateText(_text.text);
    _text.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final index = context.read<GlobalSearchIndex>();
    final scope = index.authorityScope;
    await _controller.loadUsage(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    await index.ensureLoaded();
  }

  /// Publica el índice recién compuesto **después** del frame.
  ///
  /// El menú sólo se puede resolver dentro de `build` —mira los proveedores de
  /// orden, permisos y badges— y el controlador notifica al recibirlo. Empujar
  /// desde `build` sería un `setState` durante el propio `build`; el frame de
  /// diferencia no se ve, porque el campo todavía está vacío.
  void _publishEntries(List<GlobalSearchEntry> entries) {
    if (_lastPublishedLength == entries.length &&
        _lastPublishedSignature == _signatureOf(entries)) {
      return;
    }
    _lastPublishedLength = entries.length;
    _lastPublishedSignature = _signatureOf(entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.replaceEntries(entries);
    });
  }

  int? _lastPublishedLength;
  String? _lastPublishedSignature;

  String _signatureOf(List<GlobalSearchEntry> entries) =>
      entries.isEmpty ? '' : '${entries.first.id}|${entries.last.id}';

  String _currentLocation() {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return '';
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() => _controller.updateText(_text.text);

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _text.removeListener(_onTextChanged);
    _controller.dispose();
    // Un buffer prestado se devuelve, no se destruye: su dueño sigue montado y
    // lo va a necesitar en la próxima tecla.
    if (_ownsText) _text.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    _previews.clear();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  bool _opening = false;

  Future<void> _openResult(GlobalSearchEntry entry) async {
    // Enter puede llegar por el nodo del campo y por `onSubmitted`. Abrir dos
    // veces cerraría también la ruta que hay debajo.
    if (_opening) return;
    _opening = true;
    // El orden importa: primero se cierra, y recién después se navega. Navegar
    // con la superficie todavía montada deja el velo sobre la pantalla nueva
    // durante los 120 ms de salida.
    // El visor se monta en el navegador raíz, que sobrevive al cierre de este
    // panel; se captura antes de cerrar porque después este `context` ya no
    // sirve.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    _close();
    unawaited(_controller.recordOpened(entry));

    final attachment = entry.attachment;
    if (attachment != null) {
      unawaited(_previewAttachment(rootContext, attachment));
      return;
    }

    // El sitio de un proveedor abre al lado, como una pestaña: mirar su
    // catálogo no debería costar la pantalla en la que uno estaba.
    final browserUrl = entry.browserUrl;
    if (browserUrl != null) {
      final workspaces = context.read<WorkspaceManager>();
      if (workspaces.openBrowserWorkspace(browserUrl) == null) {
        // El techo de espacios se dice, no se descubre fallando.
        ScaffoldMessenger.maybeOf(rootContext)?.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir el sitio: ya tienes '
              '${WorkspaceManager.maxWorkspaces} espacios abiertos.',
            ),
          ),
        );
      }
      return;
    }

    final tool = entry.toolbarTool;
    if (tool != null) {
      final toolbar = context.read<RightToolbarService>();
      // Un hilo se abre **dentro** de su bandeja, ya seleccionado. Abrir la
      // bandeja y dejar al operador buscándolo otra vez es devolverle el
      // trabajo que acababa de hacer.
      final conversationId = entry.conversationId;
      if (conversationId != null) {
        toolbar.openConversation(tool: tool, conversationId: conversationId);
      } else {
        toolbar.openTool(tool);
      }
      return;
    }
    final workspaces = context.read<WorkspaceManager>();
    workspaces.navigateActiveWorkspace(entry.route);
  }

  /// Muestra el archivo con el **mismo visor del chat**, sin montar el módulo
  /// de mensajería.
  ///
  /// La autorización se pide en el momento y dura minutos: un resultado de
  /// búsqueda no puede llevar guardada una URL que abra un archivo privado.
  Future<void> _previewAttachment(
    BuildContext hostContext,
    GlobalSearchAttachment attachment,
  ) async {
    String? url;
    try {
      url = await MessagingAttachmentService()
          .createSignedUrlForPath(attachment.storagePath);
    } catch (error) {
      debugPrint('[global-search] no se pudo autorizar el adjunto: $error');
    }
    if (!hostContext.mounted) return;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.maybeOf(hostContext)?.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir este archivo.')),
      );
      return;
    }
    await ChatAttachmentViewer.show(
      hostContext,
      url: url,
      fileName: attachment.fileName,
      extension: attachment.extension,
      contentType: attachment.contentType,
      isImage: attachment.isImage,
    );
  }

  /// Lo que no se encontró, se pregunta. El asistente sí puede razonar sobre
  /// una frase; el buscador contesta por identidad y nunca inventa.
  void _askAssistant() {
    final text = _controller.text.trim();
    _close();
    context.read<RightToolbarService>().openTool(ToolbarTool.aiAssistant);
    debugPrint('[global-search] se abrió el asistente tras «$text».');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _controller.moveHighlight(1);
        _revealHighlight();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _controller.moveHighlight(-1);
        _revealHighlight();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final target = _controller.primaryTarget;
        if (target != null) _openResult(target.entry);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _revealHighlight() {
    final index = _controller.highlight;
    if (index == null || !_scroll.hasClients) return;
    final target = (index * _rowHeight) - _rowHeight;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: _fast,
      curve: const Cubic(0.22, 1, 0.36, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < ResponsiveBreakpoints.desktopMin;

    final index = context.watch<GlobalSearchIndex>();
    _publishEntries(<GlobalSearchEntry>[
      ...buildGlobalSearchMenuEntries(
        modules: resolveOrderedAppModules(context),
        fixedModules: resolveFixedAppModules(
          context,
          currentLocation: _currentLocation(),
        ),
      ),
      ...index.records,
    ]);

    final panel = _buildPanel(context, isCompact: isCompact);

    if (isCompact) {
      // Compacto: la superficie es la pantalla. Un panel de 640 centrado en un
      // teléfono es una tarjeta flotando sobre nada.
      return SafeArea(child: panel);
    }

    return Padding(
      padding: EdgeInsets.only(top: media.size.height * 0.12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _desktopWidth,
            maxHeight: media.size.height * 0.66,
          ),
          child: panel,
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, {required bool isCompact}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final radius = isCompact ? 0.0 : _panelRadius;

    final surface = Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: isCompact ? null : Border.all(color: theme.dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildField(context),
            Divider(
                height: 1,
                thickness: 1,
                color: roles?.hairline ?? theme.dividerColor),
            Flexible(child: _buildBody(context)),
            _buildFooter(context),
          ],
        ),
      ),
    );

    if (isCompact) return surface;

    // La sombra va FUERA del Material que recorta: dentro de un
    // `Clip.antiAlias` se recorta entera y la superficie queda plana.
    final shadowTint = roles?.shell.canvas ?? theme.colorScheme.shadow;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            // `F-05` · escalón `overlay`: 0 12px 40px al 22 %. El valor oscuro
            // no está publicado —esa sección cae después del corte de 256 KiB
            // del archivo— así que se sube la opacidad para que un navy siga
            // leyéndose sobre un lienzo oscuro. Queda marcado como no leído.
            color: shadowTint.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.52 : 0.22,
            ),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: surface,
    );
  }

  Widget _buildField(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);

    return SizedBox(
      height: _rowHeight + 8,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('global-search-field'),
              controller: _text,
              focusNode: _fieldFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.titleMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Buscar clientes, productos, pegas, facturas…',
                hintStyle: theme.textTheme.titleMedium?.copyWith(
                  color: roles?.faintForeground ??
                      theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onSubmitted: (_) {
                final target = _controller.primaryTarget;
                if (target != null) _openResult(target.entry);
              },
            ),
          ),
          if (_controller.hasQuery)
            IconButton(
              key: const ValueKey('global-search-clear'),
              tooltip: 'Limpiar',
              iconSize: 18,
              onPressed: () {
                _text.clear();
                _controller.clear();
                _fieldFocus.requestFocus();
              },
              icon: const Icon(Icons.close_rounded),
            )
          else
            GlobalSearchKeyCap(label: _closeHintLabel()),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _closeHintLabel() => 'esc';

  Widget _buildBody(BuildContext context) {
    final index = context.watch<GlobalSearchIndex>();
    // Un error de carga no se muestra como «no hay nada»: eso afirmaría que el
    // taller no tiene clientes cuando lo que pasó es que no se pudieron leer.
    if (index.lastError != null && index.records.isEmpty) {
      return const GlobalSearchMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo cargar el buscador',
        detail: 'Revisa la conexión. Los módulos del menú siguen disponibles.',
      );
    }

    // Una sola letra no es «no existe»: es «sigue escribiendo». Decir «nada
    // con «f»» afirma una ausencia que nadie midió.
    if (!_controller.hasActionableQuery) {
      return _buildSuggestions(context, index);
    }

    if (_controller.outcome.isEmpty) {
      return _buildNoResults(context);
    }

    return AnimatedSize(
      duration: _fast,
      curve: const Cubic(0.22, 1, 0.36, 1),
      alignment: Alignment.topCenter,
      child: _buildResults(context),
    );
  }

  Widget _buildSuggestions(BuildContext context, GlobalSearchIndex index) {
    final suggestions = _controller.suggestions();
    if (suggestions.isEmpty) {
      return GlobalSearchMessage(
        icon: Icons.keyboard_rounded,
        title: 'Escribe para buscar',
        detail: index.isLoading
            ? 'Terminando de cargar los registros…'
            : 'Un nombre, un número de documento, un SKU o lo que quieras hacer.',
      );
    }

    var cursor = 0;
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        GlobalSearchGroupHeader(
          title: _controller.usage.stats.isEmpty
              ? 'Para empezar'
              : 'Lo que más abres',
        ),
        for (final entry in suggestions)
          GlobalSearchResultRow(
            entry: entry,
            height: _rowHeight,
            radius: _rowRadius,
            transition: _fast,
            previews: _previews,
            isHighlighted: _controller.highlight == cursor++,
            onTap: () => _openResult(entry),
          ),
      ],
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return GlobalSearchMessage(
      icon: Icons.search_off_rounded,
      title: 'Nada con «${_controller.text.trim()}»',
      // El asistente se abre, pero NO se lleva el texto: no hay todavía por
      // dónde pasárselo, y prometerlo en el rótulo sería mentir en el botón.
      detail: 'Revisa el nombre, o ábrelo en el asistente, que sí puede '
          'razonar sobre una frase.',
      action: TextButton.icon(
        onPressed: _askAssistant,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: const Text('Abrir el asistente'),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final groups = _controller.outcome.groups;
    final rows = <Widget>[];
    var cursor = 0;

    for (final group in groups) {
      final results = _controller.resultsOf(group);
      rows.add(GlobalSearchGroupHeader(
          title: group.kind.groupTitle, count: group.totalCount));
      for (final result in results) {
        final isHighlighted = _controller.highlight == cursor;
        cursor++;
        rows.add(
          GlobalSearchResultRow(
            entry: result.entry,
            height: _rowHeight,
            radius: _rowRadius,
            transition: _fast,
            previews: _previews,
            isHighlighted: isHighlighted,
            onTap: () => _openResult(result.entry),
          ),
        );
      }
      if (group.hasMore && !_controller.isExpanded(group.kind)) {
        rows.add(
          GlobalSearchMoreRow(
            label: '${group.totalCount - results.length} más en '
                '${group.kind.groupTitle.toLowerCase()}',
            height: _rowHeight,
            radius: _rowRadius,
            onTap: () => _controller.expandGroup(group.kind),
          ),
        );
      }
    }

    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: rows,
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final ink = roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: ink);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: roles?.hairline ?? theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Text('↑ ↓ moverse', style: style),
          const SizedBox(width: 14),
          Text('↵ abrir', style: style),
          const Spacer(),
          if (_controller.outcome.query != null)
            Text(
              '${_controller.outcome.flattened.length} resultados',
              style: style,
            ),
        ],
      ),
    );
  }
}
