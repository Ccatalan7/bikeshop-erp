part of 'ocr_product_review_workspace.dart';

/// Step 2 as one ordered table: a row per confirmed line, eight cells, three
/// of them editable in place. The stacked cards it replaces used a screen per
/// line for four numbers and hid the decision that matters — the units per
/// purchase and the rule behind them — under two buttons.
///
/// Anatomy from `T-01`: header 30 on the sunken surface with overline labels
/// and a strong bottom border; rows 48 with a hairline between them; the
/// identity column is the only flexible one and money, units, rule and state
/// keep a fixed width. Money follows `F-03`: mono tabular, right-aligned, CLP
/// without decimals. Below `fullTableBreakpoint` the rule and state fold into
/// the product cell's second line; below `touchBreakpoint` each row becomes a
/// card with the same eight cells and no disclosure.
class _PurchaseAmountsTable extends StatelessWidget {
  const _PurchaseAmountsTable(
      {required this.lines,
      required this.callbacks,
      required this.touch,
      required this.dense,
      required this.readOnly});

  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool dense;
  final bool readOnly;

  static const double _purchasedWidth = 88;
  static const double _moneyWidth = 124;
  static const double _unitsWidth = 100;
  static const double _stockWidth = 164;
  static const double _ruleWidth = 200;
  static const double _stateWidth = 128;
  static const double _gap = _OcrProductReviewWorkspaceState.space3;
  static const double _headerHeight = 30;
  static const double _rowMinHeight = 48;

  /// `T-03`: a disclosure row is indented to the content's left edge.
  static const double _componentIndent = 51;

  @override
  Widget build(BuildContext context) {
    if (touch) {
      return ListView.separated(
          key: const PageStorageKey('ocr-review-amounts'),
          padding: const EdgeInsets.all(_OcrProductReviewWorkspaceState.space3),
          itemCount: lines.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
          itemBuilder: (context, index) => _PurchaseAmountsCard(
              key: Key('ocr-review-amounts-${lines[index].id}'),
              line: lines[index],
              callbacks: callbacks,
              readOnly: readOnly));
    }
    final roles = VinabikeThemeRoles.of(context);
    return Column(children: [
      _header(context),
      Expanded(
          child: ListView.separated(
              key: const PageStorageKey('ocr-review-amounts'),
              itemCount: lines.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, thickness: 1, color: roles.hairline),
              itemBuilder: (context, index) => _PurchaseAmountsTableRow(
                  key: Key('ocr-review-amounts-${lines[index].id}'),
                  line: lines[index],
                  callbacks: callbacks,
                  dense: dense,
                  readOnly: readOnly))),
    ]);
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    Widget label(String text,
        {double? width, TextAlign align = TextAlign.start}) {
      final child = Text(text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
              color: roles.faintForeground,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8));
      return width == null
          ? Expanded(child: child)
          : SizedBox(width: width, child: child);
    }

    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(
          horizontal: _OcrProductReviewWorkspaceState.space3),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline))),
      child: Row(children: [
        label('PRODUCTO'),
        const SizedBox(width: _gap),
        label('COMPRADO', width: _purchasedWidth, align: TextAlign.end),
        const SizedBox(width: _gap),
        label('COSTO/COMPRA', width: _moneyWidth, align: TextAlign.end),
        const SizedBox(width: _gap),
        label('TOTAL LÍNEA', width: _moneyWidth, align: TextAlign.end),
        const SizedBox(width: _gap),
        label('UNID./COMPRA', width: _unitsWidth, align: TextAlign.end),
        const SizedBox(width: _gap),
        label('INGRESO A INVENTARIO', width: _stockWidth, align: TextAlign.end),
        if (!dense) ...[
          const SizedBox(width: _gap),
          label('REGLA', width: _ruleWidth),
          const SizedBox(width: _gap),
          label('ESTADO', width: _stateWidth),
        ],
      ]),
    );
  }
}

/// What the row still needs, in the operator's words. The footer confirms
/// every row that is `ready`; the others say why they are not.
enum _AmountsRowState { confirmed, ready, rulePending, invalid, failed }

