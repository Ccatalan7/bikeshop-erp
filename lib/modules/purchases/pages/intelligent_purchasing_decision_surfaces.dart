library;

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_short_select.dart';
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
///
/// **Los cuatro primeros valores son compatibilidad técnica; los tres últimos,
/// calidad de la evidencia económica.** No son la misma pregunta y venían
/// mezclados: `evidenceQuality` mide qué tan firme es el historial de compra
/// —costo, flete, recencia—, no si el producto calza con lo que se pidió. Un
/// candidato que el ERP **no pudo verificar** contra los criterios llegaba a
/// pantalla como «Cumple» sólo porque su factura estaba completa. Eso es
/// exactamente lo que el contrato de esta fase prohíbe: no saber no es cumplir.
enum CandidateCompliance {
  /// `matchState = strong`: la ficha del producto confirma los criterios.
  meets,

  /// `matchState = weak`: coincide por el nombre, no por la ficha.
  meetsByName,

  /// `matchState = no_criteria`: no había criterios técnicos que comparar.
  noCriteria,

  /// `matchState = unverified`: el ERP no pudo verificarlo. Nunca «Cumple».
  unverified,

  /// Legado del candidato histórico: evidencia económica parcial.
  review,

  /// Legado: evidencia económica débil.
  weakEvidence,

  /// Legado: el ranking devolvió la opción sin alcanzar a compararla.
  unevaluated,
}

/// De dónde salió la evidencia que da por cumplidos los criterios.
///
/// **La procedencia tiene que llegar hasta la palabra.** Desde que una lectura
/// del nombre —verificada por el servidor contra el vocabulario de la ficha—
/// cuenta como prueba, una fila puede estar completa sin que exista ninguna
/// ficha, y decir «según la ficha» sería falso justo en el caso nuevo. El
/// rótulo se arma con lo que dice `matchDetail`, que es el único lugar donde
/// consta de dónde salió cada campo.
String? supplyEvidenceProvenanceLabel(List<Map<String, dynamic>> matchDetail) {
  final fuentes = <String>{
    for (final entry in matchDetail)
      if (entry['source'] != null) entry['source'].toString(),
  }..removeWhere((fuente) =>
      fuente != 'product_spec' &&
      fuente != 'name_reading' &&
      fuente != 'identity_fallback');
  if (fuentes.isEmpty) return null;
  if (fuentes.length > 1) return 'según la evidencia comprobada';
  switch (fuentes.single) {
    case 'product_spec':
      return 'según la ficha';
    case 'name_reading':
      // No es la ficha del taller: es el nombre del producto, leído y
      // comprobado contra el vocabulario que la ficha declara.
      return 'según el nombre del producto, comprobado';
    case 'identity_fallback':
      return 'según la identidad del producto';
  }
  return null;
}

CandidateCompliance complianceOf(PurchaseCandidate candidate) {
  // El candidato de la fase B2 sabe cómo calzó con la petición; el histórico
  // no, y conserva su lectura de siempre.
  if (candidate is SupplyExternalCandidate) {
    switch (candidate.matchState) {
      case 'strong':
        return CandidateCompliance.meets;
      case 'weak':
        return CandidateCompliance.meetsByName;
      case 'no_criteria':
        return CandidateCompliance.noCriteria;
      default:
        return CandidateCompliance.unverified;
    }
  }
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
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case CandidateCompliance.meetsByName:
        // No es una excepción, es una evidencia más floja: texto, no cápsula.
        return Text(
          // «Cumple» sobreafirma: el nombre coincide, la ficha no lo dice.
          'Coincide por nombre',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case CandidateCompliance.noCriteria:
        return Text(
          'Sin criterios',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case CandidateCompliance.unverified:
        // Sí es la excepción que hay que ver: el ERP no pudo comprobarlo.
        return _ExceptionCapsule(tone: roles.warning, label: 'Sin verificar');
      case CandidateCompliance.unevaluated:
        return Text(
          'Sin evaluar',
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
        // `meta`, igual que `ComplianceLabel`: las dos cápsulas del módulo
        // dicen lo mismo con la misma voz. Acá quedaba un `labelSmall` del
        // tema partido en dos líneas, que es exactamente la forma que el
        // conteo de conversiones no ve —se buscó `textTheme.` en una línea— y
        // por eso sobrevivió a la migración.
        style: PurchaseType.meta.copyWith(color: tone.onContainer),
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
      style: PurchaseType.metaNumeric
          .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    // Una tabla sin filas no tiene nada que encabezar. Este widget se instancia
    // dos veces —los verificados y el grupo por confirmar—, así que con cero
    // verificados la pantalla dibujaba la fila de encabezados dos veces.
    if (candidates.isEmpty) return const SizedBox.shrink();
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
                                style: PurchaseType.rowTitle,
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
                  style: PurchaseType.metricSmall.copyWith(
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
                      style: PurchaseType.meta.copyWith(
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
                    style: PurchaseType.metaNumeric.copyWith(
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
        style: PurchaseType.meta
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
            style: PurchaseType.label
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        // Frames 04/05: bajo el costo va «incluye flete» en meta (NOTES §85-87).
        // Faltaba, y sin eso el número se lee como precio de lista: el operador
        // le suma el flete de cabeza y descarta al proveedor equivocado.
        //
        // **Sólo se afirma cuando es verdad.** La misma señal que el desglose
        // ya usa —`freightEvidence == 'complete'`— decide entre afirmarlo y
        // decir que el flete no está clasificado. Un «incluye flete» constante
        // sería la clase de frase que hace desconfiar de todas las demás.
        Text(
          candidate.freightEvidence == 'complete'
              ? 'incluye flete'
              : 'flete sin clasificar',
          style: PurchaseType.meta.copyWith(
            fontSize: 10.5,
            color: candidate.freightEvidence == 'complete'
                ? PurchaseTokens.of(context).inkFaint
                : VinabikeThemeRoles.of(context).warning.accent,
          ),
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
                          style: PurchaseType.cardTitle,
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
                      compliance == CandidateCompliance.weakEvidence ||
                      compliance == CandidateCompliance.unverified) ...[
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
                        style: PurchaseType.metricMedium.copyWith(
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
                style: PurchaseType.meta
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
    required this.unitLabel,
    required this.onClose,
    this.onAddToPlan,
    required this.onOpenSupplier,
    required this.adding,
    required this.alreadyInPlan,
    this.onChooseProduct,
    this.onToggleCollapsed,
    this.collapsed = false,
    this.onQuantityChanged,
  });

  final PurchaseCandidate candidate;
  final double quantity;

  /// Unidad ya concordada por el dueño canónico del vocabulario
  /// (`_supplyUnitLabel` del workspace): «par», «juego», «metros»… Esta
  /// superficie no pluraliza por su cuenta ni asume «u.»: una necesidad de dos
  /// pares no se lee «2 U.».
  final String unitLabel;
  final VoidCallback onClose;

  /// Nulo cuando la fila no está comprobada: se puede mirar, no comprometer.
  final VoidCallback? onAddToPlan;
  final VoidCallback? onOpenSupplier;

  /// Carril familia: la necesidad todavía no tiene producto confirmado, así
  /// que la primera acción es **elegir producto**, no agregar al plan. Son dos
  /// escrituras distintas y el pie las muestra en su orden real.
  final VoidCallback? onChooseProduct;

  /// `»` de los frames 04/05: devuelve ancho a la lista **sin** perder el
  /// candidato abierto, que es lo que distingue colapsar de cerrar. `null`
  /// donde no hay ancho que devolver —la hoja de teléfono—.
  final VoidCallback? onToggleCollapsed;
  final bool collapsed;

  /// Ver `_InspectorFooter.onQuantityChanged`.
  final ValueChanged<int>? onQuantityChanged;

  final bool adding;
  final bool alreadyInPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final compliance = complianceOf(candidate);
    final cost = candidate.latestLandedUnitCostNet;
    // El candidato externo trae la evaluación por señal; el histórico no.
    // Se copia a una local porque un campo del widget no promociona su tipo.
    final inspected = candidate;
    final targetMatch =
        inspected is SupplyExternalCandidate ? inspected.requestMatch : null;

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
                        // `typography.scale.panel_title` del handoff nombra al
                        // inspector explícitamente: 600 13.5 Poppins. Con
                        // `titleMedium` (16) un nombre real como «Cambio
                        // Saiguan HG43A Index Apernado» partía en dos líneas y
                        // empujaba la cápsula de cumplimiento fuera de vista.
                        style: PurchaseType.panelTitle
                            .copyWith(color: PurchaseTokens.of(context).ink),
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
                // Frames 04/05 y 17: la cabecera lleva **dos** controles,
                // `»` colapsar y `×` cerrar. Sólo estaba el segundo, así que
                // la única forma de recuperar ancho para la lista era cerrar
                // el detalle y perder el candidato abierto.
                //
                // Se ofrece nada más donde significa algo: en el split pane de
                // escritorio. En la hoja de teléfono no hay ancho que devolver
                // y un control que no hace nada es peor que no tenerlo.
                if (onToggleCollapsed != null)
                  IconButton(
                    key: const ValueKey('collapse-candidate-inspector'),
                    tooltip: collapsed ? 'Ampliar detalle' : 'Colapsar detalle',
                    onPressed: onToggleCollapsed,
                    icon: Icon(
                      collapsed
                          ? Icons.keyboard_double_arrow_left
                          : Icons.keyboard_double_arrow_right,
                      size: 18,
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
                    value: cost == null
                        ? 'sin evaluar'
                        : _inspectorMoney(cost, candidate.currency),
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
          // La banda de advertencia sólo aparece cuando hay algo que advertir.
          // `no_criteria` no es una carencia: la petición no traía criterios
          // técnicos, y decir «falta evidencia» ahí sería inventar un problema.
          if (compliance == CandidateCompliance.unverified ||
              compliance == CandidateCompliance.review ||
              compliance == CandidateCompliance.weakEvidence ||
              compliance == CandidateCompliance.unevaluated ||
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
                      : compliance == CandidateCompliance.unverified
                          ? 'La ficha no alcanza para confirmar que cumple los criterios de la petición. Se muestra igual: no saber no es lo mismo que no calzar.'
                          : 'El cumplimiento todavía está por confirmar: falta evidencia estructurada para comparar esta opción como cifra firme.',
                  style: PurchaseType.body
                      .copyWith(color: roles.warning.onContainer),
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
                        CandidateCompliance.meets => 'sí, '
                            '${supplyEvidenceProvenanceLabel(
                                  switch (candidate) {
                                    final SupplyExternalCandidate external =>
                                      external.matchDetail,
                                    _ => const <Map<String, dynamic>>[],
                                  },
                                ) ?? 'según la evidencia comprobada'}',
                        CandidateCompliance.meetsByName =>
                          'coincide por el nombre, no por la ficha',
                        CandidateCompliance.noCriteria =>
                          'no había criterios que comparar',
                        CandidateCompliance.unverified =>
                          'no se pudo verificar',
                        CandidateCompliance.review => 'por revisar',
                        CandidateCompliance.weakEvidence => 'evidencia débil',
                        CandidateCompliance.unevaluated => 'sin evaluar',
                      },
                    ),
                    if (candidate.brand != null)
                      _InspectorRow(label: 'Marca', value: candidate.brand!),
                    // La gama ya es un dato del motor —banda derivada del costo
                    // relativo de cada marca dentro de su categoría— y decidía
                    // el ranking sin aparecer nunca en el detalle.
                    _InspectorRow(
                      label: 'Gama',
                      // La banda poco firme NO se apaga: apagarla escondería
                      // un dato que decide detrás de un gris. La reserva se
                      // dice con palabras y el valor conserva su tinta.
                      // «poca evidencia» chocaba con la fila «Calidad de
                      // evidencia» de la sección de abajo, que habla del costo.
                      // La reserva de la banda es sobre la MARCA, no sobre el
                      // costo, y se dice con esas palabras.
                      value: candidate.gama == null || candidate.gamaIsConfident
                          ? _gamaLabel(candidate)
                          : '${_gamaLabel(candidate)} · pocas compras de la marca',
                    ),
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
                      // Mismo contrato que la métrica grande y que el total:
                      // una sola forma de escribir dinero en esta superficie.
                      value: cost == null
                          ? 'sin evaluar'
                          : _inspectorMoney(cost, candidate.currency),
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
                // Objetivo comercial: qué se pidió y qué se pudo comprobar.
                // Una señal sin evidencia se dice «No verificable» con su
                // causa; nunca baja a cero, porque eso castigaría al candidato
                // por una carencia del dato.
                if (targetMatch != null &&
                    targetMatch.requestedSignals.isNotEmpty)
                  _InspectorSection(
                    title: 'Objetivo comercial',
                    meta: targetMatch.blendApplied
                        ? '${targetMatch.knownSignalCount} verificadas'
                        : 'sin verificar',
                    children: [RequestMatchEvidence(match: targetMatch)],
                  ),
                _InspectorSection(
                  title: 'Historial y evidencia',
                  meta: candidate.evidenceAgeDays > 0
                      ? '${candidate.evidenceAgeDays} días'
                      : 'sin fecha',
                  children: [
                    // La marca vivía también acá, repetida. Y el conteo de
                    // compras pertenece a «Por qué aparece aquí», que explica
                    // el ranking: repetirlo acá era la misma cifra dos veces
                    // con dos nombres distintos. Historial guarda la fecha
                    // exacta —el «hace 140 días» de la cabecera es relativo— y
                    // la disponibilidad, que nunca se afirma.
                    _InspectorRow(
                      label: 'Última compra',
                      value: candidate.lastPurchaseAt == null
                          ? 'sin registro'
                          : _spanishDate(candidate.lastPurchaseAt!),
                    ),
                    const _InspectorRow(
                      label: 'Disponibilidad del proveedor',
                      value: 'no verificada',
                    ),
                  ],
                ),
              ],
            ),
          ),
          _InspectorFooter(
            quantity: quantity,
            unitLabel: unitLabel,
            unitCost: cost,
            currency: candidate.currency,
            adding: adding,
            alreadyInPlan: alreadyInPlan,
            onAddToPlan: onAddToPlan,
            onQuantityChanged: onQuantityChanged,
            onChooseProduct: onChooseProduct,
            onOpenSupplier: onOpenSupplier,
          ),
        ],
      ),
    );
  }
}

