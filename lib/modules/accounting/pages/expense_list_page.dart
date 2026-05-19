import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../models/expense_link.dart';
import '../services/expense_service.dart';

class ExpenseListPage extends StatefulWidget {
  const ExpenseListPage({super.key});

  @override
  State<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends State<ExpenseListPage> {
  late ExpenseService _expenseService;
  final NumberFormat _currencyFormat = ChileanUtils.currencyFormat;

  final TextEditingController _searchController = TextEditingController();

  List<Expense> _allExpenses = const [];
  List<Expense> _filteredExpenses = const [];
  List<ExpenseCategory> _categories = const [];
  Map<String, String> _categoryNamesById = const {};
  Map<String, List<ExpenseLink>> _expenseLinksByExpenseId = const {};

  ExpensePostingStatus? _postingFilter;
  ExpensePaymentStatus? _paymentFilter;
  String? _selectedCategoryId;
  DateTimeRange? _dateRange;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expenseService = context.read<ExpenseService>();
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Cache for payment methods
  Map<String, String> _paymentMethodsMap = {};

  // Summary of payments per expense (used to infer payment method when header is null)
  final Map<String, _ExpensePaymentSummary> _paymentSummaryByExpenseId = {};

  Future<void> _loadData({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final categories =
          await _expenseService.fetchCategories(forceRefresh: refresh);
      final expenses =
          await _expenseService.fetchExpenses(forceRefresh: refresh);

      // Fetch payment methods
      final methods = await _expenseService.fetchPaymentMethods();

      // Fetch payments for loaded expenses (to correctly label single vs mixed payments)
      final expenseIds =
          expenses.map((e) => e.id).whereType<String>().toList(growable: false);
      final paymentRows =
          await _expenseService.fetchPaymentsForExpenses(expenseIds);
      final paymentSummary = _buildPaymentSummary(paymentRows);
      List<ExpenseLink> expenseLinks = const [];
      try {
        expenseLinks = await _expenseService.fetchLinksForExpenses(expenseIds);
      } catch (_) {
        expenseLinks = const [];
      }
      final linksByExpenseId = _groupExpenseLinks(expenseLinks);

      setState(() {
        _categories = categories;
        _categoryNamesById = {
          for (final c in categories)
            if (c.id.isNotEmpty) c.id: c.name,
        };
        _allExpenses = expenses;
        _paymentMethodsMap = methods;
        _expenseLinksByExpenseId = linksByExpenseId;
        _paymentSummaryByExpenseId
          ..clear()
          ..addAll(paymentSummary);
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Map<String, _ExpensePaymentSummary> _buildPaymentSummary(
    List<Map<String, dynamic>> rows,
  ) {
    final summaries = <String, _ExpensePaymentSummary>{};

    for (final row in rows) {
      final expenseId = row['expense_id']?.toString();
      if (expenseId == null || expenseId.isEmpty) continue;

      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;

      final methodId = row['payment_method_id']?.toString();
      final accountId = row['payment_account_id']?.toString();

      final summary = summaries.putIfAbsent(
        expenseId,
        () => _ExpensePaymentSummary(),
      );
      summary.totalPaid += amount;
      if (methodId != null && methodId.isNotEmpty) {
        summary.methodIds.add(methodId);
      }
      if (accountId != null && accountId.isNotEmpty) {
        summary.accountIds.add(accountId);
      }
    }

    return summaries;
  }

  Map<String, List<ExpenseLink>> _groupExpenseLinks(List<ExpenseLink> links) {
    final grouped = <String, List<ExpenseLink>>{};
    for (final link in links) {
      if (link.expenseId.isEmpty) continue;
      grouped.putIfAbsent(link.expenseId, () => <ExpenseLink>[]).add(link);
    }
    return grouped;
  }

  void _applyFilters() {
    final term = _searchController.text.trim().toLowerCase();
    final filtered = _allExpenses.where((expense) {
      final purchaseLinks = expense.id == null
          ? const <ExpenseLink>[]
          : _expenseLinksByExpenseId[expense.id] ?? const <ExpenseLink>[];
      final matchesSearch = term.isEmpty ||
          expense.expenseNumber.toLowerCase().contains(term) ||
          (expense.supplierName?.toLowerCase().contains(term) ?? false) ||
          (expense.reference?.toLowerCase().contains(term) ?? false) ||
          purchaseLinks.any((link) => _linkSearchText(link).contains(term));

      final matchesPosting =
          _postingFilter == null || expense.postingStatus == _postingFilter;

      final matchesPayment =
          _paymentFilter == null || expense.paymentStatus == _paymentFilter;

      final matchesCategory = _selectedCategoryId == null ||
          expense.categoryId == _selectedCategoryId;

      final matchesDate = _dateRange == null ||
          (expense.issueDate.isAfter(
                  _dateRange!.start.subtract(const Duration(days: 1))) &&
              expense.issueDate
                  .isBefore(_dateRange!.end.add(const Duration(days: 1))));

      return matchesSearch &&
          matchesPosting &&
          matchesPayment &&
          matchesCategory &&
          matchesDate;
    }).toList();

    // Sort by Issue Date Descending by default
    filtered.sort((a, b) => b.issueDate.compareTo(a.issueDate));

    setState(() {
      _filteredExpenses = filtered;
    });
  }

  double get _pendingTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.pending)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _scheduledTotal => _filteredExpenses
      .where(
          (expense) => expense.paymentStatus == ExpensePaymentStatus.scheduled)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _partialTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.partial)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _paidTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.paid)
      .fold(0.0, (sum, expense) => sum + expense.totalAmount);

  Future<void> _openExpenseDetail(Expense expense) async {
    if (expense.id == null) return;

    final changed =
        await context.push<bool>('/accounting/expenses/${expense.id}');
    if (changed == true && mounted) {
      await _loadData(refresh: true);
    }
  }

  Future<void> _editExpense(Expense expense) async {
    if (expense.id == null) return;

    final changed =
        await context.push<bool>('/accounting/expenses/${expense.id}/edit');
    if (changed == true && mounted) {
      await _loadData(refresh: true);
    }
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    if (expense.id == null) return;

    List<ExpenseLink> links = const [];
    try {
      links = await _expenseService.fetchLinksForExpense(expense.id!);
    } catch (_) {
      links = const [];
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Eliminar gasto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se eliminará ${expense.expenseNumber} y también sus líneas, pagos, adjuntos y asientos contables relacionados.',
                style: theme.textTheme.bodyMedium,
              ),
              if (links.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Este gasto está vinculado a factura de compra. Al eliminarlo se quitará ese vínculo, pero la factura de compra no se eliminará.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...links.take(3).map(
                      (link) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '- ${_linkKindLabel(link.linkKind)} · ${_purchaseInvoiceLabel(link)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                if (links.length > 3)
                  Text(
                    '+${links.length - 3} vínculos más',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                'Esta acción no se puede deshacer.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      setState(() {
        _isLoading = true;
      });

      await _expenseService.deleteExpense(expense.id!);
      await _loadData(refresh: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            links.isEmpty
                ? 'Gasto ${expense.expenseNumber} eliminado junto con su información contable relacionada.'
                : 'Gasto ${expense.expenseNumber} eliminado y desvinculado de la factura de compra.',
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el gasto: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _purchaseInvoiceLabel(ExpenseLink link) {
    final number = (link.purchaseInvoiceNumber ?? '').trim();
    final supplier = (link.purchaseSupplierName ?? '').trim();
    if (number.isEmpty && supplier.isEmpty) return 'Factura de compra';
    if (number.isEmpty) return supplier;
    if (supplier.isEmpty) return number;
    return '$number · $supplier';
  }

  String _linkKindLabel(String value) {
    switch (value) {
      case 'delivery':
        return 'Entrega / transporte';
      case 'import_cost':
        return 'Costo de importación';
      default:
        return 'Relacionado';
    }
  }

  String _linkSearchText(ExpenseLink link) {
    return [
      _purchaseInvoiceLabel(link),
      _linkKindLabel(link.linkKind),
      link.notes ?? '',
    ].join(' ').toLowerCase();
  }

  void _showMobileFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filtros',
                        style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                _buildDropdown<ExpensePostingStatus?>(
                  label: 'Estado contable',
                  value: _postingFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...ExpensePostingStatus.values.map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_postingStatusLabel(status)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _postingFilter = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                _buildDropdown<ExpensePaymentStatus?>(
                  label: 'Estado de pago',
                  value: _paymentFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...ExpensePaymentStatus.values.map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_paymentStatusLabel(status)),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _paymentFilter = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                _buildDropdown<String?>(
                  label: 'Categoría',
                  value: _selectedCategoryId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ..._categories.map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedCategoryId = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 16),
                _buildDateSelector(context),
                const SizedBox(height: 24),
                AppButton(
                  text: 'Aplicar Filtros',
                  onPressed: () {
                    _applyFilters();
                    Navigator.pop(context);
                  },
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _postingFilter = null;
                      _paymentFilter = null;
                      _selectedCategoryId = null;
                      _dateRange = null;
                    });
                    _applyFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Limpiar Filtros'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        return MainLayout(
          title: 'Gastos',
          body: Column(
            children: [
              if (isMobile) ...[
                _buildTopBar(context, isMobile),
                _buildSummarySection(context, isMobile),
              ] else ...[
                _buildDesktopHeader(context),
                _buildSummarySection(context, isMobile),
              ],
              Expanded(child: _buildContent(context, isMobile)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SearchWidget(
                  controller: _searchController,
                  hintText: isMobile
                      ? 'Buscar...'
                      : 'Buscar por número, proveedor o referencia...',
                  onSearchChanged: (_) => _applyFilters(),
                ),
              ),
              const SizedBox(width: 8),
              if (isMobile)
                IconButton.filledTonal(
                  onPressed: () => _showMobileFilters(context),
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filtros',
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _isLoading ? null : () => _loadData(refresh: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Categorías',
                onPressed: () => context.push('/accounting/expense-categories'),
                icon: const Icon(Icons.sell_outlined),
              ),
              const SizedBox(width: 8),
              AppButton(
                text: isMobile ? 'Nuevo' : 'Nuevo gasto',
                icon: Icons.add,
                onPressed: () {
                  context
                      .push<bool>('/accounting/expenses/new')
                      .then((created) {
                    if (created == true) {
                      _loadData(refresh: true);
                    }
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 320,
            child: SearchWidget(
              controller: _searchController,
              hintText: 'Buscar por número, proveedor...',
              onSearchChanged: (_) => _applyFilters(),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            height: 24,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(width: 16),
          // Clean Filter Row
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompactDropdown<ExpensePostingStatus?>(
                    hint: 'Estado contable',
                    value: _postingFilter,
                    items: ExpensePostingStatus.values,
                    labelBuilder: (s) => _postingStatusLabel(s!),
                    onChanged: (v) {
                      setState(() => _postingFilter = v);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildCompactDropdown<ExpensePaymentStatus?>(
                    hint: 'Pago',
                    value: _paymentFilter,
                    items: ExpensePaymentStatus.values,
                    labelBuilder: (s) => _paymentStatusLabel(s!),
                    onChanged: (v) {
                      setState(() => _paymentFilter = v);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildCompactDropdown<String?>(
                    hint: 'Categoría',
                    value: _selectedCategoryId,
                    items: _categories.map((c) => c.id).toList(),
                    labelBuilder: (id) =>
                        _categories.firstWhere((c) => c.id == id).name,
                    onChanged: (v) {
                      setState(() => _selectedCategoryId = v);
                      _applyFilters();
                    },
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _buildDateSelector(context),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : () => _loadData(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Categorías',
            onPressed: () => context.push('/accounting/expense-categories'),
            icon: const Icon(Icons.sell_outlined),
          ),
          const SizedBox(width: 12),
          AppButton(
            text: 'Nuevo gasto',
            icon: Icons.add,
            onPressed: () {
              context.push<bool>('/accounting/expenses/new').then((created) {
                if (created == true) {
                  _loadData(refresh: true);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  // Helper for compact dropdowns
  Widget _buildCompactDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          icon: const Icon(Icons.arrow_drop_down, size: 20),
          isDense: true,
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
                value: null,
                child: Text('Todos',
                    style: TextStyle(color: Colors.grey.shade600))),
            ...items.map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(labelBuilder(item)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context, bool isMobile) {
    final cards = [
      _SummaryData(
        title: 'Pendientes',
        amount: _pendingTotal,
        color: Colors.orange.shade700,
        icon: Icons.pending_actions_outlined,
      ),
      _SummaryData(
        title: 'Programados',
        amount: _scheduledTotal,
        color: Colors.blueGrey.shade700,
        icon: Icons.schedule_outlined,
      ),
      _SummaryData(
        title: 'Parciales',
        amount: _partialTotal,
        color: Colors.purple.shade700,
        icon: Icons.timelapse_outlined,
      ),
      _SummaryData(
        title: 'Pagados',
        amount: _paidTotal,
        color: Colors.green.shade700,
        icon: Icons.verified_outlined,
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: cards
              .map((data) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _SummaryCard(data: data),
                  ))
              .toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: cards
            .map((data) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _SummaryCard(data: data),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isMobile) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(
                text: 'Reintentar', onPressed: () => _loadData(refresh: true)),
          ],
        ),
      );
    }

    if (_filteredExpenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(
              'No se encontraron gastos.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _filteredExpenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final expense = _filteredExpenses[index];
        final purchaseLinks = expense.id == null
            ? const <ExpenseLink>[]
            : _expenseLinksByExpenseId[expense.id] ?? const <ExpenseLink>[];
        return _ExpenseCard(
          expense: expense,
          isMobile: isMobile,
          currencyFormat: _currencyFormat,
          paymentMethodsMap: _paymentMethodsMap,
          paymentSummary: _paymentSummaryByExpenseId[expense.id],
          categoryNamesById: _categoryNamesById,
          purchaseLinks: purchaseLinks,
          onTap: () => _openExpenseDetail(expense),
          onEdit: () => _editExpense(expense),
          onDelete: () => _confirmDeleteExpense(expense),
        );
      },
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    final label = _dateRange == null
        ? 'Rango de fechas'
        : '${ChileanUtils.formatDate(_dateRange!.start)} - ${ChileanUtils.formatDate(_dateRange!.end)}';

    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 1),
            initialDateRange: _dateRange,
          );
          if (picked != null) {
            setState(() {
              _dateRange = picked;
            });
            _applyFilters();
          }
        },
        icon: const Icon(Icons.date_range_outlined),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  String _postingStatusLabel(ExpensePostingStatus status) {
    switch (status) {
      case ExpensePostingStatus.draft:
        return 'Borrador';
      case ExpensePostingStatus.posted:
        return 'Contabilizado';
      case ExpensePostingStatus.voided:
        return 'Anulado';
    }
  }

  String _paymentStatusLabel(ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.pending:
        return 'Pendiente';
      case ExpensePaymentStatus.scheduled:
        return 'Programado';
      case ExpensePaymentStatus.partial:
        return 'Parcial';
      case ExpensePaymentStatus.paid:
        return 'Pagado';
      case ExpensePaymentStatus.voided:
        return 'Anulado';
    }
  }
}

class _SummaryData {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  _SummaryData(
      {required this.title,
      required this.amount,
      required this.color,
      required this.icon});
}

class _SummaryCard extends StatelessWidget {
  final _SummaryData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final format = ChileanUtils.currencyFormat;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 16, color: data.color),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(data.title,
                      style: TextStyle(
                          color: data.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Text(format.format(data.amount),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.currencyFormat,
    this.isMobile = false,
    required this.paymentMethodsMap,
    this.paymentSummary,
    required this.categoryNamesById,
    required this.purchaseLinks,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final NumberFormat currencyFormat;
  final bool isMobile;
  final Map<String, String> paymentMethodsMap;
  final _ExpensePaymentSummary? paymentSummary;
  final Map<String, String> categoryNamesById;
  final List<ExpenseLink> purchaseLinks;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final paymentMethodName = () {
      final headerMethodId = expense.paymentMethodId;
      if (headerMethodId != null && headerMethodId.isNotEmpty) {
        return paymentMethodsMap[headerMethodId] ?? 'Sin medio de pago';
      }

      // If header is empty, infer from payments.
      // - 1 distinct method -> show that method name
      // - >1 distinct methods -> "Pago mixto"
      final summary = paymentSummary;
      if (summary != null &&
          expense.paymentStatus == ExpensePaymentStatus.paid) {
        if (summary.methodIds.length == 1) {
          final onlyMethodId = summary.methodIds.first;
          return paymentMethodsMap[onlyMethodId] ?? 'Medio de pago';
        }
        if (summary.methodIds.length > 1) {
          return 'Pago mixto';
        }
      }

      return 'Sin medio de pago';
    }();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // improved left indicator
                Container(
                  width: 4,
                  height: purchaseLinks.isEmpty ? 48 : 68,
                  decoration: BoxDecoration(
                    color: _getStatusColor(expense.paymentStatus),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    expense.expenseNumber,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.blue.shade800),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    expense.category?.name ??
                                        categoryNamesById[expense.categoryId] ??
                                        'Sin categoría',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.payment,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    paymentMethodName,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text('·',
                                    style:
                                        TextStyle(color: Colors.grey.shade400)),
                                const SizedBox(width: 6),
                                Text(
                                  ChileanUtils.formatDate(expense.issueDate),
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.store,
                                    size: 14, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    expense.supplierName ??
                                        'Proveedor sin nombre',
                                    style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (purchaseLinks.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildPurchaseLinkMarker(
                                context,
                                purchaseLinks.first,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            currencyFormat.format(expense.totalAmount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          _StatusBadge(status: expense.paymentStatus),
                          const SizedBox(height: 6),
                          PopupMenuButton<String>(
                            tooltip: 'Ajustes',
                            icon: Icon(
                              Icons.more_horiz,
                              size: 20,
                              color: Colors.grey.shade500,
                            ),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Text('Editar gasto'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red.shade700),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Eliminar gasto',
                                      style:
                                          TextStyle(color: Colors.red.shade700),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                onEdit();
                              } else if (value == 'delete') {
                                onDelete();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseLinkMarker(BuildContext context, ExpenseLink link) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          _linkKindIcon(link.linkKind),
          size: 14,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Compra ${_purchaseInvoiceLabel(link)} · ${_linkKindLabel(link.linkKind)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (purchaseLinks.length > 1) ...[
          const SizedBox(width: 6),
          Text(
            '+${purchaseLinks.length - 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  String _purchaseInvoiceLabel(ExpenseLink link) {
    final number = (link.purchaseInvoiceNumber ?? '').trim();
    final supplier = (link.purchaseSupplierName ?? '').trim();
    if (number.isEmpty && supplier.isEmpty) return 'factura';
    if (number.isEmpty) return supplier;
    if (supplier.isEmpty) return number;
    return '$number · $supplier';
  }

  String _linkKindLabel(String value) {
    switch (value) {
      case 'delivery':
        return 'Entrega / transporte';
      case 'import_cost':
        return 'Costo importación';
      default:
        return 'Relacionado';
    }
  }

  IconData _linkKindIcon(String value) {
    switch (value) {
      case 'delivery':
        return Icons.local_shipping_outlined;
      case 'import_cost':
        return Icons.public_outlined;
      default:
        return Icons.link_rounded;
    }
  }

  Color _getStatusColor(ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.pending:
        return Colors.orange;
      case ExpensePaymentStatus.scheduled:
        return Colors.blueGrey;
      case ExpensePaymentStatus.partial:
        return Colors.purple;
      case ExpensePaymentStatus.paid:
        return Colors.green;
      case ExpensePaymentStatus.voided:
        return Colors.red;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final ExpensePaymentStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    switch (status) {
      case ExpensePaymentStatus.pending:
        color = Colors.orange;
        text = 'Pendiente';
        break;
      case ExpensePaymentStatus.scheduled:
        color = Colors.blueGrey;
        text = 'Programado';
        break;
      case ExpensePaymentStatus.partial:
        color = Colors.purple;
        text = 'Parcial';
        break;
      case ExpensePaymentStatus.paid:
        color = Colors.green;
        text = 'Pagado';
        break;
      case ExpensePaymentStatus.voided:
        color = Colors.red;
        text = 'Anulado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _ExpensePaymentSummary {
  double totalPaid = 0;
  final Set<String> methodIds = {};
  final Set<String> accountIds = {};
}
