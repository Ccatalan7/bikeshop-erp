import 'dart:async';

import 'package:flutter/material.dart';

import '../../modules/inventory/models/inventory_models.dart';
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../services/image_service.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_notice.dart';

/// What the operator decided in the picker.
sealed class OcrCandidateDecision {
  const OcrCandidateDecision();
}

/// Link this invoice line to an existing catalog product.
class OcrCandidateLink extends OcrCandidateDecision {
  const OcrCandidateLink(this.product);

  final Product product;
}

/// None of them: create a new product from this line.
class OcrCandidateCreateNew extends OcrCandidateDecision {
  const OcrCandidateCreateNew();
}

/// The line whose identity is being decided, shown so the operator never has
/// to remember what they clicked.
class OcrCandidateLineContext {
  const OcrCandidateLineContext({
    required this.title,
    this.originalTitle,
    this.supplierCode,
    this.imageUrl,
    this.quantity,
    this.unitCost,
    this.categoryLabel,
    this.brandLabel,
  });

  final String title;
  final String? originalTitle;
  final String? supplierCode;
  final String? imageUrl;
  final double? quantity;
  final double? unitCost;
  final String? categoryLabel;
  final String? brandLabel;
}

typedef OcrCandidateSearch = Future<List<Product>> Function(String query);

/// Centred picker for «¿cuál de estos es?».
///
/// Deliberately *not* an in-row disclosure. Expanding alternatives inside the
/// reconciliation row made every row a different height, pushed the rest of the
/// invoice off screen and forced a horizontal scroll to see the decision at
/// all. Choosing which product this is, is a short atomic decision about one
/// line — the guide's own signal for a blocking surface — and it needs room for
/// a photo, a SKU, a category and the reason each option is being offered.
///
/// It restores what the legacy dialog did well (a real gallery of options with
/// pictures and manual search) without restoring its narrow shell.
class OcrCandidatePicker extends StatefulWidget {
  const OcrCandidatePicker({
    super.key,
    required this.line,
    required this.candidates,
    this.categoryConflicts = const [],
    this.aiCompositeProposal,
    this.allowCreateNew = true,
    this.inspectionOnly = false,
    this.onSearch,
    this.isLoading = false,
    this.errorMessage,
  });

  final OcrCandidateLineContext line;

  /// The immutable decision computed for this row revision. Opening the
  /// picker must not rerun vision, matching or AI adjudication.
  final List<ProductDuplicateCandidate> candidates;

  /// Same-family products filed outside the resolved category. They stay
  /// visible for catalog repair, but never compete in the normal list.
  final List<ProductDuplicateCandidate> categoryConflicts;

  /// The same immutable, review-only composite proposal shown in the row.
  /// The picker displays it but never applies or persists it.
  final String? aiCompositeProposal;

  /// False when the identity review failed. Manual catalog search remains
  /// available, but a failed model call must never be rendered as evidence
  /// that a new product should be created.
  final bool allowCreateNew;
  final bool inspectionOnly;

  /// Free-text catalog search. Absent when the host cannot search.
  final OcrCandidateSearch? onSearch;

  final bool isLoading;
  final String? errorMessage;

  /// The picker shares the large centred review envelope with the image
  /// comparison pop-over. On desktop the invoice remains visible behind the
  /// scrim, while the candidate evidence gets the space the window already has.
  static const double maxWidth = 1180;
  static const double maxHeight = 920;

