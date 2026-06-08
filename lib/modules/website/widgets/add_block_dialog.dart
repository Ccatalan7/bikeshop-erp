import 'package:flutter/material.dart';

import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';

/// Canonical block picker. Its contents come from the same registry used by
/// the editor and public renderer, so registered blocks cannot silently vanish
/// from one add-block surface.
class AddBlockDialog extends StatelessWidget {
  const AddBlockDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final definitions = WebsiteBlockRegistry.all()
        .where((definition) => definition.type != WebsiteBlockType.footer)
        .toList(growable: false);

    return AlertDialog(
      title: const Text('Agregar bloque'),
      content: SizedBox(
        width: 440,
        height: 520,
        child: ListView.separated(
          itemCount: definitions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final definition = definitions[index];
            return ListTile(
              leading: Icon(definition.icon),
              title: Text(definition.title),
              subtitle: Text(
                definition.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, definition.type.name),
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