/// Pie del inspector: cuánto, cuánto sale, y las dos salidas reales.
///
/// El handoff pide «cantidad con stepper + total». El total **sí** se agrega:
/// era el dato que faltaba para decidir —cinco unidades a $3.490 son $17.450, y
/// eso no estaba en ninguna parte de la pantalla—.
///
/// **El stepper se descarta, y queda dicho por qué.** La cantidad pertenece a la
/// necesidad, y la necesidad ya tiene un editor con dueño único: la barra
/// superior, con su `Editar necesidad`. Un segundo editor del mismo dato en el
/// inspector crearía dos dueños para una sola cifra —qué gana si difieren, cuál
/// manda al guardar— que es justo el defecto que la guía prohíbe. Aquí la
/// cantidad se **muestra**, no se edita.
class _InspectorFooter extends StatelessWidget {
  const _InspectorFooter({
    required this.quantity,
    required this.unitLabel,
    required this.unitCost,
    required this.currency,
    required this.adding,
    required this.alreadyInPlan,
    this.onAddToPlan,
    required this.onOpenSupplier,
    this.onChooseProduct,
    this.onQuantityChanged,
  });

  final double quantity;
  final String unitLabel;
  final double? unitCost;
  final String currency;
  final bool adding;
  final bool alreadyInPlan;

  /// Nulo cuando la fila no está comprobada: se puede mirar, no comprometer.
  final VoidCallback? onAddToPlan;
  final VoidCallback? onOpenSupplier;
  final VoidCallback? onChooseProduct;

  /// `frames[single-inspector].blocks.pie`: «cantidad **con stepper** + total
  /// + Abrir proveedor + Agregar al plan». El pie mostraba el total de una
  /// cantidad que sólo se podía cambiar después, en la línea del plan: para
  /// llevar tres de algo había que agregar la cantidad de la necesidad y
  /// corregirla en el paso siguiente. `null` deja el pie como estaba.
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final total = unitCost == null ? null : unitCost! * quantity;
    final quantityLabel = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);

    return Container(
      color: tokens.sunken,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onQuantityChanged != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: PurchaseQuantityStepper(
                keyPrefix: 'inspector-quantity',
                value: quantity.round(),
                unitLabel: unitLabel,
                // El ayudante compone «<acción> de <sujeto>»: el sujeto va sin
                // preposición o queda «de del candidato».
                subject: 'este candidato',
                enabled: !adding,
                onChanged: onQuantityChanged,
              ),
            ),
            const SizedBox(height: 9),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL POR $quantityLabel ${unitLabel.toUpperCase()}',
                      style:
                          PurchaseType.label.copyWith(color: tokens.inkFaint),
                    ),
                    const SizedBox(height: 3),
                    if (total == null)
                      Text(
                        // Sin costo aterrizado no se inventa un total: se dice.
                        'sin evaluar',
                        style: PurchaseType.metricSmall
                            .copyWith(color: tokens.inkMuted),
                      )
                    else
                      Text(
                        _inspectorMoney(total, currency),
                        style: PurchaseType.metricSmall.copyWith(
                          color: tokens.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (currency != 'CLP')
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    // La cifra ya lleva su código de moneda; lo que falta decir
                    // es que no se convirtió ni se puede sumar con pesos.
                    'sin convertir',
                    style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: PurchaseMetrics.actionsTopGap),
          // Alternativa a la izquierda y acción principal a la derecha, en una
          // sola fila en todo el rango del panel (330–600).
          //
          // El desborde que apareció no era del layout: era de la **palabra**.
          // El estado deshabilitado decía «Ya está en el plan» y estiraba el
          // botón 31 px más de lo que cabía. Apilar por eso habría convertido
          // una excepción —un candidato ya agregado— en la composición
          // permanente del ancho normal. Se acorta el estado a «En el plan»,
          // que además es lo que un rótulo de estado debe ser: corto.
          Row(
            children: [
              if (onOpenSupplier != null)
                PurchaseInlineAction(
                  key: const ValueKey('open-supplier-from-inspector'),
                  label: 'Abrir proveedor',
                  onPressed: onOpenSupplier,
                ),
              const Spacer(),
              if (onChooseProduct != null)
                PurchasePrimaryButton(
                  key: const ValueKey('choose-family-product'),
                  label: 'Elegir producto',
                  onPressed: adding ? null : onChooseProduct,
                )
              else if (onAddToPlan != null)
                PurchasePrimaryButton(
                  key: const ValueKey('add-candidate-to-plan'),
                  label: alreadyInPlan ? 'En el plan' : 'Agregar al plan',
                  onPressed: adding || alreadyInPlan ? null : onAddToPlan,
                )
              else
                // **Sin comprobar no hay atajo, y se dice por qué.** Un botón
                // ausente sin explicación se lee como un defecto; esto se lee
                // como lo que es: falta evidencia, no falta la función.
                Text(
                  'Sin verificar contra los criterios',
                  key: const ValueKey('candidate-unverified-note'),
                  style: PurchaseType.meta.copyWith(
                    color: PurchaseTokens.of(context).inkMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({required this.label, this.value});

  final String label;

  /// Ya formateado por la superficie: el dinero pasa por `_inspectorMoney`, que
  /// dice la moneda cuando no es CLP en vez de disfrazarla de peso.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    // `typography.scale.metric_lg` nombra esta superficie: «inspector: costo
    // aterrizado y margen», 700 21px mono. Las dos métricas usaban
    // `headlineSmall`, que además cambia de tamaño según el tema del host: en
    // la app real el margen se veía notoriamente más grande que el costo,
    // lado a lado. Un par de cifras comparables no puede tener dos tamaños.
    final metric = PurchaseType.metricLarge.copyWith(
      color: tokens.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PurchaseType.label.copyWith(color: tokens.inkFaint),
        ),
        const SizedBox(height: 4),
        // `VbMoneyText` fija su tamaño por dentro (14) e ignora el estilo
        // ambiente, así que envolverlo no cambiaba nada: por eso el costo se
        // veía más chico que el margen, lado a lado. La cifra llega ya
        // formateada y la escala la pone esta superficie.
        Text(
          value ?? '—',
          style: metric,
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
                style: PurchaseType.meta
                    .copyWith(color: PurchaseTokens.of(context).inkMuted),
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
  /// Sólo texto ya formateado. Antes había un atajo `money:` que pintaba con
  /// `VbMoneyText`, y ése asume peso chileno: una fila en USD salía con `$` y
  /// se leía como pesos. La plata entra por `PurchaseMoney.format`, que sabe
  /// de la moneda de la línea.
  const _InspectorRow({
    required this.label,
    this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
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
              // La etiqueta es la mitad prescindible de la fila; el valor es
              // el que se lee. Estaban en el mismo gris.
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              value ?? '—',
              textAlign: TextAlign.end,
              // Siempre tinta plena: un valor incierto se matiza con
              // palabras, nunca escondiéndolo tras un gris pálido.
              style: PurchaseType.body.copyWith(color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dinero del inspector. Delega en el contrato del módulo: una sola forma de
/// escribir plata para el inspector, el plan y el cierre.
String _inspectorMoney(double amount, String currency) =>
    PurchaseMoney.format(amount, currency);

/// Fecha corta en castellano, sin dependencias de formato del host.
String _spanishDate(DateTime value) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
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
        // Frame 06: «Plan borrador» + cápsula pequeña «vacío» al lado. El
        // estado vacío se quedaba sin título propio, así que el paso 4 no
        // decía qué era hasta que tenía líneas. Los dos botones de la barra
        // superior **no** van acá —el contrato los prohíbe en el vacío— y
        // «Registrar compra local» aparece más abajo, en la fila de acciones.
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                'Plan borrador',
                style: PurchaseType.surfaceTitle
                    .copyWith(color: PurchaseTokens.of(context).ink),
              ),
              // Sin tono semántico: vacío no es una advertencia, es un estado.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: PurchaseTokens.of(context).actSoft,
                  border:
                      Border.all(color: PurchaseTokens.of(context).actBorder),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'vacío',
                  style: PurchaseType.meta
                      .copyWith(color: PurchaseTokens.of(context).inkMuted),
                ),
              ),
            ],
          ),
        ),
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
                      style: PurchaseType.sectionTitle,
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
///
/// **`subject` y `keyPrefix` existen porque el plan repite el control.** Con
/// tres líneas en pantalla, tres botones rotulados «Quitar una unidad» son
/// indistinguibles: ni una persona con lector de pantalla ni una prueba pueden
/// decir cuál es cuál. Nombrando el producto, cada control vuelve a ser único.
/// Geometría del prototipo: botones 28×28 radio 7, casilla 52×28.
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
    this.subject,
    this.keyPrefix,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;
  final bool enabled;
  final String? unitLabel;
  final String? semanticsLabel;

  /// Qué se está contando, para que los dos botones se puedan nombrar.
  final String? subject;

  /// Raíz de las `key` de los dos botones, cuando hay más de un stepper.
  final String? keyPrefix;

  static const double _button = 28;
  static const double _box = 52;
  static const double _radius = 7;

  String _label(String action) =>
      subject == null ? action : '$action de $subject';

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final canDecrease = enabled && onChanged != null && value > min;
    final canIncrease = enabled && onChanged != null && value < max;
    final decreaseLabel = _label('Quitar una unidad');
    final increaseLabel = _label('Agregar una unidad');

    return Semantics(
      label: semanticsLabel ?? 'Cantidad',
      value: '$value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            buttonKey:
                keyPrefix == null ? null : ValueKey('$keyPrefix-decrease'),
            label: decreaseLabel,
            tooltip: canDecrease ? decreaseLabel : 'Ya está en el mínimo',
            icon: Icons.remove,
            onPressed: canDecrease ? () => onChanged!(value - 1) : null,
          ),
          const SizedBox(width: 5),
          Container(
            width: _box,
            height: _button,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border.all(color: tokens.borderStrong),
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Text(
              '$value',
              style: PurchaseType.metricSmall.copyWith(
                fontSize: 12,
                color: tokens.ink,
                fontFeatures: PurchaseType.tabular,
              ),
            ),
          ),
          const SizedBox(width: 5),
          _StepperButton(
            buttonKey:
                keyPrefix == null ? null : ValueKey('$keyPrefix-increase'),
            label: increaseLabel,
            tooltip: canIncrease ? increaseLabel : 'Ya está en el máximo',
            icon: Icons.add,
            onPressed: canIncrease ? () => onChanged!(value + 1) : null,
          ),
          if (unitLabel != null) ...[
            const SizedBox(width: 5),
            Text(
              unitLabel!,
              style: PurchaseType.hint.copyWith(color: tokens.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.buttonKey,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String label;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return SizedBox.square(
      dimension: PurchaseQuantityStepper._button,
      child: IconButton(
        key: buttonKey,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(PurchaseQuantityStepper._radius),
            side: BorderSide(color: tokens.borderStrong),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16, semanticLabel: label),
      ),
    );
  }
}

/// El riel que queda cuando el inspector se colapsa.
///
/// `frames[single-inspector].resize.collapse`: «botón ›› / ‹‹ con riel de
/// 28px». Colapsar **no** es cerrar: el riel conserva el candidato abierto y
/// devuelve el ancho a la comparación; el `×` del panel lo suelta. Un panel
/// estrecho en su lugar no distinguiría las dos cosas.
class CandidateInspectorRail extends StatelessWidget {
  const CandidateInspectorRail({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      key: const ValueKey('candidate-inspector-rail'),
      width: PurchaseSurfaceGeometry.inspectorCollapsedRail,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: tokens.hair)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: IconButton(
          key: const ValueKey('expand-candidate-inspector'),
          tooltip: 'Ampliar detalle',
          onPressed: onExpand,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 40),
          icon: const Icon(Icons.keyboard_double_arrow_left, size: 16),
        ),
      ),
    );
  }
}

