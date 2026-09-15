library;

import 'package:flutter/material.dart';

import '../../ai_assistant/models/ai_assistant_turn_contracts.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/intelligent_purchasing_models.dart';
import '../widgets/purchase_visual_language.dart';

/// Procedencia de abastecimiento en palabras que no mezclan catálogo,
/// historial ni disponibilidad.
String supplySourcingLabel(SupplyStockOption option) {
  final rawSupplier = option.supplierName?.trim();
  final supplier =
      rawSupplier == null || rawSupplier.isEmpty ? null : rawSupplier;
  return switch (option.evidenceState) {
    'erp_purchase_history' => supplier == null
        ? 'Con compras registradas en este ERP'
        : 'Comprado a $supplier en este ERP',
    'fresh_supplier_check' => supplier == null
        ? 'Disponible según portal · revisado ${supplySourcingDateLabel(option.availabilityCheckedAt)}'
        : 'Disponible según portal de $supplier · revisado ${supplySourcingDateLabel(option.availabilityCheckedAt)}',
    'catalog_assignment' => option.availabilityFresh &&
            option.availabilityStatus == 'out_of_stock'
        ? 'Proveedor en ficha: ${supplier ?? 'sin identificar'} · portal sin stock · revisado ${supplySourcingDateLabel(option.availabilityCheckedAt)}'
        : supplier == null
            ? 'Proveedor de ficha sin identificar · disponibilidad sin verificar'
            : 'Proveedor en ficha: $supplier · disponibilidad sin verificar',
    'no_erp_history' => 'Sin compras registradas en este ERP',
    _ => 'Procedencia de compra todavía no verificada',
  };
}

