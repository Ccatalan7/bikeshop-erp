import 'dart:math' as math;

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
                      // El título fluye con la tarjeta: en compacto, o con el
                      // texto agrandado, un `Text` suelto en un `Row` desborda
                      // en vez de reflowar. La tarjeta de abajo ya lo hacía así.
                      Expanded(
                        child: Text(
                          'Tema de la Aplicación',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
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
                      // **Los segmentos van sin icono, y ésa es la corrección.**
                      // `SegmentedButton` da a cada segmento `maxWidth / 3` y su
                      // etiqueta va `Flexible` sin `maxLines`: cuando no alcanza
                      // parte la palabra sin avisar —«Sistem/a» a 390 px, y a
                      // 430 no—. Las dos palancas que parecerían servir están
                      // cerradas por el framework: `ButtonStyleButton` recorta a
                      // cero toda densidad horizontal negativa («don't allow the
                      // VisualDensity adjustment to reduce the width of the
                      // left/right padding») y `_SegmentButton` sobrescribe el
                      // `padding` del estilo en cuanto el segmento tiene icono.
                      // Medido: 458.10 px de selector con icono —da igual el
                      // contrato o el `padding`— contra 380.10 px sin icono, o
                      // sea 26 px de holgura por segmento. A 390 px reales cada
                      // segmento recibe 108.7 y `Sistema` pasa de pedir ~108 a
                      // pedir ~82: cabe incluso al 130 % de escala de texto.
                      //
                      // No se pierde semántica: `Claro`, `Oscuro` y `Sistema`
                      // son palabras inequívocas y la selección la sigue
                      // mostrando el relleno del propio segmento. El canon
                      // compacto prohíbe el icono **sin** palabra, no al revés.
                      //
                      // La densidad **no** se fuerza acá. `VisualDensity.compact`
                      // no reducía ancho —lo prueba la medición de arriba— y su
                      // único efecto era bajar el alto del selector de 48 a 40,
                      // por debajo del mínimo táctil. La densidad la decide el
                      // `ThemeData`, que ya la deriva de la plataforma:
                      // `standard` donde se toca con el dedo, `compact` en
                      // escritorio.
                      return SegmentedButton<ThemeMode>(
                        key: const ValueKey('appearance-theme-mode'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Claro'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Oscuro'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Sistema'),
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
                      Expanded(
                        child: Text(
                          'Logo de la Empresa',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
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
                      return _LogoActions(
                        hasCustomLogo: appearanceService.hasCustomLogo,
                        onUpload: () =>
                            _handleLogoUpload(context, appearanceService),
                        onRefresh: () {
                          appearanceService.refreshLogo();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Logo actualizado'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        onRemove: () =>
                            _handleLogoRemove(context, appearanceService),
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

/// Acciones del logo — «Subir/Cambiar Logo», «Refrescar» y «Eliminar».
///
/// **Causa del defecto:** las tres iban en un `Row` fijo. La etiqueta de un
/// `*Button.icon` es `Flexible`, así que cuando el ancho no alcanza el botón no
/// se queja: parte la palabra. A 430 px se leía «Cam/biar/Logo» y «Elimi/nar»,
/// en claro y en oscuro. No era el ancho de la ventana; era esta composición.
///
/// La fila sólo se conserva **cuando cabe medida**, no por costumbre: se calcula
/// el ancho que cada acción necesita para decir su palabra completa en una línea
/// —relleno + icono + separación + texto al `textScaler` vigente— y con eso se
/// elige entre las tres composiciones. Las etiquetas nunca se parten y ninguna
/// acción se esconde detrás de un icono mudo, que es lo que pide el canon
/// compacto: una acción importante no puede depender de un icono sin palabra.
class _LogoActions extends StatelessWidget {
  const _LogoActions({
    required this.hasCustomLogo,
    required this.onUpload,
    required this.onRefresh,
    required this.onRemove,
  });

  /// Separación entre acciones, igual en fila y apiladas.
  static const double _gap = 12;

  /// Relleno horizontal declarado en el `styleFrom` de cada acción.
  static const double _horizontalPadding = 16;

  /// Tamaño del icono de un `*Button.icon` en Material 3.
  static const double _iconExtent = 18;

  /// Separación icono–etiqueta de un `*Button.icon` a escala de texto 1.
  static const double _iconGap = 8;

  /// Holgura para redondeos de medición: sobrestimar apila un poco antes, que
  /// es preferible a partir una palabra.
  static const double _measurementSlack = 4;

  /// Alto mínimo táctil exigido por el canon compacto.
  static const double _minimumTouchHeight = 48;

  final bool hasCustomLogo;
  final Future<void> Function() onUpload;
  final VoidCallback onRefresh;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final uploadLabel = hasCustomLogo ? 'Cambiar Logo' : 'Subir Logo';
    final upload = ElevatedButton.icon(
      key: const ValueKey('appearance-logo-upload'),
      onPressed: () async {
        await onUpload();
      },
      icon: const Icon(Icons.upload_file),
      label: Text(
        uploadLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(_horizontalPadding),
        minimumSize: const Size(64, _minimumTouchHeight),
      ),
    );

    if (!hasCustomLogo) {
      return SizedBox(width: double.infinity, child: upload);
    }

    final refresh = Tooltip(
      message: 'Refrescar logo para ver la última versión',
      child: OutlinedButton.icon(
        key: const ValueKey('appearance-logo-refresh'),
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh),
        label: const Text(
          'Refrescar',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(_horizontalPadding),
          minimumSize: const Size(64, _minimumTouchHeight),
        ),
      ),
    );

    final remove = OutlinedButton.icon(
      key: const ValueKey('appearance-logo-remove'),
      onPressed: () async {
        await onRemove();
      },
      icon: const Icon(Icons.delete_outline),
      label: const Text(
        'Eliminar',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(_horizontalPadding),
        minimumSize: const Size(64, _minimumTouchHeight),
        foregroundColor: Colors.red,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final uploadExtent = _labelledActionExtent(context, uploadLabel);
        final refreshExtent = _labelledActionExtent(context, 'Refrescar');
        final removeExtent = _labelledActionExtent(context, 'Eliminar');

        // La condición no es «cuánto suman», es **cuánto le toca a cada una**:
        // `Expanded` reparte el sobrante en partes iguales, así que las dos
        // acciones flexibles reciben el mismo ancho aunque una necesite más.
        // Comparar contra la suma dejaba pasar un tramo intermedio —cerca de
        // 700 px de ventana— donde la fila cabía «en total» pero `Cambiar Logo`
        // se truncaba con puntos suspensivos. Se mide contra el máximo.
        final rowRequired =
            2 * math.max(uploadExtent, removeExtent) + refreshExtent + _gap * 2;
        final splitRequired = 2 * math.max(refreshExtent, removeExtent) + _gap;

        if (rowRequired <= available) {
          return Row(
            key: const ValueKey('appearance-logo-actions-row'),
            children: [
              Expanded(child: upload),
              const SizedBox(width: _gap),
              refresh,
              const SizedBox(width: _gap),
              Expanded(child: remove),
            ],
          );
        }

        if (splitRequired <= available) {
          return Column(
            key: const ValueKey('appearance-logo-actions-split'),
            children: [
              SizedBox(width: double.infinity, child: upload),
              const SizedBox(height: _gap),
              Row(
                children: [
                  Expanded(child: refresh),
                  const SizedBox(width: _gap),
                  Expanded(child: remove),
                ],
              ),
            ],
          );
        }

        return Column(
          key: const ValueKey('appearance-logo-actions-stack'),
          children: [
            SizedBox(width: double.infinity, child: upload),
            const SizedBox(height: _gap),
            SizedBox(width: double.infinity, child: refresh),
            const SizedBox(height: _gap),
            SizedBox(width: double.infinity, child: remove),
          ],
        );
      },
    );
  }

  /// Ancho que necesita una acción para decir `label` completa en una línea.
  double _labelledActionExtent(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return _horizontalPadding * 2 +
        _iconExtent +
        _iconGap +
        painter.width +
        _measurementSlack;
  }
}