/// Controles del encabezado de la **canasta**.
///
/// Frame 20 (teléfono) pone las tabs `Líneas | Escenarios` **inmediatamente**
/// bajo el encabezado. La canasta apilaba antes dos desplegables de formulario
/// a ancho completo —«Prioridad» y «Proveedores»— más una losa tonal, y eso
/// empujaba la comparación **bajo el pliegue**: y≈590 de 788 px medidos.
///
/// En escritorio los dos desplegables se quedan, que es lo que el frame 11
/// pide en su encabezado. En teléfono se reúnen en un solo botón anclado, que
/// es exactamente el tratamiento que `ProviderResultControls` ya documenta
/// para los frames 16 y 20 a un paso de distancia. No se inventa un control:
/// se deja de escribir una variante local del que el módulo ya tiene.
class BasketResultControls extends StatelessWidget {
  const BasketResultControls({
    super.key,
    required this.compact,
    required this.profileValue,
    required this.profileOptions,
    required this.onProfileChanged,
    required this.maxSuppliersValue,
    required this.maxSuppliersOptions,
    required this.onMaxSuppliersChanged,
    this.enabled = true,
  });

  final bool compact;
  final String profileValue;
  final Map<String, String> profileOptions;
  final ValueChanged<String> onProfileChanged;
  final String maxSuppliersValue;
  final Map<String, String> maxSuppliersOptions;
  final ValueChanged<String> onMaxSuppliersChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _AnchoredMenuButton(
        menuId: 'basket-sort-and-suppliers',
        label: 'Vista',
        enabled: enabled,
        sections: [
          _MenuSection(
            title: 'Prioridad de comparación',
            value: profileValue,
            options: profileOptions,
            onSelected: onProfileChanged,
          ),
          _MenuSection(
            title: 'Máximo de proveedores',
            value: maxSuppliersValue,
            options: maxSuppliersOptions,
            onSelected: onMaxSuppliersChanged,
          ),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 210,
          child: VbShortSelect<String>(
            value: profileValue,
            options: [
              for (final entry in profileOptions.entries)
                VbShortSelectOption(value: entry.key, label: entry.value),
            ],
            onChanged: enabled ? onProfileChanged : null,
            sheetTitle: 'Prioridad de comparación',
            label: 'Prioridad',
          ),
        ),
        SizedBox(
          width: 190,
          child: VbShortSelect<String>(
            value: maxSuppliersValue,
            options: [
              for (final entry in maxSuppliersOptions.entries)
                VbShortSelectOption(value: entry.key, label: entry.value),
            ],
            onChanged: enabled ? onMaxSuppliersChanged : null,
            sheetTitle: 'Máximo de proveedores',
            label: 'Proveedores',
          ),
        ),
      ],
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
    required this.profileLabel,
    required this.viewValue,
    required this.viewOptions,
    required this.onViewChanged,
    this.enabled = true,
  });

  final bool compact;

  /// **El perfil es un dato, no un control.** La lectura externa lo toma de la
  /// revisión que gobierna la necesidad, así que un menú acá no cambiaba nada
  /// del backend: ofrecía tres opciones y el resultado llegaba idéntico. Se
  /// muestra lo que el servidor resolvió y se dice de dónde salió.
  final String profileLabel;
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
      return Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ServerProfileLabel(label: profileLabel),
          _AnchoredMenuButton(
            menuId: 'provider-sort-and-filters',
            label: 'Vista',
            enabled: enabled,
            sections: [
              _MenuSection(
                title: 'Vista',
                value: viewValue,
                options: viewOptions,
                onSelected: onViewChanged,
              ),
            ],
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ServerProfileLabel(label: profileLabel),
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

/// El perfil que el servidor resolvió, como texto secundario.
///
/// Nunca un menú: este módulo no ofrece opciones que no lleguen al backend.
class _ServerProfileLabel extends StatelessWidget {
  const _ServerProfileLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      key: const ValueKey('server-ranking-profile'),
      label,
      style: PurchaseType.meta
          .copyWith(color: PurchaseTokens.of(context).inkMuted),
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
                style: PurchaseType.label,
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
            style: PurchaseType.body.copyWith(color: roles.warning.onContainer),
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
                  style: PurchaseType.meta
                      .copyWith(color: roles.warning.onContainer),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      technicalDetail!,
                      style: PurchaseType.meta
                          .copyWith(color: roles.warning.onContainer),
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
            style: PurchaseType.sectionTitle,
          ),
          const SizedBox(height: 4),
          Text(
            causeSentence,
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  style: PurchaseType.meta,
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
          style: PurchaseType.meta
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
      style:
          PurchaseType.meta.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
///
/// **No es un `ExpansionTile`.** Ése ocupa el ancho de la identidad y cuelga
/// su chevron en el extremo derecho, a media fila del texto que abre: en el
/// plan quedaba un cuadrito suelto en mitad de la línea, sin nada que lo
/// explicara. El prototipo lo resuelve como lo que es —un botón de texto en el
/// color de acción, con la evidencia debajo—, y así queda.
class PlanLineEvidenceNote extends StatefulWidget {
  const PlanLineEvidenceNote({
    super.key,
    required this.lineId,
    required this.productName,
    required this.supplierAvailability,
    required this.currency,
    required this.landedUnitCostNet,
    required this.projectedGrossMarginRatio,
    this.catalogCostNet,
    this.catalogCostCurrency,
    this.note,
    this.onSaveNote,
    this.onSubstitute,
    this.savingNote = false,
  });

  final String lineId;

  /// El disclosure se nombra con su producto por el mismo motivo que los
  /// botones de la línea: con varias líneas abiertas, «Evidencia de la línea»
  /// repetido no identifica ninguna.
  final String productName;
  final String supplierAvailability;
  final String currency;
  final double? landedUnitCostNet;
  final double? projectedGrossMarginRatio;
  final double? catalogCostNet;
  final String? catalogCostCurrency;

  /// `frames[plan].with_lines.line_disclosure`: «Alternativa y nota
  /// (sustituir candidato, nota libre)». El desplegable existía pero sólo
  /// **mostraba evidencia**: no dejaba decir por qué se eligió este candidato
  /// ni cambiarlo sin salir a buscarlo a mano. La evidencia se queda —es lo
  /// que sostiene la decisión— y encima se le agregan las dos acciones que el
  /// contrato nombra. `null` en los callbacks deja el desplegable como estaba.
  final String? note;
  final ValueChanged<String?>? onSaveNote;
  final VoidCallback? onSubstitute;
  final bool savingNote;

  @override
  State<PlanLineEvidenceNote> createState() => _PlanLineEvidenceNoteState();
}

class _PlanLineEvidenceNoteState extends State<PlanLineEvidenceNote> {
  bool _open = false;
  late final TextEditingController _note =
      TextEditingController(text: widget.note ?? '');

  @override
  void didUpdateWidget(covariant PlanLineEvidenceNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La nota vuelve del servidor normalizada —recortada, o nula si quedó en
    // blanco—. Si el campo conservara lo tecleado, el operador vería una cosa
    // y la fila guardaría otra.
    if (oldWidget.note != widget.note && !_note.value.composing.isValid) {
      _note.text = widget.note ?? '';
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final unitCost =
        PurchaseMoney.format(widget.landedUnitCostNet, widget.currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 7),
        Semantics(
          button: true,
          expanded: _open,
          label: widget.onSaveNote == null && widget.onSubstitute == null
              ? 'Evidencia de ${widget.productName}'
              : 'Alternativa y nota de ${widget.productName}',
          // El texto visible se repite en todas las líneas; el rótulo que se
          // busca es el que nombra el producto, así que el del `Text` se
          // excluye en vez de fundirse con él.
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('plan-line-evidence-${widget.lineId}'),
            onTap: () => setState(() => _open = !_open),
            child: Text(
              _open
                  ? 'Ocultar'
                  // El contrato nombra el desplegable por lo que **hace**, no
                  // por lo que muestra: adentro se decide, no sólo se lee.
                  : widget.onSaveNote == null && widget.onSubstitute == null
                      ? 'Evidencia de la línea'
                      : 'Alternativa y nota',
              style: PurchaseType.inlineAction
                  .copyWith(fontSize: 10, color: tokens.act),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          _InspectorRow(
            label: 'Disponibilidad declarada',
            value: widget.supplierAvailability.isEmpty
                ? 'no verificada'
                : widget.supplierAvailability,
          ),
          _InspectorRow(label: 'Moneda', value: widget.currency),
          _InspectorRow(
            label: 'Costo aterrizado unitario',
            value: unitCost == '—' ? 'sin evaluar' : unitCost,
          ),
          if (widget.catalogCostNet != null)
            _InspectorRow(
              label: 'Referencia de ficha',
              value: '${PurchaseMoney.format(
                widget.catalogCostNet,
                widget.catalogCostCurrency ?? widget.currency,
              )} · no pagado',
            ),
          _InspectorRow(
            label: 'Margen proyectado',
            value: widget.projectedGrossMarginRatio == null
                // Sin precio vigente el margen no es cero: no tiene base.
                ? 'sin base'
                : '${(widget.projectedGrossMarginRatio! * 100).toStringAsFixed(1)}%',
          ),
          if (widget.onSubstitute != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: ValueKey('plan-line-substitute-${widget.lineId}'),
                onPressed: widget.savingNote ? null : widget.onSubstitute,
                child: const Text('Sustituir candidato'),
              ),
            ),
          ],
          if (widget.onSaveNote != null) ...[
            const SizedBox(height: 10),
            Text(
              'Nota',
              style: PurchaseType.label.copyWith(color: tokens.inkFaint),
            ),
            const SizedBox(height: 4),
            TextField(
              key: ValueKey('plan-line-note-field-${widget.lineId}'),
              controller: _note,
              enabled: !widget.savingNote,
              maxLines: 2,
              maxLength: 300,
              style: PurchaseType.body.copyWith(color: tokens.ink),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'Por qué este y no otro',
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: ValueKey('plan-line-note-save-${widget.lineId}'),
                onPressed: widget.savingNote
                    ? null
                    // Vacío **es** una orden: borra la nota. Se manda tal cual
                    // y el comando la normaliza; decidirlo acá sería una
                    // segunda definición de «en blanco».
                    : () => widget.onSaveNote!(_note.text),
                child: Text(widget.savingNote ? 'Guardando…' : 'Guardar nota'),
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ],
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
              style: PurchaseType.label.copyWith(
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
                    style: PurchaseType.sectionTitle,
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
                style: PurchaseType.meta
                    .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
        Text(line.name, style: PurchaseType.rowTitle),
        if (line.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            line.description,
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  style:
                      PurchaseType.meta.copyWith(color: roles.warning.accent),
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
                      style: PurchaseType.panelTitle,
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
                    style: PurchaseType.rowTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esto no compra ni recibe nada: prepara el documento para '
                    'que lo completes y lo confirmes tú.',
                    style: PurchaseType.meta
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  // Frame 13: «cada uno con etiqueta con asterisco» y «sin
                  // cápsulas naranjas de obligatoriedad: sólo el asterisco»
                  // (NOTES §193 y §202). Los tres campos que esta hoja sí
                  // captura son obligatorios —`_submit` no deja pasar sin
                  // ellos— y ninguno lo decía.
                  Text('Tipo de documento *', style: PurchaseType.label),
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
                      labelText: 'Cantidad (${widget.unitLabel}) *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _quantityError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tratamiento tributario *',
                    style: PurchaseType.label,
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
                    style: PurchaseType.meta
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
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

// ─────────────────────────────────────────────────────────────────────────────
// Plan borrador — grupo por proveedor y línea.
//
// La composición está leída de la página `Compras · Asistente inteligente
// navegable.dc.html`, bloque `planGroups`. Lo que trae de allí, verbatim:
//
//   tarjeta:   surface · 1px border · radio 10 · overflow hidden
//   cabecera:  padding 10/12 · borde inferior `hair` · flex gap 9
//              proveedor 600 12.5 sans ink · evidencia 400 10.5 sans
//              (`inkFaint` completa, `wnFg` parcial)
//   fila:      padding 10/12 · borde superior `hair`
//              identidad flex:1 min 150 · stepper 28/52/28 gap 5
//              total 700 13 mono · unitario 400 9 mono inkFaint
//              retirar 28×28 radio 7 · disclosure 600 10 sans act
//   pie:       padding 9/12 · fondo `sunken` · borde superior `hair`
//              etiqueta 500 11 sans inkMuted · cifra 700 13 mono ink
//              nota de flete 400 10/1.45 sans inkFaint
//
// **El subtotal vive en el pie, no junto a la evidencia.** Antes ambos
// colgaban del mismo `Row` de cabecera y se leían pegados —«evidencia
// completa$17.450»—: dos cosas distintas que la vista fundía en una. La
// separación no es una preferencia, es la del prototipo.
// ─────────────────────────────────────────────────────────────────────────────

/// Un proveedor del plan con sus líneas, su evidencia y su subtotal.
class PurchasePlanGroup extends StatelessWidget {
  const PurchasePlanGroup({
    super.key,
    required this.group,
    required this.lines,
    required this.removingLineId,
    required this.updatingLineId,
    required this.editingLineId,
    required this.quantityController,
    required this.quantityError,
    required this.onEditQuantity,
    required this.onCancelQuantity,
    required this.onCommitQuantity,
    required this.onStepQuantity,
    required this.onRemove,
    this.onSaveNote,
    this.onSubstitute,
    this.savingNoteLineId,
  });

  final PurchasePlanSupplierGroup group;
  final List<PurchasePlanLine> lines;
  final String? removingLineId;
  final String? updatingLineId;

  /// Línea cuya cantidad se edita en su propia fila, sin superficie flotante.
  final String? editingLineId;
  final TextEditingController quantityController;
  final String? quantityError;
  final VoidCallback onCancelQuantity;
  final ValueChanged<PurchasePlanLine> onCommitQuantity;
  final ValueChanged<PurchasePlanLine> onEditQuantity;
  final ValueChanged<PurchasePlanLine> onRemove;

  /// Las dos acciones de `line_disclosure`, bajadas a cada fila.
  final void Function(PurchasePlanLine line, String? note)? onSaveNote;
  final ValueChanged<PurchasePlanLine>? onSubstitute;
  final String? savingNoteLineId;

  /// El stepper `− n +` corrige la cantidad sin abrir el editor.
  final void Function(PurchasePlanLine line, int quantity) onStepQuantity;

  bool get _evidenceComplete =>
      lines.isNotEmpty && lines.every((line) => line.landedUnitCostNet != null);

  bool get _quoteOnly =>
      lines.isNotEmpty && lines.every((line) => line.requiresQuote);

  int get _quoteLineCount => lines.where((line) => line.requiresQuote).length;

  /// Lo que el subtotal **no** dice, en la ranura de nota del pie.
  ///
  /// Son dos advertencias distintas y las dos tienen que sobrevivir. La del
  /// flete es del prototipo. La de disponibilidad estaba en la cabecera vieja
  /// —«N productos · disponibilidad por confirmar»— y no puede desaparecer al
  /// mudarse: el contrato de datos prohíbe afirmar que el proveedor tiene
  /// stock, porque lo único que hay es historial de compra. Enterrarla dentro
  /// del disclosure de cada línea sería quitarla.
  String get _footerCaveat {
    if (_quoteOnly) {
      final referenced =
          lines.where((line) => line.catalogCostNet != null).length;
      final referenceLabel = referenced == 0
          ? 'No hay costo de ficha registrado.'
          : referenced == 1
              ? '1 línea conserva una referencia de ficha que no suma al subtotal.'
              : '$referenced líneas conservan referencias de ficha que no suman al subtotal.';
      return 'Estas líneas no tienen una compra registrada en este ERP. '
          '$referenceLabel Llevarlas al plan no reserva ni compra nada.';
    }
    if (_quoteLineCount > 0) {
      final label = _quoteLineCount == 1
          ? '1 línea está por cotizar y queda fuera del subtotal'
          : '$_quoteLineCount líneas están por cotizar y quedan fuera del '
              'subtotal';
      return '$label. El subtotal suma sólo las líneas con costo aterrizado; '
          'la disponibilidad de todas sigue por confirmar.';
    }
    final unverified = lines.any(
      (line) => line.supplierAvailability != 'confirmed',
    );
    final freight = _evidenceComplete
        ? 'Flete ya atribuido por línea; consolidar no agrega descuento.'
        : 'Falta el costo aterrizado de al menos una línea: el subtotal cubre '
            'sólo las que sí lo tienen.';
    if (!unverified) return freight;
    return '$freight La disponibilidad del proveedor está por confirmar: el '
        'historial dice que se compró, no que hoy haya.';
  }

  double? get _subtotal {
    if (lines.isEmpty) return null;
    // Una línea sin costo aterrizado no se cuenta como cero: el subtotal
    // quedaría más barato que la compra real. Se suma lo que hay y el pie dice
    // que la evidencia está incompleta.
    final priced = lines.where((line) => line.landedUnitCostNet != null);
    if (priced.isEmpty) return null;
    return priced.fold<double>(
      0,
      (total, line) => total + line.landedUnitCostNet! * line.quantity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final complete = _evidenceComplete;

    return PurchasePanel(
      key: ValueKey('plan-group-${group.supplierName}-${group.currency}'),
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera: identidad del proveedor y estado de su evidencia. Nada
          // de plata acá.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.hair)),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 9,
              runSpacing: 4,
              children: [
                Text(
                  group.supplierName,
                  style: PurchaseType.sectionTitle.copyWith(color: tokens.ink),
                ),
                Text(
                  _quoteOnly
                      ? 'producto de ficha · sin compra ERP'
                      : complete
                          ? 'evidencia completa'
                          : 'evidencia parcial',
                  style: PurchaseType.meta.copyWith(
                    fontSize: 10.5,
                    color: complete ? tokens.inkFaint : roles.warning.accent,
                  ),
                ),
              ],
            ),
          ),
          for (final line in lines)
            editingLineId == line.id
                ? PurchasePlanQuantityEditor(
                    key: ValueKey('plan-quantity-inline-${line.id}'),
                    line: line,
                    controller: quantityController,
                    error: quantityError,
                    onCancel: onCancelQuantity,
                    onCommit: () => onCommitQuantity(line),
                  )
                : PurchasePlanLineRow(
                    key: ValueKey('plan-line-${line.id}'),
                    line: line,
                    busy: removingLineId != null || updatingLineId != null,
                    updating: updatingLineId == line.id,
                    removing: removingLineId == line.id,
                    onEditQuantity: () => onEditQuantity(line),
                    onStepQuantity: (quantity) =>
                        onStepQuantity(line, quantity),
                    onRemove: () => onRemove(line),
                    onSaveNote: onSaveNote == null
                        ? null
                        : (note) => onSaveNote!(line, note),
                    onSubstitute:
                        onSubstitute == null ? null : () => onSubstitute!(line),
                    savingNote: savingNoteLineId == line.id,
                  ),
          // Pie hundido: el subtotal, rotulado con su moneda, y la nota de
          // flete que impide leerlo como precio final.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: tokens.sunken,
              border: Border(top: BorderSide(color: tokens.hair)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Subtotal mercadería ${group.currency}',
                        style: PurchaseType.body.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: tokens.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      PurchaseMoney.format(_subtotal, group.currency),
                      style: PurchaseType.metricSmall.copyWith(
                        color: tokens.ink,
                        fontFeatures: PurchaseType.tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _footerCaveat,
                  style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una línea del plan: foto, identidad, cantidad, plata y retirar.
///
/// La identidad es la única pieza elástica. Cuando el ancho disponible no
/// alcanza para la fila completa —el inspector abierto estrecha esta columna
/// muy por debajo del ancho de la ventana— los controles caen bajo la
/// identidad, que es el reflow del prototipo (`flex-wrap:wrap` con la
/// identidad en `min-width:150px`), no una vista de teléfono aparte.
class PurchasePlanLineRow extends StatelessWidget {
  const PurchasePlanLineRow({
    super.key,
    required this.line,
    required this.busy,
    required this.updating,
    required this.removing,
    required this.onEditQuantity,
    required this.onStepQuantity,
    required this.onRemove,
    this.onSaveNote,
    this.onSubstitute,
    this.savingNote = false,
  });

  final PurchasePlanLine line;
  final bool busy;
  final bool updating;
  final bool removing;
  final VoidCallback onEditQuantity;
  final ValueChanged<int> onStepQuantity;
  final VoidCallback onRemove;

  /// Ver `PlanLineEvidenceNote`: las dos acciones que el contrato nombra en
  /// `line_disclosure`. `null` deja el desplegable como estaba.
  final ValueChanged<String?>? onSaveNote;
  final VoidCallback? onSubstitute;
  final bool savingNote;

  /// El ancho mínimo de la fila en una sola línea, sumado de sus piezas leídas
  /// del prototipo. No es un número redondo elegido a ojo: si alguna pieza
  /// cambia de tamaño, este umbral cambia con ella.
  static const double _singleRowMinWidth = 12 + // padding izquierdo
      PurchaseSurfaceGeometry.mediaTableRow + // foto 38
      10 + // gap
      150 + // identidad, mínimo del prototipo
      10 +
      _stepperWidth +
      28 + // editar cantidad
      10 +
      _moneyColumnWidth +
      28 + // retirar
      12; // padding derecho

  static const double _stepperWidth = 28 + 5 + 52 + 5 + 28;
  static const double _moneyColumnWidth = 100;

  String get _productLabel => line.productName ?? 'Producto del plan';

  String get _evidenceLabel {
    switch (line.evidenceState) {
      case 'fresh_supplier_check':
        return 'proveedor de ficha · portal consultado · revisado '
            '${supplySourcingDateLabel(line.availabilityCheckedAt)}';
      case 'catalog_assignment':
        if (line.availabilityStatus == 'out_of_stock' &&
            line.availabilityCheckedAt != null) {
          return 'proveedor de ficha · portal sin stock · '
              'revisado ${supplySourcingDateLabel(line.availabilityCheckedAt)}';
        }
        return 'proveedor de ficha · sin compras en este ERP';
      case 'no_erp_history':
        return 'sin proveedor ni compras en este ERP';
      default:
        return line.landedUnitCostNet == null
            ? 'evidencia incompleta · sin costo aterrizado'
            : line.evidenceAgeDays == null
                ? 'evidencia completa'
                : 'evidencia ${line.evidenceAgeDays} días · completa';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        stacked: constraints.maxWidth < _singleRowMinWidth,
      ),
    );
  }

  Widget _build(BuildContext context, {required bool stacked}) {
    final tokens = PurchaseTokens.of(context);
    final subtotal = line.landedUnitCostNet == null
        ? null
        : line.landedUnitCostNet! * line.quantity;

    // Anulación del contrato de imagen registrada en `PurchasePlanLine.media`:
    // el t23 no pone foto en el plan, el dueño sí. Geometría prestada de
    // `image_contract.geometry.table_row`, la superficie más parecida.
    final photo = ProductMediaTile(
      key: ValueKey('plan-line-media-${line.id}'),
      media: line.media,
      name: _productLabel,
      size: PurchaseSurfaceGeometry.mediaTableRow,
    );

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_productLabel,
            style: PurchaseType.rowTitle.copyWith(color: tokens.ink)),
        const SizedBox(height: 2),
        Text(
          _evidenceLabel,
          style: PurchaseType.body.copyWith(
            fontSize: 11,
            height: 1.2,
            color: tokens.inkMuted,
          ),
        ),
        PlanLineEvidenceNote(
          lineId: line.id,
          note: line.note,
          onSaveNote: onSaveNote,
          onSubstitute: onSubstitute,
          savingNote: savingNote,
          productName: _productLabel,
          supplierAvailability: line.supplierAvailability,
          currency: line.currency,
          landedUnitCostNet: line.landedUnitCostNet,
          projectedGrossMarginRatio: line.projectedGrossMarginRatio,
          catalogCostNet: line.catalogCostNet,
          catalogCostCurrency: line.catalogCostCurrency,
        ),
      ],
    );

    final quantity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PurchaseQuantityStepper(
          value: line.quantity.round(),
          enabled: !busy,
          unitLabel: purchaseUnitLabel(line.unit, line.quantity),
          semanticsLabel: 'Cantidad de $_productLabel',
          subject: _productLabel,
          keyPrefix: 'plan-line-${line.id}',
          onChanged: onStepQuantity,
        ),
        _PlanLineIconButton(
          buttonKey: ValueKey('plan-line-edit-quantity-${line.id}'),
          label: 'Escribir la cantidad de $_productLabel',
          onPressed: busy ? null : onEditQuantity,
          busy: updating,
          icon: Icons.edit_outlined,
        ),
      ],
    );

    final referenceUnitCost =
        line.landedUnitCostNet == null ? line.catalogCostNet : null;
    final displayedTotal = subtotal ??
        (referenceUnitCost == null ? null : referenceUnitCost * line.quantity);
    final money = SizedBox(
      width: stacked ? null : _moneyColumnWidth,
      child: Column(
        crossAxisAlignment:
            stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            PurchaseMoney.format(
              displayedTotal,
              referenceUnitCost == null
                  ? line.currency
                  : line.catalogCostCurrency ?? line.currency,
            ),
            key: ValueKey('plan-line-total-${line.id}'),
            style: PurchaseType.metricSmall.copyWith(
              color: tokens.ink,
              fontFeatures: PurchaseType.tabular,
            ),
          ),
          if (line.landedUnitCostNet != null)
            Text(
              PurchaseMoney.perUnit(line.landedUnitCostNet, line.currency),
              key: ValueKey('plan-line-unit-${line.id}'),
              style: PurchaseType.hint.copyWith(
                fontSize: 9,
                color: tokens.inkFaint,
                fontFeatures: PurchaseType.tabular,
              ),
            ),
          if (line.landedUnitCostNet == null && referenceUnitCost != null)
            Text(
              '${PurchaseMoney.perUnit(
                referenceUnitCost,
                line.catalogCostCurrency ?? line.currency,
              )} · referencia de ficha',
              key: ValueKey('plan-line-catalog-unit-${line.id}'),
              style: PurchaseType.hint.copyWith(
                fontSize: 9,
                color: tokens.inkFaint,
                fontFeatures: PurchaseType.tabular,
              ),
            ),
        ],
      ),
    );

    final remove = _PlanLineIconButton(
      buttonKey: ValueKey('plan-line-remove-${line.id}'),
      label: 'Quitar $_productLabel del plan',
      tooltip: 'Retira la línea del plan; la necesidad sigue abierta',
      onPressed: busy ? null : onRemove,
      busy: removing,
      icon: Icons.close,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    photo,
                    const SizedBox(width: 10),
                    Expanded(child: identity),
                    remove,
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [quantity, money],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                photo,
                const SizedBox(width: 10),
                Expanded(child: identity),
                const SizedBox(width: 10),
                quantity,
                const SizedBox(width: 10),
                money,
                remove,
              ],
            ),
    );
  }
}

