import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';

/// Claude Design 2c — building blocks of the transfer-review step.
///
/// Source: `ERP Bikeshop UI Mockups`, page `Nóminas - Rediseño`, frame 2c and
/// the exact Flutter handoff bundle (`payroll_reconciliation_surface.dart`,
/// section "Paso 2"). The concept's composition is: ONE pending decision per
/// viewport leading the step, dense 46px statement ledger rows inside
/// collapsible evidence sections (suggestions with a batch approval, foreign
/// movements and incoming credits collapsed), and the persistent impact
/// footer owned by the page.
///
/// These widgets are presentation-only: every decision, idempotency and
/// navigation contract stays in `PayrollReconciliationPage`.

/// Leading card of the step: one question at a time with a `i DE n` counter.
class PayrollPendingDecisionCard extends StatelessWidget {
  const PayrollPendingDecisionCard({
    super.key,
    required this.counterLabel,
    required this.explainer,
    required this.child,
    this.onPrevious,
    this.onNext,
  });

  final String counterLabel;
  final String explainer;
  final Widget child;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
        boxShadow: visual.raised,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: visual.border)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: visual.warningFg,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Pendiente de decisión',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.sectionTitle.copyWith(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    explainer,
                    style: visual.bodyS.copyWith(
                      fontSize: 11,
                      color: visual.inkFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onPrevious != null || onNext != null) ...<Widget>[
                  _CounterArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: onPrevious,
                    semanticsLabel: 'Pregunta anterior',
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: visual.warningSoft,
                    borderRadius: BorderRadius.circular(PayrollTokens.rPill),
                    border: Border.all(color: visual.warningBorder),
                  ),
                  child: Text(
                    counterLabel,
                    style: visual.labelStrong.copyWith(
                      fontSize: 9.5,
                      color: visual.warningFg,
                    ),
                  ),
                ),
                if (onPrevious != null || onNext != null) ...<Widget>[
                  const SizedBox(width: 4),
                  _CounterArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: onNext,
                    semanticsLabel: 'Siguiente pregunta',
                  ),
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _CounterArrow extends StatelessWidget {
  const _CounterArrow({
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? visual.inkDisabled : visual.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet confirmation shown when the pending queue is empty: the step never
/// leaves a large void where the leading card was.
class PayrollNoPendingDecisionsCard extends StatelessWidget {
  const PayrollNoPendingDecisionsCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: visual.successFg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Sin ambigüedades pendientes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: visual.sectionTitle.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: visual.bodyS.copyWith(
                fontSize: 11,
                color: visual.inkFaint,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible 2c evidence section: disclosure arrow, semantic dot, title,
/// subtitle and an optional trailing action on a 44px header.
class PayrollReviewSection extends StatelessWidget {
  const PayrollReviewSection({
    super.key,
    required this.dotColor,
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onToggle,
    required this.child,
    this.trailing,
  });

  final Color dotColor;
  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: open,
            label: '$title. $subtitle',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        open
                            ? Icons.arrow_drop_down_rounded
                            : Icons.arrow_right_rounded,
                        size: 18,
                        color: visual.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: visual.sectionTitle.copyWith(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: visual.bodyS.copyWith(
                            fontSize: 11,
                            color: visual.inkFaint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trailing != null) ...<Widget>[
                        const SizedBox(width: 10),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open) ...<Widget>[
            Divider(height: 1, color: visual.border),
            child,
          ],
        ],
      ),
    );
  }
}

/// Soft (accent-tinted, bordered) action from the 2c handoff — batch approval
/// and per-row `Confirmar`/`Revisar`/`Cambiar` links.
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
          Expanded(child: _personCell(visual)),
          if (statusLabel != null) ...<Widget>[
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
  });

  final String title;
  final String description;
  final String tag;
  final PayrollStateTone tone;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final enabled = onSelect != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$title. $description',
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
                          color: selected ? visual.accent : visual.borderStrong,
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
    );
  }
}

/// Advance CTA shown inside the pending card once the current question is
/// answered — the Design "Guardar decisión" slot. Decisions themselves apply
/// immediately (idempotent single source of truth); this action only moves
/// the viewport to the next question.
class PayrollNextQuestionAction extends StatelessWidget {
  const PayrollNextQuestionAction({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: PayrollAccentAction(
        label: label,
        onTap: onTap,
        height: 32,
        fontSize: 11.5,
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
  /// tag that names WHY (`CALCE EXACTO`, `TOLERANCIA +$250`,
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
/// (`CALCE EXACTO`, `TOLERANCIA +$250`, `SIN PERSONA DE NÓMINA`…).
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
              'Revisar coincidencias',
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
class PayrollReviewTableRow extends StatelessWidget {
  const PayrollReviewTableRow({
    super.key,
    required this.date,
    required this.description,
    required this.amount,
    required this.stateTag,
    required this.stateTone,
    required this.why,
    required this.confidence,
    required this.decision,
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
  final String amount;
  final String stateTag;
  final PayrollStateTone stateTone;
  final String why;
  final Widget confidence;
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
                  ],
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
        color: expanded ? visual.surfaceSunken : null,
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
                  horizontal: 17,
                  vertical: 10,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: 52,
                            child: Text(
                              date,
                              style: visual.monoM.copyWith(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(flex: 5, child: movement),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 96,
                            child: Text(
                              amount,
                              textAlign: TextAlign.right,
                              style: visual.monoM.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: settled ? visual.inkMuted : visual.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: personCell),
                          const SizedBox(width: 12),
                          Expanded(flex: 5, child: whyText),
                          const SizedBox(width: 12),
                          confidence,
                          const SizedBox(width: 12),
                          SizedBox(width: 150, child: decision),
                        ],
                      );
                    }
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
                            const SizedBox(width: 10),
                            Text(
                              amount,
                              style: visual.monoM.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: settled ? visual.inkMuted : visual.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(child: personCell),
                            const SizedBox(width: 10),
                            confidence,
                          ],
                        ),
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
