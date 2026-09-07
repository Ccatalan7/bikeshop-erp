part of 'ocr_product_review_workspace.dart';

class _ReviewBatch extends StatefulWidget {
  const _ReviewBatch(
      {required this.lines,
      required this.callbacks,
      required this.step,
      required this.touch,
      required this.dense,
      required this.readOnly,
      this.selectedLineId,
      this.activity});
  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final OcrPurchaseReviewStep step;
  final bool touch;
  final bool dense;
  final bool readOnly;
  final String? selectedLineId;
  final OcrProductReviewActivity? activity;
  @override
  State<_ReviewBatch> createState() => _ReviewBatchState();
}

class _ReviewBatchState extends State<_ReviewBatch> {
  @override
  Widget build(BuildContext context) => _ReviewBatchView(
      lines: widget.lines,
      callbacks: widget.callbacks,
      step: widget.step,
      touch: widget.touch,
      dense: widget.dense,
      readOnly: widget.readOnly,
      selectedLineId: widget.selectedLineId,
      activity: widget.activity);
}

/// The same source rows move through identity, economics and new-product
/// creation. Each stage exposes only the decision that belongs to it.
class _ReviewBatchView extends StatelessWidget {
  const _ReviewBatchView(
      {required this.lines,
      required this.callbacks,
      required this.step,
      required this.touch,
      required this.dense,
      required this.readOnly,
      this.selectedLineId,
      this.activity});

  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final OcrPurchaseReviewStep step;
  final bool touch;
  final bool dense;
  final bool readOnly;
  final String? selectedLineId;
  final OcrProductReviewActivity? activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity =
        step == OcrPurchaseReviewStep.identify ? this.activity : null;
    final visible = lines
        .where((line) => switch (step) {
              OcrPurchaseReviewStep.identify => true,
              OcrPurchaseReviewStep.amounts => line.isSelected &&
                  line.identityDecision == OcrProductIdentityDecision.existing,
              OcrPurchaseReviewStep.newProducts => line.isSelected &&
                  line.identityDecision ==
                      OcrProductIdentityDecision.newProduct,
            })
        .toList();
    final identified =
        lines.where((line) => line.isSelected && line.identityConfirmed).length;
    final selected = lines.where((line) => line.isSelected).length;
    final title = switch (step) {
      OcrPurchaseReviewStep.identify => 'Identificar productos',
      OcrPurchaseReviewStep.amounts => 'Confirmar cantidades y costos',
      OcrPurchaseReviewStep.newProducts => 'Crear productos nuevos',
    };
    return Padding(
      padding: EdgeInsets.all(touch ? 12 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 24, runSpacing: 8, children: [
          for (final phase in OcrPurchaseReviewStep.values)
            Text(
                '${phase.index + 1}. ${switch (phase) {
                  OcrPurchaseReviewStep.identify => 'Productos',
                  OcrPurchaseReviewStep.amounts => 'Cantidades y costos',
                  OcrPurchaseReviewStep.newProducts => 'Productos nuevos',
                }}',
                style: theme.textTheme.labelLarge?.copyWith(
                    color: phase == step
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        phase == step ? FontWeight.w700 : FontWeight.w400)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          // While the pass runs the header is the surface's one live label
          // (`X-01`: the skeleton cells announce nothing themselves). `A-01`:
          // the spinner sits beside the gerund, never instead of it.
          if (activity != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      key: const Key('ocr-review-activity-spinner'),
                      strokeWidth: 2,
                      color: theme.colorScheme.primary)),
              const SizedBox(width: 8),
              Text(activity.text,
                  key: const Key('ocr-review-activity'),
                  style: theme.textTheme.bodySmall),
            ])
          else
            Text(
                step == OcrPurchaseReviewStep.identify
                    ? '$identified de $selected identificados'
                    : '${visible.length} productos',
                style: theme.textTheme.bodySmall),
          if (step == OcrPurchaseReviewStep.identify &&
              activity == null &&
              callbacks.onSearchPending != null)
            Padding(
                padding: const EdgeInsets.only(left: 12),
                child: VbButton(
                    label: 'Reintentar pendientes',
                    variant: VbButtonVariant.text,
                    density: VbDensity.compact,
                    onPressed: readOnly ? null : callbacks.onSearchPending)),
        ]),
        const SizedBox(height: 12),
        Expanded(
            child: switch (step) {
          OcrPurchaseReviewStep.identify => touch
              ? _IdentityTable(
                  lines: visible,
                  callbacks: callbacks,
                  touch: true,
                  readOnly: readOnly)
              : _framed(
                  context,
                  _IdentityTable(
                      lines: visible,
                      callbacks: callbacks,
                      touch: false,
                      readOnly: readOnly)),
          OcrPurchaseReviewStep.amounts => touch
              ? _PurchaseAmountsTable(
                  lines: visible,
                  callbacks: callbacks,
                  touch: true,
                  dense: true,
                  readOnly: readOnly)
              : _framed(
                  context,
                  _PurchaseAmountsTable(
                      lines: visible,
                      callbacks: callbacks,
                      touch: false,
                      dense: dense,
                      readOnly: readOnly)),
          OcrPurchaseReviewStep.newProducts => _NewProductsTable(
              lines: visible, callbacks: callbacks, readOnly: readOnly),
        }),
      ]),
    );
  }

  /// The batch frame: surface, hairline border, radius 8. Steps 1 and 2 draw
  /// their own `T-01` header inside it.
  Widget _framed(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8)),
      child: child,
    );
  }
}
