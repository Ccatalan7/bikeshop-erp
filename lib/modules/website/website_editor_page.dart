import 'package:flutter/material.dart';
import 'pages/odoo_style_editor_page.dart';

/// Website Editor - Block-based visual editor inspired by Odoo
/// 
/// Simple flow:
/// 1. Open editor
/// 2. Click blocks to edit them directly
/// 3. Use 3-tab panel: Agregar (Add) | Editar (Edit) | Tema (Theme)
/// 4. Click Save to publish changes
class WebsiteEditorPage extends StatelessWidget {
  const WebsiteEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OdooStyleEditorPage();
  }
}