_AmountsRowState _amountsStateFor(OcrProductReviewLine line) {
  if (line.errorMessage != null) return _AmountsRowState.failed;
  if (line.purchaseAmountsConfirmed) return _AmountsRowState.confirmed;
  if (!line.appliedComposition &&
      line.hasRememberedSuggestion &&
      !line.ruleRejected) {
    return _AmountsRowState.rulePending;
  }
  if (!line.purchaseAmountsValid) return _AmountsRowState.invalid;
  return _AmountsRowState.ready;
}

VbStatusBadge _amountsStateBadge(OcrProductReviewLine line) =>
    switch (_amountsStateFor(line)) {
      _AmountsRowState.confirmed =>
        const VbStatusBadge(label: 'Confirmado', tone: VbStatusTone.success),
      _AmountsRowState.ready =>
        const VbStatusBadge(label: 'Listo', tone: VbStatusTone.neutral),
      _AmountsRowState.rulePending => const VbStatusBadge(
          label: 'Regla por decidir', tone: VbStatusTone.warning),
      _AmountsRowState.invalid => const VbStatusBadge(
          label: 'Revisar importes', tone: VbStatusTone.warning),
      _AmountsRowState.failed =>
        const VbStatusBadge(label: 'Con error', tone: VbStatusTone.danger),
    };

/// Editable purchase numbers of one line, shared by the table row and the
/// touch card so both read the same controllers the same way.
class _PurchaseAmountsCells {
  _PurchaseAmountsCells(this.line);

  final OcrProductReviewLine line;

  double? get quantity => double.tryParse(
      line.purchaseQuantityController?.text.replaceAll(',', '.') ?? '');
  int? get units => int.tryParse(line.purchaseUnitsController?.text ?? '');
  double? get total => double.tryParse(
      line.purchaseTotalController?.text.replaceAll(',', '.') ?? '');

  /// «5 compras × 3 = 15 unidades», or the applied composition's totals.
  String get inventoryEntry {
    if (line.appliedComposition && line.resolutionComponents.isNotEmpty) {
      return line.resolutionComponents
          .map((part) => '${ocrReviewNumber(part.totalQuantity)} × ${part.sku}')
          .join(' + ');
    }
    final purchased = quantity;
    final perPurchase = units;
    if (purchased == null ||
        perPurchase == null ||
        purchased <= 0 ||
        perPurchase <= 0) {
      return '—';
    }
    return '${ocrReviewNumber(purchased * perPurchase)} unidades';
  }

  Widget field(BuildContext context, String key,
      {required bool enabled, required OcrProductReviewCallbacks callbacks}) {
    final controller = switch (key) {
      'quantity' => line.purchaseQuantityController,
      'unitCost' => line.purchaseUnitCostController,
      'total' => line.purchaseTotalController,
      _ => line.purchaseUnitsController,
    };
    return _CompactField(
        fieldKey: Key('ocr-purchase-$key-${line.id}'),
        controller: controller!,
        enabled: enabled,
        numeric: true,
        origin: key == 'units'
            ? OcrProductFieldOrigin.user
            : OcrProductFieldOrigin.invoice,
        onChanged: (_) => callbacks.onAmountsChanged?.call(line.id, key));
  }
}

