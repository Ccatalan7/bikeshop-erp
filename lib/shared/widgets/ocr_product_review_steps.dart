part of 'ocr_product_review_workspace.dart';

class _ReviewBatch extends StatefulWidget {
  const _ReviewBatch(
      {required this.lines,
      required this.callbacks,
      required this.step,
      required this.touch,
      required this.dense,
      required this.readOnly,
      this.selectedLineId});
  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final OcrPurchaseReviewStep step;
  final bool touch;
  final bool dense;
  final bool readOnly;
  final String? selectedLineId;
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
      selectedLineId: widget.selectedLineId);
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
      this.selectedLineId});

  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final OcrPurchaseReviewStep step;
  final bool touch;
  final bool dense;
  final bool readOnly;
  final String? selectedLineId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text(
              step == OcrPurchaseReviewStep.identify
                  ? '$identified de $selected identificados'
                  : '${visible.length} productos',
              style: theme.textTheme.bodySmall),
          if (step == OcrPurchaseReviewStep.identify &&
              callbacks.onSearchPending != null)
            TextButton(
                onPressed: readOnly ? null : callbacks.onSearchPending,
                child: const Text('Reintentar pendientes')),
        ]),
        const SizedBox(height: 12),
        Expanded(
            child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            if (!touch) _header(context),
            Expanded(
                child: ListView.separated(
                    key: PageStorageKey('ocr-review-${step.name}'),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = visible[index];
                      return switch (step) {
                        OcrPurchaseReviewStep.identify => _IdentityReviewRow(
                            key: Key('ocr-review-row-${line.id}'),
                            line: line,
                            callbacks: callbacks,
                            touch: touch,
                            readOnly: readOnly),
                        OcrPurchaseReviewStep.amounts => _PurchaseAmountsRow(
                            key: Key('ocr-review-amounts-${line.id}'),
                            line: line,
                            callbacks: callbacks,
                            touch: touch,
                            readOnly: readOnly),
                        OcrPurchaseReviewStep.newProducts => _NewCatalogRow(
                            key: Key('ocr-review-create-row-${line.id}'),
                            line: line,
                            callbacks: callbacks,
                            touch: touch,
                            dense: dense,
                            readOnly: readOnly),
                      };
                    })),
          ]),
        )),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text) => Text(text, style: theme.textTheme.labelSmall);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: switch (step) {
        OcrPurchaseReviewStep.identify => Row(children: [
            const SizedBox(width: 48),
            Expanded(flex: 4, child: label('ARTÍCULO LEÍDO POR OCR')),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: label('COINCIDENCIA EN INVENTARIO')),
            const SizedBox(width: 16),
            SizedBox(width: 172, child: label('DECISIÓN')),
          ]),
        OcrPurchaseReviewStep.amounts => Row(children: [
            Expanded(
                child:
                    label('PRODUCTOS SELECCIONADOS · IMPORTES DE LA COMPRA')),
            label('CANTIDADES Y COSTOS'),
          ]),
        OcrPurchaseReviewStep.newProducts => dense
            ? Row(children: [
                Expanded(child: label('FICHAS DE PRODUCTOS NUEVOS'))
              ])
            : Row(children: [
                Expanded(flex: 3, child: label('PRODUCTO NUEVO / SKU')),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: label('CATEGORÍA')),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: label('MARCA')),
                const SizedBox(width: 12),
                SizedBox(width: 96, child: label('UNID. / COMPRA')),
                const SizedBox(width: 12),
                SizedBox(width: 112, child: label('COSTO UNIT.')),
                const SizedBox(width: 12),
                SizedBox(width: 112, child: label('PRECIO VENTA')),
              ]),
      },
    );
  }
}

