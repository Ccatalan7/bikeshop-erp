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

        return ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
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
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
          onTap: () => onSelected(conversation),
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
