library;

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/intelligent_purchasing_models.dart';
import '../widgets/purchase_visual_language.dart';

/// Composiciones del módulo de abastecimiento — handoff-t23.
///
/// Ninguna de estas superficies tiene id en `GUÍA GENERAL Viñabike -
/// Componentes`: la guía aporta la gramática visual (roles, tipografía, tabla
/// `TB-01`, inputs `IN-02`, botones `BT-01/BT-02`, shell `SH-01`) y este
/// archivo compone el flujo real del operador. Toda medida viene de
/// `handoff-t23/spec.json`, que manda sobre los frames; ningún color se
/// escribe literal.
///
/// Reglas duras que estas superficies hacen cumplir:
/// - ningún scrim ni bloque centrado sobre fondo atenuado;
/// - cápsula sólo para la excepción, nunca para metadata ni valores;
/// - la foto real precede a la identidad textual y nunca cambia la geometría;
/// - stock interno antes que proveedores;
/// - la disponibilidad del proveedor no se afirma desde el historial.

/// Geometría publicada por `handoff-t23/spec.json`.
abstract final class PurchaseSurfaceGeometry {
  /// `image_contract.geometry`.
  static const double mediaTableRow = 38;
  static const double mediaPhoneCard = 46;
  static const double mediaStockRow = 38;
  static const double mediaStockPhoneCard = 64;
  static const double mediaInspector = 76;

  /// `geometry_shell.process_band`.
  static const double stepBadge = 20;
  static const double stepActiveUnderline = 2;
  static const double phoneStepControl = 44;

  /// `frames[single-stock].geometry`.
  static const double stockColumnMax = 840;
  static const double stockQuantityColumn = 104;

  /// `frames[single-need].geometry` y `frames[clarification].geometry`.
  static const double narrowColumnMax = 780;

  /// `frames[single-inspector].geometry`.
  static const double inspectorDefaultWidth = 420;
  static const double inspectorMinWidth = 330;
  static const double inspectorMaxWidth = 600;
  static const double inspectorHandleWidth = 13;
  static const double tabletEdgeSheetWidth = 410;

  /// Radio de tile del contrato de imagen.
  static const double mediaRadius = 8;
}

/// Foto real del producto con fallback canónico de la misma geometría.
///
/// El tile tonal es el estado de carga —se ve desde el primer frame— y también
/// el estado de error: una URL que no resuelve deja el monograma, nunca una
/// caja rota. La cadena de resolución avanza sola cuando una URL falla, de modo
/// que una `image_url_optimized` caída todavía puede mostrar la imagen cruda.
class ProductMediaTile extends StatefulWidget {
  const ProductMediaTile({
    super.key,
    required this.media,
    required this.name,
    required this.size,
  });

  final ProductMedia media;
  final String name;
  final double size;

  @override
  State<ProductMediaTile> createState() => _ProductMediaTileState();
}

class _ProductMediaTileState extends State<ProductMediaTile> {
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant ProductMediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.resolutionChain.join('|') !=
        widget.media.resolutionChain.join('|')) {
      _attempt = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chain = widget.media.resolutionChain;
    final exhausted = _attempt >= chain.length;
    final label = exhausted
        ? (chain.isEmpty
            ? 'Este producto no tiene imagen cargada en su ficha'
            : 'La imagen del producto no se pudo cargar')
        : widget.name;

    return Tooltip(
      message: label,
      child: Semantics(
        image: !exhausted,
        label: label,
        child: Container(
          width: widget.size,
          height: widget.size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // El tile tonal ES el estado de carga: sin spinner ruidoso.
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius:
                BorderRadius.circular(PurchaseSurfaceGeometry.mediaRadius),
          ),
          child: exhausted
              ? _Monogram(name: widget.name, size: widget.size)
              : Image.network(
                  chain[_attempt],
                  // contain, nunca cover: recortar un repuesto cambia su identidad.
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, _, __) {
                    // Avanza a la siguiente URL de la cadena, o al monograma.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _attempt < chain.length) {
                        setState(() => _attempt += 1);
                      }
                    });
                    return _Monogram(name: widget.name, size: widget.size);
                  },
                ),
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        productMonogram(name),
        textAlign: TextAlign.center,
        style: PurchaseType.label.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontSize: size >= PurchaseSurfaceGeometry.mediaInspector ? 20 : 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Los cuatro pasos del proceso. El stock precede siempre a los proveedores.
enum PurchaseStep { need, stock, providers, plan }

extension PurchaseStepLabel on PurchaseStep {
  String get label => switch (this) {
        PurchaseStep.need => 'Necesidad',
        PurchaseStep.stock => 'Stock interno',
        PurchaseStep.providers => 'Proveedores',
        PurchaseStep.plan => 'Plan',
      };