/// The rule cell: which earlier decision this row follows, whose it is, and
/// the one action that changes it. Never a badge that is also a button.
class _PurchaseRuleCell extends StatelessWidget {
  const _PurchaseRuleCell(
      {required this.line,
      required this.callbacks,
      required this.enabled,
      this.compact = false});

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rulePending = !line.appliedComposition &&
        line.hasRememberedSuggestion &&
        !line.ruleRejected;
    Widget action(String key, String label, ValueChanged<String>? callback) =>
        VbButton(
            key: Key('ocr-review-$key-${line.id}'),
            label: label,
            variant: VbButtonVariant.text,
            density: compact ? VbDensity.touch : VbDensity.compact,
            onPressed:
                enabled && callback != null ? () => callback(line.id) : null);
    final badge = line.appliedComposition
        ? const VbStatusBadge(
            label: 'Regla aplicada', tone: VbStatusTone.success)
        : rulePending
            ? const VbStatusBadge(
                label: 'Regla anterior', tone: VbStatusTone.warning)
            : line.ruleRejected
                ? const VbStatusBadge(
                    label: 'Se guardará tu elección',
                    tone: VbStatusTone.neutral)
                : line.canConfirmCompositeProposal
                    ? const VbStatusBadge(
                        label: 'Descomposición sugerida',
                        tone: VbStatusTone.info)
                    : null;
    final actions = <Widget>[
      if (rulePending) ...[
        action(
            'apply-rule', 'Aplicar', callbacks.onConfirmRememberedResolution),
        action(
            'reject-rule', 'Cambiar', callbacks.onRejectRememberedResolution),
      ] else if (line.appliedComposition)
        action('edit-composition', 'Modificar', callbacks.onEditComposition)
      else if (line.canConfirmCompositeProposal)
        action('confirm-composite', 'Revisar',
            callbacks.onConfirmCompositeProposal)
      else
        action('edit-composition', 'Descomponer', callbacks.onEditComposition),
    ];
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) badge,
          if (line.ruleAttribution != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line.ruleAttribution!,
                    key: Key('ocr-review-rule-attribution-${line.id}'),
                    maxLines: compact ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted)),
          if (line.ruleRejected)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Al confirmar se guarda tu elección como regla.',
                    key: Key('ocr-review-rule-rejected-${line.id}'),
                    maxLines: 2,
                    style: muted)),
          if (badge == null && line.ruleAttribution == null)
            Text('Sin regla anterior', style: muted),
          Wrap(spacing: 4, children: actions),
        ]);
  }
}

class _PurchaseAmountsTableRow extends StatelessWidget {
  const _PurchaseAmountsTableRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.dense,
      required this.readOnly});

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool dense;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final cells = _PurchaseAmountsCells(line);
    final enabled =
        !readOnly && line.status != OcrProductReviewStatus.searching;
    final product = line.inventoryProduct;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget cell(Widget child, {double? width, bool end = false}) {
      final aligned = Align(
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: child);
      return width == null
          ? Expanded(child: aligned)
          : SizedBox(width: width, child: aligned);
    }

    final identity =
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ProductImage(
          imageUrl:
              product?.imageUrlOptimized ?? product?.imageUrl ?? line.imageUrl,
          imageBytes: product == null ? line.imageBytes : null,
          size: 32),
      const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
            key: ValueKey('ocr-inventory-open-${line.id}-${product?.id}'),
            onTap:
                product?.id != null && callbacks.onOpenInventoryProduct != null
                    ? () => callbacks.onOpenInventoryProduct!(product!)
                    : null,
            child: Text(product?.name ?? line.originalTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface))),
        Text(
            [
              if (product != null) product.sku,
              'OCR: ${ocrReviewNumber(line.sourceQuantity)} × ${line.originalTitle}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted),
        if (dense) ...[
          const SizedBox(height: _OcrProductReviewWorkspaceState.space1),
          Wrap(
              spacing: _OcrProductReviewWorkspaceState.space2,
              runSpacing: _OcrProductReviewWorkspaceState.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _amountsStateBadge(line),
                _PurchaseRuleCell(
                    line: line, callbacks: callbacks, enabled: enabled),
              ]),
        ],
      ])),
    ]);

    final row = Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: _OcrProductReviewWorkspaceState.space3,
          vertical: _OcrProductReviewWorkspaceState.space2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            minHeight: _PurchaseAmountsTable._rowMinHeight -
                2 * _OcrProductReviewWorkspaceState.space2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          cell(identity),
          const SizedBox(width: _PurchaseAmountsTable._gap),
          cell(
              cells.field(context, 'quantity',
                  enabled: enabled, callbacks: callbacks),
              width: _PurchaseAmountsTable._purchasedWidth),
          const SizedBox(width: _PurchaseAmountsTable._gap),
          cell(
              cells.field(context, 'unitCost',
                  enabled: enabled, callbacks: callbacks),
              width: _PurchaseAmountsTable._moneyWidth),
          const SizedBox(width: _PurchaseAmountsTable._gap),
          cell(
              cells.field(context, 'total',
                  enabled: enabled, callbacks: callbacks),
              width: _PurchaseAmountsTable._moneyWidth),
          const SizedBox(width: _PurchaseAmountsTable._gap),
          cell(
              line.appliedComposition
                  ? Text('—', style: muted)
                  : cells.field(context, 'units',
                      enabled: enabled, callbacks: callbacks),
              width: _PurchaseAmountsTable._unitsWidth,
              end: true),
          const SizedBox(width: _PurchaseAmountsTable._gap),
          cell(
              Text(cells.inventoryEntry,
                  key: Key('ocr-review-inventory-entry-${line.id}'),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()])),
              width: _PurchaseAmountsTable._stockWidth,
              end: true),
          if (!dense) ...[
            const SizedBox(width: _PurchaseAmountsTable._gap),
            cell(
                _PurchaseRuleCell(
                    line: line, callbacks: callbacks, enabled: enabled),
                width: _PurchaseAmountsTable._ruleWidth),
            const SizedBox(width: _PurchaseAmountsTable._gap),
            cell(
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _amountsStateBadge(line),
                      if (line.errorMessage != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(line.errorMessage!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: roles.danger.accent))),
                    ]),
                width: _PurchaseAmountsTable._stateWidth),
          ],
        ]),
      ),
    );

    if (!line.appliedComposition || line.resolutionComponents.isEmpty) {
      return dense && line.errorMessage != null
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              row,
              Padding(
                  padding: const EdgeInsets.fromLTRB(
                      _OcrProductReviewWorkspaceState.space3,
                      0,
                      _OcrProductReviewWorkspaceState.space3,
                      _OcrProductReviewWorkspaceState.space2),
                  child: Text(line.errorMessage!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: roles.danger.accent))),
            ])
          : row;
    }
    final costs =
        ocrComponentDisplayCosts(line.resolutionComponents, cells.total);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row,
      for (var i = 0; i < line.resolutionComponents.length; i++)
        _CompositionComponentRow(
            key: Key('ocr-review-component-${line.id}-$i'),
            component: line.resolutionComponents[i],
            purchased: cells.quantity,
            cost: costs?[i],
            dense: dense),
    ]);
  }
}

