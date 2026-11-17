import 'package:flutter/material.dart';

/// «Foto de la página»: a page's own photo (`website_pages.og_image_url`). A
/// shared link shows it and, on a guide, so do its rows in /guias and in
/// «Sigue leyendo» (the HTML store, 2026-11-17). The page dialog picks it with
/// the site's image picker, as every image of the editor is chosen, and
/// removes it with «Quitar».
class WebsitePageImageField extends StatelessWidget {
  const WebsitePageImageField({
    super.key,
    required this.url,
    required this.isGuide,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String url;
  final bool isGuide;

  /// False while the page saves.
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasImage = url.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('website_page_image_preview'),
          width: 96,
          height: 80,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(6),
          child: hasImage
              ? Image.network(
                  url,
                  fit: BoxFit.contain,
                  semanticLabel: 'Foto de la página',
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Foto de la página', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                isGuide
                    ? 'Va junto al título de la guía en /guias y en «Sigue '
                        'leyendo», y al compartir el enlace.'
                    : 'Se ve al compartir el enlace de la página.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('website_page_image_pick'),
                    onPressed: enabled ? onPick : null,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(hasImage ? 'Cambiar foto' : 'Elegir foto'),
                  ),
                  if (hasImage)
                    TextButton.icon(
                      key: const ValueKey('website_page_image_clear'),
                      onPressed: enabled ? onClear : null,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Quitar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
