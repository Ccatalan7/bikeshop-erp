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
    this.onSearch,
    this.onLoadOptions,
    this.isLoading = false,
    this.errorMessage,
  });

  final OcrCandidateLineContext line;

  /// What the row already had. Shown immediately so the overlay never opens
  /// empty, then replaced by [onLoadOptions] when that answers.
  final List<ProductDuplicateCandidate> candidates;

  /// The wider question this surface exists to ask: every product of the same
  /// kind, including the ones a gate ruled out and why.
  ///
  /// The row's list is deliberately conservative. Reusing it here left the
  /// operator with one wrong option and «crear nuevo» — and creating a
  /// duplicate of a product that already exists is the failure the whole
  /// reconciliation step exists to prevent.
  final Future<List<ProductDuplicateCandidate>> Function()? onLoadOptions;

  /// Free-text catalog search. Absent when the host cannot search.
  final OcrCandidateSearch? onSearch;

  final bool isLoading;
  final String? errorMessage;

  /// Comfortable for a photo grid; still clearly a decision about one line and
  /// not a second application window.
  static const double maxWidth = 720;
  static const double maxHeight = 640;

  static Future<OcrCandidateDecision?> show(
    BuildContext context, {
    required OcrCandidateLineContext line,
    required List<ProductDuplicateCandidate> candidates,
    OcrCandidateSearch? onSearch,
    Future<List<ProductDuplicateCandidate>> Function()? onLoadOptions,
    bool isLoading = false,
    String? errorMessage,
  }) {
    return showDialog<OcrCandidateDecision>(
      context: context,
      barrierLabel: 'Cerrar productos parecidos',
      builder: (_) => OcrCandidatePicker(
        line: line,
        candidates: candidates,
        onSearch: onSearch,
        onLoadOptions: onLoadOptions,
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

  /// The full option list, once the host has answered.
  List<ProductDuplicateCandidate>? _options;
  bool _loadingOptions = false;

  List<ProductDuplicateCandidate> get _offered => _options ?? widget.candidates;

  @override
  void initState() {
    super.initState();
    final loader = widget.onLoadOptions;
    if (loader == null) return;
    _loadingOptions = true;
    final generation = _generation;
    loader().then((options) {
      if (!_owns(generation)) return;
      setState(() {
        _options = options;
        _loadingOptions = false;
      });
    }).catchError((Object _) {
      if (!_owns(generation)) return;
      // The row's own candidates remain; failing to widen the list is not a
      // reason to show nothing.
      setState(() => _loadingOptions = false);
    });
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
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 32),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: OcrCandidatePicker.maxWidth,
          maxHeight: OcrCandidatePicker.maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(line: widget.line, compact: compact),
            Divider(height: 1, color: theme.dividerColor),
            if (widget.onSearch != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16, 12, compact ? 12 : 16, 8),
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar otro producto por nombre, SKU o marca',
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
                      'Si ninguno es, se crea un producto nuevo con esta ficha.',
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
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: const Key('ocr-candidate-create-new'),
                    onPressed: () => Navigator.of(context)
                        .pop(const OcrCandidateCreateNew()),
                    child: const Text('Ninguno · crear nuevo'),
                  ),
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
          onSelected: () =>
              Navigator.of(context).pop(OcrCandidateLink(manual[index])),
        ),
      );
    }

    final offered = _offered;
    if (offered.isEmpty) {
      if (_loadingOptions) {
        return const Center(child: CircularProgressIndicator());
      }
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

    // Two groups, one list. The offered products come first; the ones a gate
    // ruled out follow under a heading that says so, because the operator may
    // be here precisely because the specification this engine read is what is
    // wrong. Hiding them made the overlay a dead end whose only exits were the
    // wrong product or a duplicate.
    final viable = offered.where((candidate) => !candidate.isRuledOut).toList();
    final ruledOut =
        offered.where((candidate) => candidate.isRuledOut).toList();
    final rows = <Widget>[
      for (final candidate in viable)
        _CandidateRow(
          product: candidate.product,
          reasons: candidate.reasons,
          objections: candidate.objections,
          tier: candidate.matchTier,
          onSelected: () =>
              Navigator.of(context).pop(OcrCandidateLink(candidate.product)),
        ),
      if (ruledOut.isNotEmpty) ...[
        Padding(
          key: const Key('ocr-candidate-ruled-out-heading'),
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            'Del mismo tipo, descartados por una diferencia',
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
            onSelected: () =>
                Navigator.of(context).pop(OcrCandidateLink(candidate.product)),
          ),
      ],
      if (_loadingOptions)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
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
  const _Header({required this.line, required this.compact});

  final OcrCandidateLineContext line;
  final bool compact;

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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ImageService.buildProductImage(
                imageUrl: line.imageUrl,
                size: 52,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Cuál de estos es?',
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
  });

  final Product product;
  final List<String> reasons;
  final List<String> objections;
  final ProductDuplicateMatchTier? tier;
  final VoidCallback onSelected;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ImageService.buildProductImage(
                    imageUrl: product.imageUrlOptimized ?? product.imageUrl,
                    size: 64,
                  ),
                ),
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
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: onSelected,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Es este'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
