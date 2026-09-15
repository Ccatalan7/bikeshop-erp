part of 'ocr_product_review_workspace.dart';

/// T-01 batch editing: one column definition owns both header and cells.
/// I-01/S-06 use 34 px controls; F-04 supplies 12 px gutters. Values were
/// read from the cached DesignSync GUÍA GENERAL (c430e08f/bkyc7j0gj.txt).
class _NewProductsTable extends StatelessWidget {
  const _NewProductsTable(
      {required this.lines, required this.callbacks, required this.readOnly});
  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  // Content budget: product identity needs 276 px after fixed numeric/code
  // columns and selectors. Narrower hosts recompose without horizontal scroll.
  static const tableBreakpoint = 1280.0;
  static const widths = <double?>[null, 140, 200, 160, 112, 112, 160];
  static const headings = [
    'Producto',
    'SKU',
    'Categoría',
    'Marca',
    'Costo unit.',
    'Precio venta',
    'Insumo de taller'
  ];

  static Widget columns(List<Widget> cells) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            if (widths[i] == null)
              Expanded(child: cells[i])
            else
              SizedBox(width: widths[i], child: cells[i]),
          ]
        ],
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final table = box.maxWidth >= tableBreakpoint;
        final theme = Theme.of(context);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                  child: Container(
                key: const Key('ocr-new-products-table'),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (table)
                    Container(
                      key: const Key('ocr-new-products-header'),
                      color: theme.colorScheme.surfaceContainerLow,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: columns([
                        for (var i = 0; i < headings.length; i++)
                          Text(headings[i],
                              key: Key('ocr-new-heading-$i'),
                              textAlign: i >= 4 && i <= 5
                                  ? TextAlign.end
                                  : i == 6
                                      ? TextAlign.center
                                      : TextAlign.start,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  Flexible(
                      child: ListView.separated(
                    key: const PageStorageKey('ocr-review-newProducts'),
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _NewCatalogRow(
                        key: Key('ocr-review-create-row-${lines[index].id}'),
                        line: lines[index],
                        callbacks: callbacks,
                        table: table,
                        touch: box.maxWidth < 900,
                        readOnly: readOnly),
                  )),
                ]),
              )),
            ]);
      });
}

class _NewCatalogRow extends StatelessWidget {
  const _NewCatalogRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.table,
      required this.touch,
      required this.readOnly});
  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool table;
  final bool touch;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        !readOnly && !line.isReservingSku && !line.productAlreadyCreated;
    Widget field(String kind, TextEditingController controller,
            ValueChanged<String>? onChanged,
            {bool numeric = false, bool money = false}) =>
        _CompactField(
            fieldKey: Key('ocr-review-$kind-${line.id}'),
            semanticLabel: '${switch (kind) {
              'name' => 'Nombre',
              'cost' => 'Costo unitario',
              'price' => 'Precio de venta',
              _ => kind,
            }} de ${line.originalTitle}',
            controller: controller,
            enabled: enabled,
            touch: touch,
            numeric: numeric,
            money: money,
            origin: kind == 'name'
                ? line.nameOrigin
                : kind == 'price'
                    ? line.priceOrigin
                    : kind == 'cost'
                        ? line.costOrigin
                        : OcrProductFieldOrigin.invoice,
            onChanged: onChanged);
    Widget label(String text, Widget child) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(text, style: theme.textTheme.labelSmall),
          const SizedBox(height: 5),
          child,
        ]);
    Widget pair(Widget a, Widget b) =>
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ]);
    final name = Row(children: [
      _EditableSourceImage(
          line: line,
          callbacks: callbacks,
          size: touch ? 48 : 34,
          enabled: enabled),
      const SizedBox(width: 8),
      Expanded(
          child: field(
              'name',
              line.controllers.name,
              callbacks.onNameChanged == null
                  ? null
                  : (value) => callbacks.onNameChanged!(line.id, value))),
    ]);
    final sku = Semantics(
        label: 'SKU de ${line.originalTitle}',
        child: _SkuCell(
            line: line, enabled: enabled, callbacks: callbacks, touch: touch));
    final category = _CategorySelector(
        line: line,
        enabled: enabled,
        showLabel: !table,
        touch: touch,
        onChanged: callbacks.onCategoryChanged == null
            ? null
            : (value) => callbacks.onCategoryChanged!(line.id, value));
    final brand = _BrandSelector(
        line: line,
        enabled: enabled,
        showLabel: !table,
        touch: touch,
        onChanged: callbacks.onBrandChanged == null
            ? null
            : (value) => callbacks.onBrandChanged!(line.id, value));
    final cost = field(
        'cost',
        line.controllers.cost,
        callbacks.onCostChanged == null
            ? null
            : (value) => callbacks.onCostChanged!(line.id, value),
        numeric: true,
        money: true);
    final price = field(
        'price',
        line.controllers.price,
        callbacks.onPriceChanged == null
            ? null
            : (value) => callbacks.onPriceChanged!(line.id, value),
        numeric: true,
        money: true);
    final consumable = SizedBox(
        height: touch ? 48 : 34,
        child: Center(
            child: Checkbox(
          key: Key('ocr-review-consumable-${line.id}'),
          semanticLabel: 'Insumo de taller: ${line.originalTitle}',
          // The draft callback retains its legacy sale-oriented contract.
          value: !line.isSold,
          onChanged: enabled && callbacks.onSoldChanged != null
              ? (value) => callbacks.onSoldChanged!(line.id, !value!)
              : null,
        )));
    final rowError = line.errorMessage;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (table)
                _NewProductsTable.columns(
                    [name, sku, category, brand, cost, price, consumable])
              else ...[
                label('Producto', name),
                const SizedBox(height: 12),
                pair(
                    label('SKU', sku),
                    label(
                        'Insumo de taller',
                        Align(
                            alignment: Alignment.centerLeft,
                            child: consumable))),
                const SizedBox(height: 12),
                LayoutBuilder(
                    builder: (_, box) => box.maxWidth < 600
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                category,
                                const SizedBox(height: 12),
                                brand
                              ])
                        : pair(category, brand)),
                const SizedBox(height: 12),
                pair(label('Costo unitario', cost),
                    label('Precio de venta', price)),
              ],
              if (line.siblingLineId != null && callbacks.onCopySibling != null)
                Align(
                    alignment: Alignment.centerLeft,
                    child: VbButton(
                        key: Key('ocr-review-copy-sibling-${line.id}'),
                        label: 'Reutilizar categoría y marca',
                        variant: VbButtonVariant.text,
                        density: touch ? VbDensity.touch : VbDensity.compact,
                        onPressed: enabled
                            ? () => callbacks.onCopySibling!(
                                line.id, line.siblingLineId!)
                            : null)),
              if (line.status == OcrProductReviewStatus.searching)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Completando ficha…',
                        style: theme.textTheme.bodySmall)),
              if (rowError != null &&
                  rowError != line.categoryValidationMessage &&
                  rowError != line.brandValidationMessage &&
                  rowError != line.skuErrorMessage)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(rowError,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error))),
            ],
          )),
    );
  }
}