  int get position => index + 1;
}

/// Banda de proceso sobre el shell: cuatro pasos en fila (desktop/tablet) o
/// stepper de tres piezas (teléfono). Nunca produce overflow horizontal ni
/// recorta una palabra.
class PurchaseProcessBand extends StatefulWidget {
  const PurchaseProcessBand({
    super.key,
    required this.active,
    required this.meta,
    required this.enabled,
    required this.onGo,
    required this.compact,
    this.statusLabel,
  });

  final PurchaseStep active;
  final Map<PurchaseStep, String> meta;
  final Set<PurchaseStep> enabled;
  final ValueChanged<PurchaseStep> onGo;
  final bool compact;
  final String? statusLabel;

  @override
  State<PurchaseProcessBand> createState() => _PurchaseProcessBandState();
}

class _PurchaseProcessBandState extends State<PurchaseProcessBand> {
  final _scrollController = ScrollController();
  final _stepKeys = <PurchaseStep, GlobalKey>{
    for (final step in PurchaseStep.values) step: GlobalKey(),
  };

  @override
  void didUpdateWidget(covariant PurchaseProcessBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _centerActive();
  }

  void _centerActive() {
    if (widget.compact || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _stepKeys[widget.active];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      final offset = box.localToGlobal(Offset.zero).dx;
      final current = _scrollController.offset;
      final target = current + offset - (viewport - box.size.width) / 2;
      _scrollController.jumpTo(
        target.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context).shell;
    return Container(
      color: roles.canvas,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!widget.compact) ...[
                Text(
                  'Asistente de compras',
                  style: PurchaseType.surfaceTitle.copyWith(
                    fontFamily: 'Poppins',
                    color: roles.foreground,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  'Revisa primero la bodega y, si falta, encuentra dónde comprarlo con evidencia.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      PurchaseType.meta.copyWith(color: roles.mutedForeground),
                ),
              ),
              if (widget.statusLabel != null) ...[
                const SizedBox(width: 12),
                // Punto + texto, nunca cápsula.
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: roles.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.statusLabel!,
                  style:
                      PurchaseType.label.copyWith(color: roles.mutedForeground),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          widget.compact
              ? _buildPhoneStepper(context)
              : _buildWideSteps(context),
        ],
      ),
    );
  }

