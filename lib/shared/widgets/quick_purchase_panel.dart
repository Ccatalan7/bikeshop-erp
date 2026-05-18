import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/purchases/models/smart_purchase_list_item.dart';
import '../../modules/purchases/services/smart_purchase_list_service.dart';
import '../models/product.dart';
import '../services/inventory_service.dart';

class QuickPurchasePanel extends StatefulWidget {
  const QuickPurchasePanel({super.key});

  @override
  State<QuickPurchasePanel> createState() => _QuickPurchasePanelState();
}

class _QuickPurchasePanelState extends State<QuickPurchasePanel> {
  final _productController = TextEditingController();
  final _notesController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  SmartPurchaseListItem? _editingItem;
  final _editQuantityController = TextEditingController();
  final _editNotesController = TextEditingController();

  Product? _selectedProduct;
  List<Product> _searchResults = const [];
  Timer? _searchDebounce;
  String _editStatus = 'pending';
  bool _showAll = false;
  bool _isSaving = false;
  bool _isSavingEdit = false;
  bool _isSearching = false;
  bool _didLoad = false;

  @override
  void initState() {
    super.initState();
    _productController.addListener(_handleProductChanged);
    _quantityController.addListener(_handleComposerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadItems();
      }
    });
  }

  @override
  void dispose() {
    _productController.removeListener(_handleProductChanged);
    _quantityController.removeListener(_handleComposerChanged);
    _searchDebounce?.cancel();
    _productController.dispose();
    _notesController.dispose();
    _quantityController.dispose();
    _editQuantityController.dispose();
    _editNotesController.dispose();
    super.dispose();
  }

  void _handleProductChanged() {
    final text = _productController.text.trim();

    if (_selectedProduct != null && text != _selectedProduct!.name) {
      _selectedProduct = null;
    }

    _searchDebounce?.cancel();

    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
      }
      return;
    }

    if (_selectedProduct != null && text == _selectedProduct!.name) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
      }
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await context
            .read<InventoryService>()
            .searchProducts(text, limit: 8);

        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _searchResults = const [];
          _isSearching = false;
        });
      }
    });
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectProduct(Product product) {
    _searchDebounce?.cancel();
    setState(() {
      _selectedProduct = product;
      _productController.text = product.name;
      _productController.selection = TextSelection.collapsed(
        offset: _productController.text.length,
      );
      _searchResults = const [];
      _isSearching = false;
    });
  }

  void _resetComposer() {
    _searchDebounce?.cancel();
    setState(() {
      _selectedProduct = null;
      _searchResults = const [];
      _isSearching = false;
      _productController.clear();
      _notesController.clear();
      _quantityController.text = '1';
    });
  }

  void _clearProductInput() {
    _searchDebounce?.cancel();
    setState(() {
      _selectedProduct = null;
      _searchResults = const [];
      _isSearching = false;
      _productController.clear();
    });
  }

  Future<void> _loadItems() async {
    await context.read<SmartPurchaseListService>().loadItems(
          statusFilter: _showAll ? 'all' : 'pending',
        );
  }

  bool get _canSave {
    final name = _productController.text.trim();
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    return name.isNotEmpty && quantity > 0 && !_isSaving;
  }

  Future<void> _save() async {
    final name = _productController.text.trim();
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (name.isEmpty || quantity <= 0) return;

    setState(() => _isSaving = true);
    try {
      await context.read<SmartPurchaseListService>().addItem(
            product: _selectedProduct,
            productId: _selectedProduct?.id,
            productName: _selectedProduct?.name ?? name,
            productSku: _selectedProduct?.sku,
            supplierId: _selectedProduct?.supplierId,
            supplierName: _selectedProduct?.supplierName,
            quantity: quantity,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (!mounted) return;
      _resetComposer();
      if (!mounted) return;
      setState(() => _isSaving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar compra: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openEdit(SmartPurchaseListItem item) {
    setState(() {
      _editingItem = item;
      _editStatus = item.status;
      _editQuantityController.text = item.quantityToBuy.toString();
      _editNotesController.text = item.notes ?? '';
      _isSavingEdit = false;
    });
  }

  Future<void> _saveEdit() async {
    final item = _editingItem;
    if (item == null) return;
    final quantity = int.tryParse(_editQuantityController.text.trim()) ?? 0;
    if (quantity <= 0) return;

    setState(() => _isSavingEdit = true);
    try {
      await context.read<SmartPurchaseListService>().updateItem(item.id, {
        'suggested_quantity': quantity,
        'status': _editStatus,
        'notes': _editNotesController.text.trim().isEmpty
            ? null
            : _editNotesController.text.trim(),
      });

      if (!mounted) return;
      setState(() {
        _editingItem = null;
        _isSavingEdit = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar cambios: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteEditingItem() async {
    final item = _editingItem;
    if (item == null) return;
    setState(() => _editingItem = null);
    await context.read<SmartPurchaseListService>().deleteItem(item.id);
  }

  List<_PurchaseSection> _buildSections(List<SmartPurchaseListItem> items) {
    if (_showAll) {
      final statuses = <String, String>{
        'pending': 'Pendientes',
        'ordered': 'Pedidos',
        'received': 'Recibidos',
        'ignored': 'Ignorados',
        'cancelled': 'Cancelados',
      };
      final sections = <_PurchaseSection>[];
      for (final entry in statuses.entries) {
        final sectionItems =
            items.where((item) => item.status == entry.key).toList();
        if (sectionItems.isNotEmpty) {
          sections.add(_PurchaseSection(entry.value, sectionItems));
        }
      }
      return sections;
    }

    final urgent = items.where((item) => item.isUrgent).toList();
    final regular = items.where((item) => !item.isUrgent).toList();
    final sections = <_PurchaseSection>[];
    if (urgent.isNotEmpty) {
      sections.add(_PurchaseSection('Urgentes', urgent));
    }
    if (regular.isNotEmpty) {
      sections.add(_PurchaseSection('Pendientes', regular));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: Colors.transparent,
      child: _editingItem != null
          ? _buildEditView(theme, isDark)
          : Column(
              children: [
                _buildFilterTabs(theme, isDark),
                Expanded(
                  child: Consumer<SmartPurchaseListService>(
                    builder: (context, service, _) {
                      if (service.isLoading && service.items.isEmpty) {
                        return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2));
                      }

                      final items = service.getFilteredItems(
                        statusFilter: _showAll ? 'all' : 'pending',
                      );
                      final sections = _buildSections(items);

                      if (sections.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.15),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _showAll
                                    ? 'No hay compras cargadas'
                                    : 'No hay compras pendientes',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final dividerColor = isDark
                          ? const Color(0xFF2E2E2E)
                          : const Color(0xFFEEEEEE);

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: sections.fold<int>(0,
                            (sum, section) => sum + 1 + section.items.length),
                        itemBuilder: (context, index) {
                          var cursor = 0;
                          for (final section in sections) {
                            if (index == cursor) {
                              return _buildSectionHeader(
                                  section.title, section.items.length, theme);
                            }
                            cursor += 1;
                            final itemIndex = index - cursor;
                            if (itemIndex >= 0 &&
                                itemIndex < section.items.length) {
                              final item = section.items[itemIndex];
                              final showDivider = itemIndex > 0;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showDivider)
                                    Divider(height: 1, color: dividerColor),
                                  _buildPurchaseRow(item, theme),
                                ],
                              );
                            }
                            cursor += section.items.length;
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  ),
                ),
                _buildQuickAddForm(theme, isDark),
              ],
            ),
    );
  }

  Widget _buildFilterTabs(ThemeData theme, bool isDark) {
    final borderCol =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE8EAED);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    Widget tab(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? activeColor : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? activeColor : inactiveColor,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderCol)),
      ),
      child: Row(
        children: [
          tab('Pendientes', !_showAll, () {
            if (_showAll) {
              setState(() => _showAll = false);
              _loadItems();
            }
          }),
          tab('Todas', _showAll, () {
            if (!_showAll) {
              setState(() => _showAll = true);
              _loadItems();
            }
          }),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label, int count, ThemeData theme) {
    final isUrgent = label == 'Urgentes';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isUrgent
                  ? Colors.red.withValues(alpha: 0.85)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isUrgent
                  ? Colors.red.withValues(alpha: 0.12)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isUrgent
                    ? Colors.red.withValues(alpha: 0.85)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Divider(
              height: 1,
              color: theme.dividerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseRow(SmartPurchaseListItem item, ThemeData theme) {
    final statusColor = _statusColor(item.status);
    final isReceived = item.status == 'received';
    final isOrdered = item.status == 'ordered';

    return Opacity(
      opacity: item.status == 'cancelled' ? 0.5 : 1,
      child: InkWell(
        onTap: () => _openEdit(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 1.5),
                    color: isReceived ? statusColor : Colors.transparent,
                  ),
                  child: isReceived
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : isOrdered
                          ? Icon(Icons.local_shipping_outlined,
                              size: 10, color: statusColor)
                          : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _miniMeta(theme, 'Cant. ${item.quantityToBuy}'),
                        if (item.productSku != null &&
                            item.productSku!.isNotEmpty)
                          _miniMeta(theme, item.productSku!),
                        if (item.supplierName != null &&
                            item.supplierName!.isNotEmpty)
                          _miniMeta(theme, item.supplierName!),
                        if (item.currentStock > 0)
                          _miniMeta(theme, 'Stock ${item.currentStock}'),
                        if (item.linkedJobNumber != null &&
                            item.linkedJobNumber!.isNotEmpty)
                          _miniMeta(theme, item.linkedJobNumber!),
                      ],
                    ),
                    if (item.notes != null &&
                        item.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMeta(ThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
      ),
    );
  }

  Widget _buildEditView(ThemeData theme, bool isDark) {
    final item = _editingItem!;
    final borderCol =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      letterSpacing: 0.6,
    );

    InputDecoration fieldDecoration({String? hint}) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: borderCol),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: borderCol),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  size: 17,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Volver',
                onPressed: () => setState(() => _editingItem = null),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 17,
                  color: Colors.red.withValues(alpha: 0.65),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Eliminar',
                onPressed: _deleteEditingItem,
              ),
            ],
          ),
        ),
        Divider(color: borderCol, height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CANTIDAD', style: labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _editQuantityController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurface),
                  decoration: fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('ESTADO', style: labelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: _editStatus,
                  isDense: true,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurface),
                  decoration: fieldDecoration(),
                  items: const [
                    DropdownMenuItem(
                        value: 'pending', child: Text('Pendiente')),
                    DropdownMenuItem(value: 'ordered', child: Text('Pedido')),
                    DropdownMenuItem(
                        value: 'received', child: Text('Recibido')),
                    DropdownMenuItem(value: 'ignored', child: Text('Ignorado')),
                    DropdownMenuItem(
                        value: 'cancelled', child: Text('Cancelado')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _editStatus = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text('NOTAS', style: labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _editNotesController,
                  maxLines: 4,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurface),
                  decoration:
                      fieldDecoration(hint: 'Agregar detalle de compra...'),
                ),
                const SizedBox(height: 12),
                Text('META', style: labelStyle),
                const SizedBox(height: 6),
                Text(
                  [
                    if (item.supplierName != null &&
                        item.supplierName!.isNotEmpty)
                      item.supplierName!,
                    if (item.productSku != null && item.productSku!.isNotEmpty)
                      item.productSku!,
                    if (item.linkedJobNumber != null &&
                        item.linkedJobNumber!.isNotEmpty)
                      item.linkedJobNumber!,
                    DateFormat('dd/MM/yyyy').format(item.addedDate),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _isSavingEdit ? null : _saveEdit,
              child: Text(
                _isSavingEdit ? 'Guardando...' : 'Guardar',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddForm(ThemeData theme, bool isDark) {
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);
    final hasTypedQuery = _productController.text.trim().isNotEmpty;
    final showSearchCard = hasTypedQuery && _selectedProduct == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _productController,
            autofocus: false,
            decoration: InputDecoration(
              labelText: 'Producto o compra manual',
              hintText: 'Busca producto o escribe una compra manual...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: hasTypedQuery
                  ? IconButton(
                      onPressed: _clearProductInput,
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.close, size: 18),
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: theme.colorScheme.primary, width: 1.2),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
            ),
            style: const TextStyle(fontSize: 12),
          ),
          if (showSearchCard) ...[
            const SizedBox(height: 6),
            _buildSearchResultsCard(theme, isDark, borderColor),
          ] else if (_selectedProduct != null) ...[
            const SizedBox(height: 6),
            _buildSelectedProductCard(theme, isDark),
          ],
          const SizedBox(height: 6),
          TextField(
            controller: _notesController,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Descripción (opcional)...',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 76,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: 'Cant.',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 6),
              if (_selectedProduct != null)
                Expanded(
                  child: Text(
                    [
                      if (_selectedProduct!.supplierName?.isNotEmpty == true)
                        _selectedProduct!.supplierName!,
                      'Stock ${_selectedProduct!.stockQuantity}',
                      'Costo ${_selectedProduct!.cost.toStringAsFixed(0)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Puedes agregar compras manuales sin producto de catálogo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _canSave ? _save : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: Text(
                _isSaving ? 'Guardando...' : 'Agregar Compra',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsCard(
      ThemeData theme, bool isDark, Color borderColor) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232323) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _isSearching
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : _searchResults.isEmpty
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sin productos coincidentes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Si quieres, guarda el texto tal como está y se agrega como compra manual.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: borderColor.withValues(alpha: 0.7),
                  ),
                  itemBuilder: (context, index) {
                    final product = _searchResults[index];
                    return _buildSearchResultRow(product, theme);
                  },
                ),
    );
  }

  Widget _buildSearchResultRow(Product product, ThemeData theme) {
    return InkWell(
      onTap: () => _selectProduct(product),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (product.sku.isNotEmpty) _miniMeta(theme, product.sku),
                      if (product.supplierName?.isNotEmpty == true)
                        _miniMeta(theme, product.supplierName!),
                      _miniMeta(theme, 'Stock ${product.stockQuantity}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Costo ${product.cost.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedProductCard(ThemeData theme, bool isDark) {
    final product = _selectedProduct!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (product.sku.isNotEmpty) _miniMeta(theme, product.sku),
                    if (product.supplierName?.isNotEmpty == true)
                      _miniMeta(theme, product.supplierName!),
                    _miniMeta(theme, 'Stock ${product.stockQuantity}'),
                    _miniMeta(
                        theme, 'Costo ${product.cost.toStringAsFixed(0)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              _clearProductInput();
            },
            tooltip: 'Quitar producto',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ordered':
        return Colors.orange;
      case 'received':
        return Colors.green;
      case 'ignored':
        return Colors.grey;
      case 'cancelled':
        return Colors.red.shade300;
      default:
        return Colors.blue;
    }
  }
}

class _PurchaseSection {
  final String title;
  final List<SmartPurchaseListItem> items;

  const _PurchaseSection(this.title, this.items);
}
