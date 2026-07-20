import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/chat_provider.dart';
import '../models/conversation.dart';

class ChatThreadList extends StatelessWidget {
  final Function(Conversation) onSelected;
  final String? selectedId;

  const ChatThreadList({
    super.key,
    required this.onSelected,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final conversations = provider.conversations;

    if (provider.isLoading && conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (conversations.isEmpty) {
      return const Center(
        child: Text('No hay conversaciones'),
      );
    }

    return ListView.separated(
      itemCount: conversations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final isSelected = conversation.id == selectedId;

        final hasUnread = conversation.unreadCount > 0;

        return Dismissible(
          key: Key(conversation.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            child: const Icon(Icons.archive_outlined, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Archivar conversación'),
                    content: Text(
                      'La conversación con ${provider.getChatTitle(conversation)} pasará al historial. Los mensajes y vínculos se conservarán.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Archivar'),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (direction) async {
            final success = await provider.archiveConversation(conversation.id);
            if (context.mounted && !success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Error al archivar la conversación'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: ListTile(
            selected: isSelected,
            selectedTileColor:
                Theme.of(context).primaryColor.withValues(alpha: 0.1),
            leading: CircleAvatar(
              backgroundColor: _getTypeColor(conversation.type),
              child: Icon(
                _getTypeIcon(conversation.type),
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text(
              provider.getChatTitle(conversation),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: (isSelected || hasUnread)
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    conversation.type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (conversation.lastMessageAt != null)
                  Text(
                    _formatDate(conversation.lastMessageAt!),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
              ],
            ),
            trailing: hasUnread
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      conversation.unreadCount > 99
                          ? '99+'
                          : '${conversation.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
            onTap: () => onSelected(conversation),
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'support':
        return Colors.blue;
      case 'internal':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'support':
        return Icons.support_agent;
      case 'internal':
        return Icons.people;
      default:
        return Icons.chat;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('dd MMM').format(date);
  }
}
