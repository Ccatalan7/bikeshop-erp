import 'package:flutter/material.dart';

import '../services/error_reporting_service.dart';

/// A widget that overlays any uncaught error at the top of the app.
class GlobalErrorOverlay extends StatelessWidget {
  final GlobalErrorNotifier notifier;
  const GlobalErrorOverlay({Key? key, required this.notifier})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: notifier,
      builder: (context, _) {
        if (notifier.error == null) return SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            color: Colors.red.shade900.withOpacity(0.95),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GLOBAL ERROR',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(notifier.error!, style: TextStyle(color: Colors.white)),
                  if (notifier.stackTrace != null) ...[
                    const SizedBox(height: 8),
                    Text(notifier.stackTrace!,
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                  Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: notifier.clear,
                      child: Text('Dismiss',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
