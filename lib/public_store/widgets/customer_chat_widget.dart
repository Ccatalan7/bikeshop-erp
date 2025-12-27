import 'package:flutter/material.dart';
import '../theme/public_store_theme.dart';
import 'customer_chat_panel.dart';

class CustomerChatWidget extends StatefulWidget {
  final bool showContextPanel; // Whether to show side panel (desktop only?)
  final Map<String, dynamic>?
      activeContext; // e.g., {'type': 'service', 'id': '123'}

  const CustomerChatWidget({
    super.key,
    this.showContextPanel = false,
    this.activeContext,
  });

  @override
  State<CustomerChatWidget> createState() => _CustomerChatWidgetState();
}

class _CustomerChatWidgetState extends State<CustomerChatWidget> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chat WindowOverlay
          if (_isOpen)
            Container(
              width: 350,
              height: 500,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Header handled by Panel or Custom here?
                  // Let's add a custom header for the overlay with Close button
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      border: Border(bottom: BorderSide(color: Colors.grey)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.support_agent,
                              size: 18, color: Colors.black),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Soporte Vinabike',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 20),
                          onPressed: () => setState(() => _isOpen = false),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CustomerChatPanel(
                      activeContext: widget.activeContext,
                      compactMode: false,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Toggle Button
          FloatingActionButton(
            heroTag: 'customer_chat_fab',
            onPressed: () => setState(() => _isOpen = !_isOpen),
            backgroundColor: Colors.black, // Vinabike Black
            child: Icon(
              _isOpen ? Icons.close : Icons.chat,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
