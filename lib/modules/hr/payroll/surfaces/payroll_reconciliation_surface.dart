import 'package:flutter/material.dart';

import '../../../../shared/utils/responsive_viewport.dart';
import '../theme/payroll_tokens.dart';

/// Visual state of one step in Claude Design concept 2c.
enum ReconStepState { done, current, next }

/// Presentation-only step descriptor.
///
/// The routed page remains the owner of navigation and validation. This
/// surface only renders the state it receives and delegates a permitted tap.
@immutable
class ReconStep {
  const ReconStep({
    required this.name,
    required this.compactName,
    required this.meta,
    required this.state,
    this.onTap,
  });

  final String name;
  final String compactName;
  final String meta;
  final ReconStepState state;
  final VoidCallback? onTap;
}

/// Claude Design 2c host for the real reconciliation workflow.
///
/// The source concept was `ERP Bikeshop UI Mockups`, frame 2c
/// ("Conciliar — flujo de 4 pasos"). The concept's full-screen duplicate logo
/// is deliberately omitted because the real route already lives inside
/// [MainLayout]. Everything below the global shell follows the 2c hierarchy:
/// navy workflow command band, adaptive four-step progress, tonal canvas,
/// one scroll owner supplied by the state-machine page, and a persistent
/// impact/action footer.
///
/// This widget owns no OCR, matching, payment, idempotency or navigation
/// state. Those contracts remain in `PayrollReconciliationPage`.
class PayrollReconciliationSurface extends StatelessWidget {
  const PayrollReconciliationSurface({
    super.key,
    required this.title,
    required this.steps,
    required this.body,
    required this.footer,
    required this.onClose,
    this.breadcrumb = 'Nóminas / Importar cartola',
    this.metadata,
    this.closeLabel = 'Salir sin guardar',
    this.closeEnabled = true,
    this.busy = false,
  });

  final String breadcrumb;
  final String title;
  final String? metadata;
  final List<ReconStep> steps;
  final Widget body;
  final Widget footer;
  final VoidCallback onClose;
  final String closeLabel;
  final bool closeEnabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // MainLayout already owns the route title and navigation actions while its
    // compact shell is active. Repeating another full-width navy header here
    // produced two consecutive page titles on phone and tablet. Desktop has no
    // MainLayout app bar, so this workflow header remains the one route-level
    // owner there.
    final showWorkflowHeader = !ResponsiveViewport.usesCompactShell(context);
    final visual = PayrollVisualTokens.of(context);

    return ColoredBox(
      color: visual.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showWorkflowHeader)
            _WorkflowHeader(
              key: const ValueKey('reconciliation-workflow-header'),
              breadcrumb: breadcrumb,
              title: title,
              metadata: metadata,
              closeLabel: closeLabel,
              closeEnabled: closeEnabled,
              busy: busy,
              onClose: onClose,
            ),
          _ReconciliationStepper(steps: steps),
          Expanded(child: body),
          footer,
        ],
      ),
    );
  }
}

class _WorkflowHeader extends StatelessWidget {
  const _WorkflowHeader({
    super.key,
    required this.breadcrumb,
    required this.title,
    required this.metadata,
    required this.closeLabel,
    required this.closeEnabled,
    required this.busy,
    required this.onClose,
  });

