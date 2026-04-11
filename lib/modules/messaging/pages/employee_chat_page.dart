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
      'active': convs.where((c) => c.status == 'active').toList(),
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

    final pendingCount = _getPendingCount(allConversations);

    // Find active conversation object
    Conversation? activeConversation;
    if (activeId != null) {
      try {
        activeConversation =
            allConversations.firstWhere((c) => c.id == activeId);
      } catch (_) {}
    }

    if (isMobile) {
      return _buildMobileLayout(
          provider, activeId, allConversations, pendingCount);
    }

    return _buildDesktopLayout(
        provider, activeId, activeConversation, allConversations, pendingCount);
  }

  Widget _buildMobileLayout(ChatProvider provider, String? activeId,
      List<Conversation> allConversations, int pendingCount) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mensajes',
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
            const Tab(icon: Icon(Icons.people), text: 'Internos'),
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
      int pendingCount) {
    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar: Thread List
          Container(
            width: 320,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
              color: Colors.white,
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Mensajes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_comment_outlined),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const NewChatDialog(),
                          );
                        },
                        tooltip: 'Nuevo Chat',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadConversations,
                        tooltip: 'Recargar',
                      ),
                    ],
                  ),
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
                      const Tab(text: 'Internos'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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

  /// Build simple list for internal chats
  Widget _buildInternalList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    // For internal tab, show filtered internal conversations
    final internalConvs =
        conversations.where((c) => c.type == 'internal').toList();

    if (internalConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'Sin conversaciones internas',
        subtitle: 'Inicia un chat con un compañero',
      );
    }

    return ListView.builder(
      itemCount: internalConvs.length,
      itemBuilder: (context, index) {
        final conv = internalConvs[index];
        return _buildConversationTile(provider, conv, activeId);
      },
    );
  }

  /// Build grouped list for customer chats
  Widget _buildCustomerList(ChatProvider provider, String? activeId,
      List<Conversation> conversations) {
    final customerConvs =
        conversations.where((c) => c.type == 'support').toList();
    final grouped = _groupByStatus(customerConvs);

    if (customerConvs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.support_agent_outlined,
        title: 'Sin solicitudes de clientes',
        subtitle: 'Las solicitudes de soporte aparecerán aquí',
      );
    }

    return ListView(
      children: [
        // Pending Section
        if (grouped['pending']!.isNotEmpty)
          _buildSection(
            icon: Icons.pending_actions,
            title: 'SOLICITUDES',
            count: grouped['pending']!.length,
            color: Colors.orange,
            conversations: grouped['pending']!,
            provider: provider,
            activeId: activeId,
          ),

        // Active Section
        if (grouped['active']!.isNotEmpty)
          _buildSection(
            icon: Icons.chat_bubble,
            title: 'ACTIVOS',
            count: grouped['active']!.length,
            color: Colors.green,
            conversations: grouped['active']!,
            provider: provider,
            activeId: activeId,
          ),

        // Resolved Section
        if (grouped['resolved']!.isNotEmpty)
          _buildSection(
            icon: Icons.check_circle,
            title: 'RESUELTOS',
            count: grouped['resolved']!.length,
            color: Colors.grey,
            conversations: grouped['resolved']!,
            provider: provider,
            activeId: activeId,
          ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: color.withValues(alpha: 0.1),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 1.2,
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
    if (conv.status == 'pending') return '⏳ Esperando respuesta...';
    if (conv.status == 'resolved') return '✅ Resuelto';
    if (conv.contextType == 'job') return '🔧 Servicio técnico';
    if (conv.contextType == 'invoice') return '📄 Factura';
    return conv.type == 'support' ? 'Soporte' : 'Chat interno';
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