class _IdentityReviewRow extends StatelessWidget {
  const _IdentityReviewRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.touch,
      required this.readOnly});
  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy =
        line.status == OcrProductReviewStatus.searching || line.isReservingSku;
    final enabled =
        !readOnly && !busy && line.isSelected && !line.productAlreadyCreated;
    final source = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ProductImage(
          imageUrl: line.imageUrl, imageBytes: line.imageBytes, size: 48),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (touch)
          Text('Artículo leído por OCR', style: theme.textTheme.labelSmall),
        Text(line.originalTitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(spacing: 12, children: [
          Text('${ocrReviewNumber(line.sourceQuantity)} comprados',
              style: theme.textTheme.bodySmall),
          VbMoneyText(line.sourceLineTotal),
        ]),
      ])),
    ]);
    final product = line.inventoryProduct;
    final alternativeCount = line.candidates
        .where((candidate) =>
            !candidate.isRuledOut &&
            !candidate.isReviewOnlyFamilyScope &&
            candidate.product.id != product?.id)
        .length;
    final candidate =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (line.identityDecision == OcrProductIdentityDecision.newProduct)
        Text('Producto nuevo', style: theme.textTheme.titleSmall)
      else if (product != null)
        _InventoryProductReference(
            lineId: line.id,
            product: product,
            caption: line.inventoryOrigin,
            onOpen: callbacks.onOpenInventoryProduct)
      else if (busy)
        const Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Expanded(child: Text('Buscando coincidencias…'))
        ])
      else
        Text(
            line.status == OcrProductReviewStatus.failed
                ? 'No se pudo completar la comparación'
                : 'Sin coincidencias sugeridas',
            style: theme.textTheme.bodyMedium),
      if (line.identityDecision != OcrProductIdentityDecision.newProduct)
        Wrap(spacing: 8, children: [
          if (alternativeCount > 0)
            TextButton(
                key: Key('ocr-review-alternatives-${line.id}'),
                onPressed: enabled && callbacks.onOpenCandidates != null
                    ? () => callbacks.onOpenCandidates!(line.id)
                    : null,
                child: Text('Ver otras coincidencias ($alternativeCount)')),
          TextButton(
              key: Key('ocr-review-inventory-${line.id}'),
              onPressed: enabled && callbacks.onOpenCandidates != null
                  ? () => callbacks.onOpenCandidates!(line.id)
                  : null,
              child: const Text('Buscar en inventario')),
          if (line.status == OcrProductReviewStatus.failed)
            TextButton(
                key: Key('ocr-review-retry-${line.id}'),
                onPressed: enabled && callbacks.onRetryLine != null
                    ? () => callbacks.onRetryLine!(line.id)
                    : null,
                child: const Text('Reintentar comparación')),
        ]),
    ]);
    final decision =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (line.identityConfirmed) ...[
        OutlinedButton(
            key: Key('ocr-review-change-${line.id}'),
            onPressed: enabled && callbacks.onChangeDecision != null
                ? () => callbacks.onChangeDecision!(line.id)
                : null,
            child: const Text('Cambiar selección')),
      ] else ...[
        if (product != null)
          FilledButton(
              key: Key('ocr-review-select-${line.id}'),
              onPressed: enabled && callbacks.onLinkCandidate != null
                  ? () => callbacks.onLinkCandidate!(line.id, product)
                  : null,
              child: const Text('Seleccionar producto')),
        const SizedBox(height: 8),
        OutlinedButton(
            key: Key('ocr-review-new-${line.id}'),
            onPressed: enabled && callbacks.onPrepareNewProduct != null
                ? () => callbacks.onPrepareNewProduct!(line.id)
                : null,
            child: const Text('Marcar como nuevo')),
      ],
    ]);
    final checkbox = Checkbox(
        value: line.isSelected,
        onChanged: readOnly ||
                line.productAlreadyCreated ||
                callbacks.onSelectionChanged == null
            ? null
            : (value) =>
                callbacks.onSelectionChanged!(line.id, value ?? false));
    return Padding(
        padding: const EdgeInsets.all(12),
        child: touch
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [checkbox, Expanded(child: source)]),
                const SizedBox(height: 12),
                candidate,
                const SizedBox(height: 8),
                decision,
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: 48, child: checkbox),
                Expanded(flex: 4, child: source),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: candidate),
                const SizedBox(width: 16),
                SizedBox(width: 172, child: decision),
              ]));
  }
}

