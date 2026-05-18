import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../messaging/models/conversation.dart';
import '../../messaging/providers/chat_provider.dart';
import '../../messaging/widgets/chat_window.dart';
import '../../messaging/widgets/new_chat_dialog.dart';
import '../../messaging/widgets/context_side_panel.dart';
import '../../messaging/widgets/chat_context_panel.dart';
import '../../messaging/utils/message_parser.dart';
import '../../messaging/widgets/conversation_tile.dart';
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
  ReferenceSegment? _activeReference;
  bool _isSidePanelExpanded = false;
  String? _closedContextConversationId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadConversations() {
    // Load all once - filter client-side
    final provider = context.read<ChatProvider>();
    provider.loadConversations().then((_) {
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
            _tabController.animateTo(0); // Clients tab
          } else {
            _tabController.animateTo(1); // Internal tab
          }

          // On mobile, navigate directly to the chat
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

  void _syncTabToActiveConversation(Conversation? conversation) {
    if (conversation == null) return;
    final targetIndex = conversation.type == 'support' ? 0 : 1;
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
    });
  }

  void _closeConversationContextPanel(Conversation? activeConversation) {
    if (activeConversation == null) return;
    setState(() {
      _closedContextConversationId = activeConversation.id;
    });
  }

  void _reopenConversationContextPanel() {
    setState(() {
      _closedContextConversationId = null;
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
        .where((c) => c.type == 'support' && c.status == 'pending')
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
    final internalConversations =
        allConversations.where((c) => c.type == 'internal').toList();
    final pendingCount = _getPendingCount(allConversations);
    final activeSupportCount = supportConversations
        .where((conversation) =>
            conversation.status != 'pending' &&
            conversation.status != 'resolved')
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
      activeSupportCount,
      internalConversations.length,
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
            const Tab(icon: Icon(Icons.people), text: 'Equipo'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Customer Tab
          _buildCustomerList(provider, activeId, allConversations),
          // Internal Tab
          _buildInternalList(provider, activeId, allConversations),
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
    int activeSupportCount,
    int internalCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasConversationContext =
        activeConversation?.hasSupportedContextPanel ?? false;
    final isConversationContextClosed = hasConversationContext &&
        activeConversation?.id == _closedContextConversationId;
    final showConversationContextPanel =
        hasConversationContext && !isConversationContextClosed;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Row(
        children: [
          // Left Sidebar: Thread List
          Container(
            width: 360,
            decoration: BoxDecoration(
              border:
                  Border(right: BorderSide(color: colorScheme.outlineVariant)),
              color: colorScheme.surface,
            ),
            child: Column(
              children: [
                // Header
                _buildMessagingHeader(
                  pendingCount: pendingCount,
                  activeSupportCount: activeSupportCount,
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
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Clientes ($activeSupportCount)'),
                            if (pendingCount > 0) ...[
                              const SizedBox(width: 8),
                              _buildBadge(pendingCount),
                            ],
                          ],
                        ),
                      ),
                      Tab(text: 'Equipo ($internalCount)'),
                    ],
                  ),
                ),
                // List Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCustomerList(provider, activeId, allConversations),
                      _buildInternalList(provider, activeId, allConversations),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Center Content: Chat Window
          if (!_isSidePanelExpanded)
            Expanded(
              child: activeConversation != null
                  ? ChatWindow(
                      conversation: activeConversation,
                      isContextPanelClosed: isConversationContextClosed,
                      onShowContextPanel: _reopenConversationContextPanel,
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
                          Icon(Icons.chat_bubble_outline,
                              size: 64,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.34)),
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

          // Right Sidebar: Context Panel (Smart Features or Chat Context)
          if (_activeReference != null)
            Expanded(
              child: ContextSidePanel(
                activeReference: _activeReference,
                onClose: _closeSidePanel,
                onToggleExpand: _toggleSidePanelExpansion,
                isExpanded: _isSidePanelExpanded,
              ),
            )
          else if (activeConversation?.hasSupportedContextPanel == true &&
              showConversationContextPanel)
            ChatContextPanel(
              contextType: activeConversation!.effectiveContextType!,
              contextId: activeConversation.effectiveContextId!,
              onClose: () => _closeConversationContextPanel(activeConversation),
            ),
        ],
      ),
    );
  }

  Widget _buildMessagingHeader({
    required int pendingCount,
    required int activeSupportCount,
    required int internalCount,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mensajería interna',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const NewChatDialog(),
                  );
                },
                tooltip: 'Nuevo chat',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadConversations,
                tooltip: 'Recargar',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Equipo, chat web y WhatsApp separados por canal.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMetric(
                  'Equipo',
                  internalCount,
                  Icons.people_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMetric(
                  'Activos',
                  activeSupportCount,
                  Icons.support_agent_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMetric(
                  'Solicitudes',
                  pendingCount,
                  Icons.pending_actions_outlined,
                  alert: pendingCount > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric(
    String label,
    int value,
    IconData icon, {
    bool alert = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color =
        alert ? const Color(0xFFB45309) : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: alert
            ? color.withValues(alpha: 0.06)
            : Color.alphaBlend(
                colorScheme.primary.withValues(alpha: 0.035),
                colorScheme.surface,
              ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: alert
              ? color.withValues(alpha: 0.35)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
        .toList()
      ..sort(_compareConversations);

    if (internalConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'Sin conversaciones internas',
        subtitle: 'Inicia un chat con un compañero',
      );
    }

    return ListView(
      children: [
        _buildListIntro(
          title: 'Chats de equipo',
          subtitle:
              'Conversaciones internas entre colaboradores. No salen por WhatsApp.',
          icon: Icons.people_outline,
        ),
        ...internalConvs.map(
          (conv) => _buildConversationTile(provider, conv, activeId),
        ),
      ],
    );
  }

  /// Build grouped list for customer chats
  Widget _buildCustomerList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    final customerConvs = conversations
        .where((c) => c.type == 'support')
        .toList()
      ..sort(_compareConversations);

    if (customerConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.support_agent_outlined,
        title: 'Sin conversaciones de clientes',
        subtitle: 'Los contactos con clientes aparecerán aquí',
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
    final resolvedConvs = customerConvs
        .where((conversation) => conversation.status == 'resolved')
        .toList();

    return ListView(
      children: [
        _buildSupportOverview(customerConvs),
        // Pending Section
        if (pendingConvs.isNotEmpty)
          _buildSection(
            icon: Icons.pending_actions,
            title: 'Solicitudes pendientes',
            subtitle:
                'Solicitudes nuevas. Cada fila indica si viene de web o WhatsApp.',
            count: pendingConvs.length,
            color: const Color(0xFFB45309),
            conversations: pendingConvs,
            provider: provider,
            activeId: activeId,
          ),

        // WhatsApp Section
        if (whatsAppConvs.isNotEmpty)
          _buildSection(
            icon: Icons.phone_in_talk_outlined,
            title: 'WhatsApp',
            subtitle: 'Mensajes que salen y entran por WhatsApp Cloud API.',
            count: whatsAppConvs.length,
            color: const Color(0xFF047857),
            conversations: whatsAppConvs,
            provider: provider,
            activeId: activeId,
          ),

        // Website Section
        if (websiteConvs.isNotEmpty)
          _buildSection(
            icon: Icons.language_outlined,
            title: 'Chat web',
            subtitle: 'Conversaciones del cliente desde cuenta web o tienda.',
            count: websiteConvs.length,
            color: _accentBlue,
            conversations: websiteConvs,
            provider: provider,
            activeId: activeId,
          ),

        // Resolved Section
        if (resolvedConvs.isNotEmpty)
          _buildSection(
            icon: Icons.check_circle,
            title: 'Resueltas',
            subtitle: 'Historial cerrado, disponible para consulta.',
            count: resolvedConvs.length,
            color: Colors.grey,
            conversations: resolvedConvs,
            provider: provider,
            activeId: activeId,
          ),
      ],
    );
  }

  Widget _buildListIntro({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.035),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportOverview(List<Conversation> conversations) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final orderContexts = conversations
        .where((conversation) => conversation.contextType == 'order')
        .length;
    final webConversations = conversations
        .where((conversation) => conversation.isWebsitePortal)
        .length;
    final whatsAppConversations =
        conversations.where((conversation) => conversation.isWhatsApp).length;
    final unread = conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.035),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bandeja de clientes',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chat web y WhatsApp viven separados para no mezclar canales ni permisos de envío.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  'Web',
                  webConversations,
                  Icons.language_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  'WhatsApp',
                  whatsAppConversations,
                  Icons.phone_in_talk_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniMetric(
                  'Pedidos',
                  orderContexts,
                  Icons.receipt_long_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  'Sin leer',
                  unread,
                  Icons.mark_chat_unread_outlined,
                  alert: unread > 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(
    String label,
    int value,
    IconData icon, {
    bool alert = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color =
        alert ? const Color(0xFFB45309) : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a section header with conversations
  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
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
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
              bottom: BorderSide(color: colorScheme.outlineVariant),
              left: BorderSide(color: color, width: 3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
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

    return ConversationTile(
      conversation: conv,
      isActive: isSelected,
      isMobile: isMobile,
      subtitle: _getSubtitle(conv),
      onTap: () {
        if (conv.id != activeId) {
          setState(() {
            _closedContextConversationId = null;
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
      onDelete: () => _showDeleteConfirmation(context, provider, conv),
    );
  }

  Future<bool> _showDeleteConfirmation(
    BuildContext context,
    ChatProvider provider,
    Conversation conv,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar chat?'),
        content: Text(
          'Estás a punto de eliminar el chat con "${provider.getChatTitle(conv)}". Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteConversation(conv.id);
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
        return 'Servicio técnico';
      case 'invoice':
        return 'Factura';
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
