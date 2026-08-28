import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_activity.dart';
import '../../modules/messaging/utils/conversation_search.dart';
import '../services/authority_scoped_cache.dart';
import '../services/right_toolbar_service.dart';
import '../services/tenant_service.dart';

/// Estado de vista de una bandeja que sobrevive al cierre de su panel.
///
/// Cerrar el toolbar desmonta el panel a propósito: su `dispose()` cancela la
/// suscripción realtime y suelta el historial de la conversación, de modo que
/// un panel cerrado no siga marcando como leídos mensajes que nadie vio. El
/// widget sigue siendo desechable; lo que sobrevive es esto, para que reabrir
/// no se sienta un arranque en frío.
class InboxPanelSession {
  const InboxPanelSession({
    required this.searchText,
    required this.selectedConversationId,
    this.selectedThreadRootMessageId,
    required this.showOnlyActiveChats,
    required this.scope,
    this.extra,
  });

  final String searchText;
  final String? selectedConversationId;
  final String? selectedThreadRootMessageId;
  final bool showOnlyActiveChats;

  /// Usuario y tenant a los que pertenece este estado. `RightToolbarService`
  /// vive en la raíz de la app y sobrevive al cierre de sesión, así que la
  /// sesión se descarta sola cuando el alcance cambia, en vez de confiar en que
  /// alguien se acuerde de limpiarla.
  final ErpAuthorityScopeKey? scope;

  /// Lo que sólo le importa a una bandeja concreta: su filtro propio, por
  /// ejemplo. El común lo transporta sin interpretarlo.
  final Object? extra;
}

