import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/services/payment_method_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_payment_detail_view.dart';

class PurchasePaymentsListPage extends StatefulWidget {
  const PurchasePaymentsListPage({super.key, this.highlightPaymentId});

  final String? highlightPaymentId;

  @override
  State<PurchasePaymentsListPage> createState() =>
      _PurchasePaymentsListPageState();
}

class _PurchasePaymentsListPageState extends State<PurchasePaymentsListPage> {
  static const double _mobileBreakpoint = 700;
  static const double _desktopSplitBreakpoint = 900;
  static const double _defaultListPaneWidth = 600;
  static const double _minimumListPaneWidth = 400;
  static const double _minimumDetailPaneWidth = 430;
  static const double _maximumListPaneWidth = 900;
  static const double _tableHeaderHeight = 38;
  static const double _tableRowHeight = 38;
  static const double _paymentCardExtent = 106;

  static const String _listPaneWidthPreferenceKey =
      'purchase_payments_list_pane_width_v1';
  static const String _columnOrderPreferenceKey =
      'purchase_payments_column_order_v1';
  static const String _visibleColumnsPreferenceKey =
      'purchase_payments_visible_columns_v1';
  static const String _columnWidthsPreferenceKey =
      'purchase_payments_column_widths_v1';
  static const String _allFilterValue = '__all__';

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _keyboardFocusNode =
      FocusNode(debugLabel: 'Purchase payments master list');
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _bodyHorizontalController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _cardScrollController = ScrollController();

  List<PurchasePayment> _payments = const [];
  List<PurchaseInvoice> _invoices = const [];
  List<_PurchasePaymentColumnConfig> _columns = _defaultColumns();
  List<_PurchasePaymentRow> _lastVisibleRows = const [];
  String _searchTerm = '';
  String _sortColumn = 'date';
  bool _sortAscending = false;
  _PurchasePaymentDatePreset _datePreset = _PurchasePaymentDatePreset.all;
  String _selectedMethodId = _allFilterValue;
  String _selectedSupplierId = _allFilterValue;
  String? _selectedPaymentId;
  String? _draggingColumnId;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isDesktopLayout = false;
  bool _syncingHorizontalScroll = false;
  String? _loadError;
  double _listPaneWidth = _defaultListPaneWidth;

