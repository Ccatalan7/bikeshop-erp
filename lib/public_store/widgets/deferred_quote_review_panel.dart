import 'package:flutter/material.dart';

import 'quote_review_panel.dart' deferred as quote_panel;

/// Deferred wrapper for QuoteReviewPanel to avoid loading heavy
/// SalesService in the main bundle.
class DeferredQuoteReviewPanel extends StatefulWidget {
  final String invoiceId;
  final String? messageId;
  final VoidCallback onClose;
  final Function(String message)? onRequestChanges;
  final VoidCallback? onApprove;

  const DeferredQuoteReviewPanel({
    super.key,
    required this.invoiceId,
    this.messageId,
    required this.onClose,
    this.onRequestChanges,
    this.onApprove,
  });

  @override
  State<DeferredQuoteReviewPanel> createState() =>
      _DeferredQuoteReviewPanelState();
}

class _DeferredQuoteReviewPanelState extends State<DeferredQuoteReviewPanel> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = quote_panel.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _libraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return quote_panel.QuoteReviewPanel(
          invoiceId: widget.invoiceId,
          messageId: widget.messageId,
          onClose: widget.onClose,
          onRequestChanges: widget.onRequestChanges,
          onApprove: widget.onApprove,
        );
      },
    );
  }
}
