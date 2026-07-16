import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/appearance_service.dart';
import '../../../shared/services/image_service.dart';

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Apariencia'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Mode Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Tema de la Aplicación',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecciona el tema visual del sistema',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 24),
                  Consumer<AppearanceService>(
                    builder: (context, appearanceService, _) {
                      return SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Claro'),
                            icon: Icon(Icons.light_mode),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Oscuro'),
                            icon: Icon(Icons.dark_mode),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Sistema'),
                            icon: Icon(Icons.settings_brightness),
                          ),
                        ],
                        selected: {appearanceService.themeMode},
                        onSelectionChanged: (Set<ThemeMode> newSelection) {
                          appearanceService.setThemeMode(newSelection.first);
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Company Logo Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Logo de la Empresa',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sube el logo de tu empresa que aparecerá en el encabezado del sistema',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Current Logo Preview
                  Consumer<AppearanceService>(
                    builder: (context, appearanceService, _) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              appearanceService.hasCustomLogo
                                  ? 'Logo Actual'
                                  : 'Sin Logo Personalizado',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 16),
                            if (appearanceService.hasCustomLogo)
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 120,
                                  maxWidth: 300,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(12),
                                child: CachedNetworkImage(
                                  imageUrl: appearanceService.companyLogoUrl!,
                                  fit: BoxFit.contain,
                                  imageBuilder: (context, imageProvider) =>
                                      Image(
                                    image: imageProvider,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                  placeholder: (context, url) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                    style: BorderStyle.solid,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Upload and Remove Buttons
                  Consumer<AppearanceService>(
                    builder: (context, appearanceService, _) {
                      return Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await _handleLogoUpload(
                                    context, appearanceService);
                              },
                              icon: const Icon(Icons.upload_file),
                              label: Text(appearanceService.hasCustomLogo
                                  ? 'Cambiar Logo'
                                  : 'Subir Logo'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          if (appearanceService.hasCustomLogo) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message:
                                  'Refrescar logo para ver la última versión',
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  appearanceService.refreshLogo();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Logo actualizado'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refrescar'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _handleLogoRemove(
                                      context, appearanceService);
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Eliminar'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info Card
          Card(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'El logo seleccionado reemplazará el encabezado completo del menú lateral y será clickable para regresar al inicio. Si no subes un logo personalizado, se mostrará el icono predeterminado con el nombre de la empresa.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogoUpload(
      BuildContext context, AppearanceService appearanceService) async {
    BuildContext? dialogContext;
    
    try {
      debugPrint('[AppearanceSettings] pickImage() called');
      
      // Pick image
      final result = await ImageService.pickImage();

      debugPrint(
          '[AppearanceSettings] pickImage() returned: ${result != null ? "Got file: ${result.name}" : "null (cancelled)"}');

      if (result == null) {
        debugPrint('[AppearanceSettings] User cancelled, returning');
        return; // User cancelled
      }

      debugPrint(
          '[AppearanceSettings] File size: ${result.bytes.length} bytes');

      if (!context.mounted) {
        debugPrint(
            '[AppearanceSettings] Context not mounted after pick, returning');
        return;
      }

      debugPrint('[AppearanceSettings] Showing loading dialog');

      // Show loading dialog and capture its context
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          dialogContext = ctx; // Capture the dialog context
          return const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Subiendo logo...'),
                  ],
                ),
              ),
            ),
          );
        },
      );

      debugPrint('[AppearanceSettings] Loading dialog shown');
      debugPrint('[AppearanceSettings] Starting upload: ${result.name}');

      // Upload image with timeout
      await appearanceService
          .uploadCompanyLogo(result.bytes, result.name)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint('[AppearanceSettings] Upload TIMED OUT after 30 seconds');
              throw Exception('Upload timed out after 30 seconds');
            },
          );

      debugPrint('[AppearanceSettings] Upload completed successfully');

      // Close dialog using the captured context
      if (dialogContext != null && dialogContext!.mounted) {
        debugPrint('[AppearanceSettings] Closing dialog with dialog context');
        Navigator.of(dialogContext!).pop();
      } else if (context.mounted) {
        debugPrint('[AppearanceSettings] Closing dialog with main context');
        Navigator.of(context).pop();
      }

      debugPrint('[AppearanceSettings] Dialog closed, refreshing logo');

      // Force refresh the logo to show the new one immediately
      appearanceService.refreshLogo();

      if (!context.mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo subido exitosamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[AppearanceSettings] Upload error: $e');
      
      // Close loading dialog if open
      if (dialogContext != null && dialogContext!.mounted) {
        try {
          debugPrint(
              '[AppearanceSettings] Closing dialog after error (dialog context)');
          Navigator.of(dialogContext!).pop();
        } catch (navError) {
          debugPrint('[AppearanceSettings] Error closing dialog: $navError');
        }
      } else if (context.mounted) {
        try {
          debugPrint(
              '[AppearanceSettings] Closing dialog after error (main context)');
          Navigator.of(context).pop();
        } catch (navError) {
          debugPrint('[AppearanceSettings] Error closing dialog: $navError');
        }
      }

      if (!context.mounted) return;

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir logo: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleLogoRemove(
      BuildContext context, AppearanceService appearanceService) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar logo?'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar el logo personalizado? '
          'Se volverá a mostrar el encabezado predeterminado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await appearanceService.removeCompanyLogo();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo eliminado'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar logo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
