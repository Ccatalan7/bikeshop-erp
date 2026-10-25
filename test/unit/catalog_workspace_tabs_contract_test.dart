import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/catalog/website_catalog_workspace.dart';

/// The editor hosts the store catalog and keeps its tab by name
/// (`_EditorCatalogTab.values.byName`). On 2026-10-24 «Búsquedas» joined
/// `CatalogWorkspaceTab` and not the editor's list: picking it in the editor
/// would have thrown. Every catalog tab has its own in the editor.
void main() {
  test('the editor keeps every tab of the store catalog', () {
    final source = File(
      'lib/public_store/widgets/store_layout/editor_workspace_tabs.dart',
    ).readAsStringSync();
    final body = RegExp(
      r'enum _EditorCatalogTab \{([^}]*)\}',
    ).firstMatch(source)?.group(1);
    expect(body, isNotNull);
    final names = {
      for (final part in body!.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
    expect(names, {for (final tab in CatalogWorkspaceTab.values) tab.name});
  });
}
