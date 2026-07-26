import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';

/// Recomposition boundary for the customer logbook.
///
/// Desktop keeps the operational identity rail beside the active workspace.
/// Phone and tablet replace that rail with a compact disclosure above the same
/// canonical tab content, so the workspace receives the full available width.
class ClientLogbookResponsiveFrame extends StatelessWidget {
  const ClientLogbookResponsiveFrame({
    super.key,
    required this.desktopIdentity,
    required this.compactIdentity,
    required this.content,
  });

  final Widget desktopIdentity;
  final Widget compactIdentity;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    if (ResponsiveViewport.usesCompactShell(context)) {
      return Column(
        key: const ValueKey('client-logbook-compact-frame'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          compactIdentity,
          Expanded(child: content),
        ],
      );
    }

    return Row(
      key: const ValueKey('client-logbook-desktop-frame'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 256,
          child: desktopIdentity,
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: content),
      ],
    );
  }
}
