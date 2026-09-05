import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_activity.dart';
import '../../modules/messaging/utils/conversation_search.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/messaging/widgets/conversation_tile.dart';
import '../../modules/purchases/models/purchase_invoice.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../models/supplier.dart' as shared_supplier;
import '../utils/supplier_whatsapp_phone.dart';
import '../services/authority_scoped_cache.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import 'conversation_inbox_host.dart';
import 'vb_notice.dart';

enum _SupplierMessageFilter { all, unread }

/// Lo único que Proveedores necesita conservar además de lo común: su filtro.
class _SupplierSessionExtra {
  const _SupplierSessionExtra(this.filter);
  final _SupplierMessageFilter filter;
}

enum _SupplierToolbarAction {
  filterAll,
  filterUnread,
  showActive,
  showHistory,
}

class QuickSupplierMessagesPanel extends StatefulWidget {
  const QuickSupplierMessagesPanel({
    super.key,
    this.showTitle = true,
    this.onConversationVisibilityChanged,
  });

  /// Avisa a quien la hospeda que se abrió o cerró una conversación, para que
  /// pueda cederle la altura.
  final ValueChanged<bool>? onConversationVisibilityChanged;

  /// En la hoja de Actividad el segmento ya dice «Proveedores»; repetirlo aquí
  /// gasta una fila de alto en un teléfono. Las acciones de la barra sí siguen.
  final bool showTitle;

  @override
  State<QuickSupplierMessagesPanel> createState() =>
      _QuickSupplierMessagesPanelState();
}