/// El ciclo de vida compartido por las bandejas del rail derecho.
///
/// **Por qué existe.** Clientes y Proveedores nacieron como dos archivos
/// independientes con veinte métodos del mismo nombre copiados: buscador,
/// alcance activo/historial, recarga, apertura y retorno del chat, y el ciclo
/// de la conversación activa. La consecuencia real no fue el tamaño sino la
/// deriva: un arreglo aterrizaba en una bandeja y la otra quedaba con el
/// defecto — el arranque en frío se corrigió sólo en Proveedores y nadie se
/// enteró hasta que el dueño lo notó.
///
/// Aquí vive lo que las dos hacen igual. Lo que cada una hace distinto —sus
/// filtros, sus filas, su orden, sus acciones— sigue siendo suyo y se declara,
/// no se copia.
mixin ConversationInboxHost<T extends StatefulWidget> on State<T> {
  final TextEditingController searchController = TextEditingController();

  String searchTerm = '';
  String? selectedConversationId;
  String? selectedThreadRootMessageId;
  String? panelActiveConversationId;
  bool showOnlyActiveChats = true;
  bool isRefreshing = false;

  ChatProvider? chatProvider;
  RightToolbarService? toolbarService;
  ErpAuthorityScopeKey? _scope;

  /// Bajo qué llave guarda su sesión esta bandeja.
  ToolbarTool get inboxTool;

  /// Estado propio de la bandeja que también debe sobrevivir (su filtro, por
  /// ejemplo). Por defecto no hay nada extra.
  Object? captureSessionExtra() => null;
  void restoreSessionExtra(Object? extra) {}

  /// Oportunidad de pintar la primera trama con datos ya en memoria en vez de
  /// partir en blanco. Corre ANTES del primer build a propósito: hacerlo en un
  /// `addPostFrameCallback` deja una trama vacía, que es justamente el
  /// parpadeo de arranque en frío que se quiere evitar.
  void seedFromWarmCache() {}

  /// Datos propios que la bandeja recarga junto a las conversaciones.
  Future<void> loadInboxData() async {}

  /// Avisa cuando se abre o se cierra una conversación.
  ///
  /// Quien hospeda la bandeja puede necesitarlo para cederle la altura: en la
  /// hoja compacta, con un chat abierto las pestañas y el título ya no aportan
  /// —el chat trae su propia vuelta— y sólo le quitan pantalla al mensaje.
  void onConversationVisibilityChanged(bool visible) {}

  void _setSelectedConversation(String? id) {
    selectedConversationId = id;
  }

  /// Se llama desde `build` con lo que la bandeja REALMENTE está dibujando.
  ///
  /// Atarlo a la intención de abrir no alcanzaba: si el hilo elegido ya no está
  /// en la lista, el panel vuelve solo a la bandeja y el aviso quedaba
  /// desincronizado — la hoja escondía su cabecera con la lista a la vista. Lo
  /// que se anuncia es lo que se ve.
  void announceConversationVisibility(bool rendered) {
    // Sin dedupe local: tras un remontaje la copia nueva parte de cero y un
    // dedupe aquí se tragaba la corrección. El receptor deduplica (es un
    // ValueNotifier); este lado sólo difiere el aviso fuera del build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      onConversationVisibilityChanged(rendered);
    });
  }

  // --- Ciclo de vida -------------------------------------------------------

  void initInboxHost() {
    searchController.addListener(_handleSearchChanged);
    _maybeToolbar()?.addListener(_consumePendingConversation);
    ConversationActivity.showOnlyActiveChats.addListener(
      _handleActiveModeChanged,
    );
    _restoreInboxSession();
    seedFromWarmCache();
    unawaited(_loadActiveModePreference());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Una notificación puede haber pedido este hilo antes de que el panel
      // existiera; se atiende primero, porque manda sobre lo que quedó abierto.
      _consumePendingConversation();
      resubscribeRestoredConversation();
      unawaited(
        context.read<ChatProvider>().refreshConversationContextHints(),
      );
      unawaited(loadInboxData());
    });
  }

  void didChangeInboxDependencies() {
    chatProvider = context.read<ChatProvider>();
    toolbarService = _maybeToolbar();
    _scope = _currentScope();
  }

  /// La retención de sesión es una comodidad, no un requisito: un panel
  /// compuesto fuera del rail derecho —una prueba, una pantalla incrustada—
  /// debe seguir funcionando sin ella, no reventar en `initState`.
  RightToolbarService? _maybeToolbar() {
    try {
      return context.read<RightToolbarService>();
    } catch (_) {
      return null;
    }
  }

  /// El alcance sale del `TenantService` del árbol cuando lo hay, y del
  /// singleton si no. `TenantService()` es una factoría que devuelve siempre la
  /// misma instancia, así que sin este paso por Provider la frontera de tenant
  /// sería imposible de ejercitar en una prueba.
  ErpAuthorityScopeKey? _currentScope() {
    TenantService tenant;
    try {
      tenant = context.read<TenantService>();
    } catch (_) {
      tenant = TenantService();
    }
    return ErpAuthorityScopeKey.from(
      userId: tenant.currentAuthUserId,
      tenantId: tenant.currentTenantId,
    );
  }

  void disposeInboxHost() {
    toolbarService?.removeListener(_consumePendingConversation);
    _saveInboxSession();
    // Se conserva tal cual: soltar la conversación activa es lo que cancela la
    // suscripción realtime y compacta el historial. Sin esto, un panel cerrado
    // seguiría marcando como leídos mensajes que nadie vio.
    final activeId = panelActiveConversationId;
    if (activeId != null) {
      chatProvider?.clearActiveConversation(
        conversationId: activeId,
        notify: false,
      );
    }
    searchController.removeListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.removeListener(
      _handleActiveModeChanged,
    );
    searchController.dispose();
  }

  /// Abre el hilo que pidió una notificación, si es para esta bandeja.
  void _consumePendingConversation() {
    if (!mounted) return;
    final requested = _maybeToolbar()?.takePendingConversation(inboxTool);
    if (requested == null) return;
    setState(() {
      _setSelectedConversation(requested.conversationId);
      selectedThreadRootMessageId = requested.threadRootMessageId;
      panelActiveConversationId = requested.conversationId;
    });
    context
        .read<ChatProvider>()
        .setActiveConversation(requested.conversationId);
  }

  // --- Sesión --------------------------------------------------------------

  void _restoreInboxSession() {
    // `read` no registra dependencia, así que es seguro desde initState; el
    // campo cacheado se resuelve en didChangeDependencies para poder guardar
    // desde dispose(), donde el context ya no sirve.
    final toolbar = _maybeToolbar();
    if (toolbar == null) return;
    final session = toolbar.panelSession<InboxPanelSession>(inboxTool);
    if (session == null) return;

    if (session.scope != _currentScope()) {
      toolbar.clearPanelSession(inboxTool);
      return;
    }

    showOnlyActiveChats = session.showOnlyActiveChats;
    _setSelectedConversation(session.selectedConversationId);
    selectedThreadRootMessageId = session.selectedThreadRootMessageId;
    restoreSessionExtra(session.extra);
    if (session.searchText.isNotEmpty) {
      // Asignar el texto dispara el listener, que sincroniza `searchTerm`.
      searchController.text = session.searchText;
    }
  }

  void _saveInboxSession() {
    toolbarService?.savePanelSession(
      inboxTool,
      InboxPanelSession(
        searchText: searchController.text,
        selectedConversationId: selectedConversationId,
        selectedThreadRootMessageId: selectedThreadRootMessageId,
        showOnlyActiveChats: showOnlyActiveChats,
        scope: _scope,
        extra: captureSessionExtra(),
      ),
    );
  }

  /// El chat restaurado necesita volver a suscribirse: `dispose()` canceló la
  /// suscripción realtime a propósito. Si la conversación ya no está en el
  /// tenant actual, se vuelve a la bandeja en vez de mostrar un chat fantasma.
  void resubscribeRestoredConversation() {
    final conversationId = selectedConversationId;
    if (conversationId == null || !mounted) return;
    final provider = context.read<ChatProvider>();
    final exists = provider.conversations.any((c) => c.id == conversationId);
    if (!exists) {
      setState(() {
        _setSelectedConversation(null);
        panelActiveConversationId = null;
      });
      return;
    }
    provider.setActiveConversation(conversationId);
    panelActiveConversationId = conversationId;
  }

  // --- Buscador y alcance --------------------------------------------------

  void _handleSearchChanged() {
    setState(
      () => searchTerm = ConversationSearch.normalize(searchController.text),
    );
  }

  Future<void> _loadActiveModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final showOnlyActive =
        prefs.getBool(ConversationActivity.activeOnlyPreferenceKey) ?? true;
    if (!mounted) return;
    if (ConversationActivity.showOnlyActiveChats.value != showOnlyActive) {
      ConversationActivity.showOnlyActiveChats.value = showOnlyActive;
    }
    setState(() {
      showOnlyActiveChats = ConversationActivity.showOnlyActiveChats.value;
    });
  }

  Future<void> setShowOnlyActiveChats(bool value) async {
    if (ConversationActivity.showOnlyActiveChats.value != value) {
      ConversationActivity.showOnlyActiveChats.value = value;
    } else if (mounted) {
      setState(() => showOnlyActiveChats = value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ConversationActivity.activeOnlyPreferenceKey, value);
  }

  void _handleActiveModeChanged() {
    if (!mounted) return;
    final value = ConversationActivity.showOnlyActiveChats.value;
    if (showOnlyActiveChats == value) return;
    setState(() => showOnlyActiveChats = value);
  }

  // --- Recarga y apertura de conversaciones --------------------------------

  Future<void> refreshInbox() async {
    setState(() => isRefreshing = true);
    final provider = context.read<ChatProvider>();
    await provider.loadConversations(refreshContextHints: false);
    await provider.refreshConversationContextHints();
    await loadInboxData();
    if (mounted) {
      setState(() => isRefreshing = false);
    }
  }

  void openConversationInPanel(String conversationId) {
    setState(() {
      _setSelectedConversation(conversationId);
      selectedThreadRootMessageId = null;
      panelActiveConversationId = conversationId;
    });
  }

  void returnToInbox(String conversationId) {
    final shouldClearActive = panelActiveConversationId == conversationId;
    setState(() {
      _setSelectedConversation(null);
      selectedThreadRootMessageId = null;
      if (shouldClearActive) {
        panelActiveConversationId = null;
      }
    });

    if (shouldClearActive) {
      context
          .read<ChatProvider>()
          .clearActiveConversation(conversationId: conversationId);
    }
  }
}
