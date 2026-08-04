import 'package:flutter/material.dart';

import '../models/website_block_catalog.dart';

/// Canonical block picker for pointer hosts.
///
/// Its contents come from [WebsiteBlockCatalog] — the same owner the editor's
/// insert tab and the compact catalog sheet consume — so a registered family
/// cannot exist on one add-block surface and be missing from another.
///
/// It used to drop the footer silently. It now shows it dimmed with its
/// reason, because a family the operator cannot add still has to explain
/// itself rather than vanish.
class AddBlockDialog extends StatelessWidget {
  const AddBlockDialog({super.key, this.presentBlockTypes = const <String>[]});

  /// `block_type` values already on the page. They only refine the reason a
  /// non-insertable family gives.
  final List<String> presentBlockTypes;

  @override
  Widget build(BuildContext context) {
    final entries = WebsiteBlockCatalog.entries(
      presentBlockTypes: presentBlockTypes,
    );

    return AlertDialog(
      title: const Text('Agregar bloque'),
      content: SizedBox(
        width: 440,
        height: 520,
        child: ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              enabled: entry.isInsertable,
              leading: Icon(entry.icon),
              title: Text(entry.title),
              subtitle: Text(
                entry.isInsertable
                    ? entry.description
                    : entry.unavailableReason ?? entry.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: entry.isInsertable
                  ? () => Navigator.pop(context, entry.type.name)
                  : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