class _QuickSupplierMessagesPanelState extends State<QuickSupplierMessagesPanel>
    with ConversationInboxHost<QuickSupplierMessagesPanel> {
  static const double _compactToolbarBreakpoint = 360;

  // El buscador, el alcance activo/historial, la conversación abierta, la
  // recarga y la sesión los aporta `ConversationInboxHost`. Aquí queda sólo lo
  // que es de proveedores.
  _SupplierMessageFilter _filter = _SupplierMessageFilter.all;
  String? _openingSupplierId;
  List<shared_supplier.Supplier> _suppliers = [];
  Map<String, List<PurchaseInvoice>> _invoicesBySupplierId = const {};
  bool _hasLoadedSupplierData = false;
  Future<void>? _supplierDataLoad;
  Object? _supplierLoadError;
  ErpAuthorityScopeKey? _supplierDataScope;

  @override
  void onConversationVisibilityChanged(bool visible) {
    widget.onConversationVisibilityChanged?.call(visible);
  }

  @override
  ToolbarTool get inboxTool => ToolbarTool.supplierMessages;

  @override
  Object? captureSessionExtra() => _SupplierSessionExtra(_filter);

  @override
  void restoreSessionExtra(Object? extra) {
    if (extra is _SupplierSessionExtra) _filter = extra.filter;
  }

  @override
  void initState() {
    super.initState();
    _supplierDataScope = inboxAuthorityScope;
    initInboxHost();
  }

  @override
  Future<void> loadInboxData() => _loadSupplierData();

  /// Pinta la primera trama con lo que `PurchaseService` ya tiene en memoria en
  /// vez de partir en blanco. La caché es del servicio y tiene alcance de
  /// tenant, así que esto no introduce una segunda copia ni cruza inquilinos.
  @override
  void seedFromWarmCache() {
    if (_hasLoadedSupplierData) return;
    // `read` no registra dependencia, así que es seguro desde initState.
    final purchaseService = context.read<PurchaseService>();
    if (!purchaseService.hasSuppliersCache ||
        !purchaseService.hasListInvoicesCache) return;
    _suppliers = _visibleSuppliers(purchaseService.cachedSuppliers);
    _invoicesBySupplierId =
        _indexInvoicesBySupplier(purchaseService.cachedListInvoices);
    _hasLoadedSupplierData = true;
  }

  List<shared_supplier.Supplier> _visibleSuppliers(
    List<shared_supplier.Supplier> suppliers,
  ) {
    return suppliers
        .where((supplier) => supplier.isActive)
        .where((supplier) => _supplierChatPhone(supplier) != null)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    didChangeInboxDependencies();
    final scope = inboxAuthorityScope;
    if (_supplierDataScope == scope) return;
    _supplierDataScope = scope;
    _supplierDataLoad = null;
    _suppliers = [];
    _invoicesBySupplierId = const {};
    _hasLoadedSupplierData = false;
    _supplierLoadError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSupplierData());
    });
  }

  @override
  void dispose() {
    disposeInboxHost();
    super.dispose();
  }

  Future<void> _loadSupplierData() {
    final pending = _supplierDataLoad;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _supplierDataLoad = completion.future;
    setState(() => _supplierLoadError = null);
    unawaited(_readSupplierData(completion));
    return completion.future;
  }

  Future<void> _readSupplierData(Completer<void> completion) async {
    final scope = inboxAuthorityScope;
    try {
      final purchaseService = context.read<PurchaseService>();
      // Los dos conjuntos deciden la pertenencia y la metadata de cada fila.
      // Publicarlos juntos evita tratar «todavía no cargado» como «vacío».
      final data = await Future.wait<Object>([
        purchaseService.getSuppliers(activeOnly: true),
        purchaseService.getPurchaseInvoicesForList(),
      ]).timeout(const Duration(seconds: 30));

      if (!mounted ||
          scope != inboxAuthorityScope ||
          !identical(_supplierDataLoad, completion.future)) return;
      setState(() {
        _suppliers =
            _visibleSuppliers(data[0] as List<shared_supplier.Supplier>);
        _invoicesBySupplierId =
            _indexInvoicesBySupplier(data[1] as List<PurchaseInvoice>);
        _hasLoadedSupplierData = true;
      });
    } catch (error) {
      debugPrint('Error loading supplier chats in quick panel: $error');
      if (mounted &&
          scope == inboxAuthorityScope &&
          identical(_supplierDataLoad, completion.future)) {
        setState(() => _supplierLoadError = error);
      }
    } finally {
      if (identical(_supplierDataLoad, completion.future)) {
        _supplierDataLoad = null;
      }
      completion.complete();
    }
  }

  bool _hasWhatsAppPhone(String? phone) {
    return _normalizedPhone(phone).length >= 8;
  }

  String _normalizedPhone(String? phone) {
    return phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  void _openFullChat([Conversation? conversation]) {
    final route = conversation == null
        ? '/chat'
        : Uri(
            path: '/chat',
            queryParameters: {'conversation': conversation.id},
          ).toString();
    final workspaceManager = context.read<WorkspaceManager>();
    context.read<RightToolbarService>().close();
    unawaited(workspaceManager.pushActiveWorkspace<void>(route));
  }

  Conversation? _selectedConversation(List<Conversation> conversations) {
    final selectedId = selectedConversationId;
    if (selectedId == null) return null;

    for (final conversation in conversations) {
      if (conversation.id == selectedId) return conversation;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final selectedConversation = _selectedConversation(provider.conversations);
    // Sólo con la lista YA cargada: en la primera trama tras restaurar la
    // sesión las conversaciones aún no llegan, y devolver a la bandeja ahí
    // descartaba el chat restaurado antes de poder mostrarlo.
    if (selectedConversationId != null &&
        selectedConversation == null &&
        provider.conversations.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedConversationId == null) return;
        returnToInbox(selectedConversationId!);
      });
    }

    // Se anuncia lo que se DIBUJA, no lo que se pretendía abrir.
    announceConversationVisibility(selectedConversation != null);

    if (selectedConversation != null) {
      return _buildConversationView(selectedConversation);
    }

    return Column(
      children: [
        _buildActionBar(),
        _buildSearchField(),
        _buildListToolbar(provider),
        if (_supplierLoadError != null)
          VbNotice(
            title: 'No se pudieron cargar los chats de proveedores',
            body: _hasLoadedSupplierData
                ? 'Se conserva la última información cargada.'
                : 'Reintenta para cargar los proveedores y sus compras.',
            tone: VbNoticeTone.danger,
            action: IconButton(
              tooltip: 'Reintentar',
              onPressed: _loadSupplierData,
              icon: const Icon(Icons.refresh),
            ),
          ),
        Expanded(child: _buildSupplierList(provider)),
      ],
    );
  }

  Widget _buildConversationView(Conversation conversation) {
    return ChatWindow(
      conversation: conversation,
      compact: true,
      headerLeading: IconButton(
        key: const ValueKey('quick-suppliers-back-to-inbox'),
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Volver a proveedores',
        onPressed: () => returnToInbox(conversation.id),
      ),
      headerActions: [
        // On a phone this inbox already owns the full viewport.
        if (MediaQuery.sizeOf(context).width >= 600)
          IconButton(
            key: const ValueKey('quick-suppliers-open-full'),
            icon: const Icon(Icons.open_in_full),
            tooltip: 'Abrir mensajería completa',
            onPressed: () => _openFullChat(conversation),
          ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Padding(
      // Sin título la barra es sólo acciones: se ciñe para no dejar un hueco
      // entre el segmento y el buscador.
      padding: widget.showTitle
          ? const EdgeInsets.fromLTRB(12, 12, 12, 8)
          : const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          if (widget.showTitle)
            Expanded(
              child: Text(
                'Proveedores',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          // Tinta PRIMARIA declarada. Dos lecciones en una: heredar dejaba al
          // tema ambiente decidir, y `onSurfaceVariant` —que fue el primer
          // intento— es tinta de texto secundario: en el esquema oscuro es un
          // gris azulado que sobre esta superficie casi desaparece. Un icono
          // que ES una acción lleva `onSurface`, como cualquier rótulo
          // primario; la variante queda para lo que acompaña.
          IconButton(
            tooltip: 'Recargar',
            onPressed: isRefreshing ? null : refreshInbox,
            color: Theme.of(context).colorScheme.onSurface,
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
          IconButton(
            tooltip: 'Abrir mensajería completa',
            onPressed: () => _openFullChat(),
            color: Theme.of(context).colorScheme.onSurface,
            icon: const Icon(Icons.open_in_full, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: searchTerm.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Limpiar búsqueda',
                  onPressed: searchController.clear,
                ),
          hintText: 'Buscar proveedores, compras o WhatsApp...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildListToolbar(ChatProvider provider) {
    final entries = _filteredSupplierEntries(provider);
    final allEntries = _supplierEntries(
      provider,
      includeInactive: !showOnlyActiveChats,
    );
    final allCount = allEntries.length;
    final unreadCount = allEntries.where(_isUnreadSupplierEntry).length;
    final counts = <_SupplierMessageFilter, int>{
      _SupplierMessageFilter.all: allCount,
      _SupplierMessageFilter.unread: unreadCount,
    };
    final activeCount = _supplierEntries(
      provider,
      includeInactive: false,
    ).length;
    final historyCount = _supplierEntries(
      provider,
      includeInactive: true,
    ).length;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < _compactToolbarBreakpoint;

        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: !_hasLoadedSupplierData
              ? null
              : isCompact
                  ? Row(
                      key: const ValueKey('supplier_toolbar_compact'),
                      children: [
                        Flexible(
                          child: _buildCompactToolbarMenu(
                            counts: counts,
                            activeCount: activeCount,
                            historyCount: historyCount,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Semantics(
                          label:
                              '${entries.length} ${entries.length == 1 ? 'resultado' : 'resultados'}',
                          child: Text(
                            '${entries.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('supplier_toolbar_regular'),
                      children: [
                        _buildMessageFilterMenu(counts),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 18,
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildActivityScopeMenu(
                          activeCount: activeCount,
                          historyCount: historyCount,
                        ),
                        const Spacer(),
                        Semantics(
                          label: '${entries.length} resultados',
                          child: Text(
                            '${entries.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildCompactToolbarMenu({
    required Map<_SupplierMessageFilter, int> counts,
    required int activeCount,
    required int historyCount,
  }) {
    final filterLabel = _filterLabel(_filter);
    final scopeLabel = showOnlyActiveChats ? 'Activos' : 'Historial';

    return PopupMenuButton<_SupplierToolbarAction>(
      key: const ValueKey('supplier_toolbar_compact_menu'),
      tooltip: 'Filtrar y elegir actividad',
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _SupplierToolbarAction.filterAll:
            setState(() => _filter = _SupplierMessageFilter.all);
          case _SupplierToolbarAction.filterUnread:
            setState(() => _filter = _SupplierMessageFilter.unread);
          case _SupplierToolbarAction.showActive:
            unawaited(setShowOnlyActiveChats(true));
          case _SupplierToolbarAction.showHistory:
            unawaited(setShowOnlyActiveChats(false));
        }
      },
      itemBuilder: (context) => [
        _buildCompactToolbarItem(
          action: _SupplierToolbarAction.filterAll,
          icon: _filterIcon(_SupplierMessageFilter.all),
          label: _filterLabel(_SupplierMessageFilter.all),
          count: counts[_SupplierMessageFilter.all] ?? 0,
          selected: _filter == _SupplierMessageFilter.all,
        ),
        _buildCompactToolbarItem(
          action: _SupplierToolbarAction.filterUnread,
          icon: _filterIcon(_SupplierMessageFilter.unread),
          label: _filterLabel(_SupplierMessageFilter.unread),
          count: counts[_SupplierMessageFilter.unread] ?? 0,
          selected: _filter == _SupplierMessageFilter.unread,
        ),
        const PopupMenuDivider(height: 1),
        _buildCompactToolbarItem(
          action: _SupplierToolbarAction.showActive,
          icon: Icons.bolt_outlined,
          label: 'Activos',
          count: activeCount,
          selected: showOnlyActiveChats,
        ),
        _buildCompactToolbarItem(
          action: _SupplierToolbarAction.showHistory,
          icon: Icons.history,
          label: 'Historial',
          count: historyCount,
          selected: !showOnlyActiveChats,
        ),
      ],
      child: Semantics(
        button: true,
        label: '$filterLabel, $scopeLabel',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.tune,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$filterLabel · $scopeLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_SupplierToolbarAction> _buildCompactToolbarItem({
    required _SupplierToolbarAction action,
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopupMenuItem<_SupplierToolbarAction>(
      value: action,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 16,
            child: selected
                ? Icon(Icons.check, size: 16, color: colorScheme.primary)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageFilterMenu(
    Map<_SupplierMessageFilter, int> counts,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = counts[_filter] ?? 0;

    return PopupMenuButton<_SupplierMessageFilter>(
      tooltip: 'Filtrar conversaciones',
      initialValue: _filter,
      position: PopupMenuPosition.under,
      onSelected: (filter) => setState(() => _filter = filter),
      itemBuilder: (context) => _SupplierMessageFilter.values
          .map(
            (filter) => PopupMenuItem<_SupplierMessageFilter>(
              value: filter,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    _filterIcon(filter),
                    size: 17,
                    color: filter == _filter
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _filterLabel(filter),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: filter == _filter
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${counts[filter] ?? 0}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 16,
                    child: filter == _filter
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: colorScheme.primary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: _buildToolbarMenuLabel(
        icon: _filterIcon(_filter),
        label: _filterLabel(_filter),
        count: count,
      ),
    );
  }

  Widget _buildActivityScopeMenu({
    required int activeCount,
    required int historyCount,
  }) {
    return PopupMenuButton<bool>(
      tooltip: 'Elegir actividad',
      initialValue: showOnlyActiveChats,
      position: PopupMenuPosition.under,
      onSelected: (activeOnly) => unawaited(
        setShowOnlyActiveChats(activeOnly),
      ),
      itemBuilder: (context) => [
        _buildActivityScopeItem(
          activeOnly: true,
          icon: Icons.bolt_outlined,
          label: 'Activos',
          count: activeCount,
        ),
        _buildActivityScopeItem(
          activeOnly: false,
          icon: Icons.history,
          label: 'Historial',
          count: historyCount,
        ),
      ],
      child: _buildToolbarMenuLabel(
        icon: showOnlyActiveChats ? Icons.bolt_outlined : Icons.history,
        label: showOnlyActiveChats ? 'Activos' : 'Historial',
      ),
    );
  }

  PopupMenuItem<bool> _buildActivityScopeItem({
    required bool activeOnly,
    required IconData icon,
    required String label,
    required int count,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = activeOnly == showOnlyActiveChats;

    return PopupMenuItem<bool>(
      value: activeOnly,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 16,
            child: selected
                ? Icon(Icons.check, size: 16, color: colorScheme.primary)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarMenuLabel({
    required IconData icon,
    required String label,
    int? count,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: count == null ? label : '$label, $count',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _filterLabel(_SupplierMessageFilter filter) {
    return switch (filter) {
      _SupplierMessageFilter.all => 'Todos',
      _SupplierMessageFilter.unread => 'Sin leer',
    };
  }

  IconData _filterIcon(_SupplierMessageFilter filter) {
    return switch (filter) {
      _SupplierMessageFilter.all => Icons.forum_outlined,
      _SupplierMessageFilter.unread => Icons.mark_chat_unread_outlined,
    };
  }

  Widget _buildSupplierList(ChatProvider provider) {
    if (!_hasLoadedSupplierData) {
      if (_supplierLoadError != null) return const SizedBox.shrink();
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: 'Cargando chats de proveedores',
        ),
      );
    }
    final entries = _filteredSupplierEntries(provider);

    if (entries.isEmpty) {
      return _buildEmptyState(
        isTotallyEmpty: _supplierEntries(provider).isEmpty,
        activeModeEmpty: showOnlyActiveChats &&
            _supplierEntries(provider, includeInactive: true).isNotEmpty,
      );
    }

    return RefreshIndicator(
      onRefresh: refreshInbox,
      child: ListView.builder(
        // Devuelve el scroll donde estaba al reabrir el panel: el bucket vive
        // en la ruta, que sobrevive al desmontaje del panel.
        key: const PageStorageKey<String>('quick-supplier-messages-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Column(
            key: ValueKey(
              entry.conversation?.id ?? 'supplier-${entry.supplier.id}',
            ),
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSupplierResult(entry),
              const Divider(height: 1, indent: 68, endIndent: 12),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupplierResult(_QuickSupplierChatEntry entry) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conversation = entry.conversation;
    final isSelected = conversation != null &&
        selectedConversationId != null &&
        conversation.id == selectedConversationId;
    final isOpening = _openingSupplierId == entry.supplier.id;
    final preview = conversation?.lastMessageContent?.trim();
    final invoice = entry.relevantInvoice(showOnlyActiveChats);

    if (conversation != null) {
      final contactPerson = conversation.contextHint?.contactPersonName;
      final formerContact =
          conversation.contextHint?.contactPersonIsActive == false;
      return ConversationTile(
        key: ValueKey(conversation.id),
        conversation: conversation,
        isActive: isSelected,
        isMobile: false,
        titleOverride: contactPerson == null
            ? entry.supplier.name
            : formerContact
                ? '${entry.supplier.name} · $contactPerson (anterior)'
                : '${entry.supplier.name} · $contactPerson',
        subtitle: '${entry.phone} · Proveedor WhatsApp',
        operationalStatusLabel:
            invoice == null ? null : _invoiceOperationalLabel(invoice),
        operationalStatusColor: invoice == null
            ? null
            : _purchaseInvoiceStatusColor(invoice.status),
        secondaryContextLine: invoice == null
            ? entry.phone
            : _formatCLP(invoice.balance > 0 ? invoice.balance : invoice.total),
        onTap: () => openConversationInPanel(conversation.id),
        onArchive: () => _confirmArchive(conversation),
      );
    }

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: isOpening ? null : () => _openSupplierChat(entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        const Color(0xFF0F766E).withValues(alpha: 0.1),
                    child: Text(
                      _supplierInitials(entry.supplier.name),
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if ((conversation?.unreadCount ?? 0) > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 17, minHeight: 17),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${conversation!.unreadCount > 99 ? '99+' : conversation.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.supplier.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview?.isNotEmpty == true
                          ? preview!
                          : '${entry.phone} · Proveedor WhatsApp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    if (invoice != null) ...[
                      const SizedBox(height: 6),
                      _buildSupplierInvoiceMetadata(invoice),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isOpening)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierInvoiceMetadata(PurchaseInvoice invoice) {
    final color = _purchaseInvoiceStatusColor(invoice.status);
    final number = invoice.invoiceNumber.isEmpty
        ? invoice.supplierInvoiceNumber ?? 'Compra'
        : invoice.invoiceNumber;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.receipt_long_outlined,
            size: 13,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$number · ${invoice.status.displayName} · ${_formatCLP(invoice.balance > 0 ? invoice.balance : invoice.total)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _invoiceOperationalLabel(PurchaseInvoice invoice) {
    final number = invoice.invoiceNumber.isEmpty
        ? invoice.supplierInvoiceNumber ?? 'Compra'
        : invoice.invoiceNumber;
    return '$number · ${invoice.status.displayName}';
  }

  Future<bool> _confirmArchive(Conversation conversation) async {
    final provider = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Archivar chat?'),
        content: Text(
          'El chat con "${provider.getChatTitle(conversation)}" pasará al historial sin perder mensajes, compras ni trazabilidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final success = await provider.archiveConversation(conversation.id);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo archivar la conversación'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return success;
  }

  Future<void> _openSupplierChat(_QuickSupplierChatEntry entry) async {
    final conversation = entry.conversation;
    if (conversation != null) {
      openConversationInPanel(conversation.id);
      return;
    }

    setState(() => _openingSupplierId = entry.supplier.id);
    try {
      final provider = context.read<ChatProvider>();
      await provider.openWhatsAppCustomerChat(
        phoneNumber: entry.phone,
        contactName: entry.supplier.name,
        contextType: 'supplier',
        contextId: entry.supplier.id,
      );
      if (!mounted) return;
      final conversationId = provider.activeConversationId;
      setState(() {
        selectedConversationId = conversationId;
        panelActiveConversationId = conversationId;
        _openingSupplierId = null;
      });
      searchController.clear();
    } catch (error) {
      debugPrint('Error opening WhatsApp supplier from quick panel: $error');
      if (!mounted) return;
      setState(() => _openingSupplierId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar el chat del proveedor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<_QuickSupplierChatEntry> _filteredSupplierEntries(
    ChatProvider provider,
  ) {
    return _supplierEntries(
      provider,
      includeInactive: !showOnlyActiveChats,
    ).where(_matchesFilter).where(_matchesSearch).toList()
      ..sort(_compareSupplierEntries);
  }

  List<_QuickSupplierChatEntry> _supplierEntries(
    ChatProvider provider, {
    bool? includeInactive,
  }) {
    if (!_hasLoadedSupplierData) return const [];
    final supplierConversations = provider.conversations
        .where((conversation) => conversation.isSupplierConversation)
        .toList();
    return _quickSupplierEntries(
      supplierConversations,
      includeInactive: includeInactive ?? !showOnlyActiveChats,
    );
  }

  List<_QuickSupplierChatEntry> _quickSupplierEntries(
    List<Conversation> supplierConversations, {
    required bool includeInactive,
  }) {
    final entries = <_QuickSupplierChatEntry>[];
    final usedConversationIds = <String>{};
    final conversationIndex = _SupplierConversationIndex(
      supplierConversations,
      _phoneCandidates,
    );

    for (final supplier in _suppliers) {
      final phone = _supplierChatPhone(supplier);
      if (phone == null) continue;
      final conversation = conversationIndex.find(
        supplierId: supplier.id,
        phoneCandidates: _phoneCandidates(phone),
      );
      if (conversation != null) usedConversationIds.add(conversation.id);

      final invoices = _supplierInvoices(supplier.id);
      final hasActiveWork = ConversationActivity.hasActiveSupplierWork(
        conversation: conversation,
        purchaseInvoiceStatuses: invoices.map((invoice) => invoice.status.name),
      );
      if (!includeInactive && !hasActiveWork) {
        continue;
      }

      entries.add(
        _QuickSupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    for (final conversation in supplierConversations) {
      if (usedConversationIds.contains(conversation.id)) continue;
      // El hilo de un contacto desactivado vive en Historial: se conserva,
      // pero ya no es un chat en el que se trabaja.
      if (!includeInactive &&
          conversation.contextHint?.contactPersonIsActive == false) {
        continue;
      }
      final phone = conversation.contextHint?.supplierPhone ??
          conversation.contextHint?.phone ??
          '';
      if (!_hasWhatsAppPhone(phone)) continue;
      final supplier = _supplierFromConversation(conversation, phone);
      final invoices = supplier.id.isEmpty
          ? <PurchaseInvoice>[]
          : _supplierInvoices(supplier.id);
      final hasActiveWork = ConversationActivity.hasActiveSupplierWork(
        conversation: conversation,
        purchaseInvoiceStatuses: invoices.map((invoice) => invoice.status.name),
      );
      if (!includeInactive && !hasActiveWork) continue;

      entries.add(
        _QuickSupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    return entries;
  }

  shared_supplier.Supplier _supplierFromConversation(
    Conversation conversation,
    String phone,
  ) {
    final now = DateTime.now();
    return shared_supplier.Supplier(
      id: conversation.contextHint?.supplierId ?? conversation.contextId ?? '',
      tenantId: '',
      name: conversation.contextHint?.supplierLabel ??
          conversation.creatorName ??
          conversation.title ??
          phone,
      phone: phone,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<PurchaseInvoice> _supplierInvoices(String supplierId) {
    if (supplierId.isEmpty) return const [];
    return _invoicesBySupplierId[supplierId] ?? const [];
  }

  Map<String, List<PurchaseInvoice>> _indexInvoicesBySupplier(
    List<PurchaseInvoice> invoices,
  ) {
    final index = <String, List<PurchaseInvoice>>{};
    for (final invoice in invoices) {
      final supplierId = invoice.supplierId;
      if (supplierId == null || supplierId.isEmpty) continue;
      index.putIfAbsent(supplierId, () => []).add(invoice);
    }
    for (final supplierInvoices in index.values) {
      supplierInvoices.sort((a, b) => b.date.compareTo(a.date));
    }
    return index;
  }

  bool _matchesFilter(_QuickSupplierChatEntry entry) {
    return switch (_filter) {
      _SupplierMessageFilter.all => true,
      _SupplierMessageFilter.unread => _isUnreadSupplierEntry(entry),
    };
  }

  bool _isUnreadSupplierEntry(_QuickSupplierChatEntry entry) {
    final conversation = entry.conversation;
    return (conversation?.unreadCount ?? 0) > 0 ||
        (conversation?.isSupport == true && conversation?.status == 'pending');
  }

  bool _matchesSearch(_QuickSupplierChatEntry entry) {
    if (searchTerm.isEmpty) return true;
    return ConversationSearch.matches(searchTerm, [
      entry.supplier.name,
      entry.supplier.legalName,
      entry.supplier.tradeName,
      entry.supplier.contactPerson,
      entry.supplier.salesRepName,
      entry.supplier.email,
      entry.supplier.salesRepEmail,
      entry.supplier.rut,
      entry.phone,
      entry.conversation?.lastMessageContent ?? '',
      for (final invoice in entry.invoices)
        '${invoice.invoiceNumber} ${invoice.supplierInvoiceNumber ?? ''} ${invoice.status.displayName}',
    ]);
  }

  int _compareSupplierEntries(
    _QuickSupplierChatEntry a,
    _QuickSupplierChatEntry b,
  ) {
    final unreadCompare = (b.conversation?.unreadCount ?? 0)
        .compareTo(a.conversation?.unreadCount ?? 0);
    if (unreadCompare != 0) return unreadCompare;

    final aDate = a.lastActivityAt;
    final bDate = b.lastActivityAt;
    if (aDate != null && bDate != null) {
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
    }
    if (aDate != null) return -1;
    if (bDate != null) return 1;
    return a.supplier.name.toLowerCase().compareTo(
          b.supplier.name.toLowerCase(),
        );
  }

  /// El Teléfono de la ficha manda cuando sirve para WhatsApp; el vendedor
  /// sólo lo reemplaza si la ficha tiene un fijo o nada. Regla compartida en
  /// `supplierWhatsAppPhone`.
  String? _supplierChatPhone(shared_supplier.Supplier supplier) =>
      supplierWhatsAppPhone(
        phone: supplier.phone,
        salesRepPhone: supplier.salesRepPhone,
      );

  Set<String> _phoneCandidates(String? phone) {
    final digits = _normalizedPhone(phone);
    if (digits.isEmpty) return {};
    final candidates = <String>{digits};
    if (digits.startsWith('56') && digits.length > 2) {
      candidates.add(digits.substring(2));
    }
    if (digits.startsWith('9') && digits.length == 9) {
      candidates.add('56$digits');
    }
    if (digits.length >= 8) {
      candidates.add(digits.substring(digits.length - 8));
    }
    return candidates;
  }

  String _supplierInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  Color _purchaseInvoiceStatusColor(PurchaseInvoiceStatus status) {
    return switch (status) {
      PurchaseInvoiceStatus.paid => const Color(0xFF2563EB),
      PurchaseInvoiceStatus.received => const Color(0xFF16A34A),
      PurchaseInvoiceStatus.confirmed => const Color(0xFF7C3AED),
      PurchaseInvoiceStatus.sent => const Color(0xFF0EA5E9),
      PurchaseInvoiceStatus.cancelled => const Color(0xFFDC2626),
      PurchaseInvoiceStatus.draft => const Color(0xFF64748B),
    };
  }

  String _formatCLP(double value) {
    final rounded = value.round().toString();
    final formatted = rounded.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '\$$formatted';
  }

  Widget _buildEmptyState({
    required bool isTotallyEmpty,
    bool activeModeEmpty = false,
  }) {
    final theme = Theme.of(context);
    final title = activeModeEmpty
        ? 'Sin proveedores activos'
        : isTotallyEmpty
            ? 'Sin proveedores con WhatsApp'
            : 'No hay proveedores para este filtro';
    final subtitle = activeModeEmpty
        ? 'Desactiva "Solo activos" para ver el historial completo.'
        : isTotallyEmpty
            ? 'Los proveedores con teléfono aparecerán aquí para iniciar o retomar chats.'
            : 'Prueba con otro filtro o limpia la búsqueda.';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.storefront_outlined,
          size: 46,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickSupplierChatEntry {
  final shared_supplier.Supplier supplier;
  final String phone;
  final Conversation? conversation;
  final List<PurchaseInvoice> invoices;

  const _QuickSupplierChatEntry({
    required this.supplier,
    required this.phone,
    required this.conversation,
    required this.invoices,
  });

  List<PurchaseInvoice> get activeInvoices => invoices
      .where(
        (invoice) => ConversationActivity.isActivePurchaseInvoiceStatus(
          invoice.status.name,
        ),
      )
      .toList();

  PurchaseInvoice? relevantInvoice(bool showOnlyActive) {
    final relevantInvoices = showOnlyActive ? activeInvoices : invoices;
    if (relevantInvoices.isEmpty) return null;
    return relevantInvoices.first;
  }

  DateTime? get lastActivityAt {
    final conversationDate =
        conversation?.lastMessageAt ?? conversation?.updatedAt;
    if (conversationDate != null) return conversationDate;
    if (invoices.isEmpty) return null;
    return invoices.first.date;
  }
}

class _SupplierConversationIndex {
  final Map<String, Conversation> _bySupplierId = {};
  final Map<String, Conversation> _byPhoneCandidate = {};

  _SupplierConversationIndex(
    List<Conversation> conversations,
    Set<String> Function(String? phone) phoneCandidates,
  ) {
    for (final conversation in conversations) {
      final supplierId = conversation.contextHint?.supplierId ??
          (conversation.contextType == 'supplier'
              ? conversation.contextId
              : null);
      if (supplierId != null && supplierId.isNotEmpty) {
        _bySupplierId.putIfAbsent(supplierId, () => conversation);
      }

      final phone = conversation.contextHint?.supplierPhone ??
          conversation.contextHint?.phone;
      for (final candidate in phoneCandidates(phone)) {
        _byPhoneCandidate.putIfAbsent(candidate, () => conversation);
      }
    }
  }

  Conversation? find({
    required String supplierId,
    required Set<String> phoneCandidates,
  }) {
    final direct = _bySupplierId[supplierId];
    if (direct != null) return direct;
    for (final candidate in phoneCandidates) {
      final byPhone = _byPhoneCandidate[candidate];
      if (byPhone != null) return byPhone;
    }
    return null;
  }
}