/// `T-03`: a component of an applied rule opens under its line, indented to
/// the content edge, on the selection surface and without a shadow.
class _CompositionComponentRow extends StatelessWidget {
  const _CompositionComponentRow(
      {super.key,
      required this.component,
      required this.purchased,
      required this.cost,
      required this.dense});

  final OcrReviewComponent component;
  final double? purchased;
  final int? cost;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget cell(Widget child, {double? width, bool end = false}) {
      final aligned = Align(
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: child);
      return width == null
          ? Expanded(child: aligned)
          : SizedBox(width: width, child: aligned);
    }

    final trailing = dense
        ? 0.0
        : _PurchaseAmountsTable._ruleWidth +
            _PurchaseAmountsTable._stateWidth +
            2 * _PurchaseAmountsTable._gap;
    return Container(
      color: roles.selectionContainer,
      padding: const EdgeInsets.fromLTRB(
          _PurchaseAmountsTable._componentIndent,
          _OcrProductReviewWorkspaceState.space2,
          _OcrProductReviewWorkspaceState.space3,
          _OcrProductReviewWorkspaceState.space2),
      child: Row(children: [
        cell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(component.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          Text(
              '${component.sku}${component.roleLabel.isEmpty ? '' : ' · ${component.roleLabel}'}',
              style: muted),
        ])),
        const SizedBox(width: _PurchaseAmountsTable._gap),
        cell(Text(ocrReviewNumber(purchased), style: muted),
            width: _PurchaseAmountsTable._purchasedWidth, end: true),
        const SizedBox(width: _PurchaseAmountsTable._gap),
        cell(cost == null ? Text('—', style: muted) : VbMoneyText(cost!),
            width: _PurchaseAmountsTable._moneyWidth, end: true),
        const SizedBox(width: _PurchaseAmountsTable._gap),
        cell(const SizedBox.shrink(), width: _PurchaseAmountsTable._moneyWidth),
        const SizedBox(width: _PurchaseAmountsTable._gap),
        cell(Text('${component.unitsPerPurchase}', style: muted),
            width: _PurchaseAmountsTable._unitsWidth, end: true),
        const SizedBox(width: _PurchaseAmountsTable._gap),
        cell(
            Text('${ocrReviewNumber(component.totalQuantity)} unidades',
                key:
                    ValueKey('ocr-composition-equation-${component.productId}'),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
            width: _PurchaseAmountsTable._stockWidth,
            end: true),
        if (trailing > 0) SizedBox(width: trailing),
      ]),
    );
  }
}

