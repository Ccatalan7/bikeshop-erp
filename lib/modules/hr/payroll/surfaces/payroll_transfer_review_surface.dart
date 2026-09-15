import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

/// Building blocks of the transfer-review step.
///
/// Visual grammar from `ERP Bikeshop UI Mockups`, page `Nóminas - Rediseño`
/// (frames 2c y 7c): fila densa, tag de estado que nombra el PORQUÉ, acción
/// suave con borde acentuado, y el pie de impacto que posee la página.
///
/// **La composición de la etapa cambió el 2026-08-10 por instrucción del
/// dueño**, después de usarla con una cartola real de 96 movimientos: la
/// versión anterior —UNA decisión por pantalla, en tarjeta, con las demás
/// apiladas debajo como bloques de página completa y tres grupos plegables—
/// era ilegible («I literally don't understand anything on what the fuck is
/// going on there»). Ahora la etapa es **una tabla**, con la misma gramática
/// que la lectura del paso 2, dos columnas de dinero enfrentadas —lo que pagó
/// la cartola contra lo que debe la nómina— y la decisión en un `S-05` por
/// fila. Por eso ya no existen aquí una tarjeta de pregunta abierta, su
/// contador `i DE n`, ni las secciones plegables.
///
/// These widgets are presentation-only: every decision, idempotency and
/// navigation contract stays in `PayrollReconciliationPage`.