/// A reference to the actual products row, with its canonical editor opened by
/// primary key. OCR text is never used as an inventory-record substitute.
class _InventoryProductReference extends StatelessWidget {
  const _InventoryProductReference(
      {required this.lineId, required this.product, this.caption, this.onOpen});
  final String lineId;
  final Product product;
  final String? caption;
  final ValueChanged<Product>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('ocr-inventory-record-$lineId-${product.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ProductImage(
            imageUrl: product.imageUrlOptimized ?? product.imageUrl, size: 48),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (caption != null)
            Text(caption!, style: theme.textTheme.labelSmall),
          InkWell(
              key: ValueKey('ocr-inventory-open-$lineId-${product.id}'),
              onTap: product.id != null && onOpen != null
                  ? () => onOpen!(product)
                  : null,
              child: Text(product.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Text('${product.sku} · Stock: ${product.inventoryQty}',
              style: theme.textTheme.bodySmall),
          if (product.categoryName?.isNotEmpty == true)
            Text(product.categoryName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall),
        ])),
      ]),
    );
  }
}

class _PurchaseAmountsRow extends StatelessWidget {
  const _PurchaseAmountsRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.touch,
      required this.readOnly});
  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        !readOnly && line.status != OcrProductReviewStatus.searching;
    final quantity = double.tryParse(
        line.purchaseQuantityController?.text.replaceAll(',', '.') ?? '');
    final units = int.tryParse(line.purchaseUnitsController?.text ?? '');
    final total = double.tryParse(
        line.purchaseTotalController?.text.replaceAll(',', '.') ?? '');
    Widget field(String key, String label, TextEditingController? controller,
            {bool editable = true}) =>
        _LabeledField(
            label: label,
            origin: OcrProductFieldOrigin.invoice,
            showOrigin: false,
            child: _CompactField(
                fieldKey: Key('ocr-purchase-$key-${line.id}'),
                controller: controller!,
                enabled: enabled && editable,
                numeric: true,
                origin: key == 'units'
                    ? OcrProductFieldOrigin.user
                    : OcrProductFieldOrigin.invoice,
                onChanged: (_) =>
                    callbacks.onAmountsChanged?.call(line.id, key)));
    final fields = [
      field('quantity', 'Cantidad comprada', line.purchaseQuantityController),
      field('unitCost', 'Costo por compra', line.purchaseUnitCostController),
      field('total', 'Total de la línea', line.purchaseTotalController),
      if (!line.appliedComposition)
        field('units', 'Unidades por compra', line.purchaseUnitsController),
    ];
    return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (line.inventoryProduct != null)
            _InventoryProductReference(
                lineId: line.id,
                product: line.inventoryProduct!,
                onOpen: callbacks.onOpenInventoryProduct),
          const SizedBox(height: 8),
          Text(
              'OCR: ${ocrReviewNumber(line.sourceQuantity)} compras · ${line.originalTitle}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (touch)
            Column(children: [
              for (var i = 0; i < fields.length; i += 2) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: fields[i]),
                  const SizedBox(width: 12),
                  Expanded(
                      child: i + 1 < fields.length
                          ? fields[i + 1]
                          : const SizedBox.shrink()),
                ]),
                const SizedBox(height: 12),
              ]
            ])
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < fields.length; i++) ...[
                Expanded(child: fields[i]),
                if (i < fields.length - 1) const SizedBox(width: 12),
              ],
            ]),
          const SizedBox(height: 12),
          if (line.appliedComposition)
            OcrCompositionReview(
                components: line.resolutionComponents,
                sourceQuantity: quantity,
                sourceTotal: total)
          else if (quantity != null &&
              units != null &&
              quantity > 0 &&
              units > 0)
            Text(
                'Ingreso a inventario: ${ocrReviewNumber(quantity * units)} unidades · ${line.inventoryProduct?.sku ?? ''}',
                style: theme.textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            if (!line.appliedComposition && line.hasRememberedSuggestion)
              TextButton(
                  key: Key('ocr-review-apply-rule-${line.id}'),
                  onPressed: enabled &&
                          callbacks.onConfirmRememberedResolution != null
                      ? () => callbacks.onConfirmRememberedResolution!(line.id)
                      : null,
                  child: const Text('Aplicar regla guardada')),
            if (!line.appliedComposition &&
                !line.hasRememberedSuggestion &&
                line.canConfirmCompositeProposal)
              TextButton(
                  key: Key('ocr-review-confirm-composite-${line.id}'),
                  onPressed:
                      enabled && callbacks.onConfirmCompositeProposal != null
                          ? () => callbacks.onConfirmCompositeProposal!(line.id)
                          : null,
                  child: const Text('Revisar descomposición sugerida')),
            TextButton(
                key: Key('ocr-review-edit-composition-${line.id}'),
                onPressed: enabled && callbacks.onEditComposition != null
                    ? () => callbacks.onEditComposition!(line.id)
                    : null,
                child: Text(line.appliedComposition
                    ? 'Modificar descomposición'
                    : 'Configurar descomposición')),
          ]),
          if (line.errorMessage != null)
            Text(line.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          Align(
              alignment: Alignment.centerRight,
              child: line.purchaseAmountsConfirmed
                  ? const VbStatusBadge(
                      label: 'Cantidades y costos confirmados',
                      tone: VbStatusTone.success)
                  : FilledButton(
                      key: Key('ocr-review-confirm-amounts-${line.id}'),
                      onPressed: enabled &&
                              line.purchaseAmountsValid &&
                              callbacks.onConfirmAmounts != null
                          ? () => callbacks.onConfirmAmounts!(line.id)
                          : null,
                      child: const Text('Confirmar línea'))),
        ]));
  }
}