  final String breadcrumb;
  final String title;
  final String? metadata;
  final String closeLabel;
  final bool closeEnabled;
  final bool busy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Container(
          color: visual.shell,
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 20,
            compact ? 10 : 11,
            compact ? 10 : 16,
            compact ? 10 : 11,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!compact)
                      Text(
                        breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyS.copyWith(
                          fontSize: 11,
                          color: visual.onShellMuted,
                        ),
                      ),
                    if (!compact) const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: visual.recordTitle.copyWith(
                              fontSize: compact ? 17 : 19,
                            ),
                          ),
                        ),
                        if (!compact &&
                            metadata != null &&
                            metadata!.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(width: 11),
                          Flexible(
                            child: Text(
                              metadata!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: visual.monoS.copyWith(
                                fontSize: 10.5,
                                color: visual.onShellMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (compact &&
                        metadata != null &&
                        metadata!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        metadata!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.monoS.copyWith(
                          fontSize: 9.5,
                          color: visual.onShellMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (compact)
                Semantics(
                  button: true,
                  label: closeLabel,
                  child: IconButton(
                    key: const ValueKey('reconciliation-close'),
                    onPressed: closeEnabled && !busy ? onClose : null,
                    tooltip: closeLabel,
                    icon: busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: visual.onShellMuted,
                            ),
                          )
                        : Icon(
                            Icons.close_rounded,
                            color: visual.sidebarLabel,
                          ),
                    constraints: const BoxConstraints(
                      minWidth: PayrollTokens.touchMobile,
                      minHeight: PayrollTokens.touchMobile,
                    ),
                  ),
                )
              else
                OutlinedButton(
                  key: const ValueKey('reconciliation-close'),
                  onPressed: closeEnabled && !busy ? onClose : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: visual.sidebarLabel,
                    disabledForegroundColor: visual.onShellMuted,
                    side: BorderSide(color: visual.shellEdge),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PayrollTokens.rField),
                    ),
                    textStyle: visual.labelStrong.copyWith(fontSize: 11.5),
                  ),
                  child: Text(closeLabel),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReconciliationStepper extends StatelessWidget {
  const _ReconciliationStepper({required this.steps});

  final List<ReconStep> steps;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 18,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: visual.surface,
            border: Border(
              bottom: BorderSide(color: visual.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              for (var index = 0; index < steps.length; index++) ...<Widget>[
                Expanded(
                  child: _StepPill(
                    step: steps[index],
                    index: index + 1,
                    compact: compact,
                  ),
                ),
                if (index != steps.length - 1)
                  Container(
                    width: compact ? 4 : 14,
                    height: 1,
                    color: visual.borderStrong,
                    margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 7),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.step,
    required this.index,
    required this.compact,
  });

  final ReconStep step;
  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final current = step.state == ReconStepState.current;
    final done = step.state == ReconStepState.done;
    final foreground = current
        ? visual.accent
        : done
            ? visual.inkMuted
            : visual.inkFaint;

    return Semantics(
      button: step.onTap != null,
      selected: current,
      label: '${step.name}${step.meta.isEmpty ? '' : '. ${step.meta}'}',
      excludeSemantics: true,
      child: Material(
        color: current ? visual.accentSoft : visual.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PayrollTokens.rPill),
          side: BorderSide(
            color: current ? visual.accentBorder : visual.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('reconciliation-step-$index'),
          onTap: step.onTap,
          child: Container(
            height: compact ? PayrollTokens.touchMobile : PayrollTokens.ctaH,
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: compact ? 20 : 18,
                  height: compact ? 20 : 18,
                  decoration: BoxDecoration(
                    // accent-fill: selection (active step badge; its digit
                    // paints with visual.onAccent)
                    color: done
                        ? visual.successSoft
                        : current
                            ? visual.accent
                            : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: done
                          ? visual.successBorder
                          : current
                              ? visual.accent
                              : visual.borderStrong,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: done
                      ? Icon(
                          Icons.check_rounded,
                          size: 11,
                          color: visual.successFg,
                        )
                      : Text(
                          '$index',
                          style: visual.badgeDigits(
                            9,
                            color: current ? visual.onAccent : visual.inkFaint,
                          ),
                        ),
                ),
                SizedBox(width: compact ? 4 : 7),
                Flexible(
                  child: Text(
                    compact ? step.compactName : step.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.labelStrong.copyWith(
                      fontSize: compact ? 9.5 : 11,
                      color: foreground,
                    ),
                  ),
                ),
                if (!compact && step.meta.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      step.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(fontSize: 9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
