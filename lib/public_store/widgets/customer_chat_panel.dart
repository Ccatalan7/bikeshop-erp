import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../../modules/messaging/models/message.dart';
import '../services/customer_account_service.dart';

/// Chat panel widget that appears on the customer dashboard
/// Wired to real MessagingService for persistent conversations
class CustomerChatPanel extends StatefulWidget {
  final Map<String, dynamic>? activeContext;
  final bool compactMode;

  const CustomerChatPanel({
    super.key,
    this.activeContext,
    this.compactMode = false,
  });

  @override
  State<CustomerChatPanel> createState() => _CustomerChatPanelState();
}

class _CustomerChatPanelState extends State<CustomerChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MessagingService _messagingService = MessagingService();

  String? _activeConversationId;
  List<Message> _messages = [];
  StreamSubscription? _messagesSubscription;
  bool _isLoading = true;
  bool _isSending = false;
  String? _conversationStatus;
  Map<String, Map<String, dynamic>> _senderCache = {};

  @override
  void initState() {
    super.initState();
    _loadOrCreateConversation();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadOrCreateConversation() async {
    final accountService = context.read<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Try to find existing active/pending conversation
      final conversations = await _messagingService.getCustomerConversations();
      final activeConv = conversations.firstWhere(
        (c) => c['status'] == 'active' || c['status'] == 'pending',
        orElse: () => <String, dynamic>{},
      );

      if (activeConv.isNotEmpty) {
        _activeConversationId = activeConv['id'];
        _conversationStatus = activeConv['status'];
        _subscribeToMessages();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading conversation: $e');
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    if (_activeConversationId == null) return;

    _messagesSubscription?.cancel();
    _messagesSubscription = _messagingService
        .getMessagesStream(_activeConversationId!)
        .listen((messages) {
      if (mounted) {
        setState(() => _messages = messages);
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<Map<String, dynamic>?> _getSenderInfo(String senderId) async {
    if (_senderCache.containsKey(senderId)) {
      return _senderCache[senderId];
    }
    final info = await _messagingService.getSenderInfo(senderId);
    if (info != null) {
      _senderCache[senderId] = info;
    }
    return info;
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;

    final accountService = context.read<CustomerAccountService>();
    if (!accountService.isAuthenticated) {
      _showLoginPrompt();
      return;
    }

    if (accountService.tenantId == null) {
      debugPrint('Error: tenantId is null');
      return;
    }

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      // If no active conversation, create one
      if (_activeConversationId == null) {
        // Auto-attach active job if any
        String? contextType;
        String? contextId;
        final activeServices = accountService.serviceHistory
            .where((s) => !['ENTREGADO', 'CANCELADO'].contains(s['status']))
            .toList();
        if (activeServices.isNotEmpty) {
          contextType = 'job';
          contextId = activeServices.first['id'];
        }

        _activeConversationId = await _messagingService.createChatRequest(
          initialMessage: text,
          contextType: contextType,
          contextId: contextId,
          tenantId: accountService.tenantId!,
        );
        _conversationStatus = 'pending';
        _subscribeToMessages();
      } else {
        // Send to existing conversation
        await _messagingService.sendMessage(
          conversationId: _activeConversationId!,
          content: text,
        );
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showLoginPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inicia sesión para usar el chat'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.compactMode
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : null,
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Status banner
          if (_conversationStatus == 'pending')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.orange.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Esperando respuesta...',
                      style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !accountService.isAuthenticated
                      ? _buildLoginPrompt()
                      : _messages.isEmpty && _activeConversationId == null
                          ? _buildWelcomeState()
                          : _buildMessagesList(),
            ),
          ),

          // Input
          _buildInput(accountService),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    // Show real status based on conversation state
    String statusText;
    Color statusColor;

    if (_conversationStatus == 'pending') {
      statusText = 'Esperando respuesta';
      statusColor = Colors.orange;
    } else if (_conversationStatus == 'active') {
      statusText = 'Conversación activa';
      statusColor = Colors.green;
    } else if (_activeConversationId != null) {
      statusText = 'Conectado';
      statusColor = Colors.green;
    } else {
      statusText = 'Soporte técnico';
      statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: widget.compactMode
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : null,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.black,
            child: Icon(Icons.support_agent, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Soporte Vinabike',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'Inicia sesión para chatear',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.support_agent,
                size: 32,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Escribe tu consulta',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nuestro equipo te responderá pronto',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(14),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(Message msg) {
    final isMe = msg.isMe;

    return FutureBuilder<Map<String, dynamic>?>(
      future: msg.senderId != null
          ? _getSenderInfo(msg.senderId!)
          : Future.value(null),
      builder: (context, snapshot) {
        final senderInfo = snapshot.data;
        final senderName =
            isMe ? null : (senderInfo?['name'] ?? 'Soporte Vinabike');

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe && senderName != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.grey.shade300,
                      child: const Icon(Icons.support_agent,
                          size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      senderName,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: isMe ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(isMe ? 14 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 14),
                  ),
                  border: isMe ? null : Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  msg.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatTime(msg.createdAt),
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInput(CustomerAccountService accountService) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _messageController,
                enabled: accountService.isAuthenticated,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  hintText: accountService.isAuthenticated
                      ? 'Escribe un mensaje...'
                      : 'Inicia sesión para chatear',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color:
                  accountService.isAuthenticated ? Colors.black : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 16),
              onPressed: accountService.isAuthenticated && !_isSending
                  ? () => _sendMessage(_messageController.text)
                  : null,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour =
        time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    return '$hour:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}';
  }
}
