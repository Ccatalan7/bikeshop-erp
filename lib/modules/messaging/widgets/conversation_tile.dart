import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';

class ConversationTile extends StatefulWidget {
  final Conversation conversation;
  final bool isActive;
  final bool isMobile;
  final String subtitle;
  final VoidCallback onTap;
  final Future<bool> Function() onDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.isMobile,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  bool _isHovering = false;

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inDays == 0 && now.day == local.day) {
      return DateFormat.Hm().format(local);
    } else if (diff.inDays < 7) {
      return DateFormat.E().format(local);
    } else {
      return DateFormat.Md().format(local);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final conv = widget.conversation;
    final isPending = conv.status == 'pending';
    final hasUnread = conv.unreadCount > 0;
    final channelIcon = conv.isWhatsApp
        ? Icons.phone_in_talk_outlined
        : conv.isWebsitePortal
            ? Icons.language_outlined
            : Icons.people_outline;
    final channelColor = isPending
        ? Colors.orange[700]
        : conv.isWhatsApp
            ? const Color(0xFF047857)
            : conv.isWebsitePortal
                ? const Color(0xFF093357)
                : Colors.grey[600];

    Widget content = ListTile(
      selected: widget.isActive,
      selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      onTap: widget.onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: isPending ? Colors.orange[100] : Colors.grey[200],
            child: Icon(
              channelIcon,
              color: channelColor,
              size: 20,
            ),
          ),
          if (hasUnread)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  '${conv.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        provider.getChatTitle(conv),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        widget.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPending ? Colors.orange[700] : Colors.grey[600],
          fontSize: 12,
          fontWeight: isPending ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: _buildTrailing(conv, hasUnread, context),
    );

    if (widget.isMobile) {
      return Dismissible(
        key: Key(conv.id),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) => widget.onDelete(),
        child: content,
      );
    } else {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: content,
      );
    }
  }

  Widget _buildTrailing(
      Conversation conv, bool hasUnread, BuildContext context) {
    if (!widget.isMobile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(conv.lastMessageAt ?? conv.updatedAt),
            style: TextStyle(
              fontSize: 11,
              color:
                  hasUnread ? Theme.of(context).primaryColor : Colors.grey[400],
              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          // Animated slider for dropdown
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: _isHovering ? 32.0 : 0.0,
            child: ClipRect(
              child: OverflowBox(
                minWidth: 0,
                maxWidth: 32.0,
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isHovering ? 1.0 : 0.0,
                  curve: Curves.easeOut,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      tooltip: 'Opciones',
                      icon: Icon(Icons.keyboard_arrow_down,
                          size: 20, color: Colors.grey[600]),
                      splashRadius: 16,
                      onSelected: (value) {
                        if (value == 'delete') {
                          Future.delayed(const Duration(milliseconds: 100),
                              widget.onDelete);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  color: Colors.red, size: 20),
                              SizedBox(width: 12),
                              Text('Eliminar chat',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Mobile: Just timestamp
    return Text(
      _formatTime(conv.lastMessageAt ?? conv.updatedAt),
      style: TextStyle(
        fontSize: 11,
        color: hasUnread ? Theme.of(context).primaryColor : Colors.grey[400],
        fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