  Widget _buildWideSteps(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        key: const ValueKey('purchase-process-steps'),
        children: [
          for (final step in PurchaseStep.values)
            _WideStep(
              key: _stepKeys[step],
              step: step,
              active: step == widget.active,
              meta: widget.meta[step],
              enabled: widget.enabled.contains(step),
              onGo: () => widget.onGo(step),
            ),
        ],
      ),
    );
  }

  Widget _buildPhoneStepper(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context).shell;
    const steps = PurchaseStep.values;
    final index = steps.indexOf(widget.active);
    final previous = index > 0 ? steps[index - 1] : null;
    final next = index < steps.length - 1 ? steps[index + 1] : null;
    final previousEnabled =
        previous != null && widget.enabled.contains(previous);
    final nextEnabled = next != null && widget.enabled.contains(next);

    return Row(
      key: const ValueKey('purchase-process-stepper'),
      children: [
        SizedBox(
          width: PurchaseSurfaceGeometry.phoneStepControl,
          height: PurchaseSurfaceGeometry.phoneStepControl,
          child: IconButton(
            tooltip: previous == null
                ? 'Este es el primer paso'
                : 'Volver a ${previous.label}',
            onPressed: previousEnabled ? () => widget.onGo(previous) : null,
            icon: Icon(Icons.chevron_left, color: roles.foreground),
            disabledColor: roles.mutedForeground,
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: roles.accent,
                  width: PurchaseSurfaceGeometry.stepActiveUnderline,
                ),
              ),
            ),
            child: Row(
              children: [
                _StepBadge(
                  position: widget.active.position,
                  active: true,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.active.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PurchaseType.rowTitle
                            .copyWith(color: roles.foreground),
                      ),
                      if (widget.meta[widget.active] != null)
                        Text(
                          widget.meta[widget.active]!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PurchaseType.label.copyWith(
                            color: roles.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.active.position}/${steps.length}',
                  style: PurchaseType.label.copyWith(
                    color: roles.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: PurchaseSurfaceGeometry.phoneStepControl,
          height: PurchaseSurfaceGeometry.phoneStepControl,
          child: IconButton(
            tooltip: next == null
                ? 'Este es el último paso'
                : nextEnabled
                    ? 'Ir a ${next.label}'
                    : '${next.label} todavía no está disponible',
            onPressed: nextEnabled ? () => widget.onGo(next) : null,
            icon: Icon(Icons.chevron_right, color: roles.foreground),
            disabledColor: roles.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _WideStep extends StatelessWidget {
  const _WideStep({
    super.key,
    required this.step,
    required this.active,
    required this.meta,
    required this.enabled,
    required this.onGo,
  });

  final PurchaseStep step;
  final bool active;
  final String? meta;
  final bool enabled;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context).shell;
    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: 'Paso ${step.position}: ${step.label}',
      child: InkWell(
        onTap: enabled ? onGo : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? roles.accent : Colors.transparent,
                width: PurchaseSurfaceGeometry.stepActiveUnderline,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepBadge(
                position: step.position,
                active: active,
                size: PurchaseSurfaceGeometry.stepBadge,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.label,
                    style: PurchaseType.rowTitle.copyWith(
                      color: enabled ? roles.foreground : roles.mutedForeground,
                    ),
                  ),
                  if (meta != null)
                    Text(
                      meta!,
                      style: PurchaseType.label.copyWith(
                        color: roles.mutedForeground,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.position,
    required this.active,
    required this.size,
  });

  final int position;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context).shell;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? roles.accent : roles.raised,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$position',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              color: active ? roles.onAccent : roles.mutedForeground,
            ),
      ),
    );
  }
}

/// Fila persistente de la necesidad, editable en su sitio.
///
/// Nunca abre un diálogo: el owner rechazó explícitamente editar una necesidad
/// en un bloque centrado sobre fondo atenuado.
class SupplyNeedBar extends StatelessWidget {
  const SupplyNeedBar({
    super.key,
    required this.title,
    required this.quantityLabel,
    required this.criteriaSummary,
    required this.editing,
    required this.onEdit,
    required this.onCancel,
    required this.editor,
    this.onOpenCriteria,
  });

  final String title;
  final String quantityLabel;
  final String criteriaSummary;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Widget editor;
  final VoidCallback? onOpenCriteria;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: editing
          ? editor
          : Wrap(
              spacing: 11,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title, style: PurchaseType.sectionTitle),
                Text(
                  quantityLabel,
                  style: PurchaseType.meta.copyWith(
                    fontFamily: 'IBM Plex Mono',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (criteriaSummary.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      criteriaSummary,
                      style: PurchaseType.meta
                          .copyWith(color: PurchaseTokens.of(context).inkMuted),
                    ),
                  ),
                OutlinedButton(
                  key: const ValueKey('edit-supply-need-inline'),
                  onPressed: onEdit,
                  child: const Text('Editar necesidad'),
                ),
                if (onOpenCriteria != null)
                  TextButton(
                    key: const ValueKey('open-need-criteria'),
                    onPressed: onOpenCriteria,
                    // Frames 01/02/14/15/16/19/26: la etiqueta es «Criterios».
                    child: const Text('Criterios'),
                  ),
              ],
            ),
    );
  }
}

/// Paso 2 — la bodega se consulta antes de cotizar.
///
/// En desktop y tablet es una fila; en teléfono es una card propia, nunca la
/// fila comprimida.
class InternalStockSurface extends StatelessWidget {
  const InternalStockSurface({
    super.key,
    required this.components,
    required this.requestedQuantity,
    required this.compact,
    required this.assignable,
    required this.onAssign,
    required this.onCompareProviders,
    required this.busy,
    this.countedAtLabel,
    this.rejectionReason,
  });

  final List<SupplyInventoryComponent> components;
  final double requestedQuantity;
  final bool compact;
  final bool assignable;
  final VoidCallback? onAssign;
  final VoidCallback onCompareProviders;
  final bool busy;
  final String? countedAtLabel;
  final String? rejectionReason;

  int get _coveredUnits => components.isEmpty
      ? 0
      : components.map((c) => c.coverable).reduce((a, b) => a < b ? a : b);

