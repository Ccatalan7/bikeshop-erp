import 'package:flutter/material.dart';
import 'customer_chat_surface.dart';

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
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomerChatSurface(
                activeContext: widget.activeContext,
                onClose: () => setState(() => _isOpen = false),
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
