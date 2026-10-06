import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/website_edit_mode_provider.dart';

/// `O-03 VbConfirmDialog` · deleting a page block, from any place that offers
/// it (the contextual dock, the «Secciones» list).
///
/// The safe exit holds the initial focus and the buttons name the act, never
/// Sí/No. The block is captured before the dialog opens and the delete is
/// committed against that capture: if the page changed meanwhile, nothing is
/// deleted. [requiresSelection] is for surfaces that act on the selected block
/// (the dock); a list row acts on its own block, selected or not.
Future<void> confirmWebsiteBlockDeletion(
  BuildContext context, {
  required WebsiteEditModeProvider provider,
  required String blockId,
  bool requiresSelection = true,
}) async {
  final intent = provider.captureAsyncIntent(
    blockId: blockId,
    requiresSelection: requiresSelection,
  );
  if (intent == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Eliminar este bloque?'),
      content: const Text(
        'Se quita de la página. Puedes deshacerlo mientras no guardes.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Conservar bloque'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Eliminar bloque'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final live = context.read<WebsiteEditModeProvider>();
  live.commitAsyncIntent(intent, () {
    final before = live.blocks.length;
    live.deleteBlock(blockId);
    return live.blocks.length < before
        ? WebsiteInlineMutationResult.committed
        : WebsiteInlineMutationResult.unchanged;
  });
}