String supplySourcingDateLabel(DateTime? value) {
  if (value == null) return 'sin fecha';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

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

  /// Lo que queda del inspector al colapsarlo.
  ///
  /// `frames[single-inspector].resize.collapse` del spec: «botón ›› / ‹‹ con
  /// riel de 28px». No es un panel estrecho: es una franja con el control
  /// para volver. Colapsar y cerrar se distinguen justo por esto —el riel
  /// queda y conserva el candidato; el `×` lo suelta—.
  static const double inspectorCollapsedRail = 28;

  /// Cuánto del alto disponible ocupa una hoja anclada en teléfono.
  ///
  /// La franja que queda arriba es el punto del contrato: en el frame 17 el
  /// encabezado de resultados sigue **visible y sin atenuar** detrás de la
  /// hoja. Si la hoja llegara al borde superior no habría contexto que
  /// conservar, y si fuera mucho más baja el detalle dejaría de caber. El
  /// valor ya lo usaba la hoja de compra local; acá se le pone nombre para que
  /// las dos hojas no se separen por descuido.
  static const double phoneSheetHeightFactor = 0.88;

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
    this.statusPartial = false,
  });

  final PurchaseStep active;
  final Map<PurchaseStep, String> meta;
  final Set<PurchaseStep> enabled;
  final ValueChanged<PurchaseStep> onGo;
  final bool compact;
  final String? statusLabel;

  /// El análisis dio resultado, pero falta una precisión para comparar.
  /// Tiñe el punto de ámbar; el rótulo lo pone quien lo pasa.
  final bool statusPartial;

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
                  style: PurchaseType.moduleTitle
                      .copyWith(color: roles.foreground),
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
                //
                // **El punto es semántico, no decorativo** (NOTES §36 y §132:
                // «punto ámbar + texto» para «Resultados parciales»). Era
                // siempre `accent`, así que decía lo mismo con una pregunta
                // abierta que con el análisis cerrado: el color no aportaba
                // nada y el operador tenía que leer para saberlo.
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.statusPartial
                        ? VinabikeThemeRoles.of(context).warning.accent
                        : roles.accent,
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
        // Pedir la familia por nombre la dejaba a merced de que otra pantalla
        // ya hubiera cargado IBM Plex Mono en esa sesión. `PurchaseType.label`
        // es el mismo rol mono que ya llevan la posición «n/4» y el subtítulo
        // del paso, y resuelve la familia por `google_fonts`. El
        // `letter-spacing` del rol separa letras de una etiqueta; en un dígito
        // suelto sólo agrega aire a la derecha y descentra el glifo.
        style: PurchaseType.label.copyWith(
          letterSpacing: 0,
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
      child: editing ? editor : _resumen(context),
    );
  }

  /// El resumen y sus dos acciones.
  ///
  /// **Las acciones son un grupo, no dos hermanos sueltos.** Estaban los cinco
  /// hijos en un mismo `Wrap`, y con el resumen largo la primera línea se
  /// llenaba justo después de «Editar necesidad»: «Criterios» caía sola a la
  /// línea siguiente, pegada al margen izquierdo, mientras su pareja quedaba
  /// arriba a la derecha. Dos acciones sobre el mismo objeto en esquinas
  /// opuestas. Ahora viajan juntas: envueltas se envuelven las dos.
  Widget _resumen(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final acciones = _acciones(context);
        final descripcion = _descripcion(context);
        // En una barra ancha manda la disposición de siempre: lo descriptivo a
        // la izquierda y el grupo de acciones al extremo derecho. Estrecha, se
        // apilan — que es lo que ya hacían bien el tablet y el teléfono.
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: descripcion),
              const SizedBox(width: 11),
              acciones,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            descripcion,
            const SizedBox(height: 8),
            acciones,
          ],
        );
      },
    );
  }

  Widget _acciones(BuildContext context) {
    return Wrap(
      spacing: 11,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
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
    );
  }

  Widget _descripcion(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 11,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(title, style: PurchaseType.sectionTitle),
        // **La cantidad, el separador y el resumen son UNA celda.** El
        // contrato pide «cantidad + separador `|` + resumen» (NOTES §44-45), y
        // con la cantidad como hermano suelto el `|` encabezaba la línea
        // envuelta: un glifo colgando de nada al margen izquierdo. Juntos no se
        // pueden separar, y el separador siempre queda entre las dos cosas que
        // separa.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                quantityLabel,
                style: PurchaseType.metaNumeric.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (criteriaSummary.isNotEmpty) ...<Widget>[
                const SizedBox(width: 11),
                Text(
                  '|',
                  style: PurchaseType.meta.copyWith(
                    color: PurchaseTokens.of(context).hair,
                  ),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    criteriaSummary,
                    style: PurchaseType.meta.copyWith(
                      color: PurchaseTokens.of(context).inkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
    this.sourcingByProduct = const <String, SupplyStockOption>{},
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
  final Map<String, SupplyStockOption> sourcingByProduct;

  int get _coveredUnits => components.isEmpty
      ? 0
      : components.map((c) => c.coverable).reduce((a, b) => a < b ? a : b);

  int get _remainingUnits =>
      (requestedQuantity.round() - _coveredUnits).clamp(0, 1 << 30);

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    // `frames[single-stock]`: el título de superficie y su lead van sobre el
    // lienzo; la tarjeta empieza en la cabecera `sunken`. Estaban dentro del
    // panel, y eso fundía dos bloques del diseño en uno solo.
    final header = <Widget>[
      Text(
        'Stock interno primero',
        style: PurchaseType.surfaceTitle.copyWith(color: tokens.ink),
      ),
      const SizedBox(height: 3),
      Text(
        'La bodega se consulta antes de cotizar. Existencias contadas del tenant, no historial de compras.',
        style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
      ),
      const SizedBox(height: 12),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: PurchaseSurfaceGeometry.stockColumnMax,
        ),
        child: ListView(
          key: const ValueKey('internal-stock-surface'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            ...header,
            if (components.isEmpty)
              // Sin coincidencias: texto inline, sin isla centrada.
              Text(
                'No hay existencias contadas para esta necesidad.',
                style: PurchaseType.body.copyWith(color: tokens.inkMuted),
              )
            else if (compact)
              // Teléfono: cards apiladas sobre el lienzo. Envolverlas en el
              // panel dejaba una caja dentro de otra.
              for (final component in components)
                _StockCard(
                  component: component,
                  sourcing: sourcingByProduct[component.productId],
                  countedAtLabel: countedAtLabel,
                  assignable: assignable,
                  busy: busy,
                  onAssign: onAssign,
                )
            else
              PurchasePanel(
                padded: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StockPanelHeader(
                      left: 'EXISTENCIA INTERNA',
                      right: 'DISPONIBLE',
                    ),
                    for (final component in components)
                      _StockRow(
                        component: component,
                        sourcing: sourcingByProduct[component.productId],
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
                height: compact ? PurchaseMetrics.touchTarget : 36,
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

/// Cabecera `sunken` de la tarjeta de existencias (`frames[single-stock]`).
///
/// Dos etiquetas mono 9 en versalitas, la de la derecha alineada al final. Es
/// lo que hace que la lista se lea como una tabla; faltaba en las dos vías.
class StockPanelHeader extends StatelessWidget {
  const StockPanelHeader({
    super.key,
    required this.left,
    required this.right,
  });

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      color: tokens.sunken,
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: PurchaseType.label.copyWith(color: tokens.inkFaint),
            ),
          ),
          Text(
            right,
            style: PurchaseType.label.copyWith(color: tokens.inkFaint),
          ),
        ],
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
    this.sourcing,
  });

  final SupplyInventoryComponent component;
  final String? countedAtLabel;
  final bool assignable;
  final bool busy;
  final VoidCallback? onAssign;
  final SupplyStockOption? sourcing;

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
                if (sourcing != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    supplySourcingLabel(sourcing!),
                    style: PurchaseType.meta.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                      // `metric_sm` en el spec: «celdas de tabla, totales de
                      // grupo». `metric_md` es de las cards de teléfono, y
                      // esto es la fila de escritorio.
                      style: PurchaseType.metricSmall.copyWith(
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
            // `frames[single-stock]`: la acción trailing es un botón
            // secundario **con borde**, no una CTA textual.
            OutlinedButton(
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
    this.sourcing,
  });

  final SupplyInventoryComponent component;
  final String? countedAtLabel;
  final bool assignable;
  final bool busy;
  final VoidCallback? onAssign;
  final SupplyStockOption? sourcing;

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
                      style: PurchaseType.cardTitle,
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
          if (sourcing != null) ...[
            const SizedBox(height: 4),
            Text(
              supplySourcingLabel(sourcing!),
              style: PurchaseType.meta.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (assignable && onAssign != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: PurchaseSurfaceGeometry.phoneStepControl,
              // Secundario, igual que su gemela de escritorio: el único sólido
              // de la superficie es el cierre («Comparar proveedores»). Esta
              // rama había quedado sólida y ponía dos primarios en la misma
              // pantalla de teléfono.
              child: OutlinedButton(
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

/// **Lo que el asistente miró, dicho dentro de Compras.**
///
/// Una tarjeta del gateway es un enlace a otro módulo: lleva un `destination`
/// de superficie agregada y, con `autoOpen`, se dispara sola. Dentro de un
/// flujo dedicado eso no es una acción útil sino una salida — el operador
/// estaba capturando una necesidad y aparecía en Inventario.
///
/// Esta proyección conserva lo único que aportaba —qué se miró y con qué
/// filtro— y le quita la capacidad de navegar. No tiene `onTap`, no tiene CTA
/// y no conoce ningún destino: la evidencia se lee donde se produjo.
@immutable
class PurchaseAssistantEvidence {
  const PurchaseAssistantEvidence({
    required this.title,
    this.detail,
    this.chips = const <String>[],
  });

  factory PurchaseAssistantEvidence.fromCard(AIAssistantActionCard card) {
    return PurchaseAssistantEvidence(
      title: card.title,
      detail: card.subtitle ?? card.description,
      chips: card.chips,
    );
  }

  final String title;
  final String? detail;
  final List<String> chips;
}

/// Una fila de evidencia: se lee, no se toca.
///
/// **Su anatomía no es nueva y por eso no trae medidas nuevas.** Es la misma
/// fila de lectura que ya usa la línea de un escenario en este módulo —
/// `ListTile` con `contentPadding: EdgeInsets.zero`, título y detalle— así que
/// el ritmo vertical lo pone Material y no un número elegido a ojo. Los estilos
/// son los del módulo (`PurchaseType`) atados a roles (`PurchaseTokens`); no
/// hay un literal visual acá.
class PurchaseAssistantEvidenceRow extends StatelessWidget {
  const PurchaseAssistantEvidenceRow({super.key, required this.evidence});

  final PurchaseAssistantEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final evidenceDetail = evidence.detail;
    final detail = <String>[
      if (evidenceDetail != null) evidenceDetail,
      if (evidence.chips.isNotEmpty) evidence.chips.join(' · '),
    ].where((part) => part.trim().isNotEmpty).join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        evidence.title,
        style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
      ),
      subtitle: detail.isEmpty
          ? null
          : Text(
              detail,
              style: PurchaseType.body.copyWith(color: tokens.inkMuted),
            ),
    );
  }
}

/// **Qué está resolviendo el operador.** Un solo valor, no cinco banderas.
///
/// El módulo tenía `_showScenarios`, `_selectingBasket`, `_selectedNeed`,
/// `_openSupplierId` y `_returnToScenarios` como campos independientes, escritos
/// a mano en más de treinta lugares. Nada garantizaba que una combinación
/// existiera de verdad, y dos caminos al MISMO escenario dejaban cromos
/// distintos: entrar desde la cola de prioridad no tocaba `_selectedNeed`, así
/// que la barra de necesidad no salía; entrar desde el modo canasta venía con
/// una necesidad ya elegida, y la barra salía mostrando **una necesidad ajena a
/// la canasta**, con el contador del paso leyendo la de ella.
///
/// Con un valor sellado esa combinación no se puede escribir: el foco de
/// canasta no tiene una necesidad individual que mostrar, y el cuerpo, la barra
/// y el contador se derivan todos de aquí.
///
/// Las cuatro etapas (`PurchaseStep`) son el otro eje y siguen siendo suyas:
/// una canasta también pasa por Stock interno, Proveedores y Plan. Single need
/// y canasta son modos del contenido, no pantallas de otro sistema.
sealed class PurchaseFocus {
  const PurchaseFocus();

  /// El foco al que vuelve el «volver», o nulo si este es la raíz.
  PurchaseFocus? get parent;
}

/// La cola de prioridad y la captura: todavía no se eligió nada.
final class PurchaseNoFocus extends PurchaseFocus {
  const PurchaseNoFocus();

  @override
  PurchaseFocus? get parent => null;
}

/// Una necesidad. `parent` recuerda de dónde se entró — desde la comparación de
/// una canasta, volver tiene que devolver a esa canasta y no a la lista.
final class PurchaseNeedFocus extends PurchaseFocus {
  const PurchaseNeedFocus(this.needId, {PurchaseFocus? from, this.fromStep})
      : parent = from;

  final String needId;

  /// La etapa en la que estaba el foco anterior cuando se entró acá.
  ///
  /// **Volver devuelve lo que el operador estaba mirando**, no lo reprocesa: si
  /// salió de la comparación de la canasta para precisar una línea, el volver
  /// tiene que traer la comparación, no hacerlo entrar de nuevo por bodega.
  /// Sin esto, la regla de «stock interno primero» —que es correcta al
  /// *entrar*— se aplicaba también al retroceder y le comía el resultado.
  final PurchaseStep? fromStep;

  @override
  final PurchaseFocus? parent;
}

/// De dos a ocho necesidades resueltas juntas.
///
/// `scenarios` distingue las dos caras del mismo trabajo: elegir cuáles entran,
/// y comparar el resultado. No son dos pantallas.
final class PurchaseBasketFocus extends PurchaseFocus {
  const PurchaseBasketFocus._({
    required this.needIds,
    required this.scenarios,
    required this.from,
  });

  /// **La única forma de construirlo**, porque aplica la regla del dominio:
  /// una canasta con menos de dos líneas no tiene nada que comparar, así que
  /// vuelve a la selección en vez de quedar en una comparación imposible.
  factory PurchaseBasketFocus.resolve(
    Iterable<String> needIds, {
    required bool scenarios,
    PurchaseFocus? from,
  }) {
    final ids = Set<String>.unmodifiable(needIds.take(basketMaxNeeds));
    return PurchaseBasketFocus._(
      needIds: ids,
      scenarios: scenarios && ids.length >= basketMinNeeds,
      from: from,
    );
  }

  /// Lo que estaba abierto antes de armar la canasta. Salir de ella devuelve
  /// ahí: armar una canasta y arrepentirse no puede costarle al operador la
  /// necesidad que ya tenía en pantalla.
  final PurchaseFocus? from;

  /// El rango que el servidor resuelve en una llamada.
  static const int basketMinNeeds = 2;
  static const int basketMaxNeeds = 8;

  final Set<String> needIds;
  final bool scenarios;

  bool get canCompare => needIds.length >= basketMinNeeds;

  /// **Cambiar la membresía deja la comparación sin valor, y el tipo lo sabe.**
  ///
  /// Una comparación es la respuesta a una lista concreta. Si esa lista cambia,
  /// lo que está en pantalla dejó de describirla: no es una vista un poco
  /// desactualizada, es la respuesta a otra pregunta. Conservar `scenarios` acá
  /// permitía volver al paso Necesidad desde una comparación, sacar o agregar
  /// una línea, y regresar a Proveedores para leer el reparto de la canasta
  /// **anterior** como si fuera el de la nueva.
  ///
  /// Por eso el cambio de membresía devuelve a la selección: comparar otra vez
  /// es un acto explícito del operador. Quien edita la canasta desde dentro de
  /// la comparación —la pestaña Líneas— vuelve a pedir la comparación en la
  /// misma acción, que es su intención evidente; lo que no puede pasar es que
  /// nadie la pida y la pantalla siga afirmando el resultado viejo.
  PurchaseBasketFocus withNeeds(Iterable<String> ids) {
    final next = PurchaseBasketFocus.resolve(
      ids,
      scenarios: false,
      from: from,
    );
    // Una «modificación» que no modifica nada no invalida nada.
    if (scenarios && _sameNeeds(next.needIds)) {
      return PurchaseBasketFocus.resolve(ids, scenarios: true, from: from);
    }
    return next;
  }

  bool _sameNeeds(Set<String> other) =>
      other.length == needIds.length && other.every(needIds.contains);

  PurchaseBasketFocus comparing(bool value) =>
      PurchaseBasketFocus.resolve(needIds, scenarios: value, from: from);

  /// La pila completa: la comparación vuelve a la selección, y la selección
  /// vuelve a lo que hubiera antes de armarla.
  @override
  PurchaseFocus? get parent => scenarios
      ? PurchaseBasketFocus.resolve(needIds, scenarios: false, from: from)
      : from;
}

/// La ficha de un proveedor, montada **sobre** el foco al que se vuelve.
///
/// No reemplaza lo que se estaba resolviendo: mirar a un proveedor no puede
/// perder la necesidad ni la canasta, que es exactamente por lo que esta ficha
/// es embebida y no una ruta.
final class PurchaseSupplierFocus extends PurchaseFocus {
  const PurchaseSupplierFocus({required this.supplierId, required this.under});

  final String supplierId;
  final PurchaseFocus under;

  @override
  PurchaseFocus? get parent => under;
}

/// Lo que el foco dice de sí mismo, sin que cada pantalla lo vuelva a deducir.
extension PurchaseFocusReading on PurchaseFocus {
  /// El foco de trabajo por debajo de la ficha del proveedor.
  ///
  /// La ficha se turna con la tabla en el mismo panel: la necesidad o la
  /// canasta que se está resolviendo siguen mandando el cromo.
  PurchaseFocus get working {
    final self = this;
    return self is PurchaseSupplierFocus ? self.under.working : self;
  }

  /// La necesidad individual, o nulo. **Una canasta no tiene una**, y por eso
  /// la barra de necesidad no puede contradecirla.
  String? get needId {
    final self = working;
    return self is PurchaseNeedFocus ? self.needId : null;
  }

  Set<String> get basketNeedIds {
    final self = working;
    return self is PurchaseBasketFocus ? self.needIds : const <String>{};
  }

  bool get isSelectingBasket => working is PurchaseBasketFocus;

  bool get showsScenarios {
    final self = working;
    return self is PurchaseBasketFocus && self.scenarios;
  }

  String? get openSupplierId {
    final self = this;
    return self is PurchaseSupplierFocus ? self.supplierId : null;
  }
}
