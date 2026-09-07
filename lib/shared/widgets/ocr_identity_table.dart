part of 'ocr_product_review_workspace.dart';

/// Step 1 as the same `T-01` table step 2 uses: one row per invoice line,
/// three cells — what the OCR read, what the inventory has, the decision —
/// aligned at the top, separated by a hairline, no card inside the row.
///
/// The row before this one (2026-09-05, morning) stacked a bordered card for
/// the match, a floating «Comparar» link and two 48 px Material buttons of
/// different heights in a 172 px column, so every row read at a different
/// level and the accent filled a block per line. Here the decision is a row
/// of compact `A-01` buttons, the accent appears once per undecided row, and
/// a decided row shows a badge and «Cambiar».
class _IdentityTable extends StatelessWidget {
  const _IdentityTable(
      {required this.lines,
      required this.callbacks,
      required this.touch,
      required this.readOnly});

  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool readOnly;

  static const double _checkWidth = 40;
  static const double _decisionWidth = 236;
  static const double _gap = _OcrProductReviewWorkspaceState.space4;
  static const double _headerHeight = 30;

  @override
  Widget build(BuildContext context) {
    // One sweep clock for every queued cell, so the table reads as one
    // surface loading and not as cells blinking out of phase. The group only
    // exists while something is queued: no ticker runs on a settled table.
    final anyQueued = lines.any(_IdentityRowState.isQueuedLine);
    Widget grouped(Widget child) =>
        anyQueued ? VbSkeletonGroup(child: child) : child;
    if (touch) {
      return grouped(ListView.separated(
          key: const PageStorageKey('ocr-review-identify'),
          padding: const EdgeInsets.all(_OcrProductReviewWorkspaceState.space3),
          itemCount: lines.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
          itemBuilder: (context, index) => _IdentityCard(
              key: Key('ocr-review-row-${lines[index].id}'),
              line: lines[index],
              callbacks: callbacks,
              readOnly: readOnly)));
    }
    final roles = VinabikeThemeRoles.of(context);
    return Column(children: [
      _header(context),
      Expanded(
          child: grouped(ListView.separated(
              key: const PageStorageKey('ocr-review-identify'),
              itemCount: lines.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, thickness: 1, color: roles.hairline),
              itemBuilder: (context, index) => _IdentityTableRow(
                  key: Key('ocr-review-row-${lines[index].id}'),
                  line: lines[index],
                  callbacks: callbacks,
                  readOnly: readOnly)))),
    ]);
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    Widget label(String text) => Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
            color: roles.faintForeground,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8));
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(
          horizontal: _OcrProductReviewWorkspaceState.space3),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline))),
      child: Row(children: [
        const SizedBox(width: _checkWidth),
        Expanded(flex: 5, child: label('ARTÍCULO LEÍDO POR OCR')),
        const SizedBox(width: _gap),
        Expanded(flex: 6, child: label('COINCIDENCIA EN INVENTARIO')),
        const SizedBox(width: _gap),
        SizedBox(width: _decisionWidth, child: label('DECISIÓN')),
      ]),
    );
  }
}

/// What a row knows about itself, shared by the table row and the card.
class _IdentityRowState {
  _IdentityRowState(this.line, {required this.readOnly});

  final OcrProductReviewLine line;
  final bool readOnly;

  bool get pending => line.status == OcrProductReviewStatus.needsSearch;

  /// Queued by the automatic pass: silhouette, not spinner. The spinner is
  /// for the row a worker is actually comparing right now.
  bool get queued =>
      line.queued && line.status == OcrProductReviewStatus.searching;
  bool get busy =>
      (line.status == OcrProductReviewStatus.searching && !line.queued) ||
      line.isReservingSku;
  bool get failed => line.status == OcrProductReviewStatus.failed;
  bool get isNew =>
      line.identityDecision == OcrProductIdentityDecision.newProduct;
  bool get enabled =>
      !readOnly &&
      !busy &&
      !queued &&
      !pending &&
      line.isSelected &&
      !line.productAlreadyCreated;
  static bool isQueuedLine(OcrProductReviewLine line) =>
      line.queued && line.status == OcrProductReviewStatus.searching;

  Product? get product => line.inventoryProduct;
  bool get weak => line.bestEvidence?.needsComparison == true;
  bool get pack => product == null && line.aiCompositeProposal != null;
  int get compareCount => line.viableCandidateCount;
}

