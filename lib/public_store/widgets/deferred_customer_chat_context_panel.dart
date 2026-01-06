import 'package:flutter/material.dart';

import 'customer_chat_context_panel.dart' deferred as context_panel;

/// Deferred wrapper for CustomerChatContextPanel to avoid loading heavy
/// BikeshopService and SalesService in the main bundle.
class DeferredCustomerChatContextPanel extends StatefulWidget {
  final String contextType;
  final String contextId;

  const DeferredCustomerChatContextPanel({
    super.key,
    required this.contextType,
    required this.contextId,
  });

  @override
  State<DeferredCustomerChatContextPanel> createState() =>
      _DeferredCustomerChatContextPanelState();
}

class _DeferredCustomerChatContextPanelState
    extends State<DeferredCustomerChatContextPanel> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = context_panel.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _libraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey[200]!)),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Center(
              child: Text(
                'Error cargando panel: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return context_panel.CustomerChatContextPanel(
          contextType: widget.contextType,
          contextId: widget.contextId,
        );
      },
    );
  }
}
