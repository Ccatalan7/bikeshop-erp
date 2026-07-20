import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/messaging_service.dart';
import '../models/conversation.dart';
import '../widgets/chat_window.dart';

enum _EntityChatStartChannel { website, whatsapp }

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
  static const double _collapsedWidth = 48;
  static const double _defaultExpandedWidth = 380;
  static const double _minExpandedWidth = 320;
  static const double _maxExpandedWidth = 640;
  static const String _widthPreferenceKey = 'entity_chat_sidebar_width';

  List<Conversation> _conversations = [];
  Conversation? _activeConversation;
  bool _isLoading = true;
  bool _isExpanded = false; // Collapsed by default
  bool _isResizing = false;
  bool _isCreatingChat = false;
  bool _isChoosingChannel = false;
  final Set<String> _deletingConversationIds = {};
  double _expandedWidth = _defaultExpandedWidth;
  RealtimeChannel? _realtimeChannel;

  int get _unreadCount =>
      _conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  void _safeSetState(VoidCallback update) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(update);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSavedWidth();
    // Defer provider access to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConversations();
      _subscribeToUpdates();
    });
  }

  Future<void> _loadSavedWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble(_widthPreferenceKey);
      if (savedWidth == null || !mounted) return;
      setState(() {
        _expandedWidth =
            savedWidth.clamp(_minExpandedWidth, _maxExpandedWidth).toDouble();
      });
    } catch (e) {
      debugPrint('Could not load entity chat sidebar width: $e');
    }
  }

  Future<void> _saveWidthPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_widthPreferenceKey, _expandedWidth);
    } catch (e) {
      debugPrint('Could not save entity chat sidebar width: $e');
    }
  }

  void _setExpandedWidth(double width) {
    final nextWidth =
        width.clamp(_minExpandedWidth, _maxExpandedWidth).toDouble();
    if ((_expandedWidth - nextWidth).abs() < 0.5) return;
    setState(() => _expandedWidth = nextWidth);
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
      final linkedConversationIds =
          await messagingService.getConversationIdsForContext(
        contextType: widget.entityType,
        contextId: widget.entityId,
      );
      final allConversations = await messagingService.getConversations();
      debugPrint(
          '🔍 EntityChatSidebar: Found ${allConversations.length} total conversations');
      debugPrint(
          '🔍 Looking for: entityType=${widget.entityType}, entityId=${widget.entityId}');
      debugPrint('🔍 Entity title: ${widget.entityTitle}');
      debugPrint('🔍 Context table matches: ${linkedConversationIds.length}');

      // Primary filter: exact context match
      var filtered = allConversations.where((c) {
        return linkedConversationIds.contains(c.id) ||
            (c.contextType == widget.entityType &&
                c.contextId == widget.entityId);
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
          if (_activeConversation != null &&
              !filtered.any((item) => item.id == _activeConversation!.id)) {
            _activeConversation = null;
          }
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

  Future<void> _startNewChat(_EntityChatStartChannel selectedChannel) async {
    setState(() => _isCreatingChat = true);

    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);

      final newConvId = switch (selectedChannel) {
        _EntityChatStartChannel.website =>
          await messagingService.createSupportTicket(
            title: 'Chat: ${widget.entityTitle}',
            contextType: widget.entityType,
            contextId: widget.entityId,
          ),
        _EntityChatStartChannel.whatsapp =>
          await _openWhatsAppConversation(messagingService),
      };

      if (mounted) {
        // Reload conversations to get the new one as a Conversation object
        await _loadConversations();
        // Find and select the newly created conversation
        final matching = _conversations.where((c) => c.id == newConvId);
        if (matching.isNotEmpty) {
          _safeSetState(() {
            _activeConversation = matching.first;
            _isChoosingChannel = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creando chat: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingChat = false);
    }
  }

  Widget _buildStartChatOption({
    required ThemeData theme,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStartChatPanel(
    ThemeData theme, {
    bool showCancel = false,
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Iniciar conversación',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (showCancel)
                IconButton(
                  tooltip: 'Cerrar opciones',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _isCreatingChat
                      ? null
                      : () => setState(() => _isChoosingChannel = false),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              'Elige el canal para este registro.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildStartChatOption(
            theme: theme,
            icon: Icons.language_outlined,
            color: const Color(0xFF2563EB),
            title: 'Chat web',
            subtitle: 'Conversación del portal web vinculada a este registro.',
            onTap: _isCreatingChat
                ? () {}
                : () => _startNewChat(_EntityChatStartChannel.website),
          ),
          const SizedBox(height: 8),
          _buildStartChatOption(
            theme: theme,
            icon: Icons.phone_in_talk_outlined,
            color: const Color(0xFF128C7E),
            title: 'Chat WhatsApp',
            subtitle:
                'Usa el teléfono del cliente y abre el hilo WhatsApp del ERP.',
            onTap: _isCreatingChat
                ? () {}
                : () => _startNewChat(_EntityChatStartChannel.whatsapp),
          ),
          if (_isCreatingChat) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Future<String> _openWhatsAppConversation(
    MessagingService messagingService,
  ) async {
    final contact = await messagingService.getSupportContextContact(
      contextType: widget.entityType,
      contextId: widget.entityId,
    );

    final phone = contact?['phone']?.toString();
    if (phone == null || phone.trim().isEmpty) {
      throw Exception('El cliente no tiene teléfono configurado.');
    }

    return messagingService.openWhatsAppSupportConversation(
      phoneNumber: phone,
      contactName: contact?['name']?.toString() ?? widget.entityTitle,
      customerId: contact?['customer_id']?.toString(),
      contextType: widget.entityType,
      contextId: widget.entityId,
    );
  }

  Future<void> _confirmArchiveConversation(Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Archivar chat'),
          content: Text(
            'La conversación "${conversation.title ?? conversation.channelLabel}" pasará al historial. Sus mensajes y vínculos se conservarán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('Archivar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _archiveConversation(conversation);
  }

  Future<void> _archiveConversation(Conversation conversation) async {
    setState(() => _deletingConversationIds.add(conversation.id));
    try {
      final messagingService =
          Provider.of<MessagingService>(context, listen: false);
      await messagingService.archiveConversation(conversation.id);
      if (!mounted) return;

      _safeSetState(() {
        _conversations.removeWhere((item) => item.id == conversation.id);
        if (_activeConversation?.id == conversation.id) {
          _activeConversation =
              _conversations.length == 1 ? _conversations.first : null;
        }
      });
      await _loadConversations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat eliminado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando chat: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingConversationIds.remove(conversation.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: _isResizing || kDebugMode
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: _isExpanded ? _expandedWidth : _collapsedWidth,
      child: Stack(
        children: [
          Positioned.fill(
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
          ),
          if (_isExpanded) _buildResizeHandle(theme),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(ThemeData theme) {
    final handleColor = _isResizing
        ? theme.colorScheme.primary.withValues(alpha: 0.35)
        : theme.dividerColor.withValues(alpha: 0.65);

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 10,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => setState(() => _isResizing = true),
          onHorizontalDragUpdate: (details) {
            _setExpandedWidth(_expandedWidth - details.delta.dx);
          },
          onHorizontalDragEnd: (_) {
            setState(() => _isResizing = false);
            _saveWidthPreference();
          },
          onHorizontalDragCancel: () {
            setState(() => _isResizing = false);
            _saveWidthPreference();
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedBar(ThemeData theme) {
    final unreadCount = _unreadCount;
    final badgeCount = unreadCount > 0 ? unreadCount : _conversations.length;
    final badgeColor = unreadCount > 0
        ? const Color(0xFF16A34A)
        : theme.colorScheme.onSurfaceVariant;

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
          if (badgeCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: unreadCount > 0
                    ? [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
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
          padding: const EdgeInsets.all(18),
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
              _buildStartChatPanel(theme),
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
              final isDeleting = _deletingConversationIds.contains(conv.id);
              final hasUnread = conv.unreadCount > 0;
              return ListTile(
                tileColor: hasUnread
                    ? const Color(0xFF16A34A).withValues(alpha: 0.07)
                    : null,
                leading: CircleAvatar(
                  backgroundColor: hasUnread
                      ? const Color(0xFF16A34A).withValues(alpha: 0.14)
                      : theme.colorScheme.primaryContainer,
                  child: Icon(_channelIcon(conv),
                      size: 18,
                      color: hasUnread
                          ? const Color(0xFF16A34A)
                          : theme.colorScheme.primary),
                ),
                title: Text(
                  conv.title ?? 'Sin título',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  conv.channelLabel,
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (conv.unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 2),
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF16A34A),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${conv.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Archivar chat',
                      visualDensity: VisualDensity.compact,
                      icon: isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.archive_outlined, size: 18),
                      onPressed: isDeleting
                          ? null
                          : () => _confirmArchiveConversation(conv),
                    ),
                  ],
                ),
                onTap: () => _safeSetState(() {
                  final opened = _copyConversationWithUnread(conv, 0);
                  _conversations[index] = opened;
                  _activeConversation = opened;
                }),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: _isChoosingChannel
              ? _buildStartChatPanel(theme, showCancel: true, compact: true)
              : TextButton.icon(
                  onPressed: _isCreatingChat
                      ? null
                      : () => setState(() => _isChoosingChannel = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    _isCreatingChat ? 'Creando...' : 'Nueva conversación',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildChatView() {
    final activeConv = _activeConversation;
    if (activeConv == null) return const SizedBox.shrink();
    final isDeleting = _deletingConversationIds.contains(activeConv.id);

    return Column(
      children: [
        Expanded(
          child: ChatWindow(
            conversation: activeConv,
            headerActions: [
              if (_conversations.length > 1)
                IconButton(
                  tooltip: 'Volver a la lista',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: () =>
                      _safeSetState(() => _activeConversation = null),
                ),
              IconButton(
                tooltip: 'Archivar chat',
                visualDensity: VisualDensity.compact,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.archive_outlined, size: 18),
                onPressed: isDeleting
                    ? null
                    : () => _confirmArchiveConversation(activeConv),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _channelIcon(Conversation conversation) {
    if (conversation.isWhatsApp) return Icons.phone_in_talk_outlined;
    if (conversation.isWebsitePortal) return Icons.language_outlined;
    return Icons.chat_bubble_outline;
  }

  Conversation _copyConversationWithUnread(
    Conversation conversation,
    int unreadCount,
  ) {
    return Conversation(
      id: conversation.id,
      type: conversation.type,
      channel: conversation.channel,
      isGroup: conversation.isGroup,
      counterpartyType: conversation.counterpartyType,
      status: conversation.status,
      title: conversation.title,
      contextType: conversation.contextType,
      contextId: conversation.contextId,
      updatedAt: conversation.updatedAt,
      lastMessageAt: conversation.lastMessageAt,
      staffLastReadAt: conversation.staffLastReadAt,
      staffLastReadMessageSequence: conversation.staffLastReadMessageSequence,
      lastMessageId: conversation.lastMessageId,
      lastMessageSequence: conversation.lastMessageSequence,
      lastMessageContent: conversation.lastMessageContent,
      lastMessageType: conversation.lastMessageType,
      lastMessageMetadata: conversation.lastMessageMetadata,
      lastMessageIsMine: conversation.lastMessageIsMine,
      lastMessageDirection: conversation.lastMessageDirection,
      lastMessageExternalStatus: conversation.lastMessageExternalStatus,
      unreadCount: unreadCount,
      participantIds: conversation.participantIds,
      createdBy: conversation.createdBy,
      creatorName: conversation.creatorName,
      contextHint: conversation.contextHint,
    );
  }
}
