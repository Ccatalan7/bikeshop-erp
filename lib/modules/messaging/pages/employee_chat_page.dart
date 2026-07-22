import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../messaging/models/conversation.dart';
import '../../messaging/providers/chat_provider.dart';
import '../../messaging/widgets/chat_window.dart';
import '../../messaging/widgets/new_chat_dialog.dart';
import '../../messaging/widgets/context_side_panel.dart';
import '../../messaging/widgets/chat_context_panel.dart';
import '../../messaging/utils/conversation_activity.dart';
import '../../messaging/utils/conversation_channel_presentation.dart';
import '../../messaging/utils/conversation_search.dart';
import '../../messaging/utils/message_parser.dart';
import '../../messaging/widgets/conversation_tile.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../settings/services/appearance_service.dart';

// Track last handled deep link with timestamp to prevent rapid re-processing
String? _lastHandledConversationId;
DateTime? _lastHandledTime;

class EmployeeChatPage extends StatefulWidget {
  final String? initialConversationId;

  const EmployeeChatPage({super.key, this.initialConversationId});

  @override
  State<EmployeeChatPage> createState() => _EmployeeChatPageState();
}

class _EmployeeChatPageState extends State<EmployeeChatPage>
    with SingleTickerProviderStateMixin {
  static const Color _accentBlue = Color(0xFF093357);

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  ReferenceSegment? _activeReference;
  bool _isSidePanelExpanded = false;
  String? _closedContextConversationId;
  List<shared_supplier.Supplier> _supplierChatSuppliers = [];
  Map<String, List<PurchaseInvoice>> _supplierInvoicesBySupplierId = const {};
  bool _isLoadingSupplierChats = false;
  bool _showOnlyActiveChats = true;
  String? _openingSupplierId;
  String _searchTerm = '';
  bool _isNarrowContextOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_handleSearchChanged);
    ConversationActivity.showOnlyActiveChats.addListener(
      _handleActiveModeChanged,
    );
    unawaited(_loadMessagingPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
      unawaited(_loadSupplierChatData());
    });
  }

  @override
  void dispose() {
    ConversationActivity.showOnlyActiveChats.removeListener(
      _handleActiveModeChanged,
    );
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = ConversationSearch.normalize(_searchController.text);
    if (next == _searchTerm) return;
    setState(() => _searchTerm = next);
  }

  void _loadConversations() {
    // Load all once - filter client-side
    final provider = context.read<ChatProvider>();
    unawaited(_loadSupplierChatData());
    provider.loadConversations(refreshContextHints: true).then((_) {
      // If opened from notification with a specific conversation, select it
      // Use time-based deduplication: skip if same conversation handled within 2 seconds
      final now = DateTime.now();
      final isDuplicate =
          widget.initialConversationId == _lastHandledConversationId &&
              _lastHandledTime != null &&
              now.difference(_lastHandledTime!).inSeconds < 2;

      if (widget.initialConversationId != null && !isDuplicate) {
        _lastHandledConversationId = widget.initialConversationId;
        _lastHandledTime = now;

        // Strip the query param from URL to prevent re-triggering
        if (mounted) {
          context.go('/chat');
        }

        debugPrint(
            '🔔 Deep link: selecting conversation ${widget.initialConversationId}');
        provider.setActiveConversation(widget.initialConversationId!);

        // Find the conversation to determine its type and switch tabs
        final conversations = provider.conversations;
        final targetConv = conversations
            .where((c) => c.id == widget.initialConversationId)
            .firstOrNull;

        if (targetConv != null) {
          debugPrint('🔔 Found conversation type: ${targetConv.type}');

          // Switch to correct tab (0 = Clients, 1 = Internal)
          if (targetConv.type == 'support') {
            _tabController.animateTo(
              targetConv.isSupplierConversation ? 1 : 0,
            );
          } else {
            _tabController.animateTo(2); // Internal tab
          }

          // On mobile, navigate directly to the chat
          if (!mounted) return;
          final isMobile = MediaQuery.of(context).size.width < 900;
          if (isMobile) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatWindow(conversation: targetConv),
              ),
            );
          }
        }
      }
    });
  }

  Future<void> _loadSupplierChatData() async {
    if (_isLoadingSupplierChats || !mounted) return;
    setState(() => _isLoadingSupplierChats = true);
    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers(activeOnly: true);
      final invoices = await purchaseService.getPurchaseInvoicesForList();

      if (!mounted) return;
      setState(() {
        _supplierChatSuppliers = suppliers
            .where((supplier) => _supplierChatPhone(supplier) != null)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _supplierInvoicesBySupplierId = _indexInvoicesBySupplier(invoices);
        _isLoadingSupplierChats = false;
      });
    } catch (error) {
      debugPrint('Error loading supplier chat data: $error');
      if (mounted) setState(() => _isLoadingSupplierChats = false);
    }
  }

  Future<void> _loadMessagingPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final showOnlyActive =
        prefs.getBool(ConversationActivity.activeOnlyPreferenceKey) ?? true;
    if (!mounted) return;
    if (ConversationActivity.showOnlyActiveChats.value != showOnlyActive) {
      ConversationActivity.showOnlyActiveChats.value = showOnlyActive;
    } else {
      setState(() => _showOnlyActiveChats = showOnlyActive);
    }
  }

  Future<void> _setShowOnlyActiveChats(bool value) async {
    if (ConversationActivity.showOnlyActiveChats.value != value) {
      ConversationActivity.showOnlyActiveChats.value = value;
    } else if (mounted) {
      setState(() => _showOnlyActiveChats = value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ConversationActivity.activeOnlyPreferenceKey, value);
  }

  void _handleActiveModeChanged() {
    if (!mounted) return;
    final value = ConversationActivity.showOnlyActiveChats.value;
    if (_showOnlyActiveChats == value) return;
    setState(() => _showOnlyActiveChats = value);
  }

  void _syncTabToActiveConversation(Conversation? conversation) {
    if (conversation == null) return;
    final targetIndex = conversation.type == 'support'
        ? (conversation.isSupplierConversation ? 1 : 0)
        : 2;
    if (_tabController.index == targetIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tabController.index != targetIndex) {
        _tabController.animateTo(targetIndex);
      }
    });
  }

  void _closeSidePanel() {
    setState(() {
      _activeReference = null;
      _isSidePanelExpanded = false;
      _isNarrowContextOverlayOpen = false;
    });
  }

  void _closeConversationContextPanel(Conversation? activeConversation) {
    if (activeConversation == null) return;
    setState(() {
      _closedContextConversationId = activeConversation.id;
      _isNarrowContextOverlayOpen = false;
    });
  }

  void _reopenConversationContextPanel({required bool asOverlay}) {
    setState(() {
      _closedContextConversationId = null;
      _isNarrowContextOverlayOpen = asOverlay;
    });
  }

  void _toggleSidePanelExpansion() {
    setState(() {
      _isSidePanelExpanded = !_isSidePanelExpanded;
    });
  }

  /// Count pending customer requests
  int _getPendingCount(List<Conversation> all) {
    return all
        .where((c) =>
            c.type == 'support' &&
            c.status == 'pending' &&
            !c.isSupplierConversation)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final appearanceService = context.watch<AppearanceService>();
    if (appearanceService.messagingUsesSidebarPalette) {
      final paletteTheme = buildSidebarPaletteTheme(
        Theme.of(context),
        appearanceService.sidebarPalette,
      );

      return Theme(
        data: paletteTheme,
        child: Builder(builder: _buildContent),
      );
    }

    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final activeId = provider.activeConversationId;
    final allConversations = provider.conversations;
    final isMobile = MediaQuery.of(context).size.width < 900;

    final supportConversations =
        allConversations.where((c) => c.type == 'support').toList();
    final supplierConversations =
        supportConversations.where((c) => c.isSupplierConversation).toList();
    final customerConversations =
        supportConversations.where((c) => !c.isSupplierConversation).toList();
    final internalConversations =
        allConversations.where((c) => c.type == 'internal').toList();
    final pendingCount = _getPendingCount(allConversations);
    final visibleCustomerCount = customerConversations
        .where((conversation) =>
            !_showOnlyActiveChats ||
            ConversationActivity.isActiveConversation(conversation))
        .where((conversation) =>
            _matchesConversationSearch(provider, conversation))
        .length;
    final supplierEntryCount = _supplierChatEntries(
      supplierConversations,
      includeInactive: !_showOnlyActiveChats,
    ).where(_matchesSupplierEntrySearch).length;
    final visibleInternalCount = internalConversations
        .where((conversation) =>
            _matchesConversationSearch(provider, conversation))
        .length;

    // Find active conversation object
    Conversation? activeConversation;
    if (activeId != null) {
      try {
        activeConversation =
            allConversations.firstWhere((c) => c.id == activeId);
      } catch (_) {}
    }

    _syncTabToActiveConversation(activeConversation);

    if (isMobile) {
      return _buildMobileLayout(
        provider,
        activeId,
        allConversations,
        pendingCount,
      );
    }

    return _buildDesktopLayout(
      provider,
      activeId,
      activeConversation,
      allConversations,
      pendingCount,
      visibleCustomerCount,
      supplierEntryCount,
      visibleInternalCount,
    );
  }

  Widget _buildMobileLayout(
    ChatProvider provider,
    String? activeId,
    List<Conversation> allConversations,
    int pendingCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Mensajería interna',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildActivityModeMenu(compact: true),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const NewChatDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConversations,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: colorScheme.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.support_agent),
                  const SizedBox(width: 8),
                  const Text('Clientes'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildBadge(pendingCount),
                  ],
                ],
              ),
            ),
            const Tab(
              icon: Icon(Icons.storefront_outlined),
              text: 'Proveedores',
            ),
            const Tab(icon: Icon(Icons.people), text: 'Equipo'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchField(horizontalPadding: 12, verticalPadding: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCustomerList(provider, activeId, allConversations),
                _buildSupplierList(provider, activeId, allConversations),
                _buildInternalList(provider, activeId, allConversations),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    ChatProvider provider,
    String? activeId,
    Conversation? activeConversation,
    List<Conversation> allConversations,
    int pendingCount,
    int activeCustomerCount,
    int supplierCount,
    int internalCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasConversationContext =
        activeConversation?.hasSupportedContextPanel ?? false;
    final isConversationContextManuallyClosed = hasConversationContext &&
        activeConversation?.id == _closedContextConversationId;
    final showConversationContextPanel =
        hasConversationContext && !isConversationContextManuallyClosed;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = (constraints.maxWidth * 0.3).clamp(380.0, 440.0);
          final useContextOverlay = constraints.maxWidth < 1200;
          final isContextClosedForChat = isConversationContextManuallyClosed ||
              (useContextOverlay && !_isNarrowContextOverlayOpen);
          final showReferenceOverlay = useContextOverlay &&
              _activeReference != null &&
              !_isSidePanelExpanded;
          final showConversationOverlay = useContextOverlay &&
              _activeReference == null &&
              showConversationContextPanel &&
              _isNarrowContextOverlayOpen;
          final overlayWidth = (constraints.maxWidth - sidebarWidth)
              .clamp(300.0, 360.0)
              .toDouble();
          return Row(
            children: [
              // Left Sidebar: Thread List
              Container(
                width: sidebarWidth,
                decoration: BoxDecoration(
                  border: Border(
                      right: BorderSide(color: colorScheme.outlineVariant)),
                  color: colorScheme.surface,
                ),
                child: Column(
                  children: [
                    // Header
                    _buildMessagingHeader(
                      pendingCount: pendingCount,
                      activeCustomerCount: activeCustomerCount,
                      supplierCount: supplierCount,
                      internalCount: internalCount,
                    ),
                    // Tab Bar
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: colorScheme.outlineVariant),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: colorScheme.primary,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        tabs: [
                          Tab(text: 'Clientes $activeCustomerCount'),
                          Tab(text: 'Proveedores $supplierCount'),
                          Tab(text: 'Equipo $internalCount'),
                        ],
                      ),
                    ),
                    // List Content
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildCustomerList(
                              provider, activeId, allConversations),
                          _buildSupplierList(
                              provider, activeId, allConversations),
                          _buildInternalList(
                              provider, activeId, allConversations),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Center Content: Chat Window
              if (!_isSidePanelExpanded)
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: activeConversation != null
                            ? ChatWindow(
                                conversation: activeConversation,
                                isContextPanelClosed: isContextClosedForChat,
                                onShowContextPanel: () =>
                                    _reopenConversationContextPanel(
                                  asOverlay: useContextOverlay,
                                ),
                                onReferenceTap: (ref) {
                                  setState(() {
                                    _activeReference = ref;
                                    _isSidePanelExpanded = false;
                                  });
                                },
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 64,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.34),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Selecciona una conversación',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (showReferenceOverlay || showConversationOverlay) ...[
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: showReferenceOverlay
                                ? _closeSidePanel
                                : () => _closeConversationContextPanel(
                                      activeConversation,
                                    ),
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          width: overlayWidth,
                          child: Material(
                            elevation: 4,
                            color: colorScheme.surface,
                            child: showReferenceOverlay
                                ? ContextSidePanel(
                                    activeReference: _activeReference,
                                    onClose: _closeSidePanel,
                                    onToggleExpand: _toggleSidePanelExpansion,
                                    isExpanded: false,
                                  )
                                : ChatContextPanel(
                                    contextType: activeConversation!
                                        .effectiveContextType!,
                                    contextId:
                                        activeConversation.effectiveContextId!,
                                    onClose: () =>
                                        _closeConversationContextPanel(
                                      activeConversation,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Right Sidebar: Context Panel (Smart Features or Chat Context)
              if (_activeReference != null &&
                  (!useContextOverlay || _isSidePanelExpanded))
                Expanded(
                  child: ContextSidePanel(
                    activeReference: _activeReference,
                    onClose: _closeSidePanel,
                    onToggleExpand: _toggleSidePanelExpansion,
                    isExpanded: _isSidePanelExpanded,
                  ),
                )
              else if (activeConversation?.hasSupportedContextPanel == true &&
                  showConversationContextPanel &&
                  !useContextOverlay)
                ChatContextPanel(
                  contextType: activeConversation!.effectiveContextType!,
                  contextId: activeConversation.effectiveContextId!,
                  onClose: () =>
                      _closeConversationContextPanel(activeConversation),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessagingHeader({
    required int pendingCount,
    required int activeCustomerCount,
    required int supplierCount,
    required int internalCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mensajes',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$activeCustomerCount clientes · $supplierCount proveedores · $internalCount equipo'
                      '${pendingCount > 0 ? ' · $pendingCount pendientes' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_comment_outlined, size: 19),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const NewChatDialog(),
                  );
                },
                tooltip: 'Nuevo chat',
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadConversations,
                tooltip: 'Recargar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildSearchField()),
              const SizedBox(width: 8),
              _buildActivityModeMenu(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    double horizontalPadding = 0,
    double verticalPadding = 0,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: colorScheme.surfaceContainerLowest,
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchTerm.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: _searchController.clear,
                  ),
            hintText: 'Nombre, teléfono, trabajo, bici o factura',
            hintStyle: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              fontSize: 12,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityModeMenu({bool compact = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<bool>(
      initialValue: _showOnlyActiveChats,
      tooltip: 'Elegir alcance de la bandeja',
      onSelected: (value) => unawaited(_setShowOnlyActiveChats(value)),
      itemBuilder: (context) => [
        _buildActivityMenuItem(
          value: true,
          icon: Icons.bolt_outlined,
          label: 'Activos',
          description: 'Trabajo operativo abierto',
        ),
        _buildActivityMenuItem(
          value: false,
          icon: Icons.history,
          label: 'Historial',
          description: 'Incluye conversaciones cerradas',
        ),
      ],
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _showOnlyActiveChats ? Icons.bolt_outlined : Icons.history,
              size: 16,
              color: colorScheme.primary,
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Text(
                  _showOnlyActiveChats ? 'Activos' : 'Historial',
                  key: ValueKey(_showOnlyActiveChats),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.expand_more,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<bool> _buildActivityMenuItem({
    required bool value,
    required IconData icon,
    required String label,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = value == _showOnlyActiveChats;
    return PopupMenuItem<bool>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected) Icon(Icons.check, size: 17, color: colorScheme.primary),
        ],
      ),
    );
  }

  /// Build simple list for internal chats
  Widget _buildInternalList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    // For internal tab, show filtered internal conversations
    final internalConvs = conversations
        .where((c) => c.type == 'internal')
        .where((conversation) =>
            _matchesConversationSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);

    if (internalConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: _searchTerm.isEmpty
            ? 'Sin conversaciones internas'
            : 'Sin coincidencias en equipo',
        subtitle: _searchTerm.isEmpty
            ? 'Inicia un chat con un compañero'
            : 'Prueba con otro nombre, teléfono o mensaje',
      );
    }

    return ListView(
      children: internalConvs
          .map((conv) => _buildConversationTile(provider, conv, activeId))
          .toList(),
    );
  }

  /// Build grouped list for customer chats
  Widget _buildCustomerList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    final customerConvs = conversations
        .where((c) =>
            c.type == 'support' &&
            !c.isSupplierConversation &&
            (!_showOnlyActiveChats ||
                ConversationActivity.isActiveConversation(c)))
        .where((conversation) =>
            _matchesConversationSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);

    if (customerConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.support_agent_outlined,
        title: _searchTerm.isEmpty
            ? 'Sin conversaciones de clientes'
            : 'Sin coincidencias en clientes',
        subtitle: _searchTerm.isNotEmpty
            ? 'Prueba con otro nombre, teléfono, trabajo, bici o factura'
            : _showOnlyActiveChats
                ? 'No hay clientes con trabajos, facturas o solicitudes abiertas'
                : 'Los contactos con clientes aparecerán aquí',
      );
    }

    final pendingConvs = customerConvs
        .where((conversation) => conversation.status == 'pending')
        .toList();
    final whatsAppConvs = customerConvs
        .where((conversation) =>
            conversation.isWhatsApp &&
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
        .toList();
    final websiteConvs = customerConvs
        .where((conversation) =>
            conversation.isWebsitePortal &&
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
        .toList();
    final instagramConvs = customerConvs
        .where((conversation) =>
            conversation.isInstagram &&
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
        .toList();
    final facebookMessengerConvs = customerConvs
        .where((conversation) =>
            conversation.isFacebookMessenger &&
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
        .toList();
    // Keep a visible fallback so a newly introduced provider can never vanish
    // from the canonical inbox merely because its dedicated section has not
    // shipped yet.
    final otherChannelConvs = customerConvs
        .where((conversation) =>
            !conversation.isWhatsApp &&
            !conversation.isWebsitePortal &&
            !conversation.isMetaMessaging &&
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
        .toList();
    final resolvedConvs = customerConvs
        .where((conversation) => conversation.status == 'resolved')
        .toList();

    return ListView(
      children: [
        // Pending Section
        if (pendingConvs.isNotEmpty)
          _buildSection(
            icon: Icons.pending_actions,
            title: 'Solicitudes pendientes',
            count: pendingConvs.length,
            color: const Color(0xFFB45309),
            conversations: pendingConvs,
            provider: provider,
            activeId: activeId,
          ),

        // WhatsApp Section
        if (whatsAppConvs.isNotEmpty)
          _buildSection(
            icon: ConversationChannelPresentation.iconForChannel('whatsapp'),
            title: 'WhatsApp',
            count: whatsAppConvs.length,
            color: ConversationChannelPresentation.whatsAppAccent,
            conversations: whatsAppConvs,
            provider: provider,
            activeId: activeId,
          ),

        if (instagramConvs.isNotEmpty)
          _buildSection(
            icon: ConversationChannelPresentation.iconForChannel('instagram'),
            title: 'Instagram',
            count: instagramConvs.length,
            color: ConversationChannelPresentation.instagramAccent,
            conversations: instagramConvs,
            provider: provider,
            activeId: activeId,
          ),

        if (facebookMessengerConvs.isNotEmpty)
          _buildSection(
            icon: ConversationChannelPresentation.iconForChannel(
              'facebook_messenger',
            ),
            title: 'Facebook Messenger',
            count: facebookMessengerConvs.length,
            color: ConversationChannelPresentation.facebookMessengerAccent,
            conversations: facebookMessengerConvs,
            provider: provider,
            activeId: activeId,
          ),

        // Website Section
        if (websiteConvs.isNotEmpty)
          _buildSection(
            icon: Icons.language_outlined,
            title: 'Chat web',
            count: websiteConvs.length,
            color: _accentBlue,
            conversations: websiteConvs,
            provider: provider,
            activeId: activeId,
          ),

        if (otherChannelConvs.isNotEmpty)
          _buildSection(
            icon: Icons.chat_bubble_outline,
            title: 'Otros canales',
            count: otherChannelConvs.length,
            color: ConversationChannelPresentation.internalAccent,
            conversations: otherChannelConvs,
            provider: provider,
            activeId: activeId,
          ),

        // Resolved Section
        if (!_showOnlyActiveChats && resolvedConvs.isNotEmpty)
          _buildSection(
            icon: Icons.check_circle,
            title: 'Resueltas',
            count: resolvedConvs.length,
            color: Colors.grey,
            conversations: resolvedConvs,
            provider: provider,
            activeId: activeId,
          ),
      ],
    );
  }

  Widget _buildSupplierList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    final supplierConvs = conversations
        .where((c) => c.type == 'support' && c.isSupplierConversation)
        .toList()
      ..sort(_compareConversations);
    final entries = _supplierChatEntries(
      supplierConvs,
      includeInactive: !_showOnlyActiveChats,
    ).where(_matchesSupplierEntrySearch).toList();

    if (_isLoadingSupplierChats && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (entries.isEmpty) {
      return _buildEmptyState(
        icon: Icons.storefront_outlined,
        title: _searchTerm.isEmpty
            ? 'Sin chats de proveedores'
            : 'Sin coincidencias en proveedores',
        subtitle: _searchTerm.isNotEmpty
            ? 'Prueba con el proveedor, teléfono o número de compra'
            : _showOnlyActiveChats
                ? 'No hay proveedores con chats o compras activas'
                : 'Los proveedores con WhatsApp aparecerán aquí',
      );
    }

    return ListView(
      children: [
        for (final entry in entries) ...[
          _buildSupplierChatTile(entry, activeId),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ],
      ],
    );
  }

  Widget _buildSupplierChatTile(
    _SupplierChatEntry entry,
    String? activeId,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conversation = entry.conversation;
    final isSelected = conversation?.id == activeId;
    final isOpening = _openingSupplierId == entry.supplier.id;
    final preview = conversation?.lastMessageContent?.trim();
    final relevantInvoices =
        _showOnlyActiveChats ? entry.activeInvoices : entry.invoices;
    final visibleInvoice =
        relevantInvoices.isEmpty ? null : relevantInvoices.first;

    if (conversation != null) {
      final provider = context.read<ChatProvider>();
      return ConversationTile(
        key: ValueKey(conversation.id),
        conversation: conversation,
        isActive: isSelected,
        isMobile: MediaQuery.sizeOf(context).width < 900,
        titleOverride: entry.supplier.name,
        subtitle: '${entry.phone} · Proveedor WhatsApp',
        operationalStatusLabel: visibleInvoice == null
            ? null
            : _supplierInvoiceOperationalLabel(visibleInvoice),
        operationalStatusColor: visibleInvoice == null
            ? null
            : _purchaseInvoiceStatusColor(visibleInvoice.status),
        secondaryContextLine: visibleInvoice == null
            ? entry.phone
            : _formatCLP(
                visibleInvoice.balance > 0
                    ? visibleInvoice.balance
                    : visibleInvoice.total,
              ),
        onTap: () => _openSupplierChat(entry),
        onArchive: () =>
            _showArchiveConfirmation(context, provider, conversation),
      );
    }

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: isOpening ? null : () => _openSupplierChat(entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                child: Text(
                  _supplierInitials(entry.supplier.name),
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.supplier.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (conversation?.unreadCount != null &&
                            conversation!.unreadCount > 0)
                          _buildBadge(conversation.unreadCount),
                      ],
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
                    if (visibleInvoice != null) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [_buildSupplierInvoiceChip(visibleInvoice)],
                      ),
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
                  conversation == null
                      ? Icons.add_comment_outlined
                      : Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierInvoiceChip(PurchaseInvoice invoice) {
    final color = _purchaseInvoiceStatusColor(invoice.status);
    final label = [
      invoice.invoiceNumber.isEmpty ? 'Compra' : invoice.invoiceNumber,
      invoice.status.displayName,
    ].join(' · ');

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$label · ${_formatCLP(invoice.balance > 0 ? invoice.balance : invoice.total)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }

  String _supplierInvoiceOperationalLabel(PurchaseInvoice invoice) {
    final number = invoice.invoiceNumber.isEmpty
        ? invoice.supplierInvoiceNumber ?? 'Compra'
        : invoice.invoiceNumber;
    return '$number · ${invoice.status.displayName}';
  }

  Future<void> _openSupplierChat(_SupplierChatEntry entry) async {
    final conversation = entry.conversation;
    if (conversation != null) {
      setState(() {
        _closedContextConversationId = null;
        _isNarrowContextOverlayOpen = false;
        _activeReference = null;
        _isSidePanelExpanded = false;
      });
      context.read<ChatProvider>().setActiveConversation(conversation.id);
      if (MediaQuery.of(context).size.width < 900) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatWindow(conversation: conversation),
          ),
        );
      }
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
      _tabController.animateTo(1);
      setState(() => _openingSupplierId = null);
    } catch (error) {
      debugPrint('Error opening WhatsApp supplier chat: $error');
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

  List<_SupplierChatEntry> _supplierChatEntries(
    List<Conversation> supplierConversations, {
    required bool includeInactive,
  }) {
    final entries = <_SupplierChatEntry>[];
    final usedConversationIds = <String>{};

    for (final supplier in _supplierChatSuppliers) {
      final phone = _supplierChatPhone(supplier);
      if (phone == null) continue;
      final conversation = _findSupplierConversation(
        supplier,
        supplierConversations,
      );
      if (conversation != null) usedConversationIds.add(conversation.id);

      final invoices = _supplierInvoices(supplier.id);
      final hasActiveInvoices = invoices.any(_isActivePurchaseInvoice);
      final hasStandaloneActiveConversation = invoices.isEmpty &&
          conversation != null &&
          ConversationActivity.isActiveConversation(conversation);
      final hasActiveWork =
          hasActiveInvoices || hasStandaloneActiveConversation;
      if (!includeInactive && !hasActiveWork) continue;

      entries.add(
        _SupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    for (final conversation in supplierConversations) {
      if (usedConversationIds.contains(conversation.id)) continue;
      final phone = conversation.contextHint?.supplierPhone ??
          conversation.contextHint?.phone ??
          '';
      if (!_hasWhatsAppLikePhone(phone)) continue;
      final supplier = _supplierFromConversation(conversation, phone);
      final invoices = supplier.id.isEmpty
          ? <PurchaseInvoice>[]
          : _supplierInvoices(supplier.id);
      final hasActiveInvoices = invoices.any(_isActivePurchaseInvoice);
      final hasActiveWork = hasActiveInvoices ||
          (invoices.isEmpty &&
              ConversationActivity.isActiveConversation(conversation));
      if (!includeInactive && !hasActiveWork) continue;

      entries.add(
        _SupplierChatEntry(
          supplier: supplier,
          phone: phone,
          conversation: conversation,
          invoices: invoices,
        ),
      );
    }

    entries.sort((a, b) {
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
    });

    return entries;
  }

  Conversation? _findSupplierConversation(
    shared_supplier.Supplier supplier,
    List<Conversation> conversations,
  ) {
    for (final conversation in conversations) {
      if (conversation.contextHint?.supplierId == supplier.id ||
          (conversation.contextType == 'supplier' &&
              conversation.contextId == supplier.id)) {
        return conversation;
      }
    }

    final supplierPhones = _phoneCandidates(_supplierChatPhone(supplier));
    if (supplierPhones.isEmpty) return null;
    for (final conversation in conversations) {
      final conversationPhones = _phoneCandidates(
        conversation.contextHint?.supplierPhone ??
            conversation.contextHint?.phone,
      );
      if (supplierPhones.intersection(conversationPhones).isNotEmpty) {
        return conversation;
      }
    }
    return null;
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
    return _supplierInvoicesBySupplierId[supplierId] ?? const [];
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

  bool _isActivePurchaseInvoice(PurchaseInvoice invoice) {
    return ConversationActivity.isActivePurchaseInvoiceStatus(
      invoice.status.name,
    );
  }

  String? _supplierChatPhone(shared_supplier.Supplier supplier) {
    final salesRepPhone = supplier.salesRepPhone?.trim();
    if (_hasWhatsAppLikePhone(salesRepPhone)) return salesRepPhone;
    final phone = supplier.phone?.trim();
    if (_hasWhatsAppLikePhone(phone)) return phone;
    return null;
  }

  bool _hasWhatsAppLikePhone(String? phone) {
    return _normalizedPhone(phone).length >= 8;
  }

  String _normalizedPhone(String? phone) {
    return phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

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

  bool _matchesConversationSearch(
    ChatProvider provider,
    Conversation conversation,
  ) {
    if (_searchTerm.isEmpty) return true;
    final hint = conversation.contextHint;
    return ConversationSearch.matches(_searchTerm, [
      provider.getChatTitle(conversation),
      conversation.title ?? '',
      conversation.creatorName ?? '',
      conversation.channelLabel,
      conversation.lastMessageContent ?? '',
      conversation.contextType ?? '',
      conversation.contextId ?? '',
      hint?.customerName ?? '',
      hint?.phone ?? '',
      hint?.jobNumber ?? '',
      hint?.jobStatus ?? '',
      hint?.bikeName ?? '',
      hint?.invoiceNumber ?? '',
      hint?.invoiceStatus ?? '',
      hint?.supplierName ?? '',
      hint?.supplierPhone ?? '',
      hint?.purchaseInvoiceNumber ?? '',
      hint?.purchaseInvoiceStatus ?? '',
      _getSubtitle(conversation),
    ]);
  }

  bool _matchesSupplierEntrySearch(_SupplierChatEntry entry) {
    if (_searchTerm.isEmpty) return true;
    final supplier = entry.supplier;
    return ConversationSearch.matches(_searchTerm, [
      supplier.name,
      supplier.legalName ?? '',
      supplier.tradeName ?? '',
      supplier.contactPerson ?? '',
      supplier.salesRepName ?? '',
      supplier.email ?? '',
      supplier.salesRepEmail ?? '',
      supplier.phone ?? '',
      supplier.salesRepPhone ?? '',
      supplier.rut ?? '',
      entry.phone,
      entry.conversation?.lastMessageContent ?? '',
      ...entry.invoices.expand(
        (invoice) => [invoice.invoiceNumber, invoice.status.displayName],
      ),
    ]);
  }

  /// Build a section header with conversations
  Widget _buildSection({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required List<Conversation> conversations,
    required ChatProvider provider,
    required String? activeId,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.035),
              colorScheme.surface,
            ),
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Conversations
        ...conversations
            .map((conv) => _buildConversationTile(provider, conv, activeId)),
      ],
    );
  }

  int _compareConversations(Conversation a, Conversation b) {
    final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
    if (unreadCompare != 0) return unreadCompare;

    final aDate = a.lastMessageAt ?? a.updatedAt;
    final bDate = b.lastMessageAt ?? b.updatedAt;
    return bDate.compareTo(aDate);
  }

  Widget _buildConversationTile(
      ChatProvider provider, Conversation conv, String? activeId) {
    final isSelected = conv.id == activeId;
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConversationTile(
          conversation: conv,
          isActive: isSelected,
          isMobile: isMobile,
          subtitle: _getSubtitle(conv),
          onTap: () {
            if (conv.id != activeId) {
              setState(() {
                _closedContextConversationId = null;
                _isNarrowContextOverlayOpen = false;
                _activeReference = null;
                _isSidePanelExpanded = false;
              });
            }
            context.read<ChatProvider>().setActiveConversation(conv.id);
            if (isMobile) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatWindow(conversation: conv),
                ),
              );
            }
          },
          onArchive: () => _showArchiveConfirmation(context, provider, conv),
        ),
        Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ],
    );
  }

  Future<bool> _showArchiveConfirmation(
    BuildContext context,
    ChatProvider provider,
    Conversation conv,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Archivar chat?'),
        content: Text(
          'El chat con "${provider.getChatTitle(conv)}" pasará al historial. Sus mensajes, vínculos y estados de entrega se conservarán.',
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

    if (confirmed == true) {
      await provider.archiveConversation(conv.id);
      return true;
    }
    return false;
  }

  String _getSubtitle(Conversation conv) {
    final contextLabel = _getContextLabel(conv.contextType);

    if (conv.type == 'support') {
      final statusLabel = switch (conv.status) {
        'pending' =>
          'Solicitud ${conv.shortChannelLabel.toLowerCase()} pendiente',
        'resolved' => 'Resuelto',
        _ => conv.channelLabel,
      };
      return contextLabel == null
          ? statusLabel
          : '$contextLabel · $statusLabel';
    }

    return contextLabel == null ? 'Chat de equipo' : '$contextLabel · Equipo';
  }

  String? _getContextLabel(String? contextType) {
    switch (contextType) {
      case 'order':
        return 'Pedido web';
      case 'job':
        return 'Trabajo';
      case 'invoice':
        return 'Factura';
      case 'purchase_invoice':
        return 'Compra';
      case 'supplier':
        return 'Proveedor';
      case 'bike':
        return 'Bicicleta';
      case 'customer':
        return 'Cliente';
      case 'product':
        return 'Producto';
      default:
        return null;
    }
  }

  Widget _buildBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierChatEntry {
  final shared_supplier.Supplier supplier;
  final String phone;
  final Conversation? conversation;
  final List<PurchaseInvoice> invoices;

  const _SupplierChatEntry({
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

  DateTime? get lastActivityAt {
    final conversationDate =
        conversation?.lastMessageAt ?? conversation?.updatedAt;
    if (conversationDate != null) return conversationDate;
    if (invoices.isEmpty) return null;
    return invoices.first.date;
  }
}
