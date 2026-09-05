import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../modules/inventory/models/inventory_models.dart';
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../../modules/ai_assistant/services/ai_service.dart';
import '../../modules/inventory/services/product_identity/supplier_resolution_proposal.dart';
import '../services/image_service.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_notice.dart';
import 'vb_status_badge.dart';
import 'vb_money_text.dart';
import 'ocr_review_evidence.dart';
import 'vb_searchable_select.dart';

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

/// Confirm the cached, grounded supplier-package decomposition.
class OcrCandidateConfirmComposition extends OcrCandidateDecision {
  const OcrCandidateConfirmComposition();
}

class OcrCandidateDefineComposition extends OcrCandidateDecision {
  const OcrCandidateDefineComposition(this.items);
  final List<SupplierResolutionProposalItem> items;
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

/// The row and the picker must ask the operator about candidates in exactly
/// the same order. Normal survivors come first; manual-only rows follow in the
/// matcher's stable ranking order. A category conflict is deliberately not
/// part of this list: it owns a separate section and must never become the
/// row's quick-link merely because the normal pool was exhausted.
List<ProductDuplicateCandidate> orderOcrCandidateChoices(
  Iterable<ProductDuplicateCandidate> candidates,
) {
  final normal = <ProductDuplicateCandidate>[];
  final manual = <ProductDuplicateCandidate>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final product = candidate.product;
    final key = product.id?.trim().isNotEmpty == true
        ? product.id!.trim()
        : product.sku.trim();
    if (!seen.add(key)) continue;
    if (candidate.isRuledOut || candidate.isReviewOnlyFamilyScope) {
      manual.add(candidate);
    } else {
      normal.add(candidate);
    }
  }
  return <ProductDuplicateCandidate>[...normal, ...manual];
}

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
    this.components = const [],
    this.sourceTotal,
    this.canConfirmCompositeProposal = false,
    this.allowCreateNew = true,
    this.inspectionOnly = false,
    this.onSearch,
    this.isLoading = false,
    this.errorMessage,
    this.requiresComposition = false,
    this.compositionItems = const [],
    this.allowComposition = true,
  });

  final OcrCandidateLineContext line;
  final bool requiresComposition;
  final bool allowComposition;
  final List<SupplierResolutionProposalItem> compositionItems;

  /// The immutable decision computed for this row revision. Opening the
  /// picker must not rerun vision, matching or AI adjudication.
  final List<ProductDuplicateCandidate> candidates;

  /// Same-family products filed outside the resolved category. They stay
  /// visible for catalog repair, but never compete in the normal list.
  final List<ProductDuplicateCandidate> categoryConflicts;

  /// The same immutable composite proposal shown in the row. It stays
  /// review-only until the host explicitly enables operator confirmation.
  final String? aiCompositeProposal;
  final List<OcrReviewComponent> components;
  final double? sourceTotal;
  final bool canConfirmCompositeProposal;

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
    List<OcrReviewComponent> components = const [],
    double? sourceTotal,
    bool canConfirmCompositeProposal = false,
    bool allowCreateNew = true,
    bool inspectionOnly = false,
    OcrCandidateSearch? onSearch,
    bool isLoading = false,
    String? errorMessage,
    bool requiresComposition = false,
    List<SupplierResolutionProposalItem> compositionItems = const [],
    bool allowComposition = true,
  }) {
    return showDialog<OcrCandidateDecision>(
      context: context,
      barrierLabel: 'Cerrar productos parecidos',
      builder: (_) => OcrCandidatePicker(
        line: line,
        candidates: candidates,
        categoryConflicts: categoryConflicts,
        aiCompositeProposal: aiCompositeProposal,
        components: components,
        sourceTotal: sourceTotal,
        canConfirmCompositeProposal: canConfirmCompositeProposal,
        allowCreateNew: allowCreateNew,
        inspectionOnly: inspectionOnly,
        onSearch: onSearch,
        isLoading: isLoading,
        errorMessage: errorMessage,
        requiresComposition: requiresComposition,
        compositionItems: compositionItems,
        allowComposition: allowComposition,
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
  bool _showDiscarded = false;
  bool _showConflicts = false;
  bool _showComposition = true;
  String? _searchError;
  bool _editingComposition = false;
  final List<SupplierResolutionProposalItem> _compositionItems = [];
  final List<int> _componentKeys = [];
  int _nextComponentKey = 0;

  @override
  void initState() {
    super.initState();
    _compositionItems.addAll(widget.compositionItems);
    _componentKeys
        .addAll([for (final _ in _compositionItems) _nextComponentKey++]);
    _editingComposition =
        widget.requiresComposition && widget.compositionItems.isEmpty;
  }

  bool get _selectsComponents =>
      widget.allowComposition &&
      (widget.requiresComposition ||
          _editingComposition ||
          widget.aiCompositeProposal?.isNotEmpty == true);

  void _selectProduct(Product product) {
    if (widget.inspectionOnly) return;
    if (!_selectsComponents) {
      Navigator.of(context).pop(OcrCandidateLink(product));
      return;
    }
    setState(() {
      _editingComposition = true;
      _compositionItems.add(SupplierResolutionProposalItem(
          product: product,
          catalogUnitsPerPurchase: 1,
          role: AIProductMatchComponentRole.component));
      _componentKeys.add(_nextComponentKey++);
    });
    FocusScope.of(context).unfocus();
  }

  Widget _compositionEditor(BuildContext context) {
    const roles = <AIProductMatchComponentRole, String>{
      AIProductMatchComponentRole.component: 'Componente',
      AIProductMatchComponentRole.homogeneous: 'Unidades iguales',
      AIProductMatchComponentRole.front: 'Delantero',
      AIProductMatchComponentRole.rear: 'Trasero',
      AIProductMatchComponentRole.left: 'Izquierdo',
      AIProductMatchComponentRole.right: 'Derecho',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Contenido de una compra',
          style: Theme.of(context).textTheme.titleSmall),
      if (_compositionItems.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Añade productos desde los resultados.')),
      for (var i = 0; i < _compositionItems.length; i++)
        Padding(
            key: ValueKey('ocr-content-${_componentKeys[i]}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            '${_compositionItems[i].product.sku} · ${_compositionItems[i].product.name}')),
                    IconButton(
                        tooltip: 'Quitar componente',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                              _compositionItems.removeAt(i);
                              _componentKeys.removeAt(i);
                            }))
                  ]),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: TextFormField(
                            key: ValueKey(
                                'ocr-content-units-${_componentKeys[i]}'),
                            initialValue:
                                '${_compositionItems[i].catalogUnitsPerPurchase}',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Unidades por compra'),
                            onChanged: (value) => setState(() {
                                  final item = _compositionItems[i];
                                  _compositionItems[i] =
                                      SupplierResolutionProposalItem(
                                          product: item.product,
                                          catalogUnitsPerPurchase:
                                              int.tryParse(value) ?? 0,
                                          role: item.role);
                                }))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: VbSearchableSelect<AIProductMatchComponentRole>(
                            sheetTitle: 'Función del componente',
                            value: roles.containsKey(_compositionItems[i].role)
                                ? _compositionItems[i].role
                                : AIProductMatchComponentRole.component,
                            options: [
                              for (final role in roles.entries)
                                VbSearchableSelectOption(
                                    value: role.key, label: role.value)
                            ],
                            onChanged: (role) {
                              if (role != null) {
                                setState(() {
                                  final item = _compositionItems[i];
                                  _compositionItems[i] =
                                      SupplierResolutionProposalItem(
                                          product: item.product,
                                          catalogUnitsPerPurchase:
                                              item.catalogUnitsPerPurchase,
                                          role: role);
                                });
                              }
                            }))
                  ]),
                  if (widget.line.quantity != null &&
                      _compositionItems[i].catalogUnitsPerPurchase > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            '${ocrReviewNumber(widget.line.quantity!)} × ${_compositionItems[i].catalogUnitsPerPurchase} = '
                            '${ocrReviewNumber(widget.line.quantity! * _compositionItems[i].catalogUnitsPerPurchase)} unidades al recibir',
                            style: Theme.of(context).textTheme.bodySmall)),
                ])),
    ]);
  }

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
    final compact = MediaQuery.sizeOf(context).width < 900;
    final hasComposition =
        widget.aiCompositeProposal?.trim().isNotEmpty == true;
    final footer = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar')),
                if (!widget.inspectionOnly && widget.allowCreateNew)
                  OutlinedButton(
                      key: const Key('ocr-candidate-create-new'),
                      onPressed: () => Navigator.of(context)
                          .pop(const OcrCandidateCreateNew()),
                      child: const Text('Marcar como nuevo')),
                if (!widget.inspectionOnly && _editingComposition)
                  FilledButton(
                      key: const Key('ocr-candidate-review-content'),
                      onPressed: _compositionItems.isNotEmpty &&
                              _compositionItems.every((item) =>
                                  item.catalogUnitsPerPurchase > 0 &&
                                  item.catalogUnitsPerPurchase <= 1000000)
                          ? () => Navigator.of(context).pop(
                              OcrCandidateDefineComposition(
                                  List.unmodifiable(_compositionItems)))
                          : null,
                      child: const Text('Aplicar y guardar regla')),
                if (!widget.inspectionOnly &&
                    !_editingComposition &&
                    widget.canConfirmCompositeProposal &&
                    hasComposition)
                  FilledButton(
                      key: const Key('ocr-candidate-confirm-composite'),
                      onPressed: () => Navigator.of(context)
                          .pop(const OcrCandidateConfirmComposition()),
                      child: const Text('Usar descomposición')),
              ]),
        ));
    return Dialog(
      key: const Key('ocr-candidate-picker-dialog'),
      insetPadding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : 24, vertical: compact ? 0 : 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: OcrCandidatePicker.maxWidth,
            maxHeight: OcrCandidatePicker.maxHeight),
        child: SizedBox(
          key: const Key('ocr-candidate-picker-shell'),
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              hasComposition
                                  ? 'Revisar composición'
                                  : 'Comparar productos',
                              style: theme.textTheme.titleMedium)),
                      IconButton(
                          key: const Key('ocr-candidate-close'),
                          tooltip: 'Cerrar comparación',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close)),
                    ])),
                if (widget.onSearch != null)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextField(
                          key: const Key('ocr-candidate-search'),
                          controller: _query,
                          decoration: InputDecoration(
                              isDense: !compact,
                              hintText: 'Buscar nombre, SKU o marca',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)))
                                  : _query.text.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'Limpiar búsqueda',
                                          onPressed: () {
                                            _query.clear();
                                            _onQueryChanged('');
                                          },
                                          icon: const Icon(Icons.close))
                                      : null),
                          onChanged: _onQueryChanged)),
                Expanded(
                    child: CustomScrollView(
                        key: const Key('ocr-candidate-scroll'),
                        slivers: [
                      SliverToBoxAdapter(
                          child: _Header(
                              line: widget.line,
                              compact: compact,
                              compositeReview: hasComposition,
                              onImageTap: widget.line.imageUrl
                                          ?.trim()
                                          .isNotEmpty ==
                                      true
                                  ? () => _openImageViewer(initialKey: 'source')
                                  : null)),
                      if (hasComposition)
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextButton.icon(
                                          key: const Key(
                                              'ocr-candidate-ai-composite-proposal'),
                                          onPressed: () => setState(() =>
                                              _showComposition =
                                                  !_showComposition),
                                          icon: Icon(_showComposition
                                              ? Icons.expand_less
                                              : Icons.expand_more),
                                          label: const Text(
                                              'Descomposición propuesta')),
                                      if (!_editingComposition &&
                                          _showComposition &&
                                          widget.components.isNotEmpty)
                                        OcrCompositionReview(
                                            components: widget.components,
                                            sourceQuantity:
                                                widget.line.quantity,
                                            sourceTotal: widget.sourceTotal)
                                      else if (!_editingComposition &&
                                          _showComposition)
                                        Text(widget.aiCompositeProposal!,
                                            style: theme.textTheme.bodySmall),
                                    ]))),
                      if (!widget.inspectionOnly && widget.allowComposition)
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: _editingComposition
                                    ? _compositionEditor(context)
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                            key: const Key(
                                                'ocr-candidate-edit-content'),
                                            onPressed: () => setState(() =>
                                                _editingComposition = true),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            label: Text(
                                                _compositionItems.isEmpty
                                                    ? 'Definir contenido'
                                                    : 'Editar contenido'))))),
                      if (!widget.allowCreateNew && widget.errorMessage != null)
                        const SliverToBoxAdapter(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: VbNotice(
                                    title: 'La revisión falló',
                                    body:
                                        'Reintenta o busca manualmente un producto. El fallo no demuestra que sea nuevo.',
                                    tone: VbNoticeTone.warning))),
                      SliverToBoxAdapter(child: _body(context, compact)),
                    ])),
                const Divider(height: 1),
                footer,
              ])),
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
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: manual.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _CandidateRow(
          product: manual[index],
          reasons: const <String>[],
          objections: const <String>[],
          tier: null,
          evidence: null,
          onImageTap: () => _openProductImage(
            manual[index],
            products: manual,
          ),
          onSelected: widget.inspectionOnly
              ? null
              : () => _selectProduct(manual[index]),
          addsComponent: _selectsComponents,
        ),
      );
    }

    final offered = orderOcrCandidateChoices(widget.candidates);
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
    final viable = offered
        .where((candidate) =>
            !candidate.isRuledOut && !candidate.isReviewOnlyFamilyScope)
        .toList();
    final ruledOut = offered
        .where((candidate) =>
            candidate.isRuledOut || candidate.isReviewOnlyFamilyScope)
        .toList();
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
          evidence: OcrCandidateEvidence.forCandidate(candidate),
          onImageTap: () => _openProductImage(candidate.product),
          onSelected: widget.inspectionOnly
              ? null
              : () => _selectProduct(candidate.product),
          addsComponent: _selectsComponents,
        ),
      if (ruledOut.isNotEmpty) ...[
        TextButton.icon(
            key: const Key('ocr-candidate-ruled-out-heading'),
            onPressed: () => setState(() => _showDiscarded = !_showDiscarded),
            icon: Icon(_showDiscarded ? Icons.expand_less : Icons.expand_more),
            label: Text(
                '${_showDiscarded ? 'Ocultar' : 'Ver'} ${ruledOut.length} ${ruledOut.length == 1 ? 'descartado' : 'descartados'} y sus diferencias')),
        if (_showDiscarded)
          for (final candidate in ruledOut)
            _CandidateRow(
              product: candidate.product,
              reasons: candidate.reasons,
              objections: candidate.objections,
              tier: candidate.matchTier,
              evidence: OcrCandidateEvidence.forCandidate(candidate),
              onImageTap: () => _openProductImage(candidate.product),
              onSelected: widget.inspectionOnly
                  ? null
                  : () => _selectProduct(candidate.product),
              addsComponent: _selectsComponents,
            ),
      ],
      if (categoryConflicts.isNotEmpty) ...[
        TextButton.icon(
            key: const Key('ocr-candidate-category-conflicts-heading'),
            onPressed: () => setState(() => _showConflicts = !_showConflicts),
            icon: Icon(_showConflicts || viable.isEmpty
                ? Icons.expand_less
                : Icons.expand_more),
            label: Text(
                '${categoryConflicts.length} ${categoryConflicts.length == 1 ? 'producto' : 'productos'} en otra categoría')),
        if (_showConflicts || viable.isEmpty)
          for (final candidate in categoryConflicts)
            _CandidateRow(
              product: candidate.product,
              reasons: candidate.reasons,
              objections: <String>[
                ...candidate.objections,
                'Revisa la categoría del producto antes de vincular',
              ],
              tier: candidate.matchTier,
              evidence: OcrCandidateEvidence.forCandidate(candidate),
              onImageTap: () => _openProductImage(candidate.product),
              onSelected: widget.inspectionOnly
                  ? null
                  : () => _selectProduct(candidate.product),
              addsComponent: _selectsComponents,
            ),
      ],
    ];

    return ListView.separated(
      key: const Key('ocr-candidate-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      if (line.unitCost != null)
        'Costo ${VbMoneyText.formatClp(line.unitCost!)}',
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
                      ? 'COMPRADO · presentación del proveedor'
                      : 'COMPRADO · variante a identificar',
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
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
  const _CandidateRow(
      {required this.product,
      required this.reasons,
      required this.objections,
      required this.tier,
      required this.evidence,
      required this.onSelected,
      this.addsComponent = false,
      required this.onImageTap});
  final Product product;
  final List<String> reasons;
  final List<String> objections;
  final ProductDuplicateMatchTier? tier;
  final OcrCandidateEvidence? evidence;
  final VoidCallback? onSelected;
  final VoidCallback? onImageTap;
  final bool addsComponent;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 900;
    final manual =
        tier == ProductDuplicateMatchTier.ruledOut || objections.isNotEmpty;
    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(product.name,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(
          [
            product.sku,
            if (product.brand?.isNotEmpty == true) product.brand!,
            if (product.categoryName?.isNotEmpty == true) product.categoryName!
          ].join(' · '),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      if (reasons.isNotEmpty) ...[
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final visible = reasons
              .where((reason) =>
                  !reason.startsWith('Evidencia de IA:') &&
                  !reason.startsWith('Es ') &&
                  !reason.startsWith('Misma categoría') &&
                  !reason.startsWith('Fabricante '))
              .toList();
          final columns = constraints.maxWidth >= 440 ? 2 : 1;
          return Wrap(spacing: 16, runSpacing: 4, children: [
            for (final reason in visible)
              SizedBox(
                  width: (constraints.maxWidth - 16 * (columns - 1)) / columns,
                  child: Text(ocrReadableEvidence(reason),
                      style: theme.textTheme.bodySmall))
          ]);
        }),
      ],
      if (objections.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Diferencias que debes revisar',
            style: theme.textTheme.labelSmall?.copyWith(
                color: VinabikeThemeRoles.of(context).warning.accent)),
        for (final objection in objections)
          Text(ocrReadableEvidence(objection),
              style: theme.textTheme.bodySmall),
      ],
    ]);
    final actions = Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (evidence != null)
            VbStatusBadge(label: evidence!.label, tone: evidence!.tone),
          if (onSelected != null)
            OutlinedButton(
                key: ValueKey('ocr-candidate-select-${product.id}'),
                onPressed: onSelected,
                child: Text(addsComponent
                    ? 'Añadir al contenido'
                    : manual
                        ? 'Seleccionar con diferencias'
                        : 'Seleccionar producto')),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ReviewThumbnail(
              key: Key('ocr-candidate-product-image-${product.id}'),
              imageUrl: product.imageUrlOptimized ?? product.imageUrl,
              compact: compact,
              semanticLabel: 'Ampliar imagen de ${product.name}',
              onTap: onImageTap),
          const SizedBox(width: 16),
          Expanded(child: details),
        ]),
        if (reasons.any((reason) => reason.startsWith('Evidencia de IA:')))
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Cómo se comparó', style: theme.textTheme.labelSmall),
              children: [
                for (final reason in reasons
                    .where((reason) => reason.startsWith('Evidencia de IA:')))
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(ocrReadableEvidence(reason),
                          style: theme.textTheme.bodySmall))
              ]),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: actions),
      ]),
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
