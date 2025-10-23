import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
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

  Future<void> _loadData({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final categories = await _expenseService.fetchCategories(forceRefresh: refresh);
      final expenses = await _expenseService.fetchExpenses(forceRefresh: refresh);
      setState(() {
        _categories = categories;
        _allExpenses = expenses;
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

  void _applyFilters() {
    final term = _searchController.text.trim().toLowerCase();
    final filtered = _allExpenses.where((expense) {
      final matchesSearch = term.isEmpty ||
          expense.expenseNumber.toLowerCase().contains(term) ||
          (expense.supplierName?.toLowerCase().contains(term) ?? false) ||
          (expense.reference?.toLowerCase().contains(term) ?? false);

      final matchesPosting = _postingFilter == null ||
          expense.postingStatus == _postingFilter;

      final matchesPayment = _paymentFilter == null ||
          expense.paymentStatus == _paymentFilter;

      final matchesCategory = _selectedCategoryId == null ||
          expense.categoryId == _selectedCategoryId;

      final matchesDate = _dateRange == null ||
          (expense.issueDate.isAfter(_dateRange!.start.subtract(const Duration(days: 1))) &&
              expense.issueDate.isBefore(_dateRange!.end.add(const Duration(days: 1))));

      return matchesSearch && matchesPosting && matchesPayment && matchesCategory && matchesDate;
    }).toList();

    setState(() {
      _filteredExpenses = filtered;
    });
  }

  double get _pendingTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.pending)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _scheduledTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.scheduled)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _partialTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.partial)
      .fold(0.0, (sum, expense) => sum + expense.balance);

  double get _paidTotal => _filteredExpenses
      .where((expense) => expense.paymentStatus == ExpensePaymentStatus.paid)
      .fold(0.0, (sum, expense) => sum + expense.totalAmount);

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Gastos',
      body: Column(
        children: [
          _buildFiltersCard(context),
          const SizedBox(height: 16),
          _buildSummaryRow(context),
          const SizedBox(height: 16),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildFiltersCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SearchWidget(
                    controller: _searchController,
                    hintText: 'Buscar por número, proveedor o referencia...',
                    onSearchChanged: (_) => _applyFilters(),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _isLoading ? null : () => _loadData(refresh: true),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 8),
                AppButton(
                  text: 'Nuevo gasto',
                  icon: Icons.add_circle_outline,
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
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
                    _applyFilters();
                  },
                ),
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
                    _applyFilters();
                  },
                ),
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
                    _applyFilters();
                  },
                ),
                _buildDateSelector(context),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context) {
    final label = _dateRange == null
    ? 'Rango de fechas'
    : '${ChileanUtils.formatDate(_dateRange!.start)} - ${ChileanUtils.formatDate(_dateRange!.end)}';

    return SizedBox(
      width: 220,
      child: OutlinedButton.icon(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 1),
            initialDateRange: _dateRange,
          );
          setState(() {
            _dateRange = picked;
          });
          _applyFilters();
        },
        icon: const Icon(Icons.date_range_outlined),
        label: Text(label),
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _SummaryCard(
            title: 'Pendientes',
            amount: _pendingTotal,
            color: Colors.orange.shade600,
            icon: Icons.pending_actions_outlined,
          ),
          _SummaryCard(
            title: 'Programados',
            amount: _scheduledTotal,
            color: Colors.blueGrey.shade600,
            icon: Icons.schedule_outlined,
          ),
          _SummaryCard(
            title: 'Parciales',
            amount: _partialTotal,
            color: Colors.deepPurple.shade600,
            icon: Icons.toll_outlined,
          ),
          _SummaryCard(
            title: 'Pagados',
            amount: _paidTotal,
            color: Colors.green.shade600,
            icon: Icons.verified_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredExpenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isEmpty &&
                      _postingFilter == null &&
                      _paymentFilter == null &&
                      _selectedCategoryId == null &&
                      _dateRange == null
                  ? 'No hay gastos registrados.'
                  : 'No se encontraron gastos con los filtros seleccionados.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _filteredExpenses.length,
      itemBuilder: (context, index) {
        final expense = _filteredExpenses[index];
        return _ExpenseCard(
          expense: expense,
          currencyFormat: _currencyFormat,
          onView: () {
            if (expense.id == null) return;
            context
                .push<bool>('/accounting/expenses/${expense.id}')
                .then((changed) {
              if (changed == true) {
                _loadData(refresh: true);
              }
            });
          },
          onEdit: () {
            if (expense.id == null) return;
            context
                .push<bool>('/accounting/expenses/${expense.id}/edit')
                .then((updated) {
              if (updated == true) {
                _loadData(refresh: true);
              }
            });
          },
          onPost: expense.postingStatus == ExpensePostingStatus.posted
              ? null
              : () async {
                  await _expenseService.postExpense(expense.id!);
                  await _loadData(refresh: true);
                },
          onRevert: expense.postingStatus == ExpensePostingStatus.draft
              ? null
              : () async {
                  await _expenseService.revertExpenseToDraft(expense.id!);
                  await _loadData(refresh: true);
                },
          onDelete: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Eliminar gasto'),
                content: const Text('Esta acción es irreversible. ¿Deseas continuar?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await _expenseService.deleteExpense(expense.id!);
              await _loadData(refresh: true);
            }
          },
        );
      },
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String title;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final format = ChileanUtils.currencyFormat;

    return SizedBox(
      width: 240,
      child: Card(
        color: color.withOpacity(0.08),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Icon(icon),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      format.format(amount),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.currencyFormat,
    required this.onView,
    required this.onEdit,
    this.onPost,
    this.onRevert,
    required this.onDelete,
  });

  final Expense expense;
  final NumberFormat currencyFormat;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback? onPost;
  final VoidCallback? onRevert;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.expenseNumber,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expense.supplierName ?? 'Proveedor sin nombre',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (expense.reference != null && expense.reference!.isNotEmpty)
                        Text(
                          expense.reference!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormat.format(expense.totalAmount),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Emitido: ${ChileanUtils.formatDate(expense.issueDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (expense.dueDate != null)
                      Text(
                        'Vence: ${ChileanUtils.formatDate(expense.dueDate!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: _postingStatusLabel(expense.postingStatus),
                  color: _postingStatusColor(context, expense.postingStatus),
                  icon: Icons.inventory_outlined,
                ),
                _StatusChip(
                  label: _paymentStatusLabel(expense.paymentStatus),
                  color: _paymentStatusColor(context, expense.paymentStatus),
                  icon: Icons.payments_outlined,
                ),
                if (expense.balance > 0)
                  Chip(
                    avatar: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Saldo: ${currencyFormat.format(expense.balance)}'),
                  ),
                if (expense.categoryId != null)
                  Chip(
                    avatar: const Icon(Icons.label_outline),
                    label: Text(expense.category?.name ?? 'Categoría'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver detalle'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'post':
                        onPost?.call();
                        break;
                      case 'draft':
                        onRevert?.call();
                        break;
                      case 'delete':
                        onDelete.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'post',
                      enabled: onPost != null,
                      child: const ListTile(
                        leading: Icon(Icons.task_alt_outlined),
                        title: Text('Marcar como contabilizado'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'draft',
                      enabled: onRevert != null,
                      child: const ListTile(
                        leading: Icon(Icons.undo_outlined),
                        title: Text('Volver a borrador'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text(
                          'Eliminar',
                          style: TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _postingStatusLabel(ExpensePostingStatus status) {
    switch (status) {
      case ExpensePostingStatus.draft:
        return 'Borrador';
      case ExpensePostingStatus.posted:
        return 'Contabilizado';
      case ExpensePostingStatus.voided:
        return 'Anulado';
    }
  }

  static Color _postingStatusColor(BuildContext context, ExpensePostingStatus status) {
    switch (status) {
      case ExpensePostingStatus.draft:
        return Colors.orange.shade100;
      case ExpensePostingStatus.posted:
        return Colors.green.shade100;
      case ExpensePostingStatus.voided:
        return Colors.red.shade100;
    }
  }

  static String _paymentStatusLabel(ExpensePaymentStatus status) {
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

  static Color _paymentStatusColor(BuildContext context, ExpensePaymentStatus status) {
    switch (status) {
      case ExpensePaymentStatus.pending:
        return Colors.orange.shade50;
      case ExpensePaymentStatus.scheduled:
        return Colors.blueGrey.shade50;
      case ExpensePaymentStatus.partial:
        return Colors.deepPurple.shade50;
      case ExpensePaymentStatus.paid:
        return Colors.green.shade50;
      case ExpensePaymentStatus.voided:
        return Colors.red.shade50;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.black87),
      label: Text(label),
      backgroundColor: color,
    );
  }
}