/// The OCR side of the row: image, supplier title, quantity and money.
/// `X-01` silhouette of `_InventoryProductReference`: the 40 px image block
/// with its radius 6, then a name bar and a meta bar (`h 11 · radius 4` from
/// the guide). Bar widths are the shape of the real content, not tokens.
class _MatchSilhouette extends StatelessWidget {
  const _MatchSilhouette({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      VbSkeleton.block(size: 40, radius: 6),
      SizedBox(width: _OcrProductReviewWorkspaceState.space3),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            VbSkeleton.bar(width: 220),
            SizedBox(height: _OcrProductReviewWorkspaceState.space2),
            VbSkeleton.bar(width: 140),
          ])),
    ]);
  }
}

class _IdentitySourceCell extends StatelessWidget {
  const _IdentitySourceCell({required this.line, required this.imageSize});

  final OcrProductReviewLine line;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ProductImage(
          imageUrl: line.imageUrl,
          imageBytes: line.imageBytes,
          size: imageSize),
      const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(line.originalTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(children: [
          Text('${ocrReviewNumber(line.sourceQuantity)} comprados',
              style: muted),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
          VbMoneyText(line.sourceLineTotal),
        ]),
      ])),
    ]);
  }
}

/// The inventory side of the row, with what it means for the decision.
class _IdentityMatchCell extends StatelessWidget {
  const _IdentityMatchCell(
      {required this.state, required this.callbacks, required this.density});

  final _IdentityRowState state;
  final OcrProductReviewCallbacks callbacks;
  final VbDensity density;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final line = state.line;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final product = state.product;
    final decided =
        line.identityDecision == OcrProductIdentityDecision.existing;
    final children = <Widget>[];

    if (state.isNew) {
      children.add(Row(children: [
        const VbStatusBadge(
            label: 'Producto nuevo', tone: VbStatusTone.neutral),
        const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
        Expanded(
            child: Text('Se creará en el paso 3 con su ficha.', style: muted)),
      ]));
    } else if (product != null) {
      children.add(_InventoryProductReference(
          lineId: line.id,
          product: product,
          caption: line.inventoryOrigin,
          evidence: decided ? null : line.bestEvidence,
          decided: decided,
          note: line.categoryObjection,
          onOpen: callbacks.onOpenInventoryProduct));
    } else if (state.queued) {
      // `X-01`: the silhouette of the product reference that will land here,
      // in its final place, so nothing jumps when the match arrives.
      children.add(_MatchSilhouette(key: Key('ocr-review-queued-${line.id}')));
    } else if (state.pending) {
      children.add(Text('Pendiente de comparar',
          key: Key('ocr-review-pending-${line.id}'),
          style: theme.textTheme.bodyMedium));
      children.add(
          Text('La comparación con el inventario aún no corre.', style: muted));
    } else if (state.busy) {
      children.add(Row(children: [
        const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
        Text('Comparando con el inventario…',
            style: theme.textTheme.bodyMedium),
      ]));
    } else if (state.failed) {
      children
          .add(Text('No se pudo comparar', style: theme.textTheme.bodyMedium));
    } else if (state.pack && line.aiCompositeProduct != null) {
      // The AI named ONE product and read the line as several of it. The
      // product stays on the row with its record; the pack reading is a note
      // the operator confirms in step 2, not a reason to hide the product.
      children.add(_InventoryProductReference(
          key: Key('ocr-review-pack-${line.id}'),
          lineId: line.id,
          product: line.aiCompositeProduct!,
          caption: 'Elegido por la IA',
          evidence:
              const OcrCandidateEvidence('Leído como pack', VbStatusTone.info),
          note: line.categoryObjection ??
              'La IA lo lee como ${line.aiCompositeUnits} unidades por compra; las unidades se confirman en el paso 2.',
          onOpen: callbacks.onOpenInventoryProduct));
    } else if (state.pack) {
      children.add(Text('Coincide como pack: ${line.aiCompositeProposal}',
          key: Key('ocr-review-pack-${line.id}'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium));
      children.add(Text(
          'Define cuántas unidades del catálogo entran por compra.',
          style: muted));
    } else {
      children.add(Text('Sin coincidencia recomendada',
          style: theme.textTheme.bodyMedium));
      children.add(Text(
          state.compareCount > 0
              ? '${state.compareCount} parecidos para comparar'
              : 'Nada parecido en el inventario',
          style: muted));
    }

    if (line.sharedWithLineTitle != null) {
      children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Otra línea de esta compra ya propone este producto: “${line.sharedWithLineTitle}”',
              key: Key('ocr-review-shared-${line.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: roles.warning.accent))));
    }

    if (!state.isNew &&
        !decided &&
        !state.pending &&
        !state.queued &&
        !state.busy) {
      final open = state.enabled && callbacks.onOpenCandidates != null
          ? () => callbacks.onOpenCandidates!(line.id)
          : null;
      children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, children: [
            if (state.compareCount > 0)
              VbButton(
                  key: Key('ocr-review-alternatives-${line.id}'),
                  label: 'Comparar (${state.compareCount})',
                  variant: VbButtonVariant.text,
                  density: VbDensity.compact,
                  onPressed: open)
            else
              VbButton(
                  key: Key('ocr-review-inventory-${line.id}'),
                  label: 'Buscar en inventario',
                  variant: VbButtonVariant.text,
                  density: VbDensity.compact,
                  onPressed: open),
            // Any compared row can be compared again: a cached decision is
            // a receipt, not a verdict, and the code around the model changes.
            VbButton(
                key: Key('ocr-review-retry-${line.id}'),
                label: state.failed
                    ? 'Reintentar comparación'
                    : 'Volver a comparar',
                variant: VbButtonVariant.text,
                density: VbDensity.compact,
                onPressed: state.enabled && callbacks.onRetryLine != null
                    ? () => callbacks.onRetryLine!(line.id)
                    : null),
          ])));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children);
  }
}

