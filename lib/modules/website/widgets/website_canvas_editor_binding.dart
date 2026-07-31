import 'package:flutter/material.dart';

/// Edit-only commands and transient selection for one Canvas content tree.
///
/// The persisted Canvas payload never owns [activeElementId]. Public and
/// Preview omit this binding, while Edit passes it through the same deferred
/// content renderer used by visitors.
class WebsiteCanvasEditorBinding {
  const WebsiteCanvasEditorBinding({
    required this.activeElementId,
    required this.onElementsChanged,
    required this.onActiveElementChanged,
    this.onCanvasSizeChanged,
    this.onBackgroundTap,
  });

  final String? activeElementId;
  final ValueChanged<List<Map<String, dynamic>>> onElementsChanged;
  final ValueChanged<String?> onActiveElementChanged;
  final ValueChanged<Size>? onCanvasSizeChanged;
  final VoidCallback? onBackgroundTap;
}
