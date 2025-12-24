import 'package:flutter/material.dart';

class CustomerChatPanel extends StatefulWidget {
  final Map<String, dynamic>? activeContext;
  final bool compactMode;

  const CustomerChatPanel(
      {super.key, this.activeContext, this.compactMode = false});

  @override
  State<CustomerChatPanel> createState() => _CustomerChatPanelState();
}

class _CustomerChatPanelState extends State<CustomerChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'id': '1',
      'content': '¡Hola! Bienvenido a Vinabike. ¿En qué podemos ayudarte hoy?',
      'sender': 'agent',
      'senderName': 'Soporte Vinabike',
      'time': DateTime.now().subtract(const Duration(minutes: 30)),
    },
  ];

  @override
  Widget build(BuildContext context) {
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
          Container(
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
                Stack(
                  children: [
                    CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black,
                        child: const Icon(Icons.support_agent,
                            size: 18, color: Colors.white)),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5)))),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chat Taller',
                          style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Row(
                        children: [
                          Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                  color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('En línea',
                              style: TextStyle(
                                  color: Colors.green.shade700, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, color: Colors.grey[400], size: 18),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isMe = msg['sender'] == 'me';
                  final time = msg['time'] as DateTime;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (!isMe) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.grey.shade300,
                                  child: const Icon(Icons.person,
                                      size: 12, color: Colors.white)),
                              const SizedBox(width: 6),
                              Text(msg['senderName'] ?? 'Agente',
                                  style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 240),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isMe ? 14 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 14),
                            ),
                            border: isMe
                                ? null
                                : Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(msg['content'],
                              style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontSize: 13)),
                        ),
                        const SizedBox(height: 3),
                        Text(_formatTime(time),
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 10)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20)),
                    child: TextField(
                      controller: _messageController,
                      style:
                          const TextStyle(color: Colors.black87, fontSize: 13),
                      decoration: InputDecoration(
                          hintText: 'Escribe un mensaje...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10)),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  decoration: const BoxDecoration(
                      color: Colors.black, shape: BoxShape.circle),
                  child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 16),
                      onPressed: () => _sendMessage(_messageController.text),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints()),
                ),
              ],
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

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        'id': DateTime.now().toString(),
        'content': text,
        'sender': 'me',
        'time': DateTime.now()
      });
      _messageController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients)
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _messages.add({
              'id': DateTime.now().toString(),
              'content':
                  'Gracias por tu mensaje. Un mecánico te responderá pronto.',
              'sender': 'agent',
              'senderName': 'Soporte Vinabike',
              'time': DateTime.now()
            }));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients)
            _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut);
        });
      }
    });
  }
}