  int get _remainingUnits =>
      (requestedQuantity.round() - _coveredUnits).clamp(0, 1 << 30);

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: PurchaseSurfaceGeometry.stockColumnMax,
        ),
        child: ListView(
          key: const ValueKey('internal-stock-surface'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            // Encabezado y existencias son **un** panel: el título suelto sobre
            // el fondo y las filas debajo no se leían como una superficie.
            PurchasePanel(
              padded: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Stock interno primero',
                          style: PurchaseType.surfaceTitle
                              .copyWith(color: tokens.ink),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'La bodega se consulta antes de cotizar. Existencias contadas del tenant, no historial de compras.',
                          style: PurchaseType.meta
                              .copyWith(color: tokens.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  if (components.isEmpty)
                    // Sin coincidencias: texto inline, sin isla centrada.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
                      child: Text(
                        'No hay existencias contadas para esta necesidad.',
                        style:
                            PurchaseType.body.copyWith(color: tokens.inkMuted),
                      ),
                    )
                  else
                    for (final component in components)
                      compact
                          ? _StockCard(
                              component: component,
                              countedAtLabel: countedAtLabel,
                              assignable: assignable,
                              busy: busy,
                              onAssign: onAssign,
                            )
                          : _StockRow(
                              component: component,
                              countedAtLabel: countedAtLabel,
                              assignable: assignable,
                              busy: busy,
                              onAssign: onAssign,
                            ),
                ],
              ),
            ),
            if (rejectionReason != null) ...[
              const SizedBox(height: PurchaseMetrics.stageGap),
              Text(
                'Se decidió no usar el stock: $rejectionReason',
                style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
              ),
            ],
            const SizedBox(height: PurchaseMetrics.stageGap),
            Align(
              alignment: compact ? Alignment.center : Alignment.centerLeft,
              child: SizedBox(
                width: compact ? double.infinity : null,
                height: 36,
                child: FilledButton(
                  key: const ValueKey('compare-providers-for-remaining'),
                  onPressed: busy ? null : onCompareProviders,
                  child: Text(
                    _remainingUnits > 0
                        ? 'Comparar proveedores por $_remainingUnits restantes'
                        : 'Comparar proveedores',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _coveredUnits > 0
                  ? '$_coveredUnits de ${requestedQuantity.round()} salen de bodega en este borrador. '
                      'Usar del stock no reserva ni descuenta inventario: eso ocurre al despachar.'
                  : 'Usar del stock no reserva ni descuenta inventario: eso ocurre al despachar.',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Punto semántico: verde cubre, ámbar cubre parcialmente, neutro sin existencias.
class _StockDot extends StatelessWidget {
  const _StockDot({required this.component});

  final SupplyInventoryComponent component;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final tone = component.availableToPromise <= 0
        ? roles.neutral
        : component.shortfall == 0
            ? roles.success
            : roles.warning;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: tone.accent, shape: BoxShape.circle),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.component,
    required this.countedAtLabel,
    required this.assignable,
    required this.busy,
    required this.onAssign,
  });

  final SupplyInventoryComponent component;
  final String? countedAtLabel;
  final bool assignable;
  final bool busy;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border:
            // Separador interno del panel, no el contorno de otra caja.
            Border(top: BorderSide(color: PurchaseTokens.of(context).hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProductMediaTile(
            media: component.media,
            name: component.name,
            size: PurchaseSurfaceGeometry.mediaStockRow,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(component.name, style: PurchaseType.rowTitle),
                const SizedBox(height: 2),
                Text(
                  [
                    if (component.sku != null) component.sku!,
                    'comprometido ${component.onlineCommitted + component.workshopCommitted}',
                    if (countedAtLabel != null) countedAtLabel!,
                  ].join(' · '),
                  style: PurchaseType.meta
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          SizedBox(
            width: PurchaseSurfaceGeometry.stockQuantityColumn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _StockDot(component: component),
                    const SizedBox(width: 6),
                    Text(
                      '${component.availableToPromise}',
                      style: PurchaseType.metricMedium.copyWith(
                        fontFamily: 'IBM Plex Mono',
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                Text(
                  'necesitas ${component.requiredQuantity}',
                  style: PurchaseType.meta
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (assignable && onAssign != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: busy ? null : onAssign,
              child: Text('Usar ${component.coverable} de bodega'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.component,
    required this.countedAtLabel,
    required this.assignable,
    required this.busy,
    required this.onAssign,
  });

  final SupplyInventoryComponent component;
  final String? countedAtLabel;
  final bool assignable;
  final bool busy;
  final VoidCallback? onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductMediaTile(
                media: component.media,
                name: component.name,
                size: PurchaseSurfaceGeometry.mediaStockPhoneCard,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      component.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.rowTitle,
                    ),
                    if (component.sku != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        component.sku!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PurchaseType.meta.copyWith(
                            color: PurchaseTokens.of(context).inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StockDot(component: component),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Disponible ${component.availableToPromise} · necesitas ${component.requiredQuantity}',
                  style: PurchaseType.body,
                ),
              ),
            ],
          ),
          if (countedAtLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              countedAtLabel!,
              style: PurchaseType.meta
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (assignable && onAssign != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: PurchaseSurfaceGeometry.phoneStepControl,
              child: FilledButton(
                onPressed: busy ? null : onAssign,
                child: Text('Usar ${component.coverable} de bodega'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