/// Botón de icono de una línea del plan, con nombre propio.
///
/// **Por qué no es un `IconButton` suelto.** Los iconos de las líneas no se
/// podían alcanzar por identidad: todas las filas exponían el mismo rótulo
/// genérico —«Editar cantidad», «Quitar del plan»— y con tres productos en el
/// plan no había forma de decir cuál. Acá el rótulo nombra el producto, así
/// que cada control es único en la pantalla, y la `key` permite alcanzarlo sin
/// depender del texto.
class _PlanLineIconButton extends StatelessWidget {
  const _PlanLineIconButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    required this.busy,
    required this.icon,
    this.tooltip,
  });

  final Key buttonKey;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      // El tooltip explica la consecuencia cuando la hay; el rótulo accesible
      // siempre nombra el producto, que es lo que se busca por identidad.
      tooltip: tooltip ?? label,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16, semanticLabel: label),
    );
  }
}

/// Editor de cantidad de una línea, en el sitio de la línea.
class PurchasePlanQuantityEditor extends StatelessWidget {
  const PurchasePlanQuantityEditor({
    super.key,
    required this.line,
    required this.controller,
    required this.error,
    required this.onCancel,
    required this.onCommit,
  });

  final PurchasePlanLine line;
  final TextEditingController controller;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 380;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: tokens.sunken,
            border: Border(
              top: BorderSide(color: tokens.hair),
              left: BorderSide(color: tokens.act, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.productName ?? 'Producto del plan',
                style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
              ),
              const SizedBox(height: 10),
              Flex(
                direction: stacked ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: stacked ? double.infinity : 160,
                    child: TextField(
                      key: const ValueKey('purchase-plan-quantity-field'),
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onCommit(),
                    ),
                  ),
                  SizedBox(width: stacked ? 0 : 12, height: stacked ? 10 : 0),
                  SizedBox(
                    height: 40,
                    width: stacked ? double.infinity : null,
                    child: FilledButton(
                      key: const ValueKey('save-purchase-plan-quantity'),
                      onPressed: onCommit,
                      child: const Text('Guardar'),
                    ),
                  ),
                  SizedBox(width: stacked ? 0 : 8, height: stacked ? 8 : 0),
                  SizedBox(
                    height: 40,
                    width: stacked ? double.infinity : null,
                    child: TextButton(
                      key: const ValueKey('cancel-purchase-plan-quantity'),
                      onPressed: onCancel,
                      child: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: PurchaseType.meta
                      .copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// El vocabulario de unidades del módulo, en un solo sitio.
///
/// Vive acá y no en la página porque las superficies del plan y del inspector
/// lo necesitan sin arrastrar el workspace entero. Antes una copia decía «1
/// unidades».
String purchaseUnitLabel(String raw, double quantity) {
  final singular = quantity == 1;
  return switch (raw.trim().toLowerCase()) {
    'unit' ||
    'units' ||
    'unidad' ||
    'unidades' =>
      singular ? 'unidad' : 'unidades',
    'pair' || 'pairs' || 'par' || 'pares' => singular ? 'par' : 'pares',
    'set' || 'sets' || 'juego' || 'juegos' => singular ? 'juego' : 'juegos',
    'meter' ||
    'meters' ||
    'metre' ||
    'metres' ||
    'metro' ||
    'metros' =>
      singular ? 'metro' : 'metros',
    _ => raw.trim(),
  };
}

// ───────────────────────────────────────────────────────────────────────────
// Fase B1/B2 — el carril familia en la superficie.
//
// Todas estas bandas reutilizan la gramática que el módulo ya fijó: ancho
// completo, `surfaceContainerLow`, filete arriba y abajo, `titleSmall` para el
// hecho y `bodySmall` para la causa, y las acciones en una fila. Ninguna es
// una tarjeta centrada con sombra, y ninguna repite el estado como cápsula.
// ───────────────────────────────────────────────────────────────────────────

/// Banda base de estado. Un solo dueño de la composición para que los siete
/// estados no diverjan en siete layouts.
class _DecisionStateBand extends StatelessWidget {
  const _DecisionStateBand({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      foregroundDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.hair),
          bottom: BorderSide(color: tokens.hair),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PurchaseType.sectionTitle),
          const SizedBox(height: 4),
          Text(
            body,
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// El servidor exige decidir primero el stock interno.
///
/// **No es un error.** El paso externo está cerrado porque hay una alternativa
/// interna que cubre entera la necesidad y nadie dijo por qué no sirve. La
/// única acción que lo abre está acá, no en un mensaje de reintento.
class StockFirstRequiredSurface extends StatelessWidget {
  const StockFirstRequiredSurface({
    super.key,
    required this.onExplainRejection,
    required this.onReviewStock,
    this.busy = false,
  });

  final VoidCallback onExplainRejection;
  final VoidCallback onReviewStock;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return _DecisionStateBand(
      key: const ValueKey('stock-first-required'),
      title: 'Primero decide el stock interno',
      body: 'Hay una alternativa en bodega que cubre entera esta necesidad. '
          'Para comparar proveedores, usa ese stock o explica por qué no sirve.',
      actions: [
        FilledButton(
          key: const ValueKey('stock-first-explain'),
          onPressed: busy ? null : onExplainRejection,
          child: const Text('Explicar por qué no sirve'),
        ),
        TextButton(
          key: const ValueKey('stock-first-review'),
          onPressed: busy ? null : onReviewStock,
          child: const Text('Revisar el stock interno'),
        ),
      ],
    );
  }
}

/// La lectura de la decisión falló y no hay nada que mostrar todavía.
///
/// **No es un conjunto vacío.** Sin esta superficie, un fallo de red dejaba la
/// pantalla afirmando dos cosas falsas a la vez: «no hay compras históricas
/// comparables» —que es una conclusión sobre los datos, no sobre la red— y
/// «falta confirmar qué producto es», que invita a resolver una identidad que
/// nadie pudo evaluar. Un error de lectura no autoriza ninguna conclusión.
class DecisionLoadFailedSurface extends StatelessWidget {
  const DecisionLoadFailedSurface({
    super.key,
    required this.onRetry,
    this.busy = false,
  });

  final VoidCallback onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return _DecisionStateBand(
      key: const ValueKey('decision-load-failed'),
      title: 'No se pudo leer la bodega',
      // **Decía de más y de menos a la vez.** «Todavía no sabemos qué
      // proveedores comparar» dejó de ser cierto: los proveedores y el recibo
      // ya consultado no le preguntan nada a la bodega y siguen abajo. Lo que
      // sí falta es saber qué hay en la tienda, y eso es lo único que bloquea:
      // mirar y refiltrar se puede; comprometer una compra, no.
      body: 'La consulta de stock no llegó a responder, así que no sabemos qué '
          'hay en la tienda. Los proveedores y lo ya consultado siguen abajo: '
          'se pueden revisar y refiltrar, pero no comprometer una compra hasta '
          'releerla. La necesidad no cambió.',
      actions: [
        FilledButton(
          key: const ValueKey('retry-decision-load'),
          onPressed: busy ? null : onRetry,
          child: const Text('Reintentar'),
        ),
      ],
    );
  }
}

/// Los siete estados en que la lectura externa no propone comprar.
///
/// Cada uno tiene su causa y su acción propia; colapsarlos en «sin resultados»
/// le quitaría al operador justamente lo que tiene que hacer después.
class ExternalCandidatesStateSurface extends StatelessWidget {
  const ExternalCandidatesStateSurface({
    super.key,
    required this.result,
    this.onEditNeed,
    this.onRegisterLocalPurchase,
  });

  final SupplyExternalCandidates result;
  final VoidCallback? onEditNeed;
  final VoidCallback? onRegisterLocalPurchase;

  @override
  Widget build(BuildContext context) {
    final copy = supplyExternalStatusCopy(result);
    final actions = <Widget>[];
    if (copy.actionLabel != null) {
      final onPressed = result.status == 'no_historical_candidates'
          ? onRegisterLocalPurchase
          : onEditNeed;
      if (onPressed != null) {
        actions.add(
          FilledButton(
            key: ValueKey('external-state-action-${result.status}'),
            onPressed: onPressed,
            child: Text(copy.actionLabel!),
          ),
        );
      }
    }
    return _DecisionStateBand(
      key: ValueKey('external-state-${result.status}'),
      title: copy.title,
      body: copy.body,
      actions: actions,
    );
  }
}

/// Cabecera del grupo de candidatos que el ERP no pudo verificar.
///
/// «No lo sé» no es «no cumple»: van en su propio grupo, rotulados, y nunca
/// mezclados con los accionables ni escondidos.
class UnverifiedCandidatesBand extends StatelessWidget {
  const UnverifiedCandidatesBand({
    super.key,
    required this.count,
    required this.page,
    this.onShowMore,
    this.busy = false,
  });

  final int count;
  final SupplyPage page;
  final VoidCallback? onShowMore;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    return Padding(
      key: const ValueKey('unverified-candidates-band'),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1
                ? '1 opción sin verificar'
                : '$count opciones sin verificar',
            style: PurchaseType.sectionTitle,
          ),
          const SizedBox(height: 4),
          Text(
            'La ficha no alcanza para confirmar que cumplen los criterios. '
            'Se muestran igual: no saber no es lo mismo que no calzar.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (page.hasMore) ...[
            const SizedBox(height: 6),
            Text(
              'Mostrando ${page.returned} de ${page.total}.',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
            if (onShowMore != null)
              PurchaseInlineAction(
                key: const ValueKey('show-more-unverified'),
                label: 'Ver más sin verificar',
                onPressed: busy ? null : onShowMore,
              ),
          ],
        ],
      ),
    );
  }
}

/// Evidencia del objetivo comercial para un candidato, señal por señal.
///
/// Una señal `unknown` se dice como «No verificable» **con su causa**, nunca
/// como un cero: un costo en otra moneda o un flete irreproducible son una
/// carencia del dato, no un defecto del candidato.
class RequestMatchEvidence extends StatelessWidget {
  const RequestMatchEvidence({super.key, required this.match});

