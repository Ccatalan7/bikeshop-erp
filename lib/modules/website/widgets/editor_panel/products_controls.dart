part of '../website_editor_panel.dart';

/// Products block controls - Enhanced with product selection, layout, and display options
class _ProductsBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _ProductsBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_ProductsBlockControls> createState() => _ProductsBlockControlsState();
}

class _ProductsBlockControlsState extends State<_ProductsBlockControls> {
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _availableCategories = [];
  bool _isLoading = true;
  int _catalogLoadGeneration = 0;
  Object? _catalogOwnerRevision;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant _ProductsBlockControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentOwner =
        _asyncFieldBinding('root.productsCatalogRead').readOwnerIdentity;
    if (_catalogOwnerRevision != currentOwner) _loadData();
  }

  Future<void> _loadData() async {
    final openingBinding = _asyncFieldBinding('root.productsCatalogRead');
    final ownerRevision = openingBinding.readOwnerIdentity;
    final generation = ++_catalogLoadGeneration;
    _catalogOwnerRevision = ownerRevision;
    final arm = openingBinding.capture();
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: arm,
      liveBinding: () => _asyncFieldBinding('root.productsCatalogRead'),
      isMounted: () => mounted,
      operation: 'cargar el catálogo del bloque Productos',
    );
    if (mounted && !_isLoading) setState(() => _isLoading = true);
    try {
      final authority = remoteAuthority?.call();
      if (authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del catálogo cambió antes de cargar Productos.',
        );
      }
      final readGuard = authority.claimForWrite();
      final supabase = Supabase.instance.client;

      // Load ALL active products (so user can see/deselect old selections)
      // We'll mark unavailable ones in the picker UI
      readGuard();
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
          .eq('tenant_id', authority.tenantId)
          .eq('is_active', true)
          .order('name', ascending: true)
          .limit(2000);
      readGuard();

      var allProducts = List<Map<String, dynamic>>.from(productsResponse);

      // Also load selected products that might be inactive (so we can display/deselect them)
      final selectedIds = _selectedProductIds;
      if (selectedIds.isNotEmpty) {
        final selectedResponse = await supabase
            .from('products')
            .select(
                'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
            .eq('tenant_id', authority.tenantId)
            .inFilter('id', selectedIds);
        readGuard();

        // Add any selected products not already in the list
        for (final selected in selectedResponse) {
          final exists = allProducts
              .any((p) => p['id'].toString() == selected['id'].toString());
          if (!exists) {
            allProducts.add(Map<String, dynamic>.from(selected));
          }
        }
      }

      // Load categories
      final categoriesResponse = await supabase
          .from('product_categories')
          .select('id, name')
          .eq('tenant_id', authority.tenantId)
          .order('name', ascending: true);
      readGuard();
      authority.ensureCurrent();

      if (mounted &&
          generation == _catalogLoadGeneration &&
          _asyncFieldBinding('root.productsCatalogRead').readOwnerIdentity ==
              ownerRevision) {
        setState(() {
          _availableProducts = allProducts;
          _availableCategories =
              List<Map<String, dynamic>>.from(categoriesResponse);
          _isLoading = false;
        });
      }
    } on WebsiteEditorWriteSupersededException {
      if (mounted && generation == _catalogLoadGeneration) {
        setState(() {
          _availableProducts = const <Map<String, dynamic>>[];
          _availableCategories = const <Map<String, dynamic>>[];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted &&
          generation == _catalogLoadGeneration &&
          _asyncFieldBinding('root.productsCatalogRead').readOwnerIdentity ==
              ownerRevision) {
        setState(() => _isLoading = false);
      }
    }
  }

  WebsiteProductsBlockContract get _contract =>
      WebsiteProductsBlockContract.fromData(widget.data);

  WebsiteInlineManipulationProperty _sharedProperty(
    String key, {
    Iterable<String> companionKeys = const <String>[],
  }) {
    return WebsiteInlineManipulationProperty(
      canonicalKey: key,
      policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      sharedCompanionKeys: companionKeys,
    );
  }

  WebsiteInlineManipulationTarget _sharedTarget(
    Iterable<WebsiteInlineManipulationProperty> properties,
  ) {
    return WebsiteInlineManipulationTarget(
      blockId: widget.blockId,
      owner: const WebsiteInlineBlockOwner(),
      viewport: WebsiteEditorAuthoringViewportScope.effectiveOf(
        context,
        fallback: widget.provider.previewViewport,
      ),
      properties: properties,
      requiresSelection: true,
    );
  }

  WebsiteInlineManipulationLease? _captureSharedLease(
    Iterable<WebsiteInlineManipulationProperty> properties,
  ) {
    return widget.provider.captureInlineMutationLease(
      _sharedTarget(properties),
    );
  }

  WebsiteInlineMutationResult Function(Map<String, Object?>)
      _sharedMutationBinding(
    Iterable<WebsiteInlineManipulationProperty> properties, {
    bool recaptureAccepted = false,
  }) {
    final frozenProperties = List<WebsiteInlineManipulationProperty>.of(
      properties,
      growable: false,
    );
    var lease = _captureSharedLease(frozenProperties);
    return (values) {
      final currentLease = lease;
      if (currentLease == null) return WebsiteInlineMutationResult.rejected;
      lease = null;
      final result = widget.provider.commitInlineMutation(
        currentLease,
        values,
      );
      // Text/IME controls can emit repeatedly before their rebuild. Discrete
      // controls deliberately remain one-shot so a double callback from one
      // rendered source cannot become two commands.
      if (recaptureAccepted && result.accepted) {
        lease = _captureSharedLease(frozenProperties);
      }
      return result;
    };
  }

  WebsiteAsyncFieldBinding _asyncFieldBinding(String scopeKey) {
    return WebsiteAsyncFieldBinding.pageBlock(
      provider: widget.provider,
      target: WebsiteAsyncFieldTarget.block(
        blockId: widget.blockId,
        scopeKey: scopeKey,
      ),
    );
  }

  /// Binds one presentation property of this block through the canonical
  /// owner, using the registry schema instead of a hand-written key.
  ///
  /// The catalogue source, category, selected ids, `maxProducts` and the "view
  /// all" copy/destination are business identity and therefore use exact
  /// shared-only leases rather than responsive overrides.
  WebsiteResponsiveScalarBinding<T>? _presentationBinding<T>(
    String key,
    WebsiteResponsiveDecoder<T> decode, {
    String? unavailableReason,
  }) {
    final field = WebsiteBlockRegistry.fieldForPath(
      WebsiteBlockType.products,
      key,
    );
    if (field == null) return null;
    final effectiveViewport = WebsiteEditorAuthoringViewportScope.effectiveOf(
      context,
      fallback: widget.provider.previewViewport,
    );
    return WebsiteResponsiveScalarBinding<T>.forField(
      provider: widget.provider,
      blockId: widget.blockId,
      field: field,
      owner: const WebsiteResponsiveRootField(),
      decode: decode,
      hostClass: WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
          WebsiteAuthoringHostClass.desktop,
      viewport: effectiveViewport,
      unavailableReason: unavailableReason,
    );
  }

  /// Why `Productos por fila` cannot be edited for the previewed viewport.
  ///
  /// Null on Desktop, where the value IS the base and is editable. On the other
  /// two the storefront computes the columns itself, so the control stays
  /// visible and inert with the real reason instead of offering a change that
  /// would not reach the page.
  String? get _itemsPerRowUnavailableReason {
    final effectiveViewport = WebsiteEditorAuthoringViewportScope.effectiveOf(
      context,
      fallback: widget.provider.previewViewport,
    );
    return switch (effectiveViewport) {
      WebsiteViewport.desktop => null,
      WebsiteViewport.mobile =>
        'En móvil la cuadrícula usa una columna segura y el carrusel una '
            'tarjeta visible. Este número sólo aplica en escritorio.',
      WebsiteViewport.tablet =>
        'En tablet las columnas se calculan solas para que las tarjetas '
            'queden legibles. Este número sólo aplica en escritorio.',
    };
  }

  /// Mounts a presentation control under the canonical inheritance shell.
  ///
  /// The shell owns label, status, scope sentence and the customize/reset
  /// action, so the control inside carries no second label.
  Widget _mountPresentationField<T>(
    WebsiteResponsiveScalarBinding<T>? binding,
    Widget Function(WebsiteResponsiveScalarBinding<T> binding) build,
  ) {
    if (binding == null) return const SizedBox.shrink();
    return ResponsiveFieldShell<T>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      child: build(binding),
    );
  }

  List<String> get _selectedProductIds => _contract.productIds;
  String get _productSource => _contract.productSource;
  String? get _selectedCategoryId => _contract.categoryId;
  int get _itemsPerRow => _contract.itemsPerRow;
  int get _maxProducts => _contract.maxProducts;

  @override
  Widget build(BuildContext context) {
    final writeTitle = _sharedMutationBinding(
      <WebsiteInlineManipulationProperty>[_sharedProperty('title')],
      recaptureAccepted: true,
    );
    final writeSubtitle = _sharedMutationBinding(
      <WebsiteInlineManipulationProperty>[_sharedProperty('subtitle')],
      recaptureAccepted: true,
    );
    final writeProductSource = _sharedMutationBinding(
      <WebsiteInlineManipulationProperty>[_sharedProperty('productSource')],
    );
    final writeCategory = _sharedMutationBinding(
      <WebsiteInlineManipulationProperty>[_sharedProperty('categoryId')],
    );
    final selectionProperties = <WebsiteInlineManipulationProperty>[
      _sharedProperty(
        WebsiteProductsBlockContract.productIdsKey,
        companionKeys: const <String>[
          WebsiteProductsBlockContract.legacySelectedProductsKey,
        ],
      ),
    ];
    final writeSelection = _sharedMutationBinding(selectionProperties);
    final pickerLease = _captureSharedLease(selectionProperties);
    final maxProductsProperties = <WebsiteInlineManipulationProperty>[
      _sharedProperty('maxProducts'),
    ];
    final writeViewAllAction = _sharedMutationBinding(
      <WebsiteInlineManipulationProperty>[
        _sharedProperty('viewAllText'),
        _sharedProperty('viewAllLink'),
        _sharedProperty('actionVariant'),
        _sharedProperty('actions'),
      ],
      // The universal action editor contains text/URL inputs. Like every IME
      // binding it may emit again before its parent rebuilds, so an admitted
      // write rearms from the provider's new exact source. Rejected callbacks
      // never rearm and therefore cannot redirect to a newer page or block.
      recaptureAccepted: true,
    );
    final layoutBinding = _presentationBinding<String>(
      'layout',
      WebsiteResponsiveScalarBinding.decodeOption,
    );
    final showPriceBinding = _presentationBinding<bool>(
      'showPrice',
      WebsiteResponsiveScalarBinding.decodeBoolean,
    );
    final showSkuBinding = _presentationBinding<bool>(
      'showSku',
      WebsiteResponsiveScalarBinding.decodeBoolean,
    );
    final showBrandBinding = _presentationBinding<bool>(
      'showBrand',
      WebsiteResponsiveScalarBinding.decodeBoolean,
    );
    final showViewAllBinding = _presentationBinding<bool>(
      'showViewAll',
      WebsiteResponsiveScalarBinding.decodeBoolean,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsibleSection(
          title: 'Contenido y origen',
          icon: Icons.inventory_2_outlined,
          initiallyExpanded: true,
          children: [
            _EditorTextField(
              label: 'Título de sección',
              value: widget.data['title']?.toString() ?? '',
              asyncBinding: _asyncFieldBinding('root.title'),
              onChanged: (value) => writeTitle(
                <String, Object?>{'title': value},
              ),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Subtítulo',
              value: widget.data['subtitle']?.toString() ?? '',
              asyncBinding: _asyncFieldBinding('root.subtitle'),
              onChanged: (value) => writeSubtitle(
                <String, Object?>{'subtitle': value},
              ),
            ),

            const SizedBox(height: 20),
            const _SectionHeader('Fuente de productos'),
            const SizedBox(height: 12),

            // Product source selector
            _buildSourceSelector(
              (value) => writeProductSource(
                <String, Object?>{'productSource': value},
              ),
            ),

            const SizedBox(height: 16),

            // Conditional content based on source
            if (_productSource == 'category')
              _buildCategorySelector(
                (value) => writeCategory(
                  <String, Object?>{'categoryId': value},
                ),
              ),
            if (_productSource == 'manual')
              _buildProductSelector(
                onRemove: (productId) {
                  final next = List<String>.from(_selectedProductIds)
                    ..remove(productId);
                  final normalized =
                      WebsiteProductsBlockContract.selectionWrite(
                              next)[WebsiteProductsBlockContract.productIdsKey]
                          as List<String>;
                  writeSelection(<String, Object?>{
                    WebsiteProductsBlockContract.productIdsKey: normalized,
                  });
                },
                onOpenPicker: () => _showProductPicker(
                  context,
                  pickerLease,
                ),
              ),
          ],
        ),
        _CollapsibleSection(
          title: 'Diseño de productos',
          icon: Icons.grid_view_rounded,
          initiallyExpanded: false,
          children: [
            _mountPresentationField<String>(
              layoutBinding,
              (binding) => VbSegmented<String>(
                groupLabel: 'Diseño de productos',
                value: binding.value ?? _contract.layout,
                options: const [
                  VbSegmentedOption(value: 'grid', label: 'Cuadrícula'),
                  VbSegmentedOption(value: 'carousel', label: 'Carrusel'),
                ],
                onChanged: binding.write,
              ),
            ),
            const SizedBox(height: 12),

            // Items per row — same chips as before, now resolved through the
            // canonical binding. It is a SHARED base value: on mobile and
            // tablet the shell renders it inert with its reason, because the
            // storefront decides the columns there by itself.
            _mountPresentationField<num>(
              _presentationBinding<num>(
                'itemsPerRow',
                WebsiteResponsiveScalarBinding.decodeNumber,
                unavailableReason: _itemsPerRowUnavailableReason,
              ),
              (binding) {
                final selectedCount = binding.value?.toInt() ?? _itemsPerRow;
                return VbSegmented<int>(
                  groupLabel: 'Productos por fila',
                  value: selectedCount,
                  options: const [
                    VbSegmentedOption(value: 2, label: '2'),
                    VbSegmentedOption(value: 3, label: '3'),
                    VbSegmentedOption(value: 4, label: '4'),
                  ],
                  onChanged: binding.write,
                );
              },
            ),

            const SizedBox(height: 16),
            _InlineLeaseCommitSlider(
              key: const Key('products-max-products-slider'),
              label: 'Máximo de productos',
              value: _maxProducts.toDouble(),
              min: 4,
              max: 16,
              divisions: 6,
              onLeaseStart: () => _captureSharedLease(maxProductsProperties),
              onCommitted: (lease, value) =>
                  widget.provider.commitInlineMutation(
                lease,
                <String, Object?>{'maxProducts': value.toInt()},
              ),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Información visible',
          icon: Icons.visibility_outlined,
          initiallyExpanded: false,
          children: [
            _mountPresentationField<bool>(
              showPriceBinding,
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? _contract.showPrice,
                onChanged: binding.write,
              ),
            ),
            const SizedBox(height: 8),
            _mountPresentationField<bool>(
              showViewAllBinding,
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? _contract.showViewAll,
                onChanged: binding.write,
              ),
            ),
            const SizedBox(height: 8),
            _mountPresentationField<bool>(
              showSkuBinding,
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? _contract.showSku,
                onChanged: binding.write,
              ),
            ),
            const SizedBox(height: 8),
            _mountPresentationField<bool>(
              showBrandBinding,
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? _contract.showBrand,
                onChanged: binding.write,
              ),
            ),
          ],
        ),
        if (showViewAllBinding?.value ?? _contract.showViewAll)
          _CollapsibleSection(
            title: 'Acción “Ver todos”',
            icon: Icons.call_to_action_outlined,
            initiallyExpanded: false,
            children: [
              WebsiteActionEditor(
                title: 'Botón Ver todos',
                showVariant: true,
                asyncBinding: _asyncFieldBinding('root.viewAllAction'),
                value: WebsiteActionValue.resolvePrimary(
                      widget.data,
                      labelKeys: const ['viewAllText'],
                      hrefKeys: const ['viewAllLink'],
                      defaultLabel: 'Ver todos los productos',
                      defaultHref: '/productos',
                      defaultVariant: WebsiteActionVariant.outline,
                    ) ??
                    const WebsiteActionValue(
                      label: 'Ver todos los productos',
                      href: '/productos',
                      variant: WebsiteActionVariant.outline,
                    ),
                onChanged: (action) {
                  return writeViewAllAction(<String, Object?>{
                    'viewAllText': action.label,
                    'viewAllLink': action.href,
                    'actionVariant': action.variant.storageValue,
                    'actions': WebsiteActionValue.mergePrimary(
                      widget.data['actions'],
                      action,
                    ),
                  });
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSourceSelector(ValueChanged<String> onChanged) {
    return VbSegmented<String>(
      groupLabel: 'Fuente de productos',
      value: _productSource,
      options: const [
        VbSegmentedOption(value: 'featured', label: 'Destacados'),
        VbSegmentedOption(value: 'category', label: 'Categoría'),
        VbSegmentedOption(value: 'manual', label: 'Manual'),
        VbSegmentedOption(value: 'newest', label: 'Recientes'),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildCategorySelector(ValueChanged<String> onChanged) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Seleccionar categoría',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
          ),
          child: MenuAnchor(
            style: MenuStyle(
              backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
              surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
              padding: WidgetStateProperty.all(EdgeInsets.zero),
            ),
            menuChildren: _availableCategories.map((cat) {
              final catId = cat['id'].toString();
              return MenuItemButton(
                onPressed: () => onChanged(catId),
                style: ButtonStyle(
                  backgroundColor: _selectedCategoryId == catId
                      ? WidgetStateProperty.all(
                          Colors.white.withValues(alpha: 0.1))
                      : null,
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: Text(
                    cat['name']?.toString() ?? 'Sin nombre',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            }).toList(),
            builder: (context, controller, child) {
              final selectedName = _availableCategories
                      .firstWhere(
                        (c) => c['id'].toString() == _selectedCategoryId,
                        orElse: () => {},
                      )['name']
                      ?.toString() ??
                  'Seleccionar...';

              return WebsiteEditorControlTarget(
                targetKey: const Key('products-category-selector'),
                semanticLabel: 'Seleccionar categoría. $selectedName',
                minimumWidth: true,
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          selectedName,
                          style: TextStyle(
                            color: _selectedCategoryId == null
                                ? Colors.white54
                                : Colors.white,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.expand_more,
                          color: Colors.white54, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductSelector({
    required ValueChanged<String> onRemove,
    required VoidCallback onOpenPicker,
  }) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Productos seleccionados (${_selectedProductIds.length})',
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            WebsiteEditorControlTarget(
              targetKey: const Key('products-add-selection'),
              semanticLabel: 'Agregar productos',
              minimumWidth: true,
              onTap: onOpenPicker,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Agregar',
                  style: TextStyle(color: Color(0xFF00A09D), fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedProductIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay productos seleccionados\nToca "Agregar" para elegir productos',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...(_selectedProductIds.map((productId) {
            final product = _availableProducts.firstWhere(
              (p) => p['id'].toString() == productId,
              orElse: () => <String, dynamic>{},
            );
            if (product.isEmpty) {
              return Opacity(
                opacity: 0.6,
                child: Container(
                  key: ValueKey<String>(
                    'products-missing-selection-$productId',
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.link_off,
                        size: 20,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Producto no disponible',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'La referencia ya no existe o no está accesible.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      WebsiteEditorControlTarget(
                        targetKey: ValueKey<String>(
                          'products-remove-selection-$productId',
                        ),
                        semanticLabel: 'Quitar producto no disponible',
                        minimumWidth: true,
                        onTap: () => onRemove(productId),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final isActive = product['is_active'] == true;
            final isPublished = product['is_published'] == true;
            final stockQty = (product['inventory_qty'] as num?)?.toInt() ??
                (product['stock_quantity'] as num?)?.toInt() ??
                0;
            final isAvailable = isActive && isPublished && stockQty > 0;
            final statusText = !isActive
                ? 'Inactivo'
                : stockQty <= 0
                    ? 'Sin stock'
                    : !isPublished
                        ? 'No publicado'
                        : null;

            return Opacity(
              opacity: isAvailable ? 1.0 : 0.6,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(4),
                  border: !isAvailable
                      ? Border.all(color: Colors.red.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    // Product image
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3D3D),
                        borderRadius: BorderRadius.circular(4),
                        image: product['image_url'] != null
                            ? DecorationImage(
                                image: NetworkImage(product['image_url']),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: product['image_url'] == null
                          ? const Icon(Icons.image,
                              size: 16, color: Colors.white24)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product['name']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (statusText != null)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 8),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            product['sku']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    WebsiteEditorControlTarget(
                      targetKey: ValueKey<String>(
                        'products-remove-selection-$productId',
                      ),
                      semanticLabel:
                          'Quitar ${product['name']?.toString() ?? 'producto'}',
                      minimumWidth: true,
                      onTap: () => onRemove(productId),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            );
          })),
      ],
    );
  }

  Future<void> _showProductPicker(
    BuildContext context,
    WebsiteInlineManipulationLease? lease,
  ) async {
    if (lease == null) return;
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: _selectedProductIds,
      ),
    );
    if (selectedIds == null) {
      // Closing a dialog is a rebuild boundary, not a document mutation. It
      // rearms the button from the now-current page without refreshing this
      // old callback in place.
      if (mounted) setState(() {});
      return;
    }
    final normalized = WebsiteProductsBlockContract.selectionWrite(
      selectedIds,
    )[WebsiteProductsBlockContract.productIdsKey] as List<String>;
    if (!mounted) return;
    widget.provider.commitInlineMutation(
      lease,
      <String, Object?>{
        WebsiteProductsBlockContract.productIdsKey: normalized,
      },
    );
    if (mounted) setState(() {});
  }
}

// Shared by the Products inspector and Canvas product selectors because all
// editor-panel sources are parts of the same library.
class _SelectedProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onRemove;

  const _SelectedProductRow({
    required this.product,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = product['is_active'] == true;
    final isPublished = product['is_published'] == true;
    final stockQty = (product['inventory_qty'] as num?)?.toInt() ??
        (product['stock_quantity'] as num?)?.toInt() ??
        0;
    final isAvailable = isActive && isPublished && stockQty > 0;
    final statusText = !isActive
        ? 'Inactivo'
        : stockQty <= 0
            ? 'Sin stock'
            : !isPublished
                ? 'No publicado'
                : null;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(4),
          border: !isAvailable
              ? Border.all(color: Colors.red.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(4),
                image: product['image_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(product['image_url']),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: product['image_url'] == null
                  ? const Icon(Icons.image, size: 16, color: Colors.white24)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product['name']?.toString() ?? '',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (statusText != null)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            statusText,
                            style:
                                const TextStyle(color: Colors.red, fontSize: 8),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    product['sku']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: Colors.white38,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// Slider with a local preview value and one persisted command per gesture.
///
/// Flutter reports every pointer tick through `onChanged`; sending those ticks
/// to the document owner creates dozens of undo entries. The draft is visual
/// only and `onChangeEnd` is the transaction boundary.
class _InlineLeaseCommitSlider extends StatefulWidget {
  const _InlineLeaseCommitSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onLeaseStart,
    required this.onCommitted,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final WebsiteInlineManipulationLease? Function() onLeaseStart;
  final WebsiteInlineMutationResult Function(
    WebsiteInlineManipulationLease lease,
    double value,
  ) onCommitted;

  @override
  State<_InlineLeaseCommitSlider> createState() =>
      _InlineLeaseCommitSliderState();
}

class _InlineLeaseCommitSliderState extends State<_InlineLeaseCommitSlider> {
  late double _draft = widget.value;
  bool _isChanging = false;
  WebsiteInlineManipulationLease? _lease;

  @override
  void didUpdateWidget(covariant _InlineLeaseCommitSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isChanging && oldWidget.value != widget.value) {
      _draft = widget.value;
    }
  }

  void _start(double value) {
    final lease = widget.onLeaseStart();
    setState(() {
      _lease = lease;
      _draft = value;
      _isChanging = true;
    });
  }

  void _change(double value) => setState(() => _draft = value);

  void _commit(double value) {
    final lease = _lease;
    final result = lease == null || value == widget.value
        ? WebsiteInlineMutationResult.unchanged
        : widget.onCommitted(lease, value);
    setState(() {
      _lease = null;
      _draft = result.changed ? value : widget.value;
      _isChanging = false;
    });
  }

  void _cancel() {
    if (!_isChanging && _lease == null) return;
    setState(() {
      // A captured discrete lease owns no provider session. Dropping it is a
      // true cancel: zero writes, zero notification and zero history.
      _lease = null;
      _draft = widget.value;
      _isChanging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _EditorFieldLabel(
                label: widget.label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _draft.toInt().toString(),
                style: const TextStyle(
                  color: Color(0xFF00A09D),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        Semantics(
          label: widget.label,
          value: _draft.toInt().toString(),
          child: Listener(
            onPointerCancel: (_) => _cancel(),
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF00A09D),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                thumbColor: const Color(0xFF00A09D),
                overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _draft,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                semanticFormatterCallback: (value) => value.toInt().toString(),
                onChangeStart: _start,
                onChanged: _change,
                onChangeEnd: _commit,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Product picker dialog
class _ProductPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableProducts;
  final List<String> selectedIds;
  final ValueChanged<List<String>>? onConfirm;

  const _ProductPickerDialog({
    required this.availableProducts,
    required this.selectedIds,
    this.onConfirm,
  });

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late Set<String> _selected;
  String _searchQuery = '';
  bool _filterInStock = false;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var list = widget.availableProducts;

    // Filter by stock
    if (_filterInStock) {
      list = list.where((p) {
        final stockQty = (p['inventory_qty'] as num?)?.toInt() ??
            (p['stock_quantity'] as num?)?.toInt() ??
            0;
        return stockQty > 0;
      }).toList();
    }

    if (_searchQuery.isEmpty) return list;

    final query = _searchQuery.toLowerCase();
    return list.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final sku = (p['sku']?.toString() ?? '').toLowerCase();
      // Allow searching by exact ID too
      final id = (p['id']?.toString() ?? '').toLowerCase();
      return name.contains(query) || sku.contains(query) || id == query;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return WebsiteEditorControlDensityScope.resolved(
      context: context,
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          width: 420,
          height: 560,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Seleccionar productos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              // Search field
              TextField(
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o SKU...',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white38, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF2D2D2D),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 12),

              // Filters and counts wrap instead of overflowing the narrow sheet.
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_selected.length} seleccionados',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  WebsiteEditorControlTarget(
                    targetKey: const Key('products-stock-filter'),
                    semanticLabel: 'Solo productos con stock',
                    selected: _filterInStock,
                    minimumWidth: true,
                    onTap: () =>
                        setState(() => _filterInStock = !_filterInStock),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _filterInStock
                            ? const Color(0xFF00A09D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _filterInStock
                              ? const Color(0xFF00A09D)
                              : Colors.white24,
                        ),
                      ),
                      child: Text(
                        'Solo con stock',
                        style: TextStyle(
                            color:
                                _filterInStock ? Colors.white : Colors.white54,
                            fontSize: 11,
                            fontWeight: _filterInStock
                                ? FontWeight.w600
                                : FontWeight.normal),
                      ),
                    ),
                  ),
                  Text(
                    '${_filteredProducts.length} productos',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    final productId = product['id'].toString();
                    final isSelected = _selected.contains(productId);
                    final isPublished = product['is_published'] == true;
                    final stockQty =
                        (product['inventory_qty'] as num?)?.toInt() ??
                            (product['stock_quantity'] as num?)?.toInt() ??
                            0;
                    final isAvailable = isPublished && stockQty > 0;

                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label:
                          'Seleccionar ${product['name']?.toString() ?? 'producto'}',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(productId);
                            } else {
                              _selected.add(productId);
                            }
                          });
                        },
                        child: Opacity(
                          opacity: isAvailable ? 1.0 : 0.5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF00A09D)
                                      .withValues(alpha: 0.2)
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                    color:
                                        Colors.white.withValues(alpha: 0.05)),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Checkbox
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF00A09D)
                                        : const Color(0xFF2D2D2D),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF00A09D)
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          size: 14, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                // Image
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3D3D3D),
                                    borderRadius: BorderRadius.circular(4),
                                    image: product['image_url'] != null
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                product['image_url']),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: product['image_url'] == null
                                      ? const Icon(Icons.image,
                                          size: 20, color: Colors.white24)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              product['name']?.toString() ?? '',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isAvailable)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  left: 4),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.red
                                                    .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                              child: Text(
                                                stockQty <= 0
                                                    ? 'Sin stock'
                                                    : 'No publicado',
                                                style: const TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 9),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Text(
                                        'SKU: ${product['sku'] ?? '-'} · \$${NumberFormat('#,###', 'es_CL').format(product['price'] ?? 0)}',
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11),
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
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.white54),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final selectedIds = _selected.toList();
                      widget.onConfirm?.call(selectedIds);
                      Navigator.pop(context, selectedIds);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A09D),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirmar'),
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