  static Future<OcrCandidateDecision?> show(
    BuildContext context, {
    required OcrCandidateLineContext line,
    required List<ProductDuplicateCandidate> candidates,
    List<ProductDuplicateCandidate> categoryConflicts = const [],
    String? aiCompositeProposal,
    bool allowCreateNew = true,
    bool inspectionOnly = false,
    OcrCandidateSearch? onSearch,
    bool isLoading = false,
    String? errorMessage,
  }) {
    return showDialog<OcrCandidateDecision>(
      context: context,
      barrierLabel: 'Cerrar productos parecidos',
      builder: (_) => OcrCandidatePicker(
        line: line,
        candidates: candidates,
        categoryConflicts: categoryConflicts,
        aiCompositeProposal: aiCompositeProposal,
        allowCreateNew: allowCreateNew,
        inspectionOnly: inspectionOnly,
        onSearch: onSearch,
        isLoading: isLoading,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  State<OcrCandidatePicker> createState() => _OcrCandidatePickerState();
}

class _OcrCandidatePickerState extends State<OcrCandidatePicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<Product>? _searchResults;
  bool _searching = false;
  String? _searchError;

  /// Every typed character starts a new search generation. A response only
  /// counts while it is still the newest one asked for.
  ///
  /// Without this a slow answer to `ro` could land after a fast answer to
  /// `rotor 160`, or after the operator cleared the box entirely, and quietly
  /// replace the visible list with results for a query that no longer exists —
  /// exactly the kind of stale write that makes someone link the wrong product.
  int _generation = 0;

  bool _owns(int generation) => mounted && generation == _generation;

  List<_OcrComparisonImage> _comparisonImages({List<Product>? products}) {
    final images = <_OcrComparisonImage>[];
    final sourceUrl = widget.line.imageUrl?.trim();
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      images.add(
        _OcrComparisonImage(
          key: 'source',
          imageUrl: sourceUrl,
          title: 'Imagen de la factura',
          detail: widget.line.originalTitle?.trim().isNotEmpty == true
              ? widget.line.originalTitle!.trim()
              : widget.line.title,
        ),
      );
    }

    final rows = products ??
        <Product>[
          for (final candidate in widget.candidates) candidate.product,
          for (final candidate in widget.categoryConflicts) candidate.product,
        ];
    final seenProducts = <String>{};
    for (final product in rows) {
      final imageUrl = (product.imageUrl ?? product.imageUrlOptimized)?.trim();
      if (imageUrl == null || imageUrl.isEmpty) continue;
      final productKey = product.id?.trim().isNotEmpty == true
          ? product.id!.trim()
          : '${product.sku}|$imageUrl';
      if (!seenProducts.add(productKey)) continue;
      images.add(
        _OcrComparisonImage(
          key: 'product:$productKey',
          imageUrl: imageUrl,
          title: product.name,
          detail: <String>[
            product.sku,
            if (product.brand?.trim().isNotEmpty == true) product.brand!.trim(),
            if (product.categoryName?.trim().isNotEmpty == true)
              product.categoryName!.trim(),
          ].join(' · '),
        ),
      );
    }
    return images;
  }

  void _openImageViewer({
    required String initialKey,
    List<Product>? products,
  }) {
    final images = _comparisonImages(products: products);
    if (images.isEmpty) return;
    final requested = images.indexWhere((image) => image.key == initialKey);
    _OcrComparisonImageViewer.show(
      context,
      images: images,
      initialIndex: requested < 0 ? 0 : requested,
    );
  }

  void _openProductImage(Product product, {List<Product>? products}) {
    final imageUrl = (product.imageUrl ?? product.imageUrlOptimized)?.trim();
    if (imageUrl == null || imageUrl.isEmpty) return;
    final productKey = product.id?.trim().isNotEmpty == true
        ? product.id!.trim()
        : '${product.sku}|$imageUrl';
    _openImageViewer(
      initialKey: 'product:$productKey',
      products: products,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Anything still in flight belongs to a picker that no longer exists.
    _generation++;
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      // Clearing the box is a decision: it returns to the matcher's own
      // candidates and invalidates every request already on the wire.
      setState(() {
        _searchResults = null;
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 260),
      () => _run(trimmed, generation),
    );
  }

  Future<void> _run(String query, int generation) async {
    final search = widget.onSearch;
    if (search == null || !_owns(generation)) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await search(query);
      if (!_owns(generation)) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (error) {
      // Fail closed and say so. A swallowed failure looks identical to
      // «no existe en el catálogo», which would push the worker to create a
      // duplicate product.
      if (!_owns(generation)) return;
      setState(() {
        _searching = false;
        _searchResults = null;
        _searchError = 'No se pudo buscar en el catálogo. $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 720;
    final horizontalInset = compact ? 12.0 : 42.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 24.0;
    final dialogWidth = (screenSize.width - horizontalInset * 2)
        .clamp(320.0, OcrCandidatePicker.maxWidth)
        .toDouble();
    final dialogHeight = (screenSize.height - verticalInset * 2)
        .clamp(360.0, OcrCandidatePicker.maxHeight)
        .toDouble();

    return Dialog(
      key: const Key('ocr-candidate-picker-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const Key('ocr-candidate-picker-shell'),
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _Header(
              line: widget.line,
              compact: compact,
              compositeReview:
                  widget.aiCompositeProposal?.trim().isNotEmpty == true,
              onImageTap: widget.line.imageUrl?.trim().isNotEmpty == true
                  ? () => _openImageViewer(initialKey: 'source')
                  : null,
            ),
            Divider(height: 1, color: theme.dividerColor),
            if (widget.onSearch != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16, 12, compact ? 12 : 16, 8),
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText:
                        'Buscar manualmente en todo el catálogo por nombre, SKU o marca',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
            if (widget.aiCompositeProposal?.trim().isNotEmpty == true)
              Padding(
                key: const Key('ocr-candidate-ai-composite-proposal'),
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 16,
                  widget.onSearch == null ? 12 : 0,
                  compact ? 12 : 16,
                  8,
                ),
                child: VbNotice(
                  title: 'Conjunto propuesto por IA',
                  body: widget.aiCompositeProposal!.trim(),
                  tone: VbNoticeTone.warning,
                ),
              ),
            Flexible(child: _body(context, compact)),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                10,
                compact ? 12 : 16,
                12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.inspectionOnly
                          ? 'Auditoría de solo lectura: ninguna opción se aplicará.'
                          : widget.aiCompositeProposal?.trim().isNotEmpty ==
                                  true
                              ? 'La propuesta no se vincula ni se aprende automáticamente.'
                              : !widget.allowCreateNew
                                  ? 'La revisión falló: reintenta o busca manualmente.'
                                  : 'Si ninguno es, se crea un producto nuevo con esta ficha.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  if (!widget.inspectionOnly &&
                      widget.allowCreateNew &&
                      widget.aiCompositeProposal?.trim().isNotEmpty !=
                          true) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      key: const Key('ocr-candidate-create-new'),
                      onPressed: () => Navigator.of(context)
                          .pop(const OcrCandidateCreateNew()),
                      child: const Text('Ninguno · crear nuevo'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool compact) {
    final padding = EdgeInsets.fromLTRB(
      compact ? 12 : 16,
      widget.onSearch == null ? 12 : 0,
      compact ? 12 : 16,
      12,
    );
    final compositeReview =
        widget.aiCompositeProposal?.trim().isNotEmpty == true;

    if (widget.errorMessage != null) {
      return Padding(
        padding: padding,
        child: VbNotice(
          title: 'No se pudo buscar',
          body: widget.errorMessage!,
          tone: VbNoticeTone.danger,
        ),
      );
    }

    if (_searchError != null) {
      return Padding(
        padding: padding,
        child: VbNotice(
          title: 'La búsqueda falló',
          body: _searchError!,
          tone: VbNoticeTone.danger,
        ),
      );
    }

    if (widget.isLoading) {
      return Padding(
        padding: padding,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final manual = _searchResults;
    if (manual != null) {
      if (manual.isEmpty) {
        return Padding(
          padding: padding,
          child: const VbNotice(
            title: 'Nada coincide',
            body: 'Prueba con otra palabra, el SKU o la marca.',
            tone: VbNoticeTone.neutral,
          ),
        );
      }
      return ListView.separated(
        padding: padding,
        itemCount: manual.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _CandidateRow(
          product: manual[index],
          reasons: const <String>[],
          objections: const <String>[],
          tier: null,
          onImageTap: () => _openProductImage(
            manual[index],
            products: manual,
          ),
          onSelected: compositeReview || widget.inspectionOnly
              ? null
              : () =>
                  Navigator.of(context).pop(OcrCandidateLink(manual[index])),
        ),
      );
    }

    final offered = widget.candidates;
    final categoryConflicts = widget.categoryConflicts;
    if (offered.isEmpty && categoryConflicts.isEmpty) {
      return Padding(
        padding: padding,
        child: const VbNotice(
          title: 'Sin coincidencia fiable',
          body: 'Ningún producto del catálogo comparte tipo de pieza, medida '
              'ni fabricante con esta línea. Búscalo a mano o créalo nuevo.',
          tone: VbNoticeTone.neutral,
        ),
      );
    }

    // Three explicit scopes, one list. Products from another category never
    // compete with the normal answer merely because they share words.
    final viable = offered.where((candidate) => !candidate.isRuledOut).toList();
    final ruledOut =
        offered.where((candidate) => candidate.isRuledOut).toList();
    final rows = <Widget>[
      if (viable.isNotEmpty)
        Padding(
          key: const Key('ocr-candidate-viable-heading'),
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            viable.length == 1 ? '1 viable' : '${viable.length} viables',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      for (final candidate in viable)
        _CandidateRow(
          product: candidate.product,
          reasons: candidate.reasons,
          objections: candidate.objections,
          tier: candidate.matchTier,
          onImageTap: () => _openProductImage(candidate.product),
          onSelected: compositeReview || widget.inspectionOnly
              ? null
              : () => Navigator.of(context)
                  .pop(OcrCandidateLink(candidate.product)),
        ),
      if (ruledOut.isNotEmpty) ...[
        Padding(
          key: const Key('ocr-candidate-ruled-out-heading'),
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            ruledOut.length == 1
                ? '1 descartado por una diferencia'
                : '${ruledOut.length} descartados por una diferencia',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final candidate in ruledOut)
          _CandidateRow(
            product: candidate.product,
            reasons: candidate.reasons,
            objections: candidate.objections,
            tier: candidate.matchTier,
            onImageTap: () => _openProductImage(candidate.product),
            onSelected: compositeReview || widget.inspectionOnly
                ? null
                : () => Navigator.of(context)
                    .pop(OcrCandidateLink(candidate.product)),
          ),
      ],
      if (categoryConflicts.isNotEmpty) ...[
        Padding(
          key: const Key('ocr-candidate-category-conflicts-heading'),
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            categoryConflicts.length == 1
                ? '1 producto del mismo tipo en otra categoría'
                : '${categoryConflicts.length} productos del mismo tipo en otra categoría',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final candidate in categoryConflicts)
          _CandidateRow(
            product: candidate.product,
            reasons: candidate.reasons,
            objections: <String>[
              ...candidate.objections,
              'Revisa la categoría del producto antes de vincular',
            ],
            tier: candidate.matchTier,
            onImageTap: () => _openProductImage(candidate.product),
            onSelected: compositeReview || widget.inspectionOnly
                ? null
                : () => Navigator.of(context)
                    .pop(OcrCandidateLink(candidate.product)),
          ),
      ],
    ];

    return ListView.separated(
      key: const Key('ocr-candidate-list'),
      padding: padding,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.line,
    required this.compact,
    required this.compositeReview,
    required this.onImageTap,
  });

  final OcrCandidateLineContext line;
  final bool compact;
  final bool compositeReview;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final facts = <String>[
      if ((line.supplierCode ?? '').isNotEmpty) 'Código ${line.supplierCode}',
      if (line.quantity != null) '${_number(line.quantity!)} un.',
      if (line.unitCost != null) 'Costo \$${_number(line.unitCost!)}',
      if ((line.categoryLabel ?? '').isNotEmpty) line.categoryLabel!,
      if ((line.brandLabel ?? '').isNotEmpty) line.brandLabel!,
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewThumbnail(
            key: const Key('ocr-candidate-source-image'),
            imageUrl: line.imageUrl,
            compact: compact,
            semanticLabel: 'Ampliar imagen de la factura',
            onTap: onImageTap,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compositeReview
                      ? '¿Qué productos incluye esta línea?'
                      : '¿Cuál de estos es?',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  line.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    facts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const Key('ocr-candidate-close'),
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.product,
    required this.reasons,
    required this.objections,
    required this.tier,
    required this.onSelected,
    required this.onImageTap,
  });

  final Product product;
  final List<String> reasons;
  final List<String> objections;
  final ProductDuplicateMatchTier? tier;
  final VoidCallback? onSelected;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);

    final tone = switch (tier) {
      ProductDuplicateMatchTier.exact => roles.success,
      ProductDuplicateMatchTier.strong => roles.info,
      _ => roles.neutral,
    };
    final tierLabel = switch (tier) {
      ProductDuplicateMatchTier.exact => 'Es el mismo',
      ProductDuplicateMatchTier.strong => 'Casi seguro',
      ProductDuplicateMatchTier.possible => 'Parecido',
      ProductDuplicateMatchTier.ruledOut => 'Descartado',
      null => null,
    };

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReviewThumbnail(
                key: Key('ocr-candidate-product-image-${product.id}'),
                imageUrl: product.imageUrlOptimized ?? product.imageUrl,
                compact: MediaQuery.sizeOf(context).width < 720,
                semanticLabel: 'Ampliar imagen de ${product.name}',
                onTap: onImageTap,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        product.sku,
                        product.brand ?? 'Sin marca',
                        product.categoryName ?? 'Sin categoría',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        reasons.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    if (objections.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 13,
                            color: roles.warning.accent,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              objections.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: roles.warning.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (tierLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tone.container,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: tone.border),
                      ),
                      child: Text(
                        tierLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone.onContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (onSelected != null) ...[
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: onSelected,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Es este'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewThumbnail extends StatelessWidget {
  const _ReviewThumbnail({
    super.key,
    required this.imageUrl,
    required this.compact,
    required this.semanticLabel,
    required this.onTap,
  });

  final String? imageUrl;
  final bool compact;
  final String semanticLabel;
  final VoidCallback? onTap;

  // DesignSync was unavailable in this task. These owner-requested review
  // extents are explicitly unsourced until the component guide publishes an
  // image-inspection token; the large comparison pop-over below does not depend on
  // either value.
  static const double _compactExtent = 72;
  static const double _desktopExtent = 112;

  @override
  Widget build(BuildContext context) {
    final extent = compact ? _compactExtent : _desktopExtent;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: extent,
        height: extent,
        child: ImageService.buildProductImage(
          imageUrl: imageUrl,
          size: extent,
        ),
      ),
    );
    if (onTap == null) return image;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: 'Ampliar imagen',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                image,
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.open_in_full, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OcrComparisonImage {
  const _OcrComparisonImage({
    required this.key,
    required this.imageUrl,
    required this.title,
    required this.detail,
  });

  final String key;
  final String imageUrl;
  final String title;
  final String detail;
}

class _OcrComparisonImageViewer extends StatefulWidget {
  const _OcrComparisonImageViewer({
    required this.images,
    required this.initialIndex,
  });

  final List<_OcrComparisonImage> images;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required List<_OcrComparisonImage> images,
    required int initialIndex,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierLabel: 'Cerrar visor de imágenes',
      builder: (_) => _OcrComparisonImageViewer(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  State<_OcrComparisonImageViewer> createState() =>
      _OcrComparisonImageViewerState();
}

class _OcrComparisonImageViewerState extends State<_OcrComparisonImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(int index) {
    if (index < 0 || index >= widget.images.length) return;
    _controller.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = widget.images[_index];
    final hasSeveral = widget.images.length > 1;
    final screenSize = MediaQuery.sizeOf(context);
    // Reuse the established large-preview dialog envelope used by Files: this
    // keeps the candidate picker visible behind the scrim instead of replacing
    // the whole ERP surface with a second page.
    final horizontalInset = screenSize.width < 760 ? 12.0 : 42.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 24.0;
    final dialogWidth = (screenSize.width - horizontalInset * 2)
        .clamp(320.0, 1180.0)
        .toDouble();
    final dialogHeight =
        (screenSize.height - verticalInset * 2).clamp(360.0, 920.0).toDouble();

    return Dialog(
      key: const Key('ocr-comparison-image-viewer'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: scheme.surface,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    current.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSeveral)
                        Text('${_index + 1} de ${widget.images.length}'),
                      IconButton(
                        key: const Key('ocr-comparison-image-close'),
                        tooltip: 'Volver a los productos parecidos',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PageView.builder(
                          key: const Key('ocr-comparison-image-pages'),
                          controller: _controller,
                          itemCount: widget.images.length,
                          onPageChanged: (index) =>
                              setState(() => _index = index),
                          itemBuilder: (context, index) {
                            final image = widget.images[index];
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                return Semantics(
                                  image: true,
                                  label: '${image.title}. ${image.detail}',
                                  child: InteractiveViewer(
                                    key: ValueKey<String>(
                                      'ocr-comparison-image-${image.key}',
                                    ),
                                    minScale: 0.75,
                                    maxScale: 8,
                                    child: SizedBox(
                                      key: ValueKey<String>(
                                        'ocr-comparison-image-canvas-${image.key}',
                                      ),
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      child: ImageService.buildCachedImage(
                                        imageUrl: image.imageUrl,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      if (_index > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton.filledTonal(
                            key: const Key('ocr-comparison-image-previous'),
                            tooltip: 'Imagen anterior',
                            onPressed: () => _show(_index - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ),
                      if (_index + 1 < widget.images.length)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton.filledTonal(
                            key: const Key('ocr-comparison-image-next'),
                            tooltip: 'Imagen siguiente',
                            onPressed: () => _show(_index + 1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ),
                    ],
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
