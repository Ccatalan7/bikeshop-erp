import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Enables selection/copy across the app from a single top-level wrapper.
class AppSelectionScope extends StatelessWidget {
  final Widget child;

  const AppSelectionScope({
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return child;
    }

    return SelectionArea(child: child);
  }
}