  @override
  void initState() {
    super.initState();
    _headerHorizontalController.addListener(_syncHeaderToBody);
    _bodyHorizontalController.addListener(_syncBodyToHeader);
    unawaited(_loadPreferences());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didUpdateWidget(covariant PurchasePaymentsListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightPaymentId == widget.highlightPaymentId) return;
    final paymentId = widget.highlightPaymentId?.trim();
    if (paymentId == null || paymentId.isEmpty) return;
    setState(() => _selectedPaymentId = paymentId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final index = _lastVisibleRows.indexWhere((row) => row.id == paymentId);
      if (index >= 0) _scrollRowIntoView(index);
    });
  }

  @override
  void dispose() {
    _headerHorizontalController
      ..removeListener(_syncHeaderToBody)
      ..dispose();
    _bodyHorizontalController
      ..removeListener(_syncBodyToHeader)
      ..dispose();
    _verticalScrollController.dispose();
    _cardScrollController.dispose();
    _searchController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = true}) async {
    if (_isRefreshing) return;
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _loadError = null;
      });
    }

    final purchaseService = context.read<PurchaseService>();
    final paymentMethodService = context.read<PaymentMethodService>();

    try {
      final results = await Future.wait<dynamic>([
        purchaseService.getPurchasePayments(forceRefresh: forceRefresh),
        purchaseService.getPurchaseInvoicesForList(
          forceRefresh: forceRefresh,
        ),
        paymentMethodService.loadPaymentMethods(forceRefresh: forceRefresh),
      ]);
      final payments = results[0] as List<PurchasePayment>;
      final invoices = results[1] as List<PurchaseInvoice>;
      await paymentMethodService.loadReferencedPaymentMethods(
        payments.map((payment) => payment.paymentMethodId),
      );

      if (!mounted) return;
      setState(() {
        _payments = List<PurchasePayment>.unmodifiable(payments);
        _invoices = List<PurchaseInvoice>.unmodifiable(invoices);
        _isLoading = false;
        _isRefreshing = false;
        final initialId = widget.highlightPaymentId?.trim();
        if (_selectedPaymentId == null &&
            initialId != null &&
            initialId.isNotEmpty) {
          _selectedPaymentId = initialId;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final selectedId = _selectedPaymentId;
        if (selectedId == null) return;
        final index =
            _lastVisibleRows.indexWhere((row) => row.id == selectedId);
        if (index >= 0) _scrollRowIntoView(index);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError =
            'No se pudo cargar el registro de pagos de compras: $error';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final savedOrder = preferences.getStringList(_columnOrderPreferenceKey);
    final savedVisible =
        preferences.getStringList(_visibleColumnsPreferenceKey);
    final savedWidths = preferences.getStringList(_columnWidthsPreferenceKey);
    final savedPaneWidth = preferences.getDouble(_listPaneWidthPreferenceKey);

    final columns = _defaultColumns();
    final columnsById = {for (final column in columns) column.id: column};

    if (savedWidths != null) {
      for (final entry in savedWidths) {
        final separator = entry.lastIndexOf(':');
        if (separator <= 0) continue;
        final id = entry.substring(0, separator);
        final width = double.tryParse(entry.substring(separator + 1));
        final column = columnsById[id];
        if (width == null || column == null) continue;
        column.width = width.clamp(column.minWidth, column.maxWidth).toDouble();
      }
    }

    if (savedVisible != null) {
      final visibleIds = savedVisible.toSet();
      for (final column in columns) {
        column.visible = column.alwaysVisible || visibleIds.contains(column.id);
      }
    }

    final ordered = <_PurchasePaymentColumnConfig>[];
    if (savedOrder != null) {
      for (final id in savedOrder) {
        final column = columnsById.remove(id);
        if (column != null) ordered.add(column);
      }
    }
    ordered.addAll(
      columns.where((column) => columnsById.containsKey(column.id)),
    );

    if (!mounted) return;
    setState(() {
      _columns = ordered;
      if (savedPaneWidth != null) {
        _listPaneWidth = savedPaneWidth
            .clamp(_minimumListPaneWidth, _maximumListPaneWidth)
            .toDouble();
      }
    });
  }

  Future<void> _saveColumnPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(
        _columnOrderPreferenceKey,
        _columns.map((column) => column.id).toList(growable: false),
      ),
      preferences.setStringList(
        _visibleColumnsPreferenceKey,
        _columns
            .where((column) => column.visible)
            .map((column) => column.id)
            .toList(growable: false),
      ),
      preferences.setStringList(
        _columnWidthsPreferenceKey,
        _columns
            .map(
              (column) => '${column.id}:${column.width.toStringAsFixed(1)}',
            )
            .toList(growable: false),
      ),
    ]);
  }

  Future<void> _saveListPaneWidth() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(
      _listPaneWidthPreferenceKey,
      _listPaneWidth,
    );
  }

  void _syncHeaderToBody() {
    _syncHorizontalControllers(
      source: _headerHorizontalController,
      target: _bodyHorizontalController,
    );
  }

  void _syncBodyToHeader() {
    _syncHorizontalControllers(
      source: _bodyHorizontalController,
      target: _headerHorizontalController,
    );
  }

  void _syncHorizontalControllers({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingHorizontalScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    final offset = source.offset
        .clamp(
          target.position.minScrollExtent,
          target.position.maxScrollExtent,
        )
        .toDouble();
    if ((target.offset - offset).abs() < 0.5) return;
    _syncingHorizontalScroll = true;
    target.jumpTo(offset);
    _syncingHorizontalScroll = false;
  }

  List<_PurchasePaymentRow> _buildJoinedRows(
    PaymentMethodService paymentMethodService,
  ) {
    final invoicesById = <String, PurchaseInvoice>{
      for (final invoice in _invoices)
        if (invoice.id != null) invoice.id!: invoice,
    };
    return _payments.map((payment) {
      final invoice = invoicesById[payment.invoiceId];
      final method =
          paymentMethodService.getPaymentMethodById(payment.paymentMethodId);
      return _PurchasePaymentRow(
        payment: payment,
        invoice: invoice,
        code: _paymentNumber(payment),
        paymentMethodName: method?.name ?? 'Método no disponible',
        paymentMethodCode: method?.code ?? '',
      );
    }).toList(growable: false);
  }

  List<_PurchasePaymentRow> _filteredAndSortedRows(
    List<_PurchasePaymentRow> rows,
  ) {
    final normalizedQuery = _normalizeSearch(_searchTerm);
    final filtered = rows.where((row) {
      if (!_matchesDatePreset(row.payment.date, _datePreset)) return false;
      if (_selectedMethodId != _allFilterValue &&
          row.payment.paymentMethodId != _selectedMethodId) {
        return false;
      }
      if (_selectedSupplierId != _allFilterValue &&
          row.supplierKey != _selectedSupplierId) {
        return false;
      }
      return _matchesSmartSearch(row, normalizedQuery);
    }).toList();

    filtered.sort((left, right) {
      final comparison = switch (_sortColumn) {
        'code' => _compareText(left.code, right.code),
        'date' => left.payment.date.compareTo(right.payment.date),
        'supplier' => _compareText(left.supplierName, right.supplierName),
        'invoice' => _compareText(left.invoiceNumber, right.invoiceNumber),
        'method' => _compareText(
            left.paymentMethodName,
            right.paymentMethodName,
          ),
        'reference' => _compareText(
            left.payment.reference ?? '',
            right.payment.reference ?? '',
          ),
        'amount' => left.payment.amount.compareTo(right.payment.amount),
        'notes' => _compareText(
            left.payment.notes ?? '',
            right.payment.notes ?? '',
          ),
        _ => left.payment.date.compareTo(right.payment.date),
      };
      return _sortAscending ? comparison : -comparison;
    });
    return filtered;
  }

  int _compareText(String left, String right) =>
      _normalizeSearch(left).compareTo(_normalizeSearch(right));

  bool _matchesSmartSearch(
    _PurchasePaymentRow row,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) return true;
    final values = <Object?>[
      row.code,
      row.payment.id,
      row.invoiceNumber,
      row.invoice?.supplierInvoiceNumber,
      row.supplierName,
      row.supplierRut,
      row.paymentMethodName,
      row.paymentMethodCode,
      row.payment.reference,
      row.payment.notes,
      row.payment.amount.toStringAsFixed(0),
      ChileanUtils.formatCurrency(row.payment.amount),
      ChileanUtils.formatDate(row.payment.date),
      ChileanUtils.formatDateTime(row.payment.date),
    ];
    final normalizedValues = values
        .where((value) => value != null)
        .map((value) => _normalizeSearch(value.toString()))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final compactDigits = values
        .where((value) => value != null)
        .map(
          (value) => value.toString().replaceAll(RegExp(r'[^0-9]'), ''),
        )
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    return normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .every((token) {
      if (normalizedValues.any((value) => value.contains(token))) {
        return true;
      }
      if (!RegExp(r'^\d+$').hasMatch(token)) return false;
      return compactDigits.any((value) => value.contains(token));
    });
  }

  String _normalizeSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâãåā]'), 'a')
        .replaceAll(RegExp(r'[éèëêē]'), 'e')
        .replaceAll(RegExp(r'[íìïîī]'), 'i')
        .replaceAll(RegExp(r'[óòöôõøō]'), 'o')
        .replaceAll(RegExp(r'[úùüûū]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesDatePreset(
    DateTime value,
    _PurchasePaymentDatePreset preset,
  ) {
    if (preset == _PurchasePaymentDatePreset.all) return true;
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    return switch (preset) {
      _PurchasePaymentDatePreset.all => true,
      _PurchasePaymentDatePreset.today => date == today,
      _PurchasePaymentDatePreset.last7Days =>
        !date.isBefore(today.subtract(const Duration(days: 6))) &&
            !date.isAfter(today),
      _PurchasePaymentDatePreset.thisMonth =>
        date.year == today.year && date.month == today.month,
      _PurchasePaymentDatePreset.previousMonth => () {
          final previous = DateTime(today.year, today.month - 1);
          return date.year == previous.year && date.month == previous.month;
        }(),
    };
  }

  int get _activeFilterCount =>
      (_datePreset == _PurchasePaymentDatePreset.all ? 0 : 1) +
      (_selectedMethodId == _allFilterValue ? 0 : 1) +
      (_selectedSupplierId == _allFilterValue ? 0 : 1);

  void _clearFilters() {
    setState(() {
      _datePreset = _PurchasePaymentDatePreset.all;
      _selectedMethodId = _allFilterValue;
      _selectedSupplierId = _allFilterValue;
    });
    _reconcileSelectionAfterFiltering();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchTerm = '');
    _reconcileSelectionAfterFiltering();
  }

  void _reconcileSelectionAfterFiltering() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedPaymentId == null) return;
      if (_lastVisibleRows.any((row) => row.id == _selectedPaymentId)) {
        return;
      }
      setState(() => _selectedPaymentId = null);
    });
  }

  void _changeSort(String columnId) {
    setState(() {
      if (_sortColumn == columnId) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnId;
        _sortAscending = columnId != 'date';
      }
    });
  }

  void _selectRow(_PurchasePaymentRow row) {
    _keyboardFocusNode.requestFocus();
    if (!_isDesktopLayout) {
      context.push('/purchases/payments/${row.id}');
      return;
    }
    setState(() => _selectedPaymentId = row.id);
    final index =
        _lastVisibleRows.indexWhere((candidate) => candidate.id == row.id);
    if (index >= 0) _scrollRowIntoView(index);
  }

  void _openInvoice(_PurchasePaymentRow row) {
    final invoiceId = row.invoice?.id ?? row.payment.invoiceId;
    if (invoiceId.isEmpty) return;
    context.push('/purchases/$invoiceId');
  }

  bool get _isEditableTextFocused {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _moveSelection(int delta) {
    if (_isEditableTextFocused || _lastVisibleRows.isEmpty) return;
    final currentIndex = _lastVisibleRows.indexWhere(
      (row) => row.id == _selectedPaymentId,
    );
    final nextIndex = currentIndex < 0
        ? (delta > 0 ? 0 : _lastVisibleRows.length - 1)
        : (currentIndex + delta).clamp(
            0,
            _lastVisibleRows.length - 1,
          );
    if (nextIndex == currentIndex) return;
    final row = _lastVisibleRows[nextIndex];
    setState(() => _selectedPaymentId = row.id);
    _scrollRowIntoView(nextIndex);
  }

  void _activateSelection() {
    if (_isEditableTextFocused || _lastVisibleRows.isEmpty) return;
    _PurchasePaymentRow? selected;
    for (final row in _lastVisibleRows) {
      if (row.id == _selectedPaymentId) {
        selected = row;
        break;
      }
    }
    if (selected == null) {
      setState(() => _selectedPaymentId = _lastVisibleRows.first.id);
      _scrollRowIntoView(0);
      return;
    }
    context.push('/purchases/payments/${selected.id}');
  }

  void _scrollRowIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final showingCards = _isDesktopLayout && _selectedPaymentId != null;
      final controller =
          showingCards ? _cardScrollController : _verticalScrollController;
      if (!mounted || !controller.hasClients) return;
      final position = controller.position;
      final itemExtent = showingCards ? _paymentCardExtent : _tableRowHeight;
      final rowTop = index * itemExtent;
      final rowBottom = rowTop + itemExtent;
      final viewportTop = position.pixels;
      final viewportBottom = viewportTop + position.viewportDimension;
      double? target;
      if (rowTop < viewportTop) {
        target = rowTop;
      } else if (rowBottom > viewportBottom) {
        target = rowBottom - position.viewportDimension;
      }
      if (target == null) return;
      controller.animateTo(
        target
            .clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            )
            .toDouble(),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _reorderColumn(String sourceId, String targetId) {
    if (sourceId == targetId) return;
    final sourceIndex = _columns.indexWhere((column) => column.id == sourceId);
    final targetIndex = _columns.indexWhere((column) => column.id == targetId);
    if (sourceIndex < 0 || targetIndex < 0) return;
    setState(() {
      final column = _columns.removeAt(sourceIndex);
      final adjustedTarget =
          sourceIndex < targetIndex ? targetIndex - 1 : targetIndex;
      _columns.insert(adjustedTarget, column);
      _draggingColumnId = null;
    });
    unawaited(_saveColumnPreferences());
  }

  void _resizeColumn(
    _PurchasePaymentColumnConfig column,
    double delta,
  ) {
    setState(() {
      column.width = (column.width + delta)
          .clamp(column.minWidth, column.maxWidth)
          .toDouble();
    });
  }

  Future<void> _showColumnCustomizer() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Personalizar columnas'),
            content: SizedBox(
              width: 420,
              height: 460,
              child: ReorderableListView.builder(
                itemCount: _columns.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  setState(() {
                    final column = _columns.removeAt(oldIndex);
                    _columns.insert(newIndex, column);
                  });
                  setDialogState(() {});
                  unawaited(_saveColumnPreferences());
                },
                itemBuilder: (context, index) {
                  final column = _columns[index];
                  return CheckboxListTile(
                    key: ValueKey(column.id),
                    dense: true,
                    secondary: const Icon(Icons.drag_handle, size: 19),
                    title: Text(column.label),
                    subtitle: Text('${column.width.round()} px'),
                    value: column.visible,
                    onChanged: column.alwaysVisible
                        ? null
                        : (value) {
                            setState(
                              () => column.visible = value ?? false,
                            );
                            setDialogState(() {});
                            unawaited(_saveColumnPreferences());
                          },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => _columns = _defaultColumns());
                  setDialogState(() {});
                  unawaited(_saveColumnPreferences());
                },
                child: const Text('Restablecer'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Listo'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentMethodService = context.watch<PaymentMethodService>();
    final allRows = _buildJoinedRows(paymentMethodService);
    final visibleRows = _filteredAndSortedRows(allRows);
    _lastVisibleRows = visibleRows;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown):
            _PurchasePaymentMoveIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            _PurchasePaymentMoveIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter):
            _PurchasePaymentActivateIntent(),
      },
      child: Actions(
        actions: {
          _PurchasePaymentMoveIntent:
              CallbackAction<_PurchasePaymentMoveIntent>(
            onInvoke: (intent) {
              _moveSelection(intent.delta);
              return null;
            },
          ),
          _PurchasePaymentActivateIntent:
              CallbackAction<_PurchasePaymentActivateIntent>(
            onInvoke: (_) {
              _activateSelection();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < _mobileBreakpoint;
              _isDesktopLayout =
                  constraints.maxWidth >= _desktopSplitBreakpoint;

              if (_isLoading) {
                return const Center(child: BrandedLoading());
              }
              if (_loadError != null) return _buildErrorState();
              if (isMobile) {
                return _buildMobileLayout(allRows, visibleRows);
              }
              return _buildDesktopLayout(
                allRows,
                visibleRows,
                constraints.maxWidth,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    List<_PurchasePaymentRow> allRows,
    List<_PurchasePaymentRow> visibleRows,
    double availableWidth,
  ) {
    _PurchasePaymentRow? selectedRow;
    final selectedId = _selectedPaymentId;
    if (selectedId != null) {
      for (final row in allRows) {
        if (row.id == selectedId) {
          selectedRow = row;
          break;
        }
      }
    }
    final canSplit = _isDesktopLayout && selectedRow != null;

    return Column(
      children: [
        _buildPageHeader(allRows.length),
        Expanded(
          child: canSplit
              ? _buildSplitView(
                  allRows,
                  visibleRows,
                  selectedRow,
                  availableWidth,
                )
              : _buildFullTableView(allRows, visibleRows),
        ),
      ],
    );
  }

  Widget _buildPageHeader(int totalCount) {
    final theme = Theme.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagos a proveedores',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$totalCount registros vinculados a facturas de compra',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/purchases'),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Facturas'),
          ),
        ],
      ),
    );
  }

  Widget _buildFullTableView(
    List<_PurchasePaymentRow> allRows,
    List<_PurchasePaymentRow> visibleRows,
  ) {
    return Column(
      children: [
        _buildSummaryCards(visibleRows),
        const SizedBox(height: 16),
        _buildToolbar(allRows, compact: false),
        const SizedBox(height: 8),
        Expanded(
          child: visibleRows.isEmpty
              ? _buildEmptyState(hasData: allRows.isNotEmpty)
              : _buildPaymentsTable(visibleRows),
        ),
      ],
    );
  }

  Widget _buildSplitView(
    List<_PurchasePaymentRow> allRows,
    List<_PurchasePaymentRow> visibleRows,
    _PurchasePaymentRow selectedRow,
    double availableWidth,
  ) {
    final theme = Theme.of(context);
    final maximumWidth = math.max(
      _minimumListPaneWidth,
      math.min(
        _maximumListPaneWidth,
        availableWidth - _minimumDetailPaneWidth - 9,
      ),
    );
    final listWidth =
        _listPaneWidth.clamp(_minimumListPaneWidth, maximumWidth).toDouble();

    return Row(
      children: [
        SizedBox(
          width: listWidth,
          child: Column(
            children: [
              _buildToolbar(allRows, compact: true),
              Expanded(
                child: visibleRows.isEmpty
                    ? _buildEmptyState(hasData: allRows.isNotEmpty)
                    : _buildPaymentCardsList(visibleRows),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Ajustar ancho de la lista de pagos de compras',
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _listPaneWidth = (_listPaneWidth + details.delta.dx)
                      .clamp(_minimumListPaneWidth, maximumWidth)
                      .toDouble();
                });
              },
              onHorizontalDragEnd: (_) => unawaited(_saveListPaneWidth()),
              child: SizedBox(
                width: 9,
                child: Center(
                  child: VerticalDivider(
                    width: 1,
                    color: theme.dividerColor,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: selectedRow.invoice == null
              ? _buildMissingInvoiceDetail(selectedRow)
              : PurchasePaymentDetailView(
                  key: ValueKey('purchase-payment-detail-${selectedRow.id}'),
                  payment: selectedRow.payment,
                  invoice: selectedRow.invoice!,
                  paymentMethodName: selectedRow.paymentMethodName,
                  onClose: () => setState(() => _selectedPaymentId = null),
                  onRefresh: () => _loadData(),
                ),
        ),
      ],
    );
  }

  Widget _buildPaymentCardsList(List<_PurchasePaymentRow> rows) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView.builder(
      key: const ValueKey('purchase-payments-split-card-list'),
      controller: _cardScrollController,
      itemExtent: _paymentCardExtent,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final selected = row.id == _selectedPaymentId;
        final selectedColor = isDark
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : Colors.blue[50]!;

        return Material(
          key: ValueKey('purchase-payment-card-${row.id}'),
          color: selected ? selectedColor : theme.cardColor,
          child: InkWell(
            onTap: () {
              if (selected) {
                setState(() => _selectedPaymentId = null);
              } else {
                _selectRow(row);
              }
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor),
                  left: selected
                      ? BorderSide(
                          color: theme.colorScheme.primary,
                          width: 3,
                        )
                      : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.supplierName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        ChileanUtils.formatCurrency(row.payment.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        row.code,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(
                          color: theme.hintColor.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ChileanUtils.formatDateTime(
                            row.payment.date.toLocal(),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(child: _buildPaymentMethodChip(row)),
                      const SizedBox(width: 10),
                      Tooltip(
                        message: row.invoice == null
                            ? 'La factura vinculada no está disponible'
                            : 'Abrir factura ${row.invoiceNumber}',
                        child: InkWell(
                          onTap: row.invoice == null
                              ? null
                              : () => _openInvoice(row),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Text(
                              row.invoiceNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: row.invoice == null
                                    ? theme.hintColor
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentMethodChip(_PurchasePaymentRow row) {
    final theme = Theme.of(context);
    final methodIdentity =
        '${row.paymentMethodCode} ${row.paymentMethodName}'.toLowerCase();
    bool containsAny(Iterable<String> values) =>
        values.any(methodIdentity.contains);

    final MaterialColor tone;
    var lightBackgroundShade = 100;
    var lightForegroundShade = 800;
    if (containsAny(const ['cash', 'efectivo', 'caja'])) {
      tone = Colors.green;
    } else if (containsAny(const ['mercado pago', 'mercadopago'])) {
      tone = Colors.purple;
    } else if (containsAny(const [
      'transfer',
      'bank',
      'banco',
      'deposit',
      'depósito',
      'deposito',
    ])) {
      tone = Colors.teal;
    } else if (containsAny(const [
      'card',
      'tarjeta',
      'credit',
      'crédito',
      'credito',
      'debit',
      'débito',
      'debito',
      'webpay',
      'transbank',
    ])) {
      tone = Colors.blue;
    } else if (containsAny(const ['check', 'cheque'])) {
      tone = Colors.orange;
    } else {
      tone = Colors.grey;
      lightBackgroundShade = 200;
      lightForegroundShade = 700;
    }

    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? tone[700]!.withValues(alpha: 0.28)
        : tone[lightBackgroundShade]!;
    final foregroundColor = isDark ? tone[100]! : tone[lightForegroundShade]!;

    return Tooltip(
      message: row.paymentMethodName,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            row.paymentMethodName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(
    List<_PurchasePaymentRow> allRows, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final filterControls = <Widget>[
      _buildDateFilter(allRows),
      const SizedBox(width: 8),
      _buildMethodFilter(allRows),
      const SizedBox(width: 8),
      _buildSupplierFilter(allRows),
      if (_activeFilterCount > 0) ...[
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
          label: Text('Limpiar ($_activeFilterCount)'),
        ),
      ],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: compact
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildSearchField(compact: true)),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isRefreshing ? null : () => _loadData(),
                      tooltip: 'Actualizar pagos',
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              size: 20,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: filterControls),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: _buildSearchField(compact: false)),
                const SizedBox(width: 12),
                ...filterControls,
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showColumnCustomizer,
                  tooltip: 'Ordenar, mostrar y ocultar columnas',
                  icon: const Icon(
                    Icons.view_column_outlined,
                    size: 20,
                  ),
                ),
                IconButton(
                  onPressed: _isRefreshing ? null : () => _loadData(),
                  tooltip: 'Actualizar pagos',
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchField({required bool compact}) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: compact
              ? 'Buscar pagos…'
              : 'Buscar PAG, factura, proveedor, RUT, referencia o monto…',
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          suffixIcon: _searchTerm.isEmpty
              ? null
              : IconButton(
                  onPressed: _clearSearch,
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (value) {
          setState(() => _searchTerm = value);
          _reconcileSelectionAfterFiltering();
        },
      ),
    );
  }

  Widget _buildDateFilter(List<_PurchasePaymentRow> allRows) {
    return _buildFilterMenu<_PurchasePaymentDatePreset>(
      tooltip: 'Filtrar por fecha',
      icon: Icons.calendar_today_outlined,
      label: _datePreset.label,
      value: _datePreset,
      items: _PurchasePaymentDatePreset.values
          .map(
            (preset) => DropdownMenuItem(
              value: preset,
              child: Text(
                '${preset.label} (${allRows.where((row) => _matchesDatePreset(row.payment.date, preset)).length})',
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _datePreset = value);
        _reconcileSelectionAfterFiltering();
      },
    );
  }

  Widget _buildMethodFilter(List<_PurchasePaymentRow> allRows) {
    final methodLabels = <String, String>{};
    final counts = <String, int>{};
    for (final row in allRows) {
      methodLabels[row.payment.paymentMethodId] = row.paymentMethodName;
      counts.update(
        row.payment.paymentMethodId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final ids = methodLabels.keys.toList()
      ..sort(
        (left, right) =>
            _compareText(methodLabels[left]!, methodLabels[right]!),
      );
    return _buildFilterMenu<String>(
      tooltip: 'Filtrar por medio de pago',
      icon: Icons.account_balance_wallet_outlined,
      label: _selectedMethodId == _allFilterValue
          ? 'Todos los medios'
          : methodLabels[_selectedMethodId] ?? 'Medio no disponible',
      value: _selectedMethodId,
      items: [
        DropdownMenuItem(
          value: _allFilterValue,
          child: Text('Todos los medios (${allRows.length})'),
        ),
        ...ids.map(
          (id) => DropdownMenuItem(
            value: id,
            child: Text('${methodLabels[id]} (${counts[id]})'),
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedMethodId = value);
        _reconcileSelectionAfterFiltering();
      },
    );
  }

  Widget _buildSupplierFilter(List<_PurchasePaymentRow> allRows) {
    final supplierLabels = <String, String>{};
    final counts = <String, int>{};
    for (final row in allRows) {
      supplierLabels[row.supplierKey] = row.supplierName;
      counts.update(
        row.supplierKey,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final ids = supplierLabels.keys.toList()
      ..sort(
        (left, right) =>
            _compareText(supplierLabels[left]!, supplierLabels[right]!),
      );
    return _buildFilterMenu<String>(
      tooltip: 'Filtrar por proveedor',
      icon: Icons.storefront_outlined,
      label: _selectedSupplierId == _allFilterValue
          ? 'Todos los proveedores'
          : supplierLabels[_selectedSupplierId] ?? 'Proveedor no disponible',
      value: _selectedSupplierId,
      items: [
        DropdownMenuItem(
          value: _allFilterValue,
          child: Text('Todos los proveedores (${allRows.length})'),
        ),
        ...ids.map(
          (id) => DropdownMenuItem(
            value: id,
            child: Text('${supplierLabels[id]} (${counts[id]})'),
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedSupplierId = value);
        _reconcileSelectionAfterFiltering();
      },
    );
  }

  Widget _buildFilterMenu<T>({
    required String tooltip,
    required IconData icon,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 34,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.only(left: 9, right: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(7),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            items: items,
            onChanged: onChanged,
            selectedItemBuilder: (context) => items
                .map(
                  (_) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(List<_PurchasePaymentRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final total = rows.fold<double>(0, (sum, row) => sum + row.payment.amount);
    final average = total / rows.length;
    final latest = rows
        .map((row) => row.payment.date)
        .reduce((left, right) => left.isAfter(right) ? left : right);

    final metrics = [
      _PurchasePaymentSummaryMetric(
        label: 'Total pagado',
        value: ChileanUtils.formatCurrency(total),
        icon: Icons.account_balance_wallet_outlined,
        color: Colors.green[700]!,
      ),
      _PurchasePaymentSummaryMetric(
        label: 'Pagos',
        value: '${rows.length}',
        icon: Icons.receipt_long_outlined,
        color: theme.colorScheme.primary,
      ),
      _PurchasePaymentSummaryMetric(
        label: 'Promedio',
        value: ChileanUtils.formatCurrency(average),
        icon: Icons.analytics_outlined,
        color: Colors.blueGrey[700]!,
      ),
      _PurchasePaymentSummaryMetric(
        label: 'Último pago',
        value: ChileanUtils.formatDate(latest.toLocal()),
        icon: Icons.schedule_outlined,
        color: Colors.indigo[600]!,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryMetric(metrics[0]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryMetric(metrics[1]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryMetric(metrics[2]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryMetric(metrics[3]),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    for (var index = 0; index < metrics.length; index++) ...[
                      if (index > 0) const SizedBox(width: 24),
                      Expanded(
                        child: _buildSummaryMetric(metrics[index]),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSummaryMetric(_PurchasePaymentSummaryMetric metric) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(metric.icon, color: metric.color, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStrip(
    List<_PurchasePaymentRow> rows, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final total = rows.fold<double>(0, (sum, row) => sum + row.payment.amount);
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          Text(
            '${rows.length} ${rows.length == 1 ? 'pago' : 'pagos'}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 16, color: theme.dividerColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Total visible: ${ChileanUtils.formatCurrency(total)}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsTable(List<_PurchasePaymentRow> rows) {
    final visibleColumns =
        _columns.where((column) => column.visible).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnsWidth = visibleColumns.fold<double>(
          0,
          (sum, column) => sum + column.width,
        );
        const fixedColumnsWidth = 96.0;
        final tableWidth = math.max(
          columnsWidth + fixedColumnsWidth,
          constraints.maxWidth,
        );
        final availableColumnsWidth = tableWidth - fixedColumnsWidth;
        final stretch = availableColumnsWidth > columnsWidth && columnsWidth > 0
            ? availableColumnsWidth / columnsWidth
            : 1.0;
        final effectiveWidths = {
          for (final column in visibleColumns)
            column.id: column.width * stretch,
        };

        return Container(
          key: const ValueKey('purchase-payments-full-table'),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Colors.grey[300]!),
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                controller: _headerHorizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: _buildTableHeader(
                    visibleColumns,
                    effectiveWidths,
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _bodyHorizontalController,
                  thumbVisibility:
                      columnsWidth + fixedColumnsWidth > constraints.maxWidth,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _bodyHorizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemExtent: _tableRowHeight,
                        itemCount: rows.length,
                        itemBuilder: (context, index) => _buildTableRow(
                          rows[index],
                          visibleColumns,
                          effectiveWidths,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(
    List<_PurchasePaymentColumnConfig> columns,
    Map<String, double> widths,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: _tableHeaderHeight,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerLowest
            : Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: _tableHeaderHeight,
            child: Checkbox(
              value: false,
              onChanged: (_) {},
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          ...columns.map(
            (column) => _buildHeaderCell(
              column,
              widths[column.id]!,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    _PurchasePaymentColumnConfig column,
    double width,
  ) {
    final theme = Theme.of(context);
    final isSorted = _sortColumn == column.id;
    final header = Container(
      height: _tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onTap: () => _changeSort(column.id),
        child: Row(
          mainAxisAlignment:
              column.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                column.label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.onSurfaceVariant
                      : Colors.grey[700],
                ),
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 3),
              Icon(
                _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 18,
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.onSurfaceVariant
                    : Colors.grey[700],
              ),
            ],
          ],
        ),
      ),
    );

    final draggable = Draggable<String>(
      data: column.id,
      axis: Axis.horizontal,
      onDragStarted: () => setState(() => _draggingColumnId = column.id),
      onDragEnd: (_) => setState(() => _draggingColumnId = null),
      onDraggableCanceled: (_, __) => setState(() => _draggingColumnId = null),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: width.clamp(90, 220),
          height: _tableHeaderHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            column.label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      child: Opacity(
        opacity: _draggingColumnId == column.id ? 0.35 : 1,
        child: header,
      ),
    );

    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) => details.data != column.id,
              onAcceptWithDetails: (details) =>
                  _reorderColumn(details.data, column.id),
              builder: (context, candidates, rejected) => DecoratedBox(
                decoration: BoxDecoration(
                  color: candidates.isEmpty
                      ? Colors.transparent
                      : theme.colorScheme.primary.withValues(alpha: 0.08),
                ),
                child: draggable,
              ),
            ),
          ),
          Positioned(
            right: -4,
            top: 0,
            bottom: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) =>
                    _resizeColumn(column, details.delta.dx),
                onHorizontalDragEnd: (_) => unawaited(_saveColumnPreferences()),
                onDoubleTap: () {
                  _PurchasePaymentColumnConfig? defaultColumn;
                  for (final candidate in _defaultColumns()) {
                    if (candidate.id == column.id) {
                      defaultColumn = candidate;
                      break;
                    }
                  }
                  if (defaultColumn == null) return;
                  setState(() => column.width = defaultColumn!.width);
                  unawaited(_saveColumnPreferences());
                },
                child: Center(
                  child: Container(
                    width: 1,
                    height: 20,
                    color: theme.dividerColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    _PurchasePaymentRow row,
    List<_PurchasePaymentColumnConfig> columns,
    Map<String, double> widths,
  ) {
    final theme = Theme.of(context);
    final selected = row.id == _selectedPaymentId;
    return Material(
      color: selected
          ? (theme.brightness == Brightness.dark
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.blue[50]!)
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: () => _selectRow(row),
        hoverColor: theme.brightness == Brightness.dark
            ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
            : Colors.grey[50],
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.brightness == Brightness.dark
                    ? theme.dividerColor
                    : Colors.grey[200]!,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: _tableRowHeight,
                child: Checkbox(
                  value: selected,
                  onChanged: (value) {
                    if (value == true) {
                      _selectRow(row);
                    } else {
                      setState(() => _selectedPaymentId = null);
                    }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              ...columns.map(
                (column) => _buildTableCell(
                  row,
                  column,
                  widths[column.id]!,
                ),
              ),
              SizedBox(
                width: 48,
                height: _tableRowHeight,
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Acciones del pago',
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    switch (action) {
                      case 'open':
                        _selectRow(row);
                        break;
                      case 'invoice':
                        _openInvoice(row);
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_rounded, size: 17),
                          SizedBox(width: 9),
                          Text('Abrir pago'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'invoice',
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 17,
                          ),
                          SizedBox(width: 9),
                          Text('Abrir factura'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell(
    _PurchasePaymentRow row,
    _PurchasePaymentColumnConfig column,
    double width,
  ) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      fontFeatures:
          column.numeric ? const [FontFeature.tabularFigures()] : const [],
    );
    Widget child;

    switch (column.id) {
      case 'code':
        child = Text(
          row.code,
          overflow: TextOverflow.ellipsis,
          style: textStyle?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        );
        break;
      case 'date':
        child = Text(
          ChileanUtils.formatDateTime(row.payment.date.toLocal()),
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
        break;
      case 'supplier':
        child = Text(
          row.supplierName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
        break;
      case 'invoice':
        child = Tooltip(
          message: row.invoice == null
              ? 'La factura vinculada no está disponible'
              : 'Abrir factura ${row.invoiceNumber}',
          child: InkWell(
            onTap: () => _openInvoice(row),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                row.invoiceNumber,
                overflow: TextOverflow.ellipsis,
                style: textStyle?.copyWith(
                  color: row.invoice == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
        break;
      case 'method':
        child = _buildPaymentMethodChip(row);
        break;
      case 'reference':
        child = Text(
          _displayValue(row.payment.reference),
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
        break;
      case 'amount':
        child = Text(
          ChileanUtils.formatCurrency(row.payment.amount),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: textStyle?.copyWith(fontWeight: FontWeight.w500),
        );
        break;
      case 'notes':
        child = Text(
          _displayValue(row.payment.notes),
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
        break;
      default:
        child = const SizedBox.shrink();
    }

    final tooltip = _cellTooltip(row, column.id);
    return Container(
      width: width,
      height: _tableRowHeight,
      alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: tooltip == null || column.id == 'invoice'
          ? child
          : Tooltip(message: tooltip, child: child),
    );
  }

  String? _cellTooltip(
    _PurchasePaymentRow row,
    String columnId,
  ) {
    return switch (columnId) {
      'code' => row.code,
      'date' => ChileanUtils.formatDateTime(row.payment.date.toLocal()),
      'supplier' => [
          row.supplierName,
          if (row.supplierRut.isNotEmpty)
            ChileanUtils.formatRut(row.supplierRut),
        ].join(' · '),
      'method' => row.paymentMethodName,
      'reference' => row.payment.reference,
      'amount' => ChileanUtils.formatCurrency(row.payment.amount),
      'notes' => row.payment.notes,
      _ => null,
    };
  }

  Widget _buildMobileLayout(
    List<_PurchasePaymentRow> allRows,
    List<_PurchasePaymentRow> visibleRows,
  ) {
    return Column(
      children: [
        _buildMobileHeader(allRows),
        _buildSummaryStrip(visibleRows, compact: true),
        Expanded(
          child: visibleRows.isEmpty
              ? _buildEmptyState(hasData: allRows.isNotEmpty)
              : RefreshIndicator(
                  onRefresh: () => _loadData(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                    itemCount: visibleRows.length,
                    itemBuilder: (context, index) =>
                        _buildMobilePaymentCard(visibleRows[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(List<_PurchasePaymentRow> allRows) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pagos a proveedores',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _isRefreshing ? null : () => _loadData(),
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar pagos…',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _searchTerm.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                      ),
                    ),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() => _searchTerm = value);
              _reconcileSelectionAfterFiltering();
            },
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDateFilter(allRows),
                const SizedBox(width: 8),
                _buildMethodFilter(allRows),
                const SizedBox(width: 8),
                _buildSupplierFilter(allRows),
                if (_activeFilterCount > 0)
                  TextButton(
                    onPressed: _clearFilters,
                    child: Text('Limpiar ($_activeFilterCount)'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePaymentCard(_PurchasePaymentRow row) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        onTap: () => context.push('/purchases/payments/${row.id}'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.code,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    ChileanUtils.formatCurrency(row.payment.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                row.supplierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildPaymentMethodChip(row)),
                  const SizedBox(width: 8),
                  Text(
                    ChileanUtils.formatDateTime(
                      row.payment.date.toLocal(),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 19),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton(
                    onPressed:
                        row.invoice == null ? null : () => _openInvoice(row),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(row.invoiceNumber),
                  ),
                  if (row.payment.reference?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ref. ${row.payment.reference}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
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

  Widget _buildErrorState() {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                'No se pudo cargar el registro de pagos',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _loadData(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasData}) {
    final theme = Theme.of(context);
    final filtered =
        hasData && (_searchTerm.isNotEmpty || _activeFilterCount > 0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.search_off_rounded : Icons.payments_outlined,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'No hay pagos que coincidan'
                  : 'Aún no hay pagos registrados',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              filtered
                  ? 'Ajusta la búsqueda o limpia los filtros activos.'
                  : 'Los pagos registrados desde las facturas de compra aparecerán aquí.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {
                  _clearSearch();
                  _clearFilters();
                },
                child: const Text('Limpiar búsqueda y filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMissingInvoiceDetail(_PurchasePaymentRow row) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.link_off_rounded,
                  size: 44,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Factura vinculada no disponible',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'El pago ${row.code} conserva su vínculo con la factura '
                  '${row.invoiceNumber}, pero no fue posible cargarla. '
                  'Actualiza antes de operar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _selectedPaymentId = null),
                      child: const Text('Cerrar'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(
                        Icons.refresh_rounded,
                        size: 18,
                      ),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<_PurchasePaymentColumnConfig> _defaultColumns() => [
        _PurchasePaymentColumnConfig(
          id: 'code',
          label: 'Pago',
          width: 125,
          minWidth: 105,
          maxWidth: 190,
          alwaysVisible: true,
        ),
        _PurchasePaymentColumnConfig(
          id: 'date',
          label: 'Fecha',
          width: 145,
          minWidth: 120,
          maxWidth: 220,
        ),
        _PurchasePaymentColumnConfig(
          id: 'supplier',
          label: 'Proveedor',
          width: 220,
          minWidth: 150,
          maxWidth: 380,
        ),
        _PurchasePaymentColumnConfig(
          id: 'invoice',
          label: 'Factura',
          width: 130,
          minWidth: 105,
          maxWidth: 210,
        ),
        _PurchasePaymentColumnConfig(
          id: 'method',
          label: 'Medio de pago',
          width: 180,
          minWidth: 130,
          maxWidth: 300,
        ),
        _PurchasePaymentColumnConfig(
          id: 'reference',
          label: 'Referencia',
          width: 175,
          minWidth: 120,
          maxWidth: 340,
        ),
        _PurchasePaymentColumnConfig(
          id: 'amount',
          label: 'Monto',
          width: 130,
          minWidth: 105,
          maxWidth: 190,
          numeric: true,
        ),
        _PurchasePaymentColumnConfig(
          id: 'notes',
          label: 'Notas',
          width: 260,
          minWidth: 160,
          maxWidth: 460,
          visible: false,
        ),
      ];

  static String _paymentNumber(PurchasePayment payment) {
    final id = payment.id?.trim();
    if (id == null || id.isEmpty) return 'PAG-SIN-ID';
    final compact = id.replaceAll('-', '').toUpperCase();
    final suffix = compact.length <= 6
        ? compact.padLeft(6, '0')
        : compact.substring(compact.length - 6);
    return 'PAG-$suffix';
  }

  static String _displayValue(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? '—' : trimmed;
  }
}

class _PurchasePaymentRow {
  const _PurchasePaymentRow({
    required this.payment,
    required this.invoice,
    required this.code,
    required this.paymentMethodName,
    required this.paymentMethodCode,
  });

  final PurchasePayment payment;
  final PurchaseInvoice? invoice;
  final String code;
  final String paymentMethodName;
  final String paymentMethodCode;

  String get id => payment.id ?? '';

  String get invoiceNumber {
    final value = invoice?.invoiceNumber.trim();
    if (value != null && value.isNotEmpty) return value;
    final historical = payment.invoiceNumber?.trim();
    return historical == null || historical.isEmpty
        ? 'Sin factura'
        : historical;
  }

  String get supplierName {
    final value = invoice?.supplierName?.trim();
    if (value != null && value.isNotEmpty) return value;
    final historical = payment.supplierName?.trim();
    return historical == null || historical.isEmpty
        ? 'Proveedor no disponible'
        : historical;
  }

  String get supplierKey {
    final id = invoice?.supplierId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return 'name:${supplierName.trim().toLowerCase()}';
  }

  String get supplierRut => invoice?.supplierRut?.trim() ?? '';
}

class _PurchasePaymentColumnConfig {
  _PurchasePaymentColumnConfig({
    required this.id,
    required this.label,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    this.visible = true,
    this.alwaysVisible = false,
    this.numeric = false,
  });

  final String id;
  final String label;
  double width;
  final double minWidth;
  final double maxWidth;
  bool visible;
  final bool alwaysVisible;
  final bool numeric;
}

class _PurchasePaymentSummaryMetric {
  const _PurchasePaymentSummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

enum _PurchasePaymentDatePreset {
  all('Todas las fechas'),
  today('Hoy'),
  last7Days('Últimos 7 días'),
  thisMonth('Este mes'),
  previousMonth('Mes anterior');

  const _PurchasePaymentDatePreset(this.label);
  final String label;
}

class _PurchasePaymentMoveIntent extends Intent {
  const _PurchasePaymentMoveIntent(this.delta);
  final int delta;
}

class _PurchasePaymentActivateIntent extends Intent {
  const _PurchasePaymentActivateIntent();
}
