import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms
/// The real static HTML renderer only works on web
class StaticHTMLHomePage extends StatelessWidget {
  final String? tenantSubdomain;

  const StaticHTMLHomePage({
    super.key,
    this.tenantSubdomain,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.web,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'Vista previa no disponible',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'La vista previa del sitio web solo está disponible en la versión web.\nAbre la aplicación en un navegador.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
