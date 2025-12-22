import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../messaging/models/conversation.dart';
import '../../messaging/providers/chat_provider.dart';
import '../../messaging/widgets/chat_thread_list.dart';
import '../../messaging/widgets/chat_window.dart';
import '../../messaging/widgets/new_chat_dialog.dart';
import '../../messaging/widgets/context_side_panel.dart';
import '../../messaging/utils/message_parser.dart';

class EmployeeChatPage extends StatefulWidget {
  const EmployeeChatPage({super.key});

  @override
  State<EmployeeChatPage> createState() => _EmployeeChatPageState();
}

class _EmployeeChatPageState extends State<EmployeeChatPage> {
  String _filter = 'all'; // all, internal, support
  ReferenceSegment? _activeReference; // Track selected job/invoice
  bool _isSidePanelExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
    });
  }

  void _loadConversations() {
    final type = _filter == 'all' ? null : _filter;
    context.read<ChatProvider>().loadConversations(type: type);
  }

  void _setFilter(String newFilter) {
    setState(() {
      _filter = newFilter;
    });
    _loadConversations();
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final activeId = provider.activeConversationId;
    final conversations = provider.conversations;

    // Find active conversation object
    Conversation? activeConversation;
    if (activeId != null) {
      try {
        activeConversation = conversations.firstWhere((c) => c.id == activeId);
      } catch (_) {
        // If not in current list (maybe filtered out), clear selection
      }
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Sidebar: Thread List
          Container(
            width: 300,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
              color: Colors.white,
            ),
            child: Column(
              children: [
                // Toolbar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Header
                      Row(
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
                      const SizedBox(height: 12),
                      // Filter Tabs
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'all',
                              label: Text('Todos'),
                              icon: Icon(Icons.list),
                            ),
                            ButtonSegment(
                              value: 'support',
                              label: Text('Soporte'),
                              icon: Icon(Icons.support_agent),
                            ),
                          ],
                          selected: {_filter},
                          onSelectionChanged: (Set<String> newSelection) {
                            _setFilter(newSelection.first);
                          },
                          showSelectedIcon: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List
                Expanded(
                  child: ChatThreadList(
                    selectedId: activeId,
                    onSelected: (conversation) {
                      context
                          .read<ChatProvider>()
                          .setActiveConversation(conversation.id);
                    },
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
                          _isSidePanelExpanded =
                              false; // Reset on new selection
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

          // Right Sidebar: Context Panel
          // Animate panel visibility or just standard retrieval
          if (_activeReference != null)
            if (_isSidePanelExpanded)
              Expanded(
                child: ContextSidePanel(
                  activeReference: _activeReference,
                  onClose: _closeSidePanel,
                  onToggleExpand: _toggleSidePanelExpansion,
                  isExpanded: true,
                ),
              )
            else
              ContextSidePanel(
                activeReference: _activeReference,
                onClose: _closeSidePanel,
                onToggleExpand: _toggleSidePanelExpansion,
                isExpanded: false,
              ),
        ],
      ),
    );
  }
}
