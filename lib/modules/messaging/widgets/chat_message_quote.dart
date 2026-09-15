import 'package:flutter/material.dart';

/// A content reference, not an E-04 status notice. Both composer and timeline
/// share this anatomy. Geometry: GUÍA GENERAL F-04 (8 padding/field radius,
/// 3 reference rail); typography and colours come from the application theme.
class ChatMessageQuote extends StatelessWidget {
  const ChatMessageQuote(
      {super.key, required this.author, required this.preview, this.onCancel});

  final String author;
  final String preview;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Semantics(
          label: onCancel == null
              ? 'Respuesta a $author: $preview'
              : '$author: $preview',
          excludeSemantics: true,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w600)),
                Text(preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
        )),
        if (onCancel != null)
          IconButton(
              tooltip: 'Cancelar respuesta',
              onPressed: onCancel,
              icon: const Icon(Icons.close)),
      ]),
    );
  }
}
