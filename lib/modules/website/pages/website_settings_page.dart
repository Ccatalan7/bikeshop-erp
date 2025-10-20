import 'package:flutter/material.dart';
import '../../../shared/widgets/main_layout.dart';

/// Page for configuring website settings
class WebsiteSettingsPage extends StatelessWidget {
  const WebsiteSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Configuración del Sitio'),
        ),
        body: const Center(
          child: Text('Próximamente: Configuración del Sitio'),
        ),
      ),
    );
  }
}