  final SupplyRequestMatch match;

  @override
  Widget build(BuildContext context) {
    final signals = match.requestedSignals;
    if (signals.isEmpty) return const SizedBox.shrink();
    final tokens = PurchaseTokens.of(context);
    return Column(
      key: const ValueKey('request-match-evidence'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in signals)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${supplySignalLabel(entry.key)} · '
                  '${supplySignalVerdict(entry.value)}',
                  style: PurchaseType.meta,
                ),
                Text(
                  supplySignalReasonLabel(entry.value.reason),
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ],
            ),
          ),
        if (match.blendApplied)
          Text(
            match.knownSignalCount == 1
                ? 'El puntaje mezcla 1 señal verificada con el ranking.'
                : 'El puntaje mezcla ${match.knownSignalCount} señales '
                    'verificadas con el ranking.',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          )
        else
          Text(
            'Ninguna señal pudo verificarse: el puntaje es el del ranking, sin '
            'cambios.',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
      ],
    );
  }
}

/// Paso de stock del **carril familia**: las alternativas internas elegibles.
///
/// El carril exacto tiene su vista de componentes y sets; una necesidad de
/// familia no tiene un solo producto, tiene un conjunto. Antes esta pantalla
/// dependía del snapshot exacto y, sin él, decía «no fue posible verificar el
/// stock interno» aunque el servidor sí hubiera respondido: se afirmaba una
/// falla que no existía y se escondía la bodega que sí había.

