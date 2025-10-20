import 'package:flutter/material.dart';
import '../../../shared/widgets/main_layout.dart';

/// Page for managing website content (text blocks, pages, etc.)
class ContentManagementPage extends StatelessWidget {
  const ContentManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Contenido del Sitio'),
        ),
        body: const Center(
          child: Text('Próximamente: Gestión de Contenido'),
        ),
      ),
    );
  }
}
