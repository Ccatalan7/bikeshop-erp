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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;

      // Load ALL active products (so user can see/deselect old selections)
      // We'll mark unavailable ones in the picker UI
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
          .eq('is_active', true)
          .order('name', ascending: true)
          .limit(2000);

      var allProducts = List<Map<String, dynamic>>.from(productsResponse);

      // Also load selected products that might be inactive (so we can display/deselect them)
      final selectedIds = _selectedProductIds;
      if (selectedIds.isNotEmpty) {
        final selectedResponse = await supabase
            .from('products')
            .select(
                'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
            .inFilter('id', selectedIds);

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
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _availableProducts = allProducts;
          _availableCategories =
              List<Map<String, dynamic>>.from(categoriesResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  /// Binds one presentation property of this block through the canonical
  /// owner, using the registry schema instead of a hand-written key.
  ///
  /// The catalogue source, category, selected ids, `maxProducts` and the "view
  /// all" copy/destination are business identity: they keep writing shared
  /// through [_updateField] and the existing pickers, untouched.
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
    return WebsiteResponsiveScalarBinding<T>.forField(
      provider: widget.provider,
      blockId: widget.blockId,
      field: field,
      owner: const WebsiteResponsiveRootField(),
      decode: decode,
      hostClass: WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
          WebsiteAuthoringHostClass.desktop,
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
    return switch (widget.provider.previewViewport) {
      WebsiteViewport.desktop => null,
      WebsiteViewport.mobile =>
        'En móvil los productos se muestran en un carrusel automático, '
            'de a uno. Este número sólo aplica en escritorio.',
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

  List<String> get _selectedProductIds {
    final raw = widget.data['selectedProducts'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  String get _productSource =>
      widget.data['productSource']?.toString() ?? 'featured';
  String? get _selectedCategoryId => widget.data['categoryId']?.toString();
  int get _itemsPerRow => (widget.data['itemsPerRow'] as num?)?.toInt() ?? 3;
  int get _maxProducts => (widget.data['maxProducts'] as num?)?.toInt() ?? 8;

  @override
  Widget build(BuildContext context) {
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
              onChanged: (v) => _updateField('title', v),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Subtítulo',
              value: widget.data['subtitle']?.toString() ?? '',
              onChanged: (v) => _updateField('subtitle', v),
            ),

            const SizedBox(height: 20),
            const _SectionHeader('Fuente de productos'),
            const SizedBox(height: 12),

            // Product source selector
            _buildSourceSelector(),

            const SizedBox(height: 16),

            // Conditional content based on source
            if (_productSource == 'category') _buildCategorySelector(),
            if (_productSource == 'manual') _buildProductSelector(),
          ],
        ),
        _CollapsibleSection(
          title: 'Diseño de productos',
          icon: Icons.grid_view_rounded,
          initiallyExpanded: false,
          children: [
            _EditorDropdown(
              label: 'Diseño',
              value: widget.data['layout']?.toString() ?? 'grid',
              options: const [
                ('grid', 'Cuadrícula'),
                ('carousel', 'Carrusel'),
              ],
              onChanged: (v) => _updateField('layout', v),
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
                return Row(
                  children: [2, 3, 4].map((count) {
                    final isSelected = selectedCount == count;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => binding.write(count),
                        child: Container(
                          width: 44,
                          height: 36,
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
                          child: Center(
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 16),
            _EditorSlider(
              label: 'Máximo de productos',
              value: _maxProducts.toDouble(),
              min: 4,
              max: 16,
              divisions: 6,
              onChanged: (v) => _updateField('maxProducts', v.toInt()),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Información visible',
          icon: Icons.visibility_outlined,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Mostrar precios',
              value: widget.data['showPrice'] ?? true,
              onChanged: (v) => _updateField('showPrice', v),
            ),
            const SizedBox(height: 8),
            _mountPresentationField<bool>(
              _presentationBinding<bool>(
                'showViewAll',
                WebsiteResponsiveScalarBinding.decodeBoolean,
              ),
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? true,
                onChanged: binding.write,
              ),
            ),
            const SizedBox(height: 8),
            _EditorToggle(
              label: 'Mostrar SKU',
              value: widget.data['showSku'] ?? false,
              onChanged: (v) => _updateField('showSku', v),
            ),
            const SizedBox(height: 8),
            _EditorToggle(
              label: 'Mostrar marca',
              value: widget.data['showBrand'] ?? false,
              onChanged: (v) => _updateField('showBrand', v),
            ),
          ],
        ),
        if (widget.data['showViewAll'] != false)
          _CollapsibleSection(
            title: 'Acción “Ver todos”',
            icon: Icons.call_to_action_outlined,
            initiallyExpanded: false,
            children: [
              WebsiteActionEditor(
                title: 'Botón Ver todos',
                showVariant: true,
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
                  widget.provider.updateBlockDataMultiple(
                    widget.blockId,
                    {
                      'viewAllText': action.label,
                      'viewAllLink': action.href,
                      'actionVariant': action.variant.storageValue,
                      'actions': WebsiteActionValue.mergePrimary(
                        widget.data['actions'],
                        action,
                      ),
                    },
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSourceSelector() {
    final sources = [
      {'id': 'featured', 'label': 'Destacados', 'icon': Icons.star},
      {'id': 'category', 'label': 'Categoría', 'icon': Icons.category},
      {'id': 'manual', 'label': 'Selección manual', 'icon': Icons.checklist},
      {'id': 'newest', 'label': 'Más recientes', 'icon': Icons.schedule},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources.map((source) {
        final isSelected = _productSource == source['id'];
        return GestureDetector(
          onTap: () => _updateField('productSource', source['id']),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00A09D)
                  : const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  source['icon'] as IconData,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  source['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategorySelector() {
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
                onPressed: () => _updateField('categoryId', catId),
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

              return InkWell(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  Widget _buildProductSelector() {
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
            Text(
              'Productos seleccionados (${_selectedProductIds.length})',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showProductPicker(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00A09D),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Agregar', style: TextStyle(fontSize: 12)),
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
            if (product.isEmpty) return const SizedBox.shrink();

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
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final newList = List<String>.from(_selectedProductIds)
                          ..remove(productId);
                        _updateField('selectedProducts', newList);
                      },
                    ),
                  ],
                ),
              ),
            );
          })),
      ],
    );
  }

  void _showProductPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: _selectedProductIds,
        onConfirm: (selectedIds) {
          _updateField('selectedProducts', selectedIds);
        },
      ),
    );
  }
}

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

/// Product picker dialog
class _ProductPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableProducts;
  final List<String> selectedIds;
  final Function(List<String>) onConfirm;

  const _ProductPickerDialog({
    required this.availableProducts,
    required this.selectedIds,
    required this.onConfirm,
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
    return Dialog(
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
                const Text(
                  'Seleccionar productos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
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
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
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

            // Filters and counts
            Row(
              children: [
                Text(
                  '${_selected.length} seleccionados',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Spacer(),

                // Minimalistic filter
                InkWell(
                  onTap: () => setState(() => _filterInStock = !_filterInStock),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          color: _filterInStock ? Colors.white : Colors.white54,
                          fontSize: 11,
                          fontWeight: _filterInStock
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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

                  return InkWell(
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
                              ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05)),
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
                                        image:
                                            NetworkImage(product['image_url']),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                          margin:
                                              const EdgeInsets.only(left: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
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
                                                color: Colors.red, fontSize: 9),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    'SKU: ${product['sku'] ?? '-'} · \$${NumberFormat('#,###', 'es_CL').format(product['price'] ?? 0)}',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onConfirm(_selected.toList());
                    Navigator.pop(context);
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
    );
  }
}
