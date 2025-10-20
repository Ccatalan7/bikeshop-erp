import 'package:flutter/material.dart';
import '../../../shared/widgets/main_layout.dart';

/// Page for selecting and managing featured products
class FeaturedProductsPage extends StatelessWidget {
  const FeaturedProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Productos Destacados'),
        ),
        body: const Center(
          child: Text('Próximamente: Gestión de Productos Destacados'),
        ),
      ),
    );
  }
}
