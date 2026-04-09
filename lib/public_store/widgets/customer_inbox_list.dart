import 'package:flutter/material.dart';
import '../../modules/messaging/services/messaging_service.dart';
import 'public_store_layout.dart';

class CustomerInboxList extends StatefulWidget {
  final String? activeConversationId;
  final Function(String)? onConversationSelected;

  const CustomerInboxList({
    super.key,
    this.activeConversationId,
    this.onConversationSelected,
  });

  @override
  State<CustomerInboxList> createState() => _CustomerInboxListState();
}

class _CustomerInboxListState extends State<CustomerInboxList> {
  final MessagingService _messagingService = MessagingService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final conversations = await _messagingService.getCustomerConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 48, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                'No hay conversaciones',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final conv = _conversations[index];
        final isActive = conv['id'] == widget.activeConversationId;

        return _ConversationCard(
          conversation: conv,
          isActive: isActive,
          onTap: () {
            if (widget.onConversationSelected != null) {
              widget.onConversationSelected!(conv['id']);
            } else {
              PublicStoreLayout.navigateToHref(
                context,
                '/tienda/cuenta/chats/${conv['id']}',
              );
            }
          },
        );
      },
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final bool isActive;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = conversation['status'] ?? 'pending';
    final title = conversation['title'] ?? 'Consulta';
    final contextType = conversation['context_type'];
    final messages = conversation['messages'] as List? ?? [];
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final updatedAt = conversation['last_message_at'] != null
        ? DateTime.parse(conversation['last_message_at'])
        : DateTime.now();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? Colors.blue.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? Border.all(color: Colors.blue.withOpacity(0.3))
                : Border.all(color: Colors.transparent),
            boxShadow: isActive
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Icon based on context
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getContextIcon(contextType),
                  color: _getStatusColor(status),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _getContextLabel(contextType) ?? title,
                            style: TextStyle(
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTime(updatedAt),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessage?['content'] ?? 'Nueva conversación',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'active':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getContextIcon(String? contextType) {
    switch (contextType) {
      case 'job':
        return Icons.build_circle_outlined;
      case 'order':
        return Icons.shopping_bag_outlined;
      case 'bike':
        return Icons.pedal_bike;
      case 'invoice':
        return Icons.receipt_long_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  String? _getContextLabel(String? contextType) {
    switch (contextType) {
      case 'job':
        return 'Servicio Técnico';
      case 'order':
        return 'Pedido';
      case 'bike':
        return 'Mi Bicicleta';
      case 'invoice':
        return 'Factura';
      default:
        return null;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${time.day}/${time.month}';
  }
}