/// Soft (accent-tinted, bordered) action from the 2c handoff — la aprobación en
/// lote de los calces exactos y el «Aceptar como redondeo» de una diferencia.
class PayrollSoftAction extends StatelessWidget {
  const PayrollSoftAction({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 30,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? visual.accentSoft : visual.surfaceSunken,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          side: BorderSide(
            color: enabled ? visual.accentBorder : visual.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: visual.labelStrong.copyWith(
                fontSize: 11,
                color: enabled ? visual.accent : visual.inkDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One dense 46px ledger row of the 2c statement evidence grid:
/// `date | description (mono) | amount | person/status | trailing`.
/// Below 560px it recomposes into a deliberate two-line mobile row.
class PayrollStatementLedgerRow extends StatelessWidget {
  const PayrollStatementLedgerRow({
    super.key,
    required this.date,
    required this.description,
    required this.amount,
    this.person,
    this.personDetail,
    this.initials,
    this.avatarColor,
    this.statusLabel,
    this.statusTone,
    this.trailing,
    this.inlineNote,
    this.inlineNoteDotColor,
    this.isFirst = false,
  });

  final String date;
  final String description;
  final String amount;
  final String? person;
  final String? personDetail;
  final String? initials;
  final Color? avatarColor;
  final String? statusLabel;
  final PayrollStateTone? statusTone;
  final Widget? trailing;
  final String? inlineNote;
  final Color? inlineNoteDotColor;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: isFirst ? BorderSide.none : BorderSide(color: visual.border),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 560;
              if (stacked) return _buildStacked(visual);
              return _buildWide(visual);
            },
          ),
        ),
        if (inlineNote != null)
          Container(
            padding: const EdgeInsets.fromLTRB(77, 7, 17, 9),
            decoration: BoxDecoration(
              color: visual.surfaceSunken,
              border: Border(top: BorderSide(color: visual.border)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: inlineNoteDotColor ?? visual.successFg,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    inlineNote!,
                    style: visual.monoM.copyWith(fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildWide(PayrollVisualTokens visual) {
    return SizedBox(
      height: 46,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 60,
            child: Text(
              date,
              style: visual.monoM.copyWith(fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: visual.monoM.copyWith(
                fontSize: 11.5,
                color: visual.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 108,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: visual.monoM.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: visual.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: person == null && statusLabel != null
                ? Align(
                    alignment: Alignment.centerRight,
                    child: _statusTag(visual),
                  )
                : _personCell(visual),
          ),
          if (statusLabel != null && person != null) ...<Widget>[
            const SizedBox(width: 12),
            _statusTag(visual),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _buildStacked(PayrollVisualTokens visual) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(date, style: visual.monoM.copyWith(fontSize: 11)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description,
                  style: visual.monoM.copyWith(
                    fontSize: 11.5,
                    color: visual.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                amount,
                style: visual.monoM.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: visual.ink,
                ),
              ),
            ],
          ),
          if (person != null || statusLabel != null) ...[
            const SizedBox(height: 7),
            Row(
              children: <Widget>[
                Expanded(child: _personCell(visual)),
                if (statusLabel != null) ...<Widget>[
                  const SizedBox(width: 10),
                  _statusTag(visual),
                ],
              ],
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(height: 7),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ],
      ),
    );
  }

  Widget _personCell(PayrollVisualTokens visual) {
    if (person == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        if (initials != null)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: avatarColor ?? visual.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials!,
              style: visual.bodyM.copyWith(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: visual.shell,
              ),
            ),
          ),
        if (initials != null) const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                person!,
                style: visual.bodyM.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (personDetail != null)
                Text(
                  personDetail!,
                  style: visual.monoS.copyWith(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusTag(PayrollVisualTokens visual) {
    final tone = statusTone ?? visual.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rTag),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        statusLabel!,
        style: visual.monoS.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: tone.fg,
        ),
      ),
    );
  }
}

/// 2c decision option card: radio dot, title, honest description and a tone
/// tag. Replaces every generic Material chip in the reconciliation review.
class PayrollDecisionOptionCard extends StatelessWidget {
  const PayrollDecisionOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.tag,
    required this.tone,
    required this.selected,
    required this.onSelect,
    this.movementId,
    this.optionName,
  });

  final String title;
  final String description;
  final String tag;
  final PayrollStateTone tone;
  final bool selected;
  final VoidCallback? onSelect;

  /// Identidad estable del movimiento al que pertenece esta opción. Nula sólo
  /// donde la tarjeta no vive en una lista (no hay ambigüedad que resolver).
  final String? movementId;

  /// Nombre estable de la opción (`confirm`, `notPayroll`…). El título visible
  /// puede cambiar de redacción; esto no.
  final String? optionName;

  /// Identidad estable de ESTA opción en ESTE movimiento. Nula cuando la
  /// tarjeta no vive en una lista y no hay ambigüedad que resolver.
  ///
  /// No se usa índice ni contador: la lista se acorta a medida que se
  /// responde, así que un índice apuntaría a otra fila en la vuelta siguiente.
  String? get identity {
    final id = movementId?.trim();
    if (id == null || id.isEmpty) return null;
    return 'payroll-ocr-decision-$id-${optionName ?? title}';
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final enabled = onSelect != null;
    final key = identity;
    return KeyedSubtree(
      key: key == null ? null : ValueKey<String>(key),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        // **Identidad por movimiento, SIN tocar lo que se lee en voz alta.**
        // Las cuatro opciones tienen el mismo rótulo en las diez tarjetas de la
        // etapa, así que quien resuelve por identidad —una automatización, o el
        // rotor de VoiceOver— encontraba diez «No es nómina» indistinguibles.
        //
        // El id NO va en el `label`: meterlo ahí obligaría a escuchar
        // «Movimiento p1-l34-r1» en cada opción, que es ruido para quien usa
        // lector de pantalla. Va en `identifier`, que es exactamente el campo
        // para identidad de automatización, y en una `ValueKey` con el mismo
        // valor para que `app_control tap --key` lo alcance.
        label: '$title. $description',
        identifier: identity,
        excludeSemantics: true,
        child: Material(
          color: selected ? visual.surfaceSelected : visual.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            side: BorderSide(
              color: selected ? visual.accent : visual.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelect,
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          // accent-fill: selection (radio dot of the selected
                          // decision option; no content is painted over it)
                          color: selected ? visual.accent : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                selected ? visual.accent : visual.borderStrong,
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: visual.cardTitle.copyWith(
                            fontSize: 12,
                            color: !enabled
                                ? visual.inkDisabled
                                : selected
                                    ? visual.ink
                                    : visual.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: visual.bodyS.copyWith(
                      fontSize: 10.5,
                      height: 1.45,
                      color: enabled ? visual.inkFaint : visual.inkDisabled,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tone.soft,
                      borderRadius: BorderRadius.circular(PayrollTokens.rTag),
                    ),
                    child: Text(
                      tag,
                      style: visual.monoS.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: tone.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confidence pill of Design t5 (frame 5j, step 3). It shows the matcher's
/// real score while the machine owns the proposal, and flips to MANUAL 100%
/// the moment a person takes responsibility for the row: certainty stops
/// being an estimate and becomes accountability.
class PayrollConfidencePill extends StatelessWidget {
  const PayrollConfidencePill({
    super.key,
    required this.score,
    required this.manual,
  });

  final int? score;
  final bool manual;

  /// The score is kept as INPUT because the matcher computes it and the
  /// thresholds still drive which verb the row offers. It is deliberately not
  /// PRINTED.
  ///
  /// A percentage here was false precision: the number is a heuristic product
  /// of name × amount × date-in-window, not a calibrated probability, so "61%"
  /// asserted a measurement nobody took. It also invited the one behaviour this
  /// screen must not allow — approving everything above some threshold —
  /// while the design's own note concedes that "un 63% pelado" is not something
  /// anyone can decide with.
  ///
  /// What the operator actually needs is next to this pill already: the reason
  /// tag that names WHY (`CALCE EXACTO`, `MONTO DISTINTO`,
  /// `SIN PERSONA DE NÓMINA`). This pill therefore states only what the system
  /// honestly knows, in words.
  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    if (manual) {
      return _pill(visual, visual.info, 'TÚ LO DECIDISTE');
    }
    if (score == null) {
      return _pill(visual, visual.neutral, 'SIN CALCE');
    }
    if (score! >= 90) {
      return _pill(visual, visual.success, 'CALZA');
    }
    if (score! >= 70) {
      return _pill(visual, visual.warning, 'REVISA');
    }
    return _pill(visual, visual.danger, 'NO SÉ QUIÉN ES');
  }

  Widget _pill(PayrollVisualTokens visual, PayrollStateTone tone, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rPill),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        text,
        style: visual.monoS.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: tone.fg,
        ),
      ),
    );
  }
}

/// Small state tag that names WHY a row looks the way it does
/// (`CALCE EXACTO`, `MONTO DISTINTO`, `SIN PERSONA DE NÓMINA`…).
class PayrollRowStateTag extends StatelessWidget {
  const PayrollRowStateTag({
    super.key,
    required this.label,
    required this.tone,
  });

  final String label;
  final PayrollStateTone tone;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rTag),
      ),
      child: Text(
        label,
        style: visual.monoS.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: tone.fg,
        ),
      ),
    );
  }
}