class _NewCatalogRow extends StatelessWidget {
  const _NewCatalogRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.touch,
      required this.dense,
      required this.readOnly});
  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool dense;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        !readOnly && !line.isReservingSku && !line.productAlreadyCreated;
    Widget cost(bool price) => _CompactField(
        fieldKey: Key('ocr-review-${price ? 'price' : 'cost'}-${line.id}'),
        controller: price ? line.controllers.price : line.controllers.cost,
        enabled: enabled,
        numeric: true,
        origin: price ? line.priceOrigin : line.costOrigin,
        onChanged: (value) => price
            ? callbacks.onPriceChanged?.call(line.id, value)
            : callbacks.onCostChanged?.call(line.id, value));
    final name = Row(children: [
      _EditableSourceImage(
          line: line, callbacks: callbacks, size: 48, enabled: enabled),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CompactField(
            fieldKey: Key('ocr-review-name-${line.id}'),
            controller: line.controllers.name,
            enabled: enabled,
            origin: line.nameOrigin,
            onChanged: (value) =>
                callbacks.onNameChanged?.call(line.id, value)),
        const SizedBox(height: 4),
        _SkuCell(line: line, enabled: enabled, callbacks: callbacks),
      ])),
    ]);
    return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (dense || touch) ...[
            Text(line.originalTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _NewProductFields(
                line: line, callbacks: callbacks, enabled: enabled),
          ] else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: name),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: _CategorySelector(
                      line: line,
                      enabled: enabled,
                      onChanged: (value) =>
                          callbacks.onCategoryChanged?.call(line.id, value))),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: _BrandSelector(
                      line: line,
                      enabled: enabled,
                      onChanged: (value) =>
                          callbacks.onBrandChanged?.call(line.id, value))),
              const SizedBox(width: 12),
              SizedBox(
                  width: 96,
                  child: _CompactField(
                      fieldKey: Key('ocr-review-new-units-${line.id}'),
                      controller: line.newProductUnitsController!,
                      enabled: enabled,
                      numeric: true,
                      origin: OcrProductFieldOrigin.invoice,
                      onChanged: (value) => callbacks.onNewProductUnitsChanged
                          ?.call(line.id, value))),
              const SizedBox(width: 12),
              SizedBox(width: 112, child: cost(false)),
              const SizedBox(width: 12),
              SizedBox(width: 112, child: cost(true)),
            ]),
            const SizedBox(height: 8),
            Text(
                '${ocrReviewNumber(line.sourceQuantity)} compras → ${ocrReviewNumber(line.newProductInventoryQuantity)} unidades al recibir',
                style: theme.textTheme.bodySmall),
          ],
          if (line.status == OcrProductReviewStatus.searching)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Completando ficha con IA…')),
          if (line.errorMessage != null)
            Text(line.errorMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          if (line.categoryValidationMessage != null)
            Text(line.categoryValidationMessage!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
        ]));
  }
}