/// The decision: one accent button at most per undecided row.
class _IdentityDecisionCell extends StatelessWidget {
  const _IdentityDecisionCell(
      {required this.state,
      required this.callbacks,
      required this.density,
      this.expand = false});

  final _IdentityRowState state;
  final OcrProductReviewCallbacks callbacks;
  final VbDensity density;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = state.line;
    final product = state.product;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    VbButton button(String key, String label, VbButtonVariant variant,
            VoidCallback? onPressed) =>
        VbButton(
            key: Key('ocr-review-$key-${line.id}'),
            label: label,
            variant: variant,
            density: density,
            expand: expand,
            onPressed: onPressed);
    final open = state.enabled && callbacks.onOpenCandidates != null
        ? () => callbacks.onOpenCandidates!(line.id)
        : null;
    final select =
        product != null && state.enabled && callbacks.onLinkCandidate != null
            ? () => callbacks.onLinkCandidate!(line.id, product)
            : null;
    final markNew = state.enabled && callbacks.onPrepareNewProduct != null
        ? () => callbacks.onPrepareNewProduct!(line.id)
        : null;

    final List<Widget> actions;
    if (line.identityConfirmed) {
      actions = [
        button(
            'change',
            'Cambiar',
            VbButtonVariant.text,
            state.enabled && callbacks.onChangeDecision != null
                ? () => callbacks.onChangeDecision!(line.id)
                : null),
      ];
    } else if (state.pending || state.queued || state.busy) {
      // `A-01`: an inert decision explains itself instead of vanishing.
      return Text(
          state.pending
              ? 'Esperando la comparación'
              : state.queued
                  ? 'En cola'
                  : 'Comparando…',
          key: Key('ocr-review-waiting-${line.id}'),
          style: muted);
    } else if (state.pack) {
      final packProduct = line.aiCompositeProduct;
      final selectPack = packProduct != null &&
              state.enabled &&
              callbacks.onLinkCandidate != null
          ? () => callbacks.onLinkCandidate!(line.id, packProduct)
          : null;
      actions = [
        button(
            'composition', 'Definir contenido', VbButtonVariant.primary, open),
        if (packProduct != null)
          button(
              'select', 'Seleccionar', VbButtonVariant.secondary, selectPack),
        button('new', 'Marcar como nuevo', VbButtonVariant.text, markNew),
      ];
    } else if (product != null && state.weak) {
      actions = [
        button('compare', 'Comparar', VbButtonVariant.primary, open),
        button(
            'select', 'Seleccionar igual', VbButtonVariant.secondary, select),
        button('new', 'Marcar como nuevo', VbButtonVariant.text, markNew),
      ];
    } else if (product != null) {
      actions = [
        button('select', 'Seleccionar', VbButtonVariant.primary, select),
        button('new', 'Marcar como nuevo', VbButtonVariant.text, markNew),
      ];
    } else {
      actions = [
        button('new', 'Marcar como nuevo', VbButtonVariant.secondary, markNew),
      ];
    }
    if (expand) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0)
            const SizedBox(height: _OcrProductReviewWorkspaceState.space2),
          actions[i],
        ],
      ]);
    }
    return Wrap(
        spacing: _OcrProductReviewWorkspaceState.space2,
        runSpacing: 6,
        children: actions);
  }
}