/// Header of the review table: title, per-bucket counters and the exact
/// matching rule, so the operator reads the criteria before the rows.
class PayrollReviewTableHeader extends StatelessWidget {
  const PayrollReviewTableHeader({
    super.key,
    required this.buckets,
    required this.rule,
  });

  /// (label, count, tone) triples rendered as chips.
  final List<(String, int, PayrollStateTone)> buckets;
  final String rule;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 11, 17, 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              'Propuestas de pago',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: visual.sectionTitle.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          for (final bucket in buckets)
            if (bucket.$2 > 0) ...<Widget>[
              PayrollRowStateTag(
                label: '${bucket.$2} ${bucket.$1}',
                tone: bucket.$3,
              ),
              const SizedBox(width: 6),
            ],
          const Spacer(),
          Flexible(
            child: Text(
              rule,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: visual.monoS.copyWith(fontSize: 9.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the review table (Design t5, frame 5j step 3).
///
/// Wide layout mirrors the concept's grid — date · movement (+state tag) ·
/// amount · person and week · why it matches · confidence · decision.
/// Below 900 the same content recomposes into two readable lines instead of
/// forcing a horizontal scroll. Rows that need judgement expand in place;
/// the expansion is where the full evidence and controls live, so the table
/// never hides mandatory work behind a modal.
/// Las siete pistas de `7c` (proyecto `ERP Bikeshop UI Mockups`, página
/// `Nóminas - Rediseño`, turno 7, frames `7c-ocr-{pacific,aubergine}`), leídas
/// literales del archivo con `DesignSync`:
/// `26px 76px minmax(190px,1fr) 118px minmax(200px,1.1fr) 148px 84px`, gap 10,
/// fila con padding `10 16`.
const double reviewColCaret = 26;
const double reviewColDate = 76;
const double reviewColAmount = 118;
const double reviewColGap = 10;
const double reviewRowPadH = 16;

/// La pista que 7c reserva para `CONFIANZA` la ocupa acá el **monto que la
/// nómina espera**, con el mismo ancho de dinero que publica 7c (118).
///
/// **Corrección del dueño, 2026-08-10** (revisando la etapa en la app viva):
/// *«where is really easy to identify the vs, between what was on the cartola
/// vs what have to be paid on payrolls»*. Esa comparación es la decisión de la
/// etapa y no tenía columna: el monto esperado vivía escondido como segunda
/// línea de la celda de persona, y la columna que sí existía —confianza— no
/// mueve ninguna decisión. La confianza baja al detalle de la fila, donde
/// sigue siendo auditable; el contraste sube a columna.
const double reviewColExpected = 118;

/// 7c pone 84 para su enlace `Cambiar`. Acá la pista lleva el control de
/// decisión —`S-05` con las cuatro respuestas posibles—, cuya etiqueta más
/// larga («Retener como excepción», 12px) más el relleno y el caret del
/// componente no cabe en 84: se declara la diferencia en vez de recortar un
/// control canónico para calzar un ancho.
const double reviewColDecision = 190;

/// La fila de RÓTULOS DE COLUMNA de `7c`.
///
/// No se llama `…TableHeader` porque ese nombre ya lo tiene el encabezado de
/// la tarjeta —título, contadores y la regla de calce—: son dos cosas
/// distintas y colisionaron una vez.
///
/// Sólo existe desde 900: bajo ese ancho la fila se recompone en bloques y
/// unos rótulos sobre columnas que ya no existen serían ruido.
class PayrollReviewColumnHeader extends StatelessWidget {
  const PayrollReviewColumnHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) return const SizedBox.shrink();
        return Container(
          key: const ValueKey<String>('payroll-review-column-header'),
          padding:
              const EdgeInsets.fromLTRB(reviewRowPadH, 7, reviewRowPadH, 7),
          decoration: BoxDecoration(
            color: visual.surfaceSunken,
            border: Border(bottom: BorderSide(color: visual.border)),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: reviewColCaret),
              const SizedBox(width: reviewColGap),
              SizedBox(
                width: reviewColDate,
                child: Text('FECHA', style: visual.overline),
              ),
              const SizedBox(width: reviewColGap),
              Expanded(
                flex: 10,
                child: Text(
                  'DESCRIPCIÓN EN LA CARTOLA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.overline,
                ),
              ),
              const SizedBox(width: reviewColGap),
              SizedBox(
                width: reviewColAmount,
                child: Text(
                  'CARTOLA',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.overline,
                ),
              ),
              const SizedBox(width: reviewColGap),
              Expanded(
                flex: 11,
                child: Text(
                  'PERSONA Y SEMANA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.overline,
                ),
              ),
              const SizedBox(width: reviewColGap),
              SizedBox(
                width: reviewColExpected,
                child: Text(
                  'NÓMINA',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.overline,
                ),
              ),
              const SizedBox(width: reviewColGap),
              SizedBox(
                width: reviewColDecision,
                child: Text('QUÉ HACER', style: visual.overline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PayrollReviewTableRow extends StatelessWidget {
  const PayrollReviewTableRow({
    super.key,
    required this.date,
    required this.description,
    required this.amount,
    required this.stateTag,
    required this.stateTone,
    required this.why,
    required this.decision,
    this.expectedAmount = '—',
    this.varianceNote,
    this.person,
    this.personDetail,
    this.initials,
    this.avatarColor,
    this.expanded = false,
    this.onToggleExpanded,
    this.expansion,
    this.isFirst = false,
    this.settled = false,
  });

  final String date;
  final String description;

  /// Lo que se movió en el banco. Es un hecho de la cartola.
  final String amount;

  /// Lo que la semana de nómina espera para esta persona. `—` cuando la fila no
  /// apunta a ninguna obligación: un cargo ajeno no tiene contra qué contrastar
  /// y un cero inventado ahí sería una afirmación falsa.
  final String expectedAmount;

  /// La diferencia con signo, sólo cuando existe. Va bajo el monto esperado
  /// porque es la resta de las dos columnas de dinero, no un dato aparte.
  final String? varianceNote;
  final String stateTag;
  final PayrollStateTone stateTone;
  final String why;
  final Widget decision;
  final String? person;
  final String? personDetail;
  final String? initials;
  final Color? avatarColor;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final Widget? expansion;
  final bool isFirst;

  /// A row already answered reads as quiet evidence, not as pending work.
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final movement = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.monoM.copyWith(
            fontSize: 11.5,
            color: settled ? visual.inkMuted : visual.ink,
          ),
        ),
        const SizedBox(height: 3),
        PayrollRowStateTag(label: stateTag, tone: stateTone),
      ],
    );

    final personCell = person == null
        ? Text('—', style: visual.monoM.copyWith(fontSize: 11))
        : Row(
            children: <Widget>[
              if (initials != null) ...<Widget>[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: avatarColor ?? visual.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials!,
                    style: visual.bodyM.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: visual.shell,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      person!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.bodyM.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (personDetail != null)
                      Text(
                        personDetail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.monoS.copyWith(fontSize: 9.5),
                      ),
                    // `7c`: la razón es la segunda línea de la celda de persona.
                    Text(
                      why,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(
                        fontSize: 10,
                        color: visual.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    // Las dos columnas de dinero se leen como una comparación: mismo estilo
    // numérico, misma alineación derecha, y la diferencia debajo de lo que la
    // nómina espera. Sin ese contraste la etapa obliga a abrir cada fila para
    // saber si el banco pagó de más o de menos.
    final expectedCell = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          expectedAmount,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.numRow.copyWith(
            fontSize: 13,
            color: settled ? visual.inkMuted : visual.ink,
          ),
        ),
        if (varianceNote != null)
          Text(
            varianceNote!,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.monoS.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: visual.warningFg,
            ),
          ),
      ],
    );

    final whyText = Text(
      why,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: visual.bodyS.copyWith(
        fontSize: 10.5,
        height: 1.35,
        color: visual.inkMuted,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        // `7c`: la fila marcada va en `selectionRow`, no en `sunken`. El
        // hundido es profundidad de disclosure; la selección tiene su propio
        // rol y ΔE medido contra el surface.
        color: expanded ? visual.surfaceSelected : null,
        border: Border(
          top: isFirst ? BorderSide.none : BorderSide(color: visual.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: reviewRowPadH,
                  vertical: 10,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      // Las siete pistas de `7c`, leídas del archivo de Design:
                      // `26px 76px minmax(190px,1fr) 118px minmax(200px,1.1fr)
                      // 148px 84px`, gap 10. La primera lleva el caret —el
                      // mismo rol que en 7a—, y la RAZÓN baja bajo la persona,
                      // que es donde 7c la dibuja: como segunda línea, no como
                      // columna propia. La sexta pista pasa de confianza a
                      // monto esperado (ver [reviewColExpected]) y la séptima
                      // se ensancha para el `S-05` de decisión.
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: reviewColCaret,
                            child: onToggleExpanded == null
                                ? null
                                : Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    size: 18,
                                    color: visual.inkFaint,
                                  ),
                          ),
                          const SizedBox(width: reviewColGap),
                          SizedBox(
                            width: reviewColDate,
                            child: Text(
                              date,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: visual.monoS.copyWith(
                                fontSize: 10.5,
                                color: visual.inkMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: reviewColGap),
                          Expanded(flex: 10, child: movement),
                          const SizedBox(width: reviewColGap),
                          SizedBox(
                            width: reviewColAmount,
                            child: Text(
                              amount,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: visual.numRow.copyWith(
                                fontSize: 13,
                                color: settled ? visual.inkMuted : visual.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: reviewColGap),
                          Expanded(flex: 11, child: personCell),
                          const SizedBox(width: reviewColGap),
                          SizedBox(
                            width: reviewColExpected,
                            child: expectedCell,
                          ),
                          const SizedBox(width: reviewColGap),
                          // 7c dibuja acá un enlace (`Cambiar` / `Asignar`) de
                          // 84. Este ERP resuelve la fila con el selector
                          // canónico `S-05`, que necesita más: la pista se
                          // ensancha lo que ese control pide, y queda
                          // declarado en [reviewColDecision].
                          SizedBox(width: reviewColDecision, child: decision),
                        ],
                      );
                    }
                    // Compacto: la misma comparación, apilada. Cada monto lleva
                    // su rótulo porque acá no hay encabezado de columna que lo
                    // diga, y sin él «$35.000 / $133.000» no se sabe cuál es
                    // cuál — que es justo la lectura que la etapa necesita.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              date,
                              style: visual.monoM.copyWith(fontSize: 11),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: movement),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _CompactMoney(
                                label: 'CARTOLA',
                                value: amount,
                                settled: settled,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CompactMoney(
                                label: 'NÓMINA',
                                value: expectedAmount,
                                note: varianceNote,
                                settled: settled,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        personCell,
                        const SizedBox(height: 7),
                        whyText,
                        const SizedBox(height: 9),
                        decision,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (expanded && expansion != null) ...<Widget>[
            Divider(height: 1, color: visual.border),
            expansion!,
          ],
        ],
      ),
    );
  }
}

/// Un monto con su rótulo, para el ancho compacto de [PayrollReviewTableRow].
class _CompactMoney extends StatelessWidget {
  const _CompactMoney({
    required this.label,
    required this.value,
    required this.settled,
    this.note,
  });

  final String label;
  final String value;
  final String? note;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.overline),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.numRow.copyWith(
            fontSize: 13,
            color: settled ? visual.inkMuted : visual.ink,
          ),
        ),
        if (note != null)
          Text(
            note!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.monoS.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: visual.warningFg,
            ),
          ),
      ],
    );
  }
}
