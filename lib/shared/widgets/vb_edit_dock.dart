import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';
import 'vb_button.dart';
import 'vb_segmented.dart' show VbDensity;

/// La barra que flota al pie mientras algo se edita en su lugar: cuántos
/// cambios hay y cómo guardarlos o descartarlos sin volver arriba de la hoja.
///
/// Nació en la ficha de la bici (2026-10-02) y la usa también la hoja de
/// datos del cliente (2026-10-03). Un aviso del guardado —una regla que no
/// se cumple, otro que guardó entre medio— va aquí, a la vista de quien está
/// por guardar, y no en un SnackBar que la tapa.
class VbEditDock extends StatelessWidget {
  const VbEditDock({
    super.key,
    required this.changeCount,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    this.saveSemanticLabel,
    this.busy = false,
    this.notice,
  });

  final int changeCount;

  /// «Guardar bici», «Guardar datos». En una barra angosta queda «Guardar».
  final String saveLabel;
  final String? saveSemanticLabel;
  final VoidCallback? onCancel;

  /// Nulo deshabilita; sin cambios o guardando también.
  final VoidCallback? onSave;
  final bool busy;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final count = changeCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final status = count == 0
            ? (compact ? 'Sin cambios' : 'Sin cambios todavía')
            : count == 1
                ? (compact ? '1 cambio' : '1 cambio sin guardar')
                : (compact ? '$count cambios' : '$count cambios sin guardar');
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 10, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: roles.warning.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              notice!,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: roles.warning.onContainer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (!compact) ...[
                      Icon(Icons.edit_note,
                          size: 22, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    VbButton(
                      label: 'Cancelar',
                      variant: VbButtonVariant.secondary,
                      density: VbDensity.comfortable,
                      onPressed: busy ? null : onCancel,
                    ),
                    const SizedBox(width: 8),
                    VbButton(
                      label: compact ? 'Guardar' : saveLabel,
                      icon: Icons.check,
                      density: VbDensity.comfortable,
                      busy: busy,
                      semanticLabel: saveSemanticLabel ?? saveLabel,
                      onPressed: count == 0 || busy ? null : onSave,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lo que se desplaza y, mientras se edita, la barra flotando al pie.
class VbEditDockLayer extends StatelessWidget {
  const VbEditDockLayer({super.key, required this.child, this.dock});

  final Widget child;

  /// Nula fuera de la edición.
  final Widget? dock;

  @override
  Widget build(BuildContext context) {
    final dock = this.dock;
    if (dock == null) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: dock,
            ),
          ),
        ),
      ],
    );
  }
}
