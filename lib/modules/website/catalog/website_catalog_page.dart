import 'package:flutter/material.dart';

import '../widgets/website_admin_ui.dart';
import 'website_catalog_workspace.dart';

/// The store catalog as an ERP page (`/website/product-visibility`).
///
/// Apart from [WebsiteCatalogWorkspace] on purpose: the admin shell brings the
/// whole ERP layout (messaging, notifications, mail), and the store bundle,
/// whose site editor embeds the workspace, must not carry it. With the shell
/// in the workspace the editor's deferred chunk grew from 1.41 to 2.09 MB and
/// the store stopped publishing (2026-10-10).
class WebsiteCatalogPage extends StatelessWidget {
  const WebsiteCatalogPage({
    super.key,
    this.initialTab = CatalogWorkspaceTab.products,
  });

  final CatalogWorkspaceTab initialTab;

  @override
  Widget build(BuildContext context) => WebsiteAdminShell(
        title: 'Catálogo de la tienda',
        description: 'Qué se vende en vinabike.cl, por qué lo demás no, y '
            'cómo se ve en la página real.',
        child: WebsiteCatalogWorkspace(initialTab: initialTab),
      );
}
