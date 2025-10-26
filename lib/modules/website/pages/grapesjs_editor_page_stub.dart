import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms
/// The real GrapesJS editor only works on web
class GrapesJSEditorPage extends StatelessWidget {
  final String? initialHtml;
  final String? initialCss;
  final String? pageId;

  const GrapesJSEditorPage({
    super.key,
    this.initialHtml,
    this.initialCss,
    this.pageId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website Editor'),
        backgroundColor: const Color(0xFF2d2d2d),
        foregroundColor: Colors.white,
      ),
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
                'Editor web no disponible',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'El editor de sitio web solo está disponible en la versión web.\nAbre la aplicación en un navegador para editar tu sitio.',
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
