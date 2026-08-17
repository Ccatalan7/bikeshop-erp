library;

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../models/intelligent_purchasing_models.dart';
import '../widgets/purchase_visual_language.dart';
import 'intelligent_purchasing_surfaces.dart';

/// Paso 3 (proveedores) y detalle de candidato — handoff-t23.
///
/// Reglas de estado que estas superficies hacen cumplir:
/// - «Cumple» es texto secundario: no se pinta en verde ni se repite como
///   cápsula en cada fila;
/// - sólo la excepción destaca (`Revisar` en warning, `Evidencia débil` en
///   danger, `Sin evaluar` en secundario);
/// - la edad de evidencia es texto mono y sólo pasa a cápsula a los 60 días o
///   con evidencia débil;
/// - la disponibilidad del proveedor nunca se afirma desde el historial.

/// Estado técnico visible de un candidato.
enum CandidateCompliance { meets, review, weakEvidence, unevaluated }

CandidateCompliance complianceOf(PurchaseCandidate candidate) {
  switch (candidate.evidenceQuality) {
    case 'complete':
      return CandidateCompliance.meets;
    case 'partial':
      return CandidateCompliance.review;
    case 'unevaluated':
      return CandidateCompliance.unevaluated;
    default:
      return CandidateCompliance.weakEvidence;
  }
}

/// Sólo la excepción se dibuja como cápsula; `Cumple` viaja como texto.
class ComplianceLabel extends StatelessWidget {
  const ComplianceLabel({super.key, required this.compliance});

  final CandidateCompliance compliance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    switch (compliance) {
      case CandidateCompliance.meets:
        return Text(
          'Cumple',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case CandidateCompliance.unevaluated:
        return Text(
          'Sin evaluar',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case CandidateCompliance.review:
        return _ExceptionCapsule(tone: roles.warning, label: 'Revisar');
      case CandidateCompliance.weakEvidence:
        return _ExceptionCapsule(tone: roles.danger, label: 'Evidencia débil');
    }
  }
}

class _ExceptionCapsule extends StatelessWidget {
  const _ExceptionCapsule({required this.tone, required this.label});

  final VinabikeSemanticTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.container,
        border: Border.all(color: tone.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: tone.onContainer),
      ),
    );
  }
}

/// Edad de evidencia: texto mono; cápsula sólo en la excepción.
class EvidenceAgeLabel extends StatelessWidget {
  const EvidenceAgeLabel({super.key, required this.candidate});

  final PurchaseCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final stale = candidate.evidenceAgeDays >= 60;
    final weak = candidate.evidenceQuality == 'weak';
    final text = candidate.evidenceAgeDays <= 0
        ? 'sin fecha'
        : 'hace ${candidate.evidenceAgeDays} días';
    if (stale || weak) {
      return _ExceptionCapsule(tone: roles.warning, label: text);
    }
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'IBM Plex Mono',
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

String marginLabel(PurchaseCandidate candidate) {
  final ratio = candidate.projectedGrossMarginRatio;
  // Sin precio vigente el margen es «sin base», nunca cero.
  if (ratio == null) return 'sin base';
  return '${(ratio * 100).toStringAsFixed(1)}%';
}

/// Tabla de comparación (desktop/tablet). Cabecera sunken, hairline por fila,
/// selección con inset del rol de acción — anatomía `TB-01` de la guía.
class ProviderCandidatesTable extends StatelessWidget {
  const ProviderCandidatesTable({
    super.key,
    required this.candidates,
    required this.selectedCandidateId,
    required this.onSelect,
    required this.showOptionalColumns,
  });