/// **Lo comprobado y lo que no, separados.**
///
/// De 128 cámaras del taller sólo 4 tienen ficha técnica, así que una lista
/// ordenada por evidencia sigue leyéndose como un solo lote: la cámara que
/// dice 29 en su nombre queda pegada a una de 26 y el operador tiene que leer
/// el rótulo de cada fila para separarlas.
///
/// La banda no es un encabezado ni una sección nueva: es la misma superficie
/// hundida que ya usa la cabecera del panel, con una sola frase que dice qué
/// viene abajo. Dos grupos, un panel.
class _StockGroupBand extends StatelessWidget {
  const _StockGroupBand({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.sunken,
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Text(
        label,
        style: PurchaseType.label.copyWith(color: tokens.inkFaint),
      ),
    );
  }
}

class FamilyStockOptions extends StatelessWidget {
  const FamilyStockOptions({
    super.key,
    required this.resolution,
    required this.onChooseProduct,
    required this.onCompareProviders,
    required this.busy,
    this.compact = false,
    this.onShowMore,
  });

  final SupplyStockResolution resolution;

  /// Amplía el corte de **bodega**, que es su propia página y no tiene nada
  /// que ver con la de candidatos externos. Sin esto, una alternativa interna
  /// más allá del corte quedaba invisible y sin salida: el servidor decía
  /// `hasMore` y la pantalla no lo mencionaba.
  final VoidCallback? onShowMore;

