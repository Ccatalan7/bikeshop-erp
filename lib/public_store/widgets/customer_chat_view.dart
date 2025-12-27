import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/models/message.dart';
import '../../modules/messaging/services/messaging_service.dart';

class CustomerChatView extends StatefulWidget {
  final String conversationId;
  final VoidCallback? onInfoPressed; // For Mobile Context View trigger
  final Function(String invoiceId, String messageId)? onShowQuote;

  const CustomerChatView({
    super.key,
    required this.conversationId,
    this.onInfoPressed,
    this.onShowQuote,
  });

  @override
  State<CustomerChatView> createState() => _CustomerChatViewState();
}

class _CustomerChatViewState extends State<CustomerChatView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MessagingService _messagingService = MessagingService();

  Map<String, dynamic>? _conversation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().setActiveConversation(widget.conversationId);
      _loadConversationDetails();
    });
  }

  @override
  void didUpdateWidget(CustomerChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      context.read<ChatProvider>().setActiveConversation(widget.conversationId);
      _loadConversationDetails();
      // Reset scroll to bottom (0.0 because of reverse: true)
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  Future<void> _loadConversationDetails() async {
    final conversations = await _messagingService.getCustomerConversations();
    final conv = conversations.firstWhere(
      (c) => c['id'] == widget.conversationId,
      orElse: () => <String, dynamic>{},
    );
    if (mounted && conv.isNotEmpty) {
      setState(() => _conversation = conv);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatProvider>().sendMessage(text);
      _messageController.clear();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0, // Scroll to bottom (start of list in reverse mode)
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final isLoading = chatProvider.isLoading;

    final status = _conversation?['status'] ?? 'active';
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';

    return Column(
      children: [
        // Optional Info Button Header (Only visible if handler provided, effectively Mobile)
        if (widget.onInfoPressed != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onInfoPressed,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Ver Detalles'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
              ),
            ),
          ),

        // Status banner
        if (isPending)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              border: Border(
                  bottom: BorderSide(color: Colors.orange.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.orange[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esperando respuesta del equipo...',
                    style: TextStyle(color: Colors.orange[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (isRejected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              border: Border(
                  bottom: BorderSide(color: Colors.red.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.red[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _conversation?['reject_reason'] ??
                        'Esta consulta fue cerrada.',
                    style: TextStyle(color: Colors.red[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        // Messages Area
        Expanded(
          child: Container(
            color: Colors.grey[50],
            child: isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                // Use NotificationListener to suppress OverscrollIndicatorNotification
                // This prevents the scroll event from bubbling up to the parent ScrollView
                // when the list reaches its bounds.
                : NotificationListener<OverscrollIndicatorNotification>(
                    onNotification: (notification) {
                      notification.disallowIndicator();
                      return true; // Stop propagation
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true, // Anchor to bottom, scroll up for older
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      // Allow physics again, but keep primary false
                      primary: false,
                      itemBuilder: (context, index) {
                        // Reverse index since list is reversed
                        final msg = messages[messages.length - 1 - index];
                        return _buildMessageBubble(context, msg);
                      },
                    ),
                  ),
          ),
        ),

        // Input Area
        if (!isRejected)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: isPending
                            ? 'Agregar más información...'
                            : 'Escribe un mensaje...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message msg) {
    final isMe = msg.isMe;

    // Handle action request cards specially
    if (msg.type == 'action_request') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: _buildActionRequestCard(context, msg),
          ),
        ),
      );
    }

    // Simple, clean bubble styling (original design)
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? Colors.black : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(msg.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.black54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build action request card for customer with interactive buttons
  Widget _buildActionRequestCard(BuildContext context, Message msg) {
    final actionType = msg.metadata['action_type'] as String? ?? 'unknown';
    final targetId = msg.metadata['target_id'] as String?;
    final status = msg.metadata['status'] as String? ?? 'pending';
    final amount = msg.metadata['amount'] as num?;

    // Determine card appearance based on action type
    IconData icon;
    String title;
    String buttonLabel;
    Color accentColor;

    switch (actionType) {
      case 'approve_quote':
        icon = Icons.description_outlined;
        if (status == 'accepted') {
          title = 'Presupuesto Aprobado';
          accentColor = Colors.green;
        } else if (status == 'declined') {
          title = 'Presupuesto Rechazado';
          accentColor = Colors.red;
        } else {
          title = 'Presupuesto Pendiente';
          accentColor = Colors.orange;
        }
        buttonLabel = 'Revisar Presupuesto';
        break;
      case 'pay_now':
        icon = Icons.payment;
        title = 'Pago Pendiente';
        buttonLabel = amount != null
            ? 'Pagar \$${amount.toStringAsFixed(0)}'
            : 'Pagar Ahora';
        accentColor = Colors.green;
        break;
      case 'confirm_delivery':
        icon = Icons.local_shipping;
        title = 'Confirmar Entrega';
        buttonLabel = 'Confirmar Recibido';
        accentColor = Colors.blue;
        break;
      default:
        icon = Icons.info_outline;
        title = 'Acción Requerida';
        buttonLabel = 'Ver Detalles';
        accentColor = Colors.grey;
    }

    // Status badge
    Widget statusBadge = const SizedBox.shrink();
    if (status == 'accepted') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 6),
            Text('Aprobado',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    } else if (status == 'declined') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Text('Rechazado',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.red,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: 400, // Fixed reasonable width, not percentage based
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  statusBadge,
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                msg.content,
                style: const TextStyle(
                    color: Colors.black87, fontSize: 13, height: 1.4),
              ),
            ),
            // Buttons (only if pending)
            if (status == 'pending')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min, // shrink to fit
                  children: [
                    TextButton(
                      onPressed: () => _handleActionResponse(
                          context, msg.id, actionType, targetId, 'declined'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Rechazar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: actionType == 'approve_quote'
                          ? () => _handleActionResponse(
                              context, msg.id, actionType, targetId, 'pending')
                          : () => _handleActionResponse(context, msg.id,
                              actionType, targetId, 'accepted'),
                      icon: Icon(
                          actionType == 'pay_now'
                              ? Icons.payment
                              : Icons.visibility_outlined,
                          size: 18),
                      label: Text(buttonLabel),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                DateFormat('HH:mm').format(msg.createdAt),
                style: TextStyle(color: Colors.grey[400], fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle customer response to action request
  Future<void> _handleActionResponse(
    BuildContext context,
    String messageId,
    String actionType,
    String? targetId,
    String response,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      // Update the message metadata with the response
      await supabase.from('messages').update({
        'metadata': {
          'action_type': actionType,
          'target_id': targetId,
          'status': response,
          'responded_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', messageId);

      // If accepted/pending and specific action
      if (targetId != null) {
        if (actionType == 'approve_quote') {
          // Open Sidebar Panel if available, otherwise navigation
          if (widget.onShowQuote != null) {
            widget.onShowQuote!(targetId, messageId);
          } else if (mounted) {
            context.push('/tienda/cuenta/facturas/$targetId');
          }
          return; // Stop here, don't execute below logic
        } else if (response == 'accepted' && actionType == 'pay_now') {
          // Navigate to payment page
          if (mounted)
            context.push('/tienda/cuenta/facturas/$targetId?action=pay');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                response == 'accepted' ? '✅ Acción completada' : 'Rechazado'),
            backgroundColor:
                response == 'accepted' ? Colors.green : Colors.orange,
          ),
        );
        // Refresh messages
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