  final List<PurchaseCandidate> candidates;
  final String? selectedCandidateId;
  final ValueChanged<PurchaseCandidate> onSelect;
  final bool showOptionalColumns;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    // La comparación es un objeto: cabecera hundida y filas separadas por su
    // línea interna, todo dentro del mismo borde. Suelta sobre el fondo, la
    // tabla no se distinguía de la página.
    return PurchasePanel(
      padded: false,
      child: Column(
        key: const ValueKey('provider-candidates-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: tokens.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              children: [
                const SizedBox(width: 26),
                const _HeadCell(flex: 22, label: 'Producto'),
                const _HeadCell(flex: 10, label: 'Cumplimiento'),
                const _HeadCell(
                  flex: 10,
                  label: 'Costo aterrizado',
                  alignEnd: true,
                ),
                const _HeadCell(flex: 8, label: 'Margen', alignEnd: true),
                const _HeadCell(flex: 9, label: 'Evidencia', alignEnd: true),
                if (showOptionalColumns) ...[
                  const _HeadCell(flex: 8, label: 'Gama', leadingGap: 10),
                  const _HeadCell(
                    flex: 8,
                    label: 'Historial',
                    alignEnd: true,
                  ),
                ],
              ],
            ),
          ),
          for (final candidate in candidates)
            _CandidateTableRow(
              candidate: candidate,
              selected: candidate.candidateId == selectedCandidateId,
              showOptionalColumns: showOptionalColumns,
              onSelect: () => onSelect(candidate),
            ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell({
    required this.flex,
    required this.label,
    this.alignEnd = false,
    this.leadingGap = 0,
  });

  final int flex;
  final String label;
  final bool alignEnd;

  /// Separación previa, para que dos cabeceras contiguas no se lean pegadas.
  final double leadingGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: leadingGap),
        child: Text(
          label.toUpperCase(),
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PurchaseType.label.copyWith(
            letterSpacing: 0.7,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// La banda de gama, en la palabra del negocio.
///
/// Sin banda no se escribe «—» a secas: se dice que todavía no alcanza la
/// evidencia, porque no saber no es lo mismo que no calzar.
String _gamaLabel(PurchaseCandidate candidate) {
  return switch (candidate.gama) {
    'economica' => 'Económica',
    'media' => 'Media',
    'alta' => 'Alta',
    _ => 'Sin banda aún',
  };
}

class _CandidateTableRow extends StatelessWidget {
  const _CandidateTableRow({
    required this.candidate,
    required this.selected,
    required this.showOptionalColumns,
    required this.onSelect,
  });

  final PurchaseCandidate candidate;
  final bool selected;
  final bool showOptionalColumns;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${candidate.productName}, ${candidate.supplierName}',
      child: InkWell(
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? roles.selectionContainer : null,
            border: Border(
              top: BorderSide(color: PurchaseTokens.of(context).hair),
              left: BorderSide(
                color:
                    selected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 26,
                child: RadioGroup<bool>(
                  groupValue: selected,
                  onChanged: (_) => onSelect(),
                  child: const Radio<bool>(
                    visualDensity: VisualDensity.compact,
                    value: true,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              Expanded(
                flex: 22,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Cuando la celda ya no puede hospedar foto + identidad, la
                    // identidad gana: la miniatura es apoyo, no el dato.
                    final showMedia = constraints.maxWidth >=
                        PurchaseSurfaceGeometry.mediaTableRow + 96;
                    return Row(
                      children: [
                        if (showMedia) ...[
                          ProductMediaTile(
                            media: candidate.media,
                            name: candidate.productName,
                            size: PurchaseSurfaceGeometry.mediaTableRow,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                candidate.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                candidate.supplierName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PurchaseType.meta.copyWith(
                                    color: PurchaseTokens.of(context).inkMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                flex: 10,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ComplianceLabel(compliance: complianceOf(candidate)),
                ),
              ),
              Expanded(
                flex: 10,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LandedCostText(candidate: candidate),
                ),
              ),
              Expanded(
                flex: 8,
                child: Text(
                  marginLabel(candidate),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'IBM Plex Mono',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 9,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: EvidenceAgeLabel(candidate: candidate),
                ),
              ),
              if (showOptionalColumns) ...[
                Expanded(
                  flex: 8,
                  child: Padding(
                    // La columna venía pegada a Evidencia: en la cabecera se
                    // leía «EVIDENCIAGAMA».
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      // Gama es la **banda**, no la marca. La marca ya viaja
                      // bajo el nombre del producto; repetirla acá ocupaba la
                      // columna que el dueño pidió para decidir por gama.
                      _gamaLabel(candidate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            candidate.gama == null || !candidate.gamaIsConfident
                                ? PurchaseTokens.of(context).inkFaint
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 8,
                  child: Text(
                    '${candidate.purchaseCount} compras',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'IBM Plex Mono',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LandedCostText extends StatelessWidget {
  const _LandedCostText({required this.candidate});

  final PurchaseCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cost = candidate.latestLandedUnitCostNet;
    if (cost == null) {
      return Text(
        'sin evaluar',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        VbMoneyText(cost),
        if (candidate.currency != 'CLP')
          Text(
            candidate.currency,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Card de decisión para teléfono. No es la fila comprimida.
class ProviderCandidateCard extends StatelessWidget {
  const ProviderCandidateCard({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onSelect,
  });

  final PurchaseCandidate candidate;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compliance = complianceOf(candidate);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            // El prototipo marca la card elegida con el **borde** de acento y
            // conserva la superficie: `surface` + `actBorder`. Teñir la card
            // entera y cerrarla con el acento pleno pesaba el doble.
            color: PurchaseTokens.of(context).surface,
            border: Border.all(
              color: selected
                  ? PurchaseTokens.of(context).actBorder
                  : PurchaseTokens.of(context).border,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(PurchaseMetrics.panelRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductMediaTile(
                    media: candidate.media,
                    name: candidate.productName,
                    size: PurchaseSurfaceGeometry.mediaPhoneCard,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          candidate.supplierName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PurchaseType.meta.copyWith(
                              color: PurchaseTokens.of(context).inkMuted),
                        ),
                      ],
                    ),
                  ),
                  // Cápsula sólo si es excepción.
                  if (compliance == CandidateCompliance.review ||
                      compliance == CandidateCompliance.weakEvidence) ...[
                    const SizedBox(width: 8),
                    ComplianceLabel(compliance: compliance),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MetricBlock(
                      label: 'COSTO ATERRIZADO',
                      alignEnd: false,
                      child: _LandedCostText(candidate: candidate),
                    ),
                  ),
                  Expanded(
                    child: _MetricBlock(
                      label: 'MARGEN',
                      alignEnd: true,
                      child: Text(
                        marginLabel(candidate),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'IBM Plex Mono',
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Evidencia como texto secundario legible, nunca cápsula.
              Text(
                [
                  candidate.evidenceAgeDays > 0
                      ? 'Compra hace ${candidate.evidenceAgeDays} días'
                      : 'Sin fecha de compra',
                  '${candidate.purchaseCount} compras',
                  'stock no verificado',
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.child,
    required this.alignEnd,
  });

  final String label;
  final Widget child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PurchaseType.label.copyWith(
            letterSpacing: 0.7,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

/// Detalle del candidato.
///
/// El mismo panel se monta como split pane (desktop), edge sheet (tablet) y
/// bottom sheet (teléfono). **Nunca lleva scrim**: el click-catcher del host es
/// transparente y ocupa sólo el área libre.
class CandidateInspectorPanel extends StatelessWidget {
  const CandidateInspectorPanel({
    super.key,
    required this.candidate,
    required this.quantity,
    required this.onClose,
    required this.onAddToPlan,
    required this.onOpenSupplier,
    required this.adding,
    required this.alreadyInPlan,
  });

  final PurchaseCandidate candidate;
  final double quantity;
  final VoidCallback onClose;
  final VoidCallback onAddToPlan;
  final VoidCallback? onOpenSupplier;
  final bool adding;
  final bool alreadyInPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final compliance = complianceOf(candidate);
    final cost = candidate.latestLandedUnitCostNet;

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        key: const ValueKey('candidate-inspector'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductMediaTile(
                  media: candidate.media,
                  name: candidate.productName,
                  size: PurchaseSurfaceGeometry.mediaInspector,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.productName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontFamily: 'Poppins'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Frame 23: proveedor y su relación comercial en la
                        // misma línea. «Mayorista» sólo aparece cuando el
                        // candidato no está marcado como compra local
                        // confirmada; no se inventa una categoría de proveedor.
                        candidate.isConfirmedLocal
                            ? '${candidate.supplierName} · Compra local'
                            : candidate.supplierName,
                        style: PurchaseType.meta.copyWith(
                            color: PurchaseTokens.of(context).inkMuted),
                      ),
                      const SizedBox(height: 8),
                      // Única cápsula persistente del panel.
                      ComplianceLabel(compliance: compliance),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('close-candidate-inspector'),
                  tooltip: 'Cerrar detalle',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BigMetric(
                    label: 'COSTO ATERRIZADO',
                    value: cost == null ? 'sin evaluar' : null,
                    money: cost,
                  ),
                ),
                Expanded(
                  child: _BigMetric(
                    label: 'MARGEN PROYECTADO',
                    value: marginLabel(candidate),
                  ),
                ),
              ],
            ),
          ),
          if (compliance != CandidateCompliance.meets ||
              candidate.currency != 'CLP') ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Banda tonal dentro del panel, no card flotante.
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: roles.warning.container,
                  border: Border.all(color: roles.warning.border),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  candidate.currency != 'CLP'
                      ? 'El costo está en ${candidate.currency}. Sin una fuente de cambio autorizada no se convierte ni se suma con CLP.'
                      : 'El cumplimiento todavía está por confirmar: falta evidencia estructurada para comparar esta opción como cifra firme.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.warning.onContainer),
                ),
              ),
            ),
          ],
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: [
                // Frame 23: primera sección del inspector, con su meta a la
                // derecha. «montaje no evaluado» no es un adorno: el análisis
                // no recibe un objeto de montaje, así que la compatibilidad
                // mecánica queda declarada como no evaluada en vez de
                // afirmarse.
                _InspectorSection(
                  title: 'Cumplimiento y compatibilidad',
                  meta: 'montaje no evaluado',
                  children: [
                    _InspectorRow(
                      label: 'Cumple los criterios de la petición',
                      value: switch (compliance) {
                        CandidateCompliance.meets => 'sí',
                        CandidateCompliance.review => 'por revisar',
                        CandidateCompliance.weakEvidence => 'evidencia débil',
                        CandidateCompliance.unevaluated => 'sin evaluar',
                      },
                    ),
                    if (candidate.brand != null)
                      _InspectorRow(label: 'Marca', value: candidate.brand!),
                    if (candidate.category != null)
                      _InspectorRow(
                        label: 'Categoría',
                        value: candidate.category!,
                      ),
                    const _InspectorRow(
                      label: 'Compatibilidad mecánica',
                      value: 'sin objeto de montaje',
                    ),
                  ],
                ),
                _InspectorSection(
                  title: 'Desglose de costo y flete',
                  meta: candidate.freightEvidence == 'complete'
                      ? 'flete clasificado'
                      : 'flete sin clasificar',
                  children: [
                    _InspectorRow(
                      label: 'Costo aterrizado unitario',
                      value: cost == null ? 'sin evaluar' : null,
                      money: cost,
                    ),
                    _InspectorRow(
                      label: 'Moneda',
                      value: candidate.currency,
                    ),
                  ],
                ),
                _InspectorSection(
                  title: 'Por qué aparece aquí',
                  meta: 'orden #${candidate.rank}',
                  children: [
                    _InspectorRow(
                      label: 'Compras observadas',
                      value: '${candidate.purchaseCount}',
                    ),
                    _InspectorRow(
                      label: 'Calidad de evidencia',
                      value: switch (candidate.evidenceQuality) {
                        'complete' => 'completa',
                        'partial' => 'parcial',
                        _ => 'débil',
                      },
                    ),
                  ],
                ),
                _InspectorSection(
                  title: 'Historial y evidencia',
                  meta: candidate.evidenceAgeDays > 0
                      ? '${candidate.evidenceAgeDays} días'
                      : 'sin fecha',
                  children: [
                    const _InspectorRow(
                      label: 'Disponibilidad del proveedor',
                      value: 'no verificada',
                    ),
                    if (candidate.brand != null)
                      _InspectorRow(label: 'Marca', value: candidate.brand!),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2)} u.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'IBM Plex Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (onOpenSupplier != null)
                  TextButton(
                    onPressed: onOpenSupplier,
                    child: const Text('Abrir proveedor'),
                  ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  // Único botón sólido del panel.
                  child: FilledButton(
                    key: const ValueKey('add-candidate-to-plan'),
                    onPressed: adding || alreadyInPlan ? null : onAddToPlan,
                    child: Text(
                      alreadyInPlan ? 'Ya está en el plan' : 'Agregar al plan',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({required this.label, this.value, this.money});

  final String label;
  final String? value;
  final double? money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PurchaseType.label.copyWith(
            letterSpacing: 0.7,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (money != null)
          DefaultTextStyle.merge(
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: VbMoneyText(money!),
          )
        else
          Text(
            value ?? '—',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'IBM Plex Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _InspectorSection extends StatelessWidget {
  const _InspectorSection({
    required this.title,
    required this.meta,
    required this.children,
  });

  final String title;
  final String meta;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        // Las dos piezas flexionan: con el inspector en su ancho mínimo un
        // título largo junto a su meta desbordaba la cabecera de la sección.
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Text(
                title,
                style: PurchaseType.panelTitle
                    .copyWith(color: PurchaseTokens.of(context).ink),
              ),
            ),
            const SizedBox(width: 8),
            // Meta a la derecha como texto secundario, nunca cápsula.
            Expanded(
              flex: 5,
              child: Text(
                meta,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow({required this.label, this.value, this.money});

  final String label;
  final String? value;
  final double? money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // El valor también flexiona: con el inspector en su ancho mínimo (330)
      // un texto largo desbordaba la fila en vez de envolverse.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          if (money != null)
            VbMoneyText(money!)
          else
            Expanded(
              flex: 4,
              child: Text(
                value ?? '—',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

/// Estado vacío del plan: inline y anclado arriba, en la misma superficie.
///
/// Prohibido y por eso ausente: card centrada, borde punteado, isla flotante,
/// scrim y una segunda acción que repita el destino de la primaria.
class PlanEmptyInline extends StatelessWidget {
  const PlanEmptyInline({
    super.key,
    required this.compact,
    required this.onChooseCandidate,
    required this.onRegisterLocalPurchase,
  });

  final bool compact;
  final VoidCallback onChooseCandidate;
  final VoidCallback onRegisterLocalPurchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = SizedBox(
      height: PurchaseSurfaceGeometry.phoneStepControl,
      width: compact ? double.infinity : null,
      child: FilledButton(
        key: const ValueKey('plan-empty-choose-candidate'),
        onPressed: onChooseCandidate,
        child: const Text('Elegir candidato'),
      ),
    );
    final secondary = SizedBox(
      height: PurchaseSurfaceGeometry.phoneStepControl,
      width: compact ? double.infinity : null,
      child: TextButton(
        key: const ValueKey('register-local-purchase'),
        onPressed: onRegisterLocalPurchase,
        child: const Text('Registrar compra local'),
      ),
    );

    return Column(
      key: const ValueKey('plan-empty-inline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          // Cabeceras reales del plan: el vacío ocurre dentro de la tabla.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PurchaseTokens.of(context).hair),
              ),
            ),
            child: const Row(
              children: [
                _HeadCell(flex: 24, label: 'Producto'),
                _HeadCell(flex: 14, label: 'Proveedor'),
                _HeadCell(flex: 8, label: 'Cantidad', alignEnd: true),
                _HeadCell(flex: 10, label: 'Subtotal', alignEnd: true),
              ],
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.only(top: compact ? 14 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Único acento de la superficie.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // `actSoft` + `actBorder`: el relleno de acento cierra con un
                  // borde de su misma familia, no con el contorno neutro.
                  color: PurchaseTokens.of(context).actSoft,
                  border: Border.all(
                    color: PurchaseTokens.of(context).actBorder,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.list_alt_outlined,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Todavía no hay productos elegidos',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Elige un candidato en Proveedores y agrégalo aquí. Nada se compra ni se emite hasta que confirmes.',
                      style: PurchaseType.meta
                          .copyWith(color: PurchaseTokens.of(context).inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 8), secondary],
          )
        else
          // Reflowa en vez de desbordar cuando el panel del plan se estrecha.
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [primary, secondary],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Superficies publicadas en handoff-t23 que faltaban: controles de resultados,
// análisis parcial, sin coincidencias, cabecera del plan borrador, canasta.
// Cada una cita el frame del que sale su composición.
// ─────────────────────────────────────────────────────────────────────────────

/// Stepper numérico `− n +` de los frames 24 (plan) y 28 (canasta).
///
/// No es un campo de texto disfrazado: el valor se muestra centrado en mono y
/// los dos controles tienen área táctil propia. El teclado sigue funcionando
/// porque cada botón es un `IconButton` real con tooltip.
class PurchaseQuantityStepper extends StatelessWidget {
  const PurchaseQuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 9999,
    this.enabled = true,
    this.unitLabel,
    this.semanticsLabel,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;
  final bool enabled;
  final String? unitLabel;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrease = enabled && onChanged != null && value > min;
    final canIncrease = enabled && onChanged != null && value < max;

    return Semantics(
      label: semanticsLabel ?? 'Cantidad',
      value: '$value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: canDecrease ? 'Quitar una unidad' : 'Ya está en el mínimo',
            onPressed: canDecrease ? () => onChanged!(value - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$value',
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'IBM Plex Mono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip:
                canIncrease ? 'Agregar una unidad' : 'Ya está en el máximo',
            onPressed: canIncrease ? () => onChanged!(value + 1) : null,
            icon: const Icon(Icons.add, size: 16),
          ),
          if (unitLabel != null) ...[
            const SizedBox(width: 2),
            Text(
              unitLabel!,
              style: PurchaseType.label.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Controles del encabezado de resultados.
///
/// Frames 03 y 26 (desktop/tablet): dos desplegables anclados, `Perfil · <x>` y
/// `Vista`. Frames 16 y 20 (teléfono): un único `Orden y filtros` que abre una
/// hoja inferior con todo dentro. Ningún desplegable usa velo.
class ProviderResultControls extends StatelessWidget {
  const ProviderResultControls({
    super.key,
    required this.compact,
    required this.profileValue,
    required this.profileOptions,
    required this.onProfileChanged,
    required this.viewValue,
    required this.viewOptions,
    required this.onViewChanged,
    this.enabled = true,
  });

  final bool compact;
  final String profileValue;
  final Map<String, String> profileOptions;
  final ValueChanged<String> onProfileChanged;
  final String viewValue;
  final Map<String, String> viewOptions;
  final ValueChanged<String> onViewChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // Frames 16 y 20: un único control reúne perfil **y** filtros. Antes sólo
      // ofrecía el perfil, así que en teléfono no había forma de alcanzar el
      // filtro de compatibilidad: el control existía pero la mitad de su
      // promesa no. Se ancla al propio botón; `showModalBottomSheet` pinta velo
      // y este módulo no lo admite.
      return _AnchoredMenuButton(
        menuId: 'provider-sort-and-filters',
        label: 'Orden y filtros',
        enabled: enabled,
        sections: [
          _MenuSection(
            title: 'Perfil',
            value: profileValue,
            options: profileOptions,
            onSelected: onProfileChanged,
          ),
          _MenuSection(
            title: 'Vista',
            value: viewValue,
            options: viewOptions,
            onSelected: onViewChanged,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _AnchoredMenuButton(
          menuId: 'provider-profile-menu',
          label: 'Perfil · ${profileOptions[profileValue] ?? profileValue}',
          enabled: enabled,
          sections: [
            _MenuSection(
              value: profileValue,
              options: profileOptions,
              onSelected: onProfileChanged,
            ),
          ],
        ),
        _AnchoredMenuButton(
          menuId: 'provider-view-menu',
          label: 'Vista',
          enabled: enabled,
          sections: [
            _MenuSection(
              value: viewValue,
              options: viewOptions,
              onSelected: onViewChanged,
            ),
          ],
        ),
      ],
    );
  }
}

/// Un grupo de opciones excluyentes dentro de un desplegable anclado.
class _MenuSection {
  const _MenuSection({
    required this.value,
    required this.options,
    required this.onSelected,
    this.title,
  });

  final String? title;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onSelected;
}

/// Desplegable anclado al propio botón.
///
/// `PopupMenuButton` ancla el panel al control y su barrera es transparente:
/// cumple la regla del módulo de que ningún panel atenúa el fondo.
///
/// Cada opción lleva key propia (`<menuId>-option-<valor>`). No es adorno para
/// pruebas: es la identidad estable del control, y evita que un tap tenga que
/// buscar por texto dentro de un `CheckedPopupMenuItem`, donde el centro del
/// `Text` no siempre es lo que recibe el hit-test.
class _AnchoredMenuButton extends StatelessWidget {
  const _AnchoredMenuButton({
    required this.menuId,
    required this.label,
    required this.sections,
    required this.enabled,
  });

  final String menuId;
  final String label;
  final List<_MenuSection> sections;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      key: ValueKey<String>(menuId),
      enabled: enabled,
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: (raw) {
        final split = raw.indexOf(':');
        final index = int.parse(raw.substring(0, split));
        sections[index].onSelected(raw.substring(split + 1));
      },
      itemBuilder: (context) => [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const PopupMenuDivider(),
          if (sections[index].title != null)
            // Rótulo del grupo: deshabilitado a propósito, no es una acción.
            PopupMenuItem<String>(
              enabled: false,
              height: 32,
              child: Text(
                sections[index].title!.toUpperCase(),
                style: PurchaseType.label.copyWith(
                  letterSpacing: 0.7,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final entry in sections[index].options.entries)
            CheckedPopupMenuItem<String>(
              key: ValueKey<String>('$menuId-option-${entry.key}'),
              value: '$index:${entry.key}',
              checked: entry.key == sections[index].value,
              child: Text(entry.value),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        // El rótulo flexiona: «Perfil · Mayor rentabilidad» no cabe cuando el
        // inspector estrecha la cabecera de resultados, y un `Row` con texto
        // sin flex desborda en vez de recortar.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Frame 09 — análisis parcial.
///
/// Banda tonal dentro del flujo de resultados. El mensaje principal está en
/// lenguaje del negocio; rondas y KiB viven detrás de un disclosure y nunca en
/// la frase principal.
class PartialAnalysisNotice extends StatelessWidget {
  const PartialAnalysisNotice({
    super.key,
    required this.evaluated,
    required this.total,
    required this.pendingLabels,
    required this.onContinue,
    this.busy = false,
    this.technicalDetail,
  });

  final int evaluated;
  final int total;
  final List<String> pendingLabels;
  final VoidCallback onContinue;
  final bool busy;
  final String? technicalDetail;

  String get _pendingSentence {
    if (pendingLabels.isEmpty) return '';
    if (pendingLabels.length == 1) return ' Falta ${pendingLabels.single}.';
    final head = pendingLabels.sublist(0, pendingLabels.length - 1).join(', ');
    return ' Faltan $head y ${pendingLabels.last}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      key: const ValueKey('partial-analysis-notice'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: roles.warning.container,
        border: Border.all(color: roles.warning.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evaluamos $evaluated de $total opciones.$_pendingSentence '
            'Puedes continuar sin perder lo ya revisado.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: roles.warning.onContainer),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('continue-partial-analysis'),
              onPressed: busy ? null : onContinue,
              child: const Text('Continuar análisis'),
            ),
          ),
          if (technicalDetail != null) ...[
            const SizedBox(height: 4),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const ValueKey('partial-analysis-technical-detail'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'Detalle técnico',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.warning.onContainer),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      technicalDetail!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: roles.warning.onContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Frame 10 — ninguna opción visible por filtros.
///
/// Ocupa el ancho completo de la región de resultados sobre fondo hundido, con
/// filetes arriba y abajo. Sin card, sin borde punteado, sin centrado y sin
/// sombra: el owner rechazó la isla flotante para este estado.
class NoMatchSurface extends StatelessWidget {
  const NoMatchSurface({
    super.key,
    required this.causeSentence,
    required this.onClearFilters,
    required this.onIncludeUnconfirmed,
    this.perCandidateExplanations = const <String>[],
  });

  final String causeSentence;
  final VoidCallback onClearFilters;
  final VoidCallback onIncludeUnconfirmed;
  final List<String> perCandidateExplanations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('no-match-surface'),
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      foregroundDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: PurchaseTokens.of(context).hair),
          bottom: BorderSide(color: PurchaseTokens.of(context).hair),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ninguna opción cumple todos los filtros',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            causeSentence,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: const ValueKey('clear-provider-filters'),
                onPressed: onClearFilters,
                child: const Text('Quitar filtros'),
              ),
              TextButton(
                key: const ValueKey('include-unconfirmed-compatibility'),
                onPressed: onIncludeUnconfirmed,
                child: const Text(
                  'Incluir opciones con compatibilidad por confirmar',
                ),
              ),
            ],
          ),
          if (perCandidateExplanations.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const ValueKey('which-filter-hides-each'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Qué filtro oculta cada candidato',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  for (final explanation in perCandidateExplanations)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          explanation,
                          style: PurchaseType.meta.copyWith(
                              color: PurchaseTokens.of(context).inkMuted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Frames 07, 18, 21 y 24 — cabecera del plan con líneas.
///
/// «Plan borrador» con su recuento y el estado de compra como texto secundario,
/// y a la derecha dos acciones secundarias. La primaria del plan no vive aquí:
/// está al pie, junto a los totales.
class PlanDraftHeader extends StatelessWidget {
  const PlanDraftHeader({
    super.key,
    required this.lineCount,
    required this.compact,
    required this.onBackToCompare,
    required this.onRegisterLocalPurchase,
    this.purchasedLabel = 'nada comprado',
  });

  final int lineCount;
  final bool compact;
  final VoidCallback onBackToCompare;
  final VoidCallback onRegisterLocalPurchase;
  final String purchasedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = <Widget>[
      OutlinedButton(
        key: const ValueKey('plan-back-to-compare'),
        onPressed: onBackToCompare,
        child: const Text('Volver a comparar'),
      ),
      OutlinedButton(
        key: const ValueKey('plan-register-local-purchase'),
        onPressed: onRegisterLocalPurchase,
        child: const Text('Registrar compra local'),
      ),
    ];

    final title = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        Text(
          'Plan borrador',
          style: PurchaseType.panelTitle
              .copyWith(color: PurchaseTokens.of(context).ink),
        ),
        Text(
          '$lineCount ${lineCount == 1 ? 'línea' : 'líneas'} · $purchasedLabel',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return Padding(
      key: const ValueKey('plan-draft-header'),
      padding: const EdgeInsets.only(bottom: 12),
      // Wrap plano en las dos tallas. Un `Row` con anchos intrínsecos —o un
      // Wrap anidado— desborda en cuanto el panel del plan se estrecha, que es
      // justo lo que ocurre con el inspector abierto. Cada pieza reflowa sola:
      // en ancho quedan en una línea como el frame 07/24, y en teléfono caen a
      // la siguiente como el frame 18/21.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          title,
          if (compact) const SizedBox(width: double.infinity, height: 0),
          ...actions,
        ],
      ),
    );
  }
}

/// Frames 07 y 24 — estado de evidencia del grupo, siempre como texto.
///
/// «evidencia completa» / «evidencia parcial» a la derecha del nombre del
/// proveedor. Nunca cápsula: no es una excepción, es metadato.
class PlanGroupEvidenceText extends StatelessWidget {
  const PlanGroupEvidenceText({super.key, required this.complete});

  final bool complete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      complete ? 'evidencia completa' : 'evidencia parcial',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Frame 24 — disclosure por línea del plan.
///
/// **Decisión registrada:** el frame muestra «Alternativa y nota», pero
/// `PurchasePlanLine` no tiene campo de nota ni de alternativa guardada, y este
/// módulo no crea columnas. Un campo de texto que se pierde al recargar sería
/// una promesa falsa, así que el disclosure conserva su sitio y su rótulo
/// verdadero —«Evidencia de la línea»— y muestra los datos que la línea sí
/// trae: disponibilidad declarada, moneda, costo unitario y base del margen.
class PlanLineEvidenceNote extends StatelessWidget {
  const PlanLineEvidenceNote({
    super.key,
    required this.lineId,
    required this.supplierAvailability,
    required this.currency,
    required this.landedUnitCostNet,
    required this.projectedGrossMarginRatio,
  });

  final String lineId;
  final String supplierAvailability;
  final String currency;
  final double? landedUnitCostNet;
  final double? projectedGrossMarginRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('plan-line-evidence-$lineId'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'Evidencia de la línea',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
        children: [
          _InspectorRow(
            label: 'Disponibilidad declarada',
            value: supplierAvailability.isEmpty
                ? 'no verificada'
                : supplierAvailability,
          ),
          _InspectorRow(label: 'Moneda', value: currency),
          _InspectorRow(
            label: 'Costo aterrizado unitario',
            value: landedUnitCostNet == null ? 'sin evaluar' : null,
            money: landedUnitCostNet,
          ),
          _InspectorRow(
            label: 'Margen proyectado',
            value: projectedGrossMarginRatio == null
                // Sin precio vigente el margen no es cero: no tiene base.
                ? 'sin base'
                : '${(projectedGrossMarginRatio! * 100).toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }
}

/// Frame 20 — la canasta en teléfono se parte en dos subestados con pestañas.
///
/// Cambiar de pestaña no descarta cantidades, selección ni scroll: son dos
/// vistas del mismo borrador.
enum BasketSection { lines, scenarios }

class BasketSectionTabs extends StatelessWidget {
  const BasketSectionTabs({
    super.key,
    required this.active,
    required this.onChanged,
  });

  final BasketSection active;
  final ValueChanged<BasketSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tab(BasketSection section, String label) {
      final selected = section == active;
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: () => onChanged(section),
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            margin: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color:
                      selected ? theme.colorScheme.primary : Colors.transparent,
                  width: PurchaseSurfaceGeometry.stepActiveUnderline,
                ),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('basket-section-tabs'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PurchaseTokens.of(context).hair),
        ),
      ),
      child: Row(
        children: [
          tab(BasketSection.lines, 'Líneas'),
          tab(BasketSection.scenarios, 'Escenarios'),
        ],
      ),
    );
  }
}

/// Una línea de la petición dentro de la canasta (frame 28).
class BasketRequestLine {
  const BasketRequestLine({
    required this.id,
    required this.name,
    required this.description,
    required this.quantity,
    required this.unitLabel,
    this.precisionBlocker,
  });

  final String id;
  final String name;
  final String description;
  final int quantity;
  final String unitLabel;

  /// Cuando existe, la línea queda fuera de cobertura, costo, ranking y plan.
  /// Nunca se inventa la medida que falta.
  final String? precisionBlocker;
}

/// Frame 28 — «Líneas de la petición».
///
/// Cada fila lleva su descripción, su stepper y su unidad. Una línea sin
/// precisión material muestra la causa y su acción de resolver, y se excluye
/// del cálculo en vez de aparecer con una cifra inventada.
class BasketRequestLinesCard extends StatelessWidget {
  const BasketRequestLinesCard({
    super.key,
    required this.lines,
    required this.compact,
    required this.onChangeQuantity,
    required this.onRemoveLine,
    required this.onAddLine,
    required this.onResolvePrecision,
    this.busy = false,
  });

  final List<BasketRequestLine> lines;
  final bool compact;
  final void Function(BasketRequestLine line, int quantity) onChangeQuantity;
  final ValueChanged<BasketRequestLine> onRemoveLine;
  final VoidCallback onAddLine;
  final ValueChanged<BasketRequestLine> onResolvePrecision;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('basket-request-lines'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Líneas de la petición',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  key: const ValueKey('basket-add-line'),
                  onPressed: busy ? null : onAddLine,
                  child: const Text('Agregar línea'),
                ),
              ],
            ),
          ),
          for (final line in lines)
            _BasketRequestLineRow(
              line: line,
              compact: compact,
              busy: busy,
              onChangeQuantity: (quantity) => onChangeQuantity(line, quantity),
              onRemove: () => onRemoveLine(line),
              onResolve: () => onResolvePrecision(line),
            ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(
                'La canasta todavía no tiene líneas.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _BasketRequestLineRow extends StatelessWidget {
  const _BasketRequestLineRow({
    required this.line,
    required this.compact,
    required this.busy,
    required this.onChangeQuantity,
    required this.onRemove,
    required this.onResolve,
  });

  final BasketRequestLine line;
  final bool compact;
  final bool busy;
  final ValueChanged<int> onChangeQuantity;
  final VoidCallback onRemove;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final blocker = line.precisionBlocker;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line.name, style: theme.textTheme.titleSmall),
        if (line.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            line.description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PurchaseQuantityStepper(
          value: line.quantity,
          enabled: !busy,
          unitLabel: line.unitLabel,
          semanticsLabel: 'Cantidad de ${line.name}',
          onChanged: onChangeQuantity,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Quitar ${line.name} de la canasta',
          onPressed: busy ? null : onRemove,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    );

    final blockerBlock = blocker == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Requiere precisión · $blocker',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.warning.accent),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: ValueKey<String>('basket-resolve-${line.id}'),
                onPressed: busy ? null : onResolve,
                child: const Text('Resolver'),
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: PurchaseTokens.of(context).hair)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 8),
                controls,
                if (blockerBlock != null) ...[
                  const SizedBox(height: 8),
                  blockerBlock,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 12, child: identity),
                const SizedBox(width: 12),
                controls,
                if (blockerBlock != null) ...[
                  const SizedBox(width: 12),
                  Expanded(flex: 10, child: blockerBlock),
                ],
              ],
            ),
    );
  }
}

/// Frame 13 — captura de compra local como panel anclado.
///
/// El backend de este módulo no crea la compra: el único destino real es el
/// borrador canónico de documento de compra. Por eso la hoja **revisa y
/// prepara** lo que ese borrador acepta —tipo de documento, línea, cantidad y
/// tratamiento tributario— y dice en voz alta qué se completa allá, en vez de
/// pintar campos obligatorios que no tienen dónde guardarse.
///
/// Nunca lleva velo: el host la monta con un click-catcher transparente.
class LocalPurchaseSheet extends StatefulWidget {
  const LocalPurchaseSheet({
    super.key,
    required this.productLabel,
    required this.suggestedQuantity,
    required this.unitLabel,
    required this.onCancel,
    required this.onContinue,
    this.busy = false,
  });

  final String productLabel;
  final double suggestedQuantity;
  final String unitLabel;
  final VoidCallback onCancel;

  /// Entrega lo capturado al host, que navega al borrador canónico.
  final void Function({
    required String documentKind,
    required double quantity,
    required String treatment,
  }) onContinue;

  final bool busy;

  @override
  State<LocalPurchaseSheet> createState() => _LocalPurchaseSheetState();
}

class _LocalPurchaseSheetState extends State<LocalPurchaseSheet> {
  static const _documentKinds = <String, String>{
    'receipt': 'Boleta',
    'invoice': 'Factura',
  };

  /// Los dos valores que existen en `PurchaseTreatment`. No hay «gasto» en
  /// este enum: ofrecerlo sería prometer un tratamiento que el documento no
  /// sabe guardar.
  static const _treatments = <String, String>{
    'inventory': 'Inventario',
    'workshop_consumable': 'Consumible Taller',
  };

  late String _documentKind = 'receipt';
  late String _treatment = 'inventory';
  late final TextEditingController _quantity = TextEditingController(
    text: widget.suggestedQuantity
        .toStringAsFixed(widget.suggestedQuantity % 1 == 0 ? 0 : 2),
  );
  String? _quantityError;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_quantity.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed > 999999) {
      setState(() => _quantityError = 'Ingresa una cantidad mayor que cero.');
      return;
    }
    setState(() => _quantityError = null);
    widget.onContinue(
      documentKind: _documentKind,
      quantity: parsed,
      treatment: _treatment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('local-purchase-sheet'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Registrar compra local',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontFamily: 'Poppins'),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close-local-purchase-sheet'),
                    tooltip: 'Cerrar sin registrar',
                    onPressed: widget.busy ? null : widget.onCancel,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    widget.productLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esto no compra ni recibe nada: prepara el documento para '
                    'que lo completes y lo confirmes tú.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text('Tipo de documento', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  for (final entry in _documentKinds.entries)
                    RadioListTile<String>(
                      key: ValueKey<String>('local-purchase-kind-${entry.key}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: entry.key,
                      // ignore: deprecated_member_use
                      groupValue: _documentKind,
                      title: Text(entry.value),
                      // ignore: deprecated_member_use
                      onChanged: widget.busy
                          ? null
                          : (value) => setState(
                              () => _documentKind = value ?? 'receipt'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('local-purchase-quantity'),
                    controller: _quantity,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Cantidad (${widget.unitLabel})',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _quantityError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tratamiento tributario',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (final entry in _treatments.entries)
                    RadioListTile<String>(
                      key: ValueKey<String>(
                        'local-purchase-treatment-${entry.key}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: entry.key,
                      // ignore: deprecated_member_use
                      groupValue: _treatment,
                      title: Text(entry.value),
                      // ignore: deprecated_member_use
                      onChanged: widget.busy
                          ? null
                          : (value) =>
                              setState(() => _treatment = value ?? 'inventory'),
                    ),
                  const SizedBox(height: 12),
                  // Lo que este módulo no puede capturar se dice, no se finge.
                  Text(
                    'El proveedor local, el costo unitario neto y la moneda se '
                    'eligen en el documento, con sus buscadores reales. El '
                    'stock sólo cambia con una recepción válida.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('local-purchase-continue'),
                      onPressed: widget.busy ? null : _submit,
                      child: const Text('Abrir documento de compra'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    key: const ValueKey('local-purchase-cancel'),
                    onPressed: widget.busy ? null : widget.onCancel,
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