  /// Fija la identidad de la necesidad desde una alternativa interna. Es una
  /// escritura propia, y por eso tiene su propio botón.
  final ValueChanged<SupplyStockOption> onChooseProduct;
  final VoidCallback onCompareProviders;
  final bool busy;

  /// Teléfono: cards apiladas y CTA a lo ancho, como `frames[single-stock]`
  /// declara para 390. En escritorio manda la fila dentro de un solo panel.
  final bool compact;

  static String _coverageLabel(SupplyStockOption option, double requested) {
    switch (option.coverage) {
      case 'full':
        return 'cubre la necesidad completa';
      case 'partial':
        return 'cubre ${option.availableToPromise} de '
            '${requested.toStringAsFixed(0)}';
      default:
        return 'sin stock disponible';
    }
  }

  /// Una alternativa quedó comprobada cuando algún criterio se estableció
  /// —por ficha o por el nombre curado— y ninguno se contradijo. `no_criteria`
  /// también entra: sin criterios no hay nada que comprobar y esconderla sería
  /// castigarla por una pregunta que nadie hizo.
  /// Qué se revisó y qué quedó sin comprobar, dicho en el mismo lugar.
  ///
  /// Callar lo revisado escondería que el catálogo está sin fichar, que es la
  /// razón real de que haya tan pocas alternativas; decirlo como «alternativas»
  /// sería volver al número que engañaba.
  static String _stockSubtitle(SupplyStockResolution resolution) {
    final counts = resolution.counts;
    const base =
        'Elegir una fija qué producto es la necesidad. Sumar varias no '
        'demuestra cobertura: cada alternativa se evalúa por separado.';
    if (counts.unverified == 0) return base;
    final revisadas = counts.reviewed == 1
        ? 'Se revisó 1 producto de la categoría'
        : 'Se revisaron ${counts.reviewed} productos de la categoría';
    final sinFicha = counts.unverified == 1
        ? '1 quedó sin verificar contra los criterios'
        : '${counts.unverified} quedaron sin verificar contra los criterios';
    return '$revisadas y $sinFicha. $base';
  }

  /// La misma lista positiva que exige el servidor: un estado futuro que nadie
  /// conoce cae del lado de lo no comprobado, que es el lado seguro.
  static bool _isChecked(SupplyStockOption option) => option.isChecked;

  /// «Sin verificar contra los criterios · 47». El número va porque el tamaño
  /// del grupo es la información: dice cuánto del catálogo está sin fichar, que
  /// es la razón real de que estén ahí abajo.
  ///
  /// **Es el total del grupo, no lo que trajo esta página.** Contando las filas
  /// recibidas, la banda decía 11 y pasaba a 22 al pulsar `Ver más` sobre un
  /// grupo que en realidad tiene 47: el número parecía crecer con el scroll y
  /// no describía nada.
  static String _uncheckedBandLabel(SupplyStockResolution resolution) =>
      'POR CONFIRMAR CONTRA LOS CRITERIOS · ${resolution.counts.unverified}';