/// Under 900 px the same eight cells stack as a card: identity, the four
/// numbers in two rows, the inventory entry, the rule and the state.
class _PurchaseAmountsCard extends StatelessWidget {
  const _PurchaseAmountsCard(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.readOnly});

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final cells = _PurchaseAmountsCells(line);
    final enabled =
        !readOnly && line.status != OcrProductReviewStatus.searching;
    final product = line.inventoryProduct;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget labeled(String label, Widget child) => _LabeledField(
        label: label,
        origin: OcrProductFieldOrigin.invoice,
        showOrigin: false,
        child: child);
    final costs =
        ocrComponentDisplayCosts(line.resolutionComponents, cells.total);
    return Container(
      padding: const EdgeInsets.all(_OcrProductReviewWorkspaceState.space3),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ProductImage(
              imageUrl: product?.imageUrlOptimized ??
                  product?.imageUrl ??
                  line.imageUrl,
              imageBytes: product == null ? line.imageBytes : null,
              size: 40),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                InkWell(
                    key: ValueKey(
                        'ocr-inventory-open-${line.id}-${product?.id}'),
                    onTap: product?.id != null &&
                            callbacks.onOpenInventoryProduct != null
                        ? () => callbacks.onOpenInventoryProduct!(product!)
                        : null,
                    child: Text(product?.name ?? line.originalTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600))),
                if (product != null) Text(product.sku, style: muted),
                Text(
                    'OCR: ${ocrReviewNumber(line.sourceQuantity)} × ${line.originalTitle}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted),
              ])),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
          _amountsStateBadge(line),
        ]),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: labeled(
                  'Comprado',
                  cells.field(context, 'quantity',
                      enabled: enabled, callbacks: callbacks))),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
          Expanded(
              child: labeled(
                  'Costo por compra',
                  cells.field(context, 'unitCost',
                      enabled: enabled, callbacks: callbacks))),
        ]),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: labeled(
                  'Total línea',
                  cells.field(context, 'total',
                      enabled: enabled, callbacks: callbacks))),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
          Expanded(
              child: line.appliedComposition
                  ? labeled(
                      'Unid./compra', Text('Según la regla', style: muted))
                  : labeled(
                      'Unid./compra',
                      cells.field(context, 'units',
                          enabled: enabled, callbacks: callbacks))),
        ]),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        Text('Ingreso a inventario: ${cells.inventoryEntry}',
            key: Key('ocr-review-inventory-entry-${line.id}'),
            style: theme.textTheme.titleSmall),
        if (line.appliedComposition)
          for (var i = 0; i < line.resolutionComponents.length; i++)
            Padding(
                padding: const EdgeInsets.only(
                    top: _OcrProductReviewWorkspaceState.space1),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          '${ocrReviewNumber(line.resolutionComponents[i].totalQuantity)} × ${line.resolutionComponents[i].sku} · ${line.resolutionComponents[i].name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: muted)),
                  if (costs != null) VbMoneyText(costs[i]),
                ])),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        _PurchaseRuleCell(
            line: line, callbacks: callbacks, enabled: enabled, compact: true),
        if (line.errorMessage != null)
          Padding(
              padding: const EdgeInsets.only(
                  top: _OcrProductReviewWorkspaceState.space2),
              child: Text(line.errorMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.danger.accent))),
      ]),
    );
  }
}
