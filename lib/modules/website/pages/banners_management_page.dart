import 'package:flutter/material.dart';
import '../../../shared/widgets/main_layout.dart';

/// Page for managing website banners (hero images, promotional banners)
class BannersManagementPage extends StatelessWidget {
  const BannersManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Banners del Sitio'),
        ),
        body: const Center(
          child: Text('Próximamente: Gestión de Banners'),
        ),
      ),
    );
  }
}