  static String _matchLabel(String matchState,
      [List<Map<String, dynamic>> matchDetail =
          const <Map<String, dynamic>>[]]) {
    switch (matchState) {
      case 'strong':
        // La procedencia va en la frase: una fila puede estar comprobada por
        // la ficha, por el nombre leído o por la identidad curada, y decir
        // «según la ficha» en los dos últimos casos sería mentira.
        return 'cumple los criterios '
            '${supplyEvidenceProvenanceLabel(matchDetail) ?? 'con la evidencia comprobada'}';
      case 'weak':
        // **«Coincide por el nombre» no es «cumple».** Este rótulo convivía con
        // un botón `Elegir producto`, y con dos de tres criterios sin resolver
        // eso se leía como cumplimiento. La frase dice ahora lo que falta.
        return 'algo coincide; faltan criterios por comprobar';
      case 'no_criteria':
        return 'sin criterios técnicos que comparar';
      default:
        return 'no se pudo verificar contra los criterios';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    final rejection = resolution.internalStockRejectionReason;
    // El servidor ya las devuelve ordenadas por evidencia; acá sólo se parten
    // en dos para que el corte se vea, sin reordenar nada dentro de cada grupo.
    final checked = resolution.items.where(_isChecked).toList(growable: false);
    final unchecked =
        resolution.items.where((option) => !_isChecked(option)).toList(
              growable: false,
            );
    final header = <Widget>[
      Text(
        // La identidad de la superficie, no un encabezado de bloque: es el
        // rol `surface_title` que el spec reserva para Stock interno.
        //
        // **Lo comprobado, no lo revisado.** Este título decía «49 alternativas
        // internas elegibles» sobre un conjunto donde 47 filas no tenían un
        // solo criterio establecido —patines V-Brake, pastillas Avid— porque
        // contaba el universo de la categoría. La categoría dice qué hay que
        // mirar; la compatibilidad la prueban la identidad y los criterios.
        resolution.counts.eligible == 1
            ? '1 alternativa interna comprobada'
            : '${resolution.counts.eligible} alternativas internas comprobadas',
        style: PurchaseType.surfaceTitle.copyWith(color: tokens.ink),
      ),
      const SizedBox(height: 3),
      Text(
        // El agregado de familia no prueba cobertura: sumar dos variantes
        // distintas es una decisión del taller, no una propiedad del stock.
        _stockSubtitle(resolution),
        style: PurchaseType.meta
            .copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      if (rejection != null && rejection.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          'Ya registraste por qué no sirve: «$rejection».',
          style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
        ),
      ],
    ];

    // `frames[single-stock].geometry`: en 1440 y 1116 la columna es 840 y las
    // existencias viven en UN panel con filas separadas por hairline. Esta
    // pantalla las dibujaba como cards sueltas a todo el ancho de la ventana
    // —1.716 px medidos—, que es otra superficie.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: PurchaseSurfaceGeometry.stockColumnMax,
        ),
        child: ListView(
          key: const ValueKey('family-stock-options'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            ...header,
            const SizedBox(height: 12),
            if (compact)
              for (final option in <SupplyStockOption>[
                ...checked,
                ...unchecked,
              ]) ...[
                // En teléfono las cards ya tienen borde, así que el corte es
                // el rótulo y no una banda más: dos bordes seguidos con una
                // franja entremedio son tres líneas para una sola idea.
                if (option == unchecked.firstOrNull && checked.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 2),
                    child: Text(
                      _uncheckedBandLabel(resolution),
                      style:
                          PurchaseType.label.copyWith(color: tokens.inkFaint),
                    ),
                  ),
                ],
                PurchasePanel(
                  child: _FamilyStockCard(
                    option: option,
                    requested: resolution.quantity,
                    busy: busy,
                    onChoose: () => onChooseProduct(option),
                  ),
                ),
                const SizedBox(height: 10),
              ]
            else
              PurchasePanel(
                padded: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StockPanelHeader(
                      left: 'ALTERNATIVA INTERNA',
                      right: 'DISPONIBLE',
                    ),
                    for (final option in checked)
                      _FamilyStockRow(
                        option: option,
                        requested: resolution.quantity,
                        busy: busy,
                        onChoose: () => onChooseProduct(option),
                      ),
                    // La banda sólo existe cuando hay dos grupos que separar.
                    // Con uno solo sería un rótulo sobre nada.
                    if (checked.isNotEmpty && unchecked.isNotEmpty)
                      _StockGroupBand(label: _uncheckedBandLabel(resolution)),
                    for (final option in unchecked)
                      _FamilyStockRow(
                        option: option,
                        requested: resolution.quantity,
                        busy: busy,
                        onChoose: () => onChooseProduct(option),
                      ),
                  ],
                ),
              ),
            if (resolution.page.hasMore) ...[
              const SizedBox(height: PurchaseMetrics.stageGap),
              Text(
                // **Lo paginado son productos revisados, no alternativas.** La
                // página entrega el conjunto entero —comprobado y no—, así que
                // llamarlo «alternativas» volvía a mezclar los dos conceptos
                // justo debajo de un título que ya los separaba.
                'Mostrando ${resolution.page.returned} de '
                '${resolution.page.total} productos revisados.',
                style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: PurchaseInlineAction(
                  key: const ValueKey('show-more-family-stock'),
                  label: 'Ver más en bodega',
                  onPressed: busy ? null : onShowMore,
                ),
              ),
            ],
            const SizedBox(height: PurchaseMetrics.stageGap),
            // El único botón sólido de la superficie es el cierre, como en
            // `frames[single-stock].blocks.cta`. Elegir producto es la acción
            // de una fila y va como secundaria: treinta y cuatro sólidos en
            // una lista no dejan ver cuál es la salida del paso.
            Align(
              alignment: compact ? Alignment.center : Alignment.centerLeft,
              child: SizedBox(
                width: compact ? double.infinity : null,
                height: compact ? 44 : 36,
                child: FilledButton(
                  key: const ValueKey('family-stock-compare-providers'),
                  onPressed: busy ? null : onCompareProviders,
                  child: const Text('Comparar proveedores'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de escritorio de una alternativa interna.
///
/// Misma anatomía que la del carril exacto (`frames[single-stock]`): media 38,
/// identidad elástica, la cifra comparable en su columna de 104 y la acción
/// **secundaria** al final. Antes esto era una card con la acción metida bajo
/// el texto y una foto de 64 —la medida que el contrato de imagen reserva
/// para la card de teléfono—.
class _FamilyStockRow extends StatelessWidget {
  const _FamilyStockRow({
    required this.option,
    required this.requested,
    required this.busy,
    required this.onChoose,
  });

  final SupplyStockOption option;
  final double requested;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProductMediaTile(
            media: option.media,
            name: option.name,
            size: PurchaseSurfaceGeometry.mediaStockRow,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(option.name, style: PurchaseType.rowTitle),
                const SizedBox(height: 2),
                Text(
                  [
                    if (option.sku != null) option.sku!,
                    FamilyStockOptions._coverageLabel(option, requested),
                    // «No lo sé» no es «no cumple»: se rotula y se sigue.
                    FamilyStockOptions._matchLabel(
                        option.matchState, option.matchDetail),
                  ].join(' · '),
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
                if (option.evidenceState != 'unknown') ...[
                  const SizedBox(height: 2),
                  Text(
                    supplySourcingLabel(option),
                    style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
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
                Text(
                  '${option.availableToPromise}',
                  style: PurchaseType.metricSmall.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'necesitas ${requested.round()}',
                  textAlign: TextAlign.end,
                  style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // **Elegir fija la identidad de la necesidad: exige prueba.** Sobre
          // una fila que nadie pudo verificar, «Elegir producto» convertía una
          // coincidencia de categoría en la respuesta del taller. Se conserva
          // visible —el operador puede mirarla y decidir con sus ojos— pero sin
          // el atajo que la declara compatible.
          if (option.isUnverified)
            Text(
              'sin verificar',
              key: ValueKey('unverified-stock-note-${option.productId}'),
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            )
          else
            OutlinedButton(
              key: ValueKey('choose-stock-product-${option.productId}'),
              onPressed: busy ? null : onChoose,
              child: const Text('Elegir producto'),
            ),
        ],
      ),
    );
  }
}

/// Card de teléfono: media 64 y CTA a lo ancho (`frames[single-stock].390`).
class _FamilyStockCard extends StatelessWidget {
  const _FamilyStockCard({
    required this.option,
    required this.requested,
    required this.busy,
    required this.onChoose,
  });

  final SupplyStockOption option;
  final double requested;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductMediaTile(
              media: option.media,
              name: option.name,
              size: PurchaseSurfaceGeometry.mediaStockPhoneCard,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.name,
                    style: PurchaseType.cardTitle.copyWith(color: tokens.ink),
                  ),
                  if (option.sku != null)
                    Text(
                      option.sku!,
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '${option.availableToPromise} disponibles · '
                    '${FamilyStockOptions._coverageLabel(option, requested)}',
                    style: PurchaseType.meta,
                  ),
                  // **El mismo veredicto no se dice dos veces.** En una fila
                  // sin verificar, esta línea y la nota que reemplaza al botón
                  // decían lo mismo con distintas palabras, una encima de la
                  // otra. La nota se queda —está donde estaría el CTA y
                  // explica por qué no hay— y acá se calla lo que ya se dijo.
                  // En las demás filas sí aporta: es la única que nombra de
                  // dónde salió la evidencia, y ésas sí llevan botón.
                  if (!option.isUnverified)
                    Text(
                      // La procedencia también en el teléfono: sin
                      // `matchDetail` la tarjeta compacta decía «según la
                      // ficha» de una fila comprobada por su nombre, que es la
                      // misma mentira con menos ancho.
                      FamilyStockOptions._matchLabel(
                          option.matchState, option.matchDetail),
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                  if (option.evidenceState != 'unknown')
                    Text(
                      supplySourcingLabel(option),
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        // **Elegir fija la identidad de la necesidad: exige prueba.** Sobre
        // una fila que nadie pudo verificar, «Elegir producto» convertía una
        // coincidencia de categoría en la respuesta del taller. Se conserva
        // visible —el operador puede mirarla y decidir con sus ojos— pero sin
        // el atajo que la declara compatible.
        if (option.isUnverified)
          Text(
            'no se pudo verificar contra los criterios',
            key: ValueKey('unverified-stock-note-${option.productId}'),
            style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
          )
        else
          SizedBox(
            height: PurchaseMetrics.touchTarget,
            child: OutlinedButton(
              key: ValueKey('choose-stock-product-${option.productId}'),
              onPressed: busy ? null : onChoose,
              child: const Text('Elegir producto'),
            ),
          ),
      ],
    );
  }
}

/// Editor compacto del objetivo comercial tipado.
///
/// **Existe porque el control anterior mentía.** El menú «Perfil» cambiaba una
/// cadena del cliente y volvía a pedir la misma lectura: el servidor toma el
/// perfil de la revisión, así que el resultado llegaba idéntico. Lo que sí
/// mueve el ranking es este objetivo, y hasta ahora no había forma de fijarlo.
///
/// **La moneda se muestra antes de guardar y no se envía.** Es del servidor, y
/// una carga que la traiga se rechaza; enseñarla es lo que impide que alguien
/// escriba 12.000 pensando en otra.
class CommercialTargetEditor extends StatefulWidget {
  const CommercialTargetEditor({
    super.key,
    required this.target,
    required this.onSave,
    required this.onCancel,
    required this.busy,
  });

  final SupplyCommercialTarget target;

  /// Parche explícito: clave ausente conserva, clave en `null` limpia.
  final ValueChanged<Map<String, Object?>> onSave;
  final VoidCallback onCancel;
  final bool busy;

  @override
  State<CommercialTargetEditor> createState() => _CommercialTargetEditorState();
}

class _CommercialTargetEditorState extends State<CommercialTargetEditor> {
  /// «Sin preferencia» es un valor del control, no la ausencia de control: sin
  /// él no habría forma de quitar una gama ya fijada.
  static const Map<String, String> _gamaOptions = {
    '': 'Sin preferencia',
    'economica': 'Económica',
    'media': 'Media',
    'alta': 'Alta',
  };

  /// Techo del servidor (`999999999`), repetido acá para atajar el error antes
  /// de gastar una llamada que el backend rechazaría igual.
  static const double _maxCost = 999999999;

  late String? _gama;
  late TextEditingController _cost;
  late TextEditingController _margin;
  String? _costError;
  String? _marginError;

  @override
  void initState() {
    super.initState();
    _adoptTarget();
  }

  @override
  void didUpdateWidget(CommercialTargetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **Otro objetivo es otro estado.** El editor conservaba los controllers de
    // la primera necesidad: abrirlo en A y cambiar a B mostraba —y guardaba—
    // los números de A sobre B. La identidad de un objetivo es la necesidad
    // más su revisión y la versión de la necesidad; si cualquiera cambia, este
    // formulario ya no habla de lo mismo.
    if (_targetIdentity(oldWidget.target) != _targetIdentity(widget.target)) {
      _cost.dispose();
      _margin.dispose();
      _adoptTarget();
    }
  }

  static String _targetIdentity(SupplyCommercialTarget target) =>
      '${target.needId}:${target.targetRevisionNo}:${target.needVersion}';

  void _adoptTarget() {
    final values = widget.target.target;
    _gama = values.gama;
    _costError = null;
    _marginError = null;
    _cost = TextEditingController(
      text: values.maxLandedUnitCostNet == null
          ? ''
          : values.maxLandedUnitCostNet!.toStringAsFixed(0),
    );
    _margin = TextEditingController(
      text: values.minGrossMarginRatio == null
          ? ''
          : (values.minGrossMarginRatio! * 100).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _cost.dispose();
    _margin.dispose();
    super.dispose();
  }

  /// Acepta coma o punto: el taller escribe «12,5» y eso no es un error suyo.
  static double? _parseDecimal(String raw) =>
      double.tryParse(raw.replaceAll(',', '.'));

  void _save() {
    final costText = _cost.text.trim();
    final marginText = _margin.text.trim();
    String? costError;
    String? marginError;
    double? cost;
    double? margin;

    // **Un texto inválido no se convierte en nada.** Antes un tope ilegible
    // caía a `null` y borraba el tope en silencio, y un margen ilegible caía a
    // `0`, que es un piso legítimo: dos pérdidas mudas de la decisión del
    // operador. Vacío sigue significando limpiar, porque eso sí lo dijo.
    if (costText.isNotEmpty) {
      cost = _parseDecimal(costText);
      if (cost == null || !cost.isFinite) {
        costError = 'Escribe un número, con coma o punto.';
      } else if (cost <= 0) {
        costError = 'El tope tiene que ser mayor que cero.';
      } else if (cost > _maxCost) {
        costError = 'El tope máximo es 999.999.999.';
      }
    }
    if (marginText.isNotEmpty) {
      margin = _parseDecimal(marginText);
      if (margin == null || !margin.isFinite) {
        marginError = 'Escribe un número, con coma o punto.';
      } else if (margin < 0 || margin > 100) {
        marginError = 'El margen va entre 0 y 100.';
      }
    }
    if (costError != null || marginError != null) {
      setState(() {
        _costError = costError;
        _marginError = marginError;
      });
      return;
    }

    setState(() {
      _costError = null;
      _marginError = null;
    });
    widget.onSave(<String, Object?>{
      'gama': _gama,
      // Un campo vacío **limpia** ese objetivo: `null` explícito, que es
      // distinto de omitir la clave.
      'maxLandedUnitCostNet': cost,
      'minGrossMarginRatio': margin == null ? null : margin / 100,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PurchaseTokens.of(context);
    final brandId = widget.target.target.preferredBrandId;
    return PurchasePanel(
      key: const ValueKey('commercial-target-editor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Objetivo del taller',
            style: PurchaseType.panelTitle.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 3),
          Text(
            'Reordena las opciones sin descartar ninguna. Los montos van en '
            '${widget.target.currencyCode}, la moneda que el servidor fija.',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
          if (widget.target.currencyRebased) ...[
            const SizedBox(height: 4),
            Text(
              'El taller opera hoy en ${widget.target.tenantCurrencyCode}: un '
              'tope guardado en ${widget.target.currencyCode} hay que '
              'reingresarlo para que signifique lo de hoy.',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ],
          const SizedBox(height: 11),
          // El desplegable anclado es el control de este módulo para un valor
          // excluyente. Una fila de chips no pertenece a su vocabulario.
          Align(
            alignment: Alignment.centerLeft,
            child: _AnchoredMenuButton(
              menuId: 'commercial-target-gama',
              label: 'Gama · ${_gamaOptions[_gama ?? ''] ?? 'Sin preferencia'}',
              enabled: !widget.busy,
              sections: [
                _MenuSection(
                  value: _gama ?? '',
                  options: _gamaOptions,
                  onSelected: (value) =>
                      setState(() => _gama = value.isEmpty ? null : value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          TextField(
            key: const ValueKey('commercial-target-cost'),
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  'Tope de costo aterrizado (${widget.target.currencyCode})',
              helperText: 'Vacío quita el tope.',
              errorText: _costError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 9),
          TextField(
            key: const ValueKey('commercial-target-margin'),
            controller: _margin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Margen mínimo (%)',
              helperText: 'Vacío quita el piso.',
              errorText: _marginError,
              border: const OutlineInputBorder(),
            ),
          ),
          if (brandId != null) ...[
            const SizedBox(height: 9),
            Text(
              // La marca se conserva tal cual: sin un selector no se puede
              // ofrecer cambiarla, y un campo de UUID no es una opción.
              widget.target.preferredBrandAvailable == false
                  ? 'Marca preferida guardada · ya no está disponible. Se '
                      'conserva hasta que exista un selector de marcas.'
                  : 'Marca preferida guardada. Se conserva hasta que exista un '
                      'selector de marcas.',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ],
          const SizedBox(height: PurchaseMetrics.actionsTopGap),
          Row(
            children: [
              PurchaseInlineAction(
                key: const ValueKey('commercial-target-cancel'),
                label: 'Cancelar',
                onPressed: widget.busy ? null : widget.onCancel,
              ),
              const Spacer(),
              PurchasePrimaryButton(
                key: const ValueKey('commercial-target-save'),
                label: 'Guardar objetivo',
                onPressed: widget.busy ? null : _save,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Guardar vuelve a pedir las opciones al servidor.',
            style: PurchaseType.meta
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
