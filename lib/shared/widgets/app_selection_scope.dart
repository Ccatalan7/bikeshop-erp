import 'package:flutter/material.dart';

/// Enables selection/copy across the app from a single top-level wrapper.
class AppSelectionScope extends StatelessWidget {
  final Widget child;

  const AppSelectionScope({
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => SelectionArea(child: child),
        ),
      ],
    );
  }
}