class _IdentityTableRow extends StatelessWidget {
  const _IdentityTableRow(
      {super.key,
      required this.line,
      required this.callbacks,
      required this.readOnly});

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final state = _IdentityRowState(line, readOnly: readOnly);
    final checkbox = Checkbox(
        value: line.isSelected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: readOnly ||
                line.productAlreadyCreated ||
                callbacks.onSelectionChanged == null
            ? null
            : (value) =>
                callbacks.onSelectionChanged!(line.id, value ?? false));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          _OcrProductReviewWorkspaceState.space3,
          _OcrProductReviewWorkspaceState.space3,
          _OcrProductReviewWorkspaceState.space3,
          _OcrProductReviewWorkspaceState.space3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: _IdentityTable._checkWidth,
            child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(height: 20, width: 20, child: checkbox))),
        Expanded(
            flex: 5, child: _IdentitySourceCell(line: line, imageSize: 40)),
        const SizedBox(width: _IdentityTable._gap),
        Expanded(
            flex: 6,
            child: _IdentityMatchCell(
                state: state,
                callbacks: callbacks,
                density: VbDensity.compact)),
        const SizedBox(width: _IdentityTable._gap),
        SizedBox(
            width: _IdentityTable._decisionWidth,
            child: _IdentityDecisionCell(
                state: state,
                callbacks: callbacks,
                density: VbDensity.compact)),
      ]),
    );
  }
}

/// Under 900 px the row is a card with the same three cells stacked and
/// full-width touch buttons.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard(
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
    final state = _IdentityRowState(line, readOnly: readOnly);
    final checkbox = Checkbox(
        value: line.isSelected,
        onChanged: readOnly ||
                line.productAlreadyCreated ||
                callbacks.onSelectionChanged == null
            ? null
            : (value) =>
                callbacks.onSelectionChanged!(line.id, value ?? false));
    return Container(
      padding: const EdgeInsets.all(_OcrProductReviewWorkspaceState.space3),
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          checkbox,
          Expanded(child: _IdentitySourceCell(line: line, imageSize: 48)),
        ]),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        _IdentityMatchCell(
            state: state, callbacks: callbacks, density: VbDensity.touch),
        const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
        _IdentityDecisionCell(
            state: state,
            callbacks: callbacks,
            density: VbDensity.touch,
            expand: true),
      ]),
    );
  }
}

/// A reference to the actual products row, opened by primary key. Plain cell
/// content: `T-01` draws no card inside a row.
class _InventoryProductReference extends StatelessWidget {
  const _InventoryProductReference(
      {super.key,
      required this.lineId,
      required this.product,
      this.caption,
      this.evidence,
      this.decided = false,
      this.note,
      this.onOpen});
  final String lineId;
  final Product product;
  final String? caption;
  final OcrCandidateEvidence? evidence;
  final bool decided;
  final String? note;
  final ValueChanged<Product>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final meta = <String>[
      product.sku,
      'Stock: ${product.inventoryQty}',
      if (product.categoryName?.isNotEmpty == true) product.categoryName!,
    ].join(' · ');
    return Row(
      key: ValueKey('ocr-inventory-record-$lineId-${product.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductImage(
            imageUrl: product.imageUrlOptimized ?? product.imageUrl, size: 40),
        const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: _OcrProductReviewWorkspaceState.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (decided)
                  // A choice is «hecho», not «verificado»: neutral, so the
                  // step reads as a list of decisions, not a wall of green.
                  const VbStatusBadge(
                      label: 'Seleccionado', tone: VbStatusTone.neutral)
                else if (caption != null)
                  Text(caption!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: roles.faintForeground)),
                if (evidence != null)
                  VbStatusBadge(
                      key: Key('ocr-review-evidence-$lineId'),
                      label: evidence!.label,
                      tone: evidence!.tone),
              ]),
          const SizedBox(height: 2),
          InkWell(
              key: ValueKey('ocr-inventory-open-$lineId-${product.id}'),
              onTap: product.id != null && onOpen != null
                  ? () => onOpen!(product)
                  : null,
              child: Text(product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600))),
          Text(meta,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          if (note != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note!,
                    key: Key('ocr-review-note-$lineId'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: roles.warning.accent))),
        ])),
      ],
    );
  }
}
