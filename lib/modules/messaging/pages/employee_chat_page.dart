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
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _softSurface = Color(0xFFF8FAFC);

  late TabController _tabController;
  ReferenceSegment? _activeReference;
  bool _isSidePanelExpanded = false;

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

          // Switch to correct tab (0 = Internal, 1 = Clients)
          if (targetConv.type == 'support') {
            _tabController.animateTo(1); // Clients tab
          } else {
            _tabController.animateTo(0); // Internal tab
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
    final targetIndex = conversation.type == 'support' ? 1 : 0;
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

  void _toggleSidePanelExpansion() {
    setState(() {
      _isSidePanelExpanded = !_isSidePanelExpanded;
    });
  }

  /// Group customer conversations by status
  Map<String, List<Conversation>> _groupByStatus(List<Conversation> convs) {
    return {
      'pending': convs.where((c) => c.status == 'pending').toList(),
      'active': convs
          .where((c) => c.status != 'pending' && c.status != 'resolved')
          .toList(),
      'resolved': convs.where((c) => c.status == 'resolved').toList(),
    };
  }

  /// Count pending customer requests
  int _getPendingCount(List<Conversation> all) {
    return all
        .where((c) => c.type == 'support' && c.status == 'pending')
        .length;
  }

  @override
  Widget build(BuildContext context) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mensajería interna',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Theme.of(context).primaryColor,
          tabs: [
            const Tab(icon: Icon(Icons.people), text: 'Equipo'),
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Internal Tab
          _buildInternalList(provider, activeId, allConversations),
          // Customer Tab
          _buildCustomerList(provider, activeId, allConversations),
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
    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar: Thread List
          Container(
            width: 360,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
              color: Colors.white,
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
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Theme.of(context).primaryColor,
                    unselectedLabelColor: Colors.grey[600],
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: [
                      Tab(text: 'Equipo ($internalCount)'),
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
                    ],
                  ),
                ),
                // List Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildInternalList(provider, activeId, allConversations),
                      _buildCustomerList(provider, activeId, allConversations),
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
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'Selecciona una conversación',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[500],
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
          else if (activeConversation?.contextId != null &&
              activeConversation?.contextType != null)
            ChatContextPanel(
              contextType: activeConversation!.contextType!,
              contextId: activeConversation.contextId!,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mensajería interna',
                  style: TextStyle(
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
            'Equipo y clientes WhatsApp, separados por flujo de trabajo.',
            style: TextStyle(
              color: Colors.grey[600],
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
    final color = alert ? const Color(0xFFB45309) : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: alert ? color.withValues(alpha: 0.06) : _softSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: alert ? color.withValues(alpha: 0.35) : _borderColor,
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
    final internalConvs =
        conversations.where((c) => c.type == 'internal').toList()
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
    final customerConvs =
        conversations.where((c) => c.type == 'support').toList()
          ..sort(_compareConversations);
    final grouped = _groupByStatus(customerConvs);

    if (customerConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.support_agent_outlined,
        title: 'Sin conversaciones de WhatsApp',
        subtitle: 'Los contactos con clientes aparecerán aquí',
      );
    }

    return ListView(
      children: [
        _buildSupportOverview(customerConvs),
        // Pending Section
        if (grouped['pending']!.isNotEmpty)
          _buildSection(
            icon: Icons.pending_actions,
            title: 'Solicitudes pendientes',
            subtitle: 'Requieren aceptación antes de responder como equipo.',
            count: grouped['pending']!.length,
            color: const Color(0xFFB45309),
            conversations: grouped['pending']!,
            provider: provider,
            activeId: activeId,
          ),

        // Active Section
        if (grouped['active']!.isNotEmpty)
          _buildSection(
            icon: Icons.chat_bubble,
            title: 'Conversaciones activas',
            subtitle: 'Clientes WhatsApp ya atendidos por el equipo.',
            count: grouped['active']!.length,
            color: const Color(0xFF047857),
            conversations: grouped['active']!,
            provider: provider,
            activeId: activeId,
          ),

        // Resolved Section
        if (grouped['resolved']!.isNotEmpty)
          _buildSection(
            icon: Icons.check_circle,
            title: 'Resueltas',
            subtitle: 'Historial cerrado, disponible para consulta.',
            count: grouped['resolved']!.length,
            color: Colors.grey,
            conversations: grouped['resolved']!,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _accentBlue),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
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
    final orderContexts = conversations
        .where((conversation) => conversation.contextType == 'order')
        .length;
    final unread = conversations.fold<int>(
      0,
      (sum, conversation) => sum + conversation.unreadCount,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bandeja de clientes WhatsApp',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Usa esta bandeja para revisar, personalizar y enviar respuestas al cliente.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMiniMetric(
                  'Pedidos',
                  orderContexts,
                  Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 8),
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
    final color = alert ? const Color(0xFFB45309) : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: _borderColor),
              bottom: BorderSide(color: _borderColor),
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
                        color: Colors.grey[600],
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
        'pending' => 'Solicitud pendiente',
        'resolved' => 'Resuelto',
        _ => 'Cliente WhatsApp',
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
