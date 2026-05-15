import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/widgets/chat_window.dart';
import '../../modules/messaging/widgets/conversation_tile.dart';
import '../../modules/messaging/widgets/new_chat_dialog.dart';
import '../services/right_toolbar_service.dart';

enum _MessageFilter { all, unread, whatsapp, clients, team }

class QuickMessagesPanel extends StatefulWidget {
  const QuickMessagesPanel({super.key});

  @override
  State<QuickMessagesPanel> createState() => _QuickMessagesPanelState();
}

class _QuickMessagesPanelState extends State<QuickMessagesPanel> {
  final TextEditingController _searchController = TextEditingController();

  _MessageFilter _filter = _MessageFilter.all;
  String _searchTerm = '';
  String? _selectedConversationId;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<ChatProvider>().loadConversations());
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() => _searchTerm = _searchController.text.trim().toLowerCase());
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await context.read<ChatProvider>().loadConversations();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (_) => const NewChatDialog(),
    );
  }

  void _openFullChat([Conversation? conversation]) {
    final route = conversation == null
        ? '/chat'
        : Uri(
            path: '/chat',
            queryParameters: {'conversation': conversation.id},
          ).toString();
    context.read<RightToolbarService>().close();
    context.go(route);
  }

  Conversation? _selectedConversation(List<Conversation> conversations) {
    final selectedId = _selectedConversationId;
    if (selectedId == null) return null;

    for (final conversation in conversations) {
      if (conversation.id == selectedId) {
        return conversation;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final selectedConversation = _selectedConversation(provider.conversations);

    if (selectedConversation != null) {
      return _buildConversationView(selectedConversation);
    }

    return Column(
      children: [
        _buildActionBar(provider),
        _buildSearchField(),
        _buildFilterStrip(provider),
        Expanded(child: _buildConversationList(provider)),
      ],
    );
  }

  Widget _buildConversationView(Conversation conversation) {
    return Column(
      children: [
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: 'Volver a bandeja de entrada',
                onPressed: () {
                  setState(() => _selectedConversationId = null);
                },
              ),
              Expanded(
                child: const Text(
                  'Bandeja de entrada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full, size: 18),
                tooltip: 'Abrir mensajería completa',
                onPressed: () => _openFullChat(conversation),
              ),
            ],
          ),
        ),
        Expanded(
          child: ChatWindow(
            conversation: conversation,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(ChatProvider provider) {
    final conversations = provider.conversations;
    final unread = provider.totalUnreadCount;
    final whatsapp = conversations.where((c) => c.isWhatsApp).length;
    final team = conversations.where((c) => c.isInternal).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  icon: Icons.mark_chat_unread_outlined,
                  label: 'Sin leer',
                  value: unread,
                  alert: unread > 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricChip(
                  icon: Icons.phone_in_talk_outlined,
                  label: 'WhatsApp',
                  value: whatsapp,
                  color: const Color(0xFF047857),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricChip(
                  icon: Icons.groups_outlined,
                  label: 'Equipo',
                  value: team,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showNewChatDialog,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Nuevo'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Recargar',
                onPressed: _isRefreshing ? null : _refresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Abrir mensajería completa',
                onPressed: () => _openFullChat(),
                icon: const Icon(Icons.open_in_full, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required int value,
    Color? color,
    bool alert = false,
  }) {
    final theme = Theme.of(context);
    final baseColor = alert
        ? const Color(0xFFB45309)
        : color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: alert ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: baseColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: baseColor),
              const SizedBox(width: 5),
              Text(
                '$value',
                style: TextStyle(
                  color: baseColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchTerm.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Limpiar búsqueda',
                  onPressed: _searchController.clear,
                ),
          hintText: 'Buscar mensajes...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterStrip(ChatProvider provider) {
    return SizedBox(
      height: 42,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
              _MessageFilter.all, 'Todos', provider.conversations.length),
          _buildFilterChip(
              _MessageFilter.unread, 'Sin leer', provider.totalUnreadCount),
          _buildFilterChip(
            _MessageFilter.whatsapp,
            'WhatsApp',
            provider.conversations.where((c) => c.isWhatsApp).length,
          ),
          _buildFilterChip(
            _MessageFilter.clients,
            'Clientes',
            provider.conversations.where((c) => c.isSupport).length,
          ),
          _buildFilterChip(
            _MessageFilter.team,
            'Equipo',
            provider.conversations.where((c) => c.isInternal).length,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(_MessageFilter filter, String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: _filter == filter,
        label: Text('$label $count'),
        onSelected: (_) => setState(() => _filter = filter),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildConversationList(ChatProvider provider) {
    final conversations = provider.conversations
        .where((conversation) => _matchesFilter(conversation))
        .where((conversation) => _matchesSearch(provider, conversation))
        .toList()
      ..sort(_compareConversations);

    if (conversations.isEmpty) {
      return _buildEmptyState(provider.conversations.isEmpty);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return ConversationTile(
            conversation: conversation,
            isActive: conversation.id == provider.activeConversationId,
            isMobile: false,
            subtitle: _subtitle(conversation),
            onTap: () {
              setState(() => _selectedConversationId = conversation.id);
              context.read<ChatProvider>().setActiveConversation(
                    conversation.id,
                  );
            },
            onDelete: () => _confirmDelete(provider, conversation),
          );
        },
      ),
    );
  }

  bool _matchesFilter(Conversation conversation) {
    return switch (_filter) {
      _MessageFilter.all => true,
      _MessageFilter.unread => conversation.unreadCount > 0 ||
          (conversation.isSupport && conversation.status == 'pending'),
      _MessageFilter.whatsapp => conversation.isWhatsApp,
      _MessageFilter.clients => conversation.isSupport,
      _MessageFilter.team => conversation.isInternal,
    };
  }

  bool _matchesSearch(ChatProvider provider, Conversation conversation) {
    if (_searchTerm.isEmpty) return true;

    final haystack = [
      provider.getChatTitle(conversation),
      conversation.title ?? '',
      conversation.creatorName ?? '',
      conversation.channelLabel,
      _subtitle(conversation),
    ].join(' ').toLowerCase();

    return haystack.contains(_searchTerm);
  }

  int _compareConversations(Conversation a, Conversation b) {
    final unreadCompare = b.unreadCount.compareTo(a.unreadCount);
    if (unreadCompare != 0) return unreadCompare;

    final pendingCompare = _pendingRank(b).compareTo(_pendingRank(a));
    if (pendingCompare != 0) return pendingCompare;

    final aDate = a.lastMessageAt ?? a.updatedAt;
    final bDate = b.lastMessageAt ?? b.updatedAt;
    return bDate.compareTo(aDate);
  }

  int _pendingRank(Conversation conversation) {
    return conversation.isSupport && conversation.status == 'pending' ? 1 : 0;
  }

  String _subtitle(Conversation conversation) {
    final contextLabel = _contextLabel(conversation.contextType);

    if (conversation.isSupport) {
      final statusLabel = switch (conversation.status) {
        'pending' =>
          'Solicitud ${conversation.shortChannelLabel.toLowerCase()} pendiente',
        'resolved' => 'Resuelto',
        _ => conversation.channelLabel,
      };
      return contextLabel == null
          ? statusLabel
          : '$contextLabel · $statusLabel';
    }

    return contextLabel == null ? 'Chat de equipo' : '$contextLabel · Equipo';
  }

  String? _contextLabel(String? contextType) {
    switch (contextType) {
      case 'order':
        return 'Pedido web';
      case 'job':
        return 'Trabajo';
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

  Future<bool> _confirmDelete(
    ChatProvider provider,
    Conversation conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar chat?'),
        content: Text(
          'Estás a punto de eliminar el chat con "${provider.getChatTitle(conversation)}". Esta acción no se puede deshacer.',
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

    if (confirmed != true) return false;

    final success = await provider.deleteConversation(conversation.id);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar la conversación'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return success;
  }

  Widget _buildEmptyState(bool isTotallyEmpty) {
    final theme = Theme.of(context);
    final title = isTotallyEmpty
        ? 'Sin conversaciones'
        : 'No hay mensajes para este filtro';
    final subtitle = isTotallyEmpty
        ? 'Los chats internos, web y WhatsApp aparecerán aquí.'
        : 'Prueba con otro filtro o limpia la búsqueda.';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.chat_bubble_outline,
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
