import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/messaging_service.dart';
import '../models/conversation.dart';
import '../widgets/chat_window.dart';

/// A collapsible chat sidebar for embedding in detail pages (Job, Invoice, etc.)
/// Shows conversations linked to a specific entity and allows creating new ones.
class EntityChatSidebar extends StatefulWidget {
  final String entityType; // 'job', 'invoice', etc.
  final String entityId;
  final String entityTitle; // For display, e.g., "Trabajo #123"

  const EntityChatSidebar({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.entityTitle,
  });

  @override
  State<EntityChatSidebar> createState() => _EntityChatSidebarState();
}

class _EntityChatSidebarState extends State<EntityChatSidebar> {
  List<Conversation> _conversations = [];
  Conversation? _activeConversation;
  bool _isLoading = true;
  bool _isExpanded = false; // Collapsed by default
  RealtimeChannel? _realtimeChannel;

  void _safeSetState(VoidCallback update) {
    if (!mounted) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(update);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(update);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Defer provider access to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
      _subscribeToUpdates();
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToUpdates() {
    if (!mounted) return;
    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);
      _realtimeChannel = messagingService.subscribeToConversationsUpdates(() {
        if (mounted) _loadConversations();
      });
    } catch (e) {
      debugPrint('MessagingService not available: $e');
    }
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);

      // Get all conversations and filter by context
      final allConversations = await messagingService.getConversations();
      debugPrint(
          '🔍 EntityChatSidebar: Found ${allConversations.length} total conversations');
      debugPrint(
          '🔍 Looking for: entityType=${widget.entityType}, entityId=${widget.entityId}');
      debugPrint('🔍 Entity title: ${widget.entityTitle}');

      // Primary filter: exact context match
      var filtered = allConversations.where((c) {
        return c.contextType == widget.entityType &&
            c.contextId == widget.entityId;
      }).toList();
      debugPrint('🔍 Context-linked matches: ${filtered.length}');

      // Fallback: if no context-linked chats, search by entity identifier in title
      // Extract identifier from entityTitle (e.g., "Trabajo #PG-00105" -> "PG-00105")
      if (filtered.isEmpty) {
        final identifierMatch =
            RegExp(r'#?(PG-\d+|FV-\d+|INV-\d+)').firstMatch(widget.entityTitle);
        debugPrint('🔍 Fallback regex match: ${identifierMatch?.group(0)}');
        if (identifierMatch != null) {
          final identifier =
              identifierMatch.group(0)?.replaceFirst('#', '') ?? '';
          debugPrint('🔍 Searching for identifier: $identifier');

          // Log all conversation titles for debugging
          for (final c in allConversations) {
            debugPrint(
                '   📝 Conv title: "${c.title}" | context: ${c.contextType}/${c.contextId}');
          }

          filtered = allConversations.where((c) {
            final title = c.title?.toLowerCase() ?? '';
            return title.contains(identifier.toLowerCase());
          }).toList();
          debugPrint('🔍 Title-matched: ${filtered.length}');
        }
      }

      if (mounted) {
        _safeSetState(() {
          _conversations = filtered;
          _isLoading = false;
          // Auto-select if only one conversation
          if (filtered.length == 1 && _activeConversation == null) {
            _activeConversation = filtered.first;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading entity conversations: $e');
      if (mounted) {
        _safeSetState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startNewChat() async {
    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);

      // Create a support ticket linked to this entity
      final newConvId = await messagingService.createSupportTicket(
        title: 'Chat: ${widget.entityTitle}',
        contextType: widget.entityType,
        contextId: widget.entityId,
      );

      if (mounted) {
        // Reload conversations to get the new one as a Conversation object
        await _loadConversations();
        // Find and select the newly created conversation
        final newConv = _conversations.firstWhere(
          (c) => c.id == newConvId,
          orElse: () => _conversations.first,
        );
        _safeSetState(() {
          _activeConversation = newConv;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: _isExpanded ? 380 : 48,
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: _isExpanded
            ? _buildExpandedContent(theme)
            : _buildCollapsedBar(theme),
      ),
    );
  }

  Widget _buildCollapsedBar(ThemeData theme) {
    return InkWell(
      onTap: () => _safeSetState(() => _isExpanded = true),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.chat_bubble_outline, size: 24),
          const SizedBox(height: 8),
          RotatedBox(
            quarterTurns: 3,
            child: Text(
              'Chat',
              style: theme.textTheme.labelMedium,
            ),
          ),
          if (_conversations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${_conversations.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chat: ${widget.entityTitle}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: () => _safeSetState(() => _isExpanded = false),
                tooltip: 'Colapsar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _activeConversation != null
                  ? _buildChatView()
                  : _buildConversationList(theme),
        ),
      ],
    );
  }

  Widget _buildConversationList(ThemeData theme) {
    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_outlined,
                  size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'No hay conversaciones',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _startNewChat,
                icon: const Icon(Icons.add),
                label: const Text('Iniciar Chat'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _conversations.length,
            itemBuilder: (context, index) {
              final conv = _conversations[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.chat,
                      size: 18, color: theme.colorScheme.primary),
                ),
                title: Text(
                  conv.title ?? 'Sin título',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  conv.type == 'support' ? 'Soporte' : 'Interno',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: conv.unreadCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${conv.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      )
                    : null,
                onTap: () => _safeSetState(() => _activeConversation = conv),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            onPressed: _startNewChat,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva Conversación'),
          ),
        ),
      ],
    );
  }

  Widget _buildChatView() {
    final activeConv = _activeConversation;
    if (activeConv == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Back button when viewing a chat
        if (_conversations.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      _safeSetState(() => _activeConversation = null),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Lista'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const Spacer(),
                Text(
                  activeConv.title ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        // Chat window
        Expanded(
          child: ChatWindow(
            conversation: activeConv,
          ),
        ),
      ],
    );
  }
}
